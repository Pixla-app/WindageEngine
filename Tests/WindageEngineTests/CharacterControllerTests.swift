//
//  CharacterControllerTests.swift
//  WindageEngineTests
//

import Testing
import simd
@testable import WindageEngine

/// A hillside that is rough everywhere: a long slope, plus bumps at two scales. Stands in for the
/// fractal terrain the walking half was tuned on — what matters is that there is always a bump.
private let hillside: @Sendable (Float, Float) -> Float = { x, z in
    -z * 0.18 + 0.35 * sin(x * 0.9) * cos(z * 1.3) + 0.08 * sin(x * 5.1 + z * 4.3)
}

private let step: Float = 1.0 / 120
private let flat = CharacterController.Surroundings()

private func run(_ controller: inout CharacterController,
                 seconds: Float,
                 yaw: Float = 0,
                 _ input: MovementInput = MovementInput(),
                 jump: Bool = false,
                 crouching: Bool = false,
                 in world: CharacterController.Surroundings = flat) {
    for _ in 0..<Int((seconds / step).rounded()) {
        controller.step(yaw: yaw, input: input, jump: jump, crouching: crouching,
                        deltaTime: step, in: world)
    }
}

private func ground(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

/// A box standing on the ground at the origin's z, `height` tall, starting `ahead` metres in front.
private func ledge(height: Float, ahead: Float = 2, depth: Float = 4) -> BoundingBox {
    BoundingBox(minimum: SIMD3(-3, 0, -ahead - depth), maximum: SIMD3(3, height, -ahead))
}

// MARK: - Walking, carried over

@Suite("Character controller — walking")
struct CharacterWalkingTests {

    private var forwards: MovementInput { MovementInput(forward: 1) }

    /// **The bug the free-flying camera had.** Walking along the look direction means aiming at your
    /// feet walks you into the hill at `cos θ`. The controller never sees pitch; this pins it.
    @Test("The walk speed is the walk speed, on the level")
    func walkSpeedIsExact() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, forwards)
        let crossed = simd_distance(ground(c.feet), .zero)
        let expected = Float(Int((2 / step).rounded())) * step * c.tuning.walkSpeed
        #expect(abs(crossed - expected) < 0.01, "crossed \(crossed) m rather than \(expected)")
    }

    /// Horizontal speed is the same downhill, uphill and across. A shooter that drags on an incline
    /// feels broken.
    @Test("The slope does not change how fast the ground goes by")
    func slopeDoesNotChangeGroundSpeed() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        for (name, yaw) in [("uphill", Float(0)), ("downhill", Float.pi), ("across", Float.pi / 2)] {
            var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
            run(&c, seconds: 1.5, yaw: yaw, forwards, in: world)
            let crossed = simd_distance(ground(c.feet), .zero)
            let expected = Float(Int((1.5 / step).rounded())) * step * c.tuning.walkSpeed
            #expect(abs(crossed - expected) < 0.01, "\(name): crossed \(crossed) m against \(expected)")
        }
    }

    @Test("The feet stay on the terrain, and the eye stays near its height above it")
    func followsTheGround() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
        var worst: Float = 0
        for _ in 0..<(120 * 10) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            #expect(abs(c.feet.y - hillside(c.feet.x, c.feet.z)) < 1e-4)
            worst = max(worst, abs(c.eye.y - hillside(c.feet.x, c.feet.z) - c.tuning.eyeHeight))
        }
        #expect(c.isGrounded)
        #expect(worst < 0.35, "the eye drifted \(worst) m from its standing height")
    }

    /// **Settling, not snapping.** There is always a bump; tracking it exactly at 120 Hz reads as a
    /// jitter.
    @Test("The eye is steadier than the ground")
    func eyeIsSteadierThanTheGround() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
        var eyeJerk: Float = 0, groundJerk: Float = 0
        var previousEye = c.eye.y, previousGround = c.feet.y
        for _ in 0..<(120 * 4) {
            c.step(yaw: .pi / 2, input: forwards, deltaTime: step, in: world)
            eyeJerk = max(eyeJerk, abs(c.eye.y - previousEye))
            groundJerk = max(groundJerk, abs(c.feet.y - previousGround))
            previousEye = c.eye.y
            previousGround = c.feet.y
        }
        #expect(eyeJerk < groundJerk, "the eye moved \(eyeJerk) m a step against the ground's \(groundJerk)")
    }

    @Test("Walking diagonally is not faster")
    func diagonalIsNotFaster() {
        var straight = CharacterController(feet: .zero)
        var angled = CharacterController(feet: .zero)
        run(&straight, seconds: 1, forwards)
        run(&angled, seconds: 1, MovementInput(forward: 1, strafe: 1))
        #expect(abs(simd_length(ground(straight.feet)) - simd_length(ground(angled.feet))) < 0.05)
    }

    @Test("No input means no movement")
    func standingStillIsStill() {
        var c = CharacterController(feet: SIMD3(2, 0, 3))
        run(&c, seconds: 3)
        #expect(c.feet == SIMD3(2, 0, 3))
        #expect(c.isGrounded)
    }
}

