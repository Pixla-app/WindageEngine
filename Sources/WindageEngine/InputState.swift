//
//  InputState.swift
//  WindageEngine
//

import AppKit
import GameController
import simd

/// Collects keyboard, mouse and gamepad into something the simulation can read.
///
/// Everything downstream reads **axes and intents** — ``movement``, ``consumePendingLook()``,
/// ``lookRate`` — never key codes or button names. That is what lets a keyboard, a DualSense and
/// (later) a rebinding layer or a recorded replay all drive the same camera without any of them
/// knowing about the others.
public final class InputState {

    /// macOS virtual key codes. These are physical positions, not letters — the codes below are the
    /// QWERTY WASD cluster and stay in the same place on an AZERTY keyboard, which is what a game
    /// wants.
    private enum Key {
        static let w: UInt16 = 13, a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2
        static let space: UInt16 = 49, c: UInt16 = 8, escape: UInt16 = 53
        static let up: UInt16 = 126, down: UInt16 = 125, left: UInt16 = 123, right: UInt16 = 124
    }

    private var pressedKeys: Set<UInt16> = []
    private var sprintingFromKeyboard = false

    /// Stick-click sprint latches on and stays on. See ``SprintLatch``.
    private var sprintLatch = SprintLatch()

    /// Mouse movement seen since the simulation last took it.
    private var pendingLook: SIMD2<Float> = .zero

    /// While captured the cursor is hidden and detached, and the mouse turns the camera.
    public private(set) var isMouseCaptured = false

    private var rightMouseHeld = false
    private var leftMouseHeld = false

    /// Discrete steps requested since the simulation last took them — arrow keys and the d-pad.
    ///
    /// Deliberately generic. A scope turret is the first thing needing "one notch at a time", but so
    /// does a menu, and the engine has no business knowing which.
    private var pendingSteps = SIMD2<Int>(0, 0)
    private var dpadHorizontalWasPressed = false
    private var dpadVerticalWasPressed = false

    private var connectionObservers: [NSObjectProtocol] = []

    public init() {
        observeControllers()
    }

    /// Stops observing controller connections.
    ///
    /// Not `deinit`: that is nonisolated and may run on any thread, while this state belongs to the
    /// main actor — which Swift 6 refuses to compile, and is right to.
    public func shutdown() {
        connectionObservers.forEach(NotificationCenter.default.removeObserver)
        connectionObservers.removeAll()
        GCController.stopWirelessControllerDiscovery()
    }

    // MARK: - Gamepad

    /// The active pad, if any. `GCController.current` follows whichever pad was last used, which is
    /// the right behaviour when someone puts a controller down and picks up the mouse.
    private var gamepad: GCExtendedGamepad? {
        GCController.current?.extendedGamepad
    }

    public var isGamepadConnected: Bool { gamepad != nil }

