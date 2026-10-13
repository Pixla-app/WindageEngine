---
title: CharacterController
description: A first-person body with feet — walking, stepping up, gravity, jumping, crouching and sliding, standing on moving and turning platforms, and being pushed.
---
`CharacterController` is a body with feet. It walks, stands on things, steps up a low ledge, falls off a high one, jumps, crouches and slides. For an editor, a photo mode or something that flies, move a `Camera` with `advance(_:deltaTime:)` instead.

## One step

Step it once per [fixed timestep](fixed-timestep.html) and put the camera at its eye. From the sample:

```swift
body = CharacterController(feet: spawn?.position ?? SIMD3(0, 0, 12))

// each step
body.step(yaw: camera.yaw,
          input: input.movement,
          jump: input.isJumpHeld,
          crouching: input.isCrouching,
          deltaTime: deltaTime,
          in: surroundings)
camera.position = body.eye
```

**Only the yaw goes in**: walking is along the ground plane, so looking down does not slow you. `input` is a `MovementInput` from `InputState.movement` (see [input](input.html)). `jump` is whether jump is *held*; the controller finds the press itself.

After a step, read:

| Property | What it is |
| --- | --- |
| `feet` | where the feet are; collision is exact against this |
| `eye` | where the camera goes: the feet, the posture and the eye's settling |
| `isGrounded`, `verticalVelocity` | on something, and how fast up |
| `isSliding`, `slideProgress` | a slide, 0 at entry to 1 at the end |
| `isHeldDown` | let go of crouch with no room to stand |
| `groundSolid` | which solid the feet are on, or nil for terrain or air |
| `events` | `.stride(foot:speed:)`, `.landed(impactSpeed:)`, `.jumped` — cleared at the start of every step |

The sample plays footsteps from `events`, picking the sound by `groundSolid`.

## The world it stands in

`Surroundings` is a terrain height and a list of solid boxes.

```swift
surroundings = CharacterController.Surroundings(groundHeight: { _, _ in 0 },
                                                solids: solidVolumes.map(\.worldBounds))
```

Terrain is a floor you cannot go below; walking into a rise walks up it. A solid is stood on, stepped onto if low enough, and otherwise stops you. The body is a box, which is exact against the axis-aligned boxes `Volume.worldBounds` produces; it moves one axis at a time, so a wall hit at an angle is slid along.

### Footprints

A turned crate's world box is bigger than the crate. Give each solid its real plan in `footprints`, in the same order as `solids` (nil means the box): `Footprint(of:)` for a volume turned about the vertical (nil if tilted), `Footprint(discOf:)` for something round — a box cannot say it holds a circle — or `Footprint(center:halfSize:yaw:)` and `Footprint(center:radius:)` by hand.

```swift
surroundings.footprints = zip(solidVolumes, solidPlacements).map {
    footprint(of: $0, mesh: level.placements[$1].mesh)
}
```

The box says how high a solid reaches; the footprint says where it stands.

## Things that move

Moving a solid is your game's job: update its box and say how far it went. **Keep the order of `solids` fixed** — the body knows what it stands on by index.

- **`motion`** — how far each solid moved this step. A body on one goes with it, through collision, so a platform carries no one through a wall.
- **`turns`** — a `Turn(about:by:)` per solid: the axis's `center` and the `radians` turned this step.

A solid moving into the body pushes it; pushed into a wall, `pinnedBy` names the solid, and what it does next is your game's. On leaving, the body keeps the speed it was carried or pushed at (`groundVelocity`, `airVelocity`), **so `motion` must be movement**: a solid reset to its start must report none that step.

> **The camera is your game's.** Add `turned` to the view's yaw, or the floor spins and the player keeps facing one way.

```swift
if body.turned != 0 { camera.yaw = Camera.wrapAngle(camera.yaw + body.turned) }
```

## Tuning

`tuning` holds every number; the defaults were tuned in play.

| Field | Default | Why |
| --- | --- | --- |
| `walkSpeed`, `sprintSpeed` | 6, 18 m/s | `Camera.walkSpeed`, `Camera.sprintSpeed` |
| `eyeHeight`, `crouchedEyeHeight` | 1.7, 1.05 m | crouching costs speed and the sprint |
| `stepHeight` | 0.45 m | a stair and a low plinth, not a crate — a crate you could walk onto is not cover |
| `gravity` | 20 m/s² | about twice real; at 9.8 a first-person fall floats |
| `jumpSpeed` | 6.3 m/s | clears about a meter: a low wall, not a crate |
| `coyoteSeconds`, `jumpBufferSeconds` | 0.1, 0.12 s | a jump just off a ledge, or just before landing, is not eaten |
| `slideSeconds` | 1.15 s | crouching mid-sprint carries the momentum |

## Crouch, slide and room to stand

Crouching mid-sprint slides, steered only a little, down to a crouched walk. **No jump out of a slide.** Letting go of crouch under a beam keeps the body down with `isHeldDown` true until there is room.

## What goes on the view, never the aim

`slideCameraDip`, `landingCameraDip` and `headBob` go on the camera you draw, not the one you aim with:

```swift
view.pitch += body.slideCameraDip + body.landingCameraDip
let bob = previousBob + (shownBob - previousBob) * interpolation
view.position += view.right * bob.x + SIMD3(0, bob.y, 0)
```

`shownBob` is `body.headBob * settings.headBob`, the player's setting, 0 for off. The feet move to a new height at once and the eye eases after them, which makes stairs read as stairs; a fall is never eased.

## The same at any step rate

A jump, a landing, a slide and the eye's settling come out the same at 30, 60, 120 or 240 steps a second: one course of all of them ends in the same place at every rate, within a centimeter.

## What it does not do

No capsule body: the box catches on a corner a capsule would glance off. The controller does not own the camera, and does not decide what a moving solid does when it pins someone.
