//
//  PadBindings.swift
//  WindageEngine
//

import GameController

/// A button on a controller, **by where it is rather than what it is called.**
///
/// The bottom face button is *A* on an Xbox pad, *Cross* on a DualSense and *B* on a Nintendo one —
/// three names for the same thumb position, and the position is what a player's hand learned. Stored
/// that way, a binding made on one pad means the same thing on the next. Shown that way it would be
/// meaningless, so ``name(on:)`` asks the connected pad what it prints on the button.
public nonisolated enum PadButton: String, CaseIterable, Sendable, Codable {
    case south, east, west, north
    case leftShoulder, rightShoulder
    case leftStick, rightStick

    /// What a settings screen shows when no pad is connected to ask: the position's name on the two
    /// pads a Mac player is likeliest to own.
    public var name: String {
        switch self {
        case .south: "Cross / A"
        case .east: "Circle / B"
        case .west: "Square / X"
        case .north: "Triangle / Y"
        case .leftShoulder: "L1 / LB"
        case .rightShoulder: "R1 / RB"
        case .leftStick: "L3"
        case .rightStick: "R3"
        }
    }

    /// What this pad calls the button — "Cross" on a DualSense, "A" on an Xbox pad — or ``name``.
    ///
    /// The framework's names end in " Button", which a settings row does not need.
    public func name(on pad: GCExtendedGamepad?) -> String {
        guard let pad, let local = element(on: pad)?.localizedName else { return name }
        return local.hasSuffix(" Button") ? String(local.dropLast(" Button".count)) : local
    }

    /// The element on a pad. **The framework names them in the Xbox layout** — `buttonA` is the bottom
    /// one on every pad — which is the one place here the letters and the positions line up.
    func element(on pad: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch self {
        case .south: pad.buttonA
        case .east: pad.buttonB
        case .west: pad.buttonX
        case .north: pad.buttonY
        case .leftShoulder: pad.leftShoulder
        case .rightShoulder: pad.rightShoulder
        case .leftStick: pad.leftThumbstickButton
        case .rightStick: pad.rightThumbstickButton
        }
    }
}

/// Which controller button does what.
///
/// ### Only the buttons that are actions
///
/// **The sticks move and look, the triggers aim and fire, the d-pad steps and the menu button opens a
/// menu.** Those are the console convention and they stay where they are — a shooter that let a
/// player put aim on a face button would be offering a way to make it unplayable. What moves are the
/// four actions that are buttons on a pad: jump, crouch, sprint and brace. Walking directions have
/// no button to bind; they are the stick.
///
/// ### R3 is refused, and the reserved face buttons are not
///
/// **R3 is the engine's scroll notch** — magnification, or anything else with a range — the way the
/// arrows are its steps on a keyboard, so it cannot also be a binding. **Square, Triangle and R1 are
/// only unbound by default**: the control map on ``InputState`` keeps them free so a title can grow a
/// reload or a second weapon without moving anything a player has learned. A title that has grown
/// one passes it in `reserving:`; a player of a title that has not may use them.
public nonisolated struct PadBindings: Sendable, Equatable, Codable {

    /// The actions a pad button can be bound to.
    public static let actions: [InputBindings.Action] = [.jump, .crouch, .sprint, .brace]

    /// Buttons nothing may be bound to.
    public static let fixed: Set<PadButton> = [.rightStick]

    /// The convention: Cross jumps, Circle crouches, L3 sprints, L1 braces.
    public static let standard = PadBindings(uncheckedMap: [
        .jump: .south, .crouch: .east, .sprint: .leftStick, .brace: .leftShoulder,
    ])

    private var map: [InputBindings.Action: PadButton]

    private init(uncheckedMap: [InputBindings.Action: PadButton]) { map = uncheckedMap }

    public init() { self = .standard }

    /// The button for an action, or nil for one that is not a button on a pad.
    public subscript(action: InputBindings.Action) -> PadButton? {
        guard PadBindings.actions.contains(action) else { return nil }
        return map[action] ?? PadBindings.standard.map[action]
    }

    public func action(on button: PadButton) -> InputBindings.Action? {
        PadBindings.actions.first { self[$0] == button }
    }

    /// Puts an action on a button. **Swapped, not stolen**, for the reason ``InputBindings`` gives.
    @discardableResult
    public mutating func bind(_ action: InputBindings.Action, to button: PadButton,
                              reserving: Set<PadButton> = []) -> InputBindings.Outcome {
        guard PadBindings.actions.contains(action),
              !PadBindings.fixed.contains(button), !reserving.contains(button),
              let previous = self[action] else { return .refused }
        guard previous != button else { return .bound }
        if let other = self.action(on: button) {
            map[other] = previous
            map[action] = button
            return .swapped(with: other)
        }
        map[action] = button
        return .bound
    }

    // MARK: - Codable

    /// **Tolerant, field by field**, exactly as ``InputBindings`` is and for the same reason: a file
    /// that fails to decode is every binding reset.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stored = (try? container.decode([String: String].self)) ?? [:]
        var map = PadBindings.standard.map
        var taken = Set<PadButton>()
        for action in PadBindings.actions {
            if let raw = stored[action.rawValue], let button = PadButton(rawValue: raw),
               !PadBindings.fixed.contains(button), !taken.contains(button) {
                map[action] = button
            }
            taken.insert(map[action]!)
        }
        if Set(map.values).count != map.count { map = PadBindings.standard.map }
        self.map = map
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value.rawValue) }))
    }
}
