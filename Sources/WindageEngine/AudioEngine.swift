//
//  AudioEngine.swift
//  WindageEngine
//

import AVFoundation
import simd

/// Positional one-shot audio.
///
/// **Spatialised from the start, not stereo panning bolted on later.** A game about distance needs
/// sound to carry distance: a plate hit at 800 m should arrive from where the plate is and sound
/// like it is 800 m away. `AVAudioEnvironmentNode` does the head-related work; what a title supplies
/// is a listener each frame and a world position per sound.
///
/// **Deliberately one-shots only.** No music, no loops, no buses, no mixing groups. Those arrive
/// when a title needs them and can show what shape they should be.
///
/// > **A landmine worth knowing before adding any AVFoundation callback here.** This type is
/// > main-actor-isolated like everything else in the engine, and a closure written inside one of its
/// > methods *inherits that isolation*. AVFoundation calls taps and completion handlers on a
/// > realtime audio thread, so such a closure trips the actor assertion and takes the process down
/// > — `_dispatch_assert_queue_fail`, on `RealtimeMessenger.mServiceQueue`, with no mention of
/// > actors anywhere in the crash. Mark any callback `@Sendable` and give it its own thread-safe
/// > storage. Nothing here uses one today, which is the only reason this is a note and not a bug.
public final class AudioEngine {

    /// Voices that can overlap. Beyond this the oldest is reused, because a game that runs out of
    /// voices silently drops the *newest* sound — which is always the one that just happened and
    /// therefore the one that mattered.
    public static let voiceCount = 16

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    public init?() {
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        // Distance attenuation in metres, matching the world's units.
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 8
        environment.distanceAttenuationParameters.maximumDistance = 2000
        environment.distanceAttenuationParameters.rolloffFactor = 0.9
        // **`.sphericalHead`, not `.auto`.** On a stereo output `.auto` resolves to HRTF, and sixteen
        // HRTF-spatialised voices is a real load on the audio render thread — which surfaces as
        // `HALC_ProxyIOContext: skipping cycle due to overload`, the one CoreAudio line in this
        // project's console noise that is *not* noise. Spherical head keeps the distance attenuation
        // and the directional cue a game actually reads at a fraction of the cost; binaural accuracy
        // is not what tells a player which way a shot came from at 400 m.
        environment.renderingAlgorithm = .sphericalHead

        // Mono voices: a spatialiser needs a point source, and a stereo file already has a position
        // baked into it that would fight the one being applied.
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
                                       channels: 1)
        for _ in 0..<AudioEngine.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: environment, format: monoFormat)
            players.append(player)
        }

        do {
            try engine.start()
        } catch {
            print("WindageEngine: audio engine failed to start: \(error)")
            return nil
        }
        players.forEach { $0.play() }
    }

    /// Loads a sound and keeps it decoded in memory.
    ///
    /// One-shots are short and are needed *now*; streaming them would add latency to exactly the
    /// sounds that must be immediate.
    ///
    /// **`bundle` has no default, deliberately.** It used to default to `.main`, which is right for
    /// an app bundle and wrong for a SwiftPM executable — there `.main` is the executable itself and
    /// holds no resources, so every load failed and printed. There is no default that is right for
    /// both, and a default that is silently wrong for one of them is worse than making every caller
    /// say where its sounds are. An app passes `.main`; a package target passes `.module`.
    @discardableResult
    public func load(_ name: String, withExtension ext: String = "wav", bundle: Bundle) -> Bool {
        guard buffers[name] == nil else { return true }
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else {
            print("WindageEngine: could not load sound \(name).\(ext)")
            return false
        }
        buffers[name] = buffer
        return true
    }

    /// Where the ears are. Call once per frame.
    public func updateListener(position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>) {
        environment.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
    }

    /// Plays a sound at a world position.
    ///
    /// - Parameter delay: seconds to wait first. **The reason this exists:** sound travels at about
    ///   343 m/s, so an impact 800 m away is heard nearly two and a half seconds after it happens.
    ///   In most games that is a detail; in one built around long shots it is the feedback loop
    ///   itself, and the wait is the point.
    public func play(_ name: String, at position: SIMD3<Float>, volume: Float = 1, delay: Float = 0) {
        guard let buffer = buffers[name] else { return }

        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count

        player.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        player.volume = volume
        player.renderingAlgorithm = .auto

        let start = {
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay), execute: start)
        } else {
            start()
        }
    }

    /// Plays without a position — for anything that happens *to the player* rather than in the
    /// world, where spatialising it would only make it quieter and further away.
    public func play(_ name: String, volume: Float = 1) {
        guard let buffer = buffers[name] else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count

        // At the listener, so distance attenuation leaves it alone.
        player.position = environment.listenerPosition
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    public func stop() {
        players.forEach { $0.stop() }
        engine.stop()
    }
}
