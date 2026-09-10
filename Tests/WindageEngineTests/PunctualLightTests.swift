//
//  PunctualLightTests.swift
//  WindageEngineTests
//

import Testing
import simd
@testable import WindageEngine

@MainActor
struct PunctualLightTests {

    private func lamp(at position: SIMD3<Float>,
                      colour: SIMD3<Float> = SIMD3(repeating: 10),
                      range: Float = 10) -> PunctualLight {
        PunctualLight(position: position, colour: colour, range: range)
    }

    /// **The range has to be a real edge.** A light still contributing where it is cut off draws a
    /// visible sphere on the floor.
    @Test("A light is exactly nothing at and beyond its range")
    func fallsToNothingAtRange() {
        let light = lamp(at: .zero, range: 10)
        #expect(light.attenuation(at: SIMD3(10, 0, 0)) == 0)
        #expect(light.attenuation(at: SIMD3(40, 0, 0)) == 0)
        #expect(light.attenuation(at: SIMD3(9.5, 0, 0)) > 0)
    }

    @Test("Falloff is inverse-square in the middle of the range")
    func fallsOffInverseSquare() {
        // A long range, so the window is close to 1 and the inverse square dominates.
        let light = lamp(at: .zero, range: 1000)
        let near = light.attenuation(at: SIMD3(2, 0, 0))
        let far = light.attenuation(at: SIMD3(4, 0, 0))
        #expect(abs(near / far - 4) < 0.05, "doubling the distance did not quarter the light")
    }

    @Test("Attenuation only ever decreases with distance")
    func attenuationIsMonotonic() {
        let light = lamp(at: .zero, range: 10)
        var previous = Float.greatestFiniteMagnitude
        for step in 1...200 {
            let value = light.attenuation(at: SIMD3(Float(step) * 0.06, 0, 0))
            #expect(value <= previous + 1e-6)
            previous = value
        }
    }

    /// A fragment exactly at a lamp's position is a division by zero, and the pixel that produces is
    /// not "very bright" — it is NaN, which draws black.
    @Test("Standing inside a light is bright, not NaN")
    func noSingularityAtTheLight() {
        let value = lamp(at: .zero).attenuation(at: .zero)
        #expect(value.isFinite && !value.isNaN)
        #expect(value > 0)
    }

    @Test("A light with no range lights nothing")
    func zeroRangeIsHarmless() {
        let dead = PunctualLight(position: .zero, colour: SIMD3(repeating: 10), range: 0)
        #expect(dead.attenuation(at: SIMD3(1, 0, 0)) == 0)
        #expect(dead.attenuation(at: .zero) == 0)
    }

    /// **What the probe this came from had wrong.** It ranked lights by falloff alone, so a candle at
    /// one metre outranked a floodlight at ten — and the floodlight was the one dropped.
    @Test("Influence weighs brightness, not only distance")
    func influenceAccountsForBrightness() {
        let candle = lamp(at: SIMD3(1, 0, 0), colour: SIMD3(repeating: 0.3), range: 40)
        let floodlight = lamp(at: SIMD3(10, 0, 0), colour: SIMD3(repeating: 400), range: 40)
        #expect(candle.attenuation(at: .zero) > floodlight.attenuation(at: .zero),
                "the candle should be the nearer of the two")
        #expect(floodlight.influence(at: .zero) > candle.influence(at: .zero),
                "the brighter light lost to the nearer one")
    }

    /// Green carries most of perceived brightness and blue almost none, so a blue lamp of the same
    /// numeric magnitude is the one to drop first.
    @Test("Luminance is weighted the way an eye is")
    func luminanceIsPerceptual() {
        let green = PunctualLight.luminance(SIMD3(0, 1, 0))
        let red = PunctualLight.luminance(SIMD3(1, 0, 0))
        let blue = PunctualLight.luminance(SIMD3(0, 0, 1))
        #expect(green > red && red > blue)
        #expect(abs(PunctualLight.luminance(SIMD3(repeating: 1)) - 1) < 1e-5)
    }

    /// A long wall whose centre is out of range still has an end inside it.
    @Test("A light reaches a box by its nearest point, not its centre")
    func reachesByNearestPoint() {
        let wall = BoundingBox(minimum: SIMD3(-20, 0, -0.5), maximum: SIMD3(20, 3, 0.5))
        let light = lamp(at: SIMD3(19, 1, 0), range: 5)
        #expect(light.reaches(wall), "one end of the wall is plainly lit")
        #expect(light.influence(at: wall.closestPoint(to: light.position)) > 0)

        let centre = (wall.minimum + wall.maximum) / 2
        #expect(light.influence(at: centre) == 0, "the centre is out of range, which is the trap")
    }
}

