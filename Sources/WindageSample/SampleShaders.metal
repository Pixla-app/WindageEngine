//
//  SampleShaders.metal
//  WindageSample
//
//  Deliberately the smallest shader that shows a lit scene: one directional light, one ambient
//  term, no texture, and cascaded shadows. A sample whose shaders are impressive teaches the reader
//  about the shaders.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 viewProjection;
    float4x4 model;
    float3x3 normalMatrix;
    float3   albedo;          // the game's own tint: objective state, editor selection
    float3   sunDirection;
    float4   materialBaseColor;
    float4   materialParams;  // x metallic, y roughness
};

constant int kCascadeCount = 4;

/// Frame-wide, written once per frame rather than once per object. The per-object `Uniforms` below
/// is copied for every drawable; putting four matrices in it would multiply them by the object count
/// for no reason.
struct ShadowFrame {
    float4x4 cascadeViewProjection[kCascadeCount];
    float4   cascadeSplits;
    float4   cascadeBlendStart;
    float4   cascadeDepthBias;
    float3   cameraPosition;
    float    texelSize;      // 1 / shadow map resolution
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
    float4 tangent  [[attribute(3)]];   // w is the bitangent's handedness, ±1
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 tangent;
    float  handedness;
    float3 worldPosition;
    float2 uv;
};

/// Takes a tangent-space normal into world space.
///
/// **The bitangent is reconstructed rather than carried.** It is the cross product of the other two
/// times the handedness, so storing it would be twelve bytes a vertex to save one cross product —
/// and the two could then disagree.
///
/// **The handedness is why `tangent` is a `float4`.** A UV island mirrored across the model — which
/// is most of any character, whose halves share one texture — has its bitangent the other way round.
/// Drop the sign and every mirrored surface is lit as though the light were on the other side.
static float3 applyNormalMap(float3 sampled, float3 normal, float3 tangent, float handedness)
{
    // A tangent that could not be generated arrives as zero, and normalising it gives NaN — which
    // does not draw a wrong surface, it deletes the triangle. Fall back to the vertex normal.
    if (length_squared(tangent) < 1e-8) { return normal; }

    // Gram-Schmidt: interpolation across a triangle leaves the tangent no longer perpendicular to
    // the normal, and a basis that is not orthogonal skews every direction it maps.
    const float3 t = normalize(tangent - normal * dot(normal, tangent));
    const float3 b = cross(normal, t) * handedness;
    const float3 tangentSpace = sampled * 2.0 - 1.0;      // 0..1 back to -1..1
    return normalize(t * tangentSpace.x + b * tangentSpace.y + normal * tangentSpace.z);
}

/// A skinned vertex carries two more attributes: which joints move it, and how much each one does.
///
/// **Four influences, padded.** The sample's figure uses two, and Model I/O pads the rest with a
/// joint index of 0 and a weight of 0 — which contributes nothing, so no branch is needed to skip
/// them. Four is what every rig authoring tool exports and what a real character will bring.
struct SkinnedVertexIn {
    float3  position [[attribute(0)]];
    float3  normal   [[attribute(1)]];
    float2  uv       [[attribute(2)]];
    float4  tangent  [[attribute(3)]];
    ushort4 joints   [[attribute(4)]];
    float4  weights  [[attribute(5)]];
};

/// Linear blend skinning: the weighted sum of the joint matrices moving this vertex.
///
/// **Summed as matrices, then applied once.** Transforming the vertex by each joint and averaging
/// the results gives the same answer here and four times the work; more to the point, the matrix
/// form is what lets the normal be transformed by the same basis without recomputing anything.
static float4x4 skinningMatrix(constant float4x4 *palette, ushort4 joints, float4 weights)
{
    float4x4 skin = palette[joints.x] * weights.x;
    skin += palette[joints.y] * weights.y;
    skin += palette[joints.z] * weights.z;
    skin += palette[joints.w] * weights.w;
    return skin;
}

vertex VertexOut sampleVertex(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    float4 world = uniforms.model * float4(in.position, 1.0);
    out.position = uniforms.viewProjection * world;
    out.normal = normalize(uniforms.normalMatrix * in.normal);
    // **The model matrix, not the normal matrix.** A tangent lies *along* the surface, so it
    // transforms like a position does; the inverse transpose is for things perpendicular to a
    // surface, and using it here shears the tangent off the surface under non-uniform scale.
    out.tangent = (uniforms.model * float4(in.tangent.xyz, 0.0)).xyz;
    out.handedness = in.tangent.w;
    out.worldPosition = world.xyz;
    out.uv = in.uv;
    return out;
}

