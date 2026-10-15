import Foundation
import GameCore

/// The native 3D map's camera (ARCHITECTURE decision 229): it looks at a
/// point on the ground from `distance` metres away, turned `heading` from
/// north and tilted by how close it is: straight down from far away, like
/// the 2D map, leaning over as it comes closer (NEXT_PRIORITIES §0 item 14,
/// "the same map tilts as you zoom in"). The references have no rule for
/// the tilt (MapLibre's camera tilts by hand; gap): this one is the
/// project's own, its closest tilt rail-3d's default pitch of 55°.
public struct Map3DCamera: Hashable, Sendable {
    /// The point looked at, in the scene's metres (on the ground).
    public var target: Map3DPoint
    /// How far the eye is from the target, in metres.
    public var distance: Float
    /// The way the view faces, in radians clockwise from north.
    public var heading: Float
    /// The view's size in points, for its shape.
    public var viewport: (width: Float, height: Float)

    public static let nearest: Float = 60
    public static let farthest: Float = 12_000
    /// The view's height, as an angle (35°).
    public static let fieldOfView: Float = 35 * .pi / 180
    /// From this distance out the map looks straight down; at ``tiltedFrom``
    /// and closer it leans ``mostTilt`` over.
    public static let flatFrom: Float = 2_400
    public static let tiltedFrom: Float = 300
    public static let mostTilt: Float = 55 * .pi / 180

    public init(target: Map3DPoint = .zero, distance: Float = 1_200, heading: Float = 0, viewport: (width: Float, height: Float) = (390, 844)) {
        self.target = target
        self.distance = min(max(distance, Self.nearest), Self.farthest)
        self.heading = heading
        self.viewport = viewport
    }

    public static func == (a: Map3DCamera, b: Map3DCamera) -> Bool {
        a.target == b.target && a.distance == b.distance && a.heading == b.heading
            && a.viewport.width == b.viewport.width && a.viewport.height == b.viewport.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        hasher.combine(distance)
        hasher.combine(heading)
    }

    /// The tilt from straight down at `distance`, in radians: 0 from
    /// ``flatFrom`` out, ``mostTilt`` from ``tiltedFrom`` in, and between,
    /// a smoothstep over the distance's logarithm, so each pinch tilts the
    /// map a like step.
    public static func tilt(atDistance distance: Float) -> Float {
        guard distance < flatFrom else { return 0 }
        guard distance > tiltedFrom else { return mostTilt }
        let t = (logf(flatFrom) - logf(distance)) / (logf(flatFrom) - logf(tiltedFrom))
        return mostTilt * t * t * (3 - 2 * t)
    }

    public var tilt: Float { Self.tilt(atDistance: distance) }

    /// The level way the view faces, and the way to its right.
    var forward: Map3DPoint { Map3DPoint(sinf(heading), 0, -cosf(heading)) }
    var right: Map3DPoint { Map3DPoint(cosf(heading), 0, sinf(heading)) }

    public var eye: Map3DPoint {
        target - forward * (distance * sinf(tilt)) + Map3DPoint(0, distance * cosf(tilt), 0)
    }

    public var view: Map3DMatrix {
        let eye = eye
        let look = (target - eye).normalized ?? Map3DPoint(0, -1, 0)
        let back = -look
        let side = right
        let up = back.cross(side).normalized ?? forward
        return Map3DMatrix(columns: [
            side.x, up.x, back.x, 0,
            side.y, up.y, back.y, 0,
            side.z, up.z, back.z, 0,
            -side.dot(eye), -up.dot(eye), -back.dot(eye), 1,
        ])
    }

    /// The nearest and farthest the view draws, in metres from the eye.
    public var depthRange: (near: Float, far: Float) {
        (max(1, distance * 0.02), distance * 6 + 4_000)
    }

    public var projection: Map3DMatrix {
        let aspect = max(viewport.width, 1) / max(viewport.height, 1)
        let f = 1 / tanf(Self.fieldOfView / 2)
        let (near, far) = depthRange
        return Map3DMatrix(columns: [
            f / aspect, 0, 0, 0,
            0, f, 0, 0,
            0, 0, far / (near - far), -1,
            0, 0, near * far / (near - far), 0,
        ])
    }

    public var viewProjection: Map3DMatrix { projection * view }

