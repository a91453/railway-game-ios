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
    /// From this distance out this camera looks straight down
    /// (``tilt(atDistance:from:)``): ``flatFrom`` unless a pinch handed the
    /// 2D map over closer in (decision 313: the 2D map's closest zoom), so
    /// the handed-over map starts straight down and leans from there.
    public var tiltsFrom: Float = Map3DCamera.flatFrom
    /// Decision 333: a tilt set outright, in radians from straight down,
    /// in place of the one ``tilt(atDistance:from:)`` gives: a train's
    /// follow view (``Map3DFollow``) and a flight to one
    /// (``Map3DFlight``). `nil` tilts by the distance.
    public var pitch: Float?
    /// Decision 337: the view's height as an angle, set outright in place
    /// of ``fieldOfView``: the cab view's wider lens (``Map3DFollow``).
    /// `nil` is ``fieldOfView``.
    public var lens: Float?
    /// Decision 555: the tilt two fingers dragged up the screen add, in
    /// radians, beyond ``tilt(atDistance:from:)``'s, at most up to
    /// ``mostLean`` (``tilt(atDistance:from:lean:)``). It stays when the
    /// fingers lift, and fades with the distance's own tilt, so a camera
    /// pulled out past ``flatFrom`` looks straight down as before. 0 (the
    /// default) is the distance's tilt alone (decisions 269 and 313).
    public var lean: Float = 0

    public static let nearest: Float = 60
    public static let farthest: Float = 12_000
    /// The view's height, as an angle (35°).
    public static let fieldOfView: Float = 35 * .pi / 180
    /// From this distance out the map looks straight down; at ``tiltedFrom``
    /// and closer it leans ``mostTilt`` over. Decision 269: flat as far in
    /// as the 2D map's closer zooms (where a pinch hands the 2D map over,
    /// ``Map3DHandoff``; decision 313 hands over closer in, at the 2D
    /// map's closest zoom, and that camera is flat from there,
    /// ``tiltsFrom``), 34–40° at 150–200 m (the owner's target picture,
    /// HANDOFF §4.4), at most 42° (55° from 300 m in before).
    public static let flatFrom: Float = 800
    public static let tiltedFrom: Float = 120
    public static let mostTilt: Float = 42 * .pi / 180
    /// Decision 555: the most two fingers lean the view over (60°),
    /// short of where the ground's far edge leaves what the scene draws
    /// in full and the sun's shadows reach (the horizon shows past 72.5°).
    public static let mostLean: Float = 60 * .pi / 180
    /// Decision 555: degrees of tilt a point two fingers drag up the
    /// screen (MapLibre's `degreesPerPixelMoved`, 0.5).
    public static let leanPerPoint: Float = 0.5 * .pi / 180

    public init(target: Map3DPoint = .zero, distance: Float = 1_200, heading: Float = 0, viewport: (width: Float, height: Float) = (390, 844)) {
        self.target = target
        self.distance = min(max(distance, Self.nearest), Self.farthest)
        self.heading = heading
        self.viewport = viewport
    }

    public static func == (a: Map3DCamera, b: Map3DCamera) -> Bool {
        a.target == b.target && a.distance == b.distance && a.heading == b.heading && a.tiltsFrom == b.tiltsFrom && a.pitch == b.pitch
            && a.lens == b.lens && a.lean == b.lean
            && a.viewport.width == b.viewport.width && a.viewport.height == b.viewport.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        hasher.combine(distance)
        hasher.combine(heading)
        hasher.combine(tiltsFrom)
        hasher.combine(pitch)
        hasher.combine(lens)
        hasher.combine(lean)
    }

    /// The tilt from straight down at `distance`, in radians: 0 from
    /// `flat` (``flatFrom`` unless said) out, ``mostTilt`` from
    /// ``mostTiltedDistance(flatFrom:)`` in, and between, a smoothstep over
    /// the distance's logarithm, so each pinch tilts the map a like step.
    public static func tilt(atDistance distance: Float, from flat: Float = flatFrom) -> Float {
        let most = mostTiltedDistance(flatFrom: flat)
        guard distance < flat else { return 0 }
        guard distance > most else { return mostTilt }
        let t = (logf(flat) - logf(distance)) / (logf(flat) - logf(most))
        return mostTilt * t * t * (3 - 2 * t)
    }

    /// Where a camera flat from `flat` metres leans all the way:
    /// ``tiltedFrom``, or closer for one flat from nearer in (decision 313:
    /// a phone held sideways hands over at about 150 m), so the lean still
    /// takes a few pinches; never closer than ``nearest``.
    public static func mostTiltedDistance(flatFrom flat: Float) -> Float {
        min(tiltedFrom, max(nearest, flat * 0.45))
    }

    /// Decision 555: the tilt at `distance` with `lean` added, as a share
    /// of how far the distance's own tilt leans (all of it from
    /// ``mostTiltedDistance(flatFrom:)`` in, none from `flat` out), at most
    /// ``mostLean``. With no lean, ``tilt(atDistance:from:)``.
    public static func tilt(atDistance distance: Float, from flat: Float = flatFrom, lean: Float) -> Float {
        let own = tilt(atDistance: distance, from: flat)
        guard lean > 0 else { return own }
        return min(own + lean * own / mostTilt, max(own, mostLean))
    }

    public var tilt: Float { pitch ?? Self.tilt(atDistance: distance, from: tiltsFrom, lean: lean) }

    /// Decision 555: the camera as two fingers drag up the screen `dy`
    /// points (down is positive, so up leans over): the tilt
    /// ``leanPerPoint`` a point more, between the distance's own and
    /// ``mostLean``. A camera with its tilt set outright (``pitch``: a
    /// followed train, a flight) or looking straight down at its distance
    /// does not lean.
    public func leaned(dy: Float) -> Map3DCamera {
        guard pitch == nil, dy.isFinite else { return self }
        let own = Self.tilt(atDistance: distance, from: tiltsFrom)
        guard own > 0 else { return self }
        let wanted = min(max(tilt - dy * Self.leanPerPoint, own), max(own, Self.mostLean))
        var camera = self
        camera.lean = min(max((wanted - own) * Self.mostTilt / own, 0), Self.mostLean)
        return camera
    }

    /// Decision 555: where the view's four corners meet the ground at the
    /// target's height, in the order bottom left, bottom right, top
    /// left, top right; a corner looking above the horizon meets it at
    /// the far plane. For the sun's shadows' square (``Map3DSunShadow``).
    public var groundCorners: [Map3DPoint] {
        let eye = eye
        let look = (target - eye).normalized ?? Map3DPoint(0, -1, 0)
        let side = right
        let up = (-look).cross(side).normalized ?? forward
        let tall = tanf(fieldOfViewTall / 2), wide = tall * max(viewport.width, 1) / max(viewport.height, 1)
        let far = depthRange.far
        return [(-1, -1), (1, -1), (-1, 1), (1, 1)].map { (x: Float, y: Float) in
            let ray = look + side * (x * wide) + up * (y * tall)
            let along = ray.y < -1e-6 ? (target.y - eye.y) / ray.y : .infinity
            let length = ray.length
            return eye + ray * min(along, far / max(length, 1e-6))
        }
    }

    /// The view's height as an angle: ``lens``, or ``fieldOfView``.
    public var fieldOfViewTall: Float { lens ?? Self.fieldOfView }

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

    /// Decision 342: the depth runs the other way, 1 at the near plane
    /// and 0 at the far one ("reversed Z"), so the depth buffer's floats,
    /// finest near 0, fall where the perspective leaves the fewest steps:
    /// afar. The Metal view clears the depth to 0 and keeps the greater.
    public var projection: Map3DMatrix {
        let aspect = max(viewport.width, 1) / max(viewport.height, 1)
        let f = 1 / tanf(fieldOfViewTall / 2)
        let (near, far) = depthRange
        return Map3DMatrix(columns: [
            f / aspect, 0, 0, 0,
            0, f, 0, 0,
            0, 0, near / (far - near), -1,
            0, 0, near * far / (far - near), 0,
        ])
    }

    public var viewProjection: Map3DMatrix { projection * view }

    /// Whether any of the box from `minimum` to `maximum` may be in view
    /// through `matrix` (``viewProjection``): false only when all eight
    /// corners lie beyond one side of the view.
    /// With no arrays (2026-10-21, the far view's CPU: the owner's iPhone
    /// spent 16.6 ms a frame on Taipei seen whole): the Metal view asks it
    /// of every chunk every frame, a few hundred on a city seen whole.
    public static func sees(minimum: Map3DPoint, maximum: Map3DPoint, through matrix: Map3DMatrix) -> Bool {
        let m = matrix.columns
        var left = true, right = true, bottom = true, top = true, near = true, far = true
        for corner in 0..<8 {
            let px = corner & 1 == 0 ? minimum.x : maximum.x
            let py = corner & 2 == 0 ? minimum.y : maximum.y
            let pz = corner & 4 == 0 ? minimum.z : maximum.z
            let x = m[0] * px + m[4] * py + m[8] * pz + m[12]
            let y = m[1] * px + m[5] * py + m[9] * pz + m[13]
            let z = m[2] * px + m[6] * py + m[10] * pz + m[14]
            let w = m[3] * px + m[7] * py + m[11] * pz + m[15]
            if !(x < -w) { left = false }
            if !(x > w) { right = false }
            if !(y < -w) { bottom = false }
            if !(y > w) { top = false }
            if !(z < 0) { near = false }
            if !(z > w) { far = false }
        }
        return !(left || right || bottom || top || near || far)
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
        func within(_ x: Float, _ z: Float) -> Bool {
            let dx = x - min(max(x, minimum.x), maximum.x), dz = z - min(max(z, minimum.z), maximum.z)
            return dx * dx + dz * dz <= reach * reach
        }
        if within(target.x, target.z) { return true }
        let eye = eye
        return within(eye.x, eye.z)
    }

    /// Decision 267: within this distance, the chunks round the target
    /// also draw their closest detail (``Map3DScene/Chunk/close``: a
    /// street's awnings, washing, counters and crates), within this reach
    /// of the target: about where the street's people show (decision 259).
    public static let closeDistance: Float = 450
    public static let closeReach: Float = 350

    /// Whether the chunk from `minimum` to `maximum` draws its closest
    /// detail, with the same margin as ``wantsDetail(minimum:maximum:wasDetailed:)``.
    public func wantsClose(minimum: Map3DPoint, maximum: Map3DPoint, wasClose: Bool = false) -> Bool {
        let margin: Float = wasClose ? 1.14 : 0.86
        guard distance <= Self.closeDistance * margin else { return false }
        let reach = max(Self.closeReach, distance * 0.9) * margin
        let dx = target.x - min(max(target.x, minimum.x), maximum.x), dz = target.z - min(max(target.z, minimum.z), maximum.z)
        return dx * dx + dz * dz <= reach * reach
    }

    /// Decision 380: whether a chunk from `minimum` to `maximum` draws its
    /// closest detail: close up, and drawn in full (`detailed`), or built
    /// coarse (decision 368), when its closest detail is the overhead
    /// line alone, which runs all along the line.
    public func drawsClose(minimum: Map3DPoint, maximum: Map3DPoint, detailed: Bool, coarse: Bool, wasClose: Bool = false) -> Bool {
        (detailed || coarse) && wantsClose(minimum: minimum, maximum: maximum, wasClose: wasClose)
    }

    // MARK: - Gestures

    /// Metres on the ground per point on the screen at the target.
    public var metresPerPoint: Float {
        2 * distance * tanf(fieldOfViewTall / 2) / max(viewport.height, 1)
    }

    /// The camera moved as a finger drags the map `dx`, `dy` points (right
    /// and down): the ground follows the finger.
    public func panned(dx: Float, dy: Float) -> Map3DCamera {
        var camera = self
        let scale = metresPerPoint
        camera.target = target - right * (dx * scale) + forward * (dy * scale)
        return camera
    }

    /// Decision 714 (MAP3D-FAR): the camera with its target over
    /// `ground` (scene x and z, ``Map3DStreaming/ground``), moved to its
    /// nearest edge when a drag took it past: off the map there is
    /// nothing to build, so nothing to see.
    public func held(over ground: (x: ClosedRange<Float>, z: ClosedRange<Float>)) -> Map3DCamera {
        var camera = self
        camera.target.x = min(max(target.x, ground.x.lowerBound), ground.x.upperBound)
        camera.target.z = min(max(target.z, ground.z.lowerBound), ground.z.upperBound)
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

    // MARK: - North (decision 269, later: the compass)

    /// How far from north the view may face, in radians, and still count
    /// as facing north: 0.05°, as the reference's map decides it is turned
    /// (`syncOrientationClass` in `main-reference.js`). Less does not show
    /// on a screen: the edge of a phone's view moves under half a point.
    public static let northTolerance: Float = 0.05 * .pi / 180

    /// `heading` as a turn from north, more than -π and at most π:
    /// positive is turned clockwise (facing east of north).
    public static func turnFromNorth(_ heading: Float) -> Float {
        var turn = heading.truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi } else if turn <= -.pi { turn += 2 * .pi }
        return turn
    }

    public var turnFromNorth: Float { Self.turnFromNorth(heading) }

    /// Whether the view faces north, within ``northTolerance``: the 3D
    /// map's compass shows only when it does not.
    public var facesNorth: Bool { abs(turnFromNorth) <= Self.northTolerance }

    /// The camera `progress` (0 to 1) of the way back to north from facing
    /// `start` when the compass was tapped: the shorter way round, fast at
    /// first and landing gently (``MotionRule/turnNorth``), as the
    /// reference's `stepMapNorth` eases (1 − (1 − t)²); exactly north at 1.
    public func turnedNorth(from start: Float, progress: Float) -> Map3DCamera {
        var camera = self
        let t = min(max(progress, 0), 1)
        camera.heading = t >= 1 ? 0 : Self.turnFromNorth(start) * (1 - t) * (1 - t)
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
    /// Decision 277: the day's weather, clear unless it rains.
    public var weather: Map3DWeather = .clear
    /// Decision 347: the hour of the day, 0 to 24.
    public let hour: Float
    /// Decision 813: toward the sky's sun and (full) moon, one metre long,
    /// where they stand, below the horizon too (``Map3DSky``).
    public let skySun: Map3DPoint
    public let skyMoon: Map3DPoint
    /// Decision 942: the share of the moon's disc lit, 0 (new) to 1
    /// (full), and the way from the moon toward the sun, one metre long:
    /// the side of the disc that is lit (``Map3DSky``). Full, lit from
    /// behind the eye, for a light with no date.
    public var moonLit: Float = 1
    public var moonSunward: Map3DPoint = .up
    /// Decision 813's later part (AURORA): how bright tonight's aurora is,
    /// 0 to 1, before the sky's darkness and the clouds (``Map3DSky/aurora``);
    /// 0 but far in the north (``aurora(at:latitude:)``).
    public var aurora: Float = 0

    struct Key {
        let hour: Float
        let zenith: UInt32, sky: UInt32, sun: UInt32, ground: UInt32
        let ambient: Float, sunStrength: Float, night: Float
    }

    /// The owner on TestFlight (2026-10-16): "晚上 3D 是不是偏暗？" Without
    /// three.js's tone mapping and the reference's lamps the reference's
    /// night came to a fifth of white on the ground. The city's own lights
    /// came first (``lights``: street lights, their pools, lit windows);
    /// then the night and dusk keys' ambient light is raised a little
    /// (0.58 → 0.75, dusk 0.72 → 1) and the moon lights the night
    /// (strength 1, the cool `sun` colour), so the ground and roads read at
    /// night at about 40 % of noon, still blue (`Map3DNightAndGroundTests`).
    static let keys: [Key] = [
        Key(hour: 0, zenith: 0x06141C, sky: 0x163742, sun: 0x9FD0D8, ground: 0x2C4A52, ambient: 0.75, sunStrength: 1, night: 1),
        Key(hour: 5, zenith: 0x0E1C2A, sky: 0x2C4553, sun: 0xF4BD92, ground: 0x3E5560, ambient: 0.75, sunStrength: 1, night: 1),
        Key(hour: 6.5, zenith: 0x6F89B3, sky: 0xF0C1A0, sun: 0xFFB98A, ground: 0x958071, ambient: 1, sunStrength: 1, night: 0.35),
        Key(hour: 8, zenith: 0x86ACD6, sky: 0xE4E3D8, sun: 0xFFE2BC, ground: 0xA69986, ambient: 1.2, sunStrength: 2.3, night: 0),
        Key(hour: 12, zenith: 0x78A5D6, sky: 0xDDE6E8, sun: 0xFFF1DC, ground: 0xA79987, ambient: 1.3, sunStrength: 2.6, night: 0),
        Key(hour: 15.5, zenith: 0x86A9CF, sky: 0xF4D4AC, sun: 0xFFBF78, ground: 0xC39F80, ambient: 1.2, sunStrength: 2.85, night: 0),
        Key(hour: 17.5, zenith: 0x8494B8, sky: 0xF6BB8C, sun: 0xFFB276, ground: 0xA47C63, ambient: 1, sunStrength: 1.9, night: 0.12),
        Key(hour: 18.5, zenith: 0x38466E, sky: 0xD88A74, sun: 0xFF9C78, ground: 0x5F5F74, ambient: 1, sunStrength: 0.35, night: 0.7),
        Key(hour: 20, zenith: 0x0A1824, sky: 0x1E3F4B, sun: 0x9FD0D8, ground: 0x2F4D56, ambient: 0.75, sunStrength: 1, night: 1),
        Key(hour: 24, zenith: 0x06141C, sky: 0x163742, sun: 0x9FD0D8, ground: 0x2C4A52, ambient: 0.75, sunStrength: 1, night: 1),
    ]

    /// The keyframes at `hour`, channels 0–255 unrounded.
    struct Keyed {
        var zenith: SIMD3<Float>, sky: SIMD3<Float>, sun: SIMD3<Float>, ground: SIMD3<Float>
        var ambient: Float, sunStrength: Float, night: Float

        init(hour: Float) {
            var index = 1
            while index < Map3DLighting.keys.count - 1, Map3DLighting.keys[index].hour <= hour { index += 1 }
            let a = Map3DLighting.keys[index - 1], b = Map3DLighting.keys[index]
            let t = b.hour > a.hour ? min(max((hour - a.hour) / (b.hour - a.hour), 0), 1) : 0
            func mix(_ x: UInt32, _ y: UInt32) -> SIMD3<Float> {
                func channel(_ shift: UInt32) -> Float {
                    let p = Float((x >> shift) & 0xFF), q = Float((y >> shift) & 0xFF)
                    return p + (q - p) * t
                }
                return SIMD3(channel(16), channel(8), channel(0))
            }
            zenith = mix(a.zenith, b.zenith)
            sky = mix(a.sky, b.sky)
            sun = mix(a.sun, b.sun)
            ground = mix(a.ground, b.ground)
            ambient = a.ambient + (b.ambient - a.ambient) * t
            sunStrength = a.sunStrength + (b.sunStrength - a.sunStrength) * t
            night = a.night + (b.night - a.night) * t
        }

        /// Decision 813: `self` turned `share` of the way to `other`.
        func mixed(with other: Keyed, _ share: Float) -> Keyed {
            guard share > 0 else { return self }
            var out = self
            out.zenith = zenith + (other.zenith - zenith) * share
            out.sky = sky + (other.sky - sky) * share
            out.sun = sun + (other.sun - sun) * share
            out.ground = ground + (other.ground - ground) * share
            out.ambient = ambient + (other.ambient - ambient) * share
            out.sunStrength = sunStrength + (other.sunStrength - sunStrength) * share
            out.night = night + (other.night - night) * share
            return out
        }
    }

    init(keyed: Keyed, hour: Float, sunDirection: Map3DPoint, skySun: Map3DPoint, skyMoon: Map3DPoint) {
        func rgb(_ value: SIMD3<Float>) -> PopTravel.RGB {
            PopTravel.RGB(red: UInt8(value.x.rounded()), green: UInt8(value.y.rounded()), blue: UInt8(value.z.rounded()))
        }
        zenith = rgb(keyed.zenith)
        sky = rgb(keyed.sky)
        sun = rgb(keyed.sun)
        ground = rgb(keyed.ground)
        ambient = keyed.ambient
        sunStrength = keyed.sunStrength
        night = keyed.night
        self.hour = hour
        self.sunDirection = sunDirection
        self.skySun = skySun
        self.skyMoon = skyMoon
        moonSunward = -skyMoon
    }

    /// The light at `minute` of the day (wrapped into a day), the sun up
    /// at 06:00 and down at 18:00 whatever the day and the place: the
    /// light before decision 813, kept for the showcase and for a light
    /// with no date.
    public init(minute: Double) {
        var m = minute.truncatingRemainder(dividingBy: 1_440)
        if m < 0 { m += 1_440 }
        let hour = Float(m / 60)
        // The sun rises in the east at 06:00, stands high in the south at
        // noon and sets in the west at 18:00; at night the moon lights the
        // scene from overhead, a little to the south. Within half an hour of
        // 06:00 and 18:00 the light turns from the one to the other, so a
        // roof does not brighten or darken in a step as the sun sets.
        let dayShare = (hour - 6) / 12
        let angle = Float.pi * min(max(dayShare, 0), 1)
        let elevation = max(sinf(angle), 0.08) * 1.15
        let sunLight = Map3DPoint(cosf(angle), elevation, 0.45 * sinf(angle)).normalized ?? .up
        let fromEdge = min(abs(hour - 6), abs(hour - 18)) / Self.lightTurnHours
        let isDay = dayShare > 0 && dayShare < 1
        let sunShare = fromEdge >= 1 ? (isDay ? 1 : 0) : 0.5 + (isDay ? 0.5 : -0.5) * fromEdge
        // The sky's sun and the (full) moon cross it as the light's sun
        // does: the moon up in the east at 18:00, down in the west at 06:00.
        var night = hour - 18
        if night < 0 { night += 24 }
        self.init(keyed: Keyed(hour: hour), hour: hour,
                  sunDirection: (sunLight * sunShare + Self.moonLight * (1 - sunShare)).normalized ?? .up,
                  skySun: Map3DSky.path(at: dayShare, rise: 1.15), skyMoon: Map3DSky.path(at: night / 12, rise: 0.9))
    }

    /// The moon's light by night: from overhead, a little to the south.
    static let moonLight = Map3DPoint(0.2, 1, 0.3).normalized ?? .up

    /// Decision 942: how strong the night's light is under `moon`, as a
    /// share of the full moon's (the keyframes' night, decision 229): all
    /// of it under a full moon that is up, ``darkestNight`` with no moon
    /// in the sky, the share between as the lit disc and its height (from
    /// 2° under the horizon to 6° over it). Only the light from the moon's
    /// side; the sky's ambient light stays, so a moonless night is not
    /// black (the owner's 2026-10-16 note).
    static func moonlight(_ moon: Map3DSunPath.Moon) -> Float {
        let up = Map3DSeeThrough.smoothstep(-2, 6, Float(moon.elevation))
        return darkestNight + (1 - darkestNight) * Float(moon.illuminated) * up
    }

    /// The light's share on a night with no moon up.
    static let darkestNight: Float = 0.6

    /// Decision 813: the light at game time `time` over `place`, the sun
    /// where it stands there on the game's day (``Map3DSunPath``).
    ///
    /// The keyframes stay the hours of a day at 25° N in March, when the
    /// sun is up from 06:00 to 18:00: the sun's elevation now is read as
    /// the hour it stood that high on that day, before noon on the
    /// morning's side and after it on the evening's (``keyHours(elevation:)``).
    /// So a low winter sun gives a morning's or an evening's light at noon,
    /// and a sun that never clears the horizon (Rovaniemi in December)
    /// only the blue of the dawn. The morning's and the evening's keys are
    /// not the same, so within two hours of the true noon and of the true
    /// midnight the light turns from the one to the other (``eveningShare(hourAngle:)``),
    /// and nothing steps.
    public init(at time: GameTime, place: Map3DSunPlace) {
        let seconds = time.seconds - GameDate.floorDivide(time.seconds, GameTime.secondsPerDay) * GameTime.secondsPerDay
        let minute = Double(seconds) / 60
        let day = Map3DSunPath.realDayOfYear(gameDay: GameDate.floorDivide(time.seconds, GameTime.secondsPerDay))
        let position = Map3DSunPath.position(day: day, minute: minute, at: place)
        let keys = Self.keyHours(elevation: position.elevation)
        var keyed = Keyed(hour: keys.morning).mixed(with: Keyed(hour: keys.evening), Self.eveningShare(hourAngle: position.hourAngle))
            .mixed(with: Self.polarNoon, Self.polarNoonShare(elevation: position.elevation, highest: position.highest(atLatitude: place.latitude)))
        let toSun = Self.direction(elevation: position.elevation, azimuth: position.azimuth)
        let lit = Self.direction(elevation: max(position.elevation, Self.lowestLight), azimuth: position.azimuth)
        let sunShare = Float(min(max(0.5 + 0.5 * position.elevation / Self.lightTurnDegrees, 0), 1))
        // Decision 942: the moon where it stands and as much of it lit as
        // tonight's phase, and the night's light as strong as the moon
        // (``moonlight(_:)``).
        let moon = Map3DSunPath.moonPosition(date: time, place: place)
        keyed.sunStrength *= 1 - (1 - Self.moonlight(moon)) * min(max(keyed.night, 0), 1)
        self.init(keyed: keyed, hour: Float(minute / 60),
                  sunDirection: (lit * sunShare + Self.moonLight * (1 - sunShare)).normalized ?? .up,
                  skySun: toSun, skyMoon: Self.direction(elevation: moon.elevation, azimuth: moon.azimuth))
        moonLit = Float(moon.illuminated)
        moonSunward = Map3DPoint(Float(moon.towardSun.x), Float(moon.towardSun.z), Float(-moon.towardSun.y)).normalized ?? .up
        aurora = Self.aurora(at: time, latitude: place.latitude)
    }

    /// Decision 813: the light of a day whose sun never climbs far (the
    /// Arctic's winter, kaamos): no dawn and no dusk but a long blue
    /// twilight round noon, the snow lit blue by the sky, the horizon rose
    /// where the sun is under it, the street lights still on. Without it
    /// the keyframes' dawn, which lasts there all day, came out a dark grey
    /// night. The colours are this project's own, after photographs of
    /// Rovaniemi's December noon.
    static let polarNoon: Keyed = {
        var keyed = Keyed(hour: 12)
        keyed.zenith = SIMD3(0x4F, 0x6E, 0x9E)
        keyed.sky = SIMD3(0xC4, 0xB4, 0xC8)
        keyed.sun = SIMD3(0xFF, 0xB8, 0xA0)
        keyed.ground = SIMD3(0x70, 0x82, 0xA6)
        keyed.ambient = 1.05
        keyed.sunStrength = 0.45
        keyed.night = 0.3
        return keyed
    }()

    /// How much of ``polarNoon`` the light takes: on a day whose sun climbs
    /// no higher than 4° (and none at 14° and over, so never in Taiwan or
    /// Hong Kong, whose winter noon sun is 40° high), while the sun is
    /// higher than 9° under the horizon (the civil twilight's end, 6°,
    /// and a little), so the twilight goes on round noon even where the sun
    /// does not rise at all.
    static func polarNoonShare(elevation: Double, highest: Double) -> Float {
        func smooth(_ low: Double, _ high: Double, _ x: Double) -> Double {
            let t = min(max((x - low) / (high - low), 0), 1)
            return t * t * (3 - 2 * t)
        }
        return Float((1 - smooth(4, 14, highest)) * smooth(-9, -3, elevation))
    }

    /// The latitude and season the keyframes were drawn for: 25° N at the
    /// equinox, the sun up 06:00 to 18:00.
    static let keyLatitude = 25.0

    /// The hours of the keyframes' day the sun stood `elevation` degrees
    /// high, before noon and after it: 6 and 18 on the horizon, 12 at 65°
    /// and over, 0 and 24 at 65° under.
    static func keyHours(elevation: Double) -> (morning: Float, evening: Float) {
        let share = min(max(sin(elevation * Map3DSunPath.rad) / cos(keyLatitude * Map3DSunPath.rad), -1), 1)
        let hours = Float(asin(share) / Map3DSunPath.rad / 15)
        return (6 + hours, 18 - hours)
    }

    /// How much of the evening's keys the light takes at `hourAngle`
    /// (degrees from the true noon): none in the morning, all of them in
    /// the afternoon, turning over the two hours either side of noon and
    /// halfway at the true midnight.
    static func eveningShare(hourAngle: Double) -> Float {
        func smooth(_ low: Double, _ high: Double, _ x: Double) -> Double {
            let t = min(max((x - low) / (high - low), 0), 1)
            return t * t * (3 - 2 * t)
        }
        let share: Double
        if hourAngle > 150 { share = 1 - 0.5 * smooth(150, 180, hourAngle) }
        else if hourAngle < -150 { share = 0.5 * (1 - smooth(-180, -150, hourAngle)) }
        else { share = smooth(-30, 30, hourAngle) }
        return Float(share)
    }

    /// Toward a sun `elevation` degrees high, `azimuth` round from the
    /// north through the east: east is +x, south +z.
    static func direction(elevation: Double, azimuth: Double) -> Map3DPoint {
        let e = elevation * Map3DSunPath.rad, a = azimuth * Map3DSunPath.rad
        return Map3DPoint(Float(cos(e) * sin(a)), Float(sin(e)), Float(-cos(e) * cos(a)))
    }

    /// The lowest the light comes from, degrees, as the light before
    /// decision 813 (about 5°): a sun on the horizon does not lay shadows
    /// across the whole map or light a wall from below.
    static let lowestLight = 5.3

    /// How many degrees under and over the horizon the light takes to turn
    /// from the moon to the sun: the half hour of the keyframes' day.
    static let lightTurnDegrees = 6.8

    /// How long before and after sunrise and sunset the light takes to
    /// turn from the sun to the moon or back, in hours, half each side.
    static let lightTurnHours: Float = 0.5

    /// The light at game time `time`.
    public init(at time: GameTime) {
        let seconds = time.seconds % GameTime.secondsPerDay
        self.init(minute: Double(seconds < 0 ? seconds + GameTime.secondsPerDay : seconds) / 60)
    }

    // MARK: The light the shaders use

    // The keyframes' strengths are three.js's; scaled here so the noon sun
    // on a roof comes to about white, with the colours as they are (no
    // tone mapping). `Map3DMetalView` hands these to `Map3DShaders.metal`
    // as they are (decision 229's rule 3: worked out here, tested on Linux).

    /// The sun's (or the moon's) light, red, green and blue.
    public var sunLight: SIMD3<Float> {
        let colour = Self.mix(Self.rgb(sun), Self.rgb(weather.skyTint), weather.skyMix * weatherStrength * 0.3)
        return colour * (sunStrength * 0.16 * dayBoost * Self.mix(weather.nightSunScale, weather.daySunScale, daylight))
    }
    /// The ambient light from the sky, on what faces up.
    public var skyLight: SIMD3<Float> {
        Self.tinted(Self.mix(Self.rgb(sky), Self.rgb(weather.hemiTint), weather.hemiMix * weatherStrength),
                    share: 0.3, scale: ambient * 0.5 * dayBoost * hemiScale)
    }
    /// The ambient light from the ground, on what faces down.
    public var groundLight: SIMD3<Float> {
        Self.tinted(Self.mix(Self.rgb(ground), Self.rgb(weather.groundTint), weather.groundMix * weatherStrength),
                    share: 0.5, scale: ambient * 0.5 * 0.8 * dayBoost * hemiScale)
    }

    // MARK: The weather (decision 277)

    /// The sky behind the map, 0–1 a channel: the hour's sky, greyer under
    /// rain (`applyLighting`'s background).
    public var background: SIMD3<Float> {
        Self.mix(Self.rgb(sky), Self.rgb(weather.skyTint), weather.skyMix * weatherStrength)
    }

    /// The fog's colour: the hour's sky, greyer under rain.
    public var fogColour: SIMD3<Float> {
        Self.mix(Self.rgb(sky), Self.rgb(weather.fogTint), weather.fogMix * weatherStrength)
    }

    /// Where the fog starts and ends, as shares of where it does on a
    /// clear day: nearer under rain.
    public var fogScale: (near: Float, far: Float) {
        (Self.mix(1, weather.fogNear, weatherStrength), Self.mix(1, weather.fogFar, weatherStrength))
    }

    /// 1 by day, 0 at night. The reference reads it from the sun's
    /// strength (0.45 to 3); here the moon lights the night at strength 1
    /// (decision 229), so it is the night's own measure, turned round.
    var daylight: Float { 1 - min(max(night, 0), 1) }
    /// How strongly the weather shows: wholly by day, a little under half
    /// at night (`weatherStrength`).
    var weatherStrength: Float { Self.mix(0.45, 1, daylight) }
    var hemiScale: Float { Self.mix(weather.nightHemiScale, weather.dayHemiScale, daylight) }

    /// Decision 272: by day the light a little stronger than three.js's
    /// keyframes (a bright, clear day, as the owner's target picture), at
    /// night as it was.
    public static let dayBrightening: Float = 0.12
    var dayBoost: Float { 1 + Self.dayBrightening * (1 - min(max(night, 0), 1)) }

    /// A surface of `colour` (0–1 a channel) facing `normal` as the
    /// fragment shader lights it, before the fog.
    public func lit(_ colour: SIMD3<Float>, normal: Map3DPoint) -> SIMD3<Float> {
        let facing = normal.normalized ?? .up
        let toSun = max(facing.dot(sunDirection), 0)
        let share = facing.y * 0.5 + 0.5
        let ambient = groundLight + (skyLight - groundLight) * share
        return colour * (ambient + sunLight * toSun)
    }

    // MARK: The city's lights at night

    /// How far the city's lights are on, 0 by day to 1 at night: street
    /// lights, their pools on the ground and lit windows. They come on
    /// while the dusk is still light (`Web/CityView/src/world/environment.js`:
    /// "they come on while it is still light").
    public var lights: Float { min(max(night * 1.4, 0), 1) }

    /// The light a street light's head gives at night, added to its lit
    /// colour (the shader's glowing vertices, ``Map3DVertex/glowing``).
    public func lampGlow(_ colour: SIMD3<Float>) -> SIMD3<Float> { colour * (1.3 * lights) }

    /// `Map3DUniforms.nightWindows` in `Map3DShaders.metal`, its
    /// ``nightWindowRowCount`` rows: for each ``Map3DSurface`` layer in
    /// order, two to a row, the share of its
    /// windows lit at night and how bright its own colour may be to be
    /// lit (glass is dark; a shop's goods and signs are lit whole).
    public static let nightWindowRowCount = 16
    public static let nightWindowRows: [Float] = {
        var values: [Float] = []
        for surface in Map3DSurface.allCases {
            let rule = Map3DNightWindows.rule(surface)
            values += [rule.share, rule.brightest]
        }
        precondition(values.count <= nightWindowRowCount * 4, "the shader's nightWindows holds 32 layers")
        return values + Array(repeating: 0, count: nightWindowRowCount * 4 - values.count)
    }()
}

