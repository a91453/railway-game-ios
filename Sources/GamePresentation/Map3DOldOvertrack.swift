import Foundation
import GameCore

/// Decision 1043 (the second step of decision 1042): a ground station in
/// Japan whose building stands over its tracks (橋上駅舎), from the owner's
/// earlier version: its hall over two tracks between side platforms
/// (`overtrack-1`), its hall over an island (`overtrack-2`), and the stair
/// down to a further island with the corridor to it (`overtrack-stair`).
/// The local studio turned them into the game's palette at half their old
/// size, the halls' underside 6.50 m over the rails, the deck of the
/// game's footbridges (decision 936; `a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1`,
/// #662), and `tools/old-models/old_overtrack.py` made them the game's own
/// (owner, 2026-11-28: like the old ones, not the same): their red roofs
/// the game's station green, a name board in the sign blue on the hall's
/// street front.
///
/// It stands for the station's building and its footbridge together: a
/// station with one draws neither (``Map3DScene/Builder/addStations``,
/// ``Map3DScene/Builder/addStationCrossings(_:)``).
///
/// The models' own space: metres, +x along the platforms (the stairs go
/// down towards −x), +y across the tracks, +z up; the origin on the ground
/// (0.85 m under the rails, 2 m under the platforms) at the middle between
/// the hall's two tracks. The side hall's street side is its −y: a wing
/// past the platform there, with the stairs down to the street; the
/// corridor to a further island leaves its +y wall.
enum Map3DOldOvertrack {
    enum Hall: String, CaseIterable, Sendable {
        /// Over two tracks between two side platforms.
        case side = "overtrack-1"
        /// Over an island and its two tracks, the street either side.
        case island = "overtrack-2"
    }

    static let stair = "overtrack-stair", corridor = "corridor"

    static let models: [String: Map3DModelPack.Model] = {
        var models: [String: Map3DModelPack.Model] = [:]
        for (name, text) in encoded {
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { continue }
            models[name] = Map3DRedCommuter.decodedMesh([UInt8](data), named: "old-port-station-ground-" + name,
                                                        palette: Map3DOldGroundStation.meshPalette)
        }
        return models
    }()

    /// The model `name` (a hall's raw value, ``stair`` or ``corridor``),
    /// near or `far` (the halls alone have far versions).
    static func model(_ name: String, far: Bool = false) -> Map3DModelPack.Model? {
        models[name + (far && Hall(rawValue: name) != nil ? "-far" : "")]
    }

    // MARK: Sizes (the studio's `report.json`)

    /// The platforms' face in the models' space: the rails' 0.85 m and
    /// the platform's 1.15 m.
    static let platformFace: Float = 2
    /// The halls' underside, over the platforms: the game's footbridge deck.
    static let deck: Float = 5.35
    /// How far a hall reaches along the platforms, the stairs' foot at the
    /// low end; its middle.
    static let hallReach: ClosedRange<Float> = -17.8...13.44
    static var hallMiddle: Float { (hallReach.lowerBound + hallReach.upperBound) / 2 }
    /// The side hall's two tracks either side of its middle, and the walls
    /// of each stair down to a side platform, across (the +y one's two
    /// columns stand within them).
    static let sideTracks: Float = 2.5
    static let sideStair: ClosedRange<Float> = 4.6...6.8
    /// The island hall's two tracks either side of its middle, and half
    /// its stair's roof.
    static let islandTracks: Float = 5.5
    static let islandStairHalf: Float = 1.36
    /// How far the side hall's street side reaches past its middle (its
    /// wing and the stairs to the street), the island's either side.
    static let sideStreet: Float = 11.96
    static let islandStreet: Float = 12.84
    /// No track and no other platform this far either side of the hall's
    /// middle on its street side: the wing's stairs come down there.
    static let streetClear: Float = 13.6
    /// The side platform on the street side ends within this of the
    /// hall's middle, before the wing.
    static let streetPlatform: Float = 8
    /// The side hall's wall the corridor leaves (+y), half the further
    /// stair's walls and half its roof.
    static let hallWall: Float = 8
    static let stairWall: Float = 2.06, stairRoof: Float = 2.3
    /// The narrowest island a further stair (4.6 m) stands on.
    static let stairBody: Float = 4.8
    /// How far the corridor may reach to its last stair.
    static let longestReach: Float = 60
    /// Where along the corridor its piers' two columns stand (under the
    /// hall's own), and the columns' size.
    static let pierColumns: [Float] = [-2.1, 6.7]
    static let pierLength: Float = 1.2, pierWidth: Float = 0.8