    /// Whether any of the box from `minimum` to `maximum` may be in view
    /// through `matrix` (``viewProjection``): false only when all eight
    /// corners lie beyond one side of the view.
    public static func sees(minimum: Map3DPoint, maximum: Map3DPoint, through matrix: Map3DMatrix) -> Bool {
        var outside = [true, true, true, true, true, true]
        for corner in 0..<8 {
            let p = [corner & 1 == 0 ? minimum.x : maximum.x, corner & 2 == 0 ? minimum.y : maximum.y, corner & 4 == 0 ? minimum.z : maximum.z, 1]
            var c = [Float](repeating: 0, count: 4)
            for row in 0..<4 {
                for k in 0..<4 { c[row] += matrix[row, k] * p[k] }
            }
            let (x, y, z, w) = (c[0], c[1], c[2], c[3])
            let sides = [x < -w, x > w, y < -w, y > w, z < 0, z > w]
            for side in 0..<6 where !sides[side] { outside[side] = false }
        }
        return !outside.contains(true)
    }

    // MARK: - Detail (decision 238)

    /// From this distance out every chunk is drawn simplified: the city
    /// is a field of roofs, its balconies and signs a few points each.
    public static let detailDistance: Float = 1_600
    /// How far from what the camera looks at, and from under the eye, a
    /// chunk is drawn in full: at least this, more the farther the eye.
    public static let detailReach: Float = 700

    /// Whether the chunk from `minimum` to `maximum` is drawn in full
    /// (``Map3DScene/Chunk/mesh``) rather than simplified
    /// (``Map3DScene/Chunk/far``): the camera is close enough, and the
    /// chunk is within reach of the target or of the ground under the eye.
    /// As the reference's street scene does (`updateDetail` in
    /// `Railway/street_scene_reference_clean/source/assets/scene.js`), a
    /// chunk drawn in full (`wasDetailed`) keeps its detail until 1.14
    /// times as far, and one drawn simplified gets it back only within
    /// 0.86 times: no flicker at the line.
    public func wantsDetail(minimum: Map3DPoint, maximum: Map3DPoint, wasDetailed: Bool = false) -> Bool {
        let margin: Float = wasDetailed ? 1.14 : 0.86
        guard distance <= Self.detailDistance * margin else { return false }
        let reach = max(Self.detailReach, distance * 1.2) * margin
        let eye = eye
        for point in [target, Map3DPoint(eye.x, 0, eye.z)] {
            let dx = point.x - min(max(point.x, minimum.x), maximum.x), dz = point.z - min(max(point.z, minimum.z), maximum.z)
            if dx * dx + dz * dz <= reach * reach { return true }
        }
        return false
    }

    // MARK: - Gestures

    /// Metres on the ground per point on the screen at the target.
    public var metresPerPoint: Float {
        2 * distance * tanf(Self.fieldOfView / 2) / max(viewport.height, 1)
    }

    /// The camera moved as a finger drags the map `dx`, `dy` points (right
    /// and down): the ground follows the finger.
    public func panned(dx: Float, dy: Float) -> Map3DCamera {
        var camera = self
        let scale = metresPerPoint
        camera.target = target - right * (dx * scale) + forward * (dy * scale)
        return camera
    }

    /// The camera `factor` times closer (more than 1 comes in).
    public func zoomed(by factor: Float) -> Map3DCamera {
        guard factor > 0, factor.isFinite else { return self }
        var camera = self
        camera.distance = min(max(distance / factor, Self.nearest), Self.farthest)
        return camera
    }

    /// The camera turned `radians` clockwise, as two fingers turn the map
    /// the other way.
    public func turned(by radians: Float) -> Map3DCamera {
        var camera = self
        camera.heading = (heading + radians).truncatingRemainder(dividingBy: 2 * .pi)
        return camera
    }
}

/// The light on the native 3D map at a time of day (ARCHITECTURE decision
/// 229): the sky, the sun's colour, strength and way, the ambient light and
/// how dark the night is. The keyframes are `Railway/street_scene_reference_clean/`'s
/// miniature style (`assets/scene.js`, by the hour: zenith, sky, sun,
/// ground, ambient, sun strength, night), whose look the art direction took
/// for "F 台灣版＋"; the sun goes round from east to west through the north
/// of the sky's south (Taiwan is north of the tropic only just).
public struct Map3DLighting: Hashable, Sendable {
    public let zenith: PopTravel.RGB
    public let sky: PopTravel.RGB
    public let sun: PopTravel.RGB
    public let ground: PopTravel.RGB
    public let ambient: Float
    public let sunStrength: Float
    /// 1 at night, 0 by day.
    public let night: Float
    /// Toward the sun, one metre long.
    public let sunDirection: Map3DPoint

