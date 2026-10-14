---
title: Particles
description: ParticleRecipe, ParticleSystem and ParticleEmitter simulate on the fixed step; ParticleRenderer draws sparks and dust into the HDR scene.
---
Particles are the small things that show something just happened: sparks, embers, dust. `ParticleSystem` simulates them on the fixed step, with no GPU and no randomness that changes between runs. `ParticleRenderer` draws whatever is alive as camera-facing quads in one instanced draw. The sample uses them for embers rising off braziers and lanterns, a burst when a crate is collected, and dust when the player lands from a drop.

## ParticleRecipe {#recipe}

A recipe describes one kind of particle. Your game defines its own kinds, so the engine has no list of embers or smoke.

```swift
public init(count: Int, speed: Float, spread: Float, lifetime: Float, size: Float,
            growth: Float = 0, gravity: Float = -6.5, drag: Float = 2.4,
            color: SIMD3<Float>, opacity: Float = 1, fade: Float = 1, glows: Bool = false)
```

| Field | Meaning |
| --- | --- |
| `count` | How many one burst throws. |
| `speed`, `spread` | Meters per second along the burst's axis and across it. |
| `lifetime`, `size` | Seconds and edge length in meters, before per-particle variation. |
| `growth` | Size growth over a lifetime: 0 stays the same size, 1 doubles. |
| `gravity` | Meters per second squared, **signed**: dust falls, an ember rises. |
| `drag` | Fraction of velocity lost per second. |
| `color` | Linear and unbounded. Values above 1 make a spark read as hot. |
| `opacity`, `fade` | Opacity at birth, and how it falls: `(1 − t)^fade`. |
| `glows` | Whether this is light or matter. |

### Light or matter {#glows}

Matter (dust, smoke, dirt) covers whatever is behind it. Light (a spark, an ember) adds to it and covers nothing. **Both go through one pipeline.** Color is premultiplied, and a glowing particle writes zero coverage, which turns the "over" blend into an add. A dozen overlapping sparks get brighter, and a dozen dust motes get more opaque.

For a spark, `color` is the light it gives off. For dust, it's an **albedo**: how much of the arriving light the dust passes on. The sample found this by landing: a 0.5-gray cloud on shaded ground came out as a white glow, brighter than the floor. A sky's `matterLight` gives the light a white speck of dust would scatter under that `ProceduralSky`. It is the sky's average radiance plus the sun's irradiance spread over 4π. Compute it once per level and pass it to `draw`. It ignores shadow, so dust beside a wall is lit as if it were in the open.

## ParticleSystem {#system}

```swift
private var particles = ParticleSystem(recipes: [
    ParticleRecipe(count: 1, speed: 0.9, spread: 0.35, lifetime: 1.6, size: 0.07,
                   gravity: 1.4, drag: 0.9, color: SIMD3(5.0, 1.1, 0.12), fade: 1.5, glows: true),
    ParticleRecipe(count: 48, speed: 4.5, spread: 2.2, lifetime: 0.9, size: 0.12,
                   gravity: -7, drag: 1.8, color: SIMD3(0.5, 5.0, 2.2), glows: true),
    ParticleRecipe(count: 14, speed: 0.6, spread: 1.4, lifetime: 0.9, size: 0.35, growth: 1.8,
                   gravity: -1, drag: 3, color: SIMD3(0.50, 0.46, 0.40), opacity: 0.45, fade: 2),
], capacity: 1024)
```

Those are the sample's three recipes: embers, the pickup burst and landing dust. Two glow and one doesn't, so the single blend has to handle both.

- **`burst(_:at:direction:seed:count:)`** throws a burst of the recipe at that index, along `direction` (up by default). `count` can be fewer than the recipe's count, never more.
- **`step(deltaTime:)`** advances every live particle. Call it from your [fixed step](fixed-timestep.html), so a burst plays out the same way at any frame rate.
- **`particles`**, `live`, `liveCount` and `appearance(of:)` are for reading the state. `appearance(of:)` returns a particle's premultiplied color, its coverage and its current size. A `Particle`'s fields are read-only: the system owns the pool.

A recipe's `count` and `lifetime`, and an emitter's `rate`, hold their limits however they are set — a lifetime is never below a millisecond, a count or rate never negative.

**The pool is fixed.** When it's full, a dead slot is reused, and otherwise the *oldest* particle is recycled. Dropping the newest instead would silently throw away the burst that just happened, which is the one the player is looking at.

**There is no `random()`.** Spread comes from an integer hash of the burst's seed and the particle's index, inside the engine. **The seed should come from the simulation, never from a clock.** The sample uses its step count:

```swift
particles.burst(SampleGame.pickupRecipe, at: crate + SIMD3(0, 1.6, 0), seed: stepCount)
```

The hash used to be the shader one-liner `fract(sin(x) × 43758.5453)`. In 32-bit floats on the CPU, 300,000 draws gave only 8,923 distinct values. The integer hash gives 297,320.

The landing dust only triggers on a real fall, not every step down a stair:

```swift
if wasAirborne && body.isGrounded && fallSpeed > 4 {
    particles.burst(SampleGame.dustRecipe, at: body.feet + SIMD3(0, 0.05, 0),
                    seed: stepCount)
}
```

## ParticleEmitter {#emitter}

For a steady stream rather than a burst, use `ParticleEmitter(recipe:rate:seedBase:)`. `rate` is in particles per second. The emitter carries the leftover fraction from one step to the next, so twelve a second is twelve a second at any step rate. Give each emitter a different `seedBase` so two emitters don't throw identical particles.

The sample keeps one emitter per brazier and lantern. Each step, it emits before stepping the system:

```swift
emberEmitters[index].emitter.emit(into: &particles, at: at, deltaTime: deltaTime)
// ...
particles.step(deltaTime: deltaTime)
```

The lanterns move, so an ember's origin is read from the lantern's light every step. That way an ember leaves the lantern where it is now, not where it was.

## ParticleRenderer {#renderer}

`ParticleRenderer(device:capacity:)` owns its whole pipeline, shaders included, and throws a `ParticleRendererError` saying what could not be built. A particle is just a point and a color, so there's nothing of your game's in its geometry. `capacity` has no default: name one number for it and the system's, as the sample does with `particleCapacity`, and add `allocations` to your residency set.

Draw **last in `encode`**, after everything opaque:

```swift
particleRenderer.draw(particles, into: encoder, frameSlot: frameSlot,
                      viewProjection: simd_mul(projection, view.viewMatrix),
                      cameraRight: view.right, cameraUp: view.up, matterLight: matterLight)
```

- **Into the scene, not the HUD.** A spark goes through the [tone map](tone-mapping.html) like the lamp it came from.
- **Depth is tested but never written.** A spark behind a pillar is hidden by it, but one spark doesn't punch a hole in another.
- **Unsorted.** Light is additive, so order doesn't matter, and at the low opacities dust is drawn at, a wrong order isn't visible. Dense smoke would need sorting back to front, which the renderer does not do.

`draw` leaves its own pipeline, depth state and argument table bound, so anything you draw after it must bind its own again. It returns how many particles it drew.
