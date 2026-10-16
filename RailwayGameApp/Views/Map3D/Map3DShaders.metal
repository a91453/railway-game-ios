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

// Laid out as Map3DRenderer.uniforms writes it: a matrix, then eight
// four-float rows (decision 232's shade: the shadows' strength in x; decision
// 229 續: how far the city's lights are on in y), then the night windows'
// rules (Map3DLighting.nightWindowRows: per surface layer, two to a row, the
// share lit and the brightest glass).
struct Map3DUniforms {
    float4x4 viewProjection;
    float4 sunDirection;
    float4 sunColor;
    float4 ambientSky;
    float4 ambientGround;
    float4 fogColor;
    float4 eye;
    float4 fog;
    float4 shade;
    float4 nightWindows[12];
};

struct Map3DVertexOut {
    float4 position [[position]];
    float3 color;
    float3 normal;
    float3 world;
    float2 surfaceAt;
    float layer [[flat]];
    // The face's plane (its distance along its normal), the same over the
    // face, to tell one face's windows from another's.
    float plane [[flat]];
};

vertex Map3DVertexOut map3dVertex(Map3DVertexIn in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    Map3DVertexOut out;
    out.position = uniforms.viewProjection * float4(in.position, 1.0);
    out.color = in.color.rgb;
    out.normal = in.normal;
    out.world = in.position;
    out.surfaceAt = in.texture.xy;
    out.layer = in.texture.z;
    out.plane = dot(in.position, normalize(in.normal));
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
    // Decision 229 續: a street light's head glows (Map3DVertex.glowing).
    out.layer = in.texture.z < -1.5 ? in.texture.z : -1.0;
    out.plane = 0.0;
    return out;
}

// Decision 242: the materials (Map3DSurface.materials, from layer 18 on)
// and how many metres one repeat of each covers (detailRepeat).
constant uint firstMaterial = 18;
constant float detailRepeat[4] = {3.6, 1.8, 1.8, 1.8};

// Decision 231: where a texel's alpha (its mask) is 1 it is a brightness
// around mid grey that scales the vertex's colour (walls keep the
// palette's colours); where 0 it keeps its own colour (glass, shutters).
// Decision 242: a vertex's layer may also name a material (in steps of
// 64), a fine grey pattern laid in the scene's metres over the tinted
// part, fading out from 200 m to 600 m away.
// Decision 229 續: a number from 0 to 1 for a point, the same every time
// (Web/CityView's hash12, MIT).
float hash12(float2 p) {
    float3 q = fract(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fragment float4 map3dFragment(Map3DVertexOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                              texture2d_array<float> surfaces [[texture(0)]]) {
    constexpr sampler repeating(address::repeat, filter::linear, mip_filter::linear, max_anisotropy(8));
    float3 base = in.color;
    // Decision 229 續: light of its own at night, added after the fog.
    float3 glow = float3(0.0);
    float lights = uniforms.shade.y;
    if (in.layer < -1.5) {
        glow = base * 1.3 * lights;
    }
    if (in.layer >= 0.0) {
        uint packed = uint(in.layer + 0.5);
        float4 texel = surfaces.sample(repeating, in.surfaceAt, packed % 64u);
        float3 tinted = base * texel.rgb * 2.0;
        uint material = packed / 64u;
        if (material > 0u) {
            uint layer = material - 1u;
            float metres = detailRepeat[min(layer - firstMaterial, 3u)];
            float3 facing = normalize(in.normal);
            float2 at = abs(facing.y) > 0.7 ? in.world.xz
                : float2(dot(in.world, normalize(cross(float3(0.0, 1.0, 0.0), facing))), in.world.y);
            float near = 1.0 - smoothstep(200.0, 600.0, distance(in.world, uniforms.eye.xyz));
            float detail = surfaces.sample(repeating, at / metres, layer).r * 2.0;
            tinted *= mix(1.0, detail, near);
        }
        base = mix(texel.rgb, tinted, texel.a);
        // A lit window: its glass (untinted and dark enough, or a shop's
        // whole front) where the hash of its bay, floor and face says so.
        uint surface = packed % 64u;
        float4 row = uniforms.nightWindows[min(surface / 2u, 11u)];
        float2 rule = (surface % 2u == 0u) ? row.xy : row.zw;
        if (lights > 0.0 && rule.x > 0.0) {
            float glass = (1.0 - texel.a) * step(dot(texel.rgb, float3(0.2126, 0.7152, 0.0722)), rule.y);
            float3 facing = normalize(in.normal);
            float2 face = float2(floor(in.plane / 4.0), dot(round(facing * 4.0), float3(1.0, 17.0, 289.0)));
            float2 room = floor(in.surfaceAt) + fract(face * float2(0.1373, 0.2719)) * 512.0;
            float busy = mix(0.5, 1.6, hash12(face * 0.37 + 11.0));
            float on = step(1.0 - clamp(rule.x * busy, 0.0, 0.95), hash12(room + 23.0));
            float3 warm = mix(float3(1.0, 0.6, 0.3), float3(1.0, 0.82, 0.6), hash12(room + 67.0));
            glow += warm * mix(0.55, 1.1, hash12(room + 1.3)) * glass * on * lights;
        }
    }
    float3 normal = normalize(in.normal);
    float sun = max(dot(normal, uniforms.sunDirection.xyz), 0.0);
    float3 ambient = mix(uniforms.ambientGround.rgb, uniforms.ambientSky.rgb, normal.y * 0.5 + 0.5);
    float3 lit = base * (ambient + uniforms.sunColor.rgb * sun);
    float fog = smoothstep(uniforms.fog.x, uniforms.fog.y, distance(in.world, uniforms.eye.xyz));
    return float4(mix(lit, uniforms.fogColor.rgb, fog) + glow * (1.0 - fog * 0.7), 1.0);
}

// Decision 232: the soft shadows on the ground, drawn last over what is
// already drawn, their darkness in the vertex's alpha. A cool dark tint
// rather than black, faded with the fog like everything else.
struct Map3DShadowOut {
    float4 position [[position]];
    float darkness;
    // Decision 229 續: a colour is a street light's pool, not a shadow.
    float3 light;
    float3 world;
};

vertex Map3DShadowOut map3dShadowVertex(Map3DVertexIn in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    Map3DShadowOut out;
    out.position = uniforms.viewProjection * float4(in.position, 1.0);
    out.darkness = in.color.a;
    out.light = in.color.rgb;
    out.world = in.position;
    return out;
}

fragment float4 map3dShadowFragment(Map3DShadowOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]]) {
    float fog = smoothstep(uniforms.fog.x, uniforms.fog.y, distance(in.world, uniforms.eye.xyz));
    if (any(in.light > 0.0)) {
        return float4(in.light, in.darkness * uniforms.shade.y * (1.0 - fog));
    }
    return float4(0.10, 0.12, 0.20, in.darkness * uniforms.shade.x * (1.0 - fog));
}
