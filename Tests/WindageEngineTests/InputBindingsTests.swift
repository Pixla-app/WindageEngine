//
//  InputBindingsTests.swift
//  WindageEngineTests
//

import Foundation
import Testing
@testable import WindageEngine

private func key(_ name: String) -> KeyCode { KeyCode(named: name)! }

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Suite("Key codes")
struct KeyCodeTests {

    @Test("Keys are found by name, whatever the case, and by the usual short names")
    func names() {
        #expect(KeyCode(named: "w")?.rawValue == 13)
        #expect(KeyCode(named: "W")?.rawValue == 13)
        #expect(KeyCode(named: "space")?.rawValue == 49)
        #expect(KeyCode(named: "Left Shift")?.rawValue == 56)
        #expect(KeyCode(named: "shift")?.rawValue == 56)
        #expect(KeyCode(named: "ctrl")?.rawValue == 59)
        #expect(KeyCode(named: "no such key") == nil)
        #expect(KeyCode(200).name == "Key 200")
    }

    /// **The whole reason Shift did nothing in the sample**: modifiers arrive as flags, and which
    /// Shift is down is in the low, device-specific bits — not the generic one.
    @Test("A modifier is read from its own device bit")
    func modifierBits() {
        let left = key("left shift"), right = key("right shift")
        #expect(left.isModifier && right.isModifier && !key("w").isModifier)
        // Right shift alone: its bit, 0x04, and the generic shift flag (1 << 17).
        let rightOnly: UInt = 0x04 | (1 << 17)
        #expect(right.isDown(inModifierFlags: rightOnly))
        #expect(!left.isDown(inModifierFlags: rightOnly),
                "the generic flag made the left Shift look held while only the right one was")
    }
}

@Suite("Input bindings")
struct InputBindingsTests {

    @Test("The standard layout is the one players arrive knowing")
    func standard() {
        let b = InputBindings.standard
        #expect(b[.forward] == key("W") && b[.back] == key("S"))
        #expect(b[.left] == key("A") && b[.right] == key("D"))
        #expect(b[.jump] == key("Space") && b[.crouch] == key("C") && b[.sprint] == key("Left Shift"))
        #expect(Set(InputBindings.Action.allCases.map { b[$0] }).count == InputBindings.Action.allCases.count)
    }

    @Test("A free key is simply taken")
    func bindFree() {
        var b = InputBindings.standard
        #expect(b.bind(.forward, to: key("I")) == .bound)
        #expect(b[.forward] == key("I"))
        #expect(b.action(on: key("W")) == nil, "W should now do nothing")
    }

    /// **Swapped, not stolen**: taking W for jump would otherwise leave a player who cannot walk.
    @Test("A key in use is swapped, and every action still has a key")
    func bindSwaps() {
        var b = InputBindings.standard
        #expect(b.bind(.jump, to: key("W")) == .swapped(with: .forward))
        #expect(b[.jump] == key("W"))
        #expect(b[.forward] == key("Space"))
        #expect(Set(InputBindings.Action.allCases.map { b[$0] }).count == InputBindings.Action.allCases.count)
    }

    /// **Escape is the way out** — bound to anything, the player cannot get their pointer back or reach
    /// the screen that would undo it.
    @Test("Escape, Tab and the arrows are refused")
    func fixedKeysRefused() {
        var b = InputBindings.standard
        for fixed in [KeyCode.escape, .tab, .up, .down, .left, .right] {
            #expect(b.bind(.jump, to: fixed) == .refused)
        }
        #expect(b == .standard)
    }

    /// **A key the game consumes first is a key the binding never sees.**
    @Test("A key the game reserves is refused")
    func reservedRefused() {
        var b = InputBindings.standard
        #expect(b.bind(.jump, to: key("P"), reserving: [key("P")]) == .refused)
        #expect(b[.jump] == key("Space"))
    }

    @Test("Binding an action to its own key changes nothing")
    func bindSame() {
        var b = InputBindings.standard
        #expect(b.bind(.forward, to: key("W")) == .bound)
        #expect(b == .standard)
    }

