import Foundation

// Decision 357: the sun's shadows on the 3D map, a shadow map
// (Web/CityView/src/world/environment.js's castShadow, MIT, decision 152):
// the city drawn once from the sun into a depth texture over a square
// round the camera's target, and every face the sun lights asks it whether
// something stands between. The sun moves slowly in game time, so the map
// is drawn again only when the sun has turned, the target has moved on or
// the scene has changed (the reference town scene redraws its shadows
// every other frame for the same reason), not every frame.

/// The sun's shadows on the 3D map: how large a square they cover, how the
/// sun sees it, when it is drawn again, and what the shaders are handed.
public enum Map3DSunShadow {
    /// How a quality, the phone and the GPU's budget draw the shadows: the
    /// texels a side of the map, and the fewest seconds between two
    /// drawings of it.
    public struct Plan: Equatable, Sendable {
        public var size: Int
        public var interval: Double
    }

    /// The texels a side of the map: 2048 (16 MB of depth), half once the
    /// GPU keeps over its budget (``Map3DDrawScale``) or the phone is
    /// about to slow itself down for heat.
    public static let size = 2_048
    public static let loweredSize = 1_024
    /// A quarter of a second between drawings, a second once over budget.
    public static let interval = 0.25
    public static let loweredInterval = 1.0

    /// The plan under `quality` with Low Power Mode on or off, the phone at
    /// `heat` and the GPU over its budget or not; `nil`: no sun shadows
    /// (Saving, and Automatic when it saves), only decision 232's.
    public static func plan(_ quality: Map3DQuality, lowPower: Bool, heat: Map3DQuality.Heat, overBudget: Bool) -> Plan? {
        switch quality {
        case .saving, .off:
            return nil
        case .automatic:
            if lowPower || heat >= .serious { return nil }
            return overBudget ? Plan(size: loweredSize, interval: loweredInterval) : Plan(size: size, interval: interval)
        case .high:
            return heat >= .critical ? Plan(size: loweredSize, interval: loweredInterval) : Plan(size: size, interval: interval)
        }
    }

    /// Half the square's side, in metres, at least and at most
    /// (environment.js: 220 to 1800, the camera's distance and a tenth
    /// more), in steps of 1.3 so it seldom changes.
    public static let nearest: Float = 220
    public static let farthest: Float = 1_800
    public static let step: Float = 1.3
    public static let reachPerDistance: Float = 1.1
    /// Farther out the shadows are too small to see: none drawn.
    public static let farthestCamera: Float = 4_000
    /// The sun never quite grazes the ground, so a shadow stays finite
    /// (environment.js: 0.06).
    public static let lowestSun: Float = 0.06
    /// How far along the sun's way, either side of the target, the map
    /// holds what casts or takes a shadow, in metres.
    public static let depthReach: Float = 4_000
    /// The sun turned this far (radians, about half a degree: a 30 m
    /// building's shadow moves some 30 cm at noon) draws the map again.
    public static let turn: Float = 0.01
    /// The target moved this share of the square's half side draws it
    /// again, round the new place.
    public static let moveShare: Float = 0.25

    /// Against shadow acne: each face looked up a texel out along its
    /// normal, and 0.3 m nearer the sun; the depth drawn pushed away by
    /// one and a half times its slope, at most 8 m (`setDepthBias`).
    public static let normalOffsetTexels: Float = 1
    public static let depthBias: Float = 0.3
    public static let slopeScale: Float = 1.5
    public static let slopeClamp: Float = 8
    /// The shadows fade out over the square's outer 15 %.
    public static let fadeFrom: Float = 0.85
    /// With the sun's shadows, decision 232's soft ones under buildings,
    /// trees and trains stay at this share, as the darker ground where
    /// they stand.
    public static let blobShare: Float = 0.6

    /// Half the square's side for a camera `distance` away.
    public static func extent(distance: Float) -> Float {
        let want = min(max(distance * reachPerDistance, nearest), farthest)
        let steps = (logf(want / nearest) / logf(step) - 1e-4).rounded(.up)
        return nearest * powf(step, max(steps, 0))
    }

    /// Toward the sun, lifted to ``lowestSun`` at the least.
    public static func sunWay(_ toward: Map3DPoint) -> Map3DPoint {
        let way = toward.normalized ?? .up
        guard way.y < lowestSun else { return way }
        let flat = Map3DPoint(way.x, 0, way.z).normalized ?? Map3DPoint(1, 0, 0)
        let across = (1 - lowestSun * lowestSun).squareRoot()
        return Map3DPoint(flat.x * across, lowestSun, flat.z * across)
    }

