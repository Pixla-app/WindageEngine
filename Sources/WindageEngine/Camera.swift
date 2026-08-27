//
//  Camera.swift
//  WindageEngine
//

import simd

/// What the player is asking the camera to do this step.
///
/// Axes rather than key names: the camera should not know what a keyboard is, so a gamepad stick or
/// a replay file can drive it later without touching this file.
public nonisolated struct MovementInput: Equatable, Sendable {
    /// +1 forward, -1 back.
    public var forward: Float = 0
    /// +1 right, -1 left.
    public var strafe: Float = 0
    /// +1 up, -1 down, along **world** up rather than the camera's.
    public var vertical: Float = 0
    public var sprint: Bool = false

    /// **Spelled out rather than synthesised.** A memberwise initialiser stays `internal`, so a
    /// consumer outside this module can read a `MovementInput` and never construct one — an access
    /// error that reads like a missing declaration.
    public init(forward: Float = 0, strafe: Float = 0, vertical: Float = 0, sprint: Bool = false) {
        self.forward = forward
        self.strafe = strafe
        self.vertical = vertical
        self.sprint = sprint
    }

    public static let still = MovementInput()
}

/// A first-person camera, in metres.
///
/// **Free-flying for now.** There is no player rig, no gravity and no collision — this exists so
/// there is something to look at the world with while the renderer is built. When a player
/// character arrives, the horizontal-movement rule changes (walking moves along the ground plane,
/// not along the look direction) and this becomes the eye attached to that character.
///
/// Orientation is yaw and pitch, with no roll. Quaternions would buy nothing here: pitch is clamped
/// short of vertical, so the degenerate case they exist to avoid is unreachable, and Euler angles
/// are far easier to read in a debugger and to clamp meaningfully.
public nonisolated struct Camera: Sendable {

    /// Metres. Y is up.
    public var position: SIMD3<Float>

    /// Radians. 0 looks down -Z; positive turns left.
    public var yaw: Float

    /// Radians. Positive looks up. Always within ``pitchLimit``.
    public var pitch: Float

    /// Just short of straight up or down.
    ///
    /// At exactly ±90° the look direction becomes parallel to world up and the right vector is
    /// undefined, so the view matrix degenerates and the image snaps. Every first-person game stops
    /// slightly short for this reason.
    public static let pitchLimit: Float = 89 * .pi / 180

    /// Metres per second.
    public static let walkSpeed: Float = 6
    public static let sprintSpeed: Float = 18

    /// Radians of rotation per unit of mouse movement.
    public static let lookSensitivity: Float = 0.0022

    /// Radians per second at full stick deflection.
    public static let stickLookSpeed: Float = 3.2

    public init(position: SIMD3<Float> = .zero, yaw: Float = 0, pitch: Float = 0) {
        self.position = position
        self.yaw = Camera.wrapAngle(yaw)
        self.pitch = min(max(pitch, -Camera.pitchLimit), Camera.pitchLimit)
    }

    // MARK: - Basis

    public var forward: SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    /// Horizontal only, so strafing never drifts up or down when looking at the sky.
    public var right: SIMD3<Float> {
        SIMD3(cos(yaw), 0, -sin(yaw))
    }

    public var up: SIMD3<Float> {
        simd_cross(right, forward)
    }

    /// World space to view space. Right-handed: the camera looks down **-Z**, so anything in front
    /// of it has a negative view-space Z.
    public var viewMatrix: matrix_float4x4 {
        let f = forward, r = right, u = up
        return matrix_float4x4(columns: (
            SIMD4<Float>(r.x, u.x, -f.x, 0),
            SIMD4<Float>(r.y, u.y, -f.y, 0),
            SIMD4<Float>(r.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(r, position), -simd_dot(u, position), simd_dot(f, position), 1)
        ))
    }

    // MARK: - Input

    /// Applies mouse movement.
    ///
    /// **Not scaled by delta time.** A mouse delta is a displacement the player already made, not a
    /// rate: scaling it by frame duration would make the same physical hand movement turn further
    /// on a slow frame, which is the classic way to make aiming feel unpredictable. Movement below
    /// *is* a rate and is scaled.
    public mutating func look(mouseDelta: SIMD2<Float>) {
        yaw = Camera.wrapAngle(yaw - mouseDelta.x * Camera.lookSensitivity)
        pitch = min(max(pitch - mouseDelta.y * Camera.lookSensitivity, -Camera.pitchLimit), Camera.pitchLimit)
    }

    /// Applies stick look.
    ///
    /// **Deliberately separate from ``look(mouseDelta:)``, because the two are different kinds of
    /// quantity and mixing them up ruins the feel of one or the other.** A mouse reports a
    /// displacement that already happened, so it must *not* be scaled by time. A stick reports a
    /// held position, which is a rate — hold it for twice as long and you should turn twice as far
    /// — so it *must* be. Feeding a stick through the mouse path makes turning depend on frame
    /// rate; feeding a mouse through the stick path makes fast flicks turn less than slow ones.
    public mutating func turn(rate: SIMD2<Float>, deltaTime: Float) {
        guard rate != .zero else { return }
        yaw = Camera.wrapAngle(yaw - rate.x * Camera.stickLookSpeed * deltaTime)
        let newPitch = pitch + rate.y * Camera.stickLookSpeed * deltaTime
        pitch = min(max(newPitch, -Camera.pitchLimit), Camera.pitchLimit)
    }

    /// Advances position by one simulation step.
    public mutating func advance(_ input: MovementInput, deltaTime: Float) {
        var direction = forward * input.forward + right * input.strafe + SIMD3<Float>(0, 1, 0) * input.vertical
        let lengthSquared = simd_length_squared(direction)
        guard lengthSquared > 0 else { return }

        // Normalise so that holding two directions at once is not faster than one.
        direction /= lengthSquared.squareRoot()

        let speed = input.sprint ? Camera.sprintSpeed : Camera.walkSpeed
        position += direction * speed * deltaTime
    }

    // MARK: - Interpolation

    /// Blends between two simulation steps for display, so motion stays smooth when the display
    /// runs at a different rate from the simulation.
    public static func interpolated(from start: Camera, to end: Camera, alpha: Float) -> Camera {
        var result = start
        result.position = simd_mix(start.position, end.position, SIMD3(repeating: alpha))
        result.yaw = wrapAngle(start.yaw + shortestAngle(from: start.yaw, to: end.yaw) * alpha)
        result.pitch = start.pitch + (end.pitch - start.pitch) * alpha
        return result
    }

    /// Wraps to `(-π, π]`.
    ///
    /// Yaw is kept wrapped rather than left to grow: a session spinning steadily for an hour would
    /// otherwise reach tens of thousands of radians, where a 32-bit float can no longer resolve a
    /// tenth of a degree and aim gets visibly coarse.
    public static func wrapAngle(_ angle: Float) -> Float {
        var wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped > .pi { wrapped -= 2 * .pi }
        if wrapped <= -.pi { wrapped += 2 * .pi }
        return wrapped
    }

    /// Signed shortest rotation between two wrapped angles.
    ///
    /// Without this, interpolating across the ±π seam spins the long way round: turning from 179°
    /// to -179° is 2° of movement, but a naive blend travels 358° of it in one frame.
    public static func shortestAngle(from start: Float, to end: Float) -> Float {
        wrapAngle(end - start)
    }
}
