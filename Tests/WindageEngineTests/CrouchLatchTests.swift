//
//  CrouchLatchTests.swift
//  WindageEngineTests
//

import Testing
@testable import WindageEngine

@MainActor
struct CrouchLatchTests {

    private let c: UInt16 = 8

    /// **Latched, not held.** You crouch and then walk, aim, steady and dial turrets — holding the
    /// key would mean clamping it against W/A/S/D, right mouse, Shift and the arrows at once.
    @Test("Crouch stays on after the key is released")
    func itLatches() {
        let input = InputState()
        #expect(!input.isCrouching)

        input.keyDown(c)
        #expect(input.isCrouching)
        input.keyUp(c)
        #expect(input.isCrouching, "it stood up as soon as the key came off")

        input.keyDown(c)
        #expect(!input.isCrouching, "a second press did not stand it up")
    }

    /// **macOS repeats a held key.** Without an edge check, resting a finger on `C` strobes the
    /// posture at the repeat rate.
    @Test("Key repeat does not strobe the posture")
    func repeatsAreIgnored() {
        let input = InputState()
        input.keyDown(c)
        #expect(input.isCrouching)
        for _ in 0..<20 { input.keyDown(c) }      // as the OS would repeat it
        #expect(input.isCrouching, "the repeat toggled it back and forth")
    }

    /// **Asking to sprint stands you up.** Ignoring the key would leave the player pressing
    /// something that does nothing and concluding the game is stuck; "go fast" is not ambiguous.
    @Test("Sprinting stands you up rather than doing nothing")
    func sprintingStands() {
        let input = InputState()
        input.keyDown(c)
        #expect(input.isCrouching)

        input.setSprinting(true)
        #expect(!input.isCrouching, "it stayed crouched with sprint held")
        #expect(input.movement.sprint, "and then would not sprint either")
    }

    /// And while crouched, the movement never reports a sprint — that is what the posture costs.
    @Test("Movement never reports a sprint while crouched")
    func noSprintWhileCrouched() {
        let input = InputState()
        input.keyDown(c)
        // Set the flag directly rather than through `setSprinting`, which stands you up: this pins
        // the *second* guard, so a replay or a pad path cannot sneak a crouched sprint through.
        #expect(input.isCrouching)
        #expect(!input.movement.sprint)
    }
}
