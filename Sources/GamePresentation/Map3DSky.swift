import Foundation
import GameCore

/// ARCHITECTURE decision 347: the sky behind the native 3D map, a dome
/// from the horizon's colour (the fog's, so the far ground fades into it)
/// to the hour's zenith (``Map3DLighting/zenith``), with the sun's disc and
/// glow by day and, on a clear night, stars and the moon. The look is
/// `Web/CityView/src/world/sky.js`'s (this repository's 3D city preview,
/// Procedural Tokyo, MIT): its gradient, its sun's glow and disc, its
/// stars on a hashed grid; the colours are the game's own hours (decision
/// 229), not its fixed day and night pair, and its clouds are not drawn.
///
/// The Metal view draws it once over the whole screen behind everything
/// (`map3dSkyFragment` in `Map3DShaders.metal`, which works out
/// ``colour(toward:)`` the same way; change both together).
public struct Map3DSky: Equatable, Sendable {
    /// The colour at the horizon (and below it), and straight up, 0–1 a
    /// channel.
    public let horizon: SIMD3<Float>
    public let zenith: SIMD3<Float>
    /// Toward the sun and the moon, and how much of each shows, 0 to 1
    /// (none below the horizon, under rain, or the moon by day).
    public let sun: Map3DPoint
    public let sunShown: Float
    public let moon: Map3DPoint
    public let moonShown: Float
    /// How much the stars show, 0 to 1.
    public let stars: Float
    /// Decision 813's later part (AURORA): how much the aurora shows, 0 to
    /// 1: tonight's (``Map3DLighting/aurora``) on a clear, dark night.
    public let aurora: Float

    public init(_ lighting: Map3DLighting) {
        horizon = lighting.fogColour
        zenith = Map3DLighting.mix(Map3DLighting.rgb(lighting.zenith), Map3DLighting.rgb(lighting.weather.skyTint),
                                   lighting.weather.skyMix * lighting.weatherStrength)
        // Rain hides the sun's disc, the moon and the stars.
        let clear = 1 - min(max(lighting.weather.skyMix / Map3DWeather.rain.skyMix, 0), 1)
        sun = lighting.skySun
        sunShown = clear * Map3DSeeThrough.smoothstep(-0.08, 0.04, sun.y)
        // The moon (full, the one shape drawn) stands across the sky from
        // the sun (decision 813; ``Map3DLighting/skyMoon``).
        moon = lighting.skyMoon
        moonShown = clear * min(max(lighting.night, 0), 1) * Map3DSeeThrough.smoothstep(-0.04, 0.08, moon.y)
        stars = clear * Map3DSeeThrough.smoothstep(0.5, 1, lighting.night)
        aurora = clear * lighting.aurora * Map3DSeeThrough.smoothstep(0.5, 1, lighting.night)
    }

    /// Along the path from the east (`share` 0) over the south to the west
    /// (1), as ``Map3DLighting``'s sun goes, `rise` high; below the horizon
    /// outside 0 to 1.
    static func path(at share: Float, rise: Float) -> Map3DPoint {
        let angle = Float.pi * share
        return Map3DPoint(cosf(angle), rise * sinf(angle), 0.45 * sinf(angle)).normalized ?? .up
    }

    /// The sun's glow and disc, the moon's, the stars' colour.
    static let sunGlow = SIMD3<Float>(1, 0.82, 0.6)
    static let sunDisc = SIMD3<Float>(1, 0.97, 0.9)
    static let moonGlow = SIMD3<Float>(0.6, 0.65, 0.75)
    static let moonDisc = SIMD3<Float>(0.93, 0.92, 0.86)
    static let starLight = SIMD3<Float>(0.8, 0.85, 1)

    /// The sky's colour toward `direction`, before the haze on the ground
    /// and the picture's finish (decision 349, ``Map3DGrade``) the shader
    /// puts on it; `seconds` moves the aurora (``auroraLight(_:seconds:)``).
    public func colour(toward direction: Map3DPoint, seconds: Float = 0) -> SIMD3<Float> {
        let d = direction.normalized ?? .up
        let high = max(d.y, 0)
        var colour = Map3DLighting.mix(horizon, zenith, high.squareRoot())
        let towardSun = max(d.dot(sun), 0)
        colour += Self.sunGlow * ((powf(towardSun, 12) * 0.18 + powf(towardSun, 180) * 0.5) * sunShown)
        colour = Map3DLighting.mix(colour, Self.sunDisc, Map3DSeeThrough.smoothstep(0.9994, 0.9998, towardSun) * sunShown)
        let towardMoon = max(d.dot(moon), 0)
        colour += Self.moonGlow * (powf(towardMoon, 80) * 0.12 * moonShown)
        colour = Map3DLighting.mix(colour, Self.moonDisc, Map3DSeeThrough.smoothstep(0.9990, 0.9994, towardMoon) * moonShown)
        colour += Self.starLight * (Self.star(d) * 0.5 * stars)
        if aurora > 0 { colour += Self.auroraLight(d, seconds: seconds) * aurora }
        return pointwiseMin(colour, SIMD3(repeating: 1))
    }