// MARK: - Crouch and slide, carried over

@Suite("Character controller — crouch and slide")
struct CharacterPostureTests {

    private var running: MovementInput { MovementInput(forward: 1, sprint: true) }

    @Test("Crouching lowers the eye and standing raises it again")
    func postureChanges() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, crouching: true)
        #expect(abs(c.eye.y - c.tuning.crouchedEyeHeight) < 0.02)
        run(&c, seconds: 2)
        #expect(abs(c.eye.y - c.tuning.eyeHeight) < 0.02)
    }

    @Test("The posture moves at a rate, not instantly")
    func postureIsNotATeleport() {
        var c = CharacterController(feet: .zero)
        let before = c.eye.y
        c.step(yaw: 0, input: MovementInput(), crouching: true, deltaTime: step, in: flat)
        let moved = before - c.eye.y
        #expect(moved > 0)
        #expect(moved < c.tuning.postureRate * step * 1.5)
    }

    /// **The cost. Without it the posture is free and you would simply hold it.**
    @Test("Crouched you move much slower, and cannot sprint")
    func crouchingCostsSpeed() {
        var standing = CharacterController(feet: .zero)
        var crouched = CharacterController(feet: .zero)
        var sprintCrouched = CharacterController(feet: .zero)
        run(&standing, seconds: 2, MovementInput(forward: 1))
        run(&crouched, seconds: 2, MovementInput(forward: 1), crouching: true)
        run(&sprintCrouched, seconds: 2, running, crouching: true)
        let a = simd_length(ground(standing.feet)), b = simd_length(ground(crouched.feet))
        #expect(b < a * 0.6)
        #expect(abs(simd_length(ground(sprintCrouched.feet)) - b) < 0.01, "sprint worked from a crouch")
    }

    /// Sprints, then crouches, and reports how far the slide carried and how long it lasted.
    private func slide(steering input: MovementInput? = nil)
        -> (distance: Float, seconds: Float, controller: CharacterController, start: SIMD2<Float>) {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, running)
        let start = ground(c.feet)
        var seconds: Float = 0
        // `repeat`: the slide only exists after the first crouching step.
        repeat {
            c.step(yaw: 0, input: input ?? running, crouching: true, deltaTime: step, in: flat)
            seconds += step
        } while c.isSliding && seconds < 5
        return (simd_distance(ground(c.feet), start), seconds, c, start)
    }

    @Test("Crouching while sprinting slides instead of stopping")
    func itSlides() {
        let result = slide()
        let crouchWalk = CharacterController.Tuning().walkSpeed
            * CharacterController.Tuning().crouchedSpeedFraction * result.seconds
        #expect(result.distance > crouchWalk * 2, "no momentum: \(result.distance) m")
        #expect(abs(result.seconds - CharacterController.Tuning().slideSeconds) < 0.05)
        // Momentum, not a way to travel.
        #expect(result.distance < 18, "a \(result.distance) m slide is a way of getting places")
    }

    @Test("Holding crouch does not restart the slide")
    func slideDoesNotChain() {
        var c = slide().controller
        for _ in 0..<600 {
            c.step(yaw: 0, input: running, crouching: true, deltaTime: step, in: flat)
            #expect(!c.isSliding)
        }
    }

    @Test("You cannot slide from a standstill or a walk")
    func slideNeedsSprintSpeed() {
        var still = CharacterController(feet: .zero)
        still.step(yaw: 0, input: MovementInput(), crouching: true, deltaTime: step, in: flat)
        #expect(!still.isSliding)

        var walking = CharacterController(feet: .zero)
        run(&walking, seconds: 1, MovementInput(forward: 1))
        walking.step(yaw: 0, input: MovementInput(forward: 1), crouching: true, deltaTime: step, in: flat)
        #expect(!walking.isSliding)
    }

    /// **Committed.** Entered running down −Z with a hard left demanded throughout.
    @Test("A slide goes where it was entered, not where the stick says")
    func slideIsCommitted() {
        let result = slide(steering: MovementInput(strafe: -1, sprint: true))
        let travel = ground(result.controller.feet) - result.start
        #expect(travel.y < -8, "it barely carried forward: \(travel)")
        #expect(abs(travel.x) < abs(travel.y) * 0.4, "that is steering, not sliding: \(travel)")
        #expect(abs(travel.x) > 0.3, "no influence at all — a rail: \(travel)")
    }

    @Test("The slide's camera dip peaks early and recovers")
    func dipRecovers() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, running)
        #expect(c.slideCameraDip == 0)
        var samples: [Float] = []
        repeat {
            c.step(yaw: 0, input: running, crouching: true, deltaTime: step, in: flat)
            samples.append(c.slideCameraDip)
        } while c.isSliding
        let peak = samples.min() ?? 0
        #expect(peak < -0.05)
        #expect(c.slideCameraDip == 0)
        #expect((samples.firstIndex(of: peak) ?? samples.count) < samples.count / 3)
    }
}

