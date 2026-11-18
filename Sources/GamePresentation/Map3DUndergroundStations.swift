import GameCore

// Decision 860: underground stations' platforms in the 3D map.
//
// Until now the scene drew no platform in a tunnel (`addPlatforms` left
// out `structure == .tunnel` since decision 359): a train followed into
// an underground station ran on through the round bore with nothing
// beside it, in Taipei, Kaohsiung, Hong Kong and Fukuoka alike. The
// see-through view (decision 672) laid them as flat bands only.
//
// Here each underground platform is laid where the see-through view lays
// it (decision 674's rule, ``lay(_:point:)``), drawn solid as a platform
// on the ground is (its slab, its lit edge, its props and screen doors,
// decision 436 and 847), and the round bore gives way, along the station,
// to a box: a flat floor, two walls with a yellow band, a dark ceiling
// with rows of lamps over the platforms, and at each end a head wall with
// the bores' openings. Down an island, the owner's old version's
// underground island module (``Map3DOldIslandModule``) every 40 m: its
// column, vending machine, benches, poster boards and hung signs. All of
// it in the base mesh, so the cab view deep in a tunnel (decision 394)
// still draws it.

/// Decision 860: the underground platforms and the station boxes round
/// them, in a scene's space, worked out once from the whole network so
/// every block of chunks agrees.
struct Map3DUndergroundStations: Sendable {
    /// An underground platform: its station and track, the centre line of
    /// that track at the rails' height, and how far across that line its
    /// middle stands (negative: to the line's left) and how wide it is.
    /// An island is laid as two halves, one from each track, as an island
    /// on the ground is (``Map3DScene/Builder/LaidPlatform``).
    struct Platform: Equatable, Sendable {
        let station: StationID
        let edge: TrackEdgeID
        let line: [Map3DPoint]
        let offset: Float
        let width: Float
        let island: Bool
    }

    /// A station's box: along `path` (its longest platform's line at the
    /// rails' height, run on past its platforms' ends), from `left` to
    /// `right` across it (metres, negative to the left), and where at its
    /// two ends tunnel tracks run on out of it (how far across).
    struct Box: Equatable, Sendable {
        let station: StationID
        let path: [Map3DPoint]
        let left: Float
        let right: Float
        /// The platforms in it (indices into ``platforms``).
        let platforms: [Int]
        /// How far across the path tracks leave its start and its end.
        var openings: (start: [Float], end: [Float]) = ([], [])

        static func == (a: Box, b: Box) -> Bool {
            a.station == b.station && a.path == b.path && a.left == b.left && a.right == b.right && a.platforms == b.platforms
                && a.openings.start == b.openings.start && a.openings.end == b.openings.end
        }
    }

    let platforms: [Platform]
    let boxes: [Box]

    /// None.
    init() {
        platforms = []
        boxes = []
    }

    // MARK: Sizes

    /// How far the box runs on past its platforms' ends, metres: room for
    /// the head wall clear of the platform's end.
    static let endRoom: Float = 4
    /// How far past a platform's back its wall stands.
    static let wallGap: Float = 0.3
    /// The ceiling, over the rails: the bore's crown, so the head wall
    /// meets the bores' openings without a step.
    static let ceiling: Float = Map3DScene.Builder.boreCrown
    /// The floor under the rails: the bore's.
    static let floor: Float = Map3DScene.Builder.boreFloor
    /// The walls' band of the canopy's blue, metres over the platform.
    static let bandFrom: Float = 2.4
    static let bandTo: Float = 2.9
    /// A lamp in the ceiling over each platform every so many metres, so
    /// long.
    static let lampEvery: Float = 6
    static let lampLength: Float = 2.4
    /// An island at least so wide has the old version's furniture.
    static let furnishedIsland: Float = 3
    /// How far up or down a tunnel track may run and still be one of the
    /// box's (cut out of its bore, or let through its head wall).
    static let sameLevel: Float = 3

