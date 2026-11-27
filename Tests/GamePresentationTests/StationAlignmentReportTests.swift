import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// STATION-ALIGN-REPORT (decision 1021, the station rules of 2026-11-27,
/// part (b)): how far the platforms the game lays stand from the real ones,
/// and whether the real station buildings stand on the game's track. Only
/// at the stations Chien named (2026-11-27: 「只需要目前可收購路線 月台/站房，
/// 還有不可收購但是站房已製作的」, the THSR included): every station of every
/// line on sale on every map, the lines bought one bundle after another
/// (decisions 315, 400, 862, 975, 993), and the stations whose building the
/// game draws though no line through them is on sale (decision 625/626/665/929's
/// exterior studies, decisions 370/431's Taipei and Kaohsiung landmarks),
/// each bought by itself (decision 400 A.8), as a player can. It only
/// measures and writes a table; it changes nothing the game does.
///
/// The real platforms and buildings are OpenStreetMap's, read from whole
/// extracts by `tools/station-alignment/extract_osm_platforms.py` into
/// `tools/station-alignment/data/` (ODbL 1.0); for the TRA's stations also
/// the app's own `tra_platforms.json` (each station's two farthest platform
/// vertices). The buildings are decision 625/626/665/929's exterior studies'
/// outlines and OSM's station buildings.
///
/// `STATION_ALIGN_REPORT=<file.tsv>` writes the table, one row a station
/// and system (skipped without it); `STATION_ALIGN_ONLY=<part>` measures
/// one part: `taiwan-stations` (the stations with a building), `taiwan-lines`, `hongkong`, `rovaniemi`,
/// `fukuoka`. `tools/station-alignment/README.md` says how to read it.
@MainActor
final class StationAlignmentReportTests: XCTestCase {
    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    // MARK: - The real data

    struct OSMItem: Decodable {
        let id: String
        let tags: [String: String]
        let line: [[Double]]?
        let rings: [[[Double]]]?

        /// Its outlines (or its line), each point (latitude, longitude).
        var shapes: [[[Double]]] { rings ?? line.map { [$0] } ?? [] }
        var isArea: Bool { rings != nil }
        var name: String { tags["name"] ?? tags["name:zh"] ?? tags["ref"] ?? "" }
    }

    struct OSMData: Decodable {
        let platforms: [OSMItem]
        let buildings: [OSMItem]
    }

    static let dataFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tools/station-alignment/data")

    static func osm(_ region: String) throws -> OSMData {
        try JSONDecoder().decode(OSMData.self, from: Data(contentsOf: dataFolder.appendingPathComponent("\(region).json")))
    }

    /// The modes a system's platforms are tagged with in OSM when they are
    /// tagged at all: a platform tagged only for another mode is not this
    /// system's.
    static func isMode(_ item: OSMItem, of system: String) -> Bool {
        let heavy = ["tra_sched", "thsr_sched", "vr", "kyushushinkansen"].contains(system)
        let tagged = ["train", "subway", "light_rail", "monorail", "tram"].filter { item.tags[$0] == "yes" }
        guard !tagged.isEmpty else { return true }
        return heavy ? tagged.contains("train") : !tagged.allSatisfy { $0 == "train" }
    }

    // MARK: - Geometry, in metres of the world's plan

    struct P { var x: Double, y: Double }

    /// A centre line and how far along and across it points lie: along from
    /// its first point (before 0 and past its length on its end
    /// segments' lines), across positive on the right going along.
    struct Axis {
        let points: [P]
        let along: [Double]