    struct Key {
        let hour: Float
        let zenith: UInt32, sky: UInt32, sun: UInt32, ground: UInt32
        let ambient: Float, sunStrength: Float, night: Float
    }

    static let keys: [Key] = [
        Key(hour: 0, zenith: 0x06141C, sky: 0x163742, sun: 0x9FD0D8, ground: 0x2C4A52, ambient: 0.58, sunStrength: 0, night: 1),
        Key(hour: 5, zenith: 0x0E1C2A, sky: 0x2C4553, sun: 0xF4BD92, ground: 0x3E5560, ambient: 0.6, sunStrength: 0, night: 1),
        Key(hour: 6.5, zenith: 0x6F89B3, sky: 0xF0C1A0, sun: 0xFFB98A, ground: 0x958071, ambient: 1, sunStrength: 1, night: 0.35),
        Key(hour: 8, zenith: 0x86ACD6, sky: 0xE4E3D8, sun: 0xFFE2BC, ground: 0xA69986, ambient: 1.2, sunStrength: 2.3, night: 0),
        Key(hour: 12, zenith: 0x78A5D6, sky: 0xDDE6E8, sun: 0xFFF1DC, ground: 0xA79987, ambient: 1.3, sunStrength: 2.6, night: 0),
        Key(hour: 15.5, zenith: 0x86A9CF, sky: 0xF4D4AC, sun: 0xFFBF78, ground: 0xC39F80, ambient: 1.2, sunStrength: 2.85, night: 0),
        Key(hour: 17.5, zenith: 0x8494B8, sky: 0xF6BB8C, sun: 0xFFB276, ground: 0xA47C63, ambient: 1, sunStrength: 1.9, night: 0.12),
        Key(hour: 18.5, zenith: 0x38466E, sky: 0xD88A74, sun: 0xFF9C78, ground: 0x5F5F74, ambient: 0.72, sunStrength: 0.35, night: 0.7),
        Key(hour: 20, zenith: 0x0A1824, sky: 0x1E3F4B, sun: 0x9FD0D8, ground: 0x2F4D56, ambient: 0.58, sunStrength: 0, night: 1),
        Key(hour: 24, zenith: 0x06141C, sky: 0x163742, sun: 0x9FD0D8, ground: 0x2C4A52, ambient: 0.58, sunStrength: 0, night: 1),
    ]

    /// The light at `minute` of the day (wrapped into a day).
    public init(minute: Double) {
        var m = minute.truncatingRemainder(dividingBy: 1_440)
        if m < 0 { m += 1_440 }
        let hour = Float(m / 60)
        var index = 1
        while index < Self.keys.count - 1, Self.keys[index].hour <= hour { index += 1 }
        let a = Self.keys[index - 1], b = Self.keys[index]
        let t = b.hour > a.hour ? min(max((hour - a.hour) / (b.hour - a.hour), 0), 1) : 0
        func mix(_ x: UInt32, _ y: UInt32) -> PopTravel.RGB {
            func channel(_ shift: UInt32) -> UInt8 {
                let p = Float((x >> shift) & 0xFF), q = Float((y >> shift) & 0xFF)
                return UInt8((p + (q - p) * t).rounded())
            }
            return PopTravel.RGB(red: channel(16), green: channel(8), blue: channel(0))
        }
        zenith = mix(a.zenith, b.zenith)
        sky = mix(a.sky, b.sky)
        sun = mix(a.sun, b.sun)
        ground = mix(a.ground, b.ground)
        ambient = a.ambient + (b.ambient - a.ambient) * t
        sunStrength = a.sunStrength + (b.sunStrength - a.sunStrength) * t
        night = a.night + (b.night - a.night) * t
        // The sun rises in the east at 06:00, stands high in the south at
        // noon and sets in the west at 18:00; at night the moon lights the
        // scene from overhead, a little to the south.
        let dayShare = (hour - 6) / 12
        if dayShare > 0, dayShare < 1 {
            let angle = Float.pi * dayShare
            let elevation = max(sinf(angle), 0.08) * 1.15
            sunDirection = Map3DPoint(cosf(angle), elevation, 0.45 * sinf(angle)).normalized ?? .up
        } else {
            sunDirection = Map3DPoint(0.2, 1, 0.3).normalized ?? .up
        }
    }

    /// The light at game time `time`.
    public init(at time: GameTime) {
        let seconds = time.seconds % GameTime.secondsPerDay
        self.init(minute: Double(seconds < 0 ? seconds + GameTime.secondsPerDay : seconds) / 60)
    }
}
