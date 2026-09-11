//
//  InputBindings.swift
//  WindageEngine
//

import Foundation

/// A physical key, by its macOS virtual key code.
///
/// **A position on the keyboard, not a letter.** Code 13 is the key where W sits on a US layout and
/// Z sits on an AZERTY one, which is what a game wants for movement: the cluster under the left hand
/// stays under the left hand. The *name* is the US legend, which is what a settings screen shows and
/// what a settings file stores.
public nonisolated struct KeyCode: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(_ rawValue: UInt16) { self.rawValue = rawValue }

    /// The key's legend, or its code if it has none this table knows.
    public var name: String { KeyCode.names[rawValue] ?? "Key \(rawValue)" }
    public var description: String { name }

    /// A key by the name a person would type — `"W"`, `"space"`, `"left shift"`. Case-insensitive.
    public init?(named name: String) {
        let wanted = name.lowercased()
        guard let code = KeyCode.names.first(where: { $0.value.lowercased() == wanted })?.key
                ?? KeyCode.aliases[wanted] else { return nil }
        self.rawValue = code
    }

    /// **Stored by name**, so a settings file says `"forward" : "W"` — something a person can read,
    /// and edit, and not get wrong by one digit.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(UInt16.self) {
            self.rawValue = number
            return
        }
        let name = try container.decode(String.self)
        guard let key = KeyCode(named: name) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "no key named '\(name)'")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if KeyCode.names[rawValue] != nil { try container.encode(name) } else { try container.encode(rawValue) }
    }

    // MARK: - Modifiers

    /// **Shift, Control, Option and Command are keys here, like any other.** macOS does not send them
    /// as key presses at all — they arrive as a change of *modifier flags* — which is how a sample
    /// could print "shift sprint" on screen for a release and have Shift do nothing: its window never
    /// listened for the event that carries it. Treating them as keys is what lets Control be bound to
    /// crouch, which a lot of players expect.
    public var isModifier: Bool { KeyCode.modifierMasks[rawValue] != nil }

    /// The device-specific flag bit this modifier sets while held, or nil for an ordinary key. What a
    /// replayed key press needs in order to look like the real event.
    public var modifierFlag: UInt? { KeyCode.modifierMasks[rawValue] }

    /// Whether this modifier is down, given an event's raw modifier flags.
    ///
    /// **By the device-specific bit, not the generic one.** The generic `.shift` flag is set while
    /// *either* Shift is down, so releasing the left one with the right still held would read as the
    /// left still pressed. The low bits of the raw flags say which physical key it is.
    public func isDown(inModifierFlags flags: UInt) -> Bool {
        guard let mask = KeyCode.modifierMasks[rawValue] else { return false }
        return flags & mask != 0
    }

    private static let modifierMasks: [UInt16: UInt] = [
        56: 0x02, 60: 0x04,          // left, right shift
        59: 0x01, 62: 0x2000,        // left, right control
        58: 0x20, 61: 0x40,          // left, right option
        55: 0x08, 54: 0x10,          // left, right command
    ]

    static let names: [UInt16: String] = {
        let table: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete", 57: "Caps Lock",
            50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".",
            44: "/",
            126: "Up", 125: "Down", 123: "Left", 124: "Right",
            56: "Left Shift", 60: "Right Shift", 59: "Left Control", 62: "Right Control",
            58: "Left Option", 61: "Right Option", 55: "Left Command", 54: "Right Command",
        ]
        return table
    }()

    /// Short names a script or a hand-edited file might use.
    private static let aliases: [String: UInt16] = [
        "shift": 56, "control": 59, "ctrl": 59, "option": 58, "alt": 58, "command": 55, "cmd": 55,
        "enter": 36, "esc": 53, "backspace": 51,
    ]

    public static let escape = KeyCode(53), tab = KeyCode(48), `return` = KeyCode(36)
    public static let up = KeyCode(126), down = KeyCode(125), left = KeyCode(123), right = KeyCode(124)
}

