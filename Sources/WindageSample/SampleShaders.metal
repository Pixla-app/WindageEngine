//
//  SampleShaders.metal
//  WindageSample
//
//  Deliberately the smallest shader that shows a lit scene: one directional light, one ambient
//  term, no texture. A sample whose shaders are impressive teaches the reader about the shaders.
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

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
};

vertex VertexOut sampleVertex(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    float4 world = uniforms.model * float4(in.position, 1.0);
    out.position = uniforms.viewProjection * world;
    out.normal = normalize(uniforms.normalMatrix * in.normal);
    return out;
}

fragment float4 sampleFragment(VertexOut in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]])
{
    float3 n = normalize(in.normal);
    float lambert = max(dot(n, normalize(uniforms.sunDirection)), 0.0);
    // A little sky bounce from above so upward faces are not pure black in shadow.
    // Sky bounce from above, so a face turned away from the sun is dim rather than black. Without
    // it a low-poly scene reads as silhouettes, which looks like broken lighting.
    float sky = 0.35 + 0.30 * n.y;
    float3 colour = uniforms.albedo * (lambert * 1.05 + sky * 0.55);
    return float4(colour, 1.0);
}
