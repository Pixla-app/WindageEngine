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
    float3   albedo;
    float3   sunDirection;
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
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
};

vertex VertexOut sampleVertex(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    float4 world = uniforms.model * float4(in.position, 1.0);
    out.position = uniforms.viewProjection * world;
    out.normal = normalize(uniforms.normalMatrix * in.normal);
    out.worldPosition = world.xyz;
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
                               depth2d_array<float> shadowMap [[texture(0)]])
{
    // Declared here rather than bound: a comparison sampler is a constant of this shader, not
    // something the game has any reason to vary.
    constexpr sampler shadowSampler(mag_filter::linear, min_filter::linear,
                                    address::clamp_to_edge,
                                    compare_func::greater_equal);   // reversed-Z

    float3 n = normalize(in.normal);
    float lambert = max(dot(n, normalize(uniforms.sunDirection)), 0.0);

    // **Only the direct term is shadowed.** Ambient is light arriving from everywhere; multiplying
    // it by the sun's visibility would make shadowed faces black, which is the single most common
    // way a first shadow implementation ends up looking wrong.
    float visibility = lambert > 0.0
        ? sunVisibility(frame, in.worldPosition, shadowMap, shadowSampler)
        : 1.0;

    // Sky bounce from above, so a face turned away from the sun is dim rather than black. Without
    // it a low-poly scene reads as silhouettes, which looks like broken lighting.
    float sky = 0.35 + 0.30 * n.y;
    float3 colour = uniforms.albedo * (lambert * visibility * 1.05 + sky * 0.55);
    return float4(colour, 1.0);
}
