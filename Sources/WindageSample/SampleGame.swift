//
//  SampleGame.swift
//  WindageSample
//

import AppKit
import Metal
import MetalKit
import simd
import WindageEngine
import WindageSampleCore

/// **The whole game.** Walk around a level you can edit, with a line of text saying where you are.
///
/// It is deliberately dull. Its job is not to be a good game; it is to be the thing that proves the
/// engine can be built against **using only its public API**, by somebody who is not the person who
/// wrote it. Every gap it hits is an engine bug — the first one it found was that `swift build`
/// compiles no Metal at all, so the HUD could not start outside Xcode. See ``ShaderLibrary``.
final class SampleGame: GameLoop {

    /// One description of the vertex layout, shared by the pipeline and the mesh loader. **They must
    /// agree**: Model I/O will convert a file to whatever layout it is handed, so a mismatch draws
    /// garbage rather than failing.
    static let semantics: [Int: String] = [
        0: MDLVertexAttributePosition,
        1: MDLVertexAttributeNormal,
        2: MDLVertexAttributeTextureCoordinate,
        3: MDLVertexAttributeTangent,
    ]

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = 24
        descriptor.attributes[2].bufferIndex = 0
        // **A `float4`, and the fourth component is not padding.** It is the handedness of the
        // bitangent, ±1, and a mirrored UV island — which is most of any character, whose two halves
        // share one texture — is lit from the wrong side without it.
        descriptor.attributes[3].format = .float4
        descriptor.attributes[3].offset = 32
        descriptor.attributes[3].bufferIndex = 0
        descriptor.layouts[0].stride = 48
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    /// The same, plus the two attributes that make a mesh skinnable.
    ///
    /// **A separate layout and therefore a separate pipeline.** Putting joints and weights on every
    /// vertex in the level would double the size of a courtyard's geometry to say "no joint" 40,000
    /// times.
    static let skinnedSemantics: [Int: String] = [
        0: MDLVertexAttributePosition,
        1: MDLVertexAttributeNormal,
        2: MDLVertexAttributeTextureCoordinate,
        3: MDLVertexAttributeTangent,
        4: MDLVertexAttributeJointIndices,
        5: MDLVertexAttributeJointWeights,
    ]

