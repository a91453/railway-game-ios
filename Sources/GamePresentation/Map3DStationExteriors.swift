import Foundation
import GameCore

// Decision 625: the eleven exterior studies of #1904
// (`Map3DStationExteriorBatch1`) on the 3D map. On a real-world map, a
// station of the game built as one of their stations' recipes
// (decision 321) whose platforms lie at the real station has the study
// stood where OpenStreetMap has the real buildings, turned as they are,
// instead of the kit's building beside its platforms; so does any other
// station of the game whose platforms lie within it (Liujia beside HSR
// Hsinchu, Xinwuri beside HSR Taichung). The real buildings stand round
// real track, and the game's track and platforms need not lie where the
// real ones do or as high: every part of the study that comes within a
// train's room of the track or a platform's of a platform is left out,
// then every part left standing on nothing, so nothing goes through a
// train or hangs in the air. When less than half the study is left it is
// not stood there at all, and the kit's building is, as before. Only
// drawing: which station stands where is GameCore's.

extension Map3DStationExteriorBatch1 {
    /// The study for a station of the kit's `profile`: the kit gives each of
    /// the eleven stations (and those built with them) a profile of its own.
    static func study(for profile: Map3DStationKit.Profile) -> Station? {
        switch profile {
        case .taichung: .taichungTRA
        case .hsinchu: .hsinchuTRA
        case .hualien: .hualienTRA
        case .taitung: .taitungTRA
        case .banqiao: .banqiaoTRA
        case .nangang: .nangangTRA
        case .hsrTaoyuan: .taoyuanHSR
        case .hsrHsinchu: .hsinchuHSR
        case .hsrTaichung: .taichungHSR
        case .hsrTainan: .tainanHSR
        case .zuoying: .zuoyingHSR
        default: nil
        }
    }

    /// The point (degrees north, east) the study's metres are measured
    /// from, as each outline's comment above gives it.
    static func origin(of station: Station) -> (latitude: Double, longitude: Double) {
        switch station {
        case .taichungTRA: (24.13732601, 120.68671829)
        case .hsinchuTRA: (24.80160443, 120.97165154)
        case .hualienTRA: (23.992764, 121.60093265)
        case .taitungTRA: (22.79349185, 121.12276045)
        case .banqiaoTRA: (25.0144511, 121.4640451)
        case .nangangTRA: (25.0528905, 121.60664345)
        case .taoyuanHSR: (25.01347985, 121.214539)
        case .hsinchuHSR: (24.8083231, 121.04001555)
        case .taichungHSR: (24.1112536, 120.61474665)
        case .tainanHSR: (22.92464555, 120.28626105)
        case .zuoyingHSR: (22.68726485, 120.3074864)
        }
    }

    /// The study's OpenStreetMap outlines, metres east and north of
    /// ``origin(of:)``.
    static func outlines(of station: Station) -> [[(Float, Float)]] {
        switch station {
        case .taichungTRA: [mainFootprint, oldFootprint]
        case .hsinchuTRA: [hsinchuFootprint]
        case .hualienTRA: [frontHallFootprint, rearHallFootprint, ticketHallFootprint, crossHallFootprint, welcomeUmbrellaFootprint,
                           platformNorthFootprint, platformMiddleFootprint, platformSouthFootprint]
        case .taitungTRA: [taitungHallFootprint, taitungPlatformAFootprint, taitungPlatformBFootprint, taitungPlatformCFootprint,
                           taitungPorticoFootprint]
        case .banqiaoTRA: [banqiaoMainFootprint, banqiaoCircularLineFootprint, banqiaoTowerSouthFootprint, banqiaoTowerNorthFootprint]
        case .nangangTRA: [nangangMainFootprint, nangangBlockCFootprint, nangangBlockBFootprint, nangangEastFootprint, nangangBlockAFootprint]
        case .taoyuanHSR: [taoyuanHSRFootprint, taoyuanA18Footprint]
        case .hsinchuHSR: [hsinchuHSRFootprint, liujiaFootprint]
        case .taichungHSR: [xinwuriFootprint, taichungHSRFootprint, taichungLinkEWFootprint, taichungLinkNSFootprint, taichungMRTFootprint]
        case .tainanHSR: [tainanHSRFootprint, tainanPlatformWestFootprint, tainanPlatformEastFootprint, shalunFootprint]
        case .zuoyingHSR: [zuoyingHSRFootprint, xinzuoyingFootprint]
        }
    }

    /// The study turned into the scene's axes (x east, y up, z south) about
    /// its origin: north mirrored to south, each triangle's turn and normal
    /// with it, so it still faces out.
    ///
    /// Decision 625 續: its glass walls (``nightGlassColours(for:)``) as
    /// the landmarks' curtain glass (``Map3DVertex/curtainGlass``), `u`
    /// metres along the wall and `v` metres up: mullions and floors by
    /// day, one bay in three lit after dark as the city's windows are (a
    /// glass wall glowing in its own pale colour was too faint to read).
    static func sceneMesh(for station: Station, detail: LevelOfDetail) -> Map3DMesh {
        let study = mesh(for: station, detail: detail)
        let glass = nightGlassColours(for: station)
        let vertices = study.vertices.map { v in
            let position = Map3DPoint(v.x, v.y, -v.z), normal = Map3DPoint(v.nx, v.ny, -v.nz)
            guard v.layer == Map3DVertex.glowing, glass.contains(v.color), let along = Map3DPoint(-normal.z, 0, normal.x).normalized else {
                return Map3DVertex(position, normal: normal, color: v.color, u: v.u, v: v.v, layer: v.layer)
            }
            return Map3DVertex(position, normal: normal, color: v.color, u: position.dot(along), v: position.y, layer: Map3DVertex.curtainGlass)
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(study.indices.count)
        for start in stride(from: 0, to: study.indices.count, by: 3) {
            indices += [study.indices[start], study.indices[start + 2], study.indices[start + 1]]
        }
        return Map3DMesh(vertices: vertices, indices: indices)
    }
}

/// Decision 665: a real station's exterior study of either batch, the
/// first (decision 625, #1904) or the second (decision 626, #1938), as the
/// scene stands it (``Map3DScene/Builder/addStationExteriors(_:frame:)``).
enum Map3DExteriorStudy: Hashable, Sendable, CaseIterable {
    case batch1(Map3DStationExteriorBatch1.Station)
    case batch2(Map3DStationExteriorBatch2.Station)