/// Which key does what, and the rules for changing it.
///
/// ### What can be rebound, and what cannot
///
/// **The movement and posture keys can** — the eight a player of a first-person game expects to
/// move: the four directions, jump, crouch, sprint and brace. **Escape, Tab and the arrows cannot**,
/// and are refused rather than accepted and broken:
///
/// - **Escape is the way out.** It releases the pointer. A player who binds it to jump has no way to
///   get their mouse back, and cannot open the screen that would undo it.
/// - **Tab and the arrows are the engine's generic "next" and "step"**, which a game uses for menus
///   and turrets. Binding forward to Up would move the player *and* step whatever the game has on
///   the arrows.
///
/// A game adds its own keys to the refused set when it binds — see ``bind(_:to:reserving:)`` — because
/// **a key the game consumes first is a key the binding never sees**: in the sample, P pauses, so a
/// jump bound to P would pause the game instead.
///
/// ### One key per action
///
/// A primary and a secondary per action is common on PC and doubles every question below. One key
/// per action is enough to answer the one that matters — *can I put this where my hand is* — and a
/// second slot can arrive when a title asks for it.
public nonisolated struct InputBindings: Sendable, Equatable, Codable {

    public enum Action: String, CaseIterable, Sendable, Codable {
        case forward, back, left, right, jump, crouch, sprint, brace

        /// What a settings screen calls it.
        public var title: String {
            switch self {
            case .forward: "Forward"
            case .back: "Back"
            case .left: "Left"
            case .right: "Right"
            case .jump: "Jump"
            case .crouch: "Crouch"
            case .sprint: "Sprint"
            case .brace: "Brace"
            }
        }
    }

    /// Keys nothing may be bound to. See the type's notes.
    public static let fixed: Set<KeyCode> = [.escape, .tab, .up, .down, .left, .right]

    /// The layout every player arrives knowing.
    public static let standard = InputBindings(uncheckedMap: [
        .forward: KeyCode(13), .back: KeyCode(1), .left: KeyCode(0), .right: KeyCode(2),
        .jump: KeyCode(49), .crouch: KeyCode(8), .sprint: KeyCode(56), .brace: KeyCode(11),
    ])

    private var map: [Action: KeyCode]

    private init(uncheckedMap: [Action: KeyCode]) { map = uncheckedMap }

    public init() { self = .standard }

    public subscript(action: Action) -> KeyCode { map[action] ?? InputBindings.standard.map[action]! }

    /// The action on a key, if any.
    public func action(on key: KeyCode) -> Action? {
        Action.allCases.first { self[$0] == key }
    }

    public enum Outcome: Equatable, Sendable {
        /// The key was free, or already this action's.
        case bound
        /// The key belonged to another action, which now has this action's old key.
        case swapped(with: Action)
        /// Not allowed — Escape, Tab, the arrows, or one the game reserved.
        case refused
    }

    /// Puts an action on a key.
    ///
    /// **A key already in use is swapped, not stolen.** Taking W for jump and leaving forward with
    /// nothing is a player who cannot walk and does not know why; swapping gives forward jump's old
    /// key, so every action still has one. The outcome says which, so a settings screen can tell them.
    ///
    /// - Parameter reserving: keys the game consumes itself — its pause key, its menu key. Refused,
    ///   along with ``fixed``.
    @discardableResult
    public mutating func bind(_ action: Action, to key: KeyCode, reserving: Set<KeyCode> = []) -> Outcome {
        guard !InputBindings.fixed.contains(key), !reserving.contains(key) else { return .refused }
        let previous = self[action]
        guard previous != key else { return .bound }
        if let other = self.action(on: key) {
            map[other] = previous
            map[action] = key
            return .swapped(with: other)
        }
        map[action] = key
        return .bound
    }

    // MARK: - Codable

    /// **Tolerant, and it has to be.** `SaveStore` hands back nothing for a file it cannot decode, and
    /// for settings nothing means *everything reset*: a player who rebound eight keys loses all eight
    /// because a later build added a ninth. So a missing action takes its default, an unknown one is
    /// ignored, a key name this build does not know falls back — and a file where two actions share a
    /// key, which only a hand edit can produce, falls back for the second.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Each entry on its own: a single key name this build does not know must cost that one
        // binding, not the whole dictionary.
        let stored = ((try? container.decode([String: Lenient].self)) ?? [:]).compactMapValues(\.key)
        var map = InputBindings.standard.map
        var taken = Set<KeyCode>()
        for action in Action.allCases {
            if let key = stored[action.rawValue], !InputBindings.fixed.contains(key), !taken.contains(key) {
                map[action] = key
            }
            taken.insert(map[action]!)
        }
        // A fallback can still collide with a key an earlier action took from the file.
        if Set(map.values).count != map.count { map = InputBindings.standard.map }
        self.map = map
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) }))
    }

    /// A key that decodes to nothing rather than failing.
    private struct Lenient: Decodable {
        let key: KeyCode?
        init(from decoder: Decoder) throws { key = try? KeyCode(from: decoder) }
    }
}

