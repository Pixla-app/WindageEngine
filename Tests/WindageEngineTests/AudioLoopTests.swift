//
//  AudioLoopTests.swift
//  WindageEngineTests
//

import Testing
import simd
@testable import WindageEngine

/// **Measured, because nobody here can listen.** An engine with no device, its mix pulled offline and
/// its level taken as RMS — the loops' falloff, the one-shots' for comparison, a loop outliving its
/// buffer, and silence after a stop.
@MainActor
@Suite("Audio — loops, measured offline")
struct AudioLoopTests {

    private static let rate = 48_000.0

    /// One second of noise at a fixed seed — a signal whose level is the same everywhere in it.
    private static let noise: [Float] = {
        var state: UInt32 = 0x9E37_79B9
        return (0..<48_000).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.6
        }
    }()

    private func engine() throws -> AudioEngine {
        let audio = try #require(AudioEngine(offlineSampleRate: AudioLoopTests.rate))
        #expect(audio.load("noise", samples: AudioLoopTests.noise, sampleRate: AudioLoopTests.rate))
        audio.updateListener(position: .zero, forward: SIMD3(0, 0, -1), up: SIMD3(0, 1, 0))
        return audio
    }

    /// The level of a stretch of the mix, both ears together.
    private func rms(_ audio: AudioEngine, seconds: Double) throws -> Float {
        let channels = try #require(audio.renderOffline(seconds: seconds))
        let all = channels.flatMap { $0 }
        return (all.reduce(0) { $0 + $1 * $1 } / Float(max(all.count, 1))).squareRoot()
    }

    /// Straight ahead, so both ears hear it alike and the level is only the distance.
    private func ahead(_ metres: Float) -> SIMD3<Float> { SIMD3(0, 0, -metres) }

    @Test("A loop falls off with the inverse law from 2 m: a quarter at 8, a tenth at 20")
    func loopFalloff() throws {
        let audio = try engine()
        let loop = try #require(audio.startLoop("noise", at: ahead(2)))
        _ = try rms(audio, seconds: 0.1)                    // let it settle
        let near = try rms(audio, seconds: 0.5)
        audio.moveLoop(loop, to: ahead(8))
        _ = try rms(audio, seconds: 0.1)
        let mid = try rms(audio, seconds: 0.5)
        audio.moveLoop(loop, to: ahead(20))
        _ = try rms(audio, seconds: 0.1)
        let far = try rms(audio, seconds: 0.5)
        print("AUDIO loop at 2/8/20 m: \(near), \(mid), \(far) → \(mid / near), \(far / near)")
        #expect(near > 0.01, "no sound at all: \(near)")
        #expect(abs(mid / near - 0.25) < 0.03, "8 m should be a quarter of 2 m: \(mid / near)")
        #expect(abs(far / near - 0.10) < 0.02, "20 m should be a tenth: \(far / near)")
    }

    /// **Why loops have their own spatialiser.** Through the one-shots' curve a sound at 20 m is still
    /// over half as loud as at 2 m — right for a shot across a range, wrong for a fire.
    ///
    /// > **And a measured quirk, not a model**: under HRTF a source *inside* its spatialiser's
    /// > reference distance is quieter, not flat — here 2 m reads 22% under 8 m, and the loops show
    /// > the same shape inside their 2 m. Beyond the reference the inverse law holds exactly, which is
    /// > what these assertions check.
    @Test("A one-shot through the range curve is over half as loud at 20 m as at 2, and follows its law past 8")
    func oneShotFalloffForComparison() throws {
        let audio = try engine()
        var levels: [Float] = []
        for metres: Float in [2, 8, 20] {
            audio.play("noise", at: ahead(metres))
            _ = try rms(audio, seconds: 0.3)
            levels.append(try rms(audio, seconds: 0.5))
            _ = try rms(audio, seconds: 0.3)                // let the voice finish
        }
        print("AUDIO one-shot at 2/8/20 m: \(levels) → \(levels[1] / levels[0]), \(levels[2] / levels[0])")
        #expect(abs(levels[2] / levels[1] - 8 / (8 + 0.9 * 12)) < 0.02, "the range curve from 8 to 20 m")
        #expect(levels[2] / levels[0] > 0.45, "a fire through this curve would carry: \(levels[2] / levels[0])")
    }

    @Test("A loop is still going, at the same level, long after its sound has come round")
    func loopKeepsGoing() throws {
        let audio = try engine()
        audio.startLoop("noise", at: ahead(2))
        _ = try rms(audio, seconds: 0.1)
        let first = try rms(audio, seconds: 0.5)
        _ = try rms(audio, seconds: 2.0)                    // twice round a one-second sound
        let later = try rms(audio, seconds: 0.5)
        #expect(abs(later / first - 1) < 0.05, "faded or stopped: \(first) then \(later)")
    }

    @Test("Stopping a loop silences it, and its voice is used again")
    func stopSilences() throws {
        let audio = try engine()
        let loop = try #require(audio.startLoop("noise", at: ahead(2)))
        _ = try rms(audio, seconds: 0.2)
        audio.stopLoop(loop)
        _ = try rms(audio, seconds: 0.05)
        #expect(try rms(audio, seconds: 0.3) < 1e-4)
        #expect(audio.loopCount == 0)
        #expect(audio.startLoop("noise", at: ahead(2)) != nil && audio.loopCount == 1)
    }

    /// **The cue a game about long shots reads**: which way an impact came from. Written to check a
    /// switch to the spherical-head model — and it failed: 1.01× louder in the near ear, where HRTF
    /// gives 4.6×. The switch was reverted; this stays, so the cue cannot quietly go missing again.
    @Test("A one-shot off to the right is louder in the right ear, far away as well as near — and a loop")
    func directionSurvives() throws {
        for (metres, loop) in [(Float(5), false), (400, false), (5, true)] {
            let audio = try engine()
            if loop { audio.startLoop("noise", at: SIMD3(metres, 0, 0)) } else { audio.play("noise", at: SIMD3(metres, 0, 0)) }
            _ = try #require(audio.renderOffline(seconds: 0.1))
            let channels = try #require(audio.renderOffline(seconds: 0.5))
            func level(_ c: [Float]) -> Float { (c.reduce(0) { $0 + $1 * $1 } / Float(max(c.count, 1))).squareRoot() }
            let left = level(channels[0]), right = level(channels[1])
            print("AUDIO \(loop ? "loop" : "one-shot") \(metres) m to the right: left \(left), right \(right), ratio \(right / max(left, 1e-9))")
            #expect(right > left * 1.5, "no left–right cue at \(metres) m: left \(left), right \(right)")
        }
    }
}