    // MARK: The plan

    /// A station's building over its tracks: which hall, where across the
    /// crossing's line, which way, and the further islands' stairs.
    struct Plan: Equatable, Sendable {
        let hall: Hall
        /// The hall's origin, across the crossing's line.
        let centre: Float
        /// 1 when the models' +y runs the way the line's laterals grow, −1
        /// when it runs against them.
        let way: Float
        /// The further islands' stairs, the corridors to them and the
        /// piers under those, in the models' y from the hall's origin.
        var stairs: [Float] = []
        var corridors: [ClosedRange<Float>] = []
        var piers: [Float] = []

        /// How far it all reaches across, in the models' y.
        var reach: ClosedRange<Float> {
            switch hall {
            case .island: -islandStreet...islandStreet
            case .side: -sideStreet...max(hallWall + 0.3, (stairs.last ?? 0) + stairRoof)
            }
        }
    }

    /// The building over the tracks for the platforms met along a
    /// crossing's line (`bodies`, an island's two halves merged) and the
    /// tracks it meets (their laterals), or `nil` when the station is not
    /// laid as one of the earlier version's: an island alone between its
    /// two tracks (11 m apart), or two side platforms either side of two
    /// tracks (5 m apart), the street side's past nothing within
    /// ``streetClear``, and any further islands all on the other side.
    static func plan(bodies: [Map3DStationFootbridge.Body], tracks: [Float]) -> Plan? {
        let all = Map3DStationFootbridge.merged(bodies), tracks = tracks.sorted()
        if all.count == 1 { return islandPlan(all[0], tracks: tracks) }
        var options: [(plan: Plan, streetTracks: Int)] = []
        for index in all.indices.dropLast() {
            for way: Float in [1, -1] {
                guard let plan = sidePlan(all, index, way: way, tracks: tracks) else { continue }
                // The street side with less other track beyond.
                let streetTracks = tracks.filter { t in let y = (t - plan.centre) * way; return y < -streetClear && y > -40 }.count
                options.append((plan, streetTracks))
            }
        }
        return options.min { ($0.streetTracks, -$0.plan.way) < ($1.streetTracks, -$1.plan.way) }?.plan
    }

    private static func islandPlan(_ island: Map3DStationFootbridge.Body, tracks: [Float]) -> Plan? {
        let near = tracks.filter { abs($0 - island.middle) < streetClear }
        guard island.fits, near.count == 2, let a = near.first, let b = near.last,
              a < island.low + 0.2, b > island.high - 0.2, abs((b - a) / 2 - islandTracks) <= 1 else { return nil }
        let centre = (a + b) / 2
        guard island.low <= centre - islandStairHalf, island.high >= centre + islandStairHalf else { return nil }
        return Plan(hall: .island, centre: centre, way: 1)
    }

    private static func sidePlan(_ all: [Map3DStationFootbridge.Body], _ index: Int, way: Float, tracks: [Float]) -> Plan? {
        let low = all[index], high = all[index + 1]
        guard low.fits, high.fits else { return nil }
        let between = tracks.filter { $0 > low.high - 0.2 && $0 < high.low + 0.2 }
        guard between.count == 2, abs(between[1] - between[0] - 2 * sideTracks) <= 1.2 else { return nil }
        let centre = (between[0] + between[1]) / 2
        func across(_ body: Map3DStationFootbridge.Body) -> ClosedRange<Float> {
            let a = (body.low - centre) * way, b = (body.high - centre) * way
            return min(a, b)...max(a, b)
        }
        let street = across(way > 0 ? low : high), other = across(way > 0 ? high : low)
        // Each stair on its platform; the street one's ending before the wing.
        guard -street.upperBound <= sideStair.lowerBound + 0.05, -street.lowerBound >= sideStair.upperBound - 0.05,
              -street.lowerBound <= streetPlatform,
              other.lowerBound <= sideStair.lowerBound + 0.05, other.upperBound >= sideStair.upperBound - 0.05 else { return nil }
        // Nothing else on the street side: no track past the hall's own,
        // no platform.
        guard !tracks.contains(where: { t in let y = (t - centre) * way; return y < -sideTracks - 1.2 && y > -streetClear }) else { return nil }
        var stairs: [Float] = []
        for (other_, body) in all.enumerated() where other_ != index && other_ != index + 1 {
            let range = across(body)
            guard range.lowerBound > other.upperBound, body.fits, range.upperBound - range.lowerBound >= stairBody else { return nil }
            stairs.append((range.lowerBound + range.upperBound) / 2)
        }
        stairs.sort()
        var corridors: [ClosedRange<Float>] = [], from = hallWall
        for stair in stairs {
            guard stair - stairWall >= from + 0.5 else { return nil }
            corridors.append(from...(stair - stairWall))
            from = stair + stairWall
        }
        guard (stairs.last ?? 0) + stairRoof <= longestReach else { return nil }
        // A pier between two tracks the corridor crosses, far enough apart
        // for one, with no platform between them.
        let ys = tracks.map { ($0 - centre) * way }.sorted()
        var piers: [Float] = []
        for (a, b) in zip(ys, ys.dropFirst()) where b - a >= Map3DStationFootbridge.pierRoom {
            let middle = (a + b) / 2
            guard corridors.contains(where: { $0.lowerBound + 1 <= middle && middle <= $0.upperBound - 1 }),
                  !all.contains(where: { body in let r = across(body); return r.lowerBound < b && r.upperBound > a }) else { continue }
            piers.append(middle)
        }
        return Plan(hall: .side, centre: centre, way: way, stairs: stairs, corridors: corridors, piers: piers)
    }