    @Test("A settings file stores keys by name, and reads them back")
    func roundTrip() throws {
        var b = InputBindings.standard
        b.bind(.forward, to: key("I"))
        b.bind(.crouch, to: key("left control"))
        let data = try JSONEncoder().encode(b)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"I\"") && text.contains("Left Control"), "\(text)")
        #expect(try JSONDecoder().decode(InputBindings.self, from: data) == b)
    }

    // MARK: - Tolerance — the reason a later build does not wipe a player's keys

    @Test("A missing action takes its default, and the rest are kept")
    func missingAction() throws {
        let b = try decode(InputBindings.self, #"{ "forward": "I", "jump": "F" }"#)
        #expect(b[.forward] == key("I") && b[.jump] == key("F"))
        #expect(b[.back] == key("S"))
    }

    @Test("An action this build does not know is ignored")
    func unknownAction() throws {
        let b = try decode(InputBindings.self, #"{ "forward": "I", "lean": "Q" }"#)
        #expect(b[.forward] == key("I"))
    }

    /// One bad entry must cost that one binding, not the whole dictionary.
    @Test("A key name this build does not know costs only that binding")
    func unknownKeyName() throws {
        let b = try decode(InputBindings.self, #"{ "forward": "Hyper", "jump": "F" }"#)
        #expect(b[.forward] == key("W"))
        #expect(b[.jump] == key("F"), "one unreadable key wiped the others")
    }

    @Test("A file with two actions on one key keeps the first and restores the second")
    func duplicateKeys() throws {
        let b = try decode(InputBindings.self, #"{ "forward": "F", "jump": "F" }"#)
        #expect(b[.forward] == key("F"))
        #expect(b[.jump] == key("Space"))
    }

    @Test("A fixed key in a file is not honoured")
    func fixedInFile() throws {
        let b = try decode(InputBindings.self, #"{ "jump": "Escape" }"#)
        #expect(b[.jump] == key("Space"))
    }

    @Test("A duplicate that collides with a fallback resets everything rather than sharing a key")
    func collidingFallback() throws {
        // Forward takes Space from the file; jump's default is Space; the file's jump is unreadable.
        let b = try decode(InputBindings.self, #"{ "forward": "Space", "jump": "Hyper" }"#)
        #expect(Set(InputBindings.Action.allCases.map { b[$0] }).count == InputBindings.Action.allCases.count)
    }
}

@Suite("Player settings")
struct PlayerSettingsTests {

    @Test("An older file with fewer fields keeps what it did say")
    func olderFile() throws {
        let s = try decode(PlayerSettings.self, #"{ "bindings": { "forward": "I" } }"#)
        #expect(s.bindings[.forward] == key("I"))
        #expect(s.lookSensitivity == 1 && s.volume == 0.8 && s.brightness == 0 && !s.invertLook)
    }

    @Test("An empty file is the defaults, not a failure")
    func emptyFile() throws {
        #expect(try decode(PlayerSettings.self, "{}") == PlayerSettings())
    }

    @Test("A wrong type in one field costs that field")
    func wrongType() throws {
        let s = try decode(PlayerSettings.self, #"{ "volume": "loud", "invertLook": true }"#)
        #expect(s.volume == 0.8)
        #expect(s.invertLook)
    }

    @Test("Values outside their range are clamped, from a file and when set")
    func clamped() throws {
        let s = try decode(PlayerSettings.self, #"{ "volume": 7, "lookSensitivity": 0, "brightness": -40 }"#)
        #expect(s.volume == 1)
        #expect(s.lookSensitivity == PlayerSettings.sensitivityRange.lowerBound)
        #expect(s.brightness == PlayerSettings.brightnessRange.lowerBound)

        var t = PlayerSettings()
        t.volume = -3
        t.lookSensitivity = 99
        #expect(t.volume == 0)
        #expect(t.lookSensitivity == PlayerSettings.sensitivityRange.upperBound)
    }

    @Test("Inverting look flips the vertical and nothing else")
    func invert() {
        var s = PlayerSettings()
        s.lookSensitivity = 2
        #expect(s.lookScale == SIMD2(2, 2))
        s.invertLook = true
        #expect(s.lookScale == SIMD2(2, -2))
    }

    /// Saved, then read by a store that knows nothing but the name — which is what the next launch is.
    @Test("Settings survive a save and a fresh load")
    func survivesSaving() throws {
        let store = SaveStore<PlayerSettings>(container: "WindageEngineTests-\(UUID().uuidString)",
                                              name: "settings")
        defer {
            store.clear()
            try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
        }
        var settings = PlayerSettings()
        settings.bindings.bind(.forward, to: key("I"))
        settings.volume = 0.3
        try store.save(settings)

        let again = SaveStore<PlayerSettings>(container: store.container, name: "settings")
        #expect(again.load() == settings)
    }
}

@MainActor
@Suite("Input state with bindings")
struct InputStateBindingTests {

    @Test("A rebound key moves the player and the old one does not")
    func reboundKeyMoves() {
        let input = InputState()
        input.bindings.bind(.forward, to: key("I"))
        input.keyDown(key("W").rawValue)
        #expect(input.movement.forward == 0, "the old key still walked")
        input.keyUp(key("W").rawValue)
        input.keyDown(key("I").rawValue)
        #expect(input.movement.forward == 1)
    }

    /// **The bug the sample shipped**: Shift only exists as a flags change. Routed through
    /// `flagsChanged`, it sprints.
    @Test("Shift arriving as a flags change sprints")
    func shiftSprints() {
        let input = InputState()
        input.keyDown(key("W").rawValue)
        #expect(!input.movement.sprint)
        input.flagsChanged(keyCode: 56, modifierFlags: 0x02 | (1 << 17))
        #expect(input.movement.sprint)
        input.flagsChanged(keyCode: 56, modifierFlags: 0)
        #expect(!input.movement.sprint)
    }

    /// Control for crouch is what a lot of players expect, and it is a modifier.
    @Test("Crouch bound to a modifier toggles on its press only")
    func crouchOnModifier() {
        let input = InputState()
        input.bindings.bind(.crouch, to: key("left control"))
        input.flagsChanged(keyCode: 59, modifierFlags: 0x01)
        #expect(input.isCrouching)
        input.flagsChanged(keyCode: 59, modifierFlags: 0)       // release: no second toggle
        #expect(input.isCrouching)
        input.flagsChanged(keyCode: 59, modifierFlags: 0x01)
        #expect(!input.isCrouching)
    }

    @Test("Jump follows its binding")
    func jumpFollowsBinding() {
        let input = InputState()
        input.bindings.bind(.jump, to: key("F"))
        input.keyDown(key("Space").rawValue)
        #expect(!input.isJumpHeld)
        input.keyDown(key("F").rawValue)
        #expect(input.isJumpHeld)
    }
}