/// Decision 229 續 (2026-10-16): which windows light up at night. A window
/// is the glass of a bay on one floor of a face (``Map3DPaint/bays``):
/// lit or not by a hash of the bay, the floor and the face, so the same
/// windows are lit every night and none flickers. Shops are lit more
/// often than offices, offices than homes, after this repository's 3D
/// city view (`Web/CityView/src/world/materials.js`, MIT: `onRate`
/// shop 0.75, office 0.32, home 0.22, a building's own busyness, warm
/// bulbs `mix((1, 0.6, 0.3), (1, 0.82, 0.6))`); homes and offices here a
/// little more often, so a town's blocks still show at night.
public enum Map3DNightWindows {
    /// The share of `surface`'s windows lit (before a face's busyness,
    /// 0.5–1.6 times), and the brightest its own colour may be (0–1
    /// luminance) to count as glass.
    public static func rule(_ surface: Map3DSurface) -> (share: Float, brightest: Float) {
        switch surface {
        case .shopfront, .shopOptical, .shopPhone, .shopEatery, .shopTea: (0.75, 1)
        case .officeGlass: (0.4, 0.45)
        case .homeWindows, .homeBalcony, .flatWindows, .flatBlinds, .flatBalconies, .hkWindows: (0.35, 0.45)
        case .officeRibbon, .curtainSpandrel, .officeFins: (0.4, 0.45)
        case .grass, .paving, .ballast, .concrete, .roof, .plaster, .shutter, .metalSheet,
             .formConcrete, .brickTile, .mosaicTile, .terrazzo, .crosswalk, .laneArrows: (0, 0)
        }
    }
}

extension Map3DLighting {
    /// `colour` as 0–1 a channel.
    public static func rgb(_ colour: PopTravel.RGB) -> SIMD3<Float> {
        SIMD3(Float(colour.red), Float(colour.green), Float(colour.blue)) / 255
    }

    /// `colour` (`0xRRGGBB`) as 0–1 a channel.
    static func rgb(_ colour: UInt32) -> SIMD3<Float> {
        SIMD3(Float((colour >> 16) & 0xFF), Float((colour >> 8) & 0xFF), Float(colour & 0xFF)) / 255
    }

    /// White `share` of the way to `colour`, times `scale`.
    static func tinted(_ colour: SIMD3<Float>, share: Float, scale: Float) -> SIMD3<Float> {
        (SIMD3<Float>(repeating: 1) + (colour - SIMD3<Float>(repeating: 1)) * share) * scale
    }

    static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
}
