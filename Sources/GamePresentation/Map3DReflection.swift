import Foundation

/// ARCHITECTURE decision 356: glass and water on the native 3D map show
/// what they mirror, without a second pass or a second drawing of the city
/// (no screen-space reflections, no mirror camera):
///
/// - **the sky by Fresnel's share**: a pane or the water takes the colour of
///   the sky (``Map3DSky``'s horizon and zenith, decision 347) toward the
///   way it mirrors the eye, little looking straight at it and nearly all at
///   a glancing angle;
/// - **the sun's glint**: the sun mirrored in a pane that faces it (each
///   pane a little out of true, so the glint wanders from pane to pane) and
///   on the water's ripples;
/// - **the city's lights in the glass at night**: the mirrored view ray
///   followed down to the street, where a field of lights lies, so the
///   reflection slides over the glass as the view moves;
/// - **ripples on the water**: four long low waves crossing, their slope
///   tilting the water's normal, moving with the time (still with Reduce
///   Motion).
///
/// After this repository's 3D city view (`Web/CityView/src/world/`, MIT,
/// decision 152): `materials.js` (the window glass's Fresnel, its sun glint
/// and wobble, its city lights in the glass at night; the ground's water,
/// its Fresnel and `ripple`) and `reflections.js` (glass and water's
/// Fresnel shares), and the reference street scene's shop display glass
/// (`Railway/street_scene_reference_clean`, its `sogo-display-glass`
/// Fresnel). `Map3DShaders.metal`'s `map3dShade` works them out the same
/// way; change both together.
public enum Map3DReflection {
    // MARK: Which glass mirrors

    /// The glass of `surface`: how much of a mirror it is (0 none), and
    /// whether it is a shop's display glass (the street scene's Fresnel)
    /// rather than a window (the web view's tower glass). The shader's
    /// `glassMirror`, in ``Map3DSurface`` order.
    public static func glass(_ surface: Map3DSurface) -> (share: Float, shop: Bool) {
        switch surface {
        case .officeGlass: (1, false)
        case .flatWindows, .homeWindows, .homeBalcony: (0.7, false)
        // Blinds half down: less glass shows.
        case .flatBlinds: (0.5, false)
        case .shopfront, .shopOptical, .shopPhone, .shopEatery, .shopTea: (0.8, true)
        case .grass, .paving, .ballast, .concrete, .roof, .plaster, .shutter, .metalSheet,
             .formConcrete, .brickTile, .mosaicTile, .terrazzo, .crosswalk, .laneArrows: (0, false)
        }
    }

    /// A texel counts as glass where its mask keeps its own colour (alpha
    /// 0) and that colour is dark (the panes; a shop's bright goods and a
    /// shutter's light steel do not mirror).
    public static let brightestGlass: Float = 0.45

    /// Fresnel's share of the mirrored light on a face seen `cosine` (the
    /// eye's way on the face's normal, 0–1) head on. Window glass:
    /// `materials.js`'s tower glass, `0.1 + 0.9 (1 − c)⁴`. A shop's display
    /// glass: the street scene's, `0.18 + 0.62 (1 − c)⁵`. Water:
    /// `materials.js`'s, `0.05 + 0.95 (1 − c)⁴`.
    public static func windowFresnel(_ cosine: Float) -> Float {
        0.1 + 0.9 * powf(1 - clamped(cosine), 4)
    }

    public static func shopFresnel(_ cosine: Float) -> Float {
        0.18 + 0.62 * powf(1 - clamped(cosine), 5)
    }

    public static func waterFresnel(_ cosine: Float) -> Float {
        0.05 + 0.95 * powf(1 - clamped(cosine), 4)
    }

    // MARK: What it mirrors

    /// What a mirror sees toward `way` (one metre long): above the horizon
    /// the sky as ``Map3DSky`` draws it without the sun, moon and stars
    /// (from `horizon` to `zenith`); below it the street and the houses
    /// across, the horizon's colour darkening.
    public static func seen(toward way: Map3DPoint, horizon: SIMD3<Float>, zenith: SIMD3<Float>) -> SIMD3<Float> {
        if way.y >= 0 { return Map3DLighting.mix(horizon, zenith, way.y.squareRoot()) }
        return horizon * (1 - belowDarkening * Map3DSeeThrough.smoothstep(0, 0.4, -way.y))
    }

    /// How much darker than the horizon the street seen in the glass is.
    static let belowDarkening: Float = 0.45

    /// The sun mirrored toward `reflected` (one metre long) from a face
    /// the sun reaches, in shares of its colour: `materials.js`'s glint,
    /// a hot core, a glare round it and a wide soft wash (its HDR core of
    /// 14 brought down to what the picture's shoulder, decision 349, rolls
    /// off).
    public static func glassGlint(reflected: Map3DPoint, sun: Map3DPoint) -> Float {
        let s = max(reflected.dot(sun), 0)
        return powf(s, 1_400) * 3 + powf(s, 90) * 0.35 + powf(s, 7) * 0.1
    }

