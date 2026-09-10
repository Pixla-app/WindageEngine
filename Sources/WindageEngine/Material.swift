//
//  Material.swift
//  WindageEngine
//

import Foundation
import ModelIO
import simd

/// Which map a texture is, and therefore how it must be read.
///
/// **The split that matters is colour against numbers**, and getting it wrong is the single most
/// common texture bug there is — see ``isColor``.
public nonisolated enum TextureSlot: String, Sendable, Hashable, CaseIterable {
    case baseColor
    case normal
    case metallic
    case roughness
    case ambientOcclusion
    case emissive

    /// Whether this map holds a **colour** or **numbers**.
    ///
    /// A colour map is authored in sRGB — the encoding a monitor expects, which spends more of its
    /// range on darks because eyes do. Shading arithmetic is only correct in linear space, so a
    /// colour texture has to be decoded on the way in. The GPU does that for free if the texture is
    /// created with an `_srgb` pixel format, and not at all if it is not.
    ///
    /// **A roughness or normal map is not a colour.** Its bytes are already numbers. Decode one as
    /// sRGB and every value is bent — mid-grey roughness 0.5 arrives as 0.21, so everything looks
    /// wetter than it was authored, and a normal map's flat regions stop being flat.
    ///
    /// Both mistakes look like a lighting problem rather than a loading one, which is why this is a
    /// property of the slot and not a decision left to each caller.
    public var isColor: Bool { self == .baseColor || self == .emissive }
}

/// Where a texture comes from, before anything has loaded it.
///
/// **Unresolved on purpose.** Reading a material's numbers needs no GPU; turning a file into an
/// `MTLTexture` does. Keeping the reference as data means ``Material`` stays testable, `Sendable`
/// and free of any device — the same split that makes `RigLoader` testable.
public nonisolated enum TextureSource: Sendable, Hashable {
    /// A file on disk, usually resolved by Model I/O relative to the asset that named it.
    case url(URL)
    /// A resource in a bundle, by name including its extension.
    case named(String)
}

/// How a surface responds to light: the metallic-roughness parameter set.
///
/// **This set and not another, because it is the one everything speaks.** glTF, USD's
/// `UsdPreviewSurface`, Unreal, Unity's standard shader and every DCC exporter agree on base colour,
/// metallic, roughness, normal, occlusion and emissive. An engine that invented its own vocabulary
/// would make every bought asset a conversion problem.
///
/// ### This is a material, not a material *system*
///
/// It is a value type describing a surface, and that is deliberately all it is. **No shader graph,
/// no permutations, no passes, no authoring model** — those are the contested part, where engines
/// genuinely disagree and where one game's needs would decide it wrongly for everybody. What is
/// settled is the parameter set, and that is what this is.
public nonisolated struct Material: Sendable, Equatable {

    public var name: String

    /// Linear, with alpha carrying opacity. **Multiplied with ``TextureSlot/baseColor`` when there
    /// is one**, so a material with a texture normally leaves this white.
    public var baseColor: SIMD4<Float>

    /// 0 for everything that is not metal, 1 for bare metal, and very little in between is physical.
    public var metallic: Float

    /// 0 is a mirror, 1 is chalk.
    public var roughness: Float

    /// Light the surface emits regardless of what is shining on it. Linear.
    public var emissive: SIMD3<Float>

    public var textures: [TextureSlot: TextureSource]

    /// **Defaults chosen so that a material nobody filled in still draws.** White, dielectric and
    /// fairly rough is a plausible painted surface; zeroes would be a black hole and 0 roughness a
    /// mirror, and both read as a bug in the renderer rather than a missing material.
    public init(name: String = "",
                baseColor: SIMD4<Float> = SIMD4(1, 1, 1, 1),
                metallic: Float = 0,
                roughness: Float = 0.65,
                emissive: SIMD3<Float> = .zero,
                textures: [TextureSlot: TextureSource] = [:]) {
        self.name = name
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.emissive = emissive
        self.textures = textures
    }

    public subscript(slot: TextureSlot) -> TextureSource? {
        get { textures[slot] }
        set { textures[slot] = newValue }
    }
}

