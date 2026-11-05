import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HEIGHT-STUDY (docs/research/LINE_HEIGHTS_2026-11-05.md): buys each of
/// the fourteen real lines on sale, on a world round the line that reads
/// the water and the heights (as ``AcquisitionReportTests`` plays them),
/// and prints, every 64 m along its main track, what the game built
/// there (tunnel, ground or viaduct, and how far over the ground) beside
/// the real line: its structures (`rail_structures.json`, decision 279)
/// and its tracks' heights (`rail_tracks.json`, decision 402); then each
/// station's platforms the same way. Run only when asked
/// (`LINE_HEIGHT_REPORT=1`; `LINE_HEIGHT_ONLY=<id>` for one line). The
/// lines `HEIGHT_SAMPLE`, `HEIGHT_STATION` and `HEIGHT_LINE` are read by
/// the study's summary script.
@MainActor
final class LineHeightReportTests: XCTestCase {
    static let networks = [
        "PINGXI", "JIJI", "NEIWAN", "SHENAO", "LIUJIA", "SHALUN",
        "ntdlrt:V", "ntdlrt:VB", "ntalrt:K", "trtc:R_XBT", "trtc:G_XBT", "sanying:LB", "trtc:BR", "tymc:A",
    ]

    /// The real opening each city line is bought on.
    static let cities = [
        "ntdlrt:V": "New Taipei, Tamsui", "ntdlrt:VB": "New Taipei, Tamsui", "ntalrt:K": "New Taipei, Banqiao", "trtc:R_XBT": "Taipei",
        "trtc:G_XBT": "Taipei", "sanying:LB": "New Taipei, Banqiao", "trtc:BR": "Taipei", "tymc:A": "Taoyuan",
    ]