    // MARK: Laying

    /// `snapshot`'s platforms in tunnels and their stations' boxes, `point`
    /// placing the world's points in the scene, the boxes' openings where
    /// `cover`'s tunnel pieces leave them.
    init(_ snapshot: RailwaySnapshot, point: (WorldCoordinate) -> Map3DPoint, cover: Map3DTrackCover) {
        let platforms = Self.lay(snapshot, point: point)
        var boxes = Self.boxes(platforms)
        for index in boxes.indices { boxes[index].openings = Self.openings(of: boxes[index], cover: cover) }
        self.platforms = platforms
        self.boxes = boxes
    }

    /// Decision 674's rule (``Map3DXRay/platforms(_:in:)``): each platform
    /// in a tunnel beside its track on its left, or, where another
    /// platform of the same station runs beside within 15 m at its level
    /// and the same way, far enough for one, an island halfway between the
    /// two; or on its right where only a track too near for an island
    /// runs on its left.
    static func lay(_ snapshot: RailwaySnapshot, point: (WorldCoordinate) -> Map3DPoint) -> [Platform] {
        let buried = snapshot.platforms.filter { $0.structure == .tunnel && $0.points.count > 1 }
        let lines = buried.map { $0.points.map { point($0) + Map3DScene.Builder.lifted } }
        let edge = Map3DScene.Builder.platformEdge
        var laid: [Platform] = []
        for (index, platform) in buried.enumerated() {
            let line = lines[index], middle = line[line.count / 2]
            let across = Map3DMesh.acrossDirections(line)[line.count / 2]
            let way = Map3DXRay.way(of: line)
            let beside = buried.indices
                .filter { $0 != index && buried[$0].platform.station == platform.platform.station }
                .filter { abs(lines[$0][lines[$0].count / 2].y - middle.y) <= Map3DXRay.sameLevel
                    && abs(Map3DXRay.way(of: lines[$0]).dot(way)) >= Map3DXRay.alongside }
                .map { (lines[$0][lines[$0].count / 2] - middle).dot(across) }
                .filter { abs($0) < 15 }
            let partner = beside
                .filter { abs($0) / 2 - edge >= Map3DScene.Builder.narrowestPlatform }
                .min { abs($0) < abs($1) }
            let station = platform.platform.station, track = platform.platform.edge
            if let partner {
                // Its half, from the edge by its track to the middle.
                let half = abs(partner) / 2 - edge, side: Float = partner >= 0 ? 1 : -1
                laid.append(Platform(station: station, edge: track, line: line, offset: side * (edge + half / 2), width: half, island: true))
            } else {
                let width = Map3DScene.Builder.platformWidth
                let side: Float = beside.contains { $0 < 0 } && !beside.contains { $0 > 0 } ? 1 : -1
                laid.append(Platform(station: station, edge: track, line: line, offset: side * (edge + width / 2), width: width, island: false))
            }
        }
        return laid
    }

    /// How far across one of a box's platforms another may lie and be in
    /// that box, metres (decision 867).
    static let besideReach: Float = 40