nonisolated extension Material {

    /// Reads a material out of Model I/O's.
    ///
    /// ### Two properties can share one semantic, and `property(with:)` hides that
    ///
    /// **The finding this method exists for.** A USD `UsdPreviewSurface` with a textured diffuse
    /// arrives as *two* properties both carrying `.baseColor`: a float3 named `baseColor` and a
    /// texture named `diffuseColor`. `MDLMaterial.property(with:)` returns whichever it reaches
    /// first, so a loader using it gets a colour on one asset and a texture on the next, with
    /// nothing to say which. Every semantic here is read from the **whole list**.
    ///
    /// ### Model I/O's own default is 0.18 grey, and it is not the file's intent
    ///
    /// That float3 `baseColor` above is 0.18 in a file that never mentioned a base colour — it is
    /// the importer filling in a principled-shader default. Multiply a texture by it and the whole
    /// asset comes in at 18% brightness, which reads as a lighting bug. **So a slot with a texture
    /// takes a white tint**, and the numeric value is used only when there is no map to tint.
    ///
    /// Model I/O also fills in a full Disney parameter set — subsurface, sheen, clearcoat, two
    /// indices of refraction — which a metallic-roughness renderer has no use for. Ignored rather
    /// than carried, because a field nothing reads is a field somebody will eventually trust.
    public init(_ material: MDLMaterial, name: String? = nil) {
        self.init(name: name ?? material.name)

        for slot in TextureSlot.allCases {
            guard let semantic = slot.semantic else { continue }
            // **The first match wins, and that is not arbitrary.** Where a semantic has two
            // properties, `properties(with:)` returns the one the file actually authored before the
            // one the importer invented — `diffuseColor` before its 0.18 `baseColor`,
            // `emissiveColor` before a zeroed `emission`. Taking the last instead reads every
            // authored value back out as the default that was going to be overridden.
            let properties = material.properties(with: semantic)

            if let source = properties.lazy.compactMap({ $0.textureSource }).first {
                textures[slot] = source
            }

            // Only meaningful without a map — see the 0.18 note above.
            guard textures[slot] == nil else { continue }
            for property in properties {
                switch (slot, property.type) {
                case (.baseColor, .float3):
                    baseColor = SIMD4(property.float3Value, baseColor.w)
                case (.baseColor, .float4):
                    baseColor = property.float4Value
                case (.emissive, .float3):
                    emissive = property.float3Value
                case (.metallic, .float):
                    metallic = property.floatValue
                case (.roughness, .float):
                    roughness = property.floatValue
                default:
                    continue
                }
                break
            }
        }

        if let opacity = material.property(with: .opacity), opacity.type == .float {
            baseColor.w = opacity.floatValue
        }
    }
}

nonisolated extension TextureSlot {
    /// The Model I/O semantic this slot reads from, or nil where there is no equivalent.
    var semantic: MDLMaterialSemantic? {
        switch self {
        case .baseColor: .baseColor
        case .normal: .tangentSpaceNormal
        case .metallic: .metallic
        case .roughness: .roughness
        case .ambientOcclusion: .ambientOcclusion
        case .emissive: .emission
        }
    }
}

nonisolated extension MDLMaterialProperty {
    /// The file this property points at, if it is a texture at all.
    ///
    /// **Read as a URL rather than through `textureSamplerValue`.** Model I/O will happily hand back
    /// a texture object with no name and no data — it logs *"unsupported image format"* for an
    /// ordinary PNG referenced from a `.usda` — while `urlValue` resolves correctly relative to the
    /// asset every time. The URL is also what a texture cache can be keyed on.
    ///
    /// **And the property's *type* cannot be used to recognise a texture.** The same property in the
    /// same file is `.string` before `MDLAsset.loadTextures()` is called and `.texture` after it, so
    /// a loader matching on `.texture` works or fails depending on an unrelated call somewhere else.
    /// Having a URL is the thing that actually means "this is a map".
    var textureSource: TextureSource? {
        guard let url = urlValue, type == .texture || type == .URL || type == .string else { return nil }
        return .url(url)
    }
}