    /// The square the map covers and how the sun sees it.
    public struct Region: Equatable, Sendable {
        /// Its middle, the target on a grid of a quarter of ``extent``.
        public let centre: Map3DPoint
        /// Half its side, in metres.
        public let extent: Float
        /// Toward the sun.
        public let sun: Map3DPoint
        /// Texels a side.
        public let size: Int

        /// Metres a texel.
        public var texel: Float { 2 * extent / Float(size) }

        /// The sun's way across the square (right), up it and into it,
        /// one metre long each.
        var axes: (right: Map3DPoint, up: Map3DPoint, into: Map3DPoint) {
            let into = -sun
            let right = into.cross(.up).normalized ?? Map3DPoint(1, 0, 0)
            let up = right.cross(into).normalized ?? Map3DPoint(0, 0, -1)
            return (right, up, into)
        }

        /// From the scene to the map: x and y from −1 to 1 across the
        /// square (y up, the texture's rows the other way), the depth from
        /// 0 nearest the sun to 1 farthest. The square is moved to whole
        /// texels, so redrawing it elsewhere does not make the shadows'
        /// edges crawl.
        public var matrix: Map3DMatrix {
            let (right, up, into) = axes
            let t = texel
            let x = (centre.dot(right) / t).rounded() * t, y = (centre.dot(up) / t).rounded() * t
            let near = centre.dot(into) - depthReach, span = 2 * depthReach
            var m = Map3DMatrix.identity
            for (row, axis, scale, offset) in [(0, right, 1 / extent, -x / extent), (1, up, 1 / extent, -y / extent),
                                               (2, into, 1 / span, -near / span)] {
                m[row, 0] = axis.x * scale
                m[row, 1] = axis.y * scale
                m[row, 2] = axis.z * scale
                m[row, 3] = offset
            }
            return m
        }

        /// Whether a map drawn for this region is out of date for `wanted`.
        public func isStale(for wanted: Region) -> Bool {
            if wanted.extent != extent || wanted.size != size || wanted.centre != centre { return true }
            let cosine = min(max(sun.dot(wanted.sun), -1), 1)
            return acosf(cosine) > Map3DSunShadow.turn
        }
    }

    /// The region for a camera at `target` and `distance` with the sun
    /// toward `sun`, its map `size` texels a side; `nil` too far out.
    public static func region(target: Map3DPoint, distance: Float, sun: Map3DPoint, size: Int) -> Region? {
        guard distance <= farthestCamera, size > 0 else { return nil }
        let extent = extent(distance: distance)
        let grid = extent * moveShare
        func snapped(_ value: Float) -> Float { (value / grid).rounded() * grid }
        let centre = Map3DPoint(snapped(target.x), snapped(target.y), snapped(target.z))
        return Region(centre: centre, extent: extent, sun: sunWay(sun), size: size)
    }

    /// How strong the sun's shadows are under `lighting`: by day, gone as
    /// the sun sets (the moon's light casts none). How dark they come out
    /// follows the sun's own light, which they take away (weaker under
    /// rain and at dusk).
    public static func strength(_ lighting: Map3DLighting) -> Float {
        Map3DSeeThrough.smoothstep(0.3, 0.9, lighting.daylight)
    }

    /// Decision 232's shadows' strength beside the sun's, `drawn` or not.
    public static func blobStrength(_ lighting: Map3DLighting, drawn: Bool) -> Float {
        let sun = drawn ? strength(lighting) : 0
        return Map3DShadow.strength(lighting) * (1 - (1 - blobShare) * sun)
    }

    /// The rows the shaders read after decision 356's (`Map3DUniforms`'s
    /// `sunMatrix` and `sunShadow` in `Map3DShaders.metal`): the matrix,
    /// then the strength (0 leaves them out), a texel of the texture, the
    /// normal's offset in metres and the depth's bias in the map's depth.
    public static func rows(_ region: Region?, lighting: Map3DLighting) -> [Float] {
        guard let region else { return Map3DMatrix.identity.columns + [0, 0, 0, 0] }
        return region.matrix.columns
            + [strength(lighting), 1 / Float(region.size), region.texel * normalOffsetTexels, depthBias / (2 * depthReach)]
    }

    /// The depth bias's clamp in the map's depth (`setDepthBias`).
    public static var slopeClampDepth: Float { slopeClamp / (2 * depthReach) }
}