    /// One box for each station's platforms at one level that lie beside
    /// each other: along the longest of them, across from the outermost
    /// track's bore or platform's back to the other's. Decision 867: a
    /// station's platforms off the others' ends or further than
    /// ``besideReach`` across them have a box of their own (Fukuoka's
    /// Hakata, whose Nanakuma Line platforms are 160 m from the Kuko
    /// Line's, and Nakasu-Kawabata, whose Hakozaki Line platforms lie past
    /// the Kuko Line's ends): in one box along the longest they stood
    /// outside it, in the earth.
    static func boxes(_ platforms: [Platform]) -> [Box] {
        var groups: [[Int]] = []
        for index in platforms.indices {
            let here = platforms[index], middle = here.line[here.line.count / 2], level = middle.y
            if let group = groups.firstIndex(where: { group in
                let first = platforms[group[0]]
                return first.station == here.station && abs(first.line[first.line.count / 2].y - level) <= Map3DXRay.sameLevel
                    && group.contains { member in
                        locate(middle, along: platforms[member].line, beyond: endRoom).map { abs($0.across) <= besideReach } ?? false
                    }
            }) {
                groups[group].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups.compactMap { group in
            guard let longest = group.max(by: { length(platforms[$0].line) < length(platforms[$1].line) }) else { return nil }
            let spine = platforms[longest].line
            var left = Float.infinity, right = -Float.infinity, first = Float.infinity, last = -Float.infinity
            for index in group {
                let platform = platforms[index]
                for point in platform.line {
                    guard let at = locate(point, along: spine) else { continue }
                    first = min(first, at.along)
                    last = max(last, at.along)
                }
                guard let at = locate(platform.line[platform.line.count / 2], along: spine) else { continue }
                let bore = Map3DScene.Builder.boreHalfWidth
                left = min(left, at.across - bore, at.across + platform.offset - platform.width / 2 - wallGap)
                right = max(right, at.across + bore, at.across + platform.offset + platform.width / 2 + wallGap)
            }
            guard left < right, first < last else { return nil }
            let path = extend(spine, before: endRoom - first, after: last - length(spine) + endRoom)
            return Box(station: platforms[group[0]].station, path: path, left: left, right: right, platforms: group)
        }
    }

    /// How far across the box's path each tunnel track at its level leaves
    /// it at its start and at its end.
    static func openings(of box: Box, cover: Map3DTrackCover) -> (start: [Float], end: [Float]) {
        let total = length(box.path), level = box.path[box.path.count / 2].y
        var start: [Float] = [], end: [Float] = []
        for piece in cover.pieces where piece.isTunnel && abs(piece.a.y - level) <= sameLevel && abs(piece.b.y - level) <= sameLevel {
            guard let a = locate(piece.a, along: box.path, beyond: 60), let b = locate(piece.b, along: box.path, beyond: 60) else { continue }
            for (plane, list) in [(Float(0), 0), (total, 1)] where (a.along - plane) * (b.along - plane) <= 0 && a.along != b.along {
                let share = (plane - a.along) / (b.along - a.along)
                let across = a.across + (b.across - a.across) * share
                guard across > box.left, across < box.right else { continue }
                if list == 0 { start.append(across) } else { end.append(across) }
            }
        }
        func merged(_ list: [Float]) -> [Float] {
            list.sorted().reduce(into: [Float]()) { kept, across in
                if let previous = kept.last, across - previous < 0.5 { return }
                kept.append(across)
            }
        }
        return (merged(start), merged(end))
    }

    // MARK: Bores

    /// The pieces of `line` (a tunnel's track at the rails' height) that
    /// run outside every box: a bore along them; inside a box, none.
    func outside(_ original: [Map3DPoint]) -> [[Map3DPoint]] {
        guard !boxes.isEmpty, original.count > 1 else { return [original] }
        let near = boxes.filter { box in
            let level = box.path[box.path.count / 2].y
            return original.contains { abs($0.y - level) <= Self.sameLevel }
        }
        guard !near.isEmpty else { return [original] }
        func inside(_ point: Map3DPoint) -> Bool {
            near.contains { box in
                guard abs(point.y - box.path[box.path.count / 2].y) <= Self.sameLevel,
                      let at = Self.locate(point, along: box.path) else { return false }
                return at.across > box.left && at.across < box.right
            }
        }
        // Near a box, at most 2 m between points, so a straight piece
        // crossing it with both its ends outside is cut too.
        func nearBox(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool {
            near.contains { box in
                let pad = max(-box.left, box.right) + Self.endRoom
                let xs = box.path.map(\.x), zs = box.path.map(\.z)
                return max(a.x, b.x) >= xs.min()! - pad && min(a.x, b.x) <= xs.max()! + pad
                    && max(a.z, b.z) >= zs.min()! - pad && min(a.z, b.z) <= zs.max()! + pad
            }
        }
        var line = [original[0]]
        for (a, b) in zip(original, original.dropFirst()) {
            let steps = nearBox(a, b) ? max(1, Int((Map3DPoint(b.x - a.x, 0, b.z - a.z).length / 2).rounded(.up))) : 1
            for step in 1...steps { line.append(step == steps ? b : a + (b - a) * (Float(step) / Float(steps))) }
        }
        var pieces: [[Map3DPoint]] = [], current: [Map3DPoint] = []
        var wasInside = inside(line[0])
        if !wasInside { current.append(line[0]) }
        for index in 1..<line.count {
            let a = line[index - 1], b = line[index], isInside = inside(b)
            if isInside != wasInside {
                // Where it crosses the box's side or end, to a few cm.
                var low: Float = 0, high: Float = 1
                for _ in 0..<12 {
                    let middle = (low + high) / 2
                    if inside(a + (b - a) * middle) == wasInside { low = middle } else { high = middle }
                }
                let cross = a + (b - a) * (wasInside ? high : low)
                if wasInside {
                    current = [cross]
                } else {
                    current.append(cross)
                    if current.count > 1 { pieces.append(current) }
                    current = []
                }
            }
            if !isInside { current.append(b) }
            wasInside = isInside
        }
        if current.count > 1 { pieces.append(current) }
        // Nothing inside: the line as it came, not its added points.
        if pieces.count == 1, !line.contains(where: inside) { return [original] }
        return pieces
    }

    // MARK: Geometry

    static func length(_ line: [Map3DPoint]) -> Float {
        zip(line, line.dropFirst()).reduce(0) { $0 + Map3DPoint($1.1.x - $1.0.x, 0, $1.1.z - $1.0.z).length }
    }

    /// Where `point` lies by `line`, seen from above: how far along it
    /// (from its first point) and how far across it (to its right); `nil`
    /// past its ends by more than `beyond` metres.
    static func locate(_ point: Map3DPoint, along line: [Map3DPoint], beyond: Float = 0) -> (along: Float, across: Float)? {
        var best: (along: Float, across: Float, distance: Float)?
        var travelled: Float = 0
        for (number, (a, b)) in zip(line, line.dropFirst()).enumerated() {
            let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z), length = ab.length
            guard length > 0 else { continue }
            let way = ab * (1 / length), right = Map3DPoint(-way.z, 0, way.x)
            let ap = Map3DPoint(point.x - a.x, 0, point.z - a.z)
            var t = ap.dot(way)
            // Past the first and last points, straight on.
            if number > 0 { t = max(t, 0) }
            if number < line.count - 2 { t = min(t, length) }
            let foot = a + way * t
            let distance = Map3DPoint(point.x - foot.x, 0, point.z - foot.z).length
            if best == nil || distance < best!.distance { best = (travelled + t, ap.dot(right), distance) }
            travelled += length
        }
        guard let best, best.along >= -beyond, best.along <= travelled + beyond else { return nil }
        return (best.along, best.across)
    }

    /// `line` run on straight `before` metres past its first point and
    /// `after` past its last (cut back where either is negative).
    static func extend(_ line: [Map3DPoint], before: Float, after: Float) -> [Map3DPoint] {
        guard line.count > 1 else { return line }
        var out = line
        func way(_ a: Map3DPoint, _ b: Map3DPoint) -> Map3DPoint {
            Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? Map3DPoint(0, 0, -1)
        }
        out[0] = line[0] - way(line[0], line[1]) * before
        out[out.count - 1] = line[line.count - 1] + way(line[line.count - 2], line[line.count - 1]) * after
        return out
    }
}

extension Map3DScene.Builder {
    /// Decision 860: the underground platforms, solid, and each station's
    /// box round them (``Map3DUndergroundStations``); the platforms kept
    /// (``laidUnderground``) for their props and screen doors.
    mutating func addUndergroundPlatforms() {
        let underground = undergroundStations
        for platform in underground.platforms {
            guard platform.line.contains(where: { contains(scenePoint: $0) }) else { continue }
            let line = platform.line, middle = line[line.count / 2]
            let edge = world.highSpeedStations.contains(platform.station) ? Self.highSpeedPlatformEdge : Self.platformEdge
            let side: Float = platform.offset >= 0 ? 1 : -1
            // Decision 259: its waiting crowd; no one outside, over it.
            addStationLife(line: line, offset: platform.offset, width: platform.width, station: platform.station, outside: false)
            mesh(at: middle) { mesh in
                mesh.addRibbon(along: line, width: platform.width, offset: platform.offset, lift: Self.platformHeight,
                               depth: Self.platformHeight + Self.bedDrop, top: Map3DPalette.platform, side: Map3DPalette.platform,
                               topPaint: Self.paving, sidePaint: Self.concrete)
                // Decision 721: its edge line lit (always, under ground).
                let start = mesh.vertices.count
                mesh.addRibbon(along: line, width: 0.3, offset: side * (edge + 0.35), lift: Self.platformHeight + 0.01,
                               top: Map3DPalette.platformEdge)
                mesh.makeGlowing(from: start)
            }
            laidUnderground.append(LaidPlatform(station: platform.station, line: line, offset: platform.offset, width: platform.width,
                                                structure: .tunnel, island: platform.island, edge: platform.edge))
        }
        for box in underground.boxes where box.path.contains(where: { contains(scenePoint: $0) }) {
            addUndergroundBox(box, platforms: underground.platforms)
        }
    }

    /// Whether the scene point `point` is in this scene's region.
    func contains(scenePoint point: Map3DPoint) -> Bool {
        contains(x: originX + Double(point.x) * Self.metre, y: originY + Double(point.z) * Self.metre)
    }

    /// The face through `corners`, turned to face `facing`.
    private static func undergroundFace(_ mesh: inout Map3DMesh, _ corners: [Map3DPoint], facing: Map3DPoint, color: UInt32,
                                        paint: Map3DPaint? = nil) {
        guard corners.count >= 3, let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized
                ?? (corners.count > 3 ? (corners[2] - corners[0]).cross(corners[3] - corners[0]).normalized : nil) else { return }
        let turned = normal.dot(facing) < 0 ? Array(corners.reversed()) : corners
        if turned.count == 4 {
            mesh.addQuad(turned[0], turned[1], turned[2], turned[3], color: color, paint: paint)
        } else {
            mesh.addFacet(turned, color: color, paint: paint)
        }
    }

    /// `box`: its floor, walls, band, ceiling and lamps, an island's
    /// columns, and its two head walls round the bores' openings; where
    /// the drawn ground does not cover it, a bank of earth over it, as
    /// over a bore (decision 359).
    private mutating func addUndergroundBox(_ box: Map3DUndergroundStations.Box, platforms: [Map3DUndergroundStations.Platform]) {
        typealias Station = Map3DUndergroundStations
        let path = box.path, across = Map3DMesh.acrossDirections(path)
        let floor = -Station.floor, ceiling = Station.ceiling, top = Self.platformHeight
        let grounds = path.map { drawnGround(x: $0.x, z: $0.z) }
        let cover = ceiling + Self.coverThickness
        func at(_ index: Int, _ u: Float, _ y: Float) -> Map3DPoint { path[index] + across[index] * u + Map3DPoint(0, y, 0) }
        mesh(at: path[path.count / 2]) { mesh in
            for index in 1..<path.count {
                let ends = [index - 1, index]
                func strip(_ p: (Float, Float), _ q: (Float, Float), facing: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
                    Self.undergroundFace(&mesh, [at(ends[0], p.0, p.1), at(ends[0], q.0, q.1), at(ends[1], q.0, q.1), at(ends[1], p.0, p.1)],
                                         facing: facing, color: color, paint: paint)
                }
                let up = Map3DPoint.up, down = Map3DPoint.up * -1
                strip((box.left, floor), (box.right, floor), facing: up, color: Map3DPalette.tunnelLining)
                strip((box.left, ceiling), (box.right, ceiling), facing: down, color: Map3DPalette.tunnelLining)
                for (wall, inward) in [(box.left, across[index]), (box.right, across[index] * -1)] {
                    strip((wall, floor), (wall, top + Station.bandFrom), facing: inward, color: Map3DPalette.tunnelWall, paint: Self.concrete)
                    strip((wall, top + Station.bandFrom), (wall, top + Station.bandTo), facing: inward, color: Map3DPalette.platformEdge)
                    strip((wall, top + Station.bandTo), (wall, ceiling), facing: inward, color: Map3DPalette.tunnelWall, paint: Self.concrete)
                }
                // Decision 359: earth over it where the ground does not
                // cover it, its sides down to the ground.
                if ends.contains(where: { path[$0].y + cover > grounds[$0] }) {
                    let outer = Self.coverThickness
                    strip((box.left - outer, cover), (box.right + outer, cover), facing: up, color: Map3DPalette.embankment, paint: Self.bank)
                    for (wall, outward) in [(box.left - outer, across[index] * -1), (box.right + outer, across[index])] {
                        let feet = ends.map { end in max(min(grounds[end] - path[end].y - 0.3, cover), floor - outer) }
                        let sign: Float = wall < 0 ? -1 : 1
                        Self.undergroundFace(&mesh, [at(ends[0], wall, cover), at(ends[0], wall + sign * (cover - feet[0]), feet[0]),
                                                     at(ends[1], wall + sign * (cover - feet[1]), feet[1]), at(ends[1], wall, cover)],
                                             facing: outward + up, color: Map3DPalette.embankment, paint: Self.bank)
                    }
                }
            }
            // The head walls, facing in, round the bores' openings.
            for (end, openings) in [(0, box.openings.start), (path.count - 1, box.openings.end)] {
                let inward = (end == 0 ? path[1] - path[0] : path[path.count - 2] - path[path.count - 1])
                let facing = Map3DPoint(inward.x, 0, inward.z).normalized ?? Map3DPoint(0, 0, -1)
                Self.addHeadWall(&mesh, at: { u, y in at(end, u, y) }, left: box.left, right: box.right, floor: floor, ceiling: ceiling,
                                 openings: openings, facing: facing)
            }
            // The lamps in the ceiling over each platform, always lit.
            var islands: [(across: Float, from: Float, to: Float, width: Float)] = []
            for index in box.platforms {
                let platform = platforms[index]
                guard let line = Map3DStreetLife.Path(platform.line) else { continue }
                let count = max(1, Int((line.length / Station.lampEvery).rounded(.down)))
                for number in 0..<count {
                    let spot = line.at(line.length * (Float(number) + 0.5) / Float(count))
                    let start = mesh.vertices.count
                    mesh.addBox(base: spot.point + spot.right * platform.offset + Map3DPoint(0, ceiling - 0.12, 0), forward: spot.along,
                                length: Station.lampLength, width: 0.3, height: 0.1, top: Map3DPalette.tunnelLamp, side: Map3DPalette.tunnelLamp)
                    mesh.makeGlowing(from: start)
                }
                // An island's middle line, across the box, once for its
                // two halves.
                guard platform.island, 2 * platform.width >= Station.furnishedIsland,
                      let first = Station.locate(platform.line[0], along: path), let last = Station.locate(platform.line[platform.line.count - 1], along: path),
                      let middle = Station.locate(platform.line[platform.line.count / 2], along: path) else { continue }
                let side: Float = platform.offset >= 0 ? 1 : -1
                // Its across turned as the box's path runs.
                let turned: Float = (last.along >= first.along) ? 1 : -1
                let centre = middle.across + turned * (platform.offset + side * platform.width / 2)
                guard !islands.contains(where: { abs($0.across - centre) < 0.5 }) else { continue }
                islands.append((centre, min(first.along, last.along), max(first.along, last.along), 2 * platform.width))
            }
            // Each island's furniture, the old version's module along it.
            if let spine = Map3DStreetLife.Path(path) {
                for island in islands {
                    let place = { (along: Float) -> (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint) in
                        let spot = spine.at(along)
                        return (spot.point + spot.right * island.across + Map3DPoint(0, top, 0), spot.along, spot.right)
                    }
                    Self.addIslandModules(&mesh, from: island.from, to: island.to, width: island.width, headroom: ceiling - top, place: place)
                }
            }
        }
    }

    /// A head wall across a box's end from `left` to `right` and `floor`
    /// to `ceiling` (`at` placing a point across the end and up), facing
    /// `facing`, with the bore's opening (``boreHalfWidth``, its sloped
    /// shoulders up to the crown) round each of `openings`.
    static func addHeadWall(_ mesh: inout Map3DMesh, at: (Float, Float) -> Map3DPoint, left: Float, right: Float, floor: Float,
                            ceiling: Float, openings: [Float], facing: Map3DPoint) {
        let hw = boreHalfWidth, spring = boreSpring, roofEdge = boreHalfWidth - boreSlope
        func quad(_ u0: Float, _ y0: Float, _ u1: Float, _ y1: Float) {
            guard u1 - u0 > 0.01, y1 - y0 > 0.01 else { return }
            undergroundFace(&mesh, [at(u0, y0), at(u1, y0), at(u1, y1), at(u0, y1)], facing: facing, color: Map3DPalette.tunnelWall,
                            paint: concrete)
        }
        var from = left
        for opening in openings.sorted() {
            quad(from, floor, max(from, opening - hw), ceiling)
            // Over the opening's sloped shoulders, up to the ceiling.
            for (outer, inner) in [(opening - hw, opening - roofEdge), (opening + hw, opening + roofEdge)] {
                undergroundFace(&mesh, [at(outer, spring), at(outer, ceiling), at(inner, ceiling)], facing: facing,
                                color: Map3DPalette.tunnelWall, paint: concrete)
            }
            from = max(from, opening + hw)
        }
        quad(from, floor, right, ceiling)
    }
}

// MARK: The old version's island module

/// Decision 860: the owner's old version (SwiftRailMac) has an underground
/// island platform module, `assets/models/item_0c73a21f9828496928f986a3.glb`
/// (and its plain side-platform twin `item_0832d01a…`, which is no more
/// than this box's slab, wall and ceiling): 40 m of a 6 m island under a
/// ceiling 7.34 m over it, with a square column, a vending machine beside
/// it, two double benches, two poster boards and two signs hung from the
/// ceiling. Its white model kept, its texture dropped and its parts in
/// the palette's colours (decision 767's B): each part a box where the
/// module has it, across scaled to the island's width and up to the
/// box's headroom.
enum Map3DOldIslandModule {
    /// The module's length along the island, metres.
    static let length: Float = 40
    /// Its island's width and headroom, which the parts scale from.
    static let width: Float = 6
    static let headroom: Float = 7.34

    /// A part: from `from` to `to` metres along the module, from `left` to
    /// `right` across (its island's middle at 0, to the right positive),
    /// from `bottom` to `top` over the platform, in the module's metres.
    struct Part: Equatable, Sendable {
        let from: Float, to: Float
        let left: Float, right: Float
        let bottom: Float, top: Float
        let colour: UInt32
        /// Lit always (the signs' faces).
        var glows = false
    }

    /// The module's parts, read off the file (its heights less the
    /// platform's top, 3.66 m in it; the benches' legs under the platform
    /// left out).
    static let parts: [Part] = [
        // Two double benches, on the island's middle.
        Part(from: 1.01, to: 6.99, left: -0.87, right: 0.87, bottom: 0.24, top: 0.38, colour: Map3DPalette.timber),
        Part(from: 1.01, to: 6.99, left: -0.12, right: 0.12, bottom: 0.38, top: 1.53, colour: Map3DPalette.timber),
        Part(from: 9.01, to: 14.99, left: -0.87, right: 0.87, bottom: 0.24, top: 0.38, colour: Map3DPalette.timber),
        Part(from: 9.01, to: 14.99, left: -0.12, right: 0.12, bottom: 0.38, top: 1.53, colour: Map3DPalette.timber),
        // A sign hung from the ceiling over the island's right half and
        // its track, and its lit face.
        Part(from: 15.56, to: 16.2, left: 0.71, right: 4.8, bottom: 6.32, top: 7.27, colour: Map3DPalette.dark),
        Part(from: 15.5, to: 16.26, left: 0.9, right: 4.6, bottom: 6.62, top: 6.97, colour: Map3DPalette.platformEdge, glows: true),
        // The vending machine, by the column.
        Part(from: 17.55, to: 18.66, left: -0.97, right: 1.05, bottom: 0, top: 3.53, colour: Map3DPalette.trainRed),
        // The square column, up to the ceiling.
        Part(from: 18.8, to: 21.2, left: -1.2, right: 1.2, bottom: 0, top: 7.34, colour: Map3DPalette.tunnelWall),
        // A sign hung over the left half and its track.
        Part(from: 23.58, to: 24.25, left: -4.8, right: -0.71, bottom: 6.32, top: 7.27, colour: Map3DPalette.dark),
        Part(from: 23.52, to: 24.31, left: -4.6, right: -0.9, bottom: 6.62, top: 6.97, colour: Map3DPalette.platformEdge, glows: true),
        // Two poster boards on the middle, their posts and panels.
        Part(from: 28.53, to: 32.85, left: -0.1, right: 0.1, bottom: 0, top: 3.61, colour: Map3DPalette.steel),
        Part(from: 28.73, to: 32.65, left: -0.12, right: 0.12, bottom: 0.94, top: 3.48, colour: Map3DPalette.concrete),
        Part(from: 33.57, to: 38.08, left: -0.1, right: 0.1, bottom: 0, top: 3.61, colour: Map3DPalette.steel),
        Part(from: 33.76, to: 37.89, left: -0.12, right: 0.12, bottom: 0.35, top: 3.48, colour: Map3DPalette.concrete),
    ]

    /// How many whole modules an island `length` long takes, and where
    /// along it the first starts (the rest shared at its two ends).
    static func modules(along length: Float) -> (count: Int, start: Float) {
        let count = max(0, Int((length / Self.length).rounded(.down)))
        return (count, (length - Float(count) * Self.length) / 2)
    }
}

extension Map3DScene.Builder {
    /// Decision 860: the old version's island modules from `from` to `to`
    /// along an island `width` wide under `headroom` (`place` giving its
    /// middle at the platform's top, the way along and to the right).
    static func addIslandModules(_ mesh: inout Map3DMesh, from: Float, to: Float, width: Float, headroom: Float,
                                 place: (Float) -> (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint)) {
        typealias Module = Map3DOldIslandModule
        let (count, start) = Module.modules(along: to - from)
        let across = width / Module.width, up = headroom / Module.headroom
        for number in 0..<count {
            let base = from + start + Float(number) * Module.length
            for part in Module.parts {
                let middle = base + (part.from + part.to) / 2
                let at = place(middle)
                let foot = at.point + at.right * ((part.left + part.right) / 2 * across) + Map3DPoint(0, part.bottom * up, 0)
                let begin = mesh.vertices.count
                mesh.addBox(base: foot, forward: at.along, length: part.to - part.from, width: (part.right - part.left) * across,
                            height: (part.top - part.bottom) * up, top: part.colour, side: part.colour)
                if part.glows { mesh.makeGlowing(from: begin) }
            }
        }
    }
}