        init(_ points: [P]) {
            self.points = points
            var along = [0.0]
            for i in points.indices.dropFirst() { along.append(along[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
            self.along = along
        }

        var length: Double { along.last ?? 0 }

        func project(_ p: P) -> (along: Double, across: Double) {
            var best = (distance: Double.infinity, along: 0.0, across: 0.0)
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
                guard len > 0 else { continue }
                var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len
                if i > 0 { t = max(t, 0) }
                if i < points.count - 2 { t = min(t, len) }
                let fx = a.x + dx / len * t, fy = a.y + dy / len * t
                let distance = hypot(p.x - fx, p.y - fy)
                // The world's y runs south: across is positive to the right.
                let across = ((p.x - a.x) * dy - (p.y - a.y) * dx) / len * -1
                if distance < best.distance { best = (distance, along[i] + t, across) }
            }
            return (best.along, best.across)
        }
    }

    static func inside(_ p: P, _ ring: [P]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    static func distance(_ p: P, toRing ring: [P]) -> Double {
        if inside(p, ring) { return 0 }
        var best = Double.infinity
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            best = min(best, hypot(p.x - a.x - dx * t, p.y - a.y - dy * t))
        }
        return best
    }

    // MARK: - One station measured

    /// A point of the game's track: where in plan (metres) and how far over
    /// the ground.
    struct TrackPoint { let p: P; let overGround: Double }

    struct Row {
        var map: String
        var how: String
        var station: String
        var system: String
        var problem: String = ""
        var gameLength = 0.0
        var gameTracks = 0
        var overGround = 0.0
        var osmPlatforms = 0
        var osmLength = 0.0
        var startShift = 0.0
        var endShift = 0.0
        var middleShift = 0.0
        /// How much of the game's platforms lies past the real ones' ends.
        var outside = 0.0
        var across = 0.0
        var otherGroups = ""
        var trackOnRealPlatform = 0.0
        var traEnds: String = ""
        var buildings: [String] = []
        var onTrack: [String] = []

        var hasOSM: Bool { osmPlatforms > 0 }
        /// The larger of how far the game's platforms reach past the real
        /// ones and how far they stand beside them: the table's order. A
        /// game platform shorter than the real one but within it is 0 along.
        var worst: Double { hasOSM ? max(outside, abs(across)) : -1 }

        static let header = [
            "map", "how", "station", "system", "problem", "game_platform_m", "game_tracks", "over_ground_m",
            "osm_platforms", "osm_length_m", "start_shift_m", "end_shift_m", "middle_shift_m", "outside_real_m", "across_m", "worst_m",
            "other_osm_groups_across_m", "track_through_real_platform_m", "tra_platforms_json_ends_m", "buildings_near", "buildings_on_track",
        ].joined(separator: "\t")

        var line: String {
            func f(_ v: Double) -> String { String(format: "%.1f", v) }
            let osm = hasOSM
            return [
                map, how, station, system, problem, f(gameLength), "\(gameTracks)", f(overGround),
                "\(osmPlatforms)", osm ? f(osmLength) : "", osm ? f(startShift) : "", osm ? f(endShift) : "",
                osm ? f(middleShift) : "", osm ? f(outside) : "", osm ? f(across) : "", osm ? f(worst) : "",
                otherGroups, osm ? f(trackOnRealPlatform) : "", traEnds, buildings.joined(separator: "; "), onTrack.joined(separator: "; "),
            ].joined(separator: "\t")
        }
    }

    /// Measures `station`'s platforms in `world` against OSM's (and, for
    /// the TRA, `tra_platforms.json`'s), and the real buildings near it
    /// against every track of `world` within 400 m.
    static func measure(
        _ row: inout Row, station: StationID, real: RealRailways.Station, in world: GameWorld, osm: OSMData,
        railways: RealRailways, laid: Set<TrackPlatform>? = nil
    ) {
        guard let frame = RealWorldFrame(world: world) else { return }
        func plan(_ latitude: Double, _ longitude: Double) -> P {
            let at = frame.worldPosition(latitude: latitude, longitude: longitude)
            return P(x: at.x / metre, y: at.y / metre)
        }
        func sample(_ edge: TrackEdgeID, from: Int64, to: Int64) -> [TrackPoint] {
            guard let geometry = world.trackGeometry(of: edge) else { return [] }
            var out: [TrackPoint] = []
            var at = from
            let step = 2 * WorldCoordinate.unitsPerMetre
            while true {
                let position = geometry.location(at: min(at, to)).position
                let ground = Double(world.groundHeight(at: position.plan) ?? position.z)
                out.append(TrackPoint(p: P(x: Double(position.x) / metre, y: Double(position.y) / metre), overGround: (Double(position.z) - ground) / metre))
                if at >= to { break }
                at += step
            }
            return out
        }
        // A station two systems share (Hakata): only the platforms the
        // measured line's purchase laid.
        let platforms = world.network.platforms(of: station).filter { laid?.contains($0) ?? true }
        let tracks = platforms.map { sample($0.edge, from: $0.start, to: $0.end) }.filter { $0.count > 1 }
        guard let longest = tracks.max(by: { $0.count < $1.count }) else {
            row.problem = row.problem.isEmpty ? "no platform laid" : row.problem
            return
        }
        let axis = Axis(longest.map(\.p))
        row.gameTracks = tracks.count
        let gameAlong = tracks.flatMap { $0.map { axis.project($0.p).along } }
        let gameAcross = tracks.map { track in track.map { axis.project($0.p).across }.reduce(0, +) / Double(track.count) }
        let g0 = gameAlong.min() ?? 0, g1 = gameAlong.max() ?? 0
        row.gameLength = g1 - g0
        row.overGround = longest[longest.count / 2].overGround
        let gameMiddle = ((gameAcross.min() ?? 0) + (gameAcross.max() ?? 0)) / 2
        let centre = longest[longest.count / 2].p

        // Every track of the world near the station.
        var near: [TrackPoint] = []
        for edge in world.network.edges {
            let points = sample(edge.id, from: 0, to: edge.length)
            if points.contains(where: { hypot($0.p.x - centre.x, $0.p.y - centre.y) < 400 }) { near += points }
        }

        // OSM's platforms: those of this system's mode within 80 m across
        // reaching to within 100 m of the game's platforms, grouped round
        // the nearest.
        struct Candidate { let item: OSMItem; let rings: [[P]]; let a0: Double; let a1: Double; let across: Double }
        var candidates: [Candidate] = []
        // One the game's platform cannot be on: up a floor or more over an
        // underground one, or under the ground beneath a raised one.
        let level = row.overGround
        for item in osm.platforms where isMode(item, of: real.system.id) {
            if let floor = (item.tags["layer"] ?? item.tags["level"]).flatMap({ Double($0.split(separator: ";").first ?? "") }),
               level < -3 && floor > 0 || level > 3 && floor < 0 { continue }
            let rings = item.shapes.map { $0.map { plan($0[0], $0[1]) } }
            guard let first = rings.first?.first, hypot(first.x - centre.x, first.y - centre.y) < 900 else { continue }
            let projected = rings.flatMap { $0.map(axis.project) }
            let a0 = projected.map(\.along).min()!, a1 = projected.map(\.along).max()!
            let across = projected.map(\.across).reduce(0, +) / Double(projected.count)
            guard abs(across) <= 80, a1 >= g0 - 100, a0 <= g1 + 100, a1 - a0 > 10 else { continue }
            candidates.append(Candidate(item: item, rings: item.isArea ? rings : [], a0: a0, a1: a1, across: across))
        }
        if let nearest = candidates.min(by: { abs($0.across - gameMiddle) < abs($1.across - gameMiddle) }) {
            let group = candidates.filter { abs($0.across - nearest.across) <= 30 }
            let a0 = group.map(\.a0).min()!, a1 = group.map(\.a1).max()!
            row.osmPlatforms = group.count
            row.osmLength = a1 - a0
            row.startShift = g0 - a0
            row.endShift = g1 - a1
            row.middleShift = (g0 + g1) / 2 - (a0 + a1) / 2
            row.outside = max(0, a0 - g0) + max(0, g1 - a1)
            let acrosses = group.map(\.across)
            row.across = gameMiddle - ((acrosses.min()! + acrosses.max()!) / 2)
            let others = candidates.filter { abs($0.across - nearest.across) > 30 }
            row.otherGroups = Set(others.map { String(format: "%.0f", $0.across - gameMiddle) }).sorted().joined(separator: ",")
            // How much of the game's track (within its platforms' reach)
            // runs through one of these real platforms.
            let rings = group.flatMap(\.rings)
            let through = near.filter { point in
                let along = axis.project(point.p).along
                return along >= g0 - 50 && along <= g1 + 50 && rings.contains { inside(point.p, $0) }
            }
            row.trackOnRealPlatform = Double(through.count) * 2
        }

        // The app's own TRA data: the station's two farthest platform
        // vertices, along the game's platform.
        if real.system.id == "tra_sched", let extent = railways.stationData?.platform(forStation: real.chinese) {
            let s = axis.project(plan(extent.start.latitude, extent.start.longitude)).along
            let e = axis.project(plan(extent.end.latitude, extent.end.longitude)).along
            row.traEnds = String(format: "%+.0f/%+.0f%@", g0 - min(s, e), g1 - max(s, e), extent.isDerived ? " (derived)" : "")
        }

        // The real buildings: the exterior studies standing within 400 m
        // and OSM's station buildings within 300 m.
        var buildings: [(name: String, rings: [[P]])] = []
        for study in Map3DExteriorStudy.allCases {
            let origin = plan(study.origin.latitude, study.origin.longitude)
            guard hypot(origin.x - centre.x, origin.y - centre.y) < 400 else { continue }
            let rings = study.outlines.map { $0.map { P(x: origin.x + Double($0.0), y: origin.y - Double($0.1)) } }
            buildings.append(("外觀 \(study.rawValue)", rings))
        }
        for landmark in Self.stationLandmarks {
            let origin = plan(landmark.latitude, landmark.longitude)
            guard hypot(origin.x - centre.x, origin.y - centre.y) < 400 else { continue }
            let corners = LandmarkMesh.corners(landmark.body, origin: Map3DPoint(0, 0, 0), rotation: landmark.rotation)
            buildings.append(("地標 \(landmark)", [corners.map { P(x: origin.x + Double($0.x), y: origin.y + Double($0.z)) }]))
        }
        for item in osm.buildings {
            let rings = item.shapes.map { $0.map { plan($0[0], $0[1]) } }
            guard rings.flatMap({ $0 }).contains(where: { hypot($0.x - centre.x, $0.y - centre.y) < 300 }) else { continue }
            if item.tags["building"] == "transportation", item.tags["public_transport"] == nil, item.tags["railway"] == nil,
               !item.name.contains(real.chinese) { continue }
            buildings.append(("OSM \(item.id) \(item.name)", rings))
        }
        for building in buildings {
            var nearest = Double.infinity
            var on: [TrackPoint] = []
            for point in near {
                let d = building.rings.map { distance(point.p, toRing: $0) }.min() ?? .infinity
                nearest = min(nearest, d)
                if d <= 2.2 { on.append(point) }
            }
            row.buildings.append(String(format: "%@ %.0fm", building.name, nearest))
            guard !on.isEmpty else { continue }
            let level = on.filter { $0.overGround > -3 && $0.overGround < 6 }
            let what = level.isEmpty ? "穿過（高架或地下 \(String(format: "%.0f", on[0].overGround)) m）" : "壓軌 \(level.count * 2) m"
            row.onTrack.append("\(building.name) \(what)")
        }
    }

    // MARK: - The worlds

    /// The station landmarks (decisions 370 and 431): buildings the game
    /// draws for a station of a line not on sale.
    static let stationLandmarks: [Map3DTaipeiLandmark] = [.taipeiMainStation, .kaohsiungMainStation]

    static var only: String? { ProcessInfo.processInfo.environment["STATION_ALIGN_ONLY"] }
    static func wanted(_ part: String) -> Bool { only.map { $0 == part } ?? true }

    /// Every real station of `session`'s map bought by itself, one by one,
    /// each on a copy of the world, each of its systems.
    static func stationsBought(
        on session: GameSession, map: String, osm: OSMData, done: inout Set<String>, rows: inout [Row],
        where wanted: (RealRailways.Station) -> Bool
    ) {
        guard let railways = session.railways else { return }
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        for suggestion in session.realStationSuggestions {
            for system in session.realStationSystems(of: suggestion) {
                guard let real = suggestion.stations.first(where: { $0.system.id == system.id }), wanted(real),
                      done.insert(real.id).inserted else { continue }
                var row = Row(map: map, how: "已做站房，收購單站", station: real.chinese, system: system.id)
                let offer = session.realStationOffer(for: suggestion, system: system.id)
                guard let purchase = offer.purchase else {
                    row.problem = offer.problem ?? "not on sale"
                    rows.append(row)
                    continue
                }
                var copy = session.world
                guard let station = try? session.build(purchase, in: &copy) else {
                    row.problem = "not built"
                    rows.append(row)
                    continue
                }
                measure(&row, station: station.id, real: real, in: copy, osm: osm, railways: railways)
                rows.append(row)
            }
        }
    }

    /// Every bundle of lines on sale on `session`'s map bought, one after
    /// another, and each of their stations measured.
    static func linesBought(on session: GameSession, map: String, osm: OSMData, only ids: Set<String>? = nil, rows: inout [Row]) {
        guard let railways = session.railways else { return }
        session.perform { (world: inout GameWorld) throws(GameError) -> String in
            world.setUnlimitedFunds(true)
            return ""
        }
        var tried: Set<String> = []
        var laidBy: [TrackPlatform: String] = [:]
        while let bundle = session.realLineBundles.first(where: { b in
            !tried.contains(b.lines.map(\.id).joined(separator: "+")) && (ids.map { !$0.isDisjoint(with: b.lines.map(\.id)) } ?? true)
        }) {
            let names = bundle.lines.map(\.id).joined(separator: "+")
            tried.insert(names)
            let offer = session.realLineBundleOffer(for: bundle)
            let ok = session.acquireRealLines(offer)
            print("STATION_ALIGN \(map) bought \(names): \(ok), now \(session.world.acquisitions.map(\.realLine).sorted())")
            for platform in session.world.network.platforms where laidBy[platform] == nil { laidBy[platform] = names }
            if !ok {
                rows.append(Row(map: map, how: "收購路線 \(names)", station: "", system: "", problem: offer.problemText(in: .traditionalChinese) ?? session.message?.text ?? "refused"))
            }
        }
        let world = session.world
        for line in bundleLines(of: world) {
            for stop in Set(line.stops) {
                guard let station = world.station(id: stop) else { continue }
                let real = railways.stations.first { $0.system.id == line.system && $0.chinese == station.name }
                    ?? railways.stations.first { $0.chinese == station.name }
                guard let real else { continue }
                var row = Row(map: map, how: "收購路線 \(line.id)", station: station.name, system: real.system.id)
                // The platforms its bundle laid.
                let bundle = laidBy.values.first { $0.split(separator: "+").contains(Substring(line.id)) }
                let laid = Set(laidBy.filter { $0.value == bundle }.keys)
                measure(&row, station: station.id, real: real, in: world, osm: osm, railways: railways, laid: laid)
                rows.append(row)
            }
        }
    }

    /// The lines bought on `world`, each with the system its id names.
    static func bundleLines(of world: GameWorld) -> [(id: String, system: String, stops: [StationID])] {
        world.acquisitions.compactMap { acquisition in
            guard let id = acquisition.line, let line = world.line(id: id) else { return nil }
            let prefix = String(acquisition.realLine.prefix { $0 != ":" })
            let system = prefix == "tra" ? "tra_sched" : prefix == "trtc" ? "mrt" : prefix
            return (acquisition.realLine, system, line.stops)
        }.sorted { $0.id < $1.id }
    }

    // MARK: - The report

    func testReport() throws {
        guard let path = ProcessInfo.processInfo.environment["STATION_ALIGN_REPORT"] else {
            throw XCTSkip("STATION_ALIGN_REPORT=<file.tsv> measures every station's platforms against OSM's (decision 1021)")
        }
        var rows: [Row] = []
        let started = Date()
        if Self.wanted("taiwan-stations") {
            // Chien, 2026-11-27: only the stations of the lines on sale and
            // those not on one whose building the game draws (the exterior
            // studies and the two station landmarks), each bought by itself.
            let osm = try Self.osm("taiwan")
            let railways = try BundledRealData.railways()
            let heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
            var sites: [(name: String, latitude: Double, longitude: Double)] = Map3DExteriorStudy.allCases.map { ($0.rawValue, $0.origin.latitude, $0.origin.longitude) }
            sites += Self.stationLandmarks.map { ("\($0)", $0.latitude, $0.longitude) }
            var done: Set<String> = []
            for site in sites {
                let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: site.latitude, longitudeDegrees: site.longitude))
                var world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 18, height: 1 << 18), balance: Money(100_000_000_000), rules: .simple)
                try world.mapGround()
                let session = GameSession(world: world, language: .traditionalChinese)
                session.railways = railways
                session.heights = heights
                let frame = try XCTUnwrap(RealWorldFrame(world: world))
                let centre = frame.worldPosition(latitude: site.latitude, longitude: site.longitude)
                var siteRows: [Row] = []
                Self.stationsBought(on: session, map: "台灣", osm: osm, done: &done, rows: &siteRows) { real in
                    let at = frame.worldPosition(latitude: real.coordinate.latitude, longitude: real.coordinate.longitude)
                    return hypot(at.x - centre.x, at.y - centre.y) / Self.metre < 400
                }
                rows += siteRows
                print("STATION_ALIGN taiwan site \(site.name): \(siteRows.map { "\($0.station)/\($0.system)" }), \(Int(Date().timeIntervalSince(started))) s")
            }
        }
        if Self.wanted("taiwan-lines") {
            let osm = try Self.osm("taiwan")
            var networks = RealBranchLine.names.keys.sorted()
            // The Taoyuan Airport MRT and the THSR reach past a 32 km world:
            // on the launcher's Taiwan map, below.
            let long = ["tymc:A", ThsrSaleTests.id]
            networks += RealBranchLine.urbanLines.filter { !long.contains("\(RealBranchLine.dataSystem(of: $0.system)):\($0.network)") }.map { "\(RealBranchLine.dataSystem(of: $0.system)):\($0.network)" }
            var measured: Set<String> = []
            for network in networks {
                let session = try RealLineAcquisitionTests.game(round: network, side: 1 << 21, heights: true, rules: .simple)
                let id = network.contains(":") ? network : "tra:\(network)"
                guard !measured.contains(id) else { continue }
                var lineRows: [Row] = []
                Self.linesBought(on: session, map: "台灣", osm: osm, only: [id], rows: &lineRows)
                measured.formUnion(session.world.acquisitions.map(\.realLine))
                rows += lineRows
                print("STATION_ALIGN taiwan line \(id): \(lineRows.count) rows, \(Int(Date().timeIntervalSince(started))) s")
            }
            // THSR-SALE (decision 993): the high-speed line, Nangang to
            // Zuoying, on the launcher's Taiwan map.
            for id in long {
                let session = try ThsrSaleTests.game(at: 25.047882, 121.517219)
                Self.linesBought(on: session, map: "台灣", osm: osm, only: [id], rows: &rows)
            }
            print("STATION_ALIGN taiwan THSR: \(Int(Date().timeIntervalSince(started))) s")
        }
        let overseas: [(part: String, map: String, region: String, open: () throws -> GameSession)] = [
            ("hongkong", "香港", "hong_kong", { try HongKongMapTests.hongKong() }),
            ("rovaniemi", "羅瓦涅米", "lapland", { try RovaniemiRailwaysTests.rovaniemi() }),
            ("fukuoka", "福岡", "kyushu", { try FukuokaRailwaysTests.fukuoka() }),
        ]
        for city in overseas where Self.wanted(city.part) {
            let osm = try Self.osm(city.region)
            var cityRows: [Row] = []
            Self.linesBought(on: try city.open(), map: city.map, osm: osm, rows: &cityRows)
            // The Nishi-Kyushu Shinkansen is bought from a game started by
            // it (NishiKyushuShinkansenTests): its land joins none of the
            // first start's.
            if city.part == "fukuoka" {
                let id = "kyushushinkansen:NK"
                cityRows.removeAll { $0.how == "收購路線 \(id)" && !$0.problem.isEmpty }
                Self.linesBought(on: try FukuokaRailwaysTests.fukuoka(start: 3), map: city.map, osm: osm, only: [id], rows: &cityRows)
            }
            rows += cityRows
            print("STATION_ALIGN \(city.part): \(Int(Date().timeIntervalSince(started))) s")
        }
        let sorted = rows.sorted { $0.worst > $1.worst }
        try ([Row.header] + sorted.map(\.line)).joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("STATION_ALIGN \(rows.count) rows to \(path) in \(Int(Date().timeIntervalSince(started))) s")
    }
}
