import Foundation

/// ARCHITECTURE decision 349: the finish of the native 3D map's picture,
/// after this repository's 3D city view (`Web/CityView/src/world/`, MIT,
/// decision 152) as it shows by default:
///
/// - **haze** (`fog.js`): a thin air lying on the ground and thinning
///   upward, so the far city, seen from low down, fades into the hour's
///   fog colour, and much less seen from high up (`atmosphere.js`'s
///   default `fog` 0.01: ``hazeDensity``, ``hazeHeight``);
/// - **tone mapping** (`ToneMappingMode.NEUTRAL`, Khronos PBR Neutral):
///   only its shoulder, so a sunlit white roof or a street light's glow
///   rolls off toward white instead of clipping; its toe, which darkens
///   the darkest colours, is left out (the owner found the night too dark
///   before, decision 229 續);
/// - **picture** (`atmosphere.js`'s `Picture` at its defaults: highlights
///   0.15, shadows 0.03, tint −0.25): brighter highlights, a hint of lift
///   in the shadows and a touch toward green.
///
/// The map's colours are the screen's (no linear light); the shoulder and
/// the tint work on them taken into linear light (2.2) and the highlights
/// and shadows on them as they are, as the web view's passes do. `Map3DShaders.metal`'s `map3dFinish`
/// and `map3dHaze` work them out the same way; change both together.
public enum Map3DGrade {
    /// The haze's density at sea level, per metre (`setAir`: `0.0001 +
    /// 0.0059 * fog²` at fog 0.01).
    public static let hazeDensity: Float = 0.0001 + 0.0059 * 0.01 * 0.01
    /// The height over which it thins to a third (`120 + 260 * fog`).
    public static let hazeHeight: Float = 120 + 260 * 0.01
    /// How far a ray that meets nothing (the sky) is taken to go.
    public static let skyDistance: Float = 60_000

    /// How much of the haze a ray from an eye `eyeHeight` metres up, going
    /// `distance` metres along `way` (one metre long), passes through, as
    /// a share of the colour it takes from the fog (`fog.js`: the haze's
    /// density falling off with height, summed along the ray).
    public static func haze(eyeHeight: Float, way: Map3DPoint, distance: Float) -> Float {
        // fog.js's `exp(-eye) * (1 - exp(-k)) / k`, written as the
        // difference of the two ends so a high eye looking far down does
        // not overflow; the far end held above 8 heights below sea level.
        let start = max(eyeHeight / hazeHeight, 0)
        let k = way.y * distance / hazeHeight
        let end = max(start + k, -8)
        let through: Float = abs(k) > 1e-3 ? (expf(-start) - expf(-end)) / k : expf(-start)
        return 1 - expf(-hazeDensity * distance * through)
    }

    /// Khronos PBR Neutral's shoulder on a colour in linear light: nothing
    /// below ``shoulderStart``, then the brightest channel rolls off toward
    /// 1 and the colour toward white a little.
    public static let shoulderStart: Float = 0.8 - 0.04
    static let desaturation: Float = 0.15

    static func shoulder(_ colour: SIMD3<Float>) -> SIMD3<Float> {
        let peak = max(colour.x, max(colour.y, colour.z))
        guard peak >= shoulderStart else { return colour }
        let d = 1 - shoulderStart
        let newPeak = 1 - d * d / (peak + d - shoulderStart)
        let scaled = colour * (newPeak / peak)
        let g = 1 - 1 / (desaturation * (peak - newPeak) + 1)
        return scaled + (SIMD3<Float>(repeating: newPeak) - scaled) * g
    }

    /// `atmosphere.js`'s `Picture` at its defaults (contrast and
    /// saturation 1 leave the colour as it is): the tint on a colour in
    /// linear light, then the highlights and shadows on it as the screen
    /// shows it (its `g`).
    static let tint: Float = -0.25, highlights: Float = 0.15, shadows: Float = 0.03

    static func tinted(_ linear: SIMD3<Float>) -> SIMD3<Float> {
        linear * SIMD3<Float>(1, 1 - 0.1 * tint, 1) * (1 + 0.05 * tint)
    }

    static func lifted(_ g: SIMD3<Float>) -> SIMD3<Float> {
        let l = luminance(g)
        let dark = 1 - Map3DSeeThrough.smoothstep(0, 0.5, l)
        let bright = Map3DSeeThrough.smoothstep(0.5, 1, l)
        return g + g * (0.3 * shadows * dark * (1 - l) / max(l, 0.05) * 0.5) + SIMD3(repeating: 0.3 * highlights * bright * l)
    }

    static func luminance(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    /// The finished colour of `colour` (0–1 a channel as drawn, may pass 1
    /// where it glows): the shoulder and the tint in linear light, then the
    /// highlights and shadows, held to 0–1.
    public static func finish(_ colour: SIMD3<Float>) -> SIMD3<Float> {
        let positive = SIMD3(max(colour.x, 0), max(colour.y, 0), max(colour.z, 0))
        let linear = SIMD3(powf(positive.x, 2.2), powf(positive.y, 2.2), powf(positive.z, 2.2))
        let rolled = tinted(shoulder(linear))
        let screen = SIMD3(powf(rolled.x, 1 / 2.2), powf(rolled.y, 1 / 2.2), powf(rolled.z, 1 / 2.2))
        let graded = lifted(screen)
        return SIMD3(min(max(graded.x, 0), 1), min(max(graded.y, 0), 1), min(max(graded.z, 0), 1))
    }
}