    /// Whether a station of `expansion` laid as `plan` takes its building
    /// over the tracks: an island's always (it has no other way up to it);
    /// two side platforms' when the station has a bigger concourse
    /// (the first expansion: the concourse goes over the tracks, as most
    /// of Japan's do when they grow) or no room for a building beside its
    /// platforms (`roomBeside`). A big station (the second expansion)
    /// keeps its big building (decision 1042).
    static func chosen(_ plan: Plan, expansion: StationExpansion?, roomBeside: Bool) -> Bool {
        guard expansion != .hall else { return false }
        return plan.hall == .island || expansion == .concourse || !roomBeside
    }
}

// MARK: - Building

extension Map3DScene.Builder {
    /// Decision 1043: a station's building over its tracks, as
    /// ``planOvertrack(_:indices:tracks:)`` placed it.
    struct PlacedOvertrack {
        let plan: Map3DOldOvertrack.Plan
        /// The hall's origin in the scene (its ground, 2 m under the
        /// platforms), the way its models' +x runs (level) and their +y.
        let origin: Map3DPoint
        let forward: Map3DPoint
        let left: Map3DPoint
        /// Where along each of its platforms (by its place in
        /// ``PlatformState/laidPlatforms``) the hall stands.
        let keepOut: [Int: ClosedRange<Float>]

        /// A point in the models' space.
        func point(_ x: Float, _ y: Float, _ z: Float) -> Map3DPoint {
            origin + forward * x + left * y + Map3DPoint.up * z
        }
    }

    /// Decision 1043: where the building over the tracks of the station
    /// whose surface platforms are `indices` (of ``PlatformState/laidPlatforms``)
    /// stands, among the scene's `tracks`: across the middle of its
    /// longest platform, every platform straight and clear of its ends
    /// there, none high over them; `nil` when it is not laid for one
    /// (``Map3DOldOvertrack/plan(bodies:tracks:)``).
    func planOvertrack(_ id: StationID, indices: [Int], tracks: [Map3DStreetLife.Path]) -> PlacedOvertrack? {
        typealias Old = Map3DOldOvertrack
        typealias Bridge = Map3DStationFootbridge
        let laid = state.platforms.laidPlatforms
        let paths = indices.compactMap { index in Map3DStreetLife.Path(laid[index].line).map { (index: index, path: $0) } }
        guard paths.count == indices.count, let reference = paths.max(by: { $0.path.length < $1.path.length }) else { return nil }
        let here = reference.path.at(reference.path.length / 2)
        let half = (Old.hallReach.upperBound - Old.hallReach.lowerBound) / 2
        var bodies: [Bridge.Body] = [], tops: [Float] = [], keepOut: [Int: ClosedRange<Float>] = [:]
        for (index, path) in paths {
            let platform = laid[index]
            guard let meeting = Self.meeting(of: path, across: here.right, through: here.point),
                  abs(meeting.direction.dot(here.along)) >= 0.998 else { return nil }
            let same: Float = meeting.direction.dot(here.along) >= 0 ? 1 : -1
            let middle = meeting.lateral + platform.offset * same
            let ends = [meeting.along - half, meeting.along + half]
            let clear = ends[0] >= Bridge.endGap && ends[1] <= path.length - Bridge.endGap
            let straight = ends.allSatisfy { end in
                let at = path.at(end)
                let offset = Map3DPoint(at.point.x - here.point.x, 0, at.point.z - here.point.z).dot(here.right)
                return abs(offset - meeting.lateral) < 0.25
            }
            guard clear, straight else { return nil }
            bodies.append(Bridge.Body(low: middle - platform.width / 2, high: middle + platform.width / 2, fits: true))
            tops.append(meeting.height + Self.platformHeight)
            keepOut[index] = ends[0]...ends[1]
        }
        guard let top = tops.max(), let lowest = tops.min(), top - lowest <= 0.3 else { return nil }
        var laterals: [Float] = []
        for track in tracks where track.boxDistance(to: here.point) <= 80 {
            guard let meeting = Self.meeting(of: track, across: here.right, through: here.point) else { continue }
            // None high over the platforms (a viaduct through the station).
            if meeting.height > here.point.y + 1.5 { return nil }
            laterals.append(meeting.lateral)
        }
        guard let plan = Old.plan(bodies: bodies, tracks: laterals) else { return nil }
        // The models' +y the plan's way across; their +x then follows.
        let across = here.right * plan.way
        let forward = Map3DPoint.up.cross(here.along).dot(across) >= 0 ? here.along : here.along * -1
        let left = Map3DPoint.up.cross(forward)
        // Its middle along over the platforms' middle.
        let origin = here.point + here.right * plan.centre - forward * Old.hallMiddle
        return PlacedOvertrack(plan: plan, origin: Map3DPoint(origin.x, top - Old.platformFace, origin.z), forward: forward, left: left,
                               keepOut: keepOut)
    }