    typealias LevelOfDetail = Map3DStationExteriorBatch1.LevelOfDetail

    static let allCases: [Self] = Map3DStationExteriorBatch1.Station.allCases.map(Self.batch1)
        + Map3DStationExteriorBatch2.Station.allCases.map(Self.batch2)

    var rawValue: String {
        switch self {
        case .batch1(let station): station.rawValue
        case .batch2(let station): "b2-" + station.rawValue
        }
    }

    /// The study for a station of the kit's `profile`: the first batch's
    /// eleven, and the second batch's Keelung, Chiayi and Tainan (the kit
    /// gives them a profile of their own). The forest and sugar railways'
    /// stations share the kit's timber and halt profiles with many
    /// others, so they stand for a station only whose platforms lie
    /// within them.
    static func study(for profile: Map3DStationKit.Profile) -> Self? {
        if let station = Map3DStationExteriorBatch1.study(for: profile) { return .batch1(station) }
        switch profile {
        case .keelung: return .batch2(.keelung)
        case .chiayi: return .batch2(.chiayi)
        case .tainan: return .batch2(.tainan)
        default: return nil
        }
    }

    /// The point (degrees north, east) the study's metres are measured
    /// from.
    var origin: (latitude: Double, longitude: Double) {
        switch self {
        case .batch1(let station): return Map3DStationExteriorBatch1.origin(of: station)
        case .batch2(let station):
            // The second batch keeps (longitude, latitude).
            let (longitude, latitude) = Map3DStationExteriorBatch2.origin(of: station)
            return (latitude, longitude)
        }
    }

    /// The outlines the study stands on, metres east and north of
    /// ``origin``: OpenStreetMap's buildings. For Tainan, not the new
    /// underground station's outline (530 m long, under the ground);
    /// for Wushulin and Xihu, where OpenStreetMap has only the station's
    /// node, the rectangle round the study.
    var outlines: [[(Float, Float)]] {
        switch self {
        case .batch1(let station): return Map3DStationExteriorBatch1.outlines(of: station)
        case .batch2(let station):
            typealias B = Map3DStationExteriorBatch2
            switch station {
            case .keelung: return [B.way929730121, B.way1069178919, B.way367861777]
            case .chiayi: return [B.way286891391]
            case .tainan: return [B.way204493488, B.way204493489, B.way1568887226]
            case .beimen: return [B.way353120128]
            case .fenqihu: return [B.way444296747]
            case .alishan: return [B.way344586161]
            case .qiaotou: return [B.way112644875]
            case .wushulin: return [Self.wushulinOutline]
            case .xihu: return [Self.xihuOutline]
            }
        }
    }

    private static let wushulinOutline = rectangle(round: .wushulin)
    private static let xihuOutline = rectangle(round: .xihu)

    /// The rectangle round the far study of `station`, on the ground.
    private static func rectangle(round station: Map3DStationExteriorBatch2.Station) -> [(Float, Float)] {
        guard let bounds = Map3DStationExteriorBatch2.mesh(for: station, detail: .far).bounds else { return [] }
        return [(bounds.min.x, bounds.min.z), (bounds.max.x, bounds.min.z), (bounds.max.x, bounds.max.z), (bounds.min.x, bounds.max.z)]
    }

    /// The study in its own metres, as it is drawn before it is turned.
    func mesh(detail: LevelOfDetail) -> Map3DMesh {
        switch self {
        case .batch1(let station): Map3DStationExteriorBatch1.mesh(for: station, detail: detail)
        case .batch2(let station): Map3DStationExteriorBatch2.mesh(for: station, detail: detail == .near ? .near : .far)
        }
    }

    /// The study in the scene's axes about its origin
    /// (``Map3DStationExteriorBatch1/sceneMesh(for:detail:)``). The second
    /// batch's windows are small panes, each lit warm after dark
    /// (``Map3DVertex/floodlit``) rather than one bay in three of a
    /// curtain wall; their tops and bottoms, which no one sees lit, plain.
    func sceneMesh(detail: LevelOfDetail) -> Map3DMesh {
        switch self {
        case .batch1(let station): return Map3DStationExteriorBatch1.sceneMesh(for: station, detail: detail)
        case .batch2:
            let study = mesh(detail: detail)
            let vertices = study.vertices.map { v in
                let position = Map3DPoint(v.x, v.y, -v.z), normal = Map3DPoint(v.nx, v.ny, -v.nz)
                let layer = v.layer != Map3DVertex.glowing ? v.layer : abs(normal.y) < 0.55 ? Map3DVertex.floodlit : Map3DVertex.plain
                return Map3DVertex(position, normal: normal, color: v.color, u: v.u, v: v.v, layer: layer)
            }
            var indices: [UInt32] = []
            indices.reserveCapacity(study.indices.count)
            for start in stride(from: 0, to: study.indices.count, by: 3) {
                indices += [study.indices[start], study.indices[start + 2], study.indices[start + 1]]
            }
            return Map3DMesh(vertices: vertices, indices: indices)
        }
    }
}

/// Decision 625: a study stood in the scene.
struct Map3DStationExterior: Sendable {
    let station: Map3DExteriorStudy
    /// The study's origin in the scene, at the ground it stands on.
    let origin: Map3DPoint
    /// Its outlines in the scene, on the ground.
    let outlines: [[Map3DPoint]]
    /// How much of the near and far study is left, by triangles (0–1).
    let kept: (near: Float, far: Float)
    /// What stood, close up and from afar, in the scene.
    let near: Map3DMesh
    let far: Map3DMesh

