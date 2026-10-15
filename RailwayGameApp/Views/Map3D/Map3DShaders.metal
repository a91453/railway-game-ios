// ARCHITECTURE decision 229: the native 3D map's one pipeline. Every
// vertex carries its own colour (the art direction's "one material for the
// whole city", docs/art/3d-style-2026-10-13/README.md), lit by the sun and
// a sky-to-ground ambient light, and fading into the sky with distance.
// Decision 231: a vertex may also name a layer of one array of textures
// (Map3DSurface) and where in it it falls; the layer tints with the colour.

#include <metal_stdlib>
using namespace metal;

struct Map3DVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
    float3 texture [[attribute(3)]];
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
    float2 surfaceAt;
    float layer [[flat]];
};

vertex Map3DVertexOut map3dVertex(Map3DVertexIn in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    Map3DVertexOut out;
    out.position = uniforms.viewProjection * float4(in.position, 1.0);
    out.color = in.color.rgb;
    out.normal = in.normal;
    out.world = in.position;
    out.surfaceAt = in.texture.xy;
    out.layer = in.texture.z;
    return out;
}

// Decision 230: a car drawn with a train model, as Map3DInstance in
// GamePresentation lays it out: the model's place in the scene, and the
// line's colour, which a vertex takes in the share its alpha falls short of
// one (a livery stripe).
struct Map3DInstance {
    float4x4 transform;
    float4 stripe;
};

vertex Map3DVertexOut map3dInstancedVertex(Map3DVertexIn in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                                           const device Map3DInstance *instances [[buffer(2)]], uint instance [[instance_id]]) {
    Map3DInstance car = instances[instance];
    float4 world = car.transform * float4(in.position, 1.0);
    Map3DVertexOut out;
    out.position = uniforms.viewProjection * world;
    out.color = mix(car.stripe.rgb, in.color.rgb, in.color.a);
    out.normal = (car.transform * float4(in.normal, 0.0)).xyz;
    out.world = world.xyz;
    out.surfaceAt = float2(0.0);
    out.layer = -1.0;
    return out;
}

// Decision 231: where a texel's alpha (its mask) is 1 it is a brightness
// around mid grey that scales the vertex's colour (walls keep the
// palette's colours); where 0 it keeps its own colour (glass, shutters).
fragment float4 map3dFragment(Map3DVertexOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                              texture2d_array<float> surfaces [[texture(0)]]) {
    constexpr sampler repeating(address::repeat, filter::linear, mip_filter::linear, max_anisotropy(8));
    float3 base = in.color;
    if (in.layer >= 0.0) {
        float4 texel = surfaces.sample(repeating, in.surfaceAt, uint(in.layer + 0.5));
        base = mix(texel.rgb, base * texel.rgb * 2.0, texel.a);
    }
    float3 normal = normalize(in.normal);
    float sun = max(dot(normal, uniforms.sunDirection.xyz), 0.0);
    float3 ambient = mix(uniforms.ambientGround.rgb, uniforms.ambientSky.rgb, normal.y * 0.5 + 0.5);
    float3 lit = base * (ambient + uniforms.sunColor.rgb * sun);
    float fog = smoothstep(uniforms.fog.x, uniforms.fog.y, distance(in.world, uniforms.eye.xyz));
    return float4(mix(lit, uniforms.fogColor.rgb, fog), 1.0);
}
