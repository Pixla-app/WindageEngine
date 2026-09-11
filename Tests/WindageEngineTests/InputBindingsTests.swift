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
        #expect(s.mouseSensitivity == 1 && s.stickSensitivity == 1 && s.volume == 0.8 && s.brightness == 0)
        #expect(!s.invertMouse && !s.invertStick)
    }

    @Test("Ambience defaults to full, loads when missing, and clamps")
    func ambience() throws {
        #expect(PlayerSettings().ambienceVolume == 1)
        let older = try decode(PlayerSettings.self, #"{ "volume": 0.5 }"#)
        #expect(older.ambienceVolume == 1 && older.volume == 0.5)
        #expect(try decode(PlayerSettings.self, #"{ "ambienceVolume": 3 }"#).ambienceVolume == 1)
        var s = PlayerSettings()
        s.ambienceVolume = -1
        #expect(s.ambienceVolume == 0)
    }

    @Test("Dead zones default to the engine's tuning, load when missing, and clamp to half a stick")
    func deadZones() throws {
        let s = PlayerSettings()
        #expect(s.moveDeadzone == StickResponse.moveDeadzone && s.lookDeadzone == StickResponse.lookDeadzone)
        let older = try decode(PlayerSettings.self, #"{ "headBob": 0.5 }"#)
        #expect(older.lookDeadzone == StickResponse.lookDeadzone && older.headBob == 0.5)
        let wild = try decode(PlayerSettings.self, #"{ "moveDeadzone": 0.9, "lookDeadzone": -1 }"#)
        #expect(wild.moveDeadzone == 0.5 && wild.lookDeadzone == 0)
    }

    /// Head bob arrived in 0.8.1; a file from before it has none, and must not lose everything else.
    @Test("Head bob is on by default, off at zero, and clamped")
    func headBob() throws {
        #expect(PlayerSettings().headBob == 1)
        let older = try decode(PlayerSettings.self, #"{ "mouseSensitivity": 2 }"#)
        #expect(older.headBob == 1 && older.mouseSensitivity == 2)
        #expect(try decode(PlayerSettings.self, #"{ "headBob": 0 }"#).headBob == 0)
        #expect(try decode(PlayerSettings.self, #"{ "headBob": 3 }"#).headBob == 1)
        var s = PlayerSettings()
        s.headBob = -1
        #expect(s.headBob == 0)
    }

    @Test("An empty file is the defaults, not a failure")
    func emptyFile() throws {
        #expect(try decode(PlayerSettings.self, "{}") == PlayerSettings())
    }

    @Test("A wrong type in one field costs that field")
    func wrongType() throws {
        let s = try decode(PlayerSettings.self, #"{ "volume": "loud", "invertStick": true }"#)
        #expect(s.volume == 0.8)
        #expect(s.invertStick)
    }

    @Test("Values outside their range are clamped, from a file and when set")
    func clamped() throws {
        let s = try decode(PlayerSettings.self,
                           #"{ "volume": 7, "mouseSensitivity": 0, "stickSensitivity": 80, "brightness": -40 }"#)
        #expect(s.volume == 1)
        #expect(s.mouseSensitivity == PlayerSettings.sensitivityRange.lowerBound)
        #expect(s.stickSensitivity == PlayerSettings.sensitivityRange.upperBound)
        #expect(s.brightness == PlayerSettings.brightnessRange.lowerBound)

        var t = PlayerSettings()
        t.volume = -3
        t.mouseSensitivity = 99
        t.stickSensitivity = .nan
        #expect(t.volume == 0)
        #expect(t.mouseSensitivity == PlayerSettings.sensitivityRange.upperBound)
        #expect(t.stickSensitivity == 1, "a NaN should fall back to the default, not poison the turn")
    }

    /// **The point of the change**: one device's setting must not move the other's.
    @Test("The mouse and the stick each have their own sensitivity and invert")
    func perDevice() {
        var s = PlayerSettings()
        s.mouseSensitivity = 2
        #expect(s.mouseLookScale == SIMD2(2, 2))
        #expect(s.stickLookScale == SIMD2(1, 1), "the mouse's sensitivity moved the stick's")
        s.invertStick = true
        #expect(s.stickLookScale == SIMD2(1, -1))
        #expect(s.mouseLookScale == SIMD2(2, 2), "inverting the stick inverted the mouse")
        s.stickSensitivity = 0.5
        s.invertMouse = true
        #expect(s.mouseLookScale == SIMD2(2, -2))
        #expect(s.stickLookScale == SIMD2(0.5, -0.5))
    }

    /// A player who set 2.0 and inverted before 0.8.0 had that on both devices, and keeps it.
    @Test("A file with one shared sensitivity gives it to both devices")
    func sharedSettingMigrates() throws {
        let s = try decode(PlayerSettings.self, #"{ "lookSensitivity": 2, "invertLook": true }"#)
        #expect(s.mouseSensitivity == 2 && s.stickSensitivity == 2)
        #expect(s.invertMouse && s.invertStick)
    }

    @Test("A device's own setting wins over the shared one")
    func ownSettingWins() throws {
        let s = try decode(PlayerSettings.self,
                           #"{ "lookSensitivity": 2, "invertLook": true, "stickSensitivity": 0.7, "invertMouse": false }"#)
        #expect(s.mouseSensitivity == 2 && s.stickSensitivity == 0.7)
        #expect(!s.invertMouse && s.invertStick)
    }

    @Test("The shared keys are read but never written")
    func sharedKeysNotWritten() throws {
        var s = PlayerSettings()
        s.mouseSensitivity = 1.5
        s.invertStick = true
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!text.contains("lookSensitivity") && !text.contains("invertLook"), "\(text)")
        #expect(try JSONDecoder().decode(PlayerSettings.self, from: Data(text.utf8)) == s)
    }

    /// The rates, through the camera — which is what a player feels. A mouse turns by its counts
    /// times the mouse setting, whatever the frame; a full stick turns at the stick setting's rate.
    @Test("Each device turns the view at the rate its own setting says")
    func ratesThroughTheCamera() {
        var s = PlayerSettings()
        s.mouseSensitivity = 2
        s.stickSensitivity = 0.5

        var mouseCamera = Camera()
        mouseCamera.look(mouseDelta: SIMD2(100, 0) * s.mouseLookScale)
        #expect(abs(-mouseCamera.yaw - 100 * Camera.lookSensitivity * 2) < 1e-5)

        var stickCamera = Camera()
        for _ in 0..<60 { stickCamera.turn(rate: SIMD2(1, 0) * s.stickLookScale, deltaTime: 1.0 / 120) }
        #expect(abs(-stickCamera.yaw - Camera.stickLookSpeed * 0.5 * 0.5) < 1e-4,
                "half a second at full deflection, at half the stick's speed")
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
