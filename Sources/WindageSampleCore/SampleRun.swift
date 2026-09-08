//
//  SampleRun.swift
//  WindageSampleCore
//

import Foundation
import simd
import WindageEngine

/// **The game part of the sample game.** State that persists across frames, a way to win, a way to
/// lose, and something remembered after you quit.
///
/// The walkthrough proved the engine could *load and draw* a level. It could not say whether the
/// engine supports a game **loop** — anything with state that survives a frame, a pause that is not
/// a stall, an outcome, or progress kept between runs. That is a different class of gap, and this is
/// the smallest thing that opens it.
///
/// It is a fetch quest, on purpose: touch every marked crate before the clock runs out. Nothing here
/// is interesting except that all of it has to work.
public nonisolated struct SampleRun {

    public enum Mode: Equatable {
        case playing
        case paused
        case won(seconds: Double)
        case lost
    }

    /// What is kept between runs. **A version field from the start**, because the first save format
    /// that needs changing is always one that did not have one.
    /// `nonisolated` because a save is data, and `SaveStore` is too — the sample's target defaults
    /// to `MainActor`, and a main-actor `Codable` conformance cannot satisfy a `Sendable` one.
    public nonisolated struct Progress: Codable, Equatable, Sendable {
        public var version = 1
        public var bestSeconds: Double?
        public var runs = 0
        public var wins = 0

        public init() {}
    }

    public static let store = SaveStore<Progress>(container: "WindageSample", name: "progress")

    /// Seconds allowed. Generous — a sample that is hard to beat is a sample nobody finishes, and
    /// then the win state never gets exercised.
    public static let timeLimit: Double = 90

    /// How near counts as touching one, in metres.
    ///
    /// **Measured to the crate's centre, so it has to clear the crate's own half-width.** At 2.5 m a
    /// crate 1.5 m across could be stood against and not collected — driven in-app, the player ended
    /// up 3.2 m from the centre, visibly touching it, and nothing happened.
    public static let reach: Float = 3.5

    public private(set) var mode: Mode = .playing
    public private(set) var elapsed: Double = 0
    public private(set) var progress: Progress

    /// The objectives, and which are done. Index-parallel to the level's `"objective"` markers.
    public private(set) var objectives: [SIMD3<Float>]
    public private(set) var collected: [Bool]

    public var remaining: Double { max(0, SampleRun.timeLimit - elapsed) }
    public var found: Int { collected.filter { $0 }.count }
    public var isOver: Bool { if case .playing = mode { return false }; if case .paused = mode { return false }; return true }

    public init(objectives: [SIMD3<Float>]) {
        self.objectives = objectives
        self.collected = Array(repeating: false, count: objectives.count)
        self.progress = SampleRun.store.load() ?? Progress()
    }

    /// One simulation step.
    ///
    /// **A pause is "do not advance", not "stop the loop".** The frame loop keeps running — the
    /// scene still draws, the HUD still updates, the window still resizes — which is why pausing is
    /// a game's decision and not something the engine has to provide.
    public mutating func step(deltaTime: Double, playerAt position: SIMD3<Float>) {
        guard mode == .playing else { return }

        elapsed += deltaTime
        for (index, objective) in objectives.enumerated() where !collected[index] {
            // Distance in the ground plane: the player's eye is 1.7 m up and the objective sits on
            // the floor, so a 3D distance would need a taller reach for the same feel.
            let flat = SIMD2(position.x - objective.x, position.z - objective.z)
            if simd_length(flat) <= SampleRun.reach {
                collected[index] = true
            }
        }

        if collected.allSatisfy({ $0 }) && !objectives.isEmpty {
            finish(won: true)
        } else if elapsed >= SampleRun.timeLimit {
            finish(won: false)
        }
    }

    private mutating func finish(won: Bool) {
        mode = won ? .won(seconds: elapsed) : .lost
        progress.runs += 1
        if won {
            progress.wins += 1
            if progress.bestSeconds == nil || elapsed < progress.bestSeconds! {
                progress.bestSeconds = elapsed
            }
        }
        // **Written when the run ends, not every frame.** A save per frame is a write per frame, and
        // the only thing it buys is remembering a run nobody finished.
        try? SampleRun.store.save(progress)
    }

    public mutating func togglePause() {
        switch mode {
        case .playing: mode = .paused
        case .paused: mode = .playing
        default: break                      // a finished run has nothing to pause
        }
    }

    /// Start again, keeping what was learned across runs.
    public mutating func restart() {
        mode = .playing
        elapsed = 0
        collected = Array(repeating: false, count: objectives.count)
    }
}
