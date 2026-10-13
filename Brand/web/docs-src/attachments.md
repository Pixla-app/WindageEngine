---
title: Hanging things off joints
description: Attach a lantern to a hand or a turret to a hull with TransformHierarchy, keep a thing's extent in a Volume, and hit-test volumes with a ray or a segment.
---
Some things are placed relative to other things: a lamp in a hand, a turret on a hull, a sight on a rifle. `TransformHierarchy` resolves one transform relative to another, in the right order, every frame. It owns no objects — it is a list of attachments and a list of matrices — so the same hierarchy can place a drawable, a light and a collision volume without knowing any of them exist.

## It is parenting, not a scene graph

A scene graph is an object model — nodes that own children and components, looked up by name. Windage Engine has not made that decision. What a game runs into first is much smaller, and this is that.

The same goes for what gets drawn. A `SceneObject` is a flat pair — an `MTKMesh` and a `Volume` — made with `SceneObject(loaded:transform:)`, which composes the mesh's `nodeTransform` in for you. There is no parent pointer on it.

## Building a hierarchy

Each node says what it hangs off, as a `TransformHierarchy.Attachment`:

| Case | Its parent |
| --- | --- |
| `.world` | nothing: its local transform is its world transform |
| `.node(Int)` | another node of this hierarchy, which must come **earlier** |
| `.external(Int)` | something the hierarchy does not own — a joint of a posed character, a platform driven by another system |

```swift
var hierarchy = try TransformHierarchy(attachments: [.world, .node(0), .node(1)],
                                       localTransforms: [hull, turretMount, barrelMount])
hierarchy.refresh()
let barrel = hierarchy.worldTransform(of: 2)
```

`localTransforms` is a `var`, so move a node by writing its local transform and calling `refresh(attachedTo:)` again. `worldTransforms` holds every result.

Every structural mistake — a count mismatch, a node attached to itself, a parent after its child, an unknown node or external — throws a `TransformHierarchy.Fault` when the hierarchy is built, because later it would only be a transform that is quietly wrong.

## Attaching to a joint

A rig is already a hierarchy, resolved by `SkeletonPose` (see [skeletons](skeletons.html)). What it cannot do is reach outside itself, and a thing in a hand is exactly that: its parent is a joint, inside a pose, placed by a character's world transform.

`.external(_:)` handles it. The node keeps **the grip, authored once**, as its local transform, and takes its parent's world transform from the array you hand to `refresh(attachedTo:)`. How many externals there will be is declared up front, so an out-of-range index is a load-time error rather than an object drawn at the origin in a frame nobody saw.

The sample's figures each carry a lantern. Once, at load, it finds a joint and builds one node per figure:

```swift
lanternJoint = joint   // from skeleton.index(ofJoint:), looked up once

lanterns = try? TransformHierarchy(
    attachments: figures.indices.map { .external($0) },
    localTransforms: Array(repeating: SampleGame.lanternGrip, count: figures.count),
    externalCount: figures.count)
```

Each frame, **after posing the figures**, it hands over each hand's world transform and places the lanterns:

```swift
rig.refresh(attachedTo: figures.map {
    matrix_without_scale($0.transform * $0.pose.modelTransform(ofJoint: joint))
})
for (slot, index) in lanternDrawables.enumerated() {
    let world = rig.worldTransform(of: slot)
    drawables[index].transform = world
    volumes[index].transform = world
}
```

The same matrix moves the drawable, its volume and its light. Placed from last step's pose, hand and lantern would be a frame apart.

### Strip the scale

A child inherits its parent's scale. That is right for a limb and wrong for a held object: a rig authored in centimeters carries a hundredfold scale down to the wrist, and a lantern hung off that matrix is drawn at one percent of its size, in a place that is otherwise correct. `matrix_without_scale(_:)` removes the scale and keeps rotation and position. It is a function you call, not a flag on the hierarchy, because whether to inherit scale is a decision about what is being attached, and only your game can see that. A mirrored basis stays mirrored.

### A grip is a number you set by looking

A joint's frame is not a promise about where the mesh was drawn. In the sample's figure, a grip worked out from the bind pose sits in the hand with the arm down, and floats above the head with the arm raised, because the drawn limb stops short of where the arithmetic says. Set the grip by looking at the character in the poses it will be in.

## Volume: an extent with no mesh

A `Volume` is a model-space `BoundingBox` (`local`) and a `transform`. It has no opinion about drawing, so something you only collide with or shoot at does not need a GPU mesh to be hit.

```swift
volumes.append(Volume(local: mesh.bounds, transform: matrix_identity_float4x4))
```

`worldBounds` is **computed from the transform every time it is read**, never stored, so a volume that moves is hit where it is. Its `worldBounds` are the solids [CharacterController](character-controller.html) collides with, and the boxes the sample [culls](culling.html) against.

Two hit tests run over an array of volumes and return the nearest `(index, distance)`, or nil:

- `Volume.firstHit(segmentFrom:to:against:)` — the segment a shot covers in one step. A round moves several meters a step, so testing only where it ended lets it pass through anything thinner.
- `Volume.firstHit(origin:direction:against:maxDistance:)` — a ray, for ranging or picking. The sample's editor picks with it:

```swift
let hit = Volume.firstHit(origin: origin, direction: camera.forward,
                          against: Array(volumes.prefix(levelVolumeCount)),
                          maxDistance: 200)
```

Use the same list for both, so what a reticle ranges on and what a round stops against agree.

## What it does not do

No scene graph, no lookup by name, no components and no "do not inherit scale" option. A node does not know what it places. A volume is an axis-aligned box in the world, so a turned thing's `worldBounds` is larger than the thing.