    /// **Four influences per vertex, whatever the file holds.** The sample's figure is authored with
    /// two; Model I/O pads the rest with a joint index of 0 and a weight of 0, which contributes
    /// nothing — measured, not assumed. Four is what a bought character will bring.
    static func skinnedVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = vertexDescriptor()
        // **Weights before joints, which is not the order the shader declares them in.** A `float4`
        // wants a 16-byte-aligned offset; putting the 8-byte joint indices first would land the
        // weights at 56. Attribute *index* and byte *offset* are independent, so the layout can be
        // packed correctly and still read in the order the shader finds natural.
        descriptor.attributes[5].format = .float4
        descriptor.attributes[5].offset = 48
        descriptor.attributes[5].bufferIndex = 0
        descriptor.attributes[4].format = .ushort4
        descriptor.attributes[4].offset = 64
        descriptor.attributes[4].bufferIndex = 0
        descriptor.layouts[0].stride = 72
        return descriptor
    }

    /// One animated character: the rig, where it stands, and where it is in its two clips.
    ///
    /// **The pose is kept between frames rather than rebuilt**, because it owns its arrays — posing
    /// a character allocates nothing, and that only holds if the character keeps its pose.
    private struct Figure {
        var pose: SkeletonPose
        var idle: AnimationPlayhead
        var wave: AnimationPlayhead
        /// How much of the wave is showing, 0…1. Eased toward a target so a player walking past
        /// does not switch a character between clips in one frame.
        var waveWeight: Float = 0
        let transform: matrix_float4x4
        let position: SIMD3<Float>
    }

    /// See `scriptedWalk`.
    ///
    /// **Keys, pressed and released through the same path a keyboard uses** — `keyPressed`, which
    /// gives the game first refusal and then `InputState`. It used to hand the body a movement
    /// directly, which tested the controller and skipped everything in front of it: the bindings,
    /// the menu, and the Shift that was never wired up.
    private struct ScriptedWalk {
        struct Segment {
            let label: String
            let keys: [KeyCode]
            let seconds: Float
            var yaw: Float? = nil
            var pitch: Float? = nil
            var isLook: Bool { yaw != nil || pitch != nil }
        }
        enum Event {
            case begin(Segment)
            case end(Segment, report: String?)
        }

        private let segments: [Segment]
        private var index = 0
        private var elapsed: Float = 0
        private var peak: Float = -.greatestFiniteMagnitude
        private var begun = false

        init?(_ script: String?) {
            guard let script, !script.isEmpty else { return nil }
            var parsed: [Segment] = []
            for token in script.split(whereSeparator: \.isWhitespace) {
                let parts = token.split(separator: ":")
                guard parts.count == 2, let number = Float(parts[1]) else {
                    print("WindageSample: WINDAGE_SAMPLE_WALK wants keys:seconds — ignoring '\(token)'")
                    continue
                }
                // `yaw:` and `pitch:` take degrees and no time: they turn the view, which is the
                // one thing a replayed walk otherwise cannot do, since it ignores the mouse.
                if parts[0] == "yaw" || parts[0] == "pitch" {
                    let radians = radians_from_degrees(number)
                    parsed.append(parts[0] == "yaw"
                        ? Segment(label: String(token), keys: [], seconds: 0, yaw: radians)
                        : Segment(label: String(token), keys: [], seconds: 0, pitch: radians))
                    continue
                }
                var keys: [KeyCode] = []
                for name in parts[0].split(separator: "+") where name != "wait" {
                    if let key = KeyCode(named: String(name)) {
                        keys.append(key)
                    } else {
                        print("WindageSample: WINDAGE_SAMPLE_WALK does not know the key '\(name)'")
                    }
                }
                parsed.append(Segment(label: String(token), keys: keys, seconds: number))
            }
            guard !parsed.isEmpty else { return nil }
            segments = parsed
        }

        var isRunning: Bool { index < segments.count }

        /// What happens this step, in order: a segment whose time is up ends — its keys come up —
        /// and the next begins — its keys go down. **Checked before the body moves**, so a segment of
        /// n seconds holds its keys for exactly the steps that fit in n.
        mutating func advance(by seconds: Float, body: CharacterController) -> [Event] {
            var events: [Event] = []
            while index < segments.count {
                let segment = segments[index]
                if !begun {
                    begun = true
                    elapsed = 0
                    peak = body.feet.y
                    events.append(.begin(segment))
                }
                peak = max(peak, body.feet.y)
                guard elapsed >= segment.seconds else {
                    elapsed += seconds
                    break
                }
                let f = body.feet
                let report = segment.isLook ? nil : String(
                    format: "WindageSample: walk '%@' → feet (%.2f, %.2f, %.2f), highest %.2f, %@",
                    segment.label, f.x, f.y, f.z, peak, body.isGrounded ? "on the ground" : "in the air")
                events.append(.end(segment, report: report))
                index += 1
                begun = false
            }
            return events
        }
    }

    /// The settings screen's state while it is open.
    private struct SettingsMenu {
        enum Row: Equatable {
            case bind(InputBindings.Action)
            case sensitivity, invert, volume, brightness, reset
        }
        static let rows: [Row] = InputBindings.Action.allCases.map { .bind($0) }
            + [.sensitivity, .invert, .volume, .brightness, .reset]

        var selected = 0
        /// The action waiting for a key, while the screen says "press a key".
        var capturing: InputBindings.Action?
        /// What the last change did — "Jump swapped with Forward", "P is the pause key".
        var message: String?
        /// Whether opening the screen paused the run, so closing it only resumes what it paused.
        var pausedTheRun = false

        var row: Row { SettingsMenu.rows[selected] }
    }

    /// One lamp as the shader reads it: **`w` carries the range**, so a `float3` and a scalar pack
    /// into one `float4` and there is no padding for the two sides to disagree about.
    private struct PackedLight {
        var positionAndRange: SIMD4<Float> = .zero
        var colourAndAngleOffset: SIMD4<Float> = .zero
        var directionAndAngleScale: SIMD4<Float> = .zero
        /// xy atlas offset, z scale, **w whether this light has a map at all**.
        var shadowTile: SIMD4<Float> = .zero
        /// x cube-array slice, y near plane, **w whether this light has a cube at all**.
        ///
        /// **A separate field from `shadowTile` rather than a kind flag sharing it.** The two are
        /// mutually exclusive in practice — a lamp is either aimed or it is not — but packing them
        /// into one `float4` means the shader reads `x` as a *uv offset* or as a *slice index*
        /// depending on a number in `w`, and a field whose meaning depends on another field is the
        /// kind of thing that survives every test and fails once a level mixes the two.
        var shadowCube: SIMD4<Float> = .zero
        var shadowViewProjection: matrix_float4x4 = matrix_identity_float4x4

        init() {}
        init(_ light: PunctualLight) {
            positionAndRange = SIMD4(light.position, light.range)
            // **A point light is a spot with scale 0 and offset 1**, which makes the shader's angular
            // term exactly 1 everywhere. One code path, no branch, and nothing that behaves
            // differently depending on which kind of lamp a level happens to hold.
            let cone = light.cone
            colourAndAngleOffset = SIMD4(light.colour, cone?.angleOffset ?? 1)
            directionAndAngleScale = SIMD4(cone?.direction ?? SIMD3(0, -1, 0), cone?.angleScale ?? 0)
        }
    }

    private struct Uniforms {
        var viewProjection: matrix_float4x4
        var model: matrix_float4x4
        var normalMatrix: matrix_float3x3
        /// The *game's* tint — objective state, editor selection. Multiplied with the material's.
        var albedo: SIMD3<Float>
        var sunDirection: SIMD3<Float>
        /// From the file's material.
        var materialBaseColor: SIMD4<Float>
        /// **Packed into a `float4` rather than left as two loose floats.** Both sides have to agree
        /// on the padding between a `float3` and whatever follows, and a `float4` has no argument.
        var materialParams: SIMD4<Float>
        /// The level's sun, in radiance. **`w` unused** — a `float4` so neither side has to reason
        /// about the padding after a `float3`.
        var sunColour: SIMD4<Float>
        /// What this surface emits, in radiance: the material's own emission times whatever the game
        /// wants of it right now. **`w` unused**, for the same padding reason.
        var emissive: SIMD4<Float>

        init(viewProjection: matrix_float4x4,
             model: matrix_float4x4,
             normalMatrix: matrix_float3x3,
             albedo: SIMD3<Float>,
             sunDirection: SIMD3<Float>,
             material: Material,
             specularLOD: Float,
             sunColour: SIMD3<Float>,
             emissive: SIMD3<Float>) {
            self.viewProjection = viewProjection
            self.model = model
            self.normalMatrix = normalMatrix
            self.albedo = albedo
            self.sunDirection = sunDirection
            self.materialBaseColor = material.baseColor
            self.materialParams = SIMD4(material.metallic, material.roughness, specularLOD, 0)
            self.sunColour = SIMD4(sunColour, 0)
            // **The game's value, not the material's times the game's.** Multiplying them was the
            // first attempt and it silently produced nothing: an OBJ material's emission is always
            // zero — Model I/O reads neither `Ke` nor `map_Ke` — so a crate the game wanted lit was
            // zero times whatever the game asked for. The material's emission is a *default* the game
            // may use, override or ignore, and defaulting is the caller's job because only the caller
            // knows whether this surface is currently powered.
            self.emissive = SIMD4(emissive, 0)
        }
    }

    /// Mirrors `FrameUniforms` in `SampleShaders.metal`. **Frame-wide, so it is written once** — four
    /// matrices copied into every drawable's uniforms would multiply them by the object count for
    /// nothing.
    private struct FrameUniforms {
        var cascadeViewProjection: (matrix_float4x4, matrix_float4x4, matrix_float4x4, matrix_float4x4)
        /// Takes a clip-space point back to the world — how the sky pass turns a pixel into a ray.
        var inverseViewProjection: matrix_float4x4
        /// World to view. **The planar depth a cluster slice is chosen by** — the shadow cascades use
        /// radial distance, which is a different number and would pick a different cell.
        var view: matrix_float4x4
        var cascadeSplits: SIMD4<Float>
        var cascadeBlendStart: SIMD4<Float>
        var cascadeDepthBias: SIMD4<Float>
        var cameraPosition: SIMD3<Float>
        var texelSize: Float
        var viewportSize: SIMD2<Float>
        var framePadding: SIMD2<Float> = .zero
        var clusters: PackedClusterGrid
    }

    /// Mirrors `ClusterUniforms` in the shader, which mirrors `ClusterGrid`. **The slicing on both
    /// sides must be the same expression**, or a light is binned into a cell no fragment reads.
    private struct PackedClusterGrid {
        var tilesX: UInt32 = 0
        var tilesY: UInt32 = 0
        var slices: UInt32 = 0
        var depthScale: Float = 0
        var depthBias: Float = 0
        // **Three separate floats, not a `SIMD3`.** A `SIMD3<Float>` has 16-byte alignment in Swift
        // and the shader's three trailing scalars have four — so the struct came out 48 bytes on one
        // side and 32 on the other, and every field after it in `FrameUniforms` was read from the
        // wrong place. It rendered as the local lights simply not existing.
        var padding0: Float = 0
        var padding1: Float = 0
        var padding2: Float = 0

        init() {}
        init(_ grid: ClusterGrid) {
            tilesX = UInt32(grid.tilesX)
            tilesY = UInt32(grid.tilesY)
            slices = UInt32(grid.slices)
            depthScale = grid.depthScale
            depthBias = grid.depthBias
        }
    }
    private static let shadowFrameStride = (MemoryLayout<FrameUniforms>.stride + 255) & ~255

    private let engine: FrameRenderer
    private let pipeline: MTLRenderPipelineState
    /// **Optional: no skinned pipeline means no characters, not no sample.**
    private let skinnedPipeline: MTLRenderPipelineState?
    private let depthState: MTLDepthStencilState
    private let hud: HUDRenderer?

    /// **Optional, and the game runs without it.** A machine with no output device, or an audio
    /// engine that will not start, must not stop somebody seeing the sample — sound is the first
    /// thing to go wrong on someone else's hardware and the last thing that should be fatal.
    private let audio: AudioEngine?
    private let argumentTable: MTL4ArgumentTable
    private let uniformBuffer: MTLBuffer

    /// **Optional like the audio.** A machine that cannot build the shadow pipeline should still
    /// show the sample, unlit rather than not at all.
    ///
    /// **The pass itself is the engine's now** — `ShadowMap` owns the texture, the reversed-Z depth
    /// state, the per-cascade descriptors and the encoder loop. What is left here is the part the
    /// engine genuinely cannot own: two pipelines, compiled against *this game's* shaders and *this
    /// game's* vertex layouts.
    private let shadowMap: ShadowMap?

    /// Shadow maps for the lamps, packed into one texture. **Optional like the cascades**: a machine
    /// that cannot allocate it should still show the scene, with lamps that reach through walls.
    private let shadowAtlas: ShadowAtlas?
    /// Which lights have a tile this frame, recomputed with the light set.
    private var shadowCasters: [(lightIndex: Int, caster: ShadowAtlas.Caster)] = []

    // MARK: - Settings

    /// **Where settings live, beside the progress file and separate from it** — resetting progress
    /// must not reset a player's keys, and the reverse.
    private static let settingsStore = SaveStore<PlayerSettings>(container: "WindageSample", name: "settings")
    private var settings = SampleGame.settingsStore.load() ?? PlayerSettings()
    private var menu: SettingsMenu?

    /// The game's own exposure, before the player's brightness. **The game's dial**: ACES lifts
    /// midtones by about a fifth, and half a stop down puts a scene authored before there was a curve
    /// back where it was.
    private static let baseExposure: Float = -0.5

    /// Keys this game takes before `InputState` sees them, whatever it is doing — so they cannot be
    /// bound to anything, or the binding would never fire. Tab and Escape are refused by the engine.
    private static let reservedKeys: Set<KeyCode> = ["P", "R", "N", "M", "O"].compactMap(KeyCode.init(named:))
        .reduce(into: []) { $0.insert($1) }

    // MARK: - Particles

    /// Embers, a burst for a collected crate, and dust when the player lands.
    ///
    /// **The sample's three recipes, and they are the sample's.** The engine has no idea what an ember
    /// is; it knows what a recipe is. Two of these glow and one does not, which is the point of having
    /// three: one blend has to serve light and matter both.
    private static let emberRecipe = 0, pickupRecipe = 1, dustRecipe = 2
    private var particles = ParticleSystem(recipes: [
        // **Rising, not falling** — gravity is per recipe, and heat lifts an ember. Well above 1 in
        // colour so it reads as hot, and tiny, because a spark the size of a coin is a firefly.
        ParticleRecipe(count: 1, speed: 0.9, spread: 0.35, lifetime: 1.6, size: 0.07,
                       gravity: 1.4, drag: 0.9, colour: SIMD3(5.0, 1.1, 0.12), fade: 1.5, glows: true),
        // The crate's own green, thrown outward and falling back: a moment, not a firework.
        ParticleRecipe(count: 48, speed: 4.5, spread: 2.2, lifetime: 0.9, size: 0.12,
                       gravity: -7, drag: 1.8, colour: SIMD3(0.5, 5.0, 2.2), glows: true),
        // **Matter**: it covers what is behind it, spreads as it thins, and does not glow.
        ParticleRecipe(count: 14, speed: 0.6, spread: 1.4, lifetime: 0.9, size: 0.35, growth: 1.8,
                       gravity: -1, drag: 3, colour: SIMD3(0.50, 0.46, 0.40), opacity: 0.45, fade: 2),
    ], capacity: 1024)
    private let particleRenderer: ParticleRenderer?
    /// One per lamp that points nowhere — the braziers and the lanterns — by index into
    /// `lightSet.lights`, so an emitter follows a lantern because the light does.
    private var emberEmitters: [(light: Int, emitter: ParticleEmitter)] = []
    /// Steps taken since launch. **The seed for anything a step throws**, which is what keeps a
    /// scripted walk's dust landing the same way every time.
    private var stepCount = 0

    // MARK: - Something in a hand

    /// The lanterns the figures carry.
    ///
    /// **The canonical use of a hierarchy, and the one the engine's own notes named**: a thing hung
    /// off a joint, of a pose, of an object. One node per figure, each attached externally, so the
    /// only thing that changes per frame is the array of hands.
    private var lanterns: TransformHierarchy?
    /// Where each lantern sits in `drawables` — and therefore in `volumes`, which is the same order.
    private var lanternDrawables: [Int] = []
    /// Where each lantern's light sits in `lightSet.lights`.
    private var lanternLights: [Int] = []
    /// Which joint they hang off in whatever rig actually loaded.
    private var lanternJoint: Int?
    /// How many of `volumes` came from the level, before the lanterns were appended.
    private var levelVolumeCount: Int { volumes.count - lanternDrawables.count }

    /// A 16 cm box, held just off the joint it hangs from.
    ///
    /// **In the joint's frame, not the world's, which is what makes this a grip rather than a
    /// follow.** The offset turns with the joint, so the lantern tips as the arm does; a version that
    /// merely copied the hand's *position* would stay upright and read as a balloon on a string.
    ///
    /// > **The offset is small, and picking it took several attempts.** The bind pose puts this joint
    /// > 48 cm out along the arm and the arm mesh reaches 74, so 26 cm along the joint's +X reads as
    /// > "the hand" — and with the arm down it is exactly that, verified by looking. **Raised, it is
    /// > not:** the drawn limb stops a hand's length short of where that arithmetic says the hand
    /// > went, and the lantern floats above the figure's head.
    /// >
    /// > **A joint's frame is where the rig says the joint is. It is not a promise about where the
    /// > mesh got drawn**, and the gap between the two is the asset's business rather than the
    /// > engine's. A rig with a real hand joint would not have the question; this one ends at a
    /// > forearm, so the grip is a number set by looking — which is what an attachment point in a
    /// > tool is for, and this sample has no tool.
    private static let lanternGrip: matrix_float4x4 = {
        let size: Float = 0.16
        return matrix_float4x4(columns: (SIMD4(size, 0, 0, 0),
                                         SIMD4(0, size, 0, 0),
                                         SIMD4(0, 0, size, 0),
                                         SIMD4(0.05, -0.09, 0, 1)))
    }()

    /// Cubes for the lamps that point nowhere. **Fewer of these than tiles, and deliberately** — six
    /// passes each is the cost, so the sample takes the engine's mean default rather than dressing
    /// it up.
    private let shadowCubes: ShadowCubes?
    /// Which point lights have a cube this frame.
    private var cubeCasters: [(lightIndex: Int, caster: ShadowCubes.Caster)] = []
    private let shadowPipeline: MTLRenderPipelineState?
    private let skinnedShadowPipeline: MTLRenderPipelineState?

    /// A courtyard seventy metres across, not a sniper range. **These are the sample's numbers, and
    /// that they are nothing like a long-range game's is exactly why `ShadowCascades` takes them as
    /// arguments.** `lightDepthRange` is 200 rather than the 1500 default for the same reason: it is
    /// how far along the light axis the recorded box reaches, and a courtyard needs a fraction of
    /// what a world kilometres deep does.
    private static let cascades = ShadowCascades(splits: [8, 22, 55, 120],
                                                 resolution: 1024,
                                                 lightDepthRange: 200)
    /// Frame-wide shadow data — written once a frame, not once per object.
    private let shadowFrameBuffer: MTLBuffer

    /// The level, and the editing on top of it. **The engine owns what an edit *means*** — see
    /// `LevelEditor`; this file only turns clicks and keys into those operations and draws the result.
    private var editor: LevelEditor
    private(set) var isEditing = false
    var isEditingLevel: Bool { isEditing }
    private var level: Level { editor.level }
    /// Which level is loaded. **`var`, and that is the whole point of this pass** — everything about
    /// this game assumed one level, loaded once, because there had only ever been one.
    private var levelIndex = 0

    /// **Two environment overrides, and they exist so a picture can be taken twice.**
    ///
    /// Judging a rendering change means comparing two frames, and two frames are only comparable if
    /// they are the *same* frame — which a sample that always opens on level one at the spawn point,
    /// and is then walked to the interesting corner by hand, cannot give you. Everything this sample
    /// has that is worth photographing was found by comparing a before against an after.
    ///
    /// - `WINDAGE_SAMPLE_LEVEL=1` — open on that level rather than the first.
    /// - `WINDAGE_SAMPLE_CAMERA=x,y,z,yaw,pitch` — stand there instead of at the spawn. Angles in
    ///   degrees, because they are numbers a person types.
    ///
    /// **Placing the camera this way makes it fly.** A screenshot position is a viewpoint, not
    /// somewhere to stand: with a body under it, gravity would have pulled a raised camera to the
    /// ground before the first frame was drawn, and the picture would be of the floor.
    /// A walk read from `WINDAGE_SAMPLE_WALK`, played back in place of the keyboard.
    ///
    /// **The same argument as the two overrides above, for movement.** A character controller is
    /// judged by walking it somewhere, and "I walked up the steps and it felt right" is not
    /// something anybody else can repeat. A script is: the same keys for the same seconds from the
    /// same spawn reach the same place, and the log says where that was.
    ///
    /// `WINDAGE_SAMPLE_WALK="d:0.75 w:1.6 w+space:0.1"` — segments of key names and seconds, joined
    /// with `+`: any name `KeyCode(named:)` knows, `shift` included, or `wait` for none. **Held for
    /// the segment and released at its end, through `keyPressed`** — the game's keys, the settings
    /// screen and the bindings all see them exactly as they would a keyboard's. `yaw:90` and
    /// `pitch:-40` turn the view to that many degrees, taking no time. Each segment's end is printed with where the feet are,
    /// the highest they got during it, and whether they are on the ground.
    private var scriptedWalk = ScriptedWalk(ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_WALK"])

    private static var startingLevel: Int {
        guard let value = ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_LEVEL"],
              let index = Int(value) else { return 0 }
        return min(max(index, 0), SampleLevel.names.count - 1)
    }

    private static var startingCamera: Camera? {
        guard let value = ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_CAMERA"] else { return nil }
        let parts = value.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 5 else {
            print("WindageSample: WINDAGE_SAMPLE_CAMERA wants x,y,z,yaw,pitch — ignoring '\(value)'")
            return nil
        }
        return Camera(position: SIMD3(parts[0], parts[1], parts[2]),
                      yaw: radians_from_degrees(parts[3]),
                      pitch: radians_from_degrees(parts[4]))
    }
    private var levelURL: URL { SampleLevel.writableURL(levelIndex) }
    private var levelPath: String

    /// The player's body. **The camera sits at its eye and no longer moves the player itself** —
    /// `Camera.advance` flies along the look direction, which is right for a photo mode and wrong
    /// for somebody with feet.
    private var body: CharacterController
    /// What the body stands on and walks into. **Rebuilt with the level**, from the same `solid` tag
    /// the level file already carried — in edit mode that is every change.
    private var surroundings = CharacterController.Surroundings()
    /// Whether the camera flies instead of walking. Set by `WINDAGE_SAMPLE_CAMERA`; see
    /// `startingCamera` for why a screenshot position cannot be somewhere to stand.
    private let isPhotoMode: Bool
    private var meshes: [String: LoadedMesh] = [:]
    /// Resolved from the level — anchors against this game's ground, which is simply y = 0.
    /// **Rebuilt whenever the level changes**, because in edit mode it changes constantly.
    /// **The base-colour maps travel with the drawable, not looked up by index.** `drawables` skips
    /// any placement whose mesh failed to load, so its indices are not the level's — reaching back
    /// into `level.placements` by the same index draws one object with another's texture, and only
    /// once something fails to load.
    private var drawables: [(mesh: LoadedMesh,
                             transform: matrix_float4x4,
                             albedo: SIMD3<Float>,
                             maps: [MTLTexture],
                             normals: [MTLTexture],
                             orm: [MTLTexture],
                             glow: [MTLTexture])] = []

    /// What the player cannot walk through, and what a click can pick.
    ///
    /// **Both from the same list, on purpose.** Two descriptions of "what is there" drift, and the
    /// day they do you are pointing at something you cannot touch.
    private var volumes: [Volume] = []
    private var solidVolumes: [Volume] = []
    /// Which drawables are objectives, so a collected one can go dark without searching the level.
    private var objectiveDrawables: [Int] = []

    /// The character mesh and the rig it wears — loaded once, shared by every figure in the level.
    ///
    /// **A `Skeleton` is structure, not pose**, so one of these serves any number of characters; what
    /// is per-character is the ``SkeletonPose`` inside each ``Figure``.
    /// **One store for the whole game, not one per mesh.** Every crate names the same file; loading
    /// it per mesh would decode, upload and mipmap it again and hold N copies on the GPU.
    private let textures: TextureStore?

    /// The sky, prefiltered: what surfaces reflect and what the player sees, from one source.
    ///
    /// **Rebuilt when the level changes**, because each level names its own sun and an environment
    /// lit from somewhere the sun is not is the kind of wrong that looks like a bug in the shading.
    private var environment: EnvironmentMap?
    private let skyPipeline: MTLRenderPipelineState?
    private let skyDepthState: MTLDepthStencilState?
    /// The base-colour and normal map for each of a mesh's submeshes, resolved once at load.
    private var baseColorMaps: [String: [MTLTexture]] = [:]
    private var normalMaps: [String: [MTLTexture]] = [:]
    private var emissiveMaps: [String: [MTLTexture]] = [:]
    /// Occlusion, roughness and metalness in one texture — R, G, B, which is glTF's packing.
    ///
    /// **Taken from the roughness slot, because all three name the same file.** A packed map is one
    /// file three slots point at, so `TextureStore` loads it once and any of the three would do.
    private var ormMaps: [String: [MTLTexture]] = [:]
    private var figureMaps: [MTLTexture] = []
    private var figureNormalMaps: [MTLTexture] = []
    private var figureORMMaps: [MTLTexture] = []
    private var figureEmissiveMaps: [MTLTexture] = []

    /// The up axis the figure's file declares. Identity for the built-in one, and not necessarily
    /// for a bought Z-up asset.
    private var figureOrientation: AssetOrientation = .identity

    /// Whether the figure came from `WINDAGE_SAMPLE_CHARACTER` rather than from the repository.
    private var usingExternalCharacter = false

    private var figureMesh: LoadedMesh?
    private var figureRig: Rig?
    private var figures: [Figure] = []

    private var run: SampleRun
    /// Seconds left on the pause between winning and the next level, or nil.
    private var advanceAfterWinning: Double?
    private var camera: Camera
    private var previousCamera: Camera
    private var aspectRatio: Float = 1
    private var viewportSize = SIMD2<Float>(1, 1)
    let input = InputState()

    /// Slots for uniforms: one per drawable per frame in flight, so a frame never overwrites one the
    /// GPU is still reading.
    /// Uniform slots per frame, and therefore the hard ceiling on things drawn.
    ///
    /// **Being over it silently drops the tail of the scene** — the same fault that once made
    /// a viewmodel disappear from the player's hands and read as a rendering bug. `rebuild()`
    /// says so out loud rather than leaving it to be discovered.
    private static let maxDrawables = 128
    private static let uniformStride = (MemoryLayout<Uniforms>.stride + 255) & ~255

    /// Figures take uniform slots after the level's drawables, in the same buffer.
    private static let maxFigures = 8
    private static let uniformSlots = maxDrawables + maxFigures

    /// **A ceiling, not the rig's joint count.** The buffer is allocated before any rig is loaded,
    /// so it has to be sized for a plausible character rather than for the one that turns up. A
    /// hundred joints is a humanoid with fingers.
    /// How much brighter than white the figure's seams burn.
    private static let figureGlow: Float = 2.2

    private static let maxJoints = 128
    private static let jointPaletteStride =
        (MemoryLayout<matrix_float4x4>.stride * maxJoints + 255) & ~255
    private let jointBuffer: MTLBuffer

    init?(engine: FrameRenderer) {
        self.engine = engine
        let device = engine.device

        levelIndex = SampleGame.startingLevel
        let loaded = SampleLevel.load(levelIndex)
        editor = LevelEditor(level: loaded.level)
        levelPath = loaded.report

        run = SampleRun(objectives: loaded.level.markers(ofKind: "objective").map(\.position),
                        levelName: loaded.level.name)

        // Spawn where the level says, looking where it says.
        let spawn = loaded.level.markers(ofKind: "spawn").first
        var camera = Camera(position: (spawn?.position ?? SIMD3(0, 0, 12)) + SIMD3(0, 1.7, 0))
        camera.yaw = spawn?.yaw ?? 0
        camera.pitch = radians_from_degrees(Float(spawn?.values["pitch"] ?? 0))
        // **A viewpoint the environment can override**, so a screenshot is reproducible. See
        // `startingCamera`.
        if let placed = SampleGame.startingCamera { camera = placed }
        self.isPhotoMode = SampleGame.startingCamera != nil
        // Feet on the spawn marker. The camera starts at their eye unless a photo put it elsewhere.
        self.body = CharacterController(feet: spawn?.position ?? SIMD3(0, 0, 12))
        if !isPhotoMode { camera.position = body.eye }
        self.camera = camera
        self.previousCamera = camera

        let vertexDescriptor = SampleGame.vertexDescriptor()
        var sky: MTLRenderPipelineState?

        let shaderLibrary: MTLLibrary
        do {
            shaderLibrary = try ShaderLibrary.make(device: device, bundle: .module, sourceNamed: "SampleShaders")
        } catch {
            print("WindageSample: shader library failed — \(error)")
            return nil
        }

        do {
            let library = shaderLibrary
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "sampleVertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "sampleFragment"

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = "SamplePipeline"
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.vertexDescriptor = vertexDescriptor
            // **The scene target, not the drawable.** The scene is drawn into an HDR texture and
            // fitted to the display by the engine's tone map pass; a pipeline declaring the
            // drawable's format here would not match the attachment it is given.
            descriptor.colorAttachments[0].pixelFormat = FrameRenderer.sceneColorPixelFormat
                pipeline = try compiler.makeRenderPipelineState(descriptor: descriptor, compilerTaskOptions: nil)

            // The skinned pipeline differs only in its vertex function and its layout — same
            // fragment shader, so a character is lit and shadowed by exactly the code the rest of
            // the scene is. Two fragment shaders that are meant to match is how a character ends up
            // subtly the wrong brightness.
            let skinnedVertex = MTL4LibraryFunctionDescriptor()
            skinnedVertex.library = library
            skinnedVertex.name = "sampleSkinnedVertex"
            descriptor.label = "SampleSkinnedPipeline"
            descriptor.vertexFunctionDescriptor = skinnedVertex
            descriptor.vertexDescriptor = SampleGame.skinnedVertexDescriptor()
            skinnedPipeline = try compiler.makeRenderPipelineState(descriptor: descriptor,
                                                                   compilerTaskOptions: nil)

            let skyVertex = MTL4LibraryFunctionDescriptor()
            skyVertex.library = library
            skyVertex.name = "sampleSkyVertex"
            let skyFragment = MTL4LibraryFunctionDescriptor()
            skyFragment.library = library
            skyFragment.name = "sampleSkyFragment"
            descriptor.label = "SampleSkyPipeline"
            descriptor.vertexFunctionDescriptor = skyVertex
            descriptor.fragmentFunctionDescriptor = skyFragment
            // **No vertex descriptor**: the sky is a full-screen triangle built from its vertex id.
            descriptor.vertexDescriptor = nil
            sky = try compiler.makeRenderPipelineState(descriptor: descriptor, compilerTaskOptions: nil)
        } catch {
            print("WindageSample: pipeline failed — \(error)")
            return nil
        }

        guard let depthState = engine.makeDepthStencilState() else {
            print("WindageSample: depth state failed")
            return nil
        }
        self.depthState = depthState
        skyPipeline = sky

        // **The sky writes no depth and tests none.** It is drawn first and everything else covers
        // it; writing depth would put the far plane in front of the scene, and testing it would need
        // a cleared buffer the engine has only just handed over.
        let skyDepth = MTLDepthStencilDescriptor()
        skyDepth.depthCompareFunction = .always
        skyDepth.isDepthWriteEnabled = false
        skyDepthState = device.makeDepthStencilState(descriptor: skyDepth)

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        // 0: vertices · 1: per-object uniforms · 2: frame data · 3: joints
        // 4: every light in the scene · 5: cluster ranges · 6: cluster light indices.
        tableDescriptor.maxBufferBindCount = 7
        // 0: cascades · 1: base colour · 2: normal · 3: environment · 4: irradiance · 5: ORM
        // 6: glow · 7: the lamps' shadow atlas.
        tableDescriptor.maxTextureBindCount = 9
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else {
            print("WindageSample: argument table failed")
            return nil
        }
        argumentTable = table

        guard let buffer = device.makeBuffer(
            length: SampleGame.uniformStride * SampleGame.uniformSlots * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: uniform buffer failed")
            return nil
        }
        uniformBuffer = buffer

        // One palette per figure per frame in flight — **per frame in flight**, because the GPU is
        // still reading the previous frame's pose while this one is written. Sharing one palette
        // across frames is the animation version of tearing.
        guard let joints = device.makeBuffer(
            length: SampleGame.jointPaletteStride * SampleGame.maxFigures * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: joint palette buffer failed")
            return nil
        }
        joints.label = "Joint Palettes"
        jointBuffer = joints

        // Per frame in flight, like everything else the GPU reads while the CPU writes the next one.
        guard let sceneLights = device.makeBuffer(
                length: SampleGame.sceneLightStride * SampleGame.maxSceneLights
                      * FrameRenderer.maxFramesInFlight, options: .storageModeShared),
              let clusterRanges = device.makeBuffer(
                length: SampleGame.clusterRangeStride * SampleGame.clusterGrid.clusterCount
                      * FrameRenderer.maxFramesInFlight, options: .storageModeShared),
              let clusterIndices = device.makeBuffer(
                length: MemoryLayout<UInt32>.stride * SampleGame.maxClusterIndices
                      * FrameRenderer.maxFramesInFlight, options: .storageModeShared) else {
            print("WindageSample: cluster buffers failed")
            return nil
        }
        sceneLights.label = "Scene Lights"
        clusterRanges.label = "Cluster Ranges"
        clusterIndices.label = "Cluster Light Indices"
        sceneLightBuffer = sceneLights
        clusterRangeBuffer = clusterRanges
        clusterIndexBuffer = clusterIndices

        guard let shadowFrames = device.makeBuffer(
            length: SampleGame.shadowFrameStride * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: shadow frame buffer failed")
            return nil
        }
        shadowFrameBuffer = shadowFrames

        textures = TextureStore(device: device)
        if textures == nil { print("WindageSample: no texture store — surfaces will be flat colours") }

        shadowMap = ShadowMap(device: device, cascades: SampleGame.cascades)
        shadowAtlas = ShadowAtlas(device: device, size: 2048, tilesPerSide: 4)
        if shadowAtlas == nil { print("WindageSample: no shadow atlas — lamps will reach through walls") }
        // **Four rather than the engine's two.** The ruins holds two braziers and the figures carry
        // lanterns, which is exactly the "a level should be choosing" case the default is mean about
        // — so the sample chooses, out loud, instead of inheriting a number.
        // **Six smaller cubes rather than two large ones.** The ruins holds two braziers and three
        // carried lanterns, which is exactly the "a level should be choosing" case the engine's
        // default is mean about — so the sample chooses, out loud, and pays for it in resolution
        // rather than in lamps that do not cast. Six faces at 384² is 21 MB.
        shadowCubes = ShadowCubes(device: device, size: 384, lightCount: 6)
        particleRenderer = ParticleRenderer(device: device, capacity: 1024)
        if particleRenderer == nil { print("WindageSample: no particle renderer — nothing will spark") }
        if shadowCubes == nil { print("WindageSample: no shadow cubes — point lights will reach through walls") }

        // **Two pipelines, because a skinned mesh has a different vertex layout.** Everything else
        // about a shadow pass — depth only, no colour attachment, one raster sample, the matching
        // depth format — comes from `ShadowMap.pipelineDescriptor`, which is the set of things that
        // have to be right and none of which is obvious.
        var shadow: MTLRenderPipelineState?
        var skinnedShadow: MTLRenderPipelineState?
        if shadowMap != nil {
            do {
                let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

                let staticFunction = MTL4LibraryFunctionDescriptor()
                staticFunction.library = shaderLibrary
                staticFunction.name = "sampleShadowVertex"
                shadow = try compiler.makeRenderPipelineState(
                    descriptor: ShadowMap.pipelineDescriptor(vertexFunction: staticFunction,
                                                             vertexDescriptor: vertexDescriptor,
                                                             label: "SampleShadow"))

                let skinnedFunction = MTL4LibraryFunctionDescriptor()
                skinnedFunction.library = shaderLibrary
                skinnedFunction.name = "sampleSkinnedShadowVertex"
                skinnedShadow = try compiler.makeRenderPipelineState(
                    descriptor: ShadowMap.pipelineDescriptor(
                        vertexFunction: skinnedFunction,
                        vertexDescriptor: SampleGame.skinnedVertexDescriptor(),
                        label: "SampleSkinnedShadow"))
            } catch {
                print("WindageSample: shadow pipelines failed — \(error)")
            }
        }
        shadowPipeline = shadow
        skinnedShadowPipeline = skinnedShadow
        if shadowMap == nil || shadowPipeline == nil {
            print("WindageSample: no shadows — the scene will be flat-lit")
        }

        // **The hint lines use keyboard symbols, so the atlas has to carry them.** It is ASCII by
        // default, and a character it does not carry draws nothing at all — which is how these
        // hints spent several sessions reading "S save  Z undo" with the ⌘ silently missing.
        hud = HUDRenderer(device: device, additionalCharacters: ["⌘", "⌫", "·", "°", "•", "—"])

        audio = AudioEngine()
        if let audio {
            // **From this module's bundle, not `.main`.** `AudioEngine.load` defaults to `.main`,
            // which for a SwiftPM executable is the executable itself and holds no resources — the
            // sounds live in the target's own bundle.
            let feet = ["dirt", "stone"].flatMap { surface in
                (0..<3).map { "step_\(surface)_\($0)" } + ["land_\(surface)"]
            }
            for sound in ["pickup", "win", "lose"] + feet where !audio.load(sound, bundle: .module) {
                print("WindageSample: no sound named \(sound)")
            }
        } else {
            print("WindageSample: no audio — the game runs, it is just quiet")
        }

        // **Everything the GPU reads has to be in the residency set.** A buffer or texture that is
        // not is read as whatever memory happens to be there — which is not a black screen, it is
        // garbage that looks like a shader bug.
        engine.residencySet.addAllocations([uniformBuffer, shadowFrameBuffer, jointBuffer,
                                            sceneLightBuffer, clusterRangeBuffer, clusterIndexBuffer])
        if let shadowMap { engine.residencySet.addAllocations(shadowMap.allocations) }
        if let shadowAtlas { engine.residencySet.addAllocations(shadowAtlas.allocations) }
        if let shadowCubes { engine.residencySet.addAllocations(shadowCubes.allocations) }
        if let particleRenderer { engine.residencySet.addAllocations(particleRenderer.allocations) }
        if let hud { engine.residencySet.addAllocations(hud.allocations) }

        // Meshes, then the level resolved against them.
        for name in Set(level.placements.map(\.mesh)) {
            if let mesh = try? MeshLoader.load(named: name, device: device,
                                               vertexDescriptor: vertexDescriptor,
                                               semantics: SampleGame.semantics,
                                               bundle: .module).first {
                meshes[name] = mesh
                baseColorMaps[name] = resolveBaseColorMaps(of: mesh, named: name)
                normalMaps[name] = resolveMaps(of: mesh, slot: .normal, named: name)
                ormMaps[name] = resolveMaps(of: mesh, slot: .roughness, named: name)
                emissiveMaps[name] = resolveMaps(of: mesh, slot: .emissive, named: name)
                engine.residencySet.addAllocations(mesh.mesh.vertexBuffers.map(\.buffer))
                engine.residencySet.addAllocations(mesh.mesh.submeshes.map(\.indexBuffer.buffer))
            } else {
                print("WindageSample: no mesh named \(name)")
            }
        }
        loadFigureAsset()
        rebuildEnvironment()
        engine.commitResidency()

        rebuild()
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")

        // **The player's settings, from last time.** Applied here rather than read at each use, so
        // the three things they reach — the bindings, the mixer and the exposure — are set once.
        engine.toneMapping = ToneMapping(curve: .aces, exposureStops: SampleGame.baseExposure)
        applySettings()
        print("WindageSample: settings from \(SampleGame.settingsStore.url.path) — forward "
              + "\(settings.bindings[.forward].name), jump \(settings.bindings[.jump].name)")
    }

    /// Loads the rigged figure: one mesh, one skeleton, two clips, all from one USD file.
    ///
    /// **Everything about the rig comes out of the file** — the joint hierarchy, the bind pose and
    /// both clips. Nothing about this figure is written into this game, which is the check that
    /// matters: a loader that only works on a rig the programmer already knows is not a loader.
    /// A character from outside the repository, when one is pointed at.
    ///
    /// **`WINDAGE_SAMPLE_CHARACTER=/path/to/RobotPlayer`** — a path with no extension. The sample
    /// loads `<path>.usdc` for the rig and mesh, every `<path>_*.usdc` beside it as a clip, and
    /// `<path>_ColorMap.png` as the base colour if it is there.
    ///
    /// ### Why an environment variable rather than an asset in the repository
    ///
    /// A real character is tens of megabytes and belongs to whoever made it; this repository is meant
    /// to build and run with nothing checked out beside it. But **loading one is the only way to find
    /// what a generated fixture cannot predict** — and probing one with a script, rather than running
    /// it, is exactly what produced the one wrong diagnosis this engine has had to correct. So: not
    /// shipped, and one variable away from being run.
    private func loadExternalCharacter() -> Bool {
        guard let base = ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_CHARACTER"],
              !base.isEmpty else { return false }

        let baseURL = URL(fileURLWithPath: base)
        let rigURL = baseURL.appendingPathExtension("usdc")
        guard FileManager.default.fileExists(atPath: rigURL.path) else {
            print("WindageSample: no character at \(rigURL.path)")
            return false
        }

        // Every sibling `<stem>_*.usdc` is a clip file. **Sorted, so the same two clips are picked
        // every run** — a directory listing is not ordered, and a demo that cross-fades into a
        // different animation each launch is not a demo of anything.
        let stem = baseURL.lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: baseURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        let clipURLs = siblings
            .filter { $0.pathExtension == "usdc" && $0.deletingPathExtension().lastPathComponent != stem
                      && $0.lastPathComponent.hasPrefix(stem + "_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        do {
            figureRig = try RigLoader.load(url: rigURL, clipURLs: clipURLs) {
                print("WindageSample: character clips — \($0)")
            }
        } catch {
            print("WindageSample: character rig failed — \(error)")
            return false
        }

        guard let mesh = try? MeshLoader.load(url: rigURL, device: engine.device,
                                              vertexDescriptor: SampleGame.skinnedVertexDescriptor(),
                                              semantics: SampleGame.skinnedSemantics).first else {
            print("WindageSample: character mesh failed")
            figureRig = nil
            return false
        }
        figureMesh = mesh
        figureOrientation = AssetOrientation.read(from: MDLAsset(url: rigURL))

        // **The material names no texture, and that is normal.** The tool builds the colour map in
        // memory, so there is no file for the exporter to reference; it is written beside the model
        // instead and bound by name.
        let colourMap = baseURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem)_ColorMap.png")
        if let textures, FileManager.default.fileExists(atPath: colourMap.path),
           let texture = try? textures.texture(.url(colourMap), isColor: true) {
            figureMaps = Array(repeating: texture, count: mesh.mesh.submeshes.count)
        } else {
            figureMaps = resolveBaseColorMaps(of: mesh, named: stem)
        }
        figureNormalMaps = resolveMaps(of: mesh, slot: .normal, named: stem)
        figureORMMaps = resolveMaps(of: mesh, slot: .roughness, named: stem)
        figureEmissiveMaps = resolveMaps(of: mesh, slot: .emissive, named: stem)

        engine.residencySet.addAllocations(mesh.mesh.vertexBuffers.map(\.buffer))
        engine.residencySet.addAllocations(mesh.mesh.submeshes.map(\.indexBuffer.buffer))
        if let textures { engine.residencySet.addAllocations(textures.allocations) }

        if let rig = figureRig {
            print("WindageSample: character '\(stem)' — \(rig.skeleton.jointCount) joints, "
                  + "\(mesh.mesh.vertexCount) vertices, \(figureOrientation.upAxis)-up, clips: "
                  + rig.clips.map(\.name).joined(separator: ", "))
            if rig.skeleton.jointCount > SampleGame.maxJoints {
                print("WindageSample: WARNING the rig has more joints than the palette holds")
                figureRig = nil
                return false
            }
        }
        usingExternalCharacter = figureRig != nil
        return usingExternalCharacter
    }

    private func loadFigureAsset() {
        guard skinnedPipeline != nil else { return }
        if loadExternalCharacter() { return }
        do {
            // **The rig from one file, the second animation from another.** That is how a character
            // exported one clip at a time arrives, and the clip file's own copy of the skeleton is
            // ignored — its rest pose is wherever the exporter left the rig, not the rig's.
            figureRig = try RigLoader.load(named: "figure", withExtension: "usda",
                                           clipFiles: ["figure-wave"], bundle: .module) {
                print("WindageSample: figure clips — \($0)")
            }
        } catch {
            print("WindageSample: no figure rig — \(error)")
            return
        }
        guard let mesh = try? MeshLoader.load(named: "figure", withExtension: "usda",
                                              device: engine.device,
                                              vertexDescriptor: SampleGame.skinnedVertexDescriptor(),
                                              semantics: SampleGame.skinnedSemantics,
                                              bundle: .module).first else {
            print("WindageSample: no figure mesh")
            figureRig = nil
            return
        }
        figureMesh = mesh
        figureMaps = resolveBaseColorMaps(of: mesh, named: "figure")
        figureNormalMaps = resolveMaps(of: mesh, slot: .normal, named: "figure")
        figureORMMaps = resolveMaps(of: mesh, slot: .roughness, named: "figure")
        figureEmissiveMaps = resolveMaps(of: mesh, slot: .emissive, named: "figure")
        engine.residencySet.addAllocations(mesh.mesh.vertexBuffers.map(\.buffer))
        engine.residencySet.addAllocations(mesh.mesh.submeshes.map(\.indexBuffer.buffer))
        if let textures { engine.residencySet.addAllocations(textures.allocations) }

        // **Honour the up axis the file declares.** This one says Y, so the correction is the
        // identity — but a USD out of a Blender or Unreal pipeline that did not pass through the
        // studio's own exporter says Z, and a consumer that never asks lays that character on its
        // side. Asking costs a matrix multiply at load.
        if let url = Bundle.module.url(forResource: "figure", withExtension: "usda") {
            figureOrientation = AssetOrientation.read(from: MDLAsset(url: url))
            print("WindageSample: figure asset is \(figureOrientation.upAxis)-up")
        }

        if let rig = figureRig {
            print("WindageSample: figure rig — \(rig.skeleton.jointCount) joints, clips: "
                  + rig.clips.map(\.name).joined(separator: ", "))
            if rig.skeleton.jointCount > SampleGame.maxJoints {
                print("WindageSample: WARNING the rig has more joints than the palette holds")
                figureRig = nil
            }
        }
    }

    /// Places a figure wherever the level puts a `figure` marker.
    ///
    /// **From the level file, like everything else in the scene.** A character hard-coded into the
    /// game would not prove the level format can carry one, and moving it would mean a rebuild.
    private func rebuildFigures() {
        figures.removeAll(keepingCapacity: true)
        // **First and second clip, whatever they are called.** The built-in figure names them `Idle`
        // and `figure-wave`; an external character names them whatever its exporter did. Asking for a
        // name would work for one of those and silently produce a statue for the other — so the pair
        // is positional, and printed, because "which two is it blending" is otherwise a guess.
        guard let rig = figureRig, let idleClip = rig.clips.first else { return }
        let waveClip = rig.clips.count > 1 ? rig.clips[1] : idleClip
        if figures.isEmpty {
            print("WindageSample: figures blend '\(idleClip.name)' into '\(waveClip.name)'")
        }

        for marker in level.markers(ofKind: "figure").prefix(SampleGame.maxFigures) {
            let yaw = marker.yaw
            // **Plus a half turn for an external character, and this is the finding that was
            // predicted.** Which way an asset faces is not in the file: the built-in figure is
            // symmetric front to back, and a bought character has a definite front that its own
            // toolchain points wherever it likes. It is a per-asset yaw, applied where the thing is
            // placed — which is somewhere a game already has to think.
            let facing = yaw + (usingExternalCharacter ? .pi : 0)
            let fc = cos(facing), fs = sin(facing)
            let placement = matrix_float4x4(columns: (SIMD4(fc, 0, -fs, 0),
                                                     SIMD4(0, 1, 0, 0),
                                                     SIMD4(fs, 0, fc, 0),
                                                     SIMD4(marker.position, 1)))
            // **Two corrections, both inside the placement.** The file's declared up axis, and the
            // mesh's own place in the file's node hierarchy — which is where an exported character's
            // centimetre-to-metre scale lives. Either one outside the placement would scale or rotate
            // the marker's position too, and the figure would appear in the next county.
            let node = figureMesh?.nodeTransform ?? matrix_identity_float4x4
            let transform = placement * figureOrientation.transform * node
            var figure = Figure(pose: SkeletonPose(skeleton: rig.skeleton),
                                idle: AnimationPlayhead(clip: idleClip, skeleton: rig.skeleton),
                                wave: AnimationPlayhead(clip: waveClip, skeleton: rig.skeleton),
                                transform: transform,
                                position: marker.position)
            // **Started at different points in the clip.** A row of characters moving in lockstep
            // reads as one object drawn several times, which is exactly what it is.
            figure.idle.advance(by: Float(figures.count) * 0.9)
            figures.append(figure)
        }
    }

    /// Gives every figure something to carry.
    ///
    /// **The lanterns are ordinary drawables**, appended after the level's. That is not a shortcut —
    /// it is what makes the point: a thing placed by a hierarchy is drawn, shadowed, culled and lit
    /// by exactly the same code as a thing placed by a level file, because the hierarchy produces a
    /// world transform and nothing else.
    private func rebuildLanterns() {
        lanterns = nil
        lanternJoint = nil
        lanternDrawables.removeAll(keepingCapacity: true)
        guard !figures.isEmpty, let rig = figureRig, let mesh = meshes["box"] else { return }
        guard let joint = SampleGame.lanternJoint(in: rig.skeleton) else {
            print("WindageSample: no hand-shaped joint in this rig — nobody is carrying anything")
            return
        }
        lanternJoint = joint
        print("WindageSample: lanterns hang off '\(rig.skeleton.jointPaths[joint])'")

        for _ in figures.indices {
            drawables.append((mesh, matrix_identity_float4x4, SIMD3(repeating: 1),
                              baseColorMaps["box"] ?? [], normalMaps["box"] ?? [],
                              ormMaps["box"] ?? [], emissiveMaps["box"] ?? []))
            lanternDrawables.append(drawables.count - 1)
            // **Appended to `volumes` in the same breath**, because the two are index-aligned and the
            // shadow passes cull against `volumes`. A lantern missing from it would be drawn and cast
            // nothing, which reads as the cube being broken.
            volumes.append(Volume(local: mesh.bounds, transform: matrix_identity_float4x4))
        }

        lanterns = try? TransformHierarchy(
            attachments: figures.indices.map { .external($0) },
            localTransforms: Array(repeating: SampleGame.lanternGrip, count: figures.count),
            externalCount: figures.count)
    }

    /// The joint a lantern hangs off, in whatever rig actually loaded.
    ///
    /// **The built-in figure's waving arm is its left one, and that is a fact about the clip rather
    /// than about rigs.** An external character names its joints whatever its own toolchain did, so
    /// the exact path is tried first and then a few shapes of name — and if none of them match, the
    /// figures carry nothing and say so, rather than hanging a lantern off a shin.
    private static func lanternJoint(in skeleton: Skeleton) -> Int? {
        if let index = skeleton.index(ofJoint: "root/spine/arm_l/forearm_l") { return index }
        func leaf(_ path: String) -> String {
            (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
        }
        for shape in ["hand_l", "lefthand", "hand", "forearm_l", "forearm", "wrist"] {
            if let index = skeleton.jointPaths.firstIndex(where: { leaf($0).contains(shape) }) {
                return index
            }
        }
        return nil
    }

    /// Puts every lantern where its hand is, and its light with it.
    ///
    /// ### The scale, which is the whole finding
    ///
    /// **A child inherits its parent's scale, and a rig authored in centimetres hands its wrist a
    /// hundredfold one.** That factor belongs to the arm — the forearm genuinely is fifty units long
    /// in the rig's own space — and it is exactly wrong for something merely *hung* there: the
    /// lantern comes out at one percent of its size, in a position that is otherwise correct, which
    /// reads as the wrong mesh rather than as the wrong space.
    ///
    /// `matrix_without_scale` at the call site rather than a flag inside the hierarchy, because this
    /// is a decision about *what is being attached*, and only the caller can see that.
    private func placeLanterns() {
        guard var rig = lanterns, let joint = lanternJoint, !lanternDrawables.isEmpty else { return }
        rig.refresh(attachedTo: figures.map {
            matrix_without_scale($0.transform * $0.pose.modelTransform(ofJoint: joint))
        })
        for (slot, index) in lanternDrawables.enumerated() {
            let world = rig.worldTransform(of: slot)
            drawables[index].transform = world
            volumes[index].transform = world
            if slot < lanternLights.count, lanternLights[slot] < lightSet.lights.count {
                lightSet.lights[lanternLights[slot]].position = SIMD3(world.columns.3.x,
                                                                      world.columns.3.y,
                                                                      world.columns.3.z)
            }
        }
        lanterns = rig
        // **Every frame now, because a light that moves changes which cube it deserves** — and, more
        // to the point, a cube recorded from where the lamp was last is a shadow that lags the hand.
        cubeCasters = assignShadowCubes()
    }

    /// Prefilters the level's sky into the two cubes image-based lighting needs.
    ///
    /// **The sun here is the level's sun.** An environment lit from somewhere the sun is not reads as
    /// a bug in the shading rather than as a mismatched sky, so the two come from one place.
    private func rebuildEnvironment() {
        matterLight = ParticleRenderer.matterLight(under: level.resolvedSky)
        let started = CFAbsoluteTimeGetCurrent()
        guard let built = EnvironmentMap(device: engine.device, sky: level.resolvedSky) else {
            print("WindageSample: no environment — metal will have nothing to reflect")
            return
        }
        if let previous = environment {
            engine.residencySet.removeAllocations(previous.allocations)
        }
        environment = built
        engine.residencySet.addAllocations(built.allocations)
        engine.commitResidency()
        print(String(format: "WindageSample: environment prefiltered in %.0f ms (%d mips)",
                     (CFAbsoluteTimeGetCurrent() - started) * 1000, built.specularMipCount))
    }

    /// Turn the level into things to draw, walk into and click on.
    ///
    /// The sample's ground is a plane at zero, so the anchor resolver has a trivial job — but it is
    /// still the *engine's* resolver, because what an anchor means is not this game's to reinvent.
    private func rebuild() {
        drawables.removeAll(keepingCapacity: true)
        volumes.removeAll(keepingCapacity: true)
        solidVolumes.removeAll(keepingCapacity: true)
        objectiveDrawables.removeAll(keepingCapacity: true)
        let ground = Level.Ground(heightAt: { _, _ in 0 })
        for placement in level.placements {
            guard let mesh = meshes[placement.mesh] else { continue }
            let position = level.worldPosition(of: placement, on: ground)
            let c = cos(placement.yaw), s = sin(placement.yaw), k = placement.scale
            // **Times the mesh's node transform**, which is the identity for these hand-written OBJs
            // and would not be for anything exported. Composing it unconditionally is what stops a
            // level looking correct until the first asset that has one.
            let transform = matrix_float4x4(columns: (SIMD4(c * k, 0, -s * k, 0),
                                                      SIMD4(0, k, 0, 0),
                                                      SIMD4(s * k, 0, c * k, 0),
                                                      SIMD4(position, 1))) * mesh.nodeTransform
            drawables.append((mesh, transform, SampleGame.albedo(for: placement),
                              baseColorMaps[placement.mesh] ?? [],
                              normalMaps[placement.mesh] ?? [],
                              ormMaps[placement.mesh] ?? [],
                              emissiveMaps[placement.mesh] ?? []))
            if placement.tags.contains("objective") { objectiveDrawables.append(drawables.count - 1) }
            let volume = Volume(local: mesh.bounds, transform: transform)
            volumes.append(volume)
            // **The level's own tag decides.** The engine has no idea what "solid" means; this game
            // does. Shipping the tag and then ignoring it — which this sample did on its first
            // run — is worse than not having it, because the file says something untrue.
            if placement.tags.contains("solid") { solidVolumes.append(volume) }
        }
        // **Axis-aligned world boxes, which overstate a turned crate's corners.** A crate at 45° is
        // stood beside a hand's width further off than its faces are. That is the conservative way to
        // be wrong for a thing you walk into — a player catching on air near a corner is a smaller
        // fault than a player standing inside a crate.
        surroundings = CharacterController.Surroundings(groundHeight: { _, _ in 0 },
                                                        solids: solidVolumes.map(\.worldBounds))
        rebuildFigures()
        rebuildLanterns()
        rebuildLights()
        placeLanterns()
        reportClustersNextFrame = true
        reportCubeDrawsNextFrame = true
        if drawables.count > SampleGame.maxDrawables {
            print("WindageSample: WARNING \(drawables.count) drawables against a cap of "
                  + "\(SampleGame.maxDrawables) — the rest of the level will not be drawn")
        }
    }

    /// The game's own tint, multiplied on top of the material.
    ///
    /// **It used to say what a thing *was* — earth for ground, ochre for a landmark — and now it says
    /// what a thing's *state* is.** That was not a preference: the moment surfaces carry textures,
    /// an identity tint multiplies the texture it was meant to replace, and a ground tint of 0.32
    /// takes an already-dark map down to a sixth of its brightness. Identity is the material's job
    /// now; the tint is left to the things a file cannot know — an objective that has been reached,
    /// and whatever is selected in the editor.
    private static func albedo(for placement: Level.Placement) -> SIMD3<Float> {
        SIMD3(repeating: 1)
    }

    /// **From the level's own sky.** This used to compute a direction from two `settings` keys, which
    /// meant the sun and the sky it belongs to were two separate facts that could disagree — and one
    /// of them was not in the file at all.
    private var sunDirection: SIMD3<Float> { level.resolvedSky.sunDirection }

    /// The level's lamps, plus whatever the game is lighting right now.
    ///
    /// **Rebuilt when the run changes, not every frame.** Selection is a sort over the level's lights
    /// per drawable, which is cheap — but rebuilding the *list* every frame would allocate for a set
    /// that changes only when a crate is collected.
    private var lightSet = LightSet()

    /// This frame's binning, rebuilt as the camera moves.
    private let sceneLightBuffer: MTLBuffer
    private let clusterRangeBuffer: MTLBuffer
    private let clusterIndexBuffer: MTLBuffer
    private static let sceneLightStride = MemoryLayout<PackedLight>.stride
    private static let clusterRangeStride = MemoryLayout<SIMD2<UInt32>>.stride

    /// Assembles the level's lamps and the ones the game owns.
    ///
    /// **An uncollected objective is a light as well as a glow.** Emission alone makes a crate look
    /// lit and leaves the ground beneath it dark, which is the tell that a glowing thing is a texture
    /// rather than a lamp. This is the sample's one dynamic light, and it goes out when the crate is
    /// taken.
    private func rebuildLights() {
        var lights = level.lights
        for (slot, position) in run.objectives.enumerated() {
            let taken = run.collected.indices.contains(slot) && run.collected[slot]
            guard !taken else { continue }
            lights.append(PunctualLight(position: position + SIMD3(0, 0.6, 0),
                                        colour: SIMD3(0.6, 6.0, 2.6), range: 4.5))
        }
        // **A lamp per lantern, seeded from where the lantern already is.** `rebuildLights` runs
        // again every time an objective is collected, and a light that spent one frame at the world
        // origin is a flash in the corner of the level nobody can explain afterwards.
        lanternLights.removeAll(keepingCapacity: true)
        for index in lanternDrawables {
            let at = drawables[index].transform.columns.3
            lanternLights.append(lights.count)
            lights.append(PunctualLight(position: SIMD3(at.x, at.y, at.z),
                                        colour: SIMD3(1.0, 0.72, 0.42) * 26, range: 6.5))
        }

        // **The budget is only used for the report now.** Clustering removed the per-draw limit; what
        // is left is the warning that a level has crowded a point, which is still worth knowing.
        lightSet = LightSet(lights: lights, budget: 4)

        // **Embers off the level's coneless lamps and the lanterns, and not off the crates' glow**,
        // which is a light standing in for the crate rather than a flame. Rebuilt whenever the lights
        // are, which is every collected crate — so the seed base is the light's own index, and a
        // brazier keeps throwing the same embers rather than a new pattern each time.
        let levelPoints = level.lights.indices.filter { level.lights[$0].cone == nil }
        emberEmitters = (levelPoints + lanternLights).map { index in
            (index, ParticleEmitter(recipe: SampleGame.emberRecipe,
                                    rate: lanternLights.contains(index) ? 6 : 14,
                                    seedBase: index &* 104_729))
        }
        shadowCasters = assignShadowTiles()
        cubeCasters = assignShadowCubes()
        if lights.count > SampleGame.maxSceneLights {
            print("WindageSample: WARNING \(lights.count) lights against a buffer of "
                  + "\(SampleGame.maxSceneLights) — the rest will not be lit")
        }
    }

    /// Says out loud where this level has more lights than the budget can carry.
    ///
    /// **This is the probe's finding made operational.** A hard budget cannot promise a smooth
    /// hand-over in an arbitrary level; where no more than the budget are meaningfully lit, nothing
    /// visible is ever dropped. That is a condition on the level, and a condition nobody checks is a
    /// condition nobody meets — so the sample checks it at load, on the places a player actually goes.
    private func reportOverSubscription() {
        var points = run.objectives.map { $0 + SIMD3<Float>(0, 1.7, 0) }
        points += level.markers(ofKind: "spawn").map { $0.position + SIMD3(0, 1.7, 0) }
        let crowded = lightSet.overSubscribedPoints(among: points)
        guard !crowded.isEmpty else { return }
        print("WindageSample: \(crowded.count) of \(points.count) points are over-subscribed — "
              + "more than four lights are meaningfully lit there")
    }

    /// **A courtyard's numbers, not an engine's.** Sixteen by eight tiles is roughly square cells on
    /// a wide screen; twenty-four slices over a hundred and twenty metres is where the sample's lamps
    /// stop mattering.
    private static let clusterGrid = ClusterGrid(tilesX: 16, tilesY: 8, slices: 24,
                                                 nearPlane: 0.1, lightRange: 120)

    /// The most lights a level may hold at once, and the most cluster entries a frame may produce.
    /// **Ceilings on buffers rather than on what any one fragment sees** — that number is whatever
    /// the busiest cluster came out at, and clustering is what keeps it small.
    private static let maxSceneLights = 64
    private static let maxClusterIndices = 1 << 15

    /// The light the sun actually delivers — its radiance times the solid angle its disc subtends,
    /// which is a very small number and is why the two are not interchangeable.
    ///
    /// **An overcast level says so by having a dim sun and a bright sky**, which is a thing a level
    /// can now express and previously could not.
    private var sunIrradiance: SIMD3<Float> { level.resolvedSky.sunIrradiance }

    /// What lights dust under this level's sky. Computed once per level, since the sky is the
    /// level's — see `ParticleRenderer.matterLight(under:)`.
    private var matterLight = SIMD3<Float>(repeating: 1)

    // MARK: - Levels

    /// Load a different level **while the game is running**.
    ///
    /// **Three things here were assumptions, not code, until there was a second level.** Meshes were
    /// loaded once in `init` from the first level's list, so a level using anything new drew nothing.
    /// The camera was placed in `init`, so a new spawn was ignored. And the run was sized once, so a
    /// level with a different number of objectives could not be finished. None of them would have
    /// been found by a second *copy* of the first level — only by one that differs.
    func load(level index: Int) {
        levelIndex = (index + SampleLevel.names.count) % SampleLevel.names.count
        let loaded = SampleLevel.load(levelIndex)
        editor = LevelEditor(level: loaded.level)
        levelPath = loaded.report

        loadMissingMeshes()
        rebuild()

        // Spawn where *this* level says, not where the last one did.
        let spawn = level.markers(ofKind: "spawn").first
        // A fresh body, not the old one moved: last level's fall, crouch or slide has no business
        // arriving in this one.
        body = CharacterController(feet: spawn?.position ?? SIMD3(0, 0, 12))
        camera.position = body.eye
        camera.yaw = spawn?.yaw ?? 0
        camera.pitch = radians_from_degrees(Float(spawn?.values["pitch"] ?? 0))
        previousCamera = camera

        // A fresh run, sized from this level's objectives — and keeping the progress, which is the
        // player's rather than the level's.
        run = SampleRun(objectives: level.markers(ofKind: "objective").map(\.position),
                        levelName: level.name)
        rebuildEnvironment()
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")
    }

    /// Loads any mesh this level needs that is not already in memory.
    ///
    /// **Additive rather than a reload.** Levels share most of their meshes, and throwing the lot away
    /// on every switch would stall for no reason — but a mesh has to be in the residency set before
    /// the GPU can reach it, so a newly loaded one joins it and the set is committed again.
    private func loadMissingMeshes() {
        var added: [any MTLAllocation] = []
        for name in Set(level.placements.map(\.mesh)) where meshes[name] == nil {
            guard let mesh = try? MeshLoader.load(named: name, device: engine.device,
                                                  vertexDescriptor: SampleGame.vertexDescriptor(),
                                                  semantics: SampleGame.semantics,
                                                  bundle: .module).first else {
                print("WindageSample: no mesh named \(name)")
                continue
            }
            meshes[name] = mesh
            added += mesh.mesh.vertexBuffers.map(\.buffer)
            added += mesh.mesh.submeshes.map(\.indexBuffer.buffer)
        }
        if !added.isEmpty {
            engine.residencySet.addAllocations(added)
            // **Textures too, and this is easy to forget** — a texture the GPU cannot reach is not a
            // black surface, it is whatever memory happens to be there, and it reads as a shader bug.
            if let textures { engine.residencySet.addAllocations(textures.allocations) }
            engine.commitResidency()
        }
    }

    /// The base-colour map for every submesh of a mesh, in submesh order.
    ///
    /// **From the file's own material**, not assigned here — `box.obj` names `crate.png` through its
    /// `.mtl`, and the figure names `figure.png` through its `UsdPreviewSurface`. A game that wired
    /// textures up in code would leave the loader's whole reason for existing untested.
    private func resolveMaps(of mesh: LoadedMesh, slot: TextureSlot, named name: String) -> [MTLTexture] {
        guard let textures else { return [] }
        return (0..<mesh.mesh.submeshes.count).map { index in
            let material = mesh.material(forSubmesh: index)
            guard let source = material[slot] else { return textures.fallback(for: slot) }
            do {
                // **`isColor` from the slot, never from the call site.** A normal map decoded as sRGB
                // has every value bent, and the result looks like bad lighting rather than like a
                // texture loaded wrongly.
                return try textures.texture(source, isColor: slot.isColor, bundle: .module)
            } catch {
                print("WindageSample: \(name) \(slot.rawValue) — \(error)")
                return textures.fallback(for: slot)
            }
        }
    }

    private func resolveBaseColorMaps(of mesh: LoadedMesh, named name: String) -> [MTLTexture] {
        resolveMaps(of: mesh, slot: .baseColor, named: name)
    }

    // MARK: - Editing

    /// Keys the editor takes, by macOS key code. Returns whether it consumed the event.
    ///
    /// **Consumed keys never reach `InputState`**, so `D` nudges rather than strafing. Routing every
    /// key to both and hoping they do not collide is how an editor ends up walking the camera into a
    /// wall while you are trying to move a crate.
    // MARK: - Keys in

    /// A key went down. **The game gets first refusal, then `InputState`** — a key the editor or the
    /// settings screen takes must not also walk the player.
    func keyPressed(_ code: UInt16, command: Bool) {
        // Escape is the settings screen's first — it cancels a capture or closes the screen — and
        // otherwise the pointer's, which it releases. Never a binding: see `InputBindings.fixed`.
        if code == KeyCode.escape.rawValue {
            if !handleKey(code, command: false) { input.setMouseCaptured(false) }
            return
        }
        if handleKey(code, command: command) { return }
        input.keyDown(code)
    }

    func keyReleased(_ code: UInt16) { input.keyUp(code) }

    /// A modifier changed — Shift, Control, Option, Command. **A key like any other once it gets
    /// here**, which is what lets the settings screen bind one and `InputState` sprint on one.
    func modifiersChanged(_ code: UInt16, flags: UInt) {
        let key = KeyCode(code)
        if menu != nil {
            // Captured on the way down; everything else a modifier does is swallowed while the
            // screen is open, or a held Shift would carry a sprint out of it.
            if key.isDown(inModifierFlags: flags), let action = menu?.capturing { bind(action, to: key) }
            if !key.isDown(inModifierFlags: flags) { input.flagsChanged(keyCode: code, modifierFlags: flags) }
            return
        }
        input.flagsChanged(keyCode: code, modifierFlags: flags)
    }

    func handleKey(_ code: UInt16, command: Bool) -> Bool {
        if menu != nil { return handleMenuKey(KeyCode(code)) }
        if code == KeyCode.escape.rawValue { return false }
        if code == KeyCode(named: "O")!.rawValue && !isEditing { openMenu(); return true }
        if code == 48 {                                     // tab — in and out of edit mode
            isEditing.toggle()
            input.setMouseCaptured(!isEditing)
            return true
        }
        // These work whether or not the editor is open, because a paused game you cannot unpause
        // is a hang with a label on it.
        switch code {
        case 35: run.togglePause(); return true              // p
        case 15: if !command { run.restart(); return true }  // r — but ⌘R is redo
        case 45: load(level: levelIndex + 1); return true    // n — next level
        case 46: cycleToneMapping(); return true             // m — clamp, Reinhard, ACES
        default: break
        }

        guard isEditing else { return false }

        if command {
            switch code {
            case 1:                                          // cmd-S — save
                do {
                    try editor.save(to: levelURL)
                    print("WindageSample: saved \(levelURL.path)")
                } catch { print("WindageSample: save failed — \(error)") }
            case 6: editor.undo(); rebuild()                 // cmd-Z
            case 15: editor.redo(); rebuild()                // cmd-R
            case 51:                                         // cmd-⌫ — throw the edited copy away
                // **The way back to the level this repository ships.** Once the editor has saved,
                // that copy shadows the shipped file for ever, so editing `courtyard.json` in the
                // source tree appears to do nothing. Without this the only cure is knowing where
                // Application Support is.
                if SampleLevel.discardEdits(levelIndex) {
                    print("WindageSample: discarded the edited copy")
                } else {
                    print("WindageSample: there was no edited copy to discard")
                }
                load(level: levelIndex)
            default: return false
            }
            return true
        }

        // Nudges are along the world axes rather than the camera's, so a number typed into the file
        // afterwards means the same thing as a key pressed here.
        let d = LevelEditor.nudge
        switch code {
        case 123: editor.move(by: SIMD3(-d, 0, 0))           // ←
        case 124: editor.move(by: SIMD3(d, 0, 0))            // →
        case 126: editor.move(by: SIMD3(0, 0, -d))           // ↑ — away, down the -z the camera faces
        case 125: editor.move(by: SIMD3(0, 0, d))            // ↓
        case 12: editor.move(by: SIMD3(0, d, 0))             // q — up
        case 14: editor.move(by: SIMD3(0, -d, 0))            // e — down
        case 0: editor.rotate(by: -LevelEditor.turn)         // a
        case 2: editor.rotate(by: LevelEditor.turn)          // d
        case 27: editor.scale(by: 1 / 1.25)                  // -
        case 24: editor.scale(by: 1.25)                      // =
        case 51, 117: editor.delete()                        // delete / fn-delete
        case 11: editor.duplicate()                          // b — duplicate
        case 49: pickUnderCrosshair(); return true           // space — pick, for hands already on
                                                             // the keys and for automated checks
        default: return false
        }
        rebuild()
        return true
    }

    /// Steps through the tone map curves, so the difference can be looked at rather than argued
    /// about.
    ///
    /// **`clamp` is the one worth pressing.** It is what a renderer does with no tone mapping at all,
    /// and on a lit scene the sunlit faces go flat: everything above 1 becomes the same white, so a
    /// bright surface and a *very* bright surface arrive identical.
    // MARK: - Settings screen

    private func drawSettings(_ menu: SettingsMenu, on hud: HUDRenderer, scale: Float) {
        let size = 22 * scale, line = size * 1.55
        let width = 700 * scale
        let height = line * Float(SettingsMenu.rows.count + 5)
        let left = (viewportSize.x - width) / 2, top = (viewportSize.y - height) / 2
        let white = UIColor(srgb: SIMD4(1, 1, 1, 0.95))
        let dim = UIColor(srgb: SIMD4(1, 1, 1, 0.55))
        let gold = UIColor(srgb: SIMD4(1.0, 0.85, 0.25, 1))

        hud.rect(x: left, y: top, width: width, height: height, color: UIColor(srgb: SIMD4(0.05, 0.06, 0.08, 0.86)))
        var y = top + line * 1.2
        _ = hud.text("SETTINGS", x: left + size, y: y, pointSize: size * 1.3, color: white)
        y += line * 1.3

        for (index, row) in SettingsMenu.rows.enumerated() {
            let selected = index == menu.selected
            let (label, value): (String, String) = switch row {
            case .bind(let action):
                (action.title, menu.capturing == action ? "press a key..." : settings.bindings[action].name)
            case .sensitivity: ("Look sensitivity", String(format: "%.1f", settings.lookSensitivity))
            case .invert: ("Invert look", settings.invertLook ? "on" : "off")
            case .volume: ("Volume", "\(Int((settings.volume * 100).rounded()))%")
            case .brightness: ("Brightness", String(format: "%+.2f stops", settings.brightness))
            case .reset: ("Reset to defaults", "")
            }
            let colour = selected ? gold : white
            _ = hud.text((selected ? "> " : "  ") + label, x: left + size, y: y, pointSize: size, color: colour)
            _ = hud.text(value, x: left + width * 0.58, y: y, pointSize: size, color: colour)
            y += line
        }

        y += line * 0.4
        if menu.capturing != nil {
            _ = hud.text("press the key you want · esc cancels", x: left + size, y: y, pointSize: size * 0.8, color: gold)
        } else if let message = menu.message {
            _ = hud.text(message, x: left + size, y: y, pointSize: size * 0.8, color: gold)
        }
        y += line
        _ = hud.text("up/down choose · return change · left/right adjust · o close",
                     x: left + size, y: y, pointSize: size * 0.75, color: dim)
    }

    private func openMenu() {
        var opened = SettingsMenu()
        // **Paused while it is open**, or the clock runs out behind a screen of key bindings.
        if run.mode == .playing {
            run.togglePause()
            opened.pausedTheRun = true
        }
        menu = opened
        input.setMouseCaptured(false)
    }

    private func closeMenu() {
        if menu?.pausedTheRun == true && run.mode == .paused { run.togglePause() }
        menu = nil
    }

    /// Every key while the screen is open. **Always consumed**, so nothing typed into a settings
    /// screen walks the player behind it.
    private func handleMenuKey(_ key: KeyCode) -> Bool {
        guard var current = menu else { return false }
        if let action = current.capturing {
            if key == .escape {
                current.capturing = nil
                current.message = nil
                menu = current
            } else {
                bind(action, to: key)
            }
            return true
        }

        let count = SettingsMenu.rows.count
        switch key {
        case .escape, KeyCode(named: "O")!:
            closeMenu()
            return true
        case .up: current.selected = (current.selected + count - 1) % count
        case .down: current.selected = (current.selected + 1) % count
        case .left: adjust(current.row, by: -1)
        case .right: adjust(current.row, by: 1)
        case .return:
            switch current.row {
            case .bind(let action):
                current.capturing = action
                current.message = nil
            case .invert, .sensitivity, .volume, .brightness:
                adjust(current.row, by: 1)
            case .reset:
                settings = PlayerSettings()
                current.message = "Everything back to the defaults"
                saveAndApplySettings()
            }
        default:
            break
        }
        menu = current
        return true
    }

    private func bind(_ action: InputBindings.Action, to key: KeyCode) {
        let outcome = settings.bindings.bind(action, to: key, reserving: SampleGame.reservedKeys)
        switch outcome {
        case .bound:
            menu?.message = "\(action.title) is \(key.name)"
        case .swapped(let other):
            menu?.message = "\(action.title) is \(key.name) — \(other.title) moved to "
                + settings.bindings[other].name
        case .refused:
            menu?.message = InputBindings.fixed.contains(key)
                ? "\(key.name) cannot be bound"
                : "\(key.name) is one of this game's own keys"
        }
        menu?.capturing = nil
        saveAndApplySettings()
    }

    private func adjust(_ row: SettingsMenu.Row, by steps: Int) {
        let step = Float(steps)
        switch row {
        case .sensitivity: settings.lookSensitivity = ((settings.lookSensitivity + 0.1 * step) * 10).rounded() / 10
        case .invert: settings.invertLook.toggle()
        case .volume: settings.volume = ((settings.volume + 0.1 * step) * 10).rounded() / 10
        case .brightness: settings.brightness += 0.25 * step
        case .bind, .reset: return
        }
        saveAndApplySettings()
    }

    /// Written the moment anything changes. **There is no "apply" button**: a settings screen that can
    /// be closed without saving is one a player closes without saving, and then finds their keys
    /// back the way they were.
    private func saveAndApplySettings() {
        applySettings()
        do {
            try SampleGame.settingsStore.save(settings)
        } catch {
            print("WindageSample: settings not saved — \(error)")
        }
    }

    private func applySettings() {
        input.bindings = settings.bindings
        audio?.masterVolume = settings.volume
        engine.toneMapping.exposureStops = SampleGame.baseExposure + settings.brightness
    }

    // MARK: - Footsteps

    /// Which of three recordings the next footstep uses. **An order that does not repeat every
    /// three**, so the pattern takes six steps to come round — long enough that the ear stops
    /// looking for it.
    private static let stepOrder = [0, 2, 1, 0, 1, 2]
    private var stepsPlayed = 0

    /// What the scripted walk reports for the segment in progress: footsteps, and landings.
    private var tally = (steps: 0, surfaces: Set<String>(), landings: [String]())

    /// Plays whatever the body just did.
    ///
    /// **Not positioned**, which is the engine's own advice for a sound that happens *to* the player:
    /// the ears are 1.7 m above the feet and moving with them, so a spatialised footstep would only
    /// come out a little quieter and from somewhere odd.
    private func playFootfalls() {
        // Every solid you can stand on in this sample is stone — the steps. Crates are taller than a
        // step and cannot be jumped onto, so there is no wood to walk on.
        let surface = body.groundSolid == nil ? "dirt" : "stone"
        for event in body.events {
            switch event {
            case .stride(_, let speed):
                // Louder as it gets faster: crouched is a creep, a sprint is a run.
                let crouched = body.tuning.walkSpeed * body.tuning.crouchedSpeedFraction
                let t = simd_clamp((speed - crouched) / (body.tuning.sprintSpeed - crouched), 0, 1)
                let variant = SampleGame.stepOrder[stepsPlayed % SampleGame.stepOrder.count]
                audio?.play("step_\(surface)_\(variant)", volume: 0.3 + 0.7 * t)
                stepsPlayed += 1
                tally.steps += 1
                tally.surfaces.insert(surface)
            case .landed(let impact):
                // **A step down a stair is not this** — the controller never reports one — so every
                // landing here was a fall or a jump, and how loud is how hard.
                audio?.play("land_\(surface)", volume: simd_clamp(impact / 9, 0.35, 1))
                tally.landings.append(String(format: "%.1f m/s on %@", impact, surface))
            case .jumped:
                // The push-off: a footstep, softer. A jump with no sound at the start reads as the
                // floor letting go rather than the legs pushing.
                audio?.play("step_\(surface)_0", volume: 0.4)
            }
        }
    }

    /// Plays the scripted walk's keys this step. See `ScriptedWalk`.
    private func runScript(_ deltaTime: Float) {
        guard scriptedWalk?.isRunning == true else { return }
        for event in scriptedWalk!.advance(by: deltaTime, body: body) {
            switch event {
            case .begin(let segment):
                if let yaw = segment.yaw { camera.yaw = yaw }
                if let pitch = segment.pitch { camera.pitch = pitch }
                for key in segment.keys {
                    if let flag = key.modifierFlag {
                        modifiersChanged(key.rawValue, flags: flag)
                    } else {
                        keyPressed(key.rawValue, command: false)
                    }
                }
            case .end(let segment, let report):
                for key in segment.keys {
                    if key.isModifier { modifiersChanged(key.rawValue, flags: 0) } else { keyReleased(key.rawValue) }
                }
                if let report {
                    print(report)
                    var heard = tally.steps == 1 ? "1 footstep" : "\(tally.steps) footsteps"
                    if !tally.surfaces.isEmpty { heard += " on " + tally.surfaces.sorted().joined(separator: " and ") }
                    if !tally.landings.isEmpty { heard += ", landed at " + tally.landings.joined(separator: ", ") }
                    print("WindageSample:     \(heard)")
                }
                tally = (0, [], [])
            }
        }
    }

    private func cycleToneMapping() {
        let curves = ToneMapping.Curve.allCases
        let next = curves[((curves.firstIndex(of: engine.toneMapping.curve) ?? 0) + 1) % curves.count]
        engine.toneMapping.curve = next
        print("WindageSample: tone map curve \(next), "
              + "\(engine.toneMapping.exposureStops) stops")
    }

    /// Pick whatever is under the middle of the screen.
    ///
    /// Down the crosshair rather than from the mouse position: the sample captures the pointer for
    /// look, so there *is* no mouse position while playing, and a picker that needed one would only
    /// work in a mode the sample does not have.
    func pickUnderCrosshair() {
        let origin = camera.position
        // **Not the lanterns.** The editor's selection is an index into the level's placements, and
        // a lantern has none — clicking one would select something that is not there.
        let hit = Volume.firstHit(origin: origin, direction: camera.forward,
                                  against: Array(volumes.prefix(levelVolumeCount)),
                                  maxDistance: 200)
        editor.select(hit?.index)
        rebuild()
    }

    // MARK: - GameLoop

    /// **Mouse look is consumed once per frame, not once per step.** A mouse delta is a
    /// displacement that already happened; applying it in a frame that ran three simulation steps
    /// would turn three times as far. The engine's `InputState` says so and the sample obeys it —
    /// this is the sort of thing a consumer gets wrong when the engine only documents it in one
    /// game's source.
    func beginFrame() {
        input.pollFrame()
        let look = input.consumePendingLook()
        // **A scripted walk holds its heading.** Otherwise whatever the mouse is doing over the
        // window steers it, and the same script ends somewhere different each time — which was the
        // first thing it did.
        if scriptedWalk?.isRunning != true { camera.look(mouseDelta: look * settings.lookScale) }
    }

    func step(deltaTime: Float) {
        previousCamera = camera
        // **First, and whatever state the run is in** — a script that opens the settings screen
        // pauses the run, and one that only advanced while playing would wait for ever.
        runScript(deltaTime)
        camera.turn(rate: input.lookRate * settings.lookScale, deltaTime: deltaTime)
        // **A pause is "do not advance", not "stop the loop".** The frame loop keeps running, the
        // scene still draws and the window still resizes — which is why pausing is a game's decision
        // and not something the engine has to provide.
        if !isEditing {
            let events = run.step(deltaTime: Double(deltaTime), playerAt: camera.position)
            if !events.isEmpty { rebuild() }          // a collected crate changes colour
            for crate in events.collected {
                // **At the crate, not at the player.** The whole reason the engine spatialises is
                // that a sound should come from where the thing is; playing it flat would make the
                // positional path untested by the one consumer meant to exercise it.
                audio?.play("pickup", at: crate + SIMD3(0, 1, 0))
                // **Above the lid, not at the crate's middle.** The first run threw it from 1.2 m, inside
                // a crate 1.5 m tall, and depth hid the bottom half of every burst.
                particles.burst(SampleGame.pickupRecipe, at: crate + SIMD3(0, 1.6, 0), seed: stepCount)
            }
            if events.won {
                audio?.play("win")
                // **Winning moves you on.** A game that ends and sits there is a game that stopped;
                // this is the smallest progression there is, and it is what makes a second level
                // part of the loop rather than a thing you have to ask for.
                advanceAfterWinning = 2.5
            }
            if events.lost { audio?.play("lose") }
        }

        if var wait = advanceAfterWinning {
            wait -= Double(deltaTime)
            if wait <= 0 {
                advanceAfterWinning = nil
                load(level: levelIndex + 1)
            } else {
                advanceAfterWinning = wait
            }
        }

        animateFigures(deltaTime: deltaTime)

        // **Every step, and after the lanterns have moved**, so an ember leaves the lantern where it
        // is rather than where it was. Paused or not: embers that froze mid-air would read as the game
        // having crashed, the same reason the figures keep breathing through a pause.
        for index in emberEmitters.indices where emberEmitters[index].light < lightSet.lights.count {
            let at = lightSet.lights[emberEmitters[index].light].position
            emberEmitters[index].emitter.emit(into: &particles, at: at, deltaTime: deltaTime)
        }
        particles.step(deltaTime: deltaTime)
        stepCount += 1

        // Where the ears are. Once per step is more often than needed — once per frame would do —
        // but it costs two vector writes and cannot go stale.
        audio?.updateListener(position: camera.position, forward: camera.forward, up: SIMD3(0, 1, 0))

        // In edit mode the movement keys are the editor's, so the camera holds still. So is a
        // finished run: walking around after the clock stops reads as the game not having noticed.
        if !isEditing && !run.isOver && run.mode != .paused {
            if isPhotoMode {
                camera.advance(input.movement, deltaTime: deltaTime)
            } else {
                // **Yaw from the camera, and nothing else.** Pitch never reaches the body: looking at
                // your feet does not slow the walk, and looking at the sky does not lift you off it.
                let wasAirborne = !body.isGrounded
                let fallSpeed = -body.verticalVelocity
                body.step(yaw: camera.yaw,
                          input: input.movement,
                          jump: input.isJumpHeld,
                          crouching: input.isCrouching,
                          deltaTime: deltaTime,
                          in: surroundings)
                camera.position = body.eye
                playFootfalls()
                // **Dust on a landing that was a fall**, not on every step down a stair: 4 m/s is a
                // drop of about 40 cm at this gravity, which is where a landing starts to be felt.
                if wasAirborne && body.isGrounded && fallSpeed > 4 {
                    particles.burst(SampleGame.dustRecipe, at: body.feet + SIMD3(0, 0.05, 0),
                                    seed: stepCount)
                }
            }
        }
    }

    /// How far away a figure notices the player. Chosen so a figure is waving by the time you are
    /// close enough to read the blend rather than after you have walked past it.
    private static let noticeDistance: Float = 7

    /// Advances every figure's clips and blends between them.
    ///
    /// **This is the whole animation update, and it is nine lines.** Everything expensive —
    /// sampling, the parent chain, the cross-fade — is `SkeletonPose.set(to:blendedWith:weight:)`,
    /// and the game's part is deciding *what* to play. That split is the point: a game that had to
    /// walk a joint hierarchy to make a character wave would have an engine that had not finished
    /// the job.
    ///
    /// **Runs while editing and while paused.** A frozen character in a paused game looks broken in
    /// a way a frozen crate does not.
    private func animateFigures(deltaTime: Float) {
        for index in figures.indices {
            figures[index].idle.advance(by: deltaTime)
            figures[index].wave.advance(by: deltaTime)

            let distance = simd_distance(figures[index].position, camera.position)
            let target: Float = distance < SampleGame.noticeDistance ? 1 : 0
            // Eased rather than switched. A cross-fade is the only reason the pose keeps rotation as
            // a quaternion, and snapping between clips would waste it — a quarter of a second is
            // about where a hand-over stops reading as a glitch.
            let rate = min(deltaTime / 0.25, 1)
            figures[index].waveWeight += (target - figures[index].waveWeight) * rate

            figures[index].pose.set(to: figures[index].idle,
                                    blendedWith: figures[index].wave,
                                    weight: figures[index].waveWeight)
        }
        // **After the poses, never before.** A lantern placed from last step's pose is a hand and a
        // held object a frame apart, which is the one artefact everybody recognises as wrong.
        placeLanterns()
    }

    func viewportChanged(width: Int, height: Int) {
        aspectRatio = Float(width) / Float(max(height, 1))
        viewportSize = SIMD2(Float(width), Float(height))
    }

    private func uniformOffset(frameSlot: Int, drawable index: Int) -> Int {
        frameSlot * SampleGame.uniformStride * SampleGame.uniformSlots + index * SampleGame.uniformStride
    }

    /// Figures take the slots after the level's drawables in the same buffer.
    private func uniformOffset(frameSlot: Int, figure index: Int) -> Int {
        uniformOffset(frameSlot: frameSlot, drawable: SampleGame.maxDrawables + index)
    }

    private func jointOffset(frameSlot: Int, figure index: Int) -> Int {
        (frameSlot * SampleGame.maxFigures + index) * SampleGame.jointPaletteStride
    }

    private var visibleFigureCount: Int { min(figures.count, SampleGame.maxFigures) }

    /// The highest mip a shader may ask the specular cube for: `roughness × this`.
    private var environmentLOD: Float {
        Float(max((environment?.specularMipCount ?? 1) - 1, 0))
    }

    private var visibleDrawableCount: Int { min(drawables.count, SampleGame.maxDrawables) }

    /// The camera as drawn: between the last two steps, plus the slide's dip.
    ///
    /// **The dip goes on the view and never on `camera`**, which is the aim. Folded into the aim, a
    /// slide would leave the player looking somewhere new every time — the same rule a scope's sway
    /// follows.
    private func displayCamera(_ interpolation: Float) -> Camera {
        var view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
        view.pitch += body.slideCameraDip
        return view
    }

    /// **Written before the shadow pass, not during the main one.** The shadow pass reads the same
    /// `model` matrix the main pass will; writing them in `encode` would record shadows from last
    /// frame's positions, which reads as shadows lagging behind their casters.
    private func writeUniforms(frameSlot: Int, interpolation: Float) {
        let view = displayCamera(interpolation)
        writeClusters(frameSlot: frameSlot, camera: view)
        let projection = matrix_perspective_right_hand_reverse_z(
            fovyRadians: radians_from_degrees(70), aspectRatio: aspectRatio, nearZ: 0.1)
        let viewProjection = simd_mul(projection, view.viewMatrix)

        for (index, drawable) in drawables.prefix(SampleGame.maxDrawables).enumerated() {
            var albedo = drawable.albedo

            // **An objective still to reach emits; one already taken does not.** It used to swap its
            // albedo instead, which is a colour a surface *is* — so a collected crate and an
            // uncollected one differed the way two paints differ. Emission is light the surface makes,
            // it survives being in shadow, and it is above 1 so the tone map rolls it towards white:
            // it reads as powered rather than as painted.
            var emissive = drawable.mesh.material(forSubmesh: 0).emissive
            if let slot = objectiveDrawables.firstIndex(of: index) {
                let taken = run.collected.indices.contains(slot) && run.collected[slot]
                // **Modest, because the whole crate emits and emission is unshaded.** A surface that
                // makes its own light has no light direction, so an object emitting over all of it is
                // flat by definition — which is why a real emissive surface is a strip or a panel,
                // confined by a *map*. `box.obj` cannot have one: Model I/O reads neither `Ke` nor
                // `map_Ke` from an OBJ. So the glow stays low enough that the planks and the sun's
                // shading still carry the shape, and the emission reads as a tint from within.
                emissive = taken ? .zero : SIMD3(0.05, 0.40, 0.18)
                albedo = taken ? SIMD3(0.34, 0.36, 0.34) : SIMD3(0.42, 0.62, 0.45)
            }
            // A lantern is a lamp with a body: the light is a `PunctualLight` and this is the part
            // you can see. Well above 1 so the tone map rolls it towards white.
            if lanternDrawables.contains(index) {
                emissive = SIMD3(3.4, 2.1, 0.9)
                albedo = SIMD3(1.0, 0.86, 0.62)
            }
            // The selection glows too, because an editor where you cannot tell what is selected is a
            // way to move the wrong thing.
            if isEditing && index == editor.selection { emissive = SIMD3(1.6, 1.2, 0.3) }
            // **The first submesh's material, and the sample is honest that this is a shortcut.**
            // Uniforms here are per drawable, so a mesh whose submeshes differ in roughness would
            // get the first one's for all of them. Every mesh in this sample has one submesh; a game
            // with multi-material meshes writes a set of uniforms per submesh instead.
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: drawable.transform,
                                    normalMatrix: normalMatrix(from: drawable.transform),
                                    albedo: albedo,
                                    sunDirection: sunDirection,
                                    material: drawable.mesh.material(forSubmesh: 0),
                                    specularLOD: environmentLOD,
                                    sunColour: sunIrradiance,
                                    emissive: emissive)
            uniformBuffer.contents().advanced(by: uniformOffset(frameSlot: frameSlot, drawable: index))
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
        }

        for (index, figure) in figures.prefix(SampleGame.maxFigures).enumerated() {
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: figure.transform,
                                    normalMatrix: normalMatrix(from: figure.transform),
                                    // No tint: the figure's colour is its texture's, which is the
                                    // point of it having one.
                                    albedo: SIMD3(repeating: 1),
                                    sunDirection: sunDirection,
                                    material: figureMesh?.material(forSubmesh: 0) ?? Material(),
                                    specularLOD: environmentLOD,
                                    sunColour: sunIrradiance,
                                    // **Times three, and that is the game's call.** A PNG cannot hold
                                    // a value above 1, so an emissive map alone can never be brighter
                                    // than white — and a seam that is exactly white does not read as
                                    // lit. How much brighter is a look decision, so it lives here.
                                    emissive: (figureMesh?.material(forSubmesh: 0).emissive ?? .zero)
                                        * SampleGame.figureGlow)
            uniformBuffer.contents().advanced(by: uniformOffset(frameSlot: frameSlot, figure: index))
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)

            // The palette straight out of the pose — no conversion, because `skinningMatrices` is
            // already exactly what the vertex shader indexes.
            figure.pose.skinningMatrices.withUnsafeBytes { source in
                jointBuffer.contents().advanced(by: jointOffset(frameSlot: frameSlot, figure: index))
                    .copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
        }
    }

    /// Bins this frame's lights into the clusters they reach, and uploads the result.
    ///
    /// **Every frame, because the grid is in view space.** The lights have not moved but the camera
    /// has, and a cell is a piece of the frustum rather than a piece of the world.
    private func writeClusters(frameSlot: Int, camera: Camera) {
        let projectionFovY = radians_from_degrees(70)
        let clustered = ClusteredLights(lights: Array(lightSet.lights.prefix(SampleGame.maxSceneLights)),
                                        grid: SampleGame.clusterGrid,
                                        viewMatrix: camera.viewMatrix,
                                        fovY: projectionFovY,
                                        aspectRatio: aspectRatio,
                                        maximumIndices: SampleGame.maxClusterIndices)

        var lights = lightSet.lights.prefix(SampleGame.maxSceneLights).map(PackedLight.init)
        if let shadowAtlas {
            for (lightIndex, caster) in shadowCasters where lightIndex < lights.count {
                let (offset, scale) = shadowAtlas.tile(caster.tile).uvTransform(atlasSize: shadowAtlas.size)
                lights[lightIndex].shadowTile = SIMD4(offset.x, offset.y, scale, 1)
                lights[lightIndex].shadowViewProjection = caster.viewProjection
            }
        }
        if let shadowCubes {
            for (lightIndex, caster) in cubeCasters where lightIndex < lights.count {
                // **The near plane travels with the light**, because it is what the shader's
                // reference depth is made of: `near / distance`. Reading it from a shader constant
                // instead would be one number written down twice.
                // **The face's texel size travels with the light too.** It was a shader constant
                // written as `2 / 512`, which is a number in two places the moment a game asks for a
                // different resolution — and the failure is a filter kernel of the wrong width, which
                // looks like a bias problem rather than like a stale constant.
                lights[lightIndex].shadowCube = SIMD4(Float(caster.slice), shadowCubes.nearPlane,
                                                      2 / Float(shadowCubes.size), 1)
            }
        }
        lights.withUnsafeBytes { source in
            guard let base = source.baseAddress, source.count > 0 else { return }
            sceneLightBuffer.contents()
                .advanced(by: frameSlot * SampleGame.sceneLightStride * SampleGame.maxSceneLights)
                .copyMemory(from: base, byteCount: source.count)
        }
        clustered.ranges.withUnsafeBytes { source in
            guard let base = source.baseAddress, source.count > 0 else { return }
            clusterRangeBuffer.contents()
                .advanced(by: frameSlot * SampleGame.clusterRangeStride
                                        * SampleGame.clusterGrid.clusterCount)
                .copyMemory(from: base, byteCount: source.count)
        }
        clustered.indices.withUnsafeBytes { source in
            guard let base = source.baseAddress, source.count > 0 else { return }
            clusterIndexBuffer.contents()
                .advanced(by: frameSlot * MemoryLayout<UInt32>.stride * SampleGame.maxClusterIndices)
                .copyMemory(from: base, byteCount: source.count)
        }
        busiestCluster = clustered.busiestCluster

        // **Said once per level, because it is the number that decides the worst fragment's cost.**
        // Per-draw selection made that number a constant the game chose; clustering makes it a fact
        // about the scene, and one worth watching rather than assuming.
        if reportClustersNextFrame {
            reportClustersNextFrame = false
            let grid = SampleGame.clusterGrid
            print("WindageSample: \(lightSet.lights.count) lights binned into "
                  + "\(grid.tilesX)×\(grid.tilesY)×\(grid.slices) clusters — "
                  + "\(clustered.indices.count) entries, busiest cluster holds "
                  + "\(clustered.busiestCluster)")
        }
    }

    /// Which lights got a tile of the shadow atlas this frame, and where they look from.
    ///
    /// **Spots only, and only as many as there are tiles.** Ranked by how much light they are
    /// putting out, because a lamp nobody can see casting a shadow nobody can see is the tile to give
    /// away first.
    private func assignShadowTiles() -> [(lightIndex: Int, caster: ShadowAtlas.Caster)] {
        guard let shadowAtlas else { return [] }
        let candidates = lightSet.lights.enumerated()
            .filter { $0.element.cone != nil }
            .sorted { PunctualLight.luminance($0.element.colour) * $0.element.range
                    > PunctualLight.luminance($1.element.colour) * $1.element.range }
            .prefix(shadowAtlas.tileCount)

        return candidates.enumerated().compactMap { tile, entry in
            guard let matrix = ShadowAtlas.viewProjection(for: entry.element) else { return nil }
            return (entry.offset, ShadowAtlas.Caster(tile: tile, viewProjection: matrix))
        }
    }

    /// Which point lights got a cube this frame.
    ///
    /// **The same ranking as the tiles and a much smaller number.** A cube is six passes, so the
    /// question "which lamp deserves one" is six times as sharp as it is for a spot — and a level with
    /// three braziers is going to have to answer it.
    private func assignShadowCubes() -> [(lightIndex: Int, caster: ShadowCubes.Caster)] {
        guard let shadowCubes else { return [] }
        return lightSet.lights.enumerated()
            .filter { $0.element.cone == nil }
            .sorted { PunctualLight.luminance($0.element.colour) * $0.element.range
                    > PunctualLight.luminance($1.element.colour) * $1.element.range }
            .prefix(shadowCubes.lightCount)
            .enumerated()
            .map { slice, entry in
                (entry.offset, ShadowCubes.Caster(slice: slice, position: entry.element.position,
                                                  range: entry.element.range))
            }
    }

    /// The most lights any one cluster held last frame — **the number that decides the worst
    /// fragment's cost**, and the one clustering exists to keep small.
    private(set) var busiestCluster = 0
    private var reportClustersNextFrame = true
    private var reportCubeDrawsNextFrame = true

    /// The shadow pass, before anything is drawn to the screen.
    func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float) {
        writeUniforms(frameSlot: frameSlot, interpolation: interpolation)
        guard let shadowMap else { return }

        let view = displayCamera(interpolation)
        let matrices = shadowMap.updateMatrices(frameSlot: frameSlot, camera: view,
                                                sunDirection: sunDirection)

        let cascades = SampleGame.cascades
        let projection = matrix_perspective_right_hand_reverse_z(
            fovyRadians: radians_from_degrees(70), aspectRatio: aspectRatio, nearZ: 0.1)
        var frame = FrameUniforms(
            cascadeViewProjection: (matrices[0], matrices[1], matrices[2], matrices[3]),
            inverseViewProjection: simd_inverse(simd_mul(projection, view.viewMatrix)),
            view: view.viewMatrix,
            cascadeSplits: cascades.splitVector,
            cascadeBlendStart: cascades.blendStartVector,
            cascadeDepthBias: cascades.depthBiasVector,
            cameraPosition: view.position,
            texelSize: 1 / Float(cascades.resolution),
            viewportSize: viewportSize,
            clusters: PackedClusterGrid(SampleGame.clusterGrid))
        shadowFrameBuffer.contents().advanced(by: frameSlot * SampleGame.shadowFrameStride)
            .copyMemory(from: &frame, byteCount: MemoryLayout<FrameUniforms>.size)

        guard let shadowPipeline else { return }
        var batches = [ShadowMap.Batch(
            pipeline: shadowPipeline,
            count: visibleDrawableCount,
            mesh: { self.drawables[$0].mesh.mesh },
            uniformAddress: { self.uniformBuffer.gpuAddress
                + UInt64(self.uniformOffset(frameSlot: frameSlot, drawable: $0)) },
            // **`volumes` is index-aligned with `drawables`** — the same loop appends to both, which
            // is the reason the game has one list of "what is there" rather than two.
            bounds: { self.volumes[$0].worldBounds })]

        if let skinnedShadowPipeline, let mesh = figureMesh, visibleFigureCount > 0 {
            batches.append(ShadowMap.Batch(
                pipeline: skinnedShadowPipeline,
                count: visibleFigureCount,
                mesh: { _ in mesh.mesh },
                uniformAddress: { self.uniformBuffer.gpuAddress
                    + UInt64(self.uniformOffset(frameSlot: frameSlot, figure: $0)) },
                jointPaletteAddress: { self.jointBuffer.gpuAddress
                    + UInt64(self.jointOffset(frameSlot: frameSlot, figure: $0)) },
                // **The bind pose, widened.** A skinned mesh's bounds are the pose's, not the file's,
                // and a raised arm leaves the box the loader measured. Half a metre covers this
                // sample's clips; a game with a vault or a dive computes it from the pose instead.
                bounds: { Volume(local: mesh.bounds, transform: self.figures[$0].transform)
                    .worldBounds.expanded(by: 0.5) }))
        }

        shadowMap.encode(into: commandBuffer, frameSlot: frameSlot, batches: batches)

        // **The lamps' maps, after the sun's and in one pass of their own.** Same batches, same
        // pipelines — a spot's shadow map is a perspective render, which is the shape the cascade
        // pipelines already are.
        if let shadowAtlas, !shadowCasters.isEmpty {
            shadowAtlas.encode(into: commandBuffer, frameSlot: frameSlot,
                               casters: shadowCasters.map(\.caster), batches: batches)
        }

        // **And the lamps that point nowhere, six faces each.** Reported once per level because six
        // times the passes is the sort of cost that should be visible rather than inferred.
        if let shadowCubes, !cubeCasters.isEmpty {
            let draws = shadowCubes.encode(into: commandBuffer, frameSlot: frameSlot,
                                           casters: cubeCasters.map(\.caster), batches: batches)
            if reportCubeDrawsNextFrame {
                reportCubeDrawsNextFrame = false
                let unculled = cubeCasters.count * ShadowCubes.faceCount
                    * batches.reduce(0) { $0 + $1.count }
                print("WindageSample: \(cubeCasters.count) point light(s) casting — \(draws) draws "
                      + "against \(unculled) unculled")
            }
        }
    }

    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])

        argumentTable.setAddress(
            shadowFrameBuffer.gpuAddress + UInt64(frameSlot * SampleGame.shadowFrameStride), index: 2)
        if let shadowMap { argumentTable.setTexture(shadowMap.texture.gpuResourceID, index: 0) }
        if let shadowAtlas { argumentTable.setTexture(shadowAtlas.texture.gpuResourceID, index: 7) }
        if let shadowCubes { argumentTable.setTexture(shadowCubes.texture.gpuResourceID, index: 8) }
        if let environment {
            argumentTable.setTexture(environment.specular.gpuResourceID, index: 3)
            argumentTable.setTexture(environment.irradiance.gpuResourceID, index: 4)
        }

        argumentTable.setAddress(
            sceneLightBuffer.gpuAddress
                + UInt64(frameSlot * SampleGame.sceneLightStride * SampleGame.maxSceneLights),
            index: 4)
        argumentTable.setAddress(
            clusterRangeBuffer.gpuAddress
                + UInt64(frameSlot * SampleGame.clusterRangeStride
                                   * SampleGame.clusterGrid.clusterCount),
            index: 5)
        argumentTable.setAddress(
            clusterIndexBuffer.gpuAddress
                + UInt64(frameSlot * MemoryLayout<UInt32>.stride * SampleGame.maxClusterIndices),
            index: 6)

        encodeSky(into: encoder)

        for (index, drawable) in drawables.prefix(SampleGame.maxDrawables).enumerated() {
            argumentTable.setAddress(
                uniformBuffer.gpuAddress + UInt64(uniformOffset(frameSlot: frameSlot, drawable: index)),
                index: 1)

            let mesh = drawable.mesh.mesh
            for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                argumentTable.setAddress(vertexBuffer.buffer.gpuAddress + UInt64(vertexBuffer.offset),
                                         index: bufferIndex)
            }
            let maps = drawable.maps
            for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
                // **Per submesh, because a material is per submesh** — that is the unit a file binds
                // one to, and a mesh with a painted body and a metal fitting is two submeshes.
                bindSurface(maps.indices.contains(submeshIndex) ? maps[submeshIndex] : nil,
                            drawable.normals.indices.contains(submeshIndex)
                                ? drawable.normals[submeshIndex] : nil,
                            drawable.orm.indices.contains(submeshIndex)
                                ? drawable.orm[submeshIndex] : nil,
                            drawable.glow.indices.contains(submeshIndex)
                                ? drawable.glow[submeshIndex] : nil)
                encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType,
                                              indexCount: submesh.indexCount,
                                              indexType: submesh.indexType,
                                              indexBuffer: submesh.indexBuffer.buffer.gpuAddress
                                                  + UInt64(submesh.indexBuffer.offset),
                                              indexBufferLength: submesh.indexBuffer.length)
            }
        }

        encodeFigures(into: encoder, frameSlot: frameSlot)

        // **Last, into the scene rather than onto the interface**: a spark goes through the tone map
        // like the lamp it came off. After everything opaque, so depth can hide the ones behind.
        if let particleRenderer {
            let view = displayCamera(interpolation)
            let projection = matrix_perspective_right_hand_reverse_z(
                fovyRadians: radians_from_degrees(70), aspectRatio: aspectRatio, nearZ: 0.1)
            particleRenderer.draw(particles, into: encoder, frameSlot: frameSlot,
                                  viewProjection: simd_mul(projection, view.viewMatrix), camera: view,
                                  matterLight: matterLight)
        }
    }

    /// The sky, drawn first and covered by everything else.
    ///
    /// **The same cube the surfaces reflect.** A flat clear colour behind a metal object reflecting a
    /// sky with a sun in it is two skies in one picture, and that is among the first things an eye
    /// finds wrong with a render.
    private func encodeSky(into encoder: MTL4RenderCommandEncoder) {
        guard let skyPipeline, let skyDepthState, environment != nil else { return }
        encoder.setRenderPipelineState(skyPipeline)
        encoder.setDepthStencilState(skyDepthState)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)

        // Put the scene's state back, since the sky borrowed the encoder.
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
    }

    /// Binds a base-colour map, falling back to the store's white pixel.
    ///
    /// **Something is always bound.** The alternative is a shader that branches on whether a texture
    /// exists, or a second pipeline compiled without one — a branch per fragment, or twice the
    /// pipelines. White multiplies to nothing.
    private func bindSurface(_ base: MTLTexture?, _ normal: MTLTexture?, _ orm: MTLTexture?,
                             _ glow: MTLTexture?) {
        if let resolved = base ?? textures?.white {
            argumentTable.setTexture(resolved.gpuResourceID, index: 1)
        }
        // **The normal fallback is not the white one.** A white pixel decodes to the normal (1, 1, 1),
        // which tilts every surface diagonally and lights the whole scene wrongly.
        if let resolved = normal ?? textures?.flatNormal {
            argumentTable.setTexture(resolved.gpuResourceID, index: 2)
        }
        // **White is exactly right here**, because the shader multiplies: a surface with no map keeps
        // its material's own occlusion, roughness and metalness untouched.
        if let resolved = orm ?? textures?.white {
            argumentTable.setTexture(resolved.gpuResourceID, index: 5)
        }
        // **White again, and again because it is multiplied.** A surface with no emissive map emits
        // whatever its material says — which for almost everything is nothing at all.
        if let resolved = glow ?? textures?.white {
            argumentTable.setTexture(resolved.gpuResourceID, index: 6)
        }
    }

    /// The characters, in one pipeline change rather than one per object.
    ///
    /// **Same fragment shader, same shadow map, same uniforms** — a skinned mesh differs from the
    /// rest of the scene in exactly two things: where its vertices are and what moved them there.
    private func encodeFigures(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
        guard let skinnedPipeline, let mesh = figureMesh?.mesh, visibleFigureCount > 0 else { return }
        encoder.setRenderPipelineState(skinnedPipeline)

        for index in 0..<visibleFigureCount {
            argumentTable.setAddress(
                uniformBuffer.gpuAddress + UInt64(uniformOffset(frameSlot: frameSlot, figure: index)),
                index: 1)
            argumentTable.setAddress(
                jointBuffer.gpuAddress + UInt64(jointOffset(frameSlot: frameSlot, figure: index)),
                index: 3)

            for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                argumentTable.setAddress(vertexBuffer.buffer.gpuAddress + UInt64(vertexBuffer.offset),
                                         index: bufferIndex)
            }
            for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
                bindSurface(figureMaps.indices.contains(submeshIndex) ? figureMaps[submeshIndex] : nil,
                            figureNormalMaps.indices.contains(submeshIndex)
                                ? figureNormalMaps[submeshIndex] : nil,
                            figureORMMaps.indices.contains(submeshIndex)
                                ? figureORMMaps[submeshIndex] : nil,
                            figureEmissiveMaps.indices.contains(submeshIndex)
                                ? figureEmissiveMaps[submeshIndex] : nil)
                encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType,
                                              indexCount: submesh.indexCount,
                                              indexType: submesh.indexType,
                                              indexBuffer: submesh.indexBuffer.buffer.gpuAddress
                                                  + UInt64(submesh.indexBuffer.offset),
                                              indexBufferLength: submesh.indexBuffer.length)
            }
        }
    }

    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
        guard let hud else { return }
        hud.begin(viewportSize: viewportSize)

        // **Sized against the drawable, not in raw pixels.** The viewport is in *pixels*, and on a
        // Retina display that is twice the points — so text asked for at "20" rendered at ten points
        // and was reported as unreadable. Scaling against a 1080-pixel reference is
        // resolution-independent rather than tuned to one machine.
        let scale = max(viewportSize.y / 1080, 0.75)
        let title = 30 * scale, body = 21 * scale, hint = 17 * scale
        let margin = 22 * scale
        let white = UIColor(srgb: SIMD4(1, 1, 1, 0.95))
        let gold = UIColor(srgb: SIMD4(1.0, 0.85, 0.25, 1))
        let green = UIColor(srgb: SIMD4(0.45, 0.95, 0.6, 1))
        let red = UIColor(srgb: SIMD4(1.0, 0.45, 0.4, 1))

        // **`y` is a baseline and glyphs draw upward from it**, so the first line starts a full
        // line-height down or its ascenders run off the top edge — which is what "COURTYARD touches
        // the top" was.
        var y = margin + title
        _ = hud.text("\(level.name)   \(levelIndex + 1)/\(SampleLevel.names.count)",
                     x: margin, y: y, pointSize: title, color: white)
        y += title * 1.5

        let clock = String(format: "%02d:%02d", Int(run.remaining) / 60, Int(run.remaining) % 60)
        _ = hud.text("CRATES \(run.found)/\(run.objectives.count)     \(clock)",
                     x: margin, y: y,
                     pointSize: body, color: run.remaining < 15 ? red : white)
        y += body * 1.4

        if let best = run.best {
            _ = hud.text(String(format: "best %.1fs   ·   %d of %d runs won",
                                best, run.progress.wins, run.progress.runs),
                         x: margin, y: y, pointSize: hint, color: white)
        } else {
            _ = hud.text("no run finished yet", x: margin, y: y, pointSize: hint, color: white)
        }
        y += hint * 1.6

        switch run.mode {
        case .paused:
            // Not while the settings screen is open: it paused the run itself, it takes every key
            // including P, and "p to resume" would be an instruction that does nothing.
            if menu == nil {
                _ = hud.text("PAUSED — p to resume", x: margin, y: y, pointSize: body, color: gold)
            }
        case .won(let seconds):
            _ = hud.text(String(format: "ALL FOUND in %.1fs — r to run again", seconds),
                         x: margin, y: y, pointSize: body, color: green)
        case .lost:
            _ = hud.text("OUT OF TIME — r to run again", x: margin, y: y, pointSize: body, color: red)
        case .playing:
            break
        }

        if isEditing {
            let what = editor.selected.map {
                "\($0.mesh)  yaw \(Int($0.yaw * 180 / .pi))°  scale \(String(format: "%.2f", $0.scale))"
            }
            _ = hud.text("EDIT\(editor.isDirty ? " •" : "")   \(what ?? "aim and click to pick")",
                         x: margin, y: y + body * 1.4, pointSize: body, color: gold)
            _ = hud.text("click pick · arrows move · q/e up · a/d turn · -/= scale · b copy · ⌫ delete",
                         x: margin, y: viewportSize.y - margin - hint * 1.4, pointSize: hint, color: white)
            _ = hud.text("⌘S save · ⌘Z undo · ⌘R redo · ⌘⌫ revert to shipped · tab back to walking",
                         x: margin, y: viewportSize.y - margin, pointSize: hint, color: white)
        } else {
            // **The hints follow whichever device is actually plugged in.** Telling somebody holding
            // a controller to press WASD is a small lie the game is in a position to avoid, and the
            // engine already reports which it has.
            // **From the bindings, not typed in.** The hint that said "shift sprint" while Shift did
            // nothing was written by hand; one that reads the bindings cannot disagree with them.
            let b = settings.bindings
            let directions = [b[.forward], b[.left], b[.back], b[.right]].map(\.name)
            let move = directions.allSatisfy { $0.count == 1 }
                ? directions.joined() : directions.joined(separator: "/")
            let moving = input.isGamepadConnected
                ? "left stick move · right stick look · cross jump · circle crouch"
                : "\(move) move · \(b[.sprint].name.lowercased()) sprint · "
                    + "\(b[.jump].name.lowercased()) jump · \(b[.crouch].name.lowercased()) crouch · "
                    + "click to capture"
            _ = hud.text(moving, x: margin, y: viewportSize.y - margin - hint * 1.4,
                         pointSize: hint, color: white)
            _ = hud.text("o settings · p pause · r restart · n next level · m tone map · tab edit",
                         x: margin, y: viewportSize.y - margin, pointSize: hint, color: white)
        }

        if let menu { drawSettings(menu, on: hud, scale: scale) }

        // A centre dot, so turning has something to turn about.
        let dot = 3 * scale
        hud.rect(x: viewportSize.x / 2 - dot, y: viewportSize.y / 2 - dot,
                 width: dot * 2, height: dot * 2, color: white)
        hud.draw(into: encoder, frameSlot: frameSlot)
    }
}
