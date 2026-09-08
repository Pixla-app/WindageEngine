import Testing
import Foundation
import simd
import WindageEngine
@testable import WindageSampleCore

/// **The sample's game loop, tested with no window.**
///
/// This is the reason the sample is split into a library and a thin app at all — the same split the
/// studio requires of a title. A win condition, a clock, a pause and a save are exactly the things
/// that go wrong quietly, and none of them need a drawable to check.
struct SampleRunTests {

    /// **Each test gets its own store.** Swift Testing runs tests in parallel and they all wrote one
    /// shared file, so results depended on which finished first — which is also why `SampleRun` takes
    /// its store rather than reaching for a global one.
    private func store() -> SaveStore<SampleRun.Progress> {
        SaveStore(container: "WindageSampleCoreTests", name: "progress-\(UUID().uuidString)")
    }

    private func run(objectives: Int = 3,
                     store: SaveStore<SampleRun.Progress>? = nil) -> SampleRun {
        SampleRun(objectives: (0..<objectives).map { SIMD3(Float($0) * 20, 0, 0) },
                  store: store ?? self.store())
    }

    @Test("A run starts playing with nothing found and the whole clock")
    func start() {
        let run = self.run()
        #expect(run.mode == .playing)
        #expect(run.found == 0)
        #expect(run.remaining == SampleRun.timeLimit)
        #expect(!run.isOver)
    }

    @Test("Walking onto an objective collects it, once")
    func collecting() {
        var run = self.run()
        run.step(deltaTime: 0.1, playerAt: SIMD3(0, 1.7, 0))
        #expect(run.found == 1)
        run.step(deltaTime: 0.1, playerAt: SIMD3(0, 1.7, 0))
        #expect(run.found == 1, "standing there should not collect the same crate twice")
    }

    /// The player's eye is 1.7 m up and a crate sits on the floor, so reach is measured in the ground
    /// plane — a 3D distance would need a larger number for the same feel and would then let you
    /// collect things from a storey above.
    @Test("Reach is measured on the ground, not through the air")
    func reachIgnoresHeight() {
        var run = self.run(objectives: 1)
        run.step(deltaTime: 0.1, playerAt: SIMD3(0, 40, 0))
        #expect(run.found == 1)
    }

    @Test("Collecting the last one wins, and records the time")
    func winning() {
        var run = self.run(objectives: 2)
        run.step(deltaTime: 1, playerAt: SIMD3(0, 0, 0))
        #expect(run.mode == .playing, "one of two is not a win")
        run.step(deltaTime: 2, playerAt: SIMD3(20, 0, 0))
        #expect(run.mode == .won(seconds: 3))
        #expect(run.isOver)
        #expect(run.progress.wins == 1)
        #expect(run.progress.bestSeconds == 3)
    }

    @Test("Running out of time loses")
    func losing() {
        var run = self.run()
        run.step(deltaTime: SampleRun.timeLimit + 1, playerAt: SIMD3(0, 0, -500))
        #expect(run.mode == .lost)
        #expect(run.remaining == 0)
        #expect(run.progress.wins == 0)
        #expect(run.progress.runs == 1)
    }

    /// **A pause is "do not advance", not "stop the loop".** The clock must not move and nothing must
    /// be collectable, but the frame loop keeps running — which is why this is the game's job.
    @Test("Pause freezes the clock and collection")
    func pausing() {
        var run = self.run()
        run.step(deltaTime: 5, playerAt: SIMD3(0, 0, -500))
        run.togglePause()
        let frozen = run.remaining
        run.step(deltaTime: 10, playerAt: SIMD3(0, 0, 0))
        #expect(run.remaining == frozen, "the clock ran while paused")
        #expect(run.found == 0, "a crate was collected while paused")
        run.togglePause()
        run.step(deltaTime: 1, playerAt: SIMD3(0, 0, 0))
        #expect(run.found == 1)
    }

    /// A finished run has nothing to pause — and a paused game-over screen you cannot leave is a
    /// hang with a label on it.
    @Test("A finished run cannot be paused")
    func pausingAfterTheEnd() {
        var run = self.run(objectives: 1)
        run.step(deltaTime: 1, playerAt: SIMD3(0, 0, 0))
        #expect(run.isOver)
        run.togglePause()
        #expect(run.mode != .paused)
    }

    @Test("Restart clears the run but keeps what was learned")
    func restarting() {
        var run = self.run(objectives: 1)
        run.step(deltaTime: 4, playerAt: SIMD3(0, 0, 0))
        #expect(run.progress.wins == 1)
        run.restart()
        #expect(run.mode == .playing)
        #expect(run.found == 0)
        #expect(run.remaining == SampleRun.timeLimit)
        #expect(run.progress.wins == 1, "restarting a run must not forget previous ones")
    }

    /// **The point of the save.** A second run in a new process sees the first one's best time.
    @Test("Progress survives into a new run")
    func progressPersists() {
        let store = self.store()
        defer { store.clear() }
        var first = SampleRun(objectives: [SIMD3(0, 0, 0)], store: store)
        first.step(deltaTime: 7, playerAt: SIMD3(0, 0, 0))
        #expect(first.progress.bestSeconds == 7)

        // A fresh value, as a relaunch would build.
        let second = SampleRun(objectives: [SIMD3(0, 0, 0)], store: store)
        #expect(second.progress.bestSeconds == 7)
        #expect(second.progress.runs == 1)
    }

    @Test("Only a faster run replaces the best")
    func bestOnlyImproves() {
        let store = self.store()
        defer { store.clear() }
        var run = SampleRun(objectives: [SIMD3(0, 0, 0)], store: store)
        run.step(deltaTime: 5, playerAt: SIMD3(0, 0, 0))
        run.restart()
        run.step(deltaTime: 30, playerAt: SIMD3(0, 0, 0))
        #expect(run.progress.bestSeconds == 5, "a slower run overwrote the best time")
        run.restart()
        run.step(deltaTime: 2, playerAt: SIMD3(0, 0, 0))
        #expect(run.progress.bestSeconds == 2)
    }

    /// A level with no objectives must not win instantly — `allSatisfy` on an empty array is `true`,
    /// which is the classic way an empty level reports itself complete.
    @Test("A level with no objectives does not win itself")
    func emptyLevel() {
        var run = SampleRun(objectives: [], store: self.store())
        run.step(deltaTime: 1, playerAt: .zero)
        #expect(run.mode == .playing)
    }

    @Test("The level's crates and its objective markers agree")
    func levelIsConsistent() {
        let level = SampleLevel.builtIn
        let markers = level.markers(ofKind: "objective")
        let crates = level.placements(tagged: "objective")
        #expect(markers.count == SampleLevel.cratePositions.count)
        #expect(crates.count == markers.count, "a crate with no marker cannot be collected")
        for (marker, crate) in zip(markers, crates) {
            #expect(marker.position.x == crate.position.x)
            #expect(marker.position.z == crate.position.z)
        }
    }
}
