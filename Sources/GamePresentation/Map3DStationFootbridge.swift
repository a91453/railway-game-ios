import Foundation
import GameCore

/// Decision 936: the way between the platforms of a station on the ground,
/// which the 3D map had not: a footbridge over its tracks (a stair tower on
/// each platform, the corridor's spans between them, a pier between two
/// tracks, a wall closing each end) or, where a tower has no room, the
/// stairs down to an underpass on each platform. The local studio's parts
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/station-footbridge-2026-11/revision-4`,
/// #301; lessons in `docs/studio/lessons/station-footbridge.md`), written
/// in with `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// The models' own space: metres, +x along the platform (a tower's stairs
/// climb that way), +y across the tracks, +z up. A tower's origin is its
/// first step on the platform, its corridor's middle ``corridorAxis``
/// along; a span's and an end wall's the middle of its underside
/// (``deck`` over the platform); a pier's its foot at the rails' height;
/// the underpass stairs' the middle of the opening on the platform.
///
/// How long the change takes is GameCore's (decision 912) and does not
/// look at what is drawn here.
enum Map3DStationFootbridge {
    /// Which of the studio's three looks: Taiwan Railway's (a green roof
    /// over a row of windows, round piers), the MTR's ground stations'
    /// (glass and white steel), Fukuoka's (the owner's earlier models'
    /// steel and sheet roof).
    enum Style: String, CaseIterable, Sendable {
        case taiwan = "tw", hongKong = "hk", japan = "jp"

        /// The style of a map's buildings; none on the Nordic map, whose
        /// stations are crossed on the level at a platform's end.
        init?(_ buildings: Map3DRegionLook.Buildings) {
            switch buildings {
            case .taiwan: self = .taiwan
            case .hongKong: self = .hongKong
            case .japan: self = .japan
            case .nordic: return nil
            }
        }
    }

    enum Part: String, CaseIterable, Sendable {
        case stair, span, pier, end
    }

    /// What stands on the platforms: a footbridge's towers, or the stairs
    /// down to an underpass.
    enum Kind: CaseIterable, Sendable {
        case footbridge, underpass

        /// How far it reaches along the platform either side of the
        /// crossing's line, the way its +x runs.
        var reach: ClosedRange<Float> {
            switch self {
            case .footbridge: -Map3DStationFootbridge.corridorAxis...(Map3DStationFootbridge.towerLength - Map3DStationFootbridge.corridorAxis)
            case .underpass: -4.05...4.45
            }
        }
    }

