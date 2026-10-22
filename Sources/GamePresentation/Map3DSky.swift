import Foundation

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

    public init(_ lighting: Map3DLighting) {
        horizon = lighting.fogColour
        zenith = Map3DLighting.mix(Map3DLighting.rgb(lighting.zenith), Map3DLighting.rgb(lighting.weather.skyTint),
                                   lighting.weather.skyMix * lighting.weatherStrength)
        // Rain hides the sun's disc, the moon and the stars.
        let clear = 1 - min(max(lighting.weather.skyMix / Map3DWeather.rain.skyMix, 0), 1)
        sun = Self.path(at: (lighting.hour - 6) / 12, rise: 1.15)
        sunShown = clear * Map3DSeeThrough.smoothstep(-0.08, 0.04, sun.y)
        // The moon (full, the one shape drawn) crosses the night's sky as
        // the sun the day's: up in the east at 18:00, down in the west at
        // 06:00.
        var night = lighting.hour - 18
        if night < 0 { night += 24 }
        moon = Self.path(at: night / 12, rise: 0.9)
        moonShown = clear * min(max(lighting.night, 0), 1) * Map3DSeeThrough.smoothstep(-0.04, 0.08, moon.y)
        stars = clear * Map3DSeeThrough.smoothstep(0.5, 1, lighting.night)
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
    /// puts on it.
    public func colour(toward direction: Map3DPoint) -> SIMD3<Float> {
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

    /// The floats `map3dSkyFragment` reads (`Map3DSkyUniforms` in
    /// `Map3DShaders.metal`): the camera's way, its right and its up, the
    /// lens's half width and height as tangents, then the horizon, the
    /// zenith, the sun and how much it shows, the moon and how much, and
    /// the stars, then (decision 349) the eye's height and the haze's
    /// density and height (``Map3DGrade``).
    public func floats(camera: Map3DCamera) -> [Float] {
        let view = camera.view.columns
        let tall = tanf(camera.fieldOfViewTall / 2), wide = tall * camera.viewport.width / max(camera.viewport.height, 1)
        return [-view[2], -view[6], -view[10], 0, view[0], view[4], view[8], 0, view[1], view[5], view[9], 0, wide, tall, 0, 0,
                horizon.x, horizon.y, horizon.z, 0, zenith.x, zenith.y, zenith.z, 0,
                sun.x, sun.y, sun.z, sunShown, moon.x, moon.y, moon.z, moonShown,
                stars, camera.eye.y, Map3DGrade.hazeDensity, Map3DGrade.hazeHeight]
    }
}