    /// The sun on the ripples: a sharp sparkle and a short path of glare.
    public static func waterGlint(reflected: Map3DPoint, sun: Map3DPoint) -> Float {
        let s = max(reflected.dot(sun), 0)
        return powf(s, 600) * 2 + powf(s, 60) * 0.2
    }

    /// How far out of true each pane sits: a tilt of up to half this
    /// along the face and up it (`materials.js`'s `wobble`, 0.035).
    public static let paneWobble: Float = 0.035

    /// The city's lights mirrored in a pane at `world`, `drop` metres over
    /// the street, toward `reflected` (`materials.js`'s city in the glass
    /// of a tower at night): where the ray reaches the street, a light
    /// every 26 m or so (warm, now and then cool or red), and their haze
    /// toward the horizon. Before Fresnel's share and how far the lights
    /// are on.
    public static func cityLights(world: Map3DPoint, drop: Float, reflected: Map3DPoint) -> SIMD3<Float> {
        guard reflected.y < -0.015 else { return .zero }
        let reach = max(drop, 0) / -reflected.y
        let gx = (world.x + reflected.x * reach) / lightSpacing, gz = (world.z + reflected.z * reach) / lightSpacing
        let cellX = gx.rounded(.down), cellZ = gz.rounded(.down)
        let atX = Map3DSky.hash(cellX + 3.1, cellZ + 3.1), atZ = Map3DSky.hash(cellX + 7.7, cellZ + 7.7)
        let dx = gx - cellX - atX, dz = gz - cellZ - atZ
        let d = (dx * dx + dz * dz).squareRoot() * lightSpacing
        let kind = Map3DSky.hash(cellX + 13, cellZ + 13)
        let spot = expf(-d * d / (3 + reach * 0.03)) * (kind >= 0.3 ? 1 : 0)
        let tint: SIMD3<Float> = kind > 0.8 ? SIMD3(0.8, 0.9, 1) : kind > 0.42 && kind < 0.5 ? SIMD3(1, 0.25, 0.2) : SIMD3(1, 0.72, 0.42)
        return tint * (spot * 5 / (1 + reach * reach / 4e5)) + SIMD3(1, 0.75, 0.5) * (0.035 * Map3DSeeThrough.smoothstep(0, 900, reach))
    }

    /// The street lights' spacing in the glass, in metres.
    static let lightSpacing: Float = 26

    /// How high a floor is, to tell how far a pane on floor `v` (its
    /// ``Map3DPaint/bays`` coordinate up the face) stands over the street.
    public static let floorHeight: Float = 3.2

    // MARK: Ripples

    /// One of the water's long low waves: which way it runs, how many
    /// radians a metre, how high (in units of `amplitude` metres), how
    /// fast and where it starts (`materials.js`'s `ripple`, its four
    /// crossing waves).
    struct Wave {
        let x: Float, z: Float, number: Float, height: Float, speed: Float, phase: Float
    }

    static let waves = [
        Wave(x: 0.92, z: 0.39, number: 1.1, height: 0.3, speed: 1.1, phase: 0),
        Wave(x: -0.45, z: 0.89, number: 1.6, height: 0.28, speed: -1.4, phase: 1.3),
        Wave(x: 0.2, z: -0.98, number: 2.7, height: 0.22, speed: 1.9, phase: 4),
        Wave(x: -0.8, z: -0.6, number: 4.3, height: 0.14, speed: -2.6, phase: 0),
    ]

    /// The slope's scale (`materials.js`'s `amp` close by).
    static let amplitude: Float = 0.045

    /// The water's slope along x and z at (`x`, `z`) after `seconds`, with
    /// a pixel `footprint` metres across: each wave's own slope (worked out,
    /// not sampled), the waves bent a little so they never look ruled, and
    /// each fading out as it comes to less than a few pixels a wave, where
    /// it would only shimmer (the web view fades all of them by distance
    /// instead, `170 / d`, which leaves none at the map's usual 800 m).
    public static func rippleSlope(x: Float, z: Float, seconds: Float, footprint: Float) -> (x: Float, z: Float) {
        let bentX = x + bend * sinf(z * bendNumber + seconds * 0.03)
        let bentZ = z + bend * sinf(x * bendNumber - seconds * 0.03 + 9)
        var sx: Float = 0, sz: Float = 0
        for wave in waves {
            let pixels = footprint * wave.number / (2 * Float.pi)
            let kept = 1 - Map3DSeeThrough.smoothstep(0.2, 0.5, pixels)
            let slope = wave.height * wave.number * cosf((wave.x * bentX + wave.z * bentZ) * wave.number + wave.speed * seconds + wave.phase) * kept
            sx += slope * wave.x
            sz += slope * wave.z
        }
        return (sx * amplitude, sz * amplitude)
    }

    /// How far (metres) and how often (radians a metre) the waves are bent.
    static let bend: Float = 2, bendNumber: Float = 0.11

