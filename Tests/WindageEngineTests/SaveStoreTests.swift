import Testing
import Foundation
@testable import WindageEngine

struct SaveStoreTests {

    private struct Progress: Codable, Equatable, Sendable {
        var bestSeconds: Double
        var runs: Int
    }

    private func store() -> SaveStore<Progress> {
        SaveStore(container: "WindageEngineTests", name: "progress-\(UUID().uuidString)")
    }

    @Test("Nothing saved reads as nothing, not as a failure")
    func emptyLoad() {
        let store = self.store()
        #expect(store.load() == nil)
        store.clear()
    }

    @Test("What goes in comes out")
    func roundTrip() throws {
        let store = self.store()
        defer { store.clear() }
        let progress = Progress(bestSeconds: 42.5, runs: 3)
        try store.save(progress)
        #expect(store.load() == progress)
    }

    @Test("Saving again replaces")
    func overwrite() throws {
        let store = self.store()
        defer { store.clear() }
        try store.save(Progress(bestSeconds: 10, runs: 1))
        try store.save(Progress(bestSeconds: 9, runs: 2))
        #expect(store.load() == Progress(bestSeconds: 9, runs: 2))
    }

    /// **A save that will not decode must not stop the game starting.** Losing a high score is a
    /// disappointment; refusing to launch is a bug report.
    @Test("A corrupt save reads as nothing rather than throwing")
    func corruptSave() throws {
        let store = self.store()
        defer { store.clear() }
        try Data("this is not json".utf8).write(to: store.url)
        #expect(store.load() == nil)
    }

    @Test("Clearing removes the file")
    func clearing() throws {
        let store = self.store()
        try store.save(Progress(bestSeconds: 1, runs: 1))
        #expect(FileManager.default.fileExists(atPath: store.url.path))
        store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    /// The container is what keeps two games on one machine from overwriting each other.
    @Test("Different containers are different files")
    func containersAreSeparate() throws {
        // Both under one container the suite cleans up, rather than two it leaves behind — a test
        // that litters Application Support is a test that changes the machine it runs on.
        let a = SaveStore<Progress>(container: "WindageEngineTests/a", name: "p")
        let b = SaveStore<Progress>(container: "WindageEngineTests/b", name: "p")
        defer { a.clear(); b.clear() }
        try a.save(Progress(bestSeconds: 1, runs: 1))
        try b.save(Progress(bestSeconds: 2, runs: 2))
        #expect(a.load()?.bestSeconds == 1)
        #expect(b.load()?.bestSeconds == 2)
        #expect(a.url != b.url)
    }
}