@MainActor
struct LightSetTests {

    private func lamps(_ count: Int, spacing: Float = 1) -> [PunctualLight] {
        (0..<count).map {
            PunctualLight(position: SIMD3(Float($0) * spacing, 0, 0),
                          colour: SIMD3(repeating: 10), range: 100)
        }
    }

    @Test("At most the budget comes back, strongest first")
    func budgetIsRespected() {
        let set = LightSet(lights: lamps(9), budget: 4)
        let chosen = set.affecting(SIMD3(-1, 0, 0))
        #expect(chosen.count == 4)
        // Nearest first: the lights are in a row and the point is off the near end.
        #expect(chosen.map(\.position.x) == [0, 1, 2, 3])
    }

    @Test("Lights out of range are not returned at all")
    func outOfRangeIsDropped() {
        let near = PunctualLight(position: .zero, colour: SIMD3(repeating: 10), range: 5)
        let far = PunctualLight(position: SIMD3(100, 0, 0), colour: SIMD3(repeating: 10), range: 5)
        let set = LightSet(lights: [near, far], budget: 4)
        #expect(set.affecting(SIMD3(1, 0, 0)) == [near])
        #expect(set.affecting(SIMD3(500, 0, 0)).isEmpty)
    }

    @Test("A budget of zero returns nothing rather than crashing")
    func zeroBudget() {
        #expect(LightSet(lights: lamps(4), budget: 0).affecting(.zero).isEmpty)
        #expect(LightSet(lights: lamps(4), budget: -3).affecting(.zero).isEmpty)
    }

    /// Selection per draw asks which lights matter to *this mesh*, so a light reaching any part of it
    /// counts.
    @Test("A box is lit by anything that reaches any part of it")
    func boxSelection() {
        let wall = BoundingBox(minimum: SIMD3(-20, 0, -0.5), maximum: SIMD3(20, 3, 0.5))
        let atEnd = PunctualLight(position: SIMD3(19, 1, 0), colour: SIMD3(repeating: 10), range: 5)
        let miles = PunctualLight(position: SIMD3(500, 1, 0), colour: SIMD3(repeating: 10), range: 5)
        let set = LightSet(lights: [atEnd, miles], budget: 4)
        #expect(set.affecting(wall) == [atEnd])
    }

    /// **The probe's real finding.** A hard budget cannot promise a smooth hand-over in an arbitrary
    /// arrangement — but where no more than the budget are meaningfully lit, nothing visible is ever
    /// dropped. That is a condition on the *level*, and this is what makes it checkable before it
    /// ships rather than after a flicker is reported.
    @Test("Over-subscription is detectable, and is a fact about the level")
    func overSubscription() {
        let tight = LightSet(lights: lamps(4, spacing: 0.5), budget: 4)
        #expect(!tight.isOverSubscribed(at: .zero))

        let crowded = LightSet(lights: lamps(7, spacing: 0.5), budget: 4)
        #expect(crowded.isOverSubscribed(at: .zero), "seven lights on top of each other fit a budget of four")

        // Spread far enough apart and the same seven are fine: only a few matter anywhere.
        let spread = LightSet(lights: lamps(7, spacing: 400), budget: 4)
        #expect(!spread.isOverSubscribed(at: .zero))
    }

    @Test("A level can be swept for the places that are over-subscribed")
    func sweepingALevel() {
        let set = LightSet(lights: lamps(7, spacing: 0.5), budget: 4)
        let bad = set.overSubscribedPoints(among: [.zero, SIMD3(1, 0, 0), SIMD3(900, 0, 0)])
        #expect(bad.count == 2)
        #expect(!bad.contains(SIMD3(900, 0, 0)))
    }
}