/// What a player sets once and expects to find set again.
///
/// **The engine's share of a settings screen**: the things every first-person game has and none
/// should reinvent. A game with more — a field of view, a difficulty, subtitles — keeps them beside
/// this rather than inside it.
public nonisolated struct PlayerSettings: Sendable, Equatable, Codable {

    public var bindings = InputBindings.standard

    /// Which controller button does what. See ``PadBindings``.
    public var padBindings = PadBindings.standard

    /// A multiplier on how far a mouse movement turns the view. 1 is the engine's tuning.
    ///
    /// ### Two sensitivities, because one number cannot suit both
    ///
    /// **A mouse is a displacement and a stick is a rate** (see ``Camera/look(mouseDelta:)`` and
    /// ``Camera/turn(rate:deltaTime:)``), and a player's comfortable setting for one says nothing
    /// about the other. With one multiplier a player who uses both — a pad on the sofa, a mouse at
    /// the desk — had to choose which device to leave wrong. Every shooter on a console and a PC
    /// separates them for that reason.
    public var mouseSensitivity: Float = 1 {
        didSet { mouseSensitivity = PlayerSettings.clamp(mouseSensitivity, PlayerSettings.sensitivityRange, 1) }
    }

    /// A multiplier on how fast a held stick turns the view. 1 is the engine's tuning.
    public var stickSensitivity: Float = 1 {
        didSet { stickSensitivity = PlayerSettings.clamp(stickSensitivity, PlayerSettings.sensitivityRange, 1) }
    }

    /// Pushing the mouse forward looks down. **A setting rather than a preference someone can argue
    /// out of the game**, because the players who want it cannot play without it.
    ///
    /// **Per device**, because the convention differs by device: flight-trained players often invert
    /// a stick and not a mouse, and a single switch made them pick one to get wrong.
    public var invertMouse = false

    /// Pushing the look stick up looks down.
    public var invertStick = false

    /// How far each stick must move before it counts, 0…0.5 of its travel.
    ///
    /// **A worn stick drifts**: it rests a few percent off centre, and past the dead zone that is a
    /// view creeping round or a player walking off with nobody touching anything. The only fix a
    /// player has without this is a new controller. The defaults are the engine's tuning — movement
    /// tolerates more dead area than aiming, because drifting forward slowly is harmless and an aim
    /// that creeps is not. **The response still starts from zero at the edge** of whatever dead zone
    /// is set, and still reaches full at full deflection; see ``StickResponse/shaped(_:deadzone:exponent:)``.
    public var moveDeadzone: Float = StickResponse.moveDeadzone {
        didSet { moveDeadzone = PlayerSettings.clamp(moveDeadzone, PlayerSettings.deadzoneRange, StickResponse.moveDeadzone) }
    }
    public var lookDeadzone: Float = StickResponse.lookDeadzone {
        didSet { lookDeadzone = PlayerSettings.clamp(lookDeadzone, PlayerSettings.deadzoneRange, StickResponse.lookDeadzone) }
    }

    /// Half the stick is the most a dead zone may take: past that, what is left is too short a
    /// throw to control anything with.
    public static let deadzoneRange: ClosedRange<Float> = 0...0.5

    /// How much of the head bob to show, 0…1 — **0 is off**. See ``CharacterController/headBob``.
    ///
    /// **An amount rather than a switch, with off at the bottom of it.** Bob is a known cause of
    /// motion sickness, so off has to exist and be easy to find; but most players who find the full
    /// bob too much want less of it rather than none.
    public var headBob: Float = 1 {
        didSet { headBob = PlayerSettings.clamp(headBob, 0...1, 1) }
    }

    /// Everything the game plays, 0…1.
    public var volume: Float = 0.8 {
        didSet { volume = PlayerSettings.clamp(volume, 0...1, 0.8) }
    }

    /// The sounds places make — ``AudioEngine/ambienceVolume`` — 0…1, under ``volume``. **Separate
    /// because a player who finds a fire too loud should not lose their footsteps turning it down.**
    public var ambienceVolume: Float = 1 {
        didSet { ambienceVolume = PlayerSettings.clamp(ambienceVolume, 0...1, 1) }
    }

    /// Stops added to the game's own exposure. **The player's dial on top of the game's**, so a level
    /// authored at −0.5 stays −0.5 relative to itself, and a player on a dim screen lifts all of them.
    public var brightness: Float = 0 {
        didSet { brightness = PlayerSettings.clamp(brightness, PlayerSettings.brightnessRange, 0) }
    }

    public static let sensitivityRange: ClosedRange<Float> = 0.1...5
    public static let brightnessRange: ClosedRange<Float> = -2...2

    public init() {}

    /// What to multiply a mouse delta by before ``Camera/look(mouseDelta:)``.
    public var mouseLookScale: SIMD2<Float> {
        SIMD2(mouseSensitivity, invertMouse ? -mouseSensitivity : mouseSensitivity)
    }

    /// What to multiply a stick's look rate by before ``Camera/turn(rate:deltaTime:)``.
    public var stickLookScale: SIMD2<Float> {
        SIMD2(stickSensitivity, invertStick ? -stickSensitivity : stickSensitivity)
    }

    private static func clamp(_ value: Float, _ range: ClosedRange<Float>, _ fallback: Float) -> Float {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    private enum CodingKeys: String, CodingKey {
        case bindings, padBindings, mouseSensitivity, stickSensitivity, invertMouse, invertStick
        case moveDeadzone, lookDeadzone, headBob, volume, ambienceVolume, brightness
        /// Read, never written: one sensitivity and one invert for both devices, before 0.8.0.
        case lookSensitivity, invertLook
    }

    /// **Every field optional**, for the reason ``InputBindings`` gives: a settings file from an
    /// older build must load into a newer one with everything it did say intact.
    ///
    /// **A file from before 0.8.0 has one sensitivity and one invert**, and both devices inherit
    /// them — that is what the player had, on both, the last time they played. A device's own key
    /// wins where a file has both.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = (try? c.decodeIfPresent(InputBindings.self, forKey: .bindings)) ?? .standard
        padBindings = (try? c.decodeIfPresent(PadBindings.self, forKey: .padBindings)) ?? .standard
        let range = PlayerSettings.sensitivityRange
        let sharedSensitivity = (try? c.decodeIfPresent(Float.self, forKey: .lookSensitivity)) ?? 1
        let sharedInvert = (try? c.decodeIfPresent(Bool.self, forKey: .invertLook)) ?? false
        mouseSensitivity = PlayerSettings.clamp(
            (try? c.decodeIfPresent(Float.self, forKey: .mouseSensitivity)) ?? sharedSensitivity, range, 1)
        stickSensitivity = PlayerSettings.clamp(
            (try? c.decodeIfPresent(Float.self, forKey: .stickSensitivity)) ?? sharedSensitivity, range, 1)
        invertMouse = (try? c.decodeIfPresent(Bool.self, forKey: .invertMouse)) ?? sharedInvert
        invertStick = (try? c.decodeIfPresent(Bool.self, forKey: .invertStick)) ?? sharedInvert
        moveDeadzone = PlayerSettings.clamp((try? c.decodeIfPresent(Float.self, forKey: .moveDeadzone))
            ?? StickResponse.moveDeadzone, PlayerSettings.deadzoneRange, StickResponse.moveDeadzone)
        lookDeadzone = PlayerSettings.clamp((try? c.decodeIfPresent(Float.self, forKey: .lookDeadzone))
            ?? StickResponse.lookDeadzone, PlayerSettings.deadzoneRange, StickResponse.lookDeadzone)
        headBob = PlayerSettings.clamp((try? c.decodeIfPresent(Float.self, forKey: .headBob)) ?? 1, 0...1, 1)
        volume = PlayerSettings.clamp((try? c.decodeIfPresent(Float.self, forKey: .volume)) ?? 0.8, 0...1, 0.8)
        ambienceVolume = PlayerSettings.clamp(
            (try? c.decodeIfPresent(Float.self, forKey: .ambienceVolume)) ?? 1, 0...1, 1)
        brightness = PlayerSettings.clamp(
            (try? c.decodeIfPresent(Float.self, forKey: .brightness)) ?? 0, PlayerSettings.brightnessRange, 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bindings, forKey: .bindings)
        try c.encode(padBindings, forKey: .padBindings)
        try c.encode(mouseSensitivity, forKey: .mouseSensitivity)
        try c.encode(stickSensitivity, forKey: .stickSensitivity)
        try c.encode(invertMouse, forKey: .invertMouse)
        try c.encode(invertStick, forKey: .invertStick)
        try c.encode(moveDeadzone, forKey: .moveDeadzone)
        try c.encode(lookDeadzone, forKey: .lookDeadzone)
        try c.encode(headBob, forKey: .headBob)
        try c.encode(volume, forKey: .volume)
        try c.encode(ambienceVolume, forKey: .ambienceVolume)
        try c.encode(brightness, forKey: .brightness)
    }
}
