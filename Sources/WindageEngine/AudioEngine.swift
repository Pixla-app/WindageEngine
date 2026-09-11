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
/// **One-shots, and loops that belong to a place** — a brazier's crackle, a generator's hum — since
/// 0.10.2. Still no music, no buses and no mixing groups: those arrive when a title needs them.
///
/// ### Two spatialisers, because one distance curve cannot serve both
///
/// **The one-shots' curve was tuned for a shot heard across a range**: full volume out to 8 m, then
/// 90% of the inverse law. Put a brazier's crackle through it and it is as loud at 8 m as at arm's
/// length and still 43% at 20 m — two braziers fill a level with fire. Loops go through a second
/// spatialiser with the physical inverse law from 2 m: half as loud at twice the distance, which is
/// what a small, near sound does. Measured, not argued — see ``renderOffline(seconds:)``.
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
    /// The loops' spatialiser — see the type's notes.
    private let nearEnvironment = AVAudioEnvironmentNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let monoFormat: AVAudioFormat
    private var loops: [Int: AVAudioPlayerNode] = [:]
    private var idleLoopPlayers: [AVAudioPlayerNode] = []
    private var nextLoop = 0
    private let isOffline: Bool

    /// Where a loop's inverse falloff starts, in metres: full volume nearer than this, half at twice it.
    public static let loopReferenceDistance: Float = 2

    /// A loop that is playing. Hand it back to ``moveLoop(_:to:)`` and ``stopLoop(_:)``.
    public struct Loop: Hashable, Sendable {
        fileprivate let id: Int
    }

    /// An engine that plays through the output device.
    public convenience init?() {
        self.init(offline: nil)
    }

    /// **An engine with no device at all**, whose mix is pulled with ``renderOffline(seconds:)`` —
    /// for measuring what a game sounds like without anyone listening: how loud a loop is at a
    /// distance, whether it is still going after a minute. `AVAudioEngine`'s manual rendering mode.
    public convenience init?(offlineSampleRate sampleRate: Double) {
        self.init(offline: sampleRate)
    }

    private init?(offline sampleRate: Double?) {
        isOffline = sampleRate != nil
        if let sampleRate {
            // Before anything is attached: the engine must be stopped, and its format is fixed here.
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
                  (try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)) != nil
            else { return nil }
        }
        let rate = sampleRate ?? engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return nil }
        monoFormat = mono

        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.attach(nearEnvironment)
        engine.connect(nearEnvironment, to: engine.mainMixerNode, format: nil)
        nearEnvironment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        nearEnvironment.distanceAttenuationParameters.referenceDistance = AudioEngine.loopReferenceDistance
        nearEnvironment.distanceAttenuationParameters.maximumDistance = 200
        nearEnvironment.distanceAttenuationParameters.rolloffFactor = 1

        // Distance attenuation in metres, matching the world's units.
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 8
        environment.distanceAttenuationParameters.maximumDistance = 2000
        environment.distanceAttenuationParameters.rolloffFactor = 0.9
        // **Each voice renders `.auto` — HRTF on stereo output — and that is measured, not assumed.**
        // This line used to set `.sphericalHead` on the *environment* node, with a note that spherical
        // head "keeps the directional cue a game reads at a fraction of the cost". Neither half held:
        // the algorithm is a property of each source, so setting it here did nothing, and measured
        // offline a source 5 m to the right comes out **1.01× louder in the right ear under spherical
        // head, against 4.6× under HRTF** and 5.6× under `.auto`. A game that tells a player which way
        // a shot landed needs the second. (If sixteen HRTF voices ever overload the render thread —
        // `HALC_ProxyIOContext: skipping cycle` — the answer is fewer voices, not a model with no cue.)

        // Mono voices: a spatialiser needs a point source, and a stereo file already has a position
        // baked into it that would fight the one being applied.
        for _ in 0..<AudioEngine.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: environment, format: mono)
            // Per voice, where it takes effect — see above. Once here rather than on every play().
            player.renderingAlgorithm = .auto
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

    /// Loads a sound from samples already in memory — mono, at `sampleRate` — for a sound a game
    /// makes rather than ships, and for a test that wants a signal it knows exactly.
    @discardableResult
    public func load(_ name: String, samples: [Float], sampleRate: Double) -> Bool {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress!, count: samples.count) }
        buffers[name] = buffer
        return true
    }

    /// Where the ears are. Call once per frame.
    public func updateListener(position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>) {
        let point = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        let orientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
        // Both spatialisers hear from the same head.
        for node in [environment, nearEnvironment] {
            node.listenerPosition = point
            node.listenerVectorOrientation = orientation
        }
    }

    // MARK: - Loops

    /// Starts a sound looping at a world position, until ``stopLoop(_:)``.
    ///
    /// **Each loop starts somewhere different in its sound**, so two braziers playing the same
    /// crackle are not a single crackle in two places — which is what starting both at sample zero
    /// sounds like. Through the near spatialiser; see the type's notes.
    @discardableResult
    public func startLoop(_ name: String, at position: SIMD3<Float>, volume: Float = 1) -> Loop? {
        guard let buffer = buffers[name], buffer.frameLength > 0 else { return nil }
        let player = idleLoopPlayers.popLast() ?? makeLoopPlayer()
        player.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        player.volume = volume
        let id = nextLoop
        nextLoop += 1
        // A different starting point for every loop: Knuth's multiplicative hash of its number.
        let offset = AVAudioFrameCount((UInt64(id) &* 2_654_435_761) % UInt64(buffer.frameLength))
        if offset > 0, let tail = AudioEngine.frames(of: buffer, from: offset) {
            player.scheduleBuffer(tail, at: nil, options: [])
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        loops[id] = player
        return Loop(id: id)
    }

    public func moveLoop(_ loop: Loop, to position: SIMD3<Float>) {
        loops[loop.id]?.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
    }

    public func stopLoop(_ loop: Loop) {
        guard let player = loops.removeValue(forKey: loop.id) else { return }
        player.stop()
        idleLoopPlayers.append(player)
    }

    public func stopAllLoops() {
        for loop in loops.keys.map(Loop.init(id:)) { stopLoop(loop) }
    }

    public var loopCount: Int { loops.count }

    /// **Made on demand and kept**, unlike the one-shots' fixed ring: a level has as many loops as it
    /// has things that hum, and a voice stolen from a brazier by a footstep is a fire that goes out.
    private func makeLoopPlayer() -> AVAudioPlayerNode {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: nearEnvironment, format: monoFormat)
        // As the one-shots: a fire to your left should sound as if it is on your left.
        player.renderingAlgorithm = .auto
        return player
    }

    /// The frames of `buffer` from `start` to its end, as a buffer of their own.
    private static func frames(of buffer: AVAudioPCMBuffer, from start: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let count = buffer.frameLength - start
        guard count > 0, let tail = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
              let from = buffer.floatChannelData, let to = tail.floatChannelData else { return nil }
        tail.frameLength = count
        for channel in 0..<Int(buffer.format.channelCount) {
            to[channel].update(from: from[channel] + Int(start), count: Int(count))
        }
        return tail
    }

    // MARK: - Measuring

    /// Pulls `seconds` of the mix from an engine made with ``init(offlineSampleRate:)``, one array per
    /// output channel. Nil for an engine playing through a device.
    ///
    /// **What makes a sound checkable without ears.** Every level in this type — the loops' falloff,
    /// a loop still going after its buffer has come round — was measured through this before it was
    /// described.
    public func renderOffline(seconds: Double) -> [[Float]]? {
        guard isOffline else { return nil }
        let format = engine.manualRenderingFormat
        guard let block = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)
        else { return nil }
        let total = AVAudioFrameCount(seconds * format.sampleRate)
        var channels = [[Float]](repeating: [], count: Int(format.channelCount))
        var done: AVAudioFrameCount = 0
        while done < total {
            let wanted = min(block.frameCapacity, total - done)
            guard let status = try? engine.renderOffline(wanted, to: block), status == .success,
                  let data = block.floatChannelData else { return nil }
            for channel in channels.indices {
                channels[channel] += UnsafeBufferPointer(start: data[channel], count: Int(block.frameLength))
            }
            done += block.frameLength
        }
        return channels
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

    /// Everything this engine plays, 0…1 — the player's volume setting.
    ///
    /// **On the main mixer, after the spatialiser**, so it scales every voice by the same amount
    /// without touching the distance attenuation that says how far away each one is.
    public var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = min(max(newValue, 0), 1) }
    }

    public func stop() {
        stopAllLoops()
        players.forEach { $0.stop() }
        engine.stop()
    }
}