/// The same scene, wearing a pose.
///
/// **The palette is per character, not per vertex** — one matrix per joint, written on the CPU by
/// `SkeletonPose` and read here. Every joint's parent chain, every clip sample and every blend has
/// already happened by the time this runs; a vertex shader that had to walk a hierarchy would do it
/// once per vertex instead of once per joint.
vertex VertexOut sampleSkinnedVertex(SkinnedVertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]],
                                     constant float4x4 *palette [[buffer(3)]])
{
    const float4x4 skin = skinningMatrix(palette, in.joints, in.weights);
    const float3x3 skinBasis = float3x3(skin[0].xyz, skin[1].xyz, skin[2].xyz);

    VertexOut out;
    float4 world = uniforms.model * (skin * float4(in.position, 1.0));
    out.position = uniforms.viewProjection * world;
    // **The normal is posed too.** Skip this and a waving arm keeps the shading of the arm it was
    // modelled as — lit from the wrong side, and it reads as a lighting bug rather than a skinning
    // one.
    out.normal = normalize(uniforms.normalMatrix * (skinBasis * in.normal));
    out.tangent = (uniforms.model * float4(skinBasis * in.tangent.xyz, 0.0)).xyz;
    // **Handedness survives skinning unchanged.** It is a property of how the texture was laid out,
    // not of where the joint has moved the vertex to.
    out.handedness = in.tangent.w;
    out.worldPosition = world.xyz;
    out.uv = in.uv;
    return out;
}

/// The shadow pass: position only. **No fragment function and no colour attachment** — nothing is
/// being shaded, only occlusion recorded, so everything but the depth write is wasted work.
vertex float4 sampleShadowVertex(VertexIn in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 constant float4x4 &lightViewProjection [[buffer(2)]])
{
    return lightViewProjection * (uniforms.model * float4(in.position, 1.0));
}

/// The shadow pass for skinned geometry.
///
/// **A second pipeline rather than a flag**, because the vertex layout differs — and it has to exist
/// at all: a character that is lit and shadowed by the scene but casts nothing reads as floating,
/// which is worse than a scene with no shadows in it.
vertex float4 sampleSkinnedShadowVertex(SkinnedVertexIn in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(1)]],
                                        constant float4x4 &lightViewProjection [[buffer(2)]],
                                        constant float4x4 *palette [[buffer(3)]])
{
    const float4x4 skin = skinningMatrix(palette, in.joints, in.weights);
    return lightViewProjection * (uniforms.model * (skin * float4(in.position, 1.0)));
}

/// One cascade's lookup. Lifted out of `sunVisibility` so that blending across a split samples the
/// two cascades through identical code rather than a copy that can drift.
static float sampleCascade(constant ShadowFrame &frame,
                           float3 worldPosition,
                           int cascade,
                           depth2d_array<float> shadowMap,
                           sampler shadowSampler)
{
    float4 lightPosition = frame.cascadeViewProjection[cascade] * float4(worldPosition, 1.0);
    float3 projected = lightPosition.xyz / lightPosition.w;

    // Clip space is -1..1 in X/Y, texture space is 0..1 with Y running downwards.
    float2 uv = projected.xy * float2(0.5, -0.5) + 0.5;

    // **Outside the map is lit, not shadowed.** Clamping instead smears the edge texels outward and
    // paints a shadow across everything beyond the covered box.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || projected.z <= 0.0) {
        return 1.0;
    }

    // Reversed-Z: nearer the light is a LARGER depth, so a fragment is lit when its own depth is
    // greater than the nearest recorded occluder. The bias absorbs the remaining quantisation
    // error; it comes from `ShadowCascades.normalizedDepthBias`, which derives it from the world
    // size of a texel rather than from a literal that would mean different things at different
    // scene scales.
    const float reference = projected.z + frame.cascadeDepthBias[cascade];

    // 3x3 percentage-closer filtering. `sample_compare` does the depth test *inside* the texture
    // unit and returns the filtered fraction, so this is nine comparisons rather than nine samples
    // and nine branches — and the edges come back softened instead of stair-stepped.
    float sum = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            sum += shadowMap.sample_compare(shadowSampler,
                                            uv + float2(x, y) * frame.texelSize, cascade, reference);
        }
    }
    return sum / 9.0;
}

