import GameCore

// Decision 672: seeing underground in the 3D map.
//
// The owner (2026-10-22): 「讓列車在地下也看得到／用顯示跟不顯示 以免浪費gpu算力」
// and 「記得改成遊戲風格而不是照搬」. A switch in Settings, off by default:
// off, nothing here is built or drawn. On, the overview (no train or
// vehicle followed) draws the player's tunnels, the trains in them and the
// underground stations' platforms through the ground, in flat see-through
// colours, as one more pass after everything else.
//
// The reference's `live-underground-3d` layer (`Railway/taiwan-rail-reference-clean/source/rail-3d/integration/map3d.js`,
// `buriedDraw` `xray`, `undergroundMaterial` 0.42): the depth cleared, the
// buried track and trains drawn at 0.42 opacity, on flat land, not under
// mountains (30 m of cover). Here the same rule for what shows (cover up
// to ``deepest``), the depth not cleared but not tested (one pass, a
// pipeline any GPU has), and the look the game's own: flat bands of the
// palette's tunnel colours rather than the reference's lit materials.

/// Decision 672: what the 3D map draws underground when seeing through the
/// ground is on: the tunnels' track and the underground stations'
/// platforms (``mesh``, built once a scene), and each frame the cars in
/// the tunnels (``addCars(_:to:)``). Each vertex's alpha is how much of it
/// shows.
public struct Map3DXRay: Sendable {
    /// The tunnels' track and the underground platforms, in the scene's
    /// space.
    public let mesh: Map3DMesh

    /// Nothing.
    public init() {
        mesh = Map3DMesh()
    }

    /// `scene`'s tunnels (``Map3DScene/trackCover``, the whole network)
    /// and `snapshot`'s platforms in them.
    public init(scene: Map3DScene, snapshot: RailwaySnapshot) {
        var mesh = Map3DMesh()
        Self.addTunnels(scene.trackCover, to: &mesh)
        for platform in Self.platforms(snapshot, in: scene) { Self.addPlatform(platform, to: &mesh) }
        self.mesh = mesh
    }

    /// Whether the frame draws it: only over the map, not while the camera
    /// follows a train or vehicle (from the cab or behind it, the ground
    /// over a tunnel is not between the eye and it).
    public static func draws(switchOn: Bool, following: Bool) -> Bool { switchOn && !following }

    // MARK: Look

    /// How much rock or earth over the rails still lets them show, metres:
    /// flat land and a city's subway, not a mountain's tunnel. Decision
    /// 674: 40 m, not the reference's 30 m, which hid the Tamsui–Xinyi
    /// Line from Zhongshan to NTU Hospital (Taipei Main Station 36 m
    /// under the drawn ground).
    public static let deepest: Float = 40
    /// The bore's band, as wide as the bore, and the rails' band in it.
    static let boreWidth: Float = 2 * Map3DScene.Builder.boreHalfWidth
    static let railWidth: Float = 1.6
    /// How much of each shows (the vertex's alpha, 0–255).
    static let boreOpacity: UInt32 = 110
    static let railOpacity: UInt32 = 190
    static let platformOpacity: UInt32 = 170
    /// Decision 674: the cars nearly solid, so a train in a tunnel reads
    /// at a glance (672's 215 over a white body was a faint ghost).
    static let carOpacity: UInt32 = 240
    /// The palette's tunnel lining and the player's dark navy; the
    /// platform's own paving and edge (``Map3DPalette``).
    static let boreColour = Map3DPalette.tunnelLining
    static let railColour = Map3DPalette.playerRim

    /// `colour` (opaque, from ``Map3DColor/rgb(_:)``) showing `opacity` of 255.
    static func seen(_ colour: UInt32, _ opacity: UInt32) -> UInt32 {
        (colour & 0x00FF_FFFF) | min(opacity, 255) << 24
    }

    // MARK: Tunnels

    /// Whether a tunnel's piece shows: under no more than ``deepest`` of
    /// ground at either end.
    static func shows(_ piece: Map3DTrackCover.Piece) -> Bool {
        piece.isTunnel && min(piece.groundA - piece.a.y, piece.groundB - piece.b.y) <= deepest
    }

    /// Each tunnel piece of `cover` that shows: the bore's band and the
    /// rails' band, a little over the rails so the two do not cross.
    static func addTunnels(_ cover: Map3DTrackCover, to mesh: inout Map3DMesh) {
        for piece in cover.pieces where shows(piece) {
            let line = [piece.a, piece.b]
            mesh.addRibbon(along: line, width: boreWidth, lift: -Map3DScene.Builder.bedDrop, top: seen(boreColour, boreOpacity))
            mesh.addRibbon(along: line, width: railWidth, lift: 0.05, top: seen(railColour, railOpacity))
        }
    }

    // MARK: Underground stations

    /// An underground platform as the see-through view lays it: its
    /// station, the centre line of its track (at the rails' height), and
    /// how far across that line the platform's middle stands and how
    /// wide it is (negative across: to the line's left).
    public struct Platform: Equatable, Sendable {
        public let station: StationID
        public let line: [Map3DPoint]
        public let offset: Float
        public let width: Float
    }

