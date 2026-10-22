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
// 229 續: how far the city's lights are on in y; decision 349: the fog's
// z and w, the ground haze's density and height), then the night windows'
// rules (Map3DLighting.nightWindowRows: per surface layer, two to a row, the
// share lit and the brightest glass), then decision 356's reflections
// (Map3DReflection.rows): the strength (0 leaves them out), the ripples'
// seconds and how much of the sun shows; the zenith; the glint's colour.
// Decision 357: then the sun's shadow map (Map3DSunShadow.rows): from the
// scene to the map, then its strength (0 leaves it out), a texel of it, the
// normal's offset in metres and the depth's bias.
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
    float4 mirror;
    float4 zenith;
    float4 glint;
    float4x4 sunMatrix;
    float4 sunShadow;
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
    out.layer = (in.texture.z < -1.5 && in.texture.z > -2.5) ? in.texture.z : -1.0;
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

// Decision 349: the picture's finish, as Map3DGrade works it out (the
// web view's Neutral tone mapping's shoulder and its Picture at its
// defaults, Web/CityView/src/world/atmosphere.js, MIT), and fog.js's haze
// lying on the ground. Change both together.
float map3dHaze(float eyeHeight, float3 way, float far, float density, float height) {
    float start = max(eyeHeight / height, 0.0);
    float k = way.y * far / height;
    float end = max(start + k, -8.0);
    float through = abs(k) > 1e-3 ? (exp(-start) - exp(-end)) / k : exp(-start);
    return 1.0 - exp(-density * far * through);
}

float3 map3dFinish(float3 colour) {
    float3 c = pow(max(colour, 0.0), 2.2);
    float peak = max(c.r, max(c.g, c.b));
    const float start = 0.8 - 0.04;
    if (peak >= start) {
        const float d = 1.0 - start;
        float newPeak = 1.0 - d * d / (peak + d - start);
        c *= newPeak / peak;
        float g = 1.0 - 1.0 / (0.15 * (peak - newPeak) + 1.0);
        c = mix(c, float3(newPeak), g);
    }
    c *= float3(1.0, 1.025, 1.0) * 0.9875;
    float3 g = pow(c, 1.0 / 2.2);
    float l = dot(g, float3(0.2126, 0.7152, 0.0722));
    g += g * (0.009 * (1.0 - smoothstep(0.0, 0.5, l)) * (1.0 - l) / max(l, 0.05) * 0.5) + 0.045 * smoothstep(0.5, 1.0, l) * l;
    return clamp(g, 0.0, 1.0);
}

// `base` lit by the sun and the sky on a face looking along `normal` at
// `world`, then what it mirrors laid over it by its share (`mirrored`'s
// alpha, decision 356), its own light `glow` added, faded into the fog,
// and finished. Decision 352: the signs end the same way.
// Decision 357: how much of the sun reaches `world` on a face looking
// along `normal`, 0 to 1: the sun's shadow map (Map3DSunShadow) looked up
// a texel out along the normal and a little nearer the sun, four taps of
// two by two each, faded out at the square's edge.
float map3dSunSeen(float3 world, float3 normal, constant Map3DUniforms &uniforms, depth2d<float> sunShadow) {
    float strength = uniforms.sunShadow.x;
    if (strength <= 0.0 || dot(normal, uniforms.sunDirection.xyz) <= 0.0) { return 1.0; }
    float4 at = uniforms.sunMatrix * float4(world + normal * uniforms.sunShadow.z, 1.0);
    float edge = max(abs(at.x), abs(at.y));
    if (edge >= 1.0 || at.z <= 0.0 || at.z >= 1.0) { return 1.0; }
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);
    float2 uv = float2(at.x * 0.5 + 0.5, 0.5 - at.y * 0.5);
    float texel = uniforms.sunShadow.y, depth = at.z - uniforms.sunShadow.w;
    float seen = 0.0;
    seen += sunShadow.sample_compare(s, uv + float2(-texel, -texel), depth);
    seen += sunShadow.sample_compare(s, uv + float2(texel, -texel), depth);
    seen += sunShadow.sample_compare(s, uv + float2(-texel, texel), depth);
    seen += sunShadow.sample_compare(s, uv + float2(texel, texel), depth);
    return mix(1.0, seen * 0.25, strength * (1.0 - smoothstep(0.85, 1.0, edge)));
}