    /// The water's normal for a slope.
    public static func waterNormal(slope: (x: Float, z: Float)) -> Map3DPoint {
        Map3DPoint(-slope.x, 1, -slope.z).normalized ?? .up
    }

    /// The seconds the ripples run on (wrapped to an hour, so `Float` keeps
    /// its precision): still with Reduce Motion (the motion skill: nothing
    /// loops by itself then).
    public static func rippleSeconds(_ seconds: Double, reduceMotion: Bool) -> Float {
        reduceMotion ? 0 : Float(seconds.truncatingRemainder(dividingBy: 3_600))
    }

    // MARK: The trains' glass and stainless (decision 450)

    /// How much of a mirror a train's window glass is (its window Fresnel
    /// times this): the reference garage's glass (metalness 0.26,
    /// roughness 0.19, clearcoat 0.42) is a near mirror, a little under
    /// the city's office glass (1), for a car's glass is tinted.
    public static let trainGlassShare: Float = 0.9

    /// A stainless body's mirror: the reference garage's metal (metalness
    /// 0.64, roughness 0.38): `steelBase + steelEdge (1 − c)⁵` of it, the
    /// sky it mirrors blurred and tinted by the steel's own colour (times
    /// ``steelTint``).
    public static let steelBase: Float = 0.22
    public static let steelEdge: Float = 0.4
    public static let steelTint: Float = 1.2

    /// The sun on stainless: a broad sheen, not a glint (its roughness),
    /// two lobes of (power, strength), in its own colour.
    public static let steelSheenLobes: [(power: Float, strength: Float)] = [(40, 0.25), (6, 0.05)]

    /// How much of the sky a lit train's glass mirrors at night: a lit
    /// room shows itself, as the city's windows (1 − 0.85 × lights).
    public static let litGlassMirror: Float = 0.85

    public static func trainGlassFresnel(_ cosine: Float) -> Float {
        trainGlassShare * windowFresnel(cosine)
    }

    public static func steelFresnel(_ cosine: Float) -> Float {
        steelBase + steelEdge * powf(1 - clamped(cosine), 5)
    }

    public static func steelSheen(reflected: Map3DPoint, sun: Map3DPoint) -> Float {
        let s = max(reflected.dot(sun), 0)
        return steelSheenLobes.reduce(0) { $0 + powf(s, $1.power) * $1.strength }
    }

    /// The share of its mirror a train's face keeps, `shade` the shade
    /// decision 439 baked into it (its `u`): a face shut in (under the
    /// floor, at a gangway) sees little sky.
    public static func trainOpen(shade: Float) -> Float {
        1 - clamped(shade)
    }

    /// How much the trains' glass and stainless mirror, 0 or 1 (0 and the
    /// shader leaves the work out): as decision 357's sun shadows, none on
    /// ``Map3DQuality/saving``, nor on ``Map3DQuality/automatic`` in Low
    /// Power Mode or once the phone runs hot (`serious`), nor on
    /// ``Map3DQuality/high`` once it is about to slow itself down.
    public static func trainStrength(_ quality: Map3DQuality, lowPower: Bool = false, heat: Map3DQuality.Heat = .nominal) -> Float {
        switch quality {
        case .saving, .off: 0
        case .automatic: lowPower || heat >= .serious ? 0 : 1
        case .high: heat >= .critical ? 0 : 1
        }
    }

    // MARK: To the shader

    /// How much the glass and water mirror: none on ``Map3DQuality/saving``,
    /// where the shader leaves the work out.
    public static func strength(_ quality: Map3DQuality) -> Float {
        quality == .saving ? 0 : 1
    }

    /// The three rows after the night windows in `Map3DUniforms`
    /// (``rowCount`` floats): the strength, the ripples' seconds, how
    /// much of the sun shows (``Map3DSky/sunShown``: none at night, under
    /// rain or below the horizon) and the trains' strength (decision 450,
    /// `trains`, or ``trainStrength(_:lowPower:heat:)`` of `quality`
    /// alone); the zenith (the horizon is the fog's
    /// colour, as the sky's); the glint's colour, the sun's light as a share
    /// of its brightest channel (warm at dawn and dusk).
    public static func rows(sky: Map3DSky, sunLight: SIMD3<Float>, quality: Map3DQuality, seconds: Double, reduceMotion: Bool,
                            trains: Float? = nil) -> [Float] {
        let peak = max(sunLight.x, max(sunLight.y, sunLight.z))
        let hue = peak > 0 ? sunLight / peak : SIMD3<Float>(repeating: 1)
        return [strength(quality), rippleSeconds(seconds, reduceMotion: reduceMotion), sky.sunShown, trains ?? trainStrength(quality),
                sky.zenith.x, sky.zenith.y, sky.zenith.z, 0,
                hue.x, hue.y, hue.z, 0]
    }

    public static let rowCount = 12

    static func clamped(_ value: Float) -> Float { min(max(value, 0), 1) }
}