    /// Decision 1043: the building over the tracks, close up and far off,
    /// in its own colours as a station's building is (decision 722); the
    /// cells under it.
    mutating func addOvertrack(_ placed: PlacedOvertrack) -> Set<Map3DScene.ChunkKey> {
        typealias Old = Map3DOldOvertrack
        let plan = placed.plan
        var near = Map3DMesh(), far = Map3DMesh()
        for distant in [false, true] {
            var mesh = Map3DMesh()
            guard let hall = Old.model(plan.hall.rawValue, far: distant), let stair = Old.model(Old.stair),
                  let corridor = Old.model(Old.corridor) else { return [] }
            Map3DStationFootbridge.add(hall, to: &mesh, at: placed.origin, forward: placed.forward)
            for y in plan.stairs { Map3DStationFootbridge.add(stair, to: &mesh, at: placed.point(0, y, 0), forward: placed.forward) }
            for span in plan.corridors {
                Map3DStationFootbridge.add(corridor, to: &mesh, at: placed.point(0, span.lowerBound, 0), forward: placed.forward,
                                           stretch: span.upperBound - span.lowerBound)
            }
            for y in plan.piers {
                for x in Old.pierColumns {
                    let foot = placed.point(x, y, Map3DScene.railLift)
                    mesh.addBox(base: foot, forward: placed.forward, length: Old.pierLength, width: Old.pierWidth,
                                height: Old.platformFace + Old.deck - Map3DScene.railLift, top: Map3DPalette.concrete, side: Map3DPalette.concrete)
                }
            }
            if distant { far = mesh } else { near = mesh }
        }
        Map3DLook.restyle(&near, keeping: keptColours, strength: Map3DStationKit.houseLook)
        Map3DLook.restyle(&far, keeping: keptColours, strength: Map3DStationKit.houseLook)
        let centre = placed.point(Old.hallMiddle, 0, 0)
        let key = key(of: centre)
        if !isCoarse(key) {
            ownColourNear[key, default: Map3DMesh()].append(near)
            state.stations.houseTriangleCount += near.triangleCount
        }
        ownColourFar[key, default: Map3DMesh()].append(far)
        // The cells under its footprint, for its outline.
        let reach = plan.reach
        let corners = [(Old.hallReach.lowerBound, reach.lowerBound), (Old.hallReach.upperBound, reach.lowerBound),
                       (Old.hallReach.upperBound, reach.upperBound), (Old.hallReach.lowerBound, reach.upperBound)]
            .map { placed.point($0.0, $0.1, 0) }
        let cell = Double(Land.cellLength)
        func index(_ value: Float, _ origin: Double) -> Int { Int(((origin + Double(value) * Self.metre) / cell).rounded(.down)) }
        let columns = corners.map { index($0.x, originX) }, rows = corners.map { index($0.z, originY) }
        var cells = Set<Map3DScene.ChunkKey>()
        for row in rows.min()!...rows.max()! { for column in columns.min()!...columns.max()! { cells.insert(Map3DScene.ChunkKey(column: column, row: row)) } }
        state.stations.houseFootprints.append(corners)
        return cells
    }
}