    /// 1 where a star is, 0 elsewhere: one in 400 squares of a grid over
    /// the sky (sky.js's), none low down. The shader draws each as a round
    /// point about a pixel across within its square (the squares come to
    /// several pixels in the cab's wide lens); here the whole square
    /// counts.
    static func star(_ d: Map3DPoint) -> Float {
        let x = (d.x / (abs(d.y) + 0.35) * 220).rounded(.down), z = (d.z / (abs(d.y) + 0.35) * 220).rounded(.down)
        return (hash(x, z) > 0.9975 ? 1 : 0) * Map3DSeeThrough.smoothstep(0.1, 0.5, d.y)
    }

    /// sky.js's `hash` (Dave Hoskins's hash without sine), as the shader
    /// works it in `Float`.
    static func hash(_ x: Float, _ y: Float) -> Float {
        func fract(_ v: Float) -> Float { v - v.rounded(.down) }
        var p = SIMD3(fract(x * 0.1031), fract(y * 0.1031), fract(x * 0.1031))
        let shifted = SIMD3(p.y, p.z, p.x) + 33.33
        let dot = (p * shifted).sum()
        p += dot
        return fract((p.x + p.y) * p.z)
    }

    // MARK: - The aurora (decision 813's later part, AURORA)

    /// The aurora's two colours: the green low down (oxygen's 557.7 nm)
    /// and the violet it turns to up high, the reference ribbon's
    /// `uColorA` #4CFFA6 and `uColorB` #A080FF. Light in the sky, not a
    /// surface's colour, so not of ``Map3DPalette`` (新提, decision 813).
    static let auroraGreen = SIMD3<Float>(0x4C, 0xFF, 0xA6) / 255
    static let auroraViolet = SIMD3<Float>(0xA0, 0x80, 0xFF) / 255
    /// How far round the sky the curtain reaches either side of the north
    /// (radians, about 80°), where its foot stands (about 11° up) and how
    /// tall it is (about 24°), how much its foot waves (about 3°), how
    /// bright it is at most, and how slowly it moves: the reference's
    /// ribbon moves at its own pace × 0.15 (a curtain's wave about 40 s
    /// round, its colours rising one band in some 27 s).
    static let auroraReach: Float = 1.4
    static let auroraFoot: Float = 0.19
    static let auroraHeight: Float = 0.42
    static let auroraWave: Float = 0.05
    static let auroraBrightness: Float = 0.55
    static let auroraPace: Float = 0.15

    /// The aurora's light toward `d` at full strength: a curtain over the
    /// northern sky (`-z`, ``Map3DLighting``'s sun goes round the south,
    /// `+z`). The look is the owner's geo-scene showcase's aurora ribbon
    /// (`Railway/geo-scene-reference-clean/source/public/showcase/effects/shader.js`,
    /// `aurora`): its foot waves as two sines along the ribbon, its colour
    /// bands scroll up it, and it fades toward its ends (`pow(sin, 0.5)`)
    /// and its top (`pow(1 - v, 0.5)`), drawn added to what is behind. The
    /// ribbon there is a sheet in the scene; here it is the sky's, laid
    /// round the north from the eye, so it stands behind everything. Two
    /// changes: the violet only toward the top (the reference mixed it in
    /// anywhere), and faint rays down the curtain.
    /// `Map3DShaders.metal`'s `map3dSkyFragment` works it the same way.
    static func auroraLight(_ d: Map3DPoint, seconds: Float) -> SIMD3<Float> {
        guard d.y > 0 else { return .zero }
        let round = atan2f(d.x, -d.z)
        guard abs(round) < auroraReach else { return .zero }
        let u = (round / auroraReach + 1) / 2
        let t = seconds * auroraPace
        let tau = 2 * Float.pi
        let foot = auroraFoot + sinf(u * tau * 2 + t * 1.5) * auroraWave + cosf(u * tau * 3.5 + t * 0.8) * auroraWave * 0.4
        let v = (asinf(min(d.y, 1)) - foot) / auroraHeight
        guard v > 0, v < 1 else { return .zero }
        let band = sinf((v + t * 0.25) * tau) * 0.5 + 0.5
        let colour = Map3DLighting.mix(auroraGreen, auroraViolet, band * v)
        let edge = powf(sinf(u * Float.pi), 0.5) * powf(1 - v, 0.5) * Map3DSeeThrough.smoothstep(0, 0.06, v)
        let rays = 0.7 + 0.3 * sinf(u * tau * 23 + sinf(u * tau * 5 + t * 0.6) * 2)
        return colour * (edge * rays * auroraBrightness)
    }

