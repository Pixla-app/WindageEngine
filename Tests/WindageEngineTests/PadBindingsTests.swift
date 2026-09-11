//
//  PadBindingsTests.swift
//  WindageEngineTests
//

import Foundation
import GameController
import Testing
@testable import WindageEngine

@Suite("Pad bindings")
struct PadBindingsTests {

    @Test("The standard layout is the console convention")
    func standard() {
        let b = PadBindings.standard
        #expect(b[.jump] == .south && b[.crouch] == .east && b[.sprint] == .leftStick && b[.brace] == .leftShoulder)
        #expect(b[.forward] == nil, "walking is the stick, not a button")
    }

    @Test("A button in use is swapped, not stolen")
    func swaps() {
        var b = PadBindings.standard
        #expect(b.bind(.crouch, to: .south) == .swapped(with: .jump))
        #expect(b[.crouch] == .south && b[.jump] == .east)
    }

    /// R3 is the scroll notch; walking has no button.
    @Test("R3, a reserved button and a movement action are refused")
    func refusals() {
        var b = PadBindings.standard
        #expect(b.bind(.jump, to: .rightStick) == .refused)
        #expect(b.bind(.jump, to: .west, reserving: [.west]) == .refused)
        #expect(b.bind(.forward, to: .north) == .refused)
        #expect(b == .standard)
    }

    /// **Only unbound by default** — a title without a reload leaves Square to the player.
    @Test("A reserved-by-convention face button can be bound when the game does not reserve it")
    func conventionIsNotARule() {
        var b = PadBindings.standard
        #expect(b.bind(.brace, to: .west) == .bound)
    }

    @Test("Stored by position, and read back")
    func roundTrip() throws {
        var b = PadBindings.standard
        b.bind(.jump, to: .rightShoulder)
        let data = try JSONEncoder().encode(b)
        #expect(String(decoding: data, as: UTF8.self).contains("rightShoulder"))
        #expect(try JSONDecoder().decode(PadBindings.self, from: data) == b)
    }

    @Test("A file with an unknown button or a missing action keeps the rest")
    func tolerant() throws {
        let b = try JSONDecoder().decode(PadBindings.self,
                                         from: Data(#"{ "jump": "paddle4", "crouch": "north" }"#.utf8))
        #expect(b[.jump] == .south)
        #expect(b[.crouch] == .north)
        #expect(b[.sprint] == .leftStick)
    }

    /// A settings file from before pads could be rebound has no `padBindings` at all.
    @Test("Settings from before pad bindings existed still load")
    func olderSettings() throws {
        let s = try JSONDecoder().decode(PlayerSettings.self,
                                         from: Data(#"{ "bindings": { "forward": "I" } }"#.utf8))
        #expect(s.padBindings == .standard)
        #expect(s.bindings[.forward] == KeyCode(named: "I"))
    }
}

/// **The real pad path, with a pad nobody is holding.** `GCController.withExtendedGamepad()` makes one
/// whose buttons are set from code; `useGamepad` points `InputState` at it.
@MainActor
@Suite("Input state with a pad")
struct InputStatePadTests {

    private func rig() -> (InputState, GCExtendedGamepad) {
        let input = InputState()
        let pad = GCController.withExtendedGamepad().extendedGamepad!
        input.useGamepad(pad)
        return (input, pad)
    }

    @Test("A supplied pad counts as connected, and its names come through")
    func connected() {
        let (input, pad) = rig()
        #expect(input.isGamepadConnected)
        #expect(PadButton.south.name(on: pad) == "A", "\(PadButton.south.name(on: pad))")
        #expect(PadButton.south.name(on: nil) == "Cross / A")
    }

    @Test("The default buttons do what the convention says")
    func defaults() {
        let (input, pad) = rig()
        pad.buttonA.setValue(1)
        #expect(input.isJumpHeld)
        pad.buttonA.setValue(0)
        pad.buttonB.setValue(1)
        input.pollFrame()
        #expect(input.isCrouching)
    }

    @Test("A rebound jump moves to its new button and leaves the old one")
    func reboundJump() {
        let (input, pad) = rig()
        input.padBindings.bind(.jump, to: .rightShoulder)
        pad.buttonA.setValue(1)
        #expect(!input.isJumpHeld, "Cross still jumped")
        pad.buttonA.setValue(0)
        pad.rightShoulder.setValue(1)
        #expect(input.isJumpHeld)
    }

    /// The press edge moves with the binding — a held button does not strobe the crouch.
    @Test("A rebound crouch toggles on its press, once")
    func reboundCrouch() {
        let (input, pad) = rig()
        input.padBindings.bind(.crouch, to: .north)
        pad.buttonB.setValue(1)
        input.pollFrame()
        #expect(!input.isCrouching, "Circle still crouched")
        pad.buttonB.setValue(0)
        pad.buttonY.setValue(1)
        input.pollFrame()
        input.pollFrame()
        #expect(input.isCrouching)
        pad.buttonY.setValue(0)
        input.pollFrame()
        pad.buttonY.setValue(1)
        input.pollFrame()
        #expect(!input.isCrouching)
    }

    @Test("Presses are reported, once, whatever they are bound to")
    func pressesReported() {
        let (input, pad) = rig()
        pad.buttonX.setValue(1)
        input.pollFrame()
        #expect(input.padButtonsPressed == [.west])
        input.pollFrame()
        #expect(input.padButtonsPressed.isEmpty, "a held button was reported as pressed again")
        pad.buttonMenu.setValue(1)
        input.pollFrame()
        #expect(input.padMenuPressed)
    }

    /// **A menu that has the pad must not crouch the player behind it.**
    @Test("With pad actions off, presses are reported and nothing acts")
    func menuHasThePad() {
        let (input, pad) = rig()
        input.acceptsPadActions = false
        pad.buttonB.setValue(1)
        pad.buttonA.setValue(1)
        input.pollFrame()
        #expect(input.padButtonsPressed.contains(.east))
        #expect(!input.isCrouching)
        #expect(!input.isJumpHeld)
    }

    @Test("Sprint follows its binding, and steadies while aiming")
    func sprintFollows() {
        let (input, pad) = rig()
        input.padBindings.bind(.sprint, to: .leftShoulder)     // swaps with brace
        pad.leftTrigger.setValue(1)                           // aiming
        pad.leftShoulder.setValue(1)
        input.pollFrame()
        #expect(input.isSteadying)
        pad.leftShoulder.setValue(0)
        pad.leftThumbstickButton?.setValue(1)                 // L3 is brace now
        input.pollFrame()
        #expect(!input.isSteadying)
        #expect(input.isBraced)
    }

    @Test("Handing the pad back to the system forgets the supplied one")
    func handBack() {
        let (input, _) = rig()
        input.useGamepad(nil)
        #expect(input.gamepad == GCController.current?.extendedGamepad)
    }
}