    /// The colours of the mesh's palette indices, in the order given to
    /// `glb_to_swift.py`: wall, roof, frame, glass, deck, dark, brick,
    /// canopy, white; each a colour the game already has (decision 891).
    static let meshPalette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.hallRoofs[1], Map3DPalette.steel, Map3DPalette.glazing, Map3DPalette.concrete,
        Map3DPalette.dark, Map3DPalette.redBrick, Map3DPalette.canopy, Map3DPalette.tankSteel,
    ]

    static let models: [String: Map3DModelPack.Model] = {
        var models: [String: Map3DModelPack.Model] = [:]
        for (name, text) in encoded {
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { continue }
            models[name] = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
        }
        return models
    }()

    static func model(_ style: Style, _ part: Part, far: Bool = false) -> Map3DModelPack.Model? {
        models["station-footbridge-\(style.rawValue)-\(part.rawValue)\(far ? "-far" : "")"]
    }

    /// The stairs down to an underpass, the one look for every map: brick
    /// walls to the waist round the opening, the steps going down into
    /// the dark, a small roof over their far end.
    static func underpass(far: Bool = false) -> Map3DModelPack.Model? {
        models["station-underpass-stair-covered" + (far ? "-far" : "")]
    }

    // MARK: Sizes (the studio's interface, the brief's §3)

    /// A tower: how long it is along the platform, where its corridor's
    /// middle is along it, and half its width.
    static let towerLength: Float = 16
    static let corridorAxis: Float = 14.4
    static let towerHalfWidth: Float = 1.3
    /// The corridor's underside over the platform (6.5 m over the rails,
    /// as a road bridge's, decision 375).
    static let deck: Float = 5.35
    /// A span as the studio made it, and half an end wall's thickness.
    static let spanLength: Float = 5
    static let endHalf: Float = 0.15
    /// The narrowest platform (an island's two halves together) a tower
    /// or the stairs stand on: 2.6 m and a hand's breadth each side.
    static let narrowestBody: Float = 3
    /// Two tracks at least so far apart have a pier between them: its
    /// 0.8 m and a train's room each side.
    static let pierRoom: Float = 4.4
    /// How far the stairs' foot keeps from the canopy's end (a sign on a
    /// post stands there, decision 936), and the thing from the
    /// platform's end.
    static let canopyGap: Float = 3
    static let endGap: Float = 0.5

    // MARK: The plan

    /// A platform where the crossing's line meets it: from `low` to
    /// `high` metres along that line, and whether a tower (or the
    /// stairs) has room on it there, clear of its canopy and its ends.
    struct Body: Equatable, Sendable {
        var low: Float
        var high: Float
        var fits: Bool

        var middle: Float { (low + high) / 2 }
    }

    /// The two halves of an island (they meet between its tracks) as one
    /// platform, with room only where both have.
    static func merged(_ bodies: [Body]) -> [Body] {
        var out: [Body] = []
        for body in bodies.sorted(by: { ($0.low, $0.high) < ($1.low, $1.high) }) {
            if let last = out.last, body.low - last.high < 0.3 {
                out[out.count - 1] = Body(low: last.low, high: max(last.high, body.high), fits: last.fits && body.fits)
            } else {
                out.append(body)
            }
        }
        return out
    }

    /// Where a crossing's towers and piers stand along its line.
    struct Crossing: Equatable, Sendable {
        /// The middle of each platform with a tower, in order.
        let towers: [Float]
        /// The middle between two tracks with room for a pier.
        let piers: [Float]
    }

    /// A tower on each platform wide enough with room for one, when there
    /// are two or more and a track between the first and the last; a pier
    /// between each two tracks ``pierRoom`` apart with no platform
    /// between them. `nil` when no crossing is drawn.
    static func crossing(bodies: [Body], tracks: [Float]) -> Crossing? {
        let all = merged(bodies)
        let towers = all.filter { $0.fits && $0.high - $0.low >= narrowestBody }.map(\.middle)
        guard towers.count >= 2, let first = towers.first, let last = towers.last else { return nil }
        let between = tracks.filter { $0 > first && $0 < last }.sorted()
        guard !between.isEmpty else { return nil }
        var piers: [Float] = []
        for (a, b) in zip(between, between.dropFirst()) where b - a >= pierRoom {
            if all.contains(where: { $0.low < b && $0.high > a }) { continue }
            piers.append((a + b) / 2)
        }
        return Crossing(towers: towers, piers: piers)
    }

    /// The spans between two towers whose middles are at `a` and `b`: how
    /// many, and how long each is drawn (the studio's 5 m, stretched or
    /// squeezed by at most a half so they fill the way between the
    /// towers' sides with no gap).
    static func spans(from a: Float, to b: Float) -> (count: Int, length: Float) {
        let run = max(b - a - 2 * towerHalfWidth, 0.5)
        let count = max(1, Int((run / spanLength).rounded()))
        return (count, run / Float(count))
    }

    /// Where along a platform `length` long, its canopy over its middle
    /// `share`, something `room` long stands clear of the canopy: past
    /// the canopy's end towards the platform's start (`atStart`) or its
    /// end, ``canopyGap`` from the canopy and ``endGap`` from the
    /// platform's end. `nil` where there is no room.
    static func place(length: Float, share: Float, room: Float, atStart: Bool) -> ClosedRange<Float>? {
        let free = length * (1 - share) / 2
        guard free >= room + canopyGap + endGap else { return nil }
        return atStart ? (free - canopyGap - room)...(free - canopyGap) : (length - free + canopyGap)...(length - free + canopyGap + room)
    }

    // MARK: Drawing

    /// `model` in the scene: its origin at `origin`, its +x along level
    /// `forward`, its +y to the left of that (drawn `stretch` times as
    /// long that way), its +z up. Vertices under the model's ground (the
    /// underpass's steps) are pressed onto it with `pressed`.
    static func add(_ model: Map3DModelPack.Model, to mesh: inout Map3DMesh, at origin: Map3DPoint, forward: Map3DPoint,
                    stretch: Float = 1, pressed: Bool = false) {
        let left = Map3DPoint.up.cross(forward)
        let vertices = model.vertices
        for start in stride(from: 0, to: vertices.count - 2, by: 3) {
            mesh.appendTriangle(vertices[start..<start + 3].map { v in
                let z = pressed && v.z < 0 ? pressedHeight(v.z) : v.z
                return Map3DVertex(origin + forward * v.x + left * (v.y * stretch) + Map3DPoint.up * z,
                                   normal: forward * v.nx + left * v.ny + Map3DPoint.up * v.nz, color: v.color, layer: v.layer)
            })
        }
    }

    /// The game's platform is one solid piece with no hole in it, so the
    /// underpass's steps (down to 1.95 m under the platform) are drawn
    /// pressed onto its top, from 2 to 10 cm over it, in the order they
    /// go down: from above, the steps and the dark at their foot inside
    /// the brick walls, as the opening would show.
    static func pressedHeight(_ z: Float) -> Float {
        0.02 + (max(z, -2) + 2) * 0.04
    }
}