    func testTheLinesHeights() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LINE_HEIGHT_REPORT"] != nil else {
            throw XCTSkip("Set LINE_HEIGHT_REPORT=1 to measure the real lines' heights.")
        }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let structures = try XCTUnwrap(railways.structures)
        let tracks = try XCTUnwrap(railways.tracks)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        for network in Self.networks where environment["LINE_HEIGHT_ONLY"].map({ $0 == network }) ?? true {
            var out: [String] = []
            let runs = try XCTUnwrap(railways.branchRuns[network] ?? railways.metroRuns[network])
            let prefix = String(network.prefix { $0 != ":" })
            let system = railways.branchRuns[network] != nil ? RealBranchLine.tra : prefix == "trtc" ? "mrt" : prefix
            let stations = try runs.stops.map { try BundledRealData.station($0, in: system) }
            let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
            let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
            let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
            // Where a player buys it: a city line on its city's real
            // opening (``AcquisitionReportTests/cities``), a branch line on
            // a real-world game started at its middle; both read the land,
            // the water and the heights of the whole map, and the tiles the
            // line reaches past it are bought and read with it. Built on a
            // pricing copy, so the opening's cash does not matter.
            // `LINE_HEIGHT_CENTRED=1`: on the tests' map round the line
            // instead (``AcquisitionReportTests``), which reads no water.
            let city = Self.cities[network].flatMap { name in AcquisitionReportTests.cities.first { $0.name == name } }
            let start = try city.map { try XCTUnwrap(GeoAnchor(latitudeDegrees: $0.latitude, longitudeDegrees: $0.longitude)) } ?? anchor
            let session: GameSession
            if environment["LINE_HEIGHT_CENTRED"] == nil {
                let world = GameLauncher.newWorld(at: start, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                    population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
                ))
                session = GameSession(world: world, language: .traditionalChinese)
                session.coverage = data.coverage
            } else {
                let side: Int64 = network == "tymc:A" ? 1 << 22 : 1 << 21
                var world = GameWorld.newGame(
                    anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: Money(500_000_000_000), land: [], rules: .simple
                )
                world.setLandOnDemand()
                world.setRealTransfers(true)
                try world.mapGround()
                session = GameSession(world: world, language: .traditionalChinese)
            }
            session.railways = railways
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network || $0.id == network }, network)
            let offer = session.realLineOffer(for: line)
            let acquisition = try XCTUnwrap(offer.acquisition, "\(network): \(offer.problem ?? "")")
            var built = session.world.pricingCopy()
            _ = try session.buildStepByStep(acquisition, in: &built, recording: false)
            let frame = try XCTUnwrap(RealWorldFrame(world: built))
            out.append("HEIGHT_LINE \(network) opening=\(city?.name.replacingOccurrences(of: " ", with: "_") ?? "middle") system=\(line.system) grade=\(line.rulingGrade) price=\(offer.price?.total.amount ?? 0) building=\(offer.price?.building.amount ?? 0)")

            // The main track's path, the real structures along it.
            let path = WorldPath(acquisition.pieces[0].nodes.map { WorldVector(x: Double($0.x), y: Double($0.y)) })
            let carried = structures.stretches(along: path, frame: frame, system: line.system)
            out.append("HEIGHT_CARRIED \(network) " + carried.map {
                "\($0.kind == .tunnel ? "t" : "b"):\(Int($0.range.lowerBound / metre))-\(Int($0.range.upperBound / metre)):\(Int($0.length / metre))"
            }.joined(separator: " "))
            // Every point of the track the game laid (not its depots'),
            // with its section's kind and its height over the ground.
            let depotIDs = Set(built.stations.filter(\.isDepot).map(\.id))
            let depotEdges = Set(built.network.platforms.filter { depotIDs.contains($0.station) }.map(\.edge))
            var laid: [(point: WorldVector, z: Double, kind: TrackSectionKind)] = []
            for edge in built.network.edges where !depotEdges.contains(edge.id) {
                let geometry = try XCTUnwrap(built.trackGeometry(of: edge.id))
                for span in edge.sectionSpans where span.end > span.start {
                    for point in geometry.points(from: span.start, to: span.end) {
                        laid.append((WorldVector(x: Double(point.x), y: Double(point.y)), Double(point.z), span.kind))
                    }
                }
            }
            // The real line's tracks near the path, as segments in world
            // units with the height (metres over the ground) at each end.
            let xs = path.points.map(\.x), ys = path.points.map(\.y)
            let margin = 200 * metre
            let box = (x: (xs.min()! - margin)...(xs.max()! + margin), y: (ys.min()! - margin)...(ys.max()! + margin))
            var segments: [(a: WorldVector, b: WorldVector, ha: Double, hb: Double, kind: RealRailTracks.Kind)] = []
            for track in tracks.tracks where track.system == line.system {
                let points = track.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
                for index in points.indices.dropLast() {
                    let a = points[index], b = points[index + 1]
                    guard max(a.x, b.x) >= box.x.lowerBound, min(a.x, b.x) <= box.x.upperBound,
                          max(a.y, b.y) >= box.y.lowerBound, min(a.y, b.y) <= box.y.upperBound else { continue }
                    segments.append((a, b, track.heights[index], track.heights[index + 1], track.kind))
                }
            }
            func real(at point: WorldVector) -> (kind: RealRailTracks.Kind, height: Double, off: Double)? {
                var best: (kind: RealRailTracks.Kind, height: Double, off: Double)?
                for segment in segments {
                    let d = segment.b - segment.a
                    let lengthSquared = d.dot(d)
                    let t = lengthSquared > 0 ? max(0, min(1, (point - segment.a).dot(d) / lengthSquared)) : 0
                    let off = (point - (segment.a + d * t)).length / metre
                    if off < (best?.off ?? 40) {
                        best = (segment.kind, segment.ha + (segment.hb - segment.ha) * t, off)
                    }
                }
                return best
            }
            func ground(at point: WorldVector) -> Double {
                Double(built.groundHeight(at: PlanPoint(x: Int64(point.x.rounded()), y: Int64(point.y.rounded()))) ?? 0) / metre
            }
            func wet(_ point: WorldVector) -> Bool {
                built.terrain.isWater(row: Int(point.y / Double(Land.cellLength)), column: Int(point.x / Double(Land.cellLength)))
            }
            func game(at point: WorldVector) -> (kind: TrackSectionKind, over: Double, off: Double)? {
                guard let nearest = laid.min(by: { ($0.point - point).length < ($1.point - point).length }) else { return nil }
                return (nearest.kind, nearest.z / metre - ground(at: nearest.point), (nearest.point - point).length / metre)
            }
            func structure(at distance: Double) -> String {
                guard let stretch = carried.first(where: { $0.range.contains(distance) }) else { return "-" }
                let length = (stretch.length / metre).rounded()
                return "\(stretch.kind == .tunnel ? "tunnel" : "bridge"):\(Int(length))"
            }

            // The line's stations along the path.
            // (The pricing copy keeps no acquisition: its stations near the
            // path, which a new game has no others of.)
            let own = Set(built.stations.filter { !$0.isDepot && path.nearest(WorldVector($0.location)).away <= 300 * metre }.map(\.id))
            for station in built.stations where own.contains(station.id) {
                let at = path.nearest(WorldVector(station.location)).along / metre
                let platforms = built.network.platforms(of: station.id)
                var parts: [String] = []
                for platform in platforms {
                    guard let edge = built.network.edge(platform.edge), let geometry = built.trackGeometry(of: platform.edge) else { continue }
                    let middle = (platform.start + platform.end) / 2
                    let kind = edge.sectionSpans.first { $0.start <= middle && middle <= $0.end }?.kind
                    let point = geometry.points(from: middle, to: min(middle + 1, geometry.length)).first!
                    let position = WorldVector(x: Double(point.x), y: Double(point.y))
                    parts.append("\(kind?.rawValue ?? "?"):\(String(format: "%.1f", Double(point.z) / metre - ground(at: position)))")
                }
                let realHere = real(at: WorldVector(station.location))
                let place = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
                out.append(
                    "HEIGHT_STATION \(network) \(station.name) at=\(Int(at)) ll=\(String(format: "%.6f,%.6f", place.latitude, place.longitude)) platforms=\(parts.joined(separator: ",")) real=\(realHere.map { "\($0.kind.rawValue):\(String(format: "%.1f", $0.height)):off\(Int($0.off))" } ?? "none") structure=\(structure(at: at * metre))"
                )
            }
            for distance in stride(from: 0, through: path.length, by: 64 * metre) {
                let point = path.point(at: distance)
                guard let here = game(at: point) else { continue }
                let realHere = real(at: point)
                let place = frame.coordinate(worldX: point.x, worldY: point.y)
                out.append(
                    "HEIGHT_SAMPLE \(network) d=\(Int(distance / metre)) ll=\(String(format: "%.6f,%.6f", place.latitude, place.longitude)) game=\(here.kind.rawValue):\(String(format: "%.1f", here.over)):off\(Int(here.off)) real=\(realHere.map { "\($0.kind.rawValue):\(String(format: "%.1f", $0.height)):off\(Int($0.off))" } ?? "none") structure=\(structure(at: distance)) ground=\(String(format: "%.1f", ground(at: point))) water=\(wet(point) ? 1 : 0)"
                )
            }
            FileHandle.standardError.write(Data((out.joined(separator: "\n") + "\n").utf8))
        }
    }
}