/// Fraction of the sun reaching this fragment: 0 fully shadowed, 1 fully lit.
static float sunVisibility(constant ShadowFrame &frame,
                           float3 worldPosition,
                           depth2d_array<float> shadowMap,
                           sampler shadowSampler)
{
    // **Radial distance, not planar view depth.** Slightly different cascade boundaries from the
    // textbook version, and better here: turning on the spot cannot move a surface between
    // cascades, so nothing pops as the player looks around.
    const float depth = distance(worldPosition, frame.cameraPosition);

    // The tightest cascade that still reaches this fragment, walking near to far.
    int cascade = kCascadeCount - 1;
    for (int i = 0; i < kCascadeCount; ++i) {
        if (depth < frame.cascadeSplits[i]) { cascade = i; break; }
    }

    float visibility = sampleCascade(frame, worldPosition, cascade, shadowMap, shadowSampler);

    // **Cross-fade into the next cascade over a band before the split.** Both cascades are
    // individually correct and the handover is still visible: they differ in texel size, so they
    // differ in filter footprint and in bias, and the same surface changes shadow softness within
    // one pixel. That reads as an arc drawn on the ground at a fixed distance, sweeping as the
    // player walks. The last cascade has nothing to fade into.
    if (cascade + 1 < kCascadeCount) {
        const float blendStart = frame.cascadeBlendStart[cascade];
        const float split = frame.cascadeSplits[cascade];
        const float t = saturate((depth - blendStart) / max(split - blendStart, 1e-4));
        if (t > 0.0) {
            visibility = mix(visibility,
                             sampleCascade(frame, worldPosition, cascade + 1, shadowMap, shadowSampler),
                             t);
        }
    }
    return visibility;
}

fragment float4 sampleFragment(VertexOut in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               constant ShadowFrame &frame [[buffer(2)]],
                               depth2d_array<float> shadowMap [[texture(0)]],
                               texture2d<float> baseColorMap [[texture(1)]],
                               texture2d<float> normalMap [[texture(2)]])
{
    // Declared here rather than bound: a comparison sampler is a constant of this shader, not
    // something the game has any reason to vary.
    constexpr sampler shadowSampler(mag_filter::linear, min_filter::linear,
                                    address::clamp_to_edge,
                                    compare_func::greater_equal);   // reversed-Z

    // **Mip filtering and anisotropy are what make a texture look textured.** Without mips the
    // ground shimmers as the camera moves; without anisotropy it turns to mush at a grazing angle,
    // which is most of the screen in a game played standing up.
    constexpr sampler surfaceSampler(mag_filter::linear, min_filter::linear,
                                     mip_filter::linear, address::repeat,
                                     max_anisotropy(8));

    // The texture is sRGB, so this is already linear — the GPU decoded it on the way in. The engine
    // decides that per slot; see `TextureSlot.isColor`.
    float4 base = baseColorMap.sample(surfaceSampler, in.uv)
                * uniforms.materialBaseColor
                * float4(uniforms.albedo, 1.0);

    const float metallic = uniforms.materialParams.x;
    const float roughness = clamp(uniforms.materialParams.y, 0.045, 1.0);

    // **Shading normal from the map, geometric normal kept for the shadow lookup.** Perturbing the
    // normal used to bias a shadow sample moves the sample off the surface it belongs to, and the
    // contact shadow detaches from its caster.
    const float3 geometric = normalize(in.normal);
    const float3 n = applyNormalMap(normalMap.sample(surfaceSampler, in.uv).xyz,
                                    geometric, in.tangent, in.handedness);
    float lambert = max(dot(n, normalize(uniforms.sunDirection)), 0.0);

    // **Only the direct term is shadowed.** Ambient is light arriving from everywhere; multiplying
    // it by the sun's visibility would make shadowed faces black, which is the single most common
    // way a first shadow implementation ends up looking wrong.
    float visibility = dot(geometric, normalize(uniforms.sunDirection)) > 0.0
        ? sunVisibility(frame, in.worldPosition, shadowMap, shadowSampler)
        : 1.0;

    // Sky bounce from above, so a face turned away from the sun is dim rather than black. Without
    // it a low-poly scene reads as silhouettes, which looks like broken lighting.
    float sky = 0.35 + 0.30 * n.y;

    // Metal has no diffuse — its colour lives in the reflection instead. Half a line, and it is the
    // difference between a metallic material meaning something and being a number nothing reads.
    float3 diffuse = base.rgb * (1.0 - metallic) * (lambert * visibility * 1.05 + sky * 0.55);

    // **Blinn-Phong, and deliberately not a PBR lobe.** A real specular BRDF needs a distribution
    // term, a geometry term and Fresnel; this is a sample whose job is to show that the material's
    // roughness arrives and does something. An impressive shader here would teach the reader about
    // the shader.
    const float3 view = normalize(frame.cameraPosition - in.worldPosition);
    // Not `half` — that is a type in Metal Shading Language, and the error it produces is about a
    // declaration specifier rather than about the name.
    const float3 halfway = normalize(view + normalize(uniforms.sunDirection));
    const float shininess = 2.0 / (roughness * roughness * roughness * roughness) - 2.0;
    const float3 tint = mix(float3(0.04), base.rgb, metallic);
    float3 specular = tint * pow(max(dot(n, halfway), 0.0), shininess)
                    * ((shininess + 8.0) / 25.0) * lambert * visibility;

    return float4(diffuse + specular, base.a);
}