// MARK: - Building

extension Map3DScene.Builder {
    /// Where the line across the ground through `point` along level
    /// `across` meets `path`: how far along `across` from `point`, how
    /// far along the path, the path's level way there and its height.
    /// The meeting nearest `point`, within `reach`.
    static func meeting(of path: Map3DStreetLife.Path, across: Map3DPoint, through point: Map3DPoint, reach: Float = 80)
        -> (lateral: Float, along: Float, direction: Map3DPoint, height: Float)? {
        let way = Map3DPoint(across.z, 0, -across.x)
        var best: (lateral: Float, along: Float, direction: Map3DPoint, height: Float)?
        for index in 1..<path.points.count {
            let a = path.points[index - 1], b = path.points[index]
            let da = (a - point).dot(way), db = (b - point).dot(way)
            guard da != db, (da <= 0) != (db <= 0) || da == 0 || db == 0 else { continue }
            let t = min(max(da / (da - db), 0), 1)
            let at = a + (b - a) * t
            let lateral = Map3DPoint(at.x - point.x, 0, at.z - point.z).dot(across)
            guard abs(lateral) <= reach, abs(lateral) < abs(best?.lateral ?? .infinity),
                  let direction = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized else { continue }
            best = (lateral, path.distances[index - 1] + (path.distances[index] - path.distances[index - 1]) * t, direction, at.y)
        }
        return best
    }

