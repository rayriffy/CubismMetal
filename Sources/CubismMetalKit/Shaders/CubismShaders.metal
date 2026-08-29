#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float2 uv;
};

struct Uniforms {
    float4x4 transform;
    float opacity;
    float3 padding;
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
    float2 maskUV;
    float opacity;
};

struct MaskUniforms {
    float inverted;
    float3 padding;
};

vertex RasterizerData cubismVertex(
    uint vertexID [[vertex_id]],
    const device Vertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    RasterizerData out;
    const Vertex inputVertex = vertices[vertexID];
    const float4 clipPosition = uniforms.transform * float4(inputVertex.position, 0.0, 1.0);
    out.position = clipPosition;
    out.uv = inputVertex.uv;
    const float2 ndc = clipPosition.xy / clipPosition.w;
    out.maskUV = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    out.opacity = uniforms.opacity;
    return out;
}

fragment float4 cubismFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float4 color = texture.sample(textureSampler, in.uv);
    color.a *= in.opacity;
    color.rgb *= color.a;
    return color;
}

fragment float4 cubismMaskedFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant MaskUniforms &maskUniforms [[buffer(0)]]
) {
    const bool insideMask = all(in.maskUV >= 0.0) && all(in.maskUV <= 1.0);
    const float remaining = insideMask ? maskTexture.sample(textureSampler, in.maskUV).r : 1.0;
    const float coverage = maskUniforms.inverted > 0.5 ? remaining : 1.0 - remaining;
    float4 color = texture.sample(textureSampler, in.uv);
    color.a *= in.opacity * coverage;
    color.rgb *= color.a;
    return color;
}

fragment float4 cubismMaskFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    const float alpha = texture.sample(textureSampler, in.uv).a * in.opacity;
    return float4(alpha, 0.0, 0.0, alpha);
}