// Decision 357: `sunSeen` the share of the sun that reaches it.
float4 map3dLit(float3 base, float3 glow, float4 mirrored, float3 normal, float3 world, float sunSeen, constant Map3DUniforms &uniforms) {
    float sun = max(dot(normal, uniforms.sunDirection.xyz), 0.0) * sunSeen;
    float3 ambient = mix(uniforms.ambientGround.rgb, uniforms.ambientSky.rgb, normal.y * 0.5 + 0.5);
    float3 lit = mix(base * (ambient + uniforms.sunColor.rgb * sun), mirrored.rgb, mirrored.a);
    float far = distance(world, uniforms.eye.xyz);
    float fog = smoothstep(uniforms.fog.x, uniforms.fog.y, far);
    // Decision 349: and the haze on the ground on the way.
    float3 way = (world - uniforms.eye.xyz) / max(far, 1e-3);
    fog = 1.0 - (1.0 - fog) * (1.0 - map3dHaze(uniforms.eye.y, way, far, uniforms.fog.z, uniforms.fog.w));
    return float4(map3dFinish(mix(lit, uniforms.fogColor.rgb, fog) + glow * (1.0 - fog * 0.7)), 1.0);
}

// Decision 356: glass and water mirror the sky, the sun and at night the
// city's lights, as Map3DReflection works it out (Web/CityView's
// materials.js and reflections.js, MIT; the reference street scene's
// display glass). Per surface layer, how much its glass mirrors and
// whether it is a shop's display glass (Map3DReflection.glass).
constant float2 glassMirror[24] = {
    {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0.7, 0}, {0.7, 0},
    {0.8, 1}, {0, 0}, {0.7, 0}, {1, 0}, {0, 0}, {0.8, 1}, {0.8, 1}, {0.8, 1},
    {0.8, 1}, {0.5, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
};

// What a mirror sees toward `way`: the sky from the horizon (the fog's
// colour) to the zenith, or below the horizon the street, darker.
static float3 map3dSeen(float3 way, constant Map3DUniforms &uniforms) {
    if (way.y >= 0.0) { return mix(uniforms.fogColor.rgb, uniforms.zenith.rgb, sqrt(way.y)); }
    return uniforms.fogColor.rgb * (1.0 - 0.45 * smoothstep(0.0, 0.4, -way.y));
}

// The water's slope along x and z: four crossing waves (materials.js's
// `ripple`), each worked out, bent a little, and gone where it comes to
// less than a few pixels.
// Each wave: which way it runs, radians a metre and height; its speed and
// phase.
constant float4 rippleWaves[4] = {{0.92, 0.39, 1.1, 0.3}, {-0.45, 0.89, 1.6, 0.28}, {0.2, -0.98, 2.7, 0.22}, {-0.8, -0.6, 4.3, 0.14}};
constant float2 rippleRuns[4] = {{1.1, 0.0}, {-1.4, 1.3}, {1.9, 4.0}, {-2.6, 0.0}};

static float2 map3dRipple(float2 p, float t, float footprint) {
    float2 bent = p + 2.0 * float2(sin(p.y * 0.11 + t * 0.03), sin(p.x * 0.11 - t * 0.03 + 9.0));
    float2 slope = float2(0.0);
    for (int i = 0; i < 4; i++) {
        float4 w = rippleWaves[i];
        float kept = 1.0 - smoothstep(0.2, 0.5, footprint * w.z / (2.0 * M_PI_F));
        slope += w.xy * (w.w * w.z * cos(dot(w.xy, bent) * w.z + rippleRuns[i].x * t + rippleRuns[i].y) * kept);
    }
    return slope * 0.045;
}

float4 map3dShade(Map3DVertexOut in, constant Map3DUniforms &uniforms, texture2d_array<float> surfaces, depth2d<float> sunShadow) {
    constexpr sampler repeating(address::repeat, filter::linear, mip_filter::linear, max_anisotropy(8));
    float3 base = in.color;
    // Decision 229 續: light of its own at night, added after the fog.
    float3 glow = float3(0.0);
    float lights = uniforms.shade.y;
    if (in.layer < -1.5 && in.layer > -2.5) {
        glow = base * 1.3 * lights;
    }
    // Decision 356: what the glass or water mirrors, and its share.
    float4 mirrored = float4(0.0);
    float3 normal = normalize(in.normal);
    bool mirrors = uniforms.mirror.x > 0.0;
    float3 toEye = normalize(uniforms.eye.xyz - in.world);
    // Decision 357: the sun's share, also on what glints in it.
    float sunSeen = map3dSunSeen(in.world, normal, uniforms, sunShadow);
    if (mirrors && in.layer < -2.5) {
        // Water: tilted by its ripples, the sky by Fresnel's share, and
        // the sun's glint on them.
        float2 slope = map3dRipple(in.world.xz, uniforms.mirror.y, length(fwidth(in.world.xz)));
        normal = normalize(float3(-slope.x, 1.0, -slope.y));
        sunSeen = map3dSunSeen(in.world, normal, uniforms, sunShadow);
        float3 r = reflect(-toEye, normal);
        float fresnel = 0.05 + 0.95 * pow(1.0 - max(dot(toEye, normal), 0.0), 4.0);
        mirrored = float4(map3dSeen(float3(r.x, abs(r.y), r.z), uniforms), fresnel * uniforms.mirror.x);
        float s = max(dot(r, uniforms.sunDirection.xyz), 0.0);
        glow += uniforms.glint.rgb * ((pow(s, 600.0) * 2.0 + pow(s, 60.0) * 0.2) * uniforms.mirror.z * uniforms.mirror.x * sunSeen);
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
            // 2026-10-21 (the GPU's time on Taipei): no second sample where
            // the pattern has faded out.
            if (near > 0.0) {
                float detail = surfaces.sample(repeating, at / metres, layer).r * 2.0;
                tinted *= mix(1.0, detail, near);
            }
        }
        base = mix(texel.rgb, tinted, texel.a);
        // A lit window: its glass (untinted and dark enough, or a shop's
        // whole front) where the hash of its bay, floor and face says so.
        uint surface = packed % 64u;
        float4 row = uniforms.nightWindows[min(surface / 2u, 11u)];
        float2 rule = (surface % 2u == 0u) ? row.xy : row.zw;
        float2 pane = glassMirror[min(surface, 23u)];
        float bright = dot(texel.rgb, float3(0.2126, 0.7152, 0.0722));
        float mirrorGlass = mirrors ? (1.0 - texel.a) * step(bright, 0.45) * pane.x : 0.0;
        if ((lights > 0.0 && rule.x > 0.0) || mirrorGlass > 0.0) {
            float2 face = float2(floor(in.plane / 4.0), dot(round(normal * 4.0), float3(1.0, 17.0, 289.0)));
            float2 room = floor(in.surfaceAt) + fract(face * float2(0.1373, 0.2719)) * 512.0;
            float on = 0.0;
            if (lights > 0.0 && rule.x > 0.0) {
                float glass = (1.0 - texel.a) * step(bright, rule.y);
                float busy = mix(0.5, 1.6, hash12(face * 0.37 + 11.0));
                on = step(1.0 - clamp(rule.x * busy, 0.0, 0.95), hash12(room + 23.0)) * glass;
                float3 warm = mix(float3(1.0, 0.6, 0.3), float3(1.0, 0.82, 0.6), hash12(room + 67.0));
                glow += warm * mix(0.55, 1.1, hash12(room + 1.3)) * on * lights;
            }
            if (mirrorGlass > 0.0) {
                // Each pane a little out of true (materials.js's wobble),
                // so the sun's glint wanders from pane to pane.
                float3 along = normalize(cross(float3(0.0, 1.0, 0.0), normal) + float3(1e-4, 0.0, 0.0));
                float3 tilted = normalize(normal + (along * (hash12(room + 15.7) - 0.5) + float3(0.0, hash12(room + 19.3) - 0.5, 0.0)) * 0.035);
                float3 r = reflect(-toEye, tilted);
                float c = max(dot(toEye, tilted), 0.0);
                float fresnel = pane.y > 0.5 ? 0.18 + 0.62 * pow(1.0 - c, 5.0) : 0.1 + 0.9 * pow(1.0 - c, 4.0);
                float3 seen = map3dSeen(r, uniforms);
                // At night the city's lights, where the mirrored ray meets
                // the street (pane's floor up the face times a floor's
                // height below it): a light every 26 m.
                if (lights > 0.0 && r.y < -0.015) {
                    float reach = max(in.surfaceAt.y, 0.3) * 3.2 / -r.y;
                    float2 g = (in.world.xz + r.xz * reach) / 26.0, cell = floor(g);
                    float2 at = float2(hash12(cell + 3.1), hash12(cell + 7.7));
                    float d = length(fract(g) - at) * 26.0, kind = hash12(cell + 13.0);
                    float spot = exp(-d * d / (3.0 + reach * 0.03)) * step(0.3, kind);
                    float3 tint = kind > 0.8 ? float3(0.8, 0.9, 1.0) : (kind > 0.42 && kind < 0.5) ? float3(1.0, 0.25, 0.2) : float3(1.0, 0.72, 0.42);
                    float3 city = tint * spot * 5.0 / (1.0 + reach * reach / 4.0e5) + float3(1.0, 0.75, 0.5) * 0.035 * smoothstep(0.0, 900.0, reach);
                    glow += city * fresnel * mirrorGlass * lights * (1.0 - on * 0.9) * uniforms.mirror.x;
                }
                // A lit room shows itself, not a reflection.
                mirrored = float4(seen, fresnel * mirrorGlass * (1.0 - 0.85 * lights * on) * uniforms.mirror.x);
                float s = max(dot(r, uniforms.sunDirection.xyz), 0.0);
                float glint = pow(s, 1400.0) * 3.0 + pow(s, 90.0) * 0.35 + pow(s, 7.0) * 0.1;
                glow += uniforms.glint.rgb * (glint * mirrorGlass * step(0.0, dot(normal, uniforms.sunDirection.xyz)) * uniforms.mirror.z * uniforms.mirror.x * sunSeen);
            }
        }
    }
    return map3dLit(base, glow, mirrored, normal, in.world, sunSeen, uniforms);
}

