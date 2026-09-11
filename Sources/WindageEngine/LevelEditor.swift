//
//  LevelEditor.swift
//  WindageEngine
//

import Foundation
import simd

/// Editing a level, without a window.
///
/// ### Why the editing lives here and not in the tool that draws it
///
/// **Everything an editor actually *is* — a selection, a set of operations, an undo stack and a
/// dirty flag — has nothing to do with rendering, and everything to do with the format.** Put it in
/// the viewport and it can only be tested by clicking; put it here and the whole thing runs in
/// `swift test` in milliseconds, which is the same argument the studio makes for splitting a game's
/// logic out of its app target.
///
/// It also means the *game* that ships is not the editor. A title can embed one, a separate tool can
/// drive one, and neither has to reimplement what "nudge the selected thing 0.5 m" means.
///
/// ### What it deliberately is not
///
/// No gizmos, no snapping-to-other-geometry, no multi-select, no prefabs, no scene graph. Those are
/// the parts nobody can design correctly before a second game has pushed on them — the same rule the
/// rest of this engine is built under. What is here is the smallest set that makes a level file
/// editable by pointing at it rather than by typing coordinates.
public nonisolated struct LevelEditor {

    /// The level being edited.
    public private(set) var level: Level

    /// Which placement is selected, if any. An index into ``Level/placements``.
    public private(set) var selection: Int?

    /// Whether there are changes not yet written to disk.
    ///
    /// **Tracked rather than inferred by comparing to the file.** A comparison says "different",
    /// which is also true after an undo back to the original — and an editor that claims unsaved
    /// changes when there are none trains people to ignore it.
    public private(set) var isDirty = false

    /// How far one nudge moves something, in metres.
    public static let nudge: Float = 0.5
    /// How far one turn rotates something, in radians. 15°, so twenty-four of them is a full circle
    /// and a right angle is reachable exactly.
    public static let turn: Float = .pi / 12

    private var undoStack: [Level] = []
    private var redoStack: [Level] = []

    /// How many steps back an editor remembers. Deep enough to undo a bad idea, shallow enough that
    /// a level of a few thousand placements does not sit in memory a hundred times over.
    public static let undoDepth = 64

    public init(level: Level) {
        self.level = level
    }

    // MARK: - Selection

    public mutating func select(_ index: Int?) {
        guard let index else { selection = nil; return }
        selection = level.placements.indices.contains(index) ? index : nil
    }

    /// The selected placement, if there is one.
    public var selected: Level.Placement? {
        guard let selection, level.placements.indices.contains(selection) else { return nil }
        return level.placements[selection]
    }

    // MARK: - Operations

    /// Move the selection. Positions are level-space; the caller decides what "right" means on screen.
    public mutating func move(by delta: SIMD3<Float>) {
        edit { $0.position += delta }
    }

    public mutating func rotate(by radians: Float) {
        edit { $0.yaw += radians }
    }

    /// Scale, clamped away from zero — a placement scaled to nothing cannot be selected again, which
    /// is a way to lose something with no way to get it back except undo.
    public mutating func scale(by factor: Float) {
        edit { $0.scale = min(max($0.scale * factor, 0.05), 100) }
    }

    public mutating func setAnchor(_ anchor: Level.Anchor) {
        edit { $0.anchor = anchor }
    }

    /// Duplicate the selection, offset so the copy is visibly not the original, and select the copy.
    public mutating func duplicate() {
        guard let index = selection, level.placements.indices.contains(index) else { return }
        record()
        var copy = level.placements[index]
        copy.position += SIMD3(LevelEditor.nudge * 2, 0, LevelEditor.nudge * 2)
        level.placements.insert(copy, at: index + 1)
        selection = index + 1
    }

    public mutating func delete() {
        guard let index = selection, level.placements.indices.contains(index) else { return }
        record()
        level.placements.remove(at: index)
        // Selecting the neighbour rather than nothing: deleting a run of things one at a time is the
        // common case, and re-picking after every one is the tedium that makes people stop tidying.
        selection = level.placements.isEmpty ? nil : min(index, level.placements.count - 1)
    }

    /// Add a placement at a point, and select it — carrying a lamp if it is given one, so a brazier
    /// dropped into a level arrives lit rather than cold.
    public mutating func add(mesh: String, at position: SIMD3<Float>, tags: [String] = [],
                             light: PunctualLight? = nil) {
        record()
        level.placements.append(Level.Placement(mesh: mesh, position: position, tags: tags, light: light))
        selection = level.placements.count - 1
    }

    /// Add another of a kind of thing — one of ``Level/kinds`` — at a point on the ground, and select it.
    ///
    /// **Everything but the place comes with it**: its height under its anchor, scale, tags, surface
    /// and lamp. That is the difference from ``add(mesh:at:tags:light:)``, which knows only a mesh — a
    /// brazier added by name arrives cold and walk-through; one added by kind arrives lit and solid.
    public mutating func add(_ kind: Level.Placement, at point: SIMD2<Float>, yaw: Float = 0) {
        record()
        var placement = kind
        placement.position = SIMD3(point.x, kind.position.y, point.y)
        placement.yaw = yaw
        level.placements.append(placement)
        selection = level.placements.count - 1
    }

    // MARK: - The selection's lamp
    //
    // **A lamp belongs to a placement** — see ``Level/Placement/light`` — so these edit the selection's
    // rather than a free-standing light, and moving, turning, copying or deleting the placement already
    // does the right thing to it. What was missing was a way to give one, take one away, and set the
    // two things a person adjusts by eye: how high it hangs and how bright it is.
    //
    // **An operation that changes nothing records nothing.** Brightening a placement with no lamp
    // is a no-op, not an undo step and an unsaved change.

    /// How far one press raises or lowers a lamp, in metres.
    public static let lampRaise: Float = 0.1

    /// How much one press brightens a lamp. **A third of a stop** — 2^⅓, three presses to double —
    /// because brightness is judged in ratios, like exposure: a fixed step of +5 is a leap on a candle
    /// and nothing on a floodlight.
    public static let lampBrighten: Float = pow(2, 1.0 / 3)

    /// The brightest and dimmest a lamp can be set, as radiant intensity. **Not zero**, for the reason
    /// ``scale(by:)`` is not: a lamp dimmed to nothing is still there, casting nothing, with no way to
    /// see it to fix it.
    public static let lampIntensityRange: ClosedRange<Float> = 0.5...5000

    /// Give the selection a lamp, replace the one it has, or take it away with `nil`.
    ///
    /// The lamp is in the placement's own space: `position` is an offset from its origin.
    public mutating func setLight(_ light: PunctualLight?) {
        guard let selected, selected.light != light else { return }
        edit { $0.light = light }
    }

    /// Raise the selection's lamp — or lower it, with a negative distance — in **metres of the
    /// world**. The lamp's offset scales with its placement, so on a placement at twice the size the
    /// offset moves half as far; a key that moved it by different amounts on different things would
    /// be a key nobody could judge.
    public mutating func raiseLight(by metres: Float) {
        guard let selected, selected.light != nil, metres != 0 else { return }
        edit { $0.light!.position.y += metres / max($0.scale, 1e-3) }
    }

    /// Brighten the selection's lamp by a factor — below 1 dims it — within ``lampIntensityRange``.
    /// The colour keeps its hue: every channel scales together.
    public mutating func brightenLight(by factor: Float) {
        guard let light = selected?.light, factor > 0, factor != 1 else { return }
        let intensity = max(light.colour.max(), 1e-6)
        let wanted = min(max(intensity * factor, LevelEditor.lampIntensityRange.lowerBound),
                         LevelEditor.lampIntensityRange.upperBound)
        guard wanted != intensity else { return }
        edit { $0.light!.colour *= wanted / intensity }
    }

    private mutating func edit(_ change: (inout Level.Placement) -> Void) {
        guard let index = selection, level.placements.indices.contains(index) else { return }
        record()
        change(&level.placements[index])
    }

    // MARK: - Undo

    private mutating func record() {
        undoStack.append(level)
        if undoStack.count > LevelEditor.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(level)
        level = previous
        clampSelection()
        isDirty = true
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(level)
        level = next
        clampSelection()
        isDirty = true
    }

    private mutating func clampSelection() {
        if let selection, !level.placements.indices.contains(selection) {
            self.selection = level.placements.isEmpty ? nil : level.placements.count - 1
        }
    }

    // MARK: - Saving

    /// Write the level out and clear the dirty flag.
    public mutating func save(to url: URL) throws {
        try level.encoded().write(to: url)
        isDirty = false
    }
}
