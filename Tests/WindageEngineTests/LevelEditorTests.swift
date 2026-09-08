import Testing
import Foundation
import simd
@testable import WindageEngine

/// **All of it runs with no window**, which is the reason the editing lives in the engine rather
/// than in the viewport that draws it: an editor testable only by clicking is an editor nobody tests.
struct LevelEditorTests {

    private func editor() -> LevelEditor {
        LevelEditor(level: Level(name: "test", placements: [
            Level.Placement(mesh: "a", position: SIMD3(0, 0, 0)),
            Level.Placement(mesh: "b", position: SIMD3(10, 0, 0), yaw: 1, scale: 2),
            Level.Placement(mesh: "c", position: SIMD3(20, 0, 0)),
        ]))
    }

    @Test("Nothing happens without a selection")
    func operationsNeedASelection() {
        var editor = self.editor()
        let before = editor.level
        editor.move(by: SIMD3(1, 0, 0))
        editor.rotate(by: 1)
        editor.scale(by: 2)
        editor.delete()
        #expect(editor.level == before)
        #expect(!editor.isDirty, "an operation that did nothing must not claim unsaved changes")
    }

    @Test("Selecting out of range selects nothing rather than trapping")
    func selectionIsBoundsChecked() {
        var editor = self.editor()
        editor.select(99)
        #expect(editor.selection == nil)
        editor.select(-1)
        #expect(editor.selection == nil)
        editor.select(1)
        #expect(editor.selected?.mesh == "b")
    }

    @Test("Move, rotate and scale change only the selection")
    func operationsAffectOnlyTheSelection() {
        var editor = self.editor()
        editor.select(1)
        editor.move(by: SIMD3(0, 3, 0))
        editor.rotate(by: 0.5)
        editor.scale(by: 2)
        #expect(editor.selected?.position == SIMD3(10, 3, 0))
        #expect(editor.selected?.yaw == 1.5)
        #expect(editor.selected?.scale == 4)
        #expect(editor.level.placements[0].position == SIMD3(0, 0, 0))
        #expect(editor.level.placements[2].position == SIMD3(20, 0, 0))
    }

    /// **Scaling to nothing loses a placement**: it cannot be picked again, so the only way back is
    /// undo, and by the time anyone notices the undo is gone.
    @Test("Scale cannot reach zero")
    func scaleIsClamped() {
        var editor = self.editor()
        editor.select(0)
        for _ in 0..<50 { editor.scale(by: 0.1) }
        #expect((editor.selected?.scale ?? 0) >= 0.05)
        for _ in 0..<50 { editor.scale(by: 10) }
        #expect((editor.selected?.scale ?? .infinity) <= 100)
    }

    @Test("Delete selects the neighbour, not nothing")
    func deleteKeepsAWorkingSelection() {
        var editor = self.editor()
        editor.select(1)
        editor.delete()
        #expect(editor.level.placements.map(\.mesh) == ["a", "c"])
        #expect(editor.selected?.mesh == "c", "deleting a run one at a time should not need re-picking")
        editor.delete()
        editor.delete()
        #expect(editor.level.placements.isEmpty)
        #expect(editor.selection == nil, "an empty level cannot have something selected")
    }

    @Test("Duplicate offsets the copy and selects it")
    func duplicate() {
        var editor = self.editor()
        editor.select(0)
        editor.duplicate()
        #expect(editor.level.placements.count == 4)
        #expect(editor.selection == 1)
        #expect(editor.selected?.mesh == "a")
        #expect(editor.selected?.position != editor.level.placements[0].position,
                "a copy on top of the original cannot be told apart or picked")
    }

    @Test("Undo and redo walk the history")
    func undoRedo() {
        var editor = self.editor()
        #expect(!editor.canUndo)
        editor.select(0)
        editor.move(by: SIMD3(5, 0, 0))
        editor.move(by: SIMD3(5, 0, 0))
        #expect(editor.selected?.position == SIMD3(10, 0, 0))
        editor.undo()
        #expect(editor.selected?.position == SIMD3(5, 0, 0))
        editor.undo()
        #expect(editor.selected?.position == SIMD3(0, 0, 0))
        #expect(!editor.canUndo)
        editor.redo()
        #expect(editor.selected?.position == SIMD3(5, 0, 0))
    }

    /// A new edit abandons the redo branch — otherwise redo replays a future that no longer follows
    /// from the present.
    @Test("Editing after undo drops the redo branch")
    func editingClearsRedo() {
        var editor = self.editor()
        editor.select(0)
        editor.move(by: SIMD3(1, 0, 0))
        editor.undo()
        #expect(editor.canRedo)
        editor.move(by: SIMD3(0, 0, 1))
        #expect(!editor.canRedo)
    }

    /// Undo past a delete must not leave the selection pointing off the end.
    @Test("Undo repairs a selection that no longer exists")
    func undoClampsSelection() {
        var editor = self.editor()
        editor.select(2)
        editor.delete()
        editor.select(1)
        editor.undo()
        #expect(editor.selection.map { editor.level.placements.indices.contains($0) } ?? true)
    }

    @Test("Saving clears the dirty flag and round-trips")
    func saving() throws {
        var editor = self.editor()
        editor.select(1)
        editor.move(by: SIMD3(0, 0, 7))
        #expect(editor.isDirty)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-test-\(UUID().uuidString).json")
        try editor.save(to: url)
        #expect(!editor.isDirty)

        let reloaded = try Level.decode(from: try Data(contentsOf: url))
        #expect(reloaded == editor.level)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Adding puts a placement where it was asked for and selects it")
    func adding() {
        var editor = self.editor()
        editor.add(mesh: "new", at: SIMD3(1, 2, 3), tags: ["solid"])
        #expect(editor.selected?.mesh == "new")
        #expect(editor.selected?.position == SIMD3(1, 2, 3))
        #expect(editor.selected?.tags == ["solid"])
        editor.undo()
        #expect(editor.level.placements.count == 3)
    }
}

struct BoundingBoxContainsTests {
    private let box = BoundingBox(minimum: SIMD3(-1, 0, -1), maximum: SIMD3(1, 2, 1))

    @Test func insideAndOutside() {
        #expect(box.contains(SIMD3(0, 1, 0)))
        #expect(!box.contains(SIMD3(0, 3, 0)))
        #expect(!box.contains(SIMD3(2, 1, 0)))
        #expect(!box.contains(SIMD3(0, -0.1, 0)))
    }

    /// Hand-authored levels put everything on round numbers, so points land exactly on faces all the
    /// time — and "on the wall" reading as "outside it" is how a player ends up standing inside one.
    @Test func facesAndCornersCount() {
        #expect(box.contains(SIMD3(1, 0, -1)))
        #expect(box.contains(SIMD3(-1, 2, 1)))
        #expect(box.contains(SIMD3(0, 0, 0)))
    }
}

/// **The engine must not say another product's name.**
///
/// Its gamepad connect/disconnect messages were logged as `"Coldkeel: …"` — found by running the
/// sample, where a controller plugged in and the console announced a game that was not running. A
/// third party would have seen the same thing in their own app.
struct EngineIdentityTests {
    @Test func theEngineNamesItself() {
        #expect(Engine.name == "Windage Engine")
        #expect(!Engine.name.isEmpty)
    }
}
