import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The real-world demo on the ground (decision 132): the Yilan, Western
/// Trunk, Pingxi and Shenao Lines built over the app's heights, level at
/// the stations, the automatic structure making the rest embankment,
/// cutting, viaduct, bridge or tunnel; TRA's Pingxi Line trains at their
/// real times (decision 133) and the Yilan and trunk lines at a headway, five
/// trains in all. Each
/// test builds it again (each runs on its own), so there are few of them.
final class RealWorldDemoGroundTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func resource(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/\(path)"))
    }

    private static func railways() throws -> RealRailways {
        try RealRailways(
            lines: resource("RealRailways/track_lines.geojson"), stations: resource("RealRailways/track_stations.geojson"),
            names: resource("RealRailways/station_names.json"),
            pingxiRuns: RealLineRuns(data: resource("RealRailways/tra_pingxi_runs.json"))
        )
    }

    /// The demo as the app opens it, with its water, steep slopes and
    /// heights; built once for every test here (it takes some seconds in a
    /// debug build).
    private static let built: Result<(RealRailways, GameWorld), Error> = Result {
        let railways = try RealWorldDemoGroundTests.railways()
        let heights = try HeightGrid(data: RealWorldDemoGroundTests.resource("RealWorld/taiwan_heights.dat"))
        let water = try WaterGrid(data: RealWorldDemoGroundTests.resource("RealWorld/taiwan_water.json"))
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let world = RealWorldDemo.make(
            in: .traditionalChinese, railways: railways, water: water.cells(frame: frame, bounds: GameWorld.newGameBounds),
            steep: water.steepCells(frame: frame, bounds: GameWorld.newGameBounds), heights: heights
        )
        return (railways, world)
    }

    private static let names = [
        "七堵", "八堵", "暖暖", "四腳亭", "瑞芳", "猴硐", "三貂嶺", "牡丹", "三坑", "基隆", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐", "海科館", "八斗子",
    ]

    // MARK: - On the ground

    func testTheTrackStandsOnTheGroundItRead() throws {
        let (_, world) = try Self.built.get()
        XCTAssertTrue(world.ground.isMapped)
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance, "what it built was added to a new game's money, and paid")
        XCTAssertTrue(world.network.edges.allSatisfy { $0.structure == .automatic && $0.profile == .uniform })
        // The ground decides what carries it: every kind is somewhere on
        // these hill lines, and most of it is on the ground.
        var lengths: [TrackSectionKind: Int] = [:]
        for edge in world.network.edges {
            for section in edge.sections {
                lengths[section.kind, default: 0] += section.lengths
            }
        }
        XCTAssertEqual(Set(lengths.keys), Set(TrackSectionKind.allCases), "\(lengths)")
        let onGround = [TrackSectionKind.surface, .embankment, .cutting].map { lengths[$0] ?? 0 }.reduce(0, +)
        XCTAssertGreaterThan(onGround * 2, lengths.values.reduce(0, +), "\(lengths)")
        // Every node within the game's reach of the ground, and every edge
        // measured over ground read.
        for node in world.network.nodes {
            let ground = try XCTUnwrap(world.groundHeight(at: node.position.plan))
            XCTAssertTrue(RailwayNetwork.heightRange.contains(node.position.z - ground), "node \(node.id)")
        }
        for edge in world.network.edges {
            XCTAssertNotNil(world.longSection(of: edge.id), "\(edge.id)")
        }
        // A station's platforms are level and near the ground where it
        // stands.
        for station in world.stations {
            let platforms = world.trackPlatforms(of: station.id)
            XCTAssertFalse(platforms.isEmpty, station.name)
            let ground = try XCTUnwrap(world.groundHeight(at: station.point))
            for platform in platforms {
                let geometry = try XCTUnwrap(world.trackGeometry(of: platform.edge))
                let rail = geometry.height(at: platform.start)
                XCTAssertEqual(rail, geometry.height(at: platform.end), station.name)
                XCTAssertLessThanOrEqual(abs(rail - ground), 20 * 64, "\(station.name) stands \((rail - ground) / 64) m off the ground")
            }
        }
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world, "it saves and loads")
    }

    // MARK: - What it builds

    func testTheLinesRunLongerWithMoreTrains() throws {
        let (railways, world) = try Self.built.get()
        XCTAssertEqual(world.geoAnchor, RealWorldDemo.anchor)
        XCTAssertEqual(world.stations.map(\.name), Self.names)
        // A second platform on the passing loops at Qidu, Sijiaoting,
        // Ruifang, Houtong, Sandiaoling, Mudan, Sankeng and Shifen, and on
        // the trunk line's own track at Badu; a third on Ruifang's second
        // loop, where the Pingxi trains wait between runs.
        XCTAssertEqual(world.stations.map { world.trackPlatforms(of: $0.id).count }, [2, 2, 1, 2, 3, 2, 2, 2, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1])

        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        XCTAssertEqual(world.lines.map(\.name), ["平溪線", "宜蘭線", "縱貫線"])
        XCTAssertEqual(world.lines[0].stops, ["八斗子", "海科館", "瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[1].stops, ["牡丹", "三貂嶺", "猴硐", "瑞芳", "四腳亭", "暖暖", "八堵", "七堵"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[2].stops, ["七堵", "八堵", "三坑", "基隆"].compactMap { ids[$0] })
        // Decision 133: the Pingxi Line runs TRA's trains, 38 and a
        // positioning run, with three trainsets standing at Shifen,
        // Ruifang (on its second loop) and Jingtong at midnight. The Yilan
        // Line runs one train, so two of its own never meet at Ruifang
        // while Pingxi trains wait there; the trunk line's long single
        // track from Qidu to Sankeng takes one.
        let pingxi = world.lines[0]
        XCTAssertEqual(pingxi.runs.count, 39)
        XCTAssertEqual(pingxi.runs.count { $0.runs(onDay: 0) }, 34, "a Monday's trains")
        XCTAssertEqual(pingxi.routePreferences.map { [$0.from, $0.to] }, [[1, 2], [3, 2]], "into Ruifang on its second loop")
        XCTAssertEqual(world.lines.dropFirst().map(\.trainsInService.peak), [1, 1])
        XCTAssertEqual(world.lines.dropFirst().map { world.lineMaximumTrains($0.id) }, [3, 1])
        XCTAssertEqual(world.trains.map(\.name), ["平溪線列車 1", "平溪線列車 2", "平溪線列車 3", "宜蘭線列車 1", "縱貫線列車 1"])
        XCTAssertTrue(world.trains.allSatisfy { $0.cars == RealWorldDemo.cars })
        XCTAssertEqual(Set(pingxi.trains.flatMap { world.stationsStoppedAt(by: $0) }), Set(["十分", "瑞芳", "菁桐"].compactMap { ids[$0] }))
        for line in world.lines.dropFirst() {
            for train in line.trains {
                XCTAssertEqual(world.stationsStoppedAt(by: train), [line.stops[0]], "\(line.name): its trains stand at its first call")
            }
        }
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)

        // Each station stands on its real line, within 60 m of the real one.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for station in world.stations {
            let real = try XCTUnwrap(railways.stations.first { $0.system.id == "tra_sched" && $0.name(in: .traditionalChinese) == station.name })
            let point = frame.worldPosition(latitude: real.coordinate.latitude, longitude: real.coordinate.longitude)
            let away = ((Double(station.point.x) - point.x) * (Double(station.point.x) - point.x)
                + (Double(station.point.y) - point.y) * (Double(station.point.y) - point.y)).squareRoot() / 64
            XCTAssertLessThan(away, 60, "\(station.name) is \(away) m from the real one")
        }

        // Every node joins the edges on either side, so trains run the
        // whole way; the five ends are Qidu and Mudan on the main track,
        // Keelung, Jingtong and Badouzi. At the ends of Ruifang's and
        // Sandiaoling's loops the Shenao and Pingxi Lines leave: the main
        // track either way, the loop and the branch.
        for node in world.network.nodes where node.ends.count > 1 {
            XCTAssertTrue(node.ends.allSatisfy { !$0.exits.isEmpty }, "every edge at node \(node.id) goes on")
        }
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 1 }.count, 5)
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 4 }.count, 2, "Ruifang's east end and Sandiaoling's south end")
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 5 }.count, 1, "Ruifang's west end, where the Shenao Line leaves too")
        // The trunk line's trains take the platform on their own track at
        // Badu, which goes on to Keelung.
        let trunk = world.lines[2]
        XCTAssertEqual(trunk.routePreferences.map { [$0.from, $0.to] }, [[0, 1], [2, 1]])
        XCTAssertNotNil(world.lineJourney(trunk.id))
    }

    // MARK: - Running

    /// The night is quiet; at 04:15 the positioning run takes the train at
    /// Shifen to Ruifang, and at 05:07 the first of TRA's trains leaves
    /// Ruifang for Jingtong; at 05:00 the Yilan and trunk lines begin.
    /// Passengers ride, and nothing waits for itself.
    func testTheDayBeginsWithTheRealTrains() throws {
        var (_, world) = try Self.built.get()
        let pingxi = world.lines[0].id
        try world.advance(ticks: 250)
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil }, "nothing runs at night")
        try world.advance(ticks: 80)
        let line = try XCTUnwrap(world.line(id: pingxi))
        let first = try XCTUnwrap(line.runs.firstIndex { $0.times[0].departure == 15_300 })
        let morning = try XCTUnwrap(line.runs.firstIndex { $0.times[0].departure == 18_420 })
        XCTAssertEqual(line.runDays[first], 0, "the positioning run went")
        XCTAssertEqual(line.runDays[morning], 0, "train 4704 left Ruifang")
        XCTAssertTrue(world.lines.dropFirst().allSatisfy { $0.lastDispatch != nil }, "the Yilan and trunk lines began")
        XCTAssertEqual(world.deadlockedTrains(), [])
        try world.advance(ticks: 60)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertGreaterThan(world.stations.map { world.passengerLedger(of: $0.id).arrived }.reduce(0, +), 0, "passengers rode")
    }

    /// Without the app's heights it is the flat demo, as before.
    func testWithoutHeightsItIsTheFlatDemo() throws {
        let railways = try Self.railways()
        let world = RealWorldDemo.make(in: .english, railways: railways)
        XCTAssertFalse(world.ground.isMapped)
        XCTAssertEqual(world, RealWorldDemo.makeFlat(in: .english, railways: railways))
    }
}
