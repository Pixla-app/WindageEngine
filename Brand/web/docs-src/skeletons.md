---
title: Skeletons and clips
description: Load a rigged character's skeleton and animation clips from USD, pose it each frame, cross-fade between clips and hand the joint palette to a vertex shader.
---
A skinned character is a mesh, the skeleton it was bound to, and clips that move the skeleton. `RigLoader` reads the skeleton and clips from USD, `SkeletonPose` poses them, and you get the matrices a vertex shader skins with. None of it needs a GPU, so all of it runs under `swift test`.

## The types

| Type | What it is |
| --- | --- |
| `Skeleton` | Structure only: joint paths, derived parentage, the rest pose and the inverse bind matrices. Loaded once, shared by every character wearing the rig. |
| `AnimationClip` | Keys for translation, rotation and scale, with the clip's own joint names. Each channel is a `JointTrack`. |
| `AnimationBinding` | Which of a rig's joints each of a clip's joints drives, matched **by path, once**. |
| `AnimationPlayhead` | A clip, its binding to a rig, and the time. |
| `SkeletonPose` | A rig with a pose on it, one per character, kept between frames. |
| `Rig` | What `RigLoader` returns: a `skeleton`, its `clips` and a `nodeTransform`. |

## Loading a rig

`RigLoader.load(named:withExtension:bundle:)` reads the skeleton and every clip from one file; `load(url:)` does the same from anywhere on disk. The extension defaults to `"usdc"`.

A real character usually arrives as one file per clip, and each of those files carries a whole copy of the mesh and the skeleton. Take the rig from the base file and only the clips from the others:

```swift
let rig = try RigLoader.load(named: "figure", withExtension: "usda",
                             clipFiles: ["figure-wave"], bundle: .module) {
    print("figure clips — \($0)")
}
```

`load(url:clipURLs:reportingTo:)` does the same from disk. Both:

- **Rename a file's only clip to the file's name**, so a game asks for `figure-wave`, not the exporter's name.
- **Drop and report a clip that drives none of the rig's joints** — otherwise it looks exactly like a character standing still.
- **Ignore the clip files' skeletons.** Their rest pose is wherever the exporter left the rig; merged, every joint a clip does not animate stands wrong.

`RigLoader.clips(named:withExtension:bundle:)` and `clips(url:)` read only animations; `Rig.adding(_:)` puts them on a rig. `rig.jointsNotDrivenBy(clip)` lists joints a clip ignores: empty is what you want.

Loading throws a `RigLoaderError` — `.assetNotFound`, `.noSkeleton`, `.conflictingGeometryBindTransforms` — or a `SkeletonError` for a missing or out-of-order parent or a bind transform that cannot be inverted, rather than drawing a limb in the wrong place.

## Posing a character

Make a pose and one playhead per clip when the character is placed:

```swift
var pose = SkeletonPose(skeleton: rig.skeleton)
var idle = AnimationPlayhead(clip: idleClip, skeleton: rig.skeleton)
var wave = AnimationPlayhead(clip: waveClip, skeleton: rig.skeleton)
```

A new pose starts at rest. A playhead loops by default; `looping: false` makes a one-shot that clamps and reports `isFinished`. Its `time` may run past `duration`.

Each frame, advance the playheads and pose the rig. One clip is `pose.set(to: idle)`. Two is a cross-fade, from the sample:

```swift
figures[index].idle.advance(by: deltaTime)
figures[index].wave.advance(by: deltaTime)

let target: Float = distance < SampleGame.noticeDistance ? 1 : 0
let rate = min(deltaTime / 0.25, 1)
figures[index].waveWeight += (target - figures[index].waveWeight) * rate

figures[index].pose.set(to: figures[index].idle,
                        blendedWith: figures[index].wave,
                        weight: figures[index].waveWeight)
```

`weight` is how much of the second clip, 0 to 1. **Each clip is sampled at its own time.** Ease the weight rather than switching it. Posing allocates nothing.

For anything that is not a clip — a head turn, a solver — use `set(localTransforms:)` with `JointTransform`s, which keep rotation as a quaternion because a matrix cannot be blended.

## What a pose gives you

| Property | Space | For |
| --- | --- | --- |
| `localTransforms` | joint-local | what a clip writes, and where blending happens |
| `modelTransforms` | the character's own space | attaching things to a joint |
| `skinningMatrices` | model, relative to the bind | what the vertex shader multiplies by |

`skinningMatrices` is already exactly what a shader indexes, so it is copied into a buffer as it is:

```swift
figure.pose.skinningMatrices.withUnsafeBytes { source in
    jointBuffer.contents().advanced(by: jointOffset(frameSlot: frameSlot, figure: index))
        .copyMemory(from: source.baseAddress!, byteCount: source.count)
}
```

The skinning shader and palette size are your game's; the sample's takes 128 joints. Find a joint once with `skeleton.index(ofJoint:)`; `pose.modelTransform(ofJoint:)` says where it is each frame — see [attachments](attachments.html).

## Scale and orientation

An exported character often sits in centimeters under a node scaled by 0.01. `Rig.nodeTransform` carries that matrix, as the mesh's `nodeTransform` does. Apply it inside the placement, with the up-axis correction:

```swift
let transform = placement * figureOrientation.transform * node
```

One matrix corrects mesh, rig and clips at once. Which way a character faces is not in the file; it is a yaw where it is placed.

## Gotchas

- **Rest transforms are joint-local; bind transforms are skeleton-space.** They coincide only in a rig rooted at the origin. A hand-built `Skeleton(jointPaths:restTransforms:bindTransforms:)` must keep them apart.
- **Clip translations are joint-local.** Channels a clip lacks fall back to rest.
- **Keyframe times arrive in seconds.**

## What it does not do

No animation state machine: which two clips to cross-fade is your game's decision. No retargeting, no IK and no root motion yet.