    /// Decision 936: at each station on the ground with two or more
    /// platforms, a footbridge over its tracks past one end of its
    /// canopies, or the stairs down to an underpass where a tower has no
    /// room; close up the studio's models, far off their far versions.
    /// Where each stands on a platform is kept (``crossingKeepOut``), so
    /// the platform's own things stand clear of it.
    ///
    /// None at a depot, under a shell or where a real building stands
    /// for the station (its own platforms' roofs), on the Nordic map, or
    /// where a block of chunks holds only some of the station's platforms
    /// (another block, holding them all, draws it).
    mutating func addStationCrossings(_ snapshot: RailwaySnapshot) {
        typealias Bridge = Map3DStationFootbridge
        guard let style = Bridge.Style(look.buildings) else { return }
        let saved = target
        defer { target = saved }
        var partial = Set<StationID>()
        for platform in snapshot.platforms where platform.points.count > 1 && platform.structure != .tunnel
            && !platform.points.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) {
            partial.insert(platform.platform.station)
        }
        var byStation: [StationID: [Int]] = [:]
        for (index, platform) in laidPlatforms.enumerated() where platform.structure == .surface {
            byStation[platform.station, default: []].append(index)
        }
        let tracks = trackLines.filter { $0.kind != .tunnel }.compactMap { Map3DStreetLife.Path($0.points) }
        for (id, indices) in byStation.sorted(by: { $0.key < $1.key }) where indices.count >= 2 {
            guard !partial.contains(id), !shellRoofed.contains(id), !studiedStations.contains(id),
                  world.station(id: id)?.isDepot != true else { continue }
            let paths = indices.compactMap { index in Map3DStreetLife.Path(laidPlatforms[index].line).map { (index: index, path: $0) } }
            guard paths.count == indices.count, let reference = paths.max(by: { $0.path.length < $1.path.length }) else { continue }
            let share = Map3DStationKit.canopyShare(world.station(id: id)?.expansion)
            search: for kind in Bridge.Kind.allCases {
                let reach = kind.reach
                for atStart in [true, false] {
                    guard let range = Bridge.place(length: reference.path.length, share: share, room: reach.upperBound - reach.lowerBound,
                                                   atStart: atStart) else { continue }
                    // Its +x away from the platform's middle: the stairs'
                    // foot (the opening) towards the canopy.
                    let line = atStart ? range.upperBound + reach.lowerBound : range.lowerBound - reach.lowerBound
                    let here = reference.path.at(line)
                    let forward = atStart ? here.along * -1 : here.along
                    var bodies: [Bridge.Body] = [], measured: [(index: Int, body: Bridge.Body, own: ClosedRange<Float>, top: Float)] = []
                    for (index, path) in paths {
                        let platform = laidPlatforms[index]
                        guard let meeting = Self.meeting(of: path, across: here.right, through: here.point),
                              abs(meeting.direction.dot(here.along)) >= 0.998 else { continue }
                        let same: Float = meeting.direction.dot(here.along) >= 0 ? 1 : -1
                        let middle = meeting.lateral + platform.offset * same
                        // Along its own line: clear of its own canopy and
                        // ends, and as straight as the reference there.
                        let way = same * (atStart ? -1 : 1)
                        let ends = [meeting.along + way * reach.lowerBound, meeting.along + way * reach.upperBound]
                        let own = min(ends[0], ends[1])...max(ends[0], ends[1])
                        let free = path.length * (1 - share) / 2
                        let clear = own.lowerBound >= Bridge.endGap && own.upperBound <= path.length - Bridge.endGap
                            && (own.upperBound <= free - 1 || own.lowerBound >= path.length - free + 1)
                        let straight = ends.allSatisfy { end in
                            let at = path.at(end)
                            let offset = Map3DPoint(at.point.x - here.point.x, 0, at.point.z - here.point.z).dot(here.right)
                            return abs(offset - meeting.lateral) < 0.25
                        }
                        let body = Bridge.Body(low: middle - platform.width / 2, high: middle + platform.width / 2, fits: clear && straight)
                        bodies.append(body)
                        measured.append((index, body, own, meeting.height + Self.platformHeight))
                    }
                    // The tracks the line crosses; none of them high over
                    // the platforms (a viaduct through the station).
                    var laterals: [Float] = []
                    var overhead = false
                    for track in tracks where track.boxDistance(to: here.point) <= 80 {
                        guard let meeting = Self.meeting(of: track, across: here.right, through: here.point) else { continue }
                        laterals.append(meeting.lateral)
                        if meeting.height > here.point.y + 1.5 { overhead = true }
                    }
                    guard !overhead, let crossing = Bridge.crossing(bodies: bodies, tracks: laterals) else { continue }
                    let all = Bridge.merged(bodies)
                    let standing = measured.filter { piece in
                        all.contains { $0.fits && $0.high - $0.low >= Bridge.narrowestBody && $0.low <= piece.body.low + 0.01 && $0.high >= piece.body.high - 0.01 }
                    }
                    let tops = standing.map(\.top)
                    guard let top = tops.max(), let lowest = tops.min(), top - lowest <= 0.3 else { continue }
                    for piece in standing { crossingKeepOut[piece.index] = piece.own }
                    func at(_ lateral: Float, _ height: Float) -> Map3DPoint {
                        Map3DPoint(here.point.x, height, here.point.z) + here.right * lateral
                    }
                    // Model +y is to the left of `forward`.
                    let leftward: Float = Map3DPoint.up.cross(forward).dot(here.right) >= 0 ? 1 : -1
                    let middle = at((crossing.towers[0] + crossing.towers[crossing.towers.count - 1]) / 2, top)
                    for far in [false, true] {
                        target = far ? .far : .near
                        mesh(at: middle) { mesh in
                            switch kind {
                            case .underpass:
                                guard let stairs = Bridge.underpass(far: far) else { return }
                                for tower in crossing.towers { Bridge.add(stairs, to: &mesh, at: at(tower, top), forward: forward, pressed: true) }
                            case .footbridge:
                                guard let stair = Bridge.model(style, .stair, far: far), let span = Bridge.model(style, .span, far: far),
                                      let pier = Bridge.model(style, .pier, far: far), let end = Bridge.model(style, .end, far: far) else { return }
                                for tower in crossing.towers {
                                    Bridge.add(stair, to: &mesh, at: at(tower, top) - forward * Bridge.corridorAxis, forward: forward)
                                }
                                for (a, b) in zip(crossing.towers, crossing.towers.dropFirst()) {
                                    let spans = Bridge.spans(from: a, to: b)
                                    for number in 0..<spans.count {
                                        let lateral = a + Bridge.towerHalfWidth + spans.length * (Float(number) + 0.5)
                                        Bridge.add(span, to: &mesh, at: at(lateral, top + Bridge.deck), forward: forward,
                                                   stretch: spans.length / Bridge.spanLength)
                                    }
                                }
                                // A wall over each outer opening, its
                                // outer face outwards (the studio's
                                // faces +y).
                                let outer = Bridge.towerHalfWidth + Bridge.endHalf
                                Bridge.add(end, to: &mesh, at: at(crossing.towers[0] - outer, top + Bridge.deck), forward: forward * -leftward)
                                Bridge.add(end, to: &mesh, at: at(crossing.towers[crossing.towers.count - 1] + outer, top + Bridge.deck),
                                           forward: forward * leftward)
                                for lateral in crossing.piers {
                                    let foot = at(lateral, top - Self.platformHeight)
                                    Bridge.add(pier, to: &mesh, at: foot, forward: forward)
                                    // Its footing in the track bed.
                                    mesh.addBox(base: foot - Map3DPoint(0, 0.7, 0), forward: forward, length: 1.2, width: 1.2, height: 0.7,
                                                top: Map3DPalette.concrete, side: Map3DPalette.concrete)
                                }
                            }
                        }
                    }
                    break search
                }
            }
        }
    }
}
