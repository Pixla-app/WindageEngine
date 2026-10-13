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

    /// ### The control map, and why most of it is not free to reassign
    ///
    /// Console shooters share a layout players arrive already knowing, and a game that ignores it is
    /// not being original — it is being wrong in a way every player notices and nobody reports. So
    /// this engine binds *around* the convention rather than through it, and the reserved rows below
    /// are as much a part of the map as the bound ones.
    ///
    /// | control | convention | here |
    /// |---|---|---|
    /// | Cross (`buttonA`) | jump | vertical movement |
    /// | Circle (`buttonB`) | crouch / prone | crouch latch |
    /// | Square (`buttonX`) | **reload** | **reserved — unbound** |
    /// | Triangle (`buttonY`) | **weapon swap** | **reserved — unbound** |
    /// | L1 (`leftShoulder`) | equipment / lean | brace latch |
    /// | R1 (`rightShoulder`) | grenade / melee | **reserved — unbound** |
    /// | L2 | aim | aim |
    /// | R2 | fire | fire |
    /// | L3 | sprint | sprint latch |
    /// | R3 | — | one scroll notch (magnification) |
    /// | d-pad | — | discrete steps (scope turrets, weapon select) |
    ///
    /// **The jump, crouch, sprint and brace rows are defaults**, and a player can move them — see
    /// ``padBindings`` and ``PadBindings``. The sticks, triggers, d-pad, R3 and the menu button are
    /// the convention and stay put.
    ///
    /// **Square and Triangle stay unbound even in a title that has neither a reload nor a second
    /// weapon**, because a player will press them looking for both, and because a title that later
    /// grows either would otherwise have to move something a player had already learned. That is the
    /// mistake this table exists to stop: the brace was on Square, then Triangle, before landing on a
    /// shoulder that nothing else wanted.
    ///
    /// > The framework names the face buttons in the **Xbox** layout, so on a DualSense `buttonY` is
    /// > Triangle and `buttonX` is Square — the opposite of what the letters suggest when you are
    /// > looking at the pad.

    /// macOS virtual key codes. These are physical positions, not letters — the codes below are the
    /// QWERTY WASD cluster and stay in the same place on an AZERTY keyboard, which is what a game
    /// wants.
    ///
    /// **Only the keys nothing may rebind are named here.** Everything a player can move lives in
    /// ``bindings``.
    private enum Key {
        static let escape: UInt16 = 53, tab: UInt16 = 48
        static let up: UInt16 = 126, down: UInt16 = 125, left: UInt16 = 123, right: UInt16 = 124
    }

    private var pressedKeys: Set<UInt16> = []
    /// Shift as reported by a window that forwards modifier flags itself — see ``setSprinting(_:)``.
    private var sprintingFromKeyboard = false

    /// Which key does what. **Everything the keyboard drives reads through this**, so a rebinding
    /// takes effect on the next key event with nothing else to update. See ``InputBindings``.
    public var bindings = InputBindings.standard

    private func held(_ action: InputBindings.Action) -> Bool {
        pressedKeys.contains(bindings[action].rawValue)
    }

    /// The sprint key, however it arrived.
    private var sprintKeyHeld: Bool { sprintingFromKeyboard || held(.sprint) }

    /// Stick-click sprint latches on and stays on. See ``SprintLatch``.
    private var sprintLatch = SprintLatch()

    /// Mouse movement seen since the simulation last took it.
    private var pendingLook: SIMD2<Float> = .zero

    /// While captured the cursor is hidden and detached, and the mouse turns the camera.
    public private(set) var isMouseCaptured = false

    private var rightMouseHeld = false
    private var leftMouseHeld = false

    /// Notches of scroll since the simulation last took them — mouse wheel, trackpad, or R3.
    ///
    /// **A notch, not a distance.** A wheel reports a continuous delta and a trackpad reports a
    /// stream of tiny ones; a game that consumes raw deltas gets a magnification that races on a
    /// trackpad and crawls on a wheel. Accumulating to a threshold makes both devices produce the
    /// same discrete clicks.
    private var scrollAccumulator: Float = 0
    private var pendingScroll = 0

    /// How much raw scroll makes one notch.
    public static let scrollNotch: Float = 1.0

    /// Feed raw scroll from the window. Positive is up / away from the user.
    public func addScroll(_ delta: Float) {
        scrollAccumulator += delta
        while scrollAccumulator >= InputState.scrollNotch {
            scrollAccumulator -= InputState.scrollNotch
            pendingScroll += 1
        }
        while scrollAccumulator <= -InputState.scrollNotch {
            scrollAccumulator += InputState.scrollNotch
            pendingScroll -= 1
        }
    }

    /// Notches since the last call. **Consumed once per simulation step**, like the look delta.
    public func consumeScroll() -> Int {
        defer { pendingScroll = 0 }
        return pendingScroll
    }

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
    /// the right behavior when someone puts a controller down and picks up the mouse.
    public var gamepad: GCExtendedGamepad? {
        suppliedGamepad ?? GCController.current?.extendedGamepad
    }

    public var isGamepadConnected: Bool { gamepad != nil }

    /// One the game handed over, which wins over the system's.
    private var suppliedGamepad: GCExtendedGamepad?

    /// Reads this pad instead of whichever one the system says is current — or, given nil, goes back.
    ///
    /// **For a pad nobody is holding**: `GCController.withExtendedGamepad()` makes one whose buttons are
    /// set from code, which is what a replay, a scripted check or a test drives. The system never
    /// makes it `current`, because it is not connected to anything — so without this there would be
    /// no way to put a finger on the real input path without a real finger.
    public func useGamepad(_ pad: GCExtendedGamepad?) {
        suppliedGamepad = pad
        padButtonsDown = []
    }

    /// Which button does what on a pad. **Everything the pad's buttons drive reads through this.**
    public var padBindings = PadBindings.standard

    /// How far each stick must move before it counts. The engine's tuning until a game hands over the
    /// player's — ``PlayerSettings/moveDeadzone`` and ``PlayerSettings/lookDeadzone``.
    public var moveDeadzone = StickResponse.moveDeadzone
    public var lookDeadzone = StickResponse.lookDeadzone

    /// Whether the pad's buttons act — crouch, brace, sprint, jump, the scroll notch.
    ///
    /// **Off while a game's menu has the pad.** A keyboard key the menu takes never reaches this type;
    /// a pad is polled here, so without a switch a Circle pressed to leave a settings screen would
    /// also crouch the player behind it. The presses are still reported in ``padButtonsPressed``, which
    /// is what the menu reads instead.
    public var acceptsPadActions = true

    /// Buttons that went down this frame, whatever they are bound to. For a menu, or for a settings
    /// screen waiting for the button a player wants.
    public private(set) var padButtonsPressed: Set<PadButton> = []

    /// Whether the pad's menu button went down this frame.
    public private(set) var padMenuPressed = false

    private var padButtonsDown: Set<PadButton> = []
    private var padMenuWasDown = false

    private func padHeld(_ action: InputBindings.Action) -> Bool {
        guard acceptsPadActions, let pad = gamepad, let button = padBindings[action] else { return false }
        return button.element(on: pad)?.isPressed ?? false
    }

    private func observeControllers() {
        let center = NotificationCenter.default
        connectionObservers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
                let name = (note.object as? GCController)?.vendorName ?? "Controller"
                NSLog("\(Engine.name): \(name) connected")
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { note in
                let name = (note.object as? GCController)?.vendorName ?? "Controller"
                NSLog("\(Engine.name): \(name) disconnected")
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
        if keyCode == bindings[.crouch].rawValue && !wasDown { toggleCrouch() }
        if keyCode == Key.tab && !wasDown { pendingNext += 1 }
        if keyCode == bindings[.brace].rawValue && !wasDown { toggleBrace() }

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

    /// A modifier key changed: forward every `flagsChanged` event here with its key code and raw
    /// flags.
    ///
    /// **macOS never sends Shift, Control, Option or Command as key presses** — only as a change of
    /// flags — so a window that forwards `keyDown` and `keyUp` alone silently has no Shift at all. The
    /// sample shipped a release like that, with "shift sprint" printed on screen. Routed through
    /// here, a modifier is a key like any other, and can be bound to anything.
    public func flagsChanged(keyCode: UInt16, modifierFlags: UInt) {
        let key = KeyCode(keyCode)
        guard key.isModifier else { return }
        if key.isDown(inModifierFlags: modifierFlags) { keyDown(keyCode) } else { keyUp(keyCode) }
    }

    /// Presses of **Tab** since the game last took them.
    ///
    /// **A generic "next" edge, not a game verb.** The engine has no idea what a title advances —
    /// a job, a level, a page of a menu — and should not learn. It counts presses; the game decides.
    public private(set) var pendingNext = 0

    /// Takes the accumulated presses and clears them.
    public func consumeNext() -> Int {
        defer { pendingNext = 0 }
        return pendingNext
    }

    /// Toggles the crouch. Called on the key *down* edge, so holding `C` does not strobe it.
    public func toggleCrouch() {
        isCrouching.toggle()
    }
    /// Sprint held, for a window that reads Shift from its own modifier flags.
    ///
    /// **Prefer ``flagsChanged(keyCode:modifierFlags:)``**, which makes Shift a key like any other
    /// and so rebindable. This remains for a window that already does it this way, and the two
    /// combine: either one held is sprinting.
    public func setSprinting(_ sprinting: Bool) {
        sprintingFromKeyboard = sprinting
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
        sprintKeyHeld || steadyingFromPad
    }

    /// Jump: **Space**, or Cross on a pad. **Held state, not a press** — a controller that jumps
    /// finds the press itself, because it also has to remember one that arrived a moment before
    /// landing, and only it knows when that was.
    ///
    /// Read separately from `MovementInput.vertical`, which the same keys also drive for a title that
    /// flies: `C` pulls that axis down, so holding Space and C together reads as zero there and would
    /// swallow a jump taken from a crouch.
    public var isJumpHeld: Bool {
        held(.jump) || padHeld(.jump)
    }

    private var steadyingFromPad = false

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
    /// the button. See `CharacterController.Tuning.crouchedEyeHeight`.
    ///
    /// The same keys previously drove `MovementInput.vertical` for the free-flying camera. That axis
    /// is still there for a title that flies; a game with feet reads ``isJumpHeld`` instead.
    public private(set) var isCrouching = false

    /// Whether the player is **braced** — resting the weapon on something rather than holding it up.
    ///
    /// Latched like the crouch, and generic on purpose: a bipod is one version of it, a wall lean or
    /// a sandbag is another. What the engine knows is that it is a held posture the player toggles;
    /// what it *means* is the game's business.
    ///
    /// **`B` on the keyboard, L1 on a controller** — see the control map on ``InputState``.
    public private(set) var isBraced = false

    public func toggleBrace() { isBraced.toggle() }

    /// Give it up. A game calls this when its own rules say bracing has ended — a deployed bipod
    /// folds when the player stands or runs.
    public func releaseBrace() { isBraced = false }


    /// **Asking to sprint stands you up — on the press, not while it is held.**
    ///
    /// You cannot sprint crouched, so a sprint *press* while crouched is either ignored or obeyed.
    /// Ignoring it leaves the player pressing a key that does nothing and concluding the game is
    /// stuck; standing up is what they meant, because "go fast" is not an ambiguous intent.
    ///
    /// > **It checked the held state and ran every frame, which made crouching while sprinting
    /// > impossible.** `pollFrame` called this on every tick, so pressing `C` with Shift down
    /// > crouched for exactly one step and stood back up on the next — and since a slide starts on
    /// > the edge of crouching at sprint speed, the slide could never happen either. It reads as the
    /// > key doing nothing. Tests missed it because they drove this type directly and never ran
    /// > `pollFrame`; only stepping the real input path in the running game showed it.
    private func standIfSprinting() {
        let requested = sprintKeyHeld || sprintLatch.isEngaged
        defer { sprintWasRequested = requested }
        guard requested, !sprintWasRequested else { return }
        isCrouching = false
    }

    private var sprintWasRequested = false

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
        // **Every button's press edge, once, from one set** — rather than a remembered flag per
        // button, which is what this was while each button meant one fixed thing. Bound buttons move,
        // so the edge has to be found for all of them and then looked up.
        let down = Set(PadButton.allCases.filter { button in
            gamepad.flatMap { button.element(on: $0)?.isPressed } ?? false
        })
        padButtonsPressed = down.subtracting(padButtonsDown)
        padButtonsDown = down
        let menuDown = gamepad?.buttonMenu.isPressed ?? false
        padMenuPressed = menuDown && !padMenuWasDown
        padMenuWasDown = menuDown

        if acceptsPadActions {
            // Crouch toggles on its press edge, like `C` does. Level-triggering it would strobe the
            // posture for as long as the button is down.
            if let crouch = padBindings[.crouch], padButtonsPressed.contains(crouch) { toggleCrouch() }

            // **L1 by default, because every face button is spoken for.** Square is reload and
            // Triangle is weapon swap; a shooter is expected to grow a second weapon, so Triangle is
            // not free to borrow even while there is only one. See ``PadBindings``.
            if let brace = padBindings[.brace], padButtonsPressed.contains(brace) { toggleBrace() }

            // **R3 scrolls one way only, and that is a real limit rather than an oversight.** A button
            // has no sign; a game binding it to something with a range has to wrap around, and should
            // say so on screen. The mouse wheel is the two-way device. Never a binding.
            if padButtonsPressed.contains(.rightStick) { pendingScroll += 1 }
        }

        // Sprint stands a crouched player up on the press edge. Evaluated once a frame, here, after
        // the latch below has settled — checking the *held* state instead is what made crouching
        // while sprinting impossible.
        defer { standIfSprinting() }

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
        let stickClick = padHeld(.sprint)
        let aiming = isAiming
        steadyingFromPad = aiming && stickClick

        if aiming {
            sprintLatch.disengage()
        } else {
            sprintLatch.update(buttonPressed: stickClick, forwardInput: movement.forward)
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
        padButtonsDown = []
        padButtonsPressed = []
    }

    // MARK: - Simulation reads

    /// Movement intent, from keyboard and left stick together.
    public var movement: MovementInput {
        var input = MovementInput()

        if held(.forward) { input.forward += 1 }
        if held(.back) { input.forward -= 1 }
        if held(.right) { input.strafe += 1 }
        if held(.left) { input.strafe -= 1 }
        if held(.jump) { input.vertical += 1 }
        if held(.crouch) { input.vertical -= 1 }
        input.sprint = sprintKeyHeld

        if let gamepad {
            let stick = StickResponse.shaped(
                SIMD2(gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value),
                deadzone: moveDeadzone, exponent: StickResponse.moveExponent)
            input.strafe += stick.x
            input.forward += stick.y

            // Cross rises. Circle used to drop, matching C — it toggles the crouch now, and a
            // button cannot mean both "go down one metre per second" and "change posture".
            if padHeld(.jump) { input.vertical += 1 }
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
            deadzone: lookDeadzone, exponent: StickResponse.lookExponent)
    }
}