    /// The floats `map3dSkyFragment` reads (`Map3DSkyUniforms` in
    /// `Map3DShaders.metal`): the camera's way, its right and its up, the
    /// lens's half width and height as tangents, then the horizon, the
    /// zenith, the sun and how much it shows, the moon and how much, and
    /// the stars, then (decision 349) the eye's height and the haze's
    /// density and height (``Map3DGrade``), then how much of the aurora
    /// shows and the seconds that move it (0 under Reduce Motion, so it
    /// stands still).
    public func floats(camera: Map3DCamera, seconds: Float = 0) -> [Float] {
        let view = camera.view.columns
        let tall = tanf(camera.fieldOfViewTall / 2), wide = tall * camera.viewport.width / max(camera.viewport.height, 1)
        return [-view[2], -view[6], -view[10], 0, view[0], view[4], view[8], 0, view[1], view[5], view[9], 0, wide, tall, 0, 0,
                horizon.x, horizon.y, horizon.z, 0, zenith.x, zenith.y, zenith.z, 0,
                sun.x, sun.y, sun.z, sunShown, moon.x, moon.y, moon.z, moonShown,
                stars, camera.eye.y, Map3DGrade.hazeDensity, Map3DGrade.hazeHeight,
                aurora, seconds, 0, 0]
    }
}

extension Map3DLighting {
    /// Decision 813's later part (AURORA): how bright the aurora is at
    /// `time` at `latitude`, 0 to 1. Whether a night has one is drawn from
    /// the night's number (the evening's game day), the same for every
    /// player and every look at it, with the share of nights the Finnish
    /// Meteorological Institute gives (``auroraNights(latitude:)``); that
    /// night's strength is drawn too. Through the night it is out from
    /// about 20:00 to about 04:00, at its brightest from 21:30 to 02:00
    /// (the local clock; the magnetic midnight in Finland is round 23:30).
    /// Whether it shows at all is the sky's: none by day, under cloud or
    /// rain (``Map3DSky/aurora``).
    static func aurora(at time: GameTime, latitude: Double) -> Float {
        let share = auroraNights(latitude: latitude)
        guard share > 0 else { return 0 }
        let day = GameTime.secondsPerDay
        let night = GameDate.floorDivide(time.seconds - day / 2, day)
        guard auroraDraw(night, 0) < share else { return 0 }
        let strength = 0.55 + 0.45 * auroraDraw(night, 1)
        let hour = Float(time.seconds - GameDate.floorDivide(time.seconds, day) * day) / 3600
        let late = hour < 12 ? hour + 24 : hour
        return strength * Map3DSeeThrough.smoothstep(19.5, 21.5, late) * (1 - Map3DSeeThrough.smoothstep(26, 28.5, late))
    }

    /// The share of clear, dark nights with an aurora at `latitude`: the
    /// Finnish Meteorological Institute's figures (Visit Finland's and
    /// space.fmi.fi's pages): about one night a month on the south coast
    /// (60° N), every other night over Rovaniemi (66.5°), three nights of
    /// four in the far north of Lapland (69°); none south of 58°, so never
    /// in Taiwan or Hong Kong.
    static func auroraNights(latitude: Double) -> Float {
        let rows: [(Double, Double)] = [(58, 0), (60, 0.033), (66.5, 0.5), (69, 0.75)]
        let north = latitude
        guard north > rows[0].0 else { return 0 }
        for (low, high) in zip(rows, rows.dropFirst()) where north < high.0 {
            return Float(low.1 + (high.1 - low.1) * (north - low.0) / (high.0 - low.0))
        }
        return Float(rows[rows.count - 1].1)
    }

    /// 0 up to 1, from the night's number and a salt (SplitMix64).
    static func auroraDraw(_ night: Int64, _ salt: UInt64) -> Float {
        var z = UInt64(bitPattern: night) &+ 0x9E37_79B9_7F4A_7C15 &* (salt &+ 0xA0)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}
