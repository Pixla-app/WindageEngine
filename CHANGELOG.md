# Changelog

Every release of Windage Engine, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html), as set out in `README.md` § "Versioning".

**1.0.0 is the first release.** How the engine was built before it is in the git log, not here. Releases are
cut in Pixla Games Control's Releases window, never by hand.

**Written for somebody upgrading**, which means the entries that matter most after 1.0.0 are under
*Changed* and *Removed*. A new type costs a reader nothing; a changed one costs them a build.

## [Unreleased]

## [1.0.0] — 2026-10-14

**Initial release.** A Swift 6 and Metal 4 game engine for the Mac, extracted from working games.

### Added

- **Frame pacing:** frames in flight, a fixed simulation step, and a clock that keeps time with the window
  hidden. `GameLoop`, `FrameRenderer`, `FixedTimestep`.
- **Rendering:** reversed-Z depth, an HDR scene with tone mapping and exposure in stops, physically based
  materials (base color, normal, occlusion–roughness–metallic and emission maps), and image-based lighting
  from the sky.
- **Light and shadow:** cascaded sun shadows, and spot and point lights binned into clusters, each able to
  cast. `ShadowMap`, `ClusteredLights`.
- **Meshes:** loading through Model I/O, with USD's orientation and units handled. `MeshLoader`.
- **Many copies:** instanced drawing, one draw per kind of prop. `InstanceBatches`, `InstanceBuffer`.
- **Detail by distance:** simpler tiers of every mesh made when it loads, and the tier a copy's distance
  earns. `MeshDetail`, using meshoptimizer's simplifier (MIT).
- **Culling:** frustum culling for the screen and for each shadow cascade. `Frustum`.
- **Characters:** skinned animation from USD, cross-fades, and things hung off joints. `SkeletonPose`,
  `TransformHierarchy`.
- **A body with feet:** stairs, slopes, lifts, turntables and being pushed, with the same result at any
  step rate. `CharacterController`.
- **Particles:** sparks, embers and dust, simulated on the fixed step and drawn in one instanced draw.
  `ParticleSystem`.
- **Levels:** a versioned level format, and an editor you use inside your running game. `Level`,
  `LevelEditor`.
- **Sound:** positional audio and looping ambience that belongs to a place. `AudioEngine`.
- **Input and settings:** keys and controllers a player rebinds, per-device sensitivity, dead zones and
  invert, and settings that save. `InputBindings`, `SaveStore`.
- **The HUD:** text and shapes drawn after the tone map. `HUDRenderer`.
- **Your game's name:** a splash screen and the engine's mark. `SplashScreen`, `EngineMark`.
- **Checks:** scripted walks and recorded frames, so a change that moves the player or the picture fails a
  check instead of going unnoticed. `Tools/walks.py`, `Tools/frames.py`.
- **A sample game** built only against the public API. `swift run WindageSample`.