// MARK: - Standing on things: new

@Suite("Character controller — standing on things")
struct CharacterFootingTests {

    private var forwards: MovementInput { MovementInput(forward: 1) }

    /// **Stairs.** Below the step height, a ledge is walked up without a jump, and the feet end up
    /// exactly on its top.
    @Test("A ledge below the step height is walked onto")
    func stepsUpALowLedge() {
        let world = CharacterController.Surroundings(solids: [ledge(height: 0.3)])
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, forwards, in: world)
        #expect(c.feet.z < -2.5, "it did not get onto the ledge: \(c.feet)")
        #expect(abs(c.feet.y - 0.3) < 1e-4)
        #expect(c.isGrounded)
    }

    /// **A crate is cover.** Taller than a step, it stops you, and you stay on the ground in front of
    /// it rather than climbing it or sinking into it.
    @Test("A crate taller than the step height stops you")
    func crateStops() {
        let crate = ledge(height: 1.5)
        let world = CharacterController.Surroundings(solids: [crate])
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, forwards, in: world)
        #expect(c.feet.y == 0)
        #expect(c.feet.z >= crate.maximum.z + c.tuning.radius - 1e-3,
                "walked into the crate: feet at \(c.feet.z), face at \(crate.maximum.z)")
        #expect(c.feet.z < crate.maximum.z + c.tuning.radius + 0.05,
                "stopped short of the crate: \(c.feet.z)")
    }

    /// **Met, not stopped short of.** Refusing a blocked step outright leaves the player wherever
    /// the last whole step ended — found in the sample as a 4 cm gap at a walk and 15 cm at a sprint.
    @Test("Running into a wall ends touching it, at a walk or a sprint")
    func wallIsMet() {
        let crate = ledge(height: 1.5)
        let world = CharacterController.Surroundings(solids: [crate])
        for input in [MovementInput(forward: 1), MovementInput(forward: 1, sprint: true)] {
            var c = CharacterController(feet: .zero)
            run(&c, seconds: 1, input, in: world)
            let gap = c.feet.z - (crate.maximum.z + c.tuning.radius)
            #expect(gap >= 0 && gap < 0.01, "\(input.sprint ? "sprinting" : "walking"): \(gap) m short")
        }
    }

    /// **Walking into a wall at an angle slides along it.** Refusing the whole move is what makes a
    /// wall feel like glue — and is also the only way out of a corner.
    @Test("A wall hit at an angle is slid along, not stuck to")
    func slidesAlongWalls() {
        let wall = BoundingBox(minimum: SIMD3(-50, 0, -2), maximum: SIMD3(50, 3, -1))
        let world = CharacterController.Surroundings(solids: [wall])
        var c = CharacterController(feet: .zero)
        // Forward and right at once, into a wall that runs left–right.
        run(&c, seconds: 2, MovementInput(forward: 1, strafe: 1), in: world)
        #expect(c.feet.x > 5, "it stuck to the wall: \(c.feet)")
        #expect(c.feet.z > -1 + c.tuning.radius - 1e-3)
    }

    /// **Walking off an edge falls**, and lands on whatever is below.
    @Test("Walking off something taller than a step falls, and lands")
    func fallsOffAnEdge() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 1.2, 3))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 1.2, 0))
        var wasAirborne = false
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            if !c.isGrounded { wasAirborne = true }
        }
        #expect(wasAirborne, "it walked off a 1.2 m drop without leaving the ground")
        #expect(c.isGrounded)
        #expect(c.feet.y == 0)
        #expect(c.feet.z < -3)
    }

    /// Down a step is not a fall: the feet follow it, and the eye eases after them.
    @Test("Stepping down a low ledge stays grounded")
    func stepsDown() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 0.3, 3))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 0.3, 0))
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            #expect(c.isGrounded, "a 30 cm step down became a fall at \(c.feet)")
        }
        #expect(c.feet.y == 0)
    }

    /// **The feet move at once; the eye follows.** Stairs that snapped the eye would stutter.
    @Test("Stepping up moves the feet at once and the eye over a moment")
    func eyeEasesUpAStep() {
        let world = CharacterController.Surroundings(solids: [ledge(height: 0.4, ahead: 0.5)])
        var c = CharacterController(feet: .zero)
        var eyeRise: [Float] = []
        var previous = c.eye.y
        for _ in 0..<60 {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            eyeRise.append(c.eye.y - previous)
            previous = c.eye.y
        }
        #expect(abs(c.feet.y - 0.4) < 1e-4)
        #expect((eyeRise.max() ?? 0) < 0.2, "the eye jumped \(eyeRise.max() ?? 0) m in one step")
    }

    @Test("A jump clears a low wall but not a crate")
    func jumpHeight() {
        var c = CharacterController(feet: .zero)
        var apex: Float = 0
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
            apex = max(apex, c.feet.y)
        }
        #expect(apex > 0.9 && apex < 1.2, "a jump reached \(apex) m")
        #expect(c.isGrounded)
    }

    /// **Holding jump is one jump.** Without the edge, holding the key bounces for ever.
    @Test("Holding jump does not bounce")
    func holdingJumpIsOneJump() {
        var c = CharacterController(feet: .zero)
        var takeoffs = 0
        var wasGrounded = true
        for _ in 0..<(120 * 3) {
            c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
            if wasGrounded && !c.isGrounded { takeoffs += 1 }
            wasGrounded = c.isGrounded
        }
        #expect(takeoffs == 1)
    }

    /// **Coyote time.** A jump pressed just after running off an edge still counts.
    @Test("A jump just after leaving an edge still jumps")
    func coyoteTime() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 1.2, 0))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 1.2, -1))
        // Walk off the +z edge (yaw π faces +z) until airborne, then press jump two steps later.
        while c.isGrounded { c.step(yaw: .pi, input: forwards, deltaTime: step, in: world) }
        c.step(yaw: .pi, input: forwards, deltaTime: step, in: world)
        let before = c.verticalVelocity
        c.step(yaw: .pi, input: forwards, jump: true, deltaTime: step, in: world)
        #expect(c.verticalVelocity > before + 3, "the late jump was eaten: \(c.verticalVelocity)")
    }

    /// **Jump buffering.** Pressed a moment before landing, it jumps on landing.
    @Test("A jump pressed just before landing jumps on landing")
    func jumpBuffer() {
        var c = CharacterController(feet: SIMD3(0, 0.6, 0))
        c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)   // falling
        while c.feet.y > 0.08 { c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat) }
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)  // pressed in the air
        var rose = false
        for _ in 0..<12 {
            c.step(yaw: 0, input: MovementInput(), jump: false, deltaTime: step, in: flat)
            if c.verticalVelocity > 3 { rose = true }
        }
        #expect(rose, "a jump pressed just before landing was lost")
    }

    @Test("No jump out of a slide")
    func noJumpFromSlide() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, MovementInput(forward: 1, sprint: true))
        c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), crouching: true,
               deltaTime: step, in: flat)
        #expect(c.isSliding)
        c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), jump: true, crouching: true,
               deltaTime: step, in: flat)
        #expect(c.isGrounded)
    }

    /// A head against the underside of something stops the rise, rather than passing through.
    @Test("A jump under a low ceiling stops at the ceiling")
    func ceilingStopsAJump() {
        let ceiling = BoundingBox(minimum: SIMD3(-3, 2.2, -3), maximum: SIMD3(3, 2.5, 3))
        let world = CharacterController.Surroundings(solids: [ceiling])
        var c = CharacterController(feet: .zero)
        var highestHead: Float = 0
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: world)
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world)
            highestHead = max(highestHead, c.bounds.maximum.y)
        }
        #expect(highestHead <= 2.2 + 1e-3, "the head reached \(highestHead) m into a ceiling at 2.2")
        #expect(c.isGrounded)
    }

    /// **A fast fall cannot skip a thin floor.** Landing is measured from where the feet were.
    @Test("A long fall lands on a thin platform rather than passing through it")
    func fastFallLands() {
        let slab = BoundingBox(minimum: SIMD3(-3, 4.95, -3), maximum: SIMD3(3, 5, 3))
        let world = CharacterController.Surroundings(solids: [slab])
        var c = CharacterController(feet: SIMD3(0, 60, 0))
        run(&c, seconds: 4, in: world)
        #expect(abs(c.feet.y - 5) < 1e-4, "fell to \(c.feet.y)")
        #expect(c.isGrounded)
    }

    /// Standing on a crate and walking across it is not walking into it.
    @Test("Walking across the top of a solid is not blocked by it")
    func walksAcrossATop() {
        let top = BoundingBox(minimum: SIMD3(-5, 0, -20), maximum: SIMD3(5, 1.5, 5))
        let world = CharacterController.Surroundings(solids: [top])
        var c = CharacterController(feet: SIMD3(0, 1.5, 0))
        run(&c, seconds: 2, forwards, in: world)
        #expect(c.feet.z < -10)
        #expect(abs(c.feet.y - 1.5) < 1e-4)
    }
}
