// ARCHITECTURE decision 229: the native 3D map's one pipeline. Every
// vertex carries its own colour (the art direction's "one material for the
// whole city", docs/art/3d-style-2026-10-13/README.md), lit by the sun and
// a sky-to-ground ambient light, and fading into the sky with distance.

#include <metal_stdlib>
using namespace metal;

struct Map3DVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
};

// Laid out as Map3DRenderer.uniforms writes it: a matrix, then seven
// four-float rows.
struct Map3DUniforms {
    float4x4 viewProjection;
    float4 sunDirection;
    float4 sunColor;
    float4 ambientSky;
    float4 ambientGround;
    float4 fogColor;
    float4 eye;
    float4 fog;
};

struct Map3DVertexOut {
    float4 position [[position]];
    float3 color;
    float3 normal;
    float3 world;
};

vertex Map3DVertexOut map3dVertex(Map3DVertexIn in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    Map3DVertexOut out;
    out.position = uniforms.viewProjection * float4(in.position, 1.0);
    out.color = in.color.rgb;
    out.normal = in.normal;
    out.world = in.position;
    return out;
}

fragment float4 map3dFragment(Map3DVertexOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    float3 normal = normalize(in.normal);
    float sun = max(dot(normal, uniforms.sunDirection.xyz), 0.0);
    float3 ambient = mix(uniforms.ambientGround.rgb, uniforms.ambientSky.rgb, normal.y * 0.5 + 0.5);
    float3 lit = in.color * (ambient + uniforms.sunColor.rgb * sun);
    float fog = smoothstep(uniforms.fog.x, uniforms.fog.y, distance(in.world, uniforms.eye.xyz));
    return float4(mix(lit, uniforms.fogColor.rgb, fog), 1.0);
}