fragment float4 map3dFragment(Map3DVertexOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                              texture2d_array<float> surfaces [[texture(0)]], depth2d<float> sunShadow [[texture(1)]]) {
    return map3dShade(in, uniforms, surfaces, sunShadow);
}

// Decision 342: the cars the buildings in front of are seen through, as
// Map3DSeeThrough.floats lays them out: each car's middle on its rails,
// then how many, the cones' radius at the car, the opacity in them and
// the clearance over the rails, then how near the car nothing is seen
// through and how high over the rails the cones aim.
struct Map3DSeeThroughCars {
    float4 cars[16];
    float4 shape;
    float4 more;
};

// Decision 342: the city of a chunk a cone crosses, with its alpha the
// share of it that shows (Map3DSeeThrough.opacity(at:), worked out the
// same way): the pipeline turns the alpha into the share of a pixel's
// four samples it covers, so the train behind shows in the rest.
fragment float4 map3dSeeThroughFragment(Map3DVertexOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                                        constant Map3DSeeThroughCars &see [[buffer(2)]],
                                        texture2d_array<float> surfaces [[texture(0)]], depth2d<float> sunShadow [[texture(1)]]) {
    float4 colour = map3dShade(in, uniforms, surfaces, sunShadow);
    float3 eye = uniforms.eye.xyz;
    float3 v = in.world - eye;
    float radius = see.shape.y, opacity = see.shape.z, clearance = see.shape.w;
    float beside = see.more.x, bodyMiddle = see.more.y;
    float shown = 1.0;
    int count = min(int(see.shape.x), 16);
    for (int index = 0; index < count; index++) {
        float3 car = see.cars[index].xyz;
        if (in.world.y <= car.y + clearance) { continue; }
        float3 d = car + float3(0.0, bodyMiddle, 0.0) - eye;
        float far = length(d);
        if (far <= beside) { continue; }
        float along = dot(v, d) / far;
        if (along <= 0.0 || along >= far - beside) { continue; }
        float t = along / far;
        float off = length(v - d * t) / (radius * t);
        shown = min(shown, opacity + (1.0 - opacity) * smoothstep(0.7, 1.0, off));
    }
    colour.a = shown;
    return colour;
}