    /// Whether `point` (on the ground) is within `margin` metres of an
    /// outline or inside one.
    func covers(_ point: Map3DPoint, margin: Float) -> Bool {
        outlines.contains { Self.distance(from: point, to: $0) <= margin }
    }

    /// How far `point` is from the polygon `outline`, across the ground;
    /// 0 inside it.
    static func distance(from point: Map3DPoint, to outline: [Map3DPoint]) -> Float {
        var inside = false, nearest = Float.infinity
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            if (a.z > point.z) != (b.z > point.z), point.x < (b.x - a.x) * (point.z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
            let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z), ap = Map3DPoint(point.x - a.x, 0, point.z - a.z)
            let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
            nearest = min(nearest, (ap - ab * share).length)
        }
        return inside ? 0 : nearest
    }

    /// The smallest rectangle round `outline` (on the ground), its corners
    /// in turn: a station building's footprint as the streets and the
    /// commercial kit keep clear of.
    static func rectangle(round outline: [Map3DPoint]) -> [Map3DPoint] {
        var best: (area: Float, corners: [Map3DPoint])?
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            guard let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized else { continue }
            let across = Map3DPoint(-along.z, 0, along.x)
            let u = outline.map { ($0 - a).dot(along) }, v = outline.map { ($0 - a).dot(across) }
            let (u0, u1, v0, v1) = (u.min()!, u.max()!, v.min()!, v.max()!)
            let area = (u1 - u0) * (v1 - v0)
            if best == nil || area < best!.area {
                best = (area, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)].map { a + along * $0.0 + across * $0.1 })
            }
        }
        return best?.corners ?? outline
    }
}

/// Decision 625: the room the game's trains and platforms need, which no
/// part of a study may come into.
struct Map3DTrainRoom {
    /// A stretch of room along a line at the rails' (or a platform
    /// edge's line's) height: `half` metres either side across the
    /// ground, from `below` under it to `above` over it.
    struct Stretch {
        let a: Map3DPoint, b: Map3DPoint
        let half: Float, below: Float, above: Float
    }

    /// Either side of a track's middle: a car's half width (1.7 m) and an
    /// overhead line's mast beside it.
    static let trackHalf: Float = 3.2
    /// Over the rails: a car, its pantograph and the wire (decision 326's
    /// wire at about 5.5 m).
    static let trackAbove: Float = 6.5
    /// Over a platform: people and the game's own canopy over it.
    static let platformAbove: Float = 6
    /// How high over the station's ground the rails are on a viaduct, all
    /// under them kept clear (the deck and its piers).
    static let raised: Float = 2.5

    private(set) var stretches: [Stretch] = []
    private var cells: [Int64: [Int]] = [:]
    static let cell: Float = 16