    /// `snapshot`'s platforms in tunnels, in `scene`'s space: beside their
    /// track on its left, or, where another platform of the same station
    /// runs beside within 15 m, an island halfway between the two.
    /// Decision 674: beside it at the same level and the same way, not a
    /// line crossing over or under it (Taipei Main Station's Bannan Line,
    /// 21 m over the Tamsui–Xinyi Line, was laid an island with it).
    static func platforms(_ snapshot: RailwaySnapshot, in scene: Map3DScene) -> [Platform] {
        let buried = snapshot.platforms.filter { $0.structure == .tunnel && $0.points.count > 1 }
        let lines = buried.map { $0.points.map { scene.point($0) + Map3DScene.Builder.lifted } }
        let edge = Map3DScene.Builder.platformEdge
        var laid: [Platform] = []
        for (index, platform) in buried.enumerated() {
            let line = lines[index], middle = line[line.count / 2]
            let across = Map3DMesh.acrossDirections(line)[line.count / 2]
            let way = Self.way(of: line)
            let beside = buried.indices
                .filter { $0 != index && buried[$0].platform.station == platform.platform.station }
                .filter { abs(lines[$0][lines[$0].count / 2].y - middle.y) <= sameLevel && abs(Self.way(of: lines[$0]).dot(way)) >= alongside }
                .map { (lines[$0][lines[$0].count / 2] - middle).dot(across) }
                .filter { abs($0) < 15 }
            let partner = beside
                .filter { abs($0) / 2 - edge >= Map3DScene.Builder.narrowestPlatform }
                .min { abs($0) < abs($1) }
            if let partner {
                let width = abs(partner) - 2 * edge
                laid.append(Platform(station: platform.platform.station, line: line, offset: partner / 2, width: width))
            } else {
                // Decision 674: on the side away from a track beside it too
                // near for an island (Taipei Main's Tamsui–Xinyi Line, its
                // two tracks 5 m apart), not over that track.
                let width = Map3DScene.Builder.platformWidth
                let side: Float = beside.contains { $0 < 0 } && !beside.contains { $0 > 0 } ? 1 : -1
                laid.append(Platform(station: platform.platform.station, line: line, offset: side * (edge + width / 2), width: width))
            }
        }
        return laid
    }

    /// Decision 674: how far up or down, metres, and how near the same way
    /// (the cosine between them) another platform runs to make an island
    /// with this one.
    static let sameLevel: Float = 2
    static let alongside: Float = 0.9

    /// The level way from a line's first point to its last.
    static func way(of line: [Map3DPoint]) -> Map3DPoint {
        guard let first = line.first, let last = line.last else { return .zero }
        return Map3DPoint(last.x - first.x, 0, last.z - first.z).normalized ?? .zero
    }

    /// Decision 672: one underground platform drawn, a plain slab at the
    /// platform's height with its yellow edge.
    ///
    /// The place for decision 670's underground station parts (the
    /// station kit's platform, its screen doors, stairs and lights, Codex
    /// `codex/underground-platform-kit`): once they are merged, this lays
    /// those along `platform.line` instead, as the surface stations lay
    /// the kit's parts (``Map3DStationKit``). Its callers stay as they
    /// are.
    static func addPlatform(_ platform: Platform, to mesh: inout Map3DMesh) {
        let height = Map3DScene.Builder.platformHeight
        mesh.addRibbon(along: platform.line, width: platform.width, offset: platform.offset, lift: height,
                       depth: height + Map3DScene.Builder.bedDrop, top: seen(Map3DPalette.platform, platformOpacity),
                       side: seen(Map3DColor.shaded(Map3DPalette.platform, 0.8), platformOpacity))
        for side: Float in [-1, 1] {
            let rim = platform.offset + side * (platform.width / 2 - 0.35)
            mesh.addRibbon(along: platform.line, width: 0.3, offset: rim, lift: height + 0.01,
                           top: seen(Map3DPalette.platformEdge, platformOpacity))
        }
    }

    // MARK: Cars

    /// A car in a tunnel this frame, as ``Map3DTrains/frame(_:progress:heights:in:models:eye:palette:ringed:reach:buried:headlamp:)``
    /// finds it: from its back to its front on the rails, and its colour
    /// (decision 674: its line's, else its body's).
    public struct Car: Equatable, Sendable {
        public let back: Map3DPoint
        public let front: Map3DPoint
        public let colour: UInt32
    }

    /// Decision 674: how far the dark rim round a car reaches past it,
    /// each way and over its roof, metres: the outline the game's flat
    /// look draws round what it picks out (the 2D map's trains, the
    /// labels' ink border), here in the tunnels' navy.
    static let rim: Float = 0.6

    /// `cars` as see-through boxes, as long as each car and as wide and
    /// high as the trains' boxes (``Map3DTrains/carWidth``). Decision 674:
    /// in the line's colour, nearly solid, its sides a shade darker and
    /// its top last (nothing here is depth tested, so what is added later
    /// shows over what came before), over a navy rim a little larger.
    public static func addCars(_ cars: [Car], to mesh: inout Map3DMesh) {
        let base = Map3DPoint(0, 0.3, 0), height = Map3DTrains.carHeight - 0.3
        for car in cars {
            let length = (car.front - car.back).length
            guard length > 1 else { continue }
            let middle = (car.front + car.back) * 0.5 + base, forward = car.front - car.back
            let rim = seen(railColour, carOpacity)
            mesh.addBox(base: middle - Map3DPoint(0, Self.rim, 0), forward: forward, length: length + 2 * Self.rim,
                        width: Map3DTrains.carWidth + 2 * Self.rim, height: height + 2 * Self.rim, top: rim, side: rim, shaded: false)
            let colour = seen(car.colour, carOpacity)
            mesh.addBox(base: middle, forward: forward, length: length, width: Map3DTrains.carWidth, height: height,
                        top: colour, side: colour, capped: false)
            guard let along = Map3DPoint(forward.x, 0, forward.z).normalized else { continue }
            let f = along * (length / 2), r = Map3DPoint(-along.z, 0, along.x) * (Map3DTrains.carWidth / 2)
            let top = middle + Map3DPoint(0, height, 0)
            mesh.addQuad(top + f - r, top - f - r, top - f + r, top + f + r, color: colour)
        }
    }
}