// Decision 357: the sun's shadow map, the city's depth seen from the sun
// (Map3DSunShadow.Region.matrix), no colour: the chunks' meshes, and the
// street furniture through its instances.
vertex float4 map3dSunDepthVertex(Map3DVertexIn in [[stage_in]], constant float4x4 &sun [[buffer(1)]]) {
    return sun * float4(in.position, 1.0);
}

vertex float4 map3dSunDepthInstancedVertex(Map3DVertexIn in [[stage_in]], constant float4x4 &sun [[buffer(1)]],
                                           const device Map3DInstance *instances [[buffer(2)]], uint instance [[instance_id]]) {
    return sun * (instances[instance].transform * float4(in.position, 1.0));
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

// Decision 347: the sky, one triangle over the whole screen at the far
// plane (depth 0, decision 342), drawn where nothing else was. Laid out as
// Map3DSky.floats writes it; the colour worked out as Map3DSky.colour(toward:)
// (Web/CityView/src/world/sky.js's gradient, sun, moon and stars).
struct Map3DSkyUniforms {
    float4 look;
    float4 side;
    float4 up;
    float4 lens;
    float4 horizon;
    float4 zenith;
    float4 sun;
    float4 moon;
    float4 stars;
};

struct Map3DSkyOut {
    float4 position [[position]];
    float2 screen;
};

vertex Map3DSkyOut map3dSkyVertex(uint index [[vertex_id]]) {
    // (-1, -1), (3, -1), (-1, 3): the screen and beyond.
    float2 corner = float2(index == 1 ? 3.0 : -1.0, index == 2 ? 3.0 : -1.0);
    Map3DSkyOut out;
    out.position = float4(corner, 0.0, 1.0);
    out.screen = corner;
    return out;
}

static float map3dSkyHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fragment float4 map3dSkyFragment(Map3DSkyOut in [[stage_in]], constant Map3DSkyUniforms &sky [[buffer(3)]]) {
    float3 d = normalize(sky.look.xyz + sky.side.xyz * (in.screen.x * sky.lens.x) + sky.up.xyz * (in.screen.y * sky.lens.y));
    float high = max(d.y, 0.0);
    float3 colour = mix(sky.horizon.rgb, sky.zenith.rgb, sqrt(high));
    float towardSun = max(dot(d, sky.sun.xyz), 0.0);
    colour += float3(1.0, 0.82, 0.6) * ((pow(towardSun, 12.0) * 0.18 + pow(towardSun, 180.0) * 0.5) * sky.sun.w);
    colour = mix(colour, float3(1.0, 0.97, 0.9), smoothstep(0.9994, 0.9998, towardSun) * sky.sun.w);
    float towardMoon = max(dot(d, sky.moon.xyz), 0.0);
    colour += float3(0.6, 0.65, 0.75) * (pow(towardMoon, 80.0) * 0.12 * sky.moon.w);
    colour = mix(colour, float3(0.93, 0.92, 0.86), smoothstep(0.9990, 0.9994, towardMoon) * sky.moon.w);
    // A cell that holds a star (Map3DSky.star) shows it as a round point
    // about a pixel across somewhere in the cell, not the whole cell: the
    // cells come to several pixels in the cab's wide lens.
    float2 cells = d.xz / (abs(d.y) + 0.35) * 220.0;
    float2 grid = floor(cells);
    float star = step(0.9975, map3dSkyHash(grid)) * smoothstep(0.1, 0.5, d.y);
    float2 centre = grid + 0.25 + 0.5 * float2(map3dSkyHash(grid + 7.1), map3dSkyHash(grid + 3.7));
    float pixel = max(length(fwidth(cells)), 1e-4);
    float spot = 1.0 - smoothstep(0.6, 1.4, length(cells - centre) / pixel);
    colour += float3(0.8, 0.85, 1.0) * (star * spot * 0.5 * sky.stars.x);
    // Decision 349: the haze on the ground (a ray that meets nothing taken
    // 60 km), in the fog's colour, and the picture's finish, as on the city.
    colour = mix(colour, sky.horizon.rgb, map3dHaze(sky.stars.y, d, 60000.0, sky.stars.z, sky.stars.w));
    return float4(map3dFinish(colour), 1.0);
}

// Decision 352: the signs, billboards and LED screens (Web/CityView's
// ads.js, MIT), each an instance as Map3DSign.floats lays it out: its
// middle and kind (0 a poster, 1 a screen, 2 a banner, 3 a word across,
// 4 a word down), half its width toward the reader's right and the
// picture, half its height and the seed, the board's and letters' colours
// (red + green * 256 + blue * 65536) and the minutes after noon it goes
// dark. Beside them, as Map3DSign.clock writes it: the seconds the screens
// run on, the minutes after noon now, and how far from the eye signs are
// drawn. The atlas (Map3DSigns.png, Map3DSignAtlas): 8 by 8 cells.
struct Map3DSignIn {
    float4 middle;
    float4 right;
    float4 up;
    float4 colours;
};

struct Map3DSignOut {
    float4 position [[position]];
    float2 at;
    float3 world;
    float3 normal [[flat]];
    float kind [[flat]];
    float picture [[flat]];
    float seed [[flat]];
    float aspect [[flat]];
    float3 board [[flat]];
    float3 letters [[flat]];
    float lit [[flat]];
};

static float3 map3dUnpack(float packed) {
    return float3(fmod(packed, 256.0), fmod(floor(packed / 256.0), 256.0), floor(packed / 65536.0)) / 255.0;
}

vertex Map3DSignOut map3dSignVertex(uint corner [[vertex_id]], uint instance [[instance_id]], constant Map3DUniforms &uniforms [[buffer(1)]],
                                    const device Map3DSignIn *signs [[buffer(2)]], constant float4 &clock [[buffer(3)]]) {
    Map3DSignIn sign = signs[instance];
    // A strip: bottom left, bottom right, top left, top right as read.
    float2 at = float2((corner & 1u) ? 1.0 : 0.0, (corner & 2u) ? 1.0 : 0.0);
    float3 world = sign.middle.xyz + sign.right.xyz * (at.x * 2.0 - 1.0) + sign.up.xyz * (at.y * 2.0 - 1.0);
    Map3DSignOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    // Too far to read: every corner at one point past the far plane, so
    // nothing is drawn.
    if (distance(sign.middle.xyz, uniforms.eye.xyz) > clock.z) { out.position = float4(0.0, 0.0, -1.0, 1.0); }
    out.at = at;
    out.world = world;
    out.normal = normalize(cross(sign.right.xyz, sign.up.xyz));
    out.kind = sign.middle.w;
    out.picture = sign.right.w;
    out.seed = sign.up.w;
    out.aspect = length(sign.right.xyz) / max(length(sign.up.xyz), 1e-3);
    out.board = map3dUnpack(sign.colours.x);
    out.letters = map3dUnpack(sign.colours.y);
    out.lit = clock.y < sign.colours.z ? 1.0 : 0.0;
    return out;
}

// A poster's cell (ads.js `poster`), `at` from its bottom left.
static float3 map3dPoster(texture2d<float> atlas, sampler s, float index, float2 at) {
    float i = floor(index + 0.5);
    float2 cell = float2(fmod(i, 8.0), floor(i / 8.0));
    return atlas.sample(s, (cell + clamp(float2(at.x, 1.0 - at.y), 0.004, 0.996)) / 8.0).rgb;
}

// How much of a word's letters cover `at` on a board `aspect` wide for
// each metre high: the word's strip (`shape` wide for each high, at
// `origin`, `size` of the atlas) fitted in the board's middle, the rest
// the board's own colour.
static float map3dWord(texture2d<float> atlas, sampler s, float2 origin, float2 size, float shape, float aspect, float2 at) {
    float2 fitted = aspect > shape ? float2((at.x - 0.5) * aspect / shape + 0.5, at.y) : float2(at.x, (at.y - 0.5) * shape / aspect + 0.5);
    // Sampled everywhere, so the pixels round it keep their mipmaps.
    float inside = step(0.0, min(fitted.x, fitted.y)) * step(max(fitted.x, fitted.y), 1.0);
    return atlas.sample(s, origin + clamp(float2(fitted.x, 1.0 - fitted.y), 0.01, 0.99) * size).r * inside;
}

fragment float4 map3dSignFragment(Map3DSignOut in [[stage_in]], constant Map3DUniforms &uniforms [[buffer(1)]],
                                  constant float4 &clock [[buffer(3)]], texture2d<float> atlas [[texture(0)]],
                                  depth2d<float> sunShadow [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, mip_filter::linear, max_anisotropy(4));
    // Read from behind (a blade sign's far side), the right way round.
    float3 normal = in.normal;
    float2 at = in.at;
    if (dot(normal, uniforms.eye.xyz - in.world) < 0.0) {
        normal = -normal;
        at.x = 1.0 - at.x;
    }
    uint kind = uint(in.kind + 0.5);
    float lights = uniforms.shade.y;
    float3 colour, base, glow;
    if (kind == 1u) {
        // A screen: the next poster wipes in every few seconds; LED
        // pixels show close up.
        float t = clock.x * 0.16 + in.seed * 9.0, wipe = smoothstep(0.86, 1.0, fract(t));
        float now = fmod(in.picture + floor(t), 24.0), next = fmod(now + 1.0, 24.0);
        colour = mix(map3dPoster(atlas, s, now, at), map3dPoster(atlas, s, next, at), step(at.x, wipe));
        float2 led = fract(at * float2(160.0, 90.0));
        float fine = max(fwidth(at.x * 160.0), fwidth(at.y * 90.0));
        colour *= mix(0.72 + 0.5 * step(0.22, led.x) * step(0.22, led.y), 1.0, smoothstep(0.3, 1.0, fine));
        // Bright by day too; dark once switched off.
        base = colour * 0.35;
        glow = colour * (0.55 + 0.75 * lights) * in.lit;
    } else if (kind <= 2u) {
        // A neon poster or banner: by day dull glass on a dark board.
        colour = kind == 2u ? map3dPoster(atlas, s, 24.0 + in.picture, float2(at.x / 3.0, at.y)) : map3dPoster(atlas, s, in.picture, at);
        base = mix(colour * 0.55 + 0.03, colour, lights);
        glow = colour * (0.1 + 1.6 * lights * in.lit);
    } else {
        // A shop's board, its word in its letters' colour, lit from
        // inside after dark until the shop closes.
        float i = floor(in.picture + 0.5), strip = fmod(i, 4.0);
        float across = kind == 3u ? 1.0 : 0.0;
        float index = (kind == 3u ? 32.0 : 48.0) + floor(i / 4.0);
        float2 origin = float2(fmod(index, 8.0), floor(index / 8.0)) / 8.0 + float2(1.0 - across, across) * (strip / 32.0);
        float2 size = kind == 3u ? float2(0.125, 0.03125) : float2(0.03125, 0.125);
        float letter = map3dWord(atlas, s, origin, size, kind == 3u ? 4.0 : 0.25, in.aspect, at);
        colour = mix(in.board, in.letters, letter);
        base = colour;
        glow = colour * (1.1 * lights * in.lit);
    }
    return map3dLit(base, glow, float4(0.0), normal, in.world, map3dSunSeen(in.world, normal, uniforms, sunShadow), uniforms);
}