    private static func key(_ x: Int, _ z: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(z))) }

    /// Room along `line` at the rails' height, the station's ground at
    /// `ground`: under it too where it runs `raised` over that.
    mutating func add(line: [Map3DPoint], half: Float, above: Float, ground: Float) {
        // In long straight stretches, a few centimetres off the line: the
        // track is drawn every metre or two, and each stretch cuts.
        let line = Self.simplified(line, within: 0.1)
        for (a, b) in zip(line, line.dropFirst()) {
            let below = min(a.y, b.y) - ground > Self.raised ? max(a.y, b.y) - ground + 1 : 0.3
            let index = stretches.count
            stretches.append(Stretch(a: a, b: b, half: half, below: below, above: above))
            let reach = half + 1
            let x0 = Int(((min(a.x, b.x) - reach) / Self.cell).rounded(.down)), x1 = Int(((max(a.x, b.x) + reach) / Self.cell).rounded(.down))
            let z0 = Int(((min(a.z, b.z) - reach) / Self.cell).rounded(.down)), z1 = Int(((max(a.z, b.z) + reach) / Self.cell).rounded(.down))
            guard x1 - x0 < 64, z1 - z0 < 64 else { continue }
            for x in x0...x1 { for z in z0...z1 { cells[Self.key(x, z), default: []].append(index) } }
        }
    }

    /// `line` with the points left out that lie within `tolerance` metres
    /// of the line between those kept either side (Douglas–Peucker).
    static func simplified(_ line: [Map3DPoint], within tolerance: Float) -> [Map3DPoint] {
        guard line.count > 2 else { return line }
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true; keep[line.count - 1] = true
        var spans = [(0, line.count - 1)]
        while let (first, last) = spans.popLast() {
            guard last > first + 1 else { continue }
            let a = line[first], ab = line[last] - a, length = max(ab.dot(ab), 1e-8)
            var farthest = first, distance: Float = 0
            for i in (first + 1)..<last {
                let ap = line[i] - a, share = min(max(ab.dot(ap) / length, 0), 1)
                let off = (ap - ab * share).length
                if off > distance { distance = off; farthest = i }
            }
            if distance > tolerance {
                keep[farthest] = true
                spans.append((first, farthest)); spans.append((farthest, last))
            }
        }
        return line.indices.filter { keep[$0] }.map { line[$0] }
    }

    /// Whether `point` is in the room.
    func contains(_ point: Map3DPoint) -> Bool {
        let key = Self.key(Int((point.x / Self.cell).rounded(.down)), Int((point.z / Self.cell).rounded(.down)))
        guard let indices = cells[key] else { return false }
        return indices.contains { index in
            let s = stretches[index]
            let ab = Map3DPoint(s.b.x - s.a.x, 0, s.b.z - s.a.z), ap = Map3DPoint(point.x - s.a.x, 0, point.z - s.a.z)
            let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
            guard (ap - ab * share).length < s.half else { return false }
            let rails = s.a.y + (s.b.y - s.a.y) * share
            return point.y > rails - s.below && point.y < rails + s.above
        }
    }

    /// What of the convex polygon `polygon` is out of the room, as convex
    /// polygons: cut by each stretch it reaches, across the ground either
    /// side of the stretch's middle (and `half` past its ends, so a bend
    /// leaves no gap), then over and under it.
    /// A piece of a polygon out of the room: `over`, the way along the
    /// track (on the ground) when it lies over the room.
    struct Piece {
        var polygon: [Map3DVertex]
        var over: Map3DPoint?
    }

    func outside(_ polygon: [Map3DVertex]) -> [Piece] {
        let xs = polygon.map(\.x), zs = polygon.map(\.z)
        let x0 = Int((xs.min()! / Self.cell).rounded(.down)), x1 = Int((xs.max()! / Self.cell).rounded(.down))
        let z0 = Int((zs.min()! / Self.cell).rounded(.down)), z1 = Int((zs.max()! / Self.cell).rounded(.down))
        var near = Set<Int>()
        for x in x0...x1 { for z in z0...z1 { near.formUnion(cells[Self.key(x, z)] ?? []) } }
        var pending = [Piece(polygon: polygon, over: nil)]
        // In an order of their own places, not of how the lines were
        // listed, so the same track cuts the same pieces.
        let order = near.sorted { i, j in
            let a = stretches[i], b = stretches[j]
            return (a.a.x, a.a.z, a.b.x, a.b.z, a.half) < (b.a.x, b.a.z, b.b.x, b.b.z, b.half)
        }
        for index in order {
            pending = pending.flatMap { Self.outside($0, stretches[index]) }
            if pending.isEmpty { break }
        }
        return pending
    }

    /// What of `polygon` is out of the one stretch `s`.
    private static func outside(_ piece: Piece, _ s: Stretch) -> [Piece] {
        let polygon = piece.polygon
        let flat = Map3DPoint(s.b.x - s.a.x, 0, s.b.z - s.a.z), length = flat.length
        guard length > 1e-4 else { return [piece] }
        let along = flat * (1 / length), across = Map3DPoint(-along.z, 0, along.x)
        func t(_ v: Map3DVertex) -> Float { along.dot(Map3DPoint(v.x - s.a.x, 0, v.z - s.a.z)) }
        func d(_ v: Map3DVertex) -> Float { across.dot(Map3DPoint(v.x - s.a.x, 0, v.z - s.a.z)) }
        let reach = s.half
        // Wholly to one side: as it is.
        if polygon.allSatisfy({ d($0) >= s.half }) || polygon.allSatisfy({ d($0) <= -s.half })
            || polygon.allSatisfy({ t($0) <= -reach }) || polygon.allSatisfy({ t($0) >= length + reach }) {
            return [piece]
        }
        // Linear in the vertex: the rails' height along the stretch is,
        // within it, so the planes over and under it are planes.
        func railsLinear(_ v: Map3DVertex) -> Float { s.a.y + (s.b.y - s.a.y) * (t(v) / length) }
        // Nothing of it in this stretch's room or over it: as it is, not
        // cut up.
        var inside = polygon
        for plane in [{ (v: Map3DVertex) in -d(v) - s.half }, { d($0) - s.half }, { -t($0) - reach }, { t($0) - length - reach },
                      { railsLinear($0) - s.below - $0.y }] as [(Map3DVertex) -> Float] {
            inside = cut(inside, by: plane).0
            if inside.count < 3 { return [piece] }
        }
        var kept: [[Map3DVertex]] = []
        let (left, rest) = cut(polygon) { d($0) + s.half }
        kept.append(left)
        let (middle, right) = cut(rest) { d($0) - s.half }
        kept.append(right)
        let (before, rest2) = cut(middle) { t($0) + reach }
        kept.append(before)
        let (within, after) = cut(rest2) { t($0) - length - reach }
        kept.append(after)
        let (under, high) = cut(within) { $0.y - railsLinear($0) - s.above }
        let (low, _) = cut(under) { $0.y - railsLinear($0) + s.below }
        kept.append(low)
        return kept.filter { $0.count >= 3 }.map { Piece(polygon: $0, over: piece.over) }
            + (high.count >= 3 ? [Piece(polygon: high, over: piece.over ?? along)] : [])
    }

    /// Decision 625 續: a roof over the track only as its frame, a rib
    /// ``frameWidth`` wide every ``frameSpacing`` metres along the track
    /// (``Map3DStationExterior/carved(_:clearOf:ground:)``).
    static let frameSpacing: Float = 16
    static let frameWidth: Float = 1
    /// From afar, every other rib (the far study's budget).
    static let farFrameSpacing: Float = 32

    /// The ribs of `polygon`, each where a multiple of ``frameSpacing``
    /// metres along `along` (from the scene's origin, either way, so
    /// tracks side by side cut the same ribs) lies within half
    /// ``frameWidth``.
    static func frame(_ polygon: [Map3DVertex], along: Map3DPoint, spacing frameSpacing: Float = frameSpacing) -> [[Map3DVertex]] {
        guard polygon.count >= 3 else { return [] }
        func t(_ v: Map3DVertex) -> Float { along.x * v.x + along.z * v.z }
        let ts = polygon.map(t), half = frameWidth / 2
        let first = Int(((ts.min()! - half) / frameSpacing).rounded(.up)), last = Int(((ts.max()! + half) / frameSpacing).rounded(.down))
        guard first <= last else { return [] }
        return (first...last).map { k in
            let middle = Float(k) * frameSpacing
            let (from, _) = cut(polygon) { middle - half - t($0) }
            return cut(from) { t($0) - middle - half }.0
        }
    }

    /// `polygon` cut by the plane `f = 0` (`f` linear in the vertex's
    /// place): the part where `f ≤ 0`, then where `f ≥ 0`.
    private static func cut(_ polygon: [Map3DVertex], by f: (Map3DVertex) -> Float) -> ([Map3DVertex], [Map3DVertex]) {
        guard polygon.count >= 3 else { return ([], []) }
        let values = polygon.map(f)
        if values.allSatisfy({ $0 <= 0 }) { return (polygon, []) }
        if values.allSatisfy({ $0 >= 0 }) { return ([], polygon) }
        var negative: [Map3DVertex] = [], positive: [Map3DVertex] = []
        for i in polygon.indices {
            let j = (i + 1) % polygon.count
            let (a, b, fa, fb) = (polygon[i], polygon[j], values[i], values[j])
            if fa <= 0 { negative.append(a) }
            if fa >= 0 { positive.append(a) }
            if (fa < 0 && fb > 0) || (fa > 0 && fb < 0) {
                let share = fa / (fa - fb)
                var m = a
                m.x = a.x + (b.x - a.x) * share; m.y = a.y + (b.y - a.y) * share; m.z = a.z + (b.z - a.z) * share
                m.u = a.u + (b.u - a.u) * share; m.v = a.v + (b.v - a.v) * share
                negative.append(m); positive.append(m)
            }
        }
        return (negative, positive)
    }
}

