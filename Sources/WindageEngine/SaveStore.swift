//
//  SaveStore.swift
//  WindageEngine
//

import Foundation

/// Somewhere to keep what a game remembers between runs.
///
/// ### Why the engine owns this and not each title
///
/// **The engine's distribution rule says it may never assume a writable location outside its
/// container** — it has to run sandboxed or not, because the *title* is what gets distributed and it
/// may go to the App Store. That rule is easy to state and easy to break: the natural thing to write
/// is a path, and a path beside the executable works right up until someone sandboxes the app.
///
/// So there is one place that knows where a game may write, and it is here. `Application Support`
/// resolves correctly under a sandbox *and* outside one, which is the whole requirement.
///
/// ### Atomic, because a crash mid-write is a corrupted save
///
/// Writing over the live file leaves a truncated one if the process dies partway. `Data.write` with
/// `.atomic` writes a temporary and renames, and rename is atomic on APFS — so the save is either
/// the old one or the new one, never half of either.
public nonisolated struct SaveStore<Value: Codable & Sendable>: Sendable {

    /// The folder everything for this game goes in — named, so two games on one machine do not
    /// collide and so a person can find and delete it.
    public let container: String

    /// The file's name inside that folder, without extension.
    public let name: String

    public init(container: String, name: String) {
        self.container = container
        self.name = name
    }

    /// Where the file lives. Created on demand — asking for the URL does not write anything.
    public var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(container, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(name).json")
    }

    /// What was saved, or `nil` if there is nothing or it cannot be read.
    ///
    /// **Returns `nil` rather than throwing on a bad file, deliberately.** A save that will not
    /// decode — written by an older build, or truncated — must not stop the game starting. Losing a
    /// high score is a disappointment; refusing to launch is a bug report.
    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// Remove the file. Used by "reset progress", and by tests that must not leave one behind.
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