    private func observeControllers() {
        let centre = NotificationCenter.default
        connectionObservers = [
            centre.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
                let name = (note.object as? GCController)?.vendorName ?? "Controller"
                NSLog("Coldkeel: \(name) connected")
            },
            centre.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { note in
                let name = (note.object as? GCController)?.vendorName ?? "Controller"
                NSLog("Coldkeel: \(name) disconnected")
            }
        ]
        // Pads paired before launch are already present; this picks up ones woken afterwards.
        GCController.startWirelessControllerDiscovery()
    }

    // MARK: - Events in

    public func keyDown(_ keyCode: UInt16) {
        // **Only a fresh press toggles.** macOS repeats a held key, so without the already-down
        // check, resting a finger on `C` would strobe the crouch at the repeat rate.
        let wasDown = pressedKeys.contains(keyCode)
        pressedKeys.insert(keyCode)
        if keyCode == Key.c && !wasDown { toggleCrouch() }

        // Arrows step once per press — and again on key repeat, which is what makes holding one
        // down run a turret up rather than requiring forty presses.
        switch keyCode {
        case Key.up: pendingSteps.y += 1
        case Key.down: pendingSteps.y -= 1
        case Key.right: pendingSteps.x += 1
        case Key.left: pendingSteps.x -= 1
        default: break
        }
    }
    public func keyUp(_ keyCode: UInt16) { pressedKeys.remove(keyCode) }

    /// Toggles the crouch. Called on the key *down* edge, so holding `C` does not strobe it.
    public func toggleCrouch() {
        isCrouching.toggle()
    }
    public func setSprinting(_ sprinting: Bool) {
        sprintingFromKeyboard = sprinting
        standIfSprinting()
    }
    public func setRightMouse(_ held: Bool) { rightMouseHeld = held }
    public func setLeftMouse(_ held: Bool) { leftMouseHeld = held }

    /// Firing: left mouse while the pointer is captured, or the right trigger past halfway.
    public var isFiring: Bool {
        if leftMouseHeld && isMouseCaptured { return true }
        return (gamepad?.rightTrigger.value ?? 0) > 0.5
    }

    /// Steadying: Shift, or **L3 held while aiming**.
    ///
    /// **The stick click does double duty, dispatched by whether the optic is up.** Sprinting and
    /// steadying are mutually exclusive — you sprint at the hip and steady through the scope — so
    /// one button can serve both, which is what console shooters do and what players expect. It also
    /// keeps the left trigger free, since aiming is already held there and clamping a shoulder
    /// button at the same time is a hand contortion.
    ///
    /// Held rather than latched here, where sprint is latched: holding L3 is awkward *while
    /// steering*, and a player taking a precision shot is standing still.
    public var isSteadying: Bool {
        sprintingFromKeyboard || steadyingFromPad
    }

    private var steadyingFromPad = false
    private var crouchButtonWasPressed = false

    /// Crouch: **C** on the keyboard, Circle on a pad. **Latched — press to crouch, press to stand.**
    ///
    /// **Held was wrong, and this codebase already said so.** The rule it follows is the one written
    /// for sprint: latch what stays on *while your hands are busy with something else*, hold what is
    /// a moment. Steadying is held because a player taking a precision shot is standing still for a
    /// second. Crouching is not that — you crouch and then walk, aim, steady and dial turrets, so
    /// holding `C` means clamping it against W/A/S/D, right mouse, Shift and the arrow keys at once.
    ///
    /// **The worry that made it held does not survive contact with the cost.** A latched posture
    /// that is only steadier would indeed get switched on once and never off — but crouching costs
    /// 55% of your speed and the whole sprint, so what stops it being the default is the trade, not
    /// the button. See `Footing.crouchedEyeHeight`.
    ///
    /// The same keys previously drove `MovementInput.vertical` for the free-flying camera. That axis
    /// is still there for a title that flies; nothing in a game with feet reads it.
    public private(set) var isCrouching = false

    /// **Asking to sprint stands you up**, rather than doing nothing.
    ///
    /// You cannot sprint crouched — that is the cost — so a sprint press while crouched is either
    /// ignored or obeyed. Ignoring it leaves the player pressing a key that does nothing and
    /// concluding the game is stuck; standing up is what they meant, because "go fast" is not an
    /// ambiguous intent.
    private func standIfSprinting() {
        if sprintingFromKeyboard || sprintLatch.isEngaged { isCrouching = false }
    }

    /// Takes the accumulated discrete steps and clears them.
    public func consumeSteps() -> SIMD2<Int> {
        defer { pendingSteps = SIMD2(0, 0) }
        return pendingSteps
    }

    /// Aiming down sights: right mouse, or the left trigger past halfway.
    ///
    /// A *threshold* on the trigger rather than its analogue value, because aiming is a state and
    /// not a degree — half-scoped is not a thing. The analogue value stays available for anything
    /// that genuinely wants it.
    public var isAiming: Bool {
        if rightMouseHeld { return true }
        return (gamepad?.leftTrigger.value ?? 0) > 0.5
    }

    public func addMouseDelta(x: Float, y: Float) {
        guard isMouseCaptured else { return }
        pendingLook += SIMD2(x, y)
    }

    public static func isEscape(_ keyCode: UInt16) -> Bool { keyCode == Key.escape }

    // MARK: - Capture

    public func setMouseCaptured(_ captured: Bool) {
        guard captured != isMouseCaptured else { return }
        isMouseCaptured = captured

        if captured {
            NSCursor.hide()
            // Detach the pointer from the cursor so it can keep generating deltas at the edge of
            // the screen instead of stopping dead against it.
            CGAssociateMouseAndMouseCursorPosition(0)
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            pendingLook = .zero
        }
    }

    /// Edge-detects gamepad buttons and expires the sprint latch. Call once per frame, before the
    /// simulation steps.
    ///
    /// **Sprint from the stick click is a toggle, not a hold, and that is deliberate.** L3 is under
    /// the same thumb that steers: holding it clamped while pushing the stick around is awkward and
    /// tiring, which is why console shooters almost universally latch it. Shift on the keyboard
    /// stays hold, because a little finger resting on it costs nothing.
    ///
    /// The latch expires when the player stops moving forward — otherwise it silently persists
    /// through a stop, and the next tap of the stick reads as sprinting when the player meant to
    /// walk.
    public func pollFrame() {
        // Circle toggles the crouch on its press edge, like `C` does. Level-triggering it would
        // strobe the posture for as long as the button is down.
        let crouchButton = gamepad?.buttonB.isPressed ?? false
        if crouchButton && !crouchButtonWasPressed { toggleCrouch() }
        crouchButtonWasPressed = crouchButton

        // The d-pad steps on the press edge, like the arrow keys — level-triggering it would run a
        // turret to its stop in a third of a second.
        if let pad = gamepad?.dpad {
            let horizontal = pad.right.isPressed || pad.left.isPressed
            let vertical = pad.up.isPressed || pad.down.isPressed
            if horizontal && !dpadHorizontalWasPressed { pendingSteps.x += pad.right.isPressed ? 1 : -1 }
            if vertical && !dpadVerticalWasPressed { pendingSteps.y += pad.up.isPressed ? 1 : -1 }
            dpadHorizontalWasPressed = horizontal
            dpadVerticalWasPressed = vertical
        } else {
            dpadHorizontalWasPressed = false
            dpadVerticalWasPressed = false
        }

        // One button, two jobs. Through the optic the stick click steadies the shot; at the hip it
        // latches a sprint. Feeding the latch while aiming would toggle a sprint the player cannot
        // use and would find waiting for them when they lowered the scope.
        let stickClick = gamepad?.leftThumbstickButton?.isPressed ?? false
        let aiming = isAiming
        steadyingFromPad = aiming && stickClick

        if aiming {
            sprintLatch.disengage()
        } else {
            sprintLatch.update(buttonPressed: stickClick, forwardInput: movement.forward)
            standIfSprinting()
        }
    }

    /// Drops every held key and releases the pointer.
    ///
    /// Call this the moment the game window stops being focused. Without it, a key held as focus
    /// leaves stays held forever — no `keyUp` is ever delivered — and the camera slides away on its
    /// own while the player is in another app.
    public func releaseAll() {
        setMouseCaptured(false)
        pressedKeys.removeAll()
        sprintingFromKeyboard = false
        rightMouseHeld = false
        leftMouseHeld = false
        pendingSteps = SIMD2(0, 0)
        dpadHorizontalWasPressed = false
        dpadVerticalWasPressed = false
        sprintLatch.disengage()
        steadyingFromPad = false
        pendingLook = .zero
    }

    // MARK: - Simulation reads

    /// Movement intent, from keyboard and left stick together.
    public var movement: MovementInput {
        var input = MovementInput()

        if pressedKeys.contains(Key.w) { input.forward += 1 }
        if pressedKeys.contains(Key.s) { input.forward -= 1 }
        if pressedKeys.contains(Key.d) { input.strafe += 1 }
        if pressedKeys.contains(Key.a) { input.strafe -= 1 }
        if pressedKeys.contains(Key.space) { input.vertical += 1 }
        if pressedKeys.contains(Key.c) { input.vertical -= 1 }
        input.sprint = sprintingFromKeyboard

        if let gamepad {
            let stick = StickResponse.shaped(
                SIMD2(gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value),
                deadzone: StickResponse.moveDeadzone, exponent: StickResponse.moveExponent)
            input.strafe += stick.x
            input.forward += stick.y

            // Cross rises. Circle used to drop, matching C — it toggles the crouch now, and a
            // button cannot mean both "go down one metre per second" and "change posture".
            if gamepad.buttonA.isPressed { input.vertical += 1 }
        }

        // Never sprinting through the optic — the states are exclusive by design.
        if sprintLatch.isEngaged && !isAiming {
            input.sprint = true
        }
        // And never while crouched: that is what the posture costs. See `isCrouching`.
        if isCrouching { input.sprint = false }

        // Keyboard and stick can both contribute; clamp so holding both is not faster than either.
        input.forward = min(max(input.forward, -1), 1)
        input.strafe = min(max(input.strafe, -1), 1)
        input.vertical = min(max(input.vertical, -1), 1)
        return input
    }

    /// Takes the accumulated mouse movement and clears it.
    ///
    /// Consumed exactly once per *frame*, not once per simulation step: the delta is a displacement
    /// that already happened, so applying it to every step of a frame that ran three of them would
    /// turn three times as far.
    public func consumePendingLook() -> SIMD2<Float> {
        defer { pendingLook = .zero }
        return pendingLook
    }

    /// Look **rate** from the right stick, in the range -1...1 per axis.
    ///
    /// Unlike the mouse delta this is a held position rather than a displacement, so the camera
    /// scales it by step duration. See `Camera.turn(rate:deltaTime:)`.
    public var lookRate: SIMD2<Float> {
        guard let gamepad else { return .zero }
        return StickResponse.shaped(
            SIMD2(gamepad.rightThumbstick.xAxis.value, gamepad.rightThumbstick.yAxis.value),
            deadzone: StickResponse.lookDeadzone, exponent: StickResponse.lookExponent)
    }
}