extension Map3DStationExterior {
    /// `mesh` (in the scene) cut clear of `room`, without the parts then
    /// standing on nothing, and how much of it, by area, is left. A part
    /// is a run of triangles sharing corners (a box, a roof); a triangle
    /// that comes into the room is cut along the room's sides, top and
    /// bottom and what is in it left out
    /// (``Map3DTrainRoom/outside(_:)``), so a wall stops either side of a
    /// track and a roof over it stays. A part stands when
    /// its foot is within 0.6 m of `ground` or its bounds are within 0.6 m
    /// of a part that stands.
    static func carved(_ mesh: Map3DMesh, clearOf room: Map3DTrainRoom, ground: Float,
                       frameSpacing: Float = Map3DTrainRoom.frameSpacing) -> (mesh: Map3DMesh, kept: Float) {
        let count = mesh.triangleCount
        guard count > 0 else { return (mesh, 1) }
        // The parts: triangles joined through corners at the same place.
        var parent = Array(0..<count)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        struct Corner: Hashable { let x: Int32, y: Int32, z: Int32 }
        var owner: [Corner: Int] = [:]
        let points = mesh.vertices.map(\.position)
        for triangle in 0..<count {
            for k in 0..<3 {
                let p = points[Int(mesh.indices[triangle * 3 + k])]
                let corner = Corner(x: Int32((p.x * 100).rounded()), y: Int32((p.y * 100).rounded()), z: Int32((p.z * 100).rounded()))
                if let other = owner[corner] {
                    let (r1, r2) = (root(other), root(triangle))
                    if r1 != r2 { parent[r1] = r2 }
                } else {
                    owner[corner] = triangle
                }
            }
        }
        var parts: [Int: Int] = [:], members: [[Int]] = []
        for triangle in 0..<count {
            let r = root(triangle)
            if parts[r] == nil { parts[r] = members.count; members.append([]) }
            members[parts[r]!].append(triangle)
        }
        func area(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint) -> Float { (b - a).cross(c - a).length / 2 }
        func polygonArea(_ p: [Map3DVertex]) -> Float {
            (1..<(p.count - 1)).reduce(0) { $0 + area(p[0].position, p[$1].position, p[$1 + 1].position) }
        }
        // The pieces of a polygon as triangles, the winding kept; none
        // thinner than a centimetre (slivers the cuts leave, drawn as
        // stray fins).
        func triangles(_ polygon: [Map3DVertex], into pieces: inout [(Map3DVertex, Map3DVertex, Map3DVertex)]) {
            for k in 1..<(polygon.count - 1) {
                let (a, b, c) = (polygon[0], polygon[k], polygon[k + 1])
                guard !Self.isSliver(a.position, b.position, c.position) else { continue }
                pieces.append((a, b, c))
            }
        }
        var total: Float = 0, framed: [Float?] = []
        var kept: [[(Map3DVertex, Map3DVertex, Map3DVertex)]] = []
        var low = [Map3DPoint](), high = [Map3DPoint]()
        for part in members {
            var pieces: [(Map3DVertex, Map3DVertex, Map3DVertex)] = []
            var cut: [Map3DTrainRoom.Piece] = []
            var partArea: Float = 0
            for triangle in part {
                let v = (0..<3).map { mesh.vertices[Int(mesh.indices[triangle * 3 + $0])] }
                partArea += area(v[0].position, v[1].position, v[2].position)
                cut += room.outside([v[0], v[1], v[2]])
            }
            total += partArea
            // Decision 625 續: a part whose share over the track and
            // platforms is ``framedShare`` or more (a station's roof over
            // its tracks) stands as its frame alone, ribs across the
            // track, so the trains and platforms under it show; its area
            // counts as left. Less (a hall's edge over a track or a
            // platform) is cut back to the room's side, so no solid
            // building hangs over the trains.
            let over = cut.filter { $0.over != nil }.map { ($0, polygonArea($0.polygon)) }
            if partArea > 0, let way = over.max(by: { $0.1 < $1.1 })?.0.over,
               over.reduce(0, { $0 + $1.1 }) >= Self.framedShare * partArea {
                framed.append(partArea)
                // Its faces seen from above only: the camera never looks
                // up at a roof's underside, and the ribs cost half as much.
                // Ribs of its own triangles, then clear of the room (a rib
                // is cut only across), not of the many pieces the room cut.
                for triangle in part {
                    let v = (0..<3).map { mesh.vertices[Int(mesh.indices[triangle * 3 + $0])] }
                    guard v[0].ny > -0.3 else { continue }
                    for rib in Map3DTrainRoom.frame(v, along: way, spacing: frameSpacing) where rib.count >= 3 {
                        for piece in room.outside(rib) { triangles(piece.polygon, into: &pieces) }
                    }
                }
            } else {
                framed.append(nil)
                for piece in cut where piece.over == nil { triangles(piece.polygon, into: &pieces) }
            }
            // Whether it stands is asked of what is drawn, but of a frame
            // the whole roof's bounds (a rib between posts still rests
            // on them).
            var lo = Map3DPoint(.infinity, .infinity, .infinity), hi = Map3DPoint(-.infinity, -.infinity, -.infinity)
            let bounding = framed.last! == nil ? pieces.map { [$0.0.position, $0.1.position, $0.2.position] }
                : (pieces.isEmpty ? [] : part.map { t in (0..<3).map { points[Int(mesh.indices[t * 3 + $0])] } })
            for corners in bounding {
                for p in corners {
                    lo = Map3DPoint(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                    hi = Map3DPoint(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
                }
            }
            kept.append(pieces); low.append(lo); high.append(hi)
        }
        // Standing: from the ground up, through parts that meet.
        let touch: Float = 0.6
        var stands = kept.indices.map { !kept[$0].isEmpty && low[$0].y <= ground + touch }
        var changed = true
        while changed {
            changed = false
            for i in kept.indices where !kept[i].isEmpty && !stands[i] {
                let meets = kept.indices.contains { j in
                    stands[j] && low[i].x <= high[j].x + touch && low[j].x <= high[i].x + touch
                        && low[i].y <= high[j].y + touch && low[j].y <= high[i].y + touch
                        && low[i].z <= high[j].z + touch && low[j].z <= high[i].z + touch
                }
                if meets { stands[i] = true; changed = true }
            }
        }
        var vertices: [Map3DVertex] = [], indices: [UInt32] = [], left: Float = 0
        for (index, pieces) in kept.enumerated() where stands[index] {
            if let whole = framed[index] { left += whole }
            for piece in pieces {
                for vertex in [piece.0, piece.1, piece.2] {
                    indices.append(UInt32(vertices.count))
                    vertices.append(vertex)
                }
                if framed[index] == nil { left += area(piece.0.position, piece.1.position, piece.2.position) }
            }
        }
        return (Map3DMesh(vertices: vertices, indices: indices), total > 0 ? min(left / total, 1) : 1)
    }

    /// Decision 625 續: the share of a part over the room from which it
    /// stands as its frame.
    static let framedShare: Float = 0.25

    /// Whether the triangle is a sliver: thinner than a centimetre across
    /// its longest side, or of no area.
    static func isSliver(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint) -> Bool {
        let doubled = (b - a).cross(c - a).length
        let longest = max((b - a).length, (c - b).length, (a - c).length)
        return doubled < 1e-5 || doubled / max(longest, 1e-6) < 0.01
    }
}

extension Map3DRealTrains {
    /// Decision 625: each lane of the real lines' track drawn, in runs
    /// where a car shows (not in a tunnel), and each path of their trains'
    /// assignment the same way.
    var shownLanes: [[Map3DPoint]] {
        var runs: [[Map3DPoint]] = []
        func add(_ points: [Map3DPoint?], _ shown: [Bool]) {
            var run: [Map3DPoint] = []
            for (point, show) in zip(points, shown) {
                if let point, show { run.append(point) } else {
                    if run.count > 1 { runs.append(run) }
                    run = []
                }
            }
            if run.count > 1 { runs.append(run) }
        }
        for track in tracks.joined() {
            for (lane, shown) in zip(track.lanes, track.shown) { add(lane.map { Optional($0) }, shown) }
            for route in track.routes.values { add(route.points, route.shown) }
        }
        return runs
    }
}

extension Map3DScene.Builder {
    /// Decision 625: less than this share of a study left clear of the
    /// track, and it does not stand (the kit's building stands instead).
    static let exteriorLeast: Float = 0.5
    /// How near, in metres, a station's platforms' middle must be to a
    /// study that stands for it to draw no building or entrances of its
    /// own (the study has them).
    static let exteriorCovers: Float = 40

    /// Decision 625: as the landmarks (decision 370), each study whose
    /// origin is in the scene, where OpenStreetMap has it, cut clear of
    /// the track and platforms; the cells under its outlines, on which no
    /// real building, footprint, temple, scene or city lot stands.
    mutating func addStationExteriors(_ snapshot: RailwaySnapshot, frame: RealWorldFrame) -> [Map3DExteriorStudy: Set<Map3DScene.ChunkKey>] {
        var built: [Map3DExteriorStudy: Set<Map3DScene.ChunkKey>] = [:]
        for station in Map3DExteriorStudy.allCases {
            let origin = station.origin
            let place = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
            guard contains(x: place.x, y: place.y), let placed = addStationExterior(station, snapshot: snapshot, frame: frame) else { continue }
            stationExteriors.append(placed)
            built[station] = placed.outlines.reduce(into: Set<Map3DScene.ChunkKey>()) { $0.formUnion(cells(under: $1)) }
        }
        return built
    }

    /// The room `snapshot`'s track and platforms need within `box` (on
    /// the ground), the station's ground `ground` high, and the real
    /// lines' track drawn (decision 402). From the whole network, not the
    /// scene's own lines, so a block of chunks built apart (decision 358)
    /// keeps the same room as the whole scene.
    func trainRoom(_ snapshot: RailwaySnapshot, within box: (min: Map3DPoint, max: Map3DPoint), ground: Float) -> Map3DTrainRoom {
        var room = Map3DTrainRoom()
        // Each run of a line's segments that reach round the box: so what
        // the room is does not hang on how far the line runs on.
        func reaches(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool {
            max(a.x, b.x) > box.min.x - 20 && min(a.x, b.x) < box.max.x + 20 && max(a.z, b.z) > box.min.z - 20 && min(a.z, b.z) < box.max.z + 20
        }
        func runs(_ line: [Map3DPoint]) -> [[Map3DPoint]] {
            var runs: [[Map3DPoint]] = [], run: [Map3DPoint] = []
            for (a, b) in zip(line, line.dropFirst()) {
                if reaches(a, b) {
                    if run.isEmpty { run.append(a) }
                    run.append(b)
                } else if !run.isEmpty {
                    runs.append(run); run = []
                }
            }
            if run.count > 1 { runs.append(run) }
            return runs
        }
        for alignment in snapshot.edges {
            for span in alignment.edge.sectionSpans where span.end > span.start && span.kind != .tunnel {
                let line = sample(alignment.geometry, from: span.start, to: span.end).map { point($0) + Self.lifted }
                for run in runs(line) {
                    room.add(line: run, half: Map3DTrainRoom.trackHalf, above: Map3DTrainRoom.trackAbove, ground: ground)
                }
            }
        }
        for line in realTrackLines {
            for run in runs(line) {
                room.add(line: run, half: Map3DTrainRoom.trackHalf, above: Map3DTrainRoom.trackAbove, ground: ground)
            }
        }
        // A platform either side of its track, as wide as any is laid
        // (``addPlatforms(_:)``).
        for platform in snapshot.platforms where platform.structure != .tunnel && platform.points.count > 1 {
            let line = platform.points.map { point($0) + Self.lifted }
            for run in runs(line) {
                room.add(line: run, half: Self.highSpeedPlatformEdge + Self.platformWidth + 0.5, above: Map3DTrainRoom.platformAbove, ground: ground)
            }
        }
        return room
    }

    /// `station`'s outlines in the scene, on level ground.
    func sceneOutlines(of station: Map3DExteriorStudy, frame: RealWorldFrame) -> [[Map3DPoint]] {
        let origin = station.origin
        let place = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
        let centre = point(x: place.x, y: place.y, height: 0)
        return station.outlines.map { outline in
            outline.map { Map3DPoint(centre.x + $0.0, 0, centre.z - $0.1) }
        }
    }

    /// Decision 625: where `station`'s study stands in the scene, where
    /// OpenStreetMap has it, on the lowest ground under it; its outlines
    /// there, and the room the track and platforms need round it.
    mutating func exteriorPlace(_ station: Map3DExteriorStudy, snapshot: RailwaySnapshot, frame: RealWorldFrame)
        -> (origin: Map3DPoint, outlines: [[Map3DPoint]], ground: Float, room: Map3DTrainRoom) {
        let place = frame.worldPosition(latitude: station.origin.latitude, longitude: station.origin.longitude)
        let centre = point(x: place.x, y: place.y, height: 0)
        var outlines = sceneOutlines(of: station, frame: frame)
        // On the lowest ground under it, so no corner is in the air.
        let ground = outlines.flatMap { $0 }.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
        outlines = outlines.map { $0.map { Map3DPoint($0.x, ground, $0.z) } }
        let all = outlines.flatMap { $0 }
        let box = (min: Map3DPoint(all.map(\.x).min()!, 0, all.map(\.z).min()!), max: Map3DPoint(all.map(\.x).max()!, 0, all.map(\.z).max()!))
        return (Map3DPoint(centre.x, ground, centre.z), outlines, ground, trainRoom(snapshot, within: box, ground: ground))
    }

    /// `station`'s study at `origin`, cut clear of `room`.
    static func exteriorCarved(_ station: Map3DExteriorStudy, detail: Map3DExteriorStudy.LevelOfDetail,
                               at origin: Map3DPoint, clearOf room: Map3DTrainRoom) -> (mesh: Map3DMesh, kept: Float) {
        var placed = Map3DMesh()
        placed.append(station.sceneMesh(detail: detail), at: origin, forward: Map3DPoint(1, 0, 0))
        return Map3DStationExterior.carved(placed, clearOf: room, ground: origin.y,
                                           frameSpacing: detail == .near ? Map3DTrainRoom.frameSpacing : Map3DTrainRoom.farFrameSpacing)
    }

    /// Whether `station`'s study stands (``addStationExterior(_:snapshot:frame:)``),
    /// asked without drawing it, by a block of chunks without its origin.
    mutating func exteriorStands(_ station: Map3DExteriorStudy, snapshot: RailwaySnapshot, frame: RealWorldFrame) -> Bool {
        let place = exteriorPlace(station, snapshot: snapshot, frame: frame)
        return Self.exteriorCarved(station, detail: .near, at: place.origin, clearOf: place.room).kept >= Self.exteriorLeast
    }

    /// Decision 625: `station`'s study where OpenStreetMap has it, if at
    /// least ``exteriorLeast`` of it is clear of the track and platforms;
    /// close by the near study, from afar the far one, each cut clear the
    /// same way. `nil` when it does not stand.
    mutating func addStationExterior(_ station: Map3DExteriorStudy, snapshot: RailwaySnapshot,
                                     frame: RealWorldFrame) -> Map3DStationExterior? {
        let (origin, outlines, _, room) = exteriorPlace(station, snapshot: snapshot, frame: frame)
        let near = Self.exteriorCarved(station, detail: .near, at: origin, clearOf: room)
        guard near.kept >= Self.exteriorLeast else { return nil }
        let far = Self.exteriorCarved(station, detail: .far, at: origin, clearOf: room)
        // In the chunk of its origin, as a landmark's: the one block of
        // chunks built apart that holds the origin draws it. Decision 625
        // 續: in its own colours, added after the look (the look's pale
        // version left the glass bands, the brick and the coloured
        // fascias all near white).
        // Its outlines' edges in the ground's colour stay the ground's,
        // in the look as the ground round them is.
        func grounded(_ mesh: Map3DMesh) -> Map3DMesh {
            var mesh = mesh
            let ground = Map3DPalette.ground, looked = Map3DLook.colour(Map3DPalette.ground)
            mesh.restyleVertices { if $0.color == ground { $0.color = looked } }
            return mesh
        }
        let (nearMesh, farMesh) = (grounded(near.mesh), grounded(far.mesh))
        let key = key(of: origin)
        if !isCoarse(key) { ownColourNear[key, default: Map3DMesh()].append(nearMesh) }
        ownColourFar[key, default: Map3DMesh()].append(farMesh)
        // No shadow under it: its parts left out over the track would
        // leave one there. The streets and the commercial kit keep off it.
        for outline in outlines { houseFootprints.append(Map3DStationExterior.rectangle(round: outline)) }
        return Map3DStationExterior(station: station, origin: origin, outlines: outlines, kept: (near.kept, far.kept),
                                    near: nearMesh, far: farMesh)
    }

    /// Decision 625 with decision 506's: an expanded station's wings
    /// beside `station`'s study, which stands for its building: the kit's
    /// wings (``StationKitBuilder/expansionWings(_:)``) at each end of the
    /// study's largest outline along its long side, their backs on its
    /// side nearer the track, cut clear of the track as the study is. The
    /// cells they stand on.
    mutating func addExpansionWings(_ expansion: StationExpansion, beside station: Map3DExteriorStudy,
                                    frame: RealWorldFrame, snapshot: RailwaySnapshot) -> Set<Map3DScene.ChunkKey> {
        let (_, outlines, ground, room) = exteriorPlace(station, snapshot: snapshot, frame: frame)
        let rectangles = outlines.map(Map3DStationExterior.rectangle(round:)).filter { $0.count == 4 }
        guard let largest = rectangles.max(by: { a, b in
            (a[1] - a[0]).length * (a[2] - a[1]).length < (b[1] - b[0]).length * (b[2] - b[1]).length
        }) else { return [] }
        // The rectangle's long side along the platforms (the kit's z), its
        // short side across (the kit's x), its back towards the track.
        var long = largest[1] - largest[0], short = largest[2] - largest[1]
        if long.length < short.length { swap(&long, &short) }
        let centre = largest.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * 0.25
        guard var forward = Map3DPoint(short.x, 0, short.z).normalized else { return [] }
        let nearest = room.stretches.min { a, b in
            ((a.a + a.b) * 0.5 - centre).length < ((b.a + b.b) * 0.5 - centre).length
        }
        if let nearest {
            let toTrack = (nearest.a + nearest.b) * 0.5 - centre
            if Map3DPoint(toTrack.x, 0, toTrack.z).dot(forward) > 0 { forward = forward * -1 }
        }
        var kit = StationKitBuilder()
        // A stand-in as big as the study's building, for the wings' size
        // and place, then left out.
        kit.box(short.length / 2, 0, 0, short.length, long.length, 0.01, Map3DPalette.plaza)
        let standIn = kit.mesh.triangleCount
        kit.expansionWings(expansion)
        let all = kit.mesh
        var wings = Map3DMesh()
        wings.append(Map3DMesh(vertices: Array(all.vertices), indices: Array(all.indices.dropFirst(standIn * 3))),
                     at: Map3DPoint(0, 0, 0), forward: Map3DPoint(1, 0, 0))
        let back = Map3DPoint(centre.x, ground, centre.z) - forward * (short.length / 2)
        var placed = Map3DMesh()
        placed.append(wings, at: back, forward: forward)
        let cut = Map3DStationExterior.carved(placed, clearOf: room, ground: ground)
        guard let bounds = cut.mesh.bounds else { return [] }
        let saved = target
        defer { target = saved }
        target = .near
        mesh(at: back) { $0.append(cut.mesh) }
        target = .far
        mesh(at: back) { $0.append(cut.mesh) }
        let corners = [Map3DPoint(bounds.min.x, 0, bounds.min.z), Map3DPoint(bounds.max.x, 0, bounds.min.z),
                       Map3DPoint(bounds.max.x, 0, bounds.max.z), Map3DPoint(bounds.min.x, 0, bounds.max.z)]
        return cells(under: corners)
    }
}
