//
//  TransformHierarchy.swift
//  WindageEngine
//

import simd

/// Things that hang off other things: a lamp on a hand, a turret on a hull, a sight on a rifle.
///
/// ### This is parenting, and it is deliberately not a scene graph
///
/// A scene graph is an object model — nodes that own children, own components, are looked up by name
/// and are the unit everything else in the engine is written against. That is a decision this engine
/// has not made and does not need to make, and the README says why. **What a game actually runs into
/// first is much smaller: one transform expressed relative to another**, resolved in the right order,
/// every frame.
///
/// So this owns no objects. It is a list of attachments and a list of matrices; what those matrices
/// belong to is the caller's business, and the same hierarchy can drive a drawable, a light and a
/// collision volume without knowing that any of them exist.
///
/// ### Half of it arrived with ``Skeleton``, and the missing half is the interesting one
///
/// A rig is already a hierarchy, resolved by ``SkeletonPose`` in one forward pass. What it cannot do
/// is reach *outside* itself — and the canonical case, a weapon in a hand, is exactly that: the
/// parent is a joint, inside a pose, that is itself positioned by an object's world transform.
///
/// ``Attachment/external(_:)`` is that case made first-class. A node attached externally takes its
/// parent's world transform from an array handed to ``refresh(attachedTo:)``, so the node's own local
/// transform stays what it should be — **the grip, authored once** — rather than being rewritten every
/// frame by a caller who has had to keep the grip somewhere else anyway.
///
/// ### Parent-first, checked rather than trusted
///
/// The same rule ``Skeleton`` enforces, for the same reason: a parent must come before its child, so
/// one forward pass resolves everything and nothing recurses. A hierarchy that violated it would
/// still produce a picture — with the child a frame behind the parent, which reads as a lag in the
/// animation rather than as a structural fault.
public nonisolated struct TransformHierarchy: Sendable {

    /// What a node hangs off.
    public enum Attachment: Sendable, Equatable {
        /// Nothing. Its local transform is its world transform.
        case world
        /// Another node of this hierarchy, which must appear **earlier** than this one.
        case node(Int)
        /// Something this hierarchy does not own — a joint of a posed character, a platform driven by
        /// another system. Indexes the array given to ``refresh(attachedTo:)``.
        case external(Int)
    }

    /// **Every fault here is a structural one, caught when the hierarchy is built.** None of them can
    /// be detected later by looking: each produces a transform that is merely wrong.
    public enum Fault: Error, CustomStringConvertible, Sendable {
        case countMismatch(attachments: Int, transforms: Int)
        case selfParent(node: Int)
        case parentAfterChild(node: Int, parent: Int)
        case unknownNode(node: Int, parent: Int)
        case unknownExternal(node: Int, external: Int, count: Int)

        public var description: String {
            switch self {
            case .countMismatch(let attachments, let transforms):
                "\(attachments) attachments against \(transforms) transforms"
            case .selfParent(let node):
                "node \(node) is attached to itself"
            case .parentAfterChild(let node, let parent):
                "node \(node) is attached to \(parent), which is resolved after it"
            case .unknownNode(let node, let parent):
                "node \(node) is attached to \(parent), which is not in this hierarchy"
            case .unknownExternal(let node, let external, let count):
                "node \(node) is attached to external \(external), and only \(count) were declared"
            }
        }
    }

    public let attachments: [Attachment]

    /// How many external transforms ``refresh(attachedTo:)`` will be given.
    ///
    /// **Declared up front so an out-of-range attachment is a load-time error.** Left to the call
    /// site it would be an index read at sixty hertz, and the cheapest thing to do with a bad one is
    /// substitute the identity — which puts the held object at the world origin, once, in a frame
    /// nobody was looking at.
    public let externalCount: Int

    /// Each node relative to whatever it hangs off.
    public var localTransforms: [matrix_float4x4]

    /// Where each node has ended up. Valid after ``refresh(attachedTo:)``.
    public private(set) var worldTransforms: [matrix_float4x4]

    public var count: Int { attachments.count }

    public init(attachments: [Attachment],
                localTransforms: [matrix_float4x4]? = nil,
                externalCount: Int = 0) throws {
        let locals = localTransforms
            ?? [matrix_float4x4](repeating: matrix_identity_float4x4, count: attachments.count)
        guard locals.count == attachments.count else {
            throw Fault.countMismatch(attachments: attachments.count, transforms: locals.count)
        }

        for (node, attachment) in attachments.enumerated() {
            switch attachment {
            case .world:
                continue
            case .node(let parent):
                guard parent != node else { throw Fault.selfParent(node: node) }
                guard parent >= 0, parent < attachments.count else {
                    throw Fault.unknownNode(node: node, parent: parent)
                }
                guard parent < node else { throw Fault.parentAfterChild(node: node, parent: parent) }
            case .external(let index):
                guard index >= 0, index < externalCount else {
                    throw Fault.unknownExternal(node: node, external: index, count: externalCount)
                }
            }
        }

        self.attachments = attachments
        self.externalCount = max(0, externalCount)
        self.localTransforms = locals
        self.worldTransforms = locals
    }

    /// Resolves every node's world transform, in one forward pass.
    ///
    /// - Parameter externals: the world transforms of the things outside this hierarchy that nodes
    ///   are attached to, in the order ``Attachment/external(_:)`` indexes. Must hold at least
    ///   ``externalCount`` of them.
    public mutating func refresh(attachedTo externals: [matrix_float4x4] = []) {
        precondition(externals.count >= externalCount,
                     "a hierarchy declaring \(externalCount) external attachments was given "
                     + "\(externals.count)")
        for node in 0..<attachments.count {
            let local = localTransforms[node]
            switch attachments[node] {
            case .world:              worldTransforms[node] = local
            case .node(let parent):   worldTransforms[node] = worldTransforms[parent] * local
            case .external(let index):worldTransforms[node] = externals[index] * local
            }
        }
    }

    public func worldTransform(of node: Int) -> matrix_float4x4 { worldTransforms[node] }
}

/// The same transform with its scale removed, leaving rotation and position.
///
/// ### Why a hierarchy needs this and a rig does not
///
/// **A child inherits its parent's scale, which is right for a limb and wrong for a held object.** A
/// rig exported from a package that works in centimeters carries a hundredfold scale down to the
/// wrist, and it belongs there — the arm is a hundred units long in that space. Hang a lantern off
/// the same matrix and the lantern is drawn at one percent of its size, in a place that is otherwise
/// correct, which reads as the wrong mesh rather than as the wrong space.
///
/// The alternative — an attachment flag that says "do not inherit scale" — puts a policy inside the
/// hierarchy that only some callers want. This is the same thing at the call site, where the caller
/// can see what it is attaching to.
///
/// **A mirrored basis stays mirrored.** Each axis is normalized, and nothing here tries to decide
/// that a negative determinant was a mistake; a shear is flattened onto its own axes, which is the
/// only thing it can mean once the scale is gone.
public nonisolated func matrix_without_scale(_ m: matrix_float4x4) -> matrix_float4x4 {
    func unit(_ column: SIMD4<Float>) -> SIMD4<Float> {
        let axis = SIMD3(column.x, column.y, column.z)
        let length = simd_length(axis)
        // A zero axis has no direction to preserve, and normalising it would make every component of
        // the matrix NaN — which draws nothing at all, from anywhere.
        guard length > 1e-6 else { return column }
        return SIMD4(axis / length, 0)
    }
    return matrix_float4x4(columns: (unit(m.columns.0), unit(m.columns.1), unit(m.columns.2),
                                     m.columns.3))
}
