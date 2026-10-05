import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The real-world demo (2026-10-05, the author's request): Taiwan's Pingxi,
/// Yilan and Shenao Lines built as the game's own track on their real
/// alignments, with ordinary commands, and running at once.
final class RealWorldDemoTests: XCTestCase {
    private static func bundledRailways() throws -> RealRailways {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        return try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
    }

    /// Built once for every test here: building it takes seconds in a debug
    /// build.
    private static let built: Result<(RealRailways, GameWorld), Error> = Result {
        let railways = try bundledRailways()
        return (railways, RealWorldDemo.make(in: .traditionalChinese, railways: railways))
    }

    // MARK: - Where the world lies

    /// A point's place in the world is the same as on the app's map: the
    /// anchor at the middle, a metre at the anchor's latitude 64 units, east
    /// along x and south along y.
    func testTheEarthLiesOverTheWorldAsTheMapShowsIt() throws {
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let middle = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees, longitude: RealWorldDemo.anchor.longitudeDegrees)
        XCTAssertEqual(middle.x, 524_288, accuracy: 1e-6)
        XCTAssertEqual(middle.y, 524_288, accuracy: 1e-6)
        // A kilometre east at the anchor's latitude: a hundredth of a degree
        // of longitude is 1,007.6 m at 25.08°.
        let east = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees, longitude: RealWorldDemo.anchor.longitudeDegrees + 0.01)
        let metres = 0.01 * .pi / 180 * 6_378_137 * cos(25.0805 * .pi / 180)
        XCTAssertEqual((east.x - 524_288) / 64, metres, accuracy: 1e-6)
        XCTAssertEqual(east.y, 524_288, accuracy: 1e-6)
        // North is up the map, so a smaller y; and the frame's own metres
        // agree with it.
        let north = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees + 0.01, longitude: RealWorldDemo.anchor.longitudeDegrees)
        XCTAssertLessThan(north.y, 524_288)
        XCTAssertEqual(frame.metresFromAnchor(worldX: north.x, worldY: north.y).south, (north.y - 524_288) / 64, accuracy: 1e-9)
    }

    // MARK: - What it builds

    func testTheRealLinesAreBuiltAsTheGamesTrack() throws {
        let (railways, world) = try Self.built.get()
        XCTAssertEqual(world.geoAnchor, RealWorldDemo.anchor)
        XCTAssertEqual(world.stations.map(\.name), ["四腳亭", "瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐", "海科館", "八斗子"])
        // A platform at each, and a second on a passing loop at Ruifang,
        // Houtong, Sandiaoling and Shifen.
        XCTAssertEqual(world.stations.map { world.trackPlatforms(of: $0.id).count }, [1, 2, 2, 2, 1, 2, 1, 1, 1, 1, 1, 1])
        XCTAssertTrue(world.network.edges.allSatisfy { $0.structure == .surface && $0.profile == .uniform }, "all on the ground")

        // Each station stands on its real line, within 60 m of the real
        // station: its platform lies on the track nearest it, and at the
        // ends of the lines, where the site's line ends at the station,
        // stops short of the end.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for station in world.stations {
            let real = try XCTUnwrap(railways.stations.first { $0.system.id == "tra_sched" && $0.name(in: .traditionalChinese) == station.name })
            let point = frame.worldPosition(latitude: real.coordinate.latitude, longitude: real.coordinate.longitude)
            let away = ((Double(station.point.x) - point.x) * (Double(station.point.x) - point.x)
                + (Double(station.point.y) - point.y) * (Double(station.point.y) - point.y)).squareRoot() / 64
            XCTAssertLessThan(away, 60, "\(station.name) is \(away) m from the real one")
        }

        XCTAssertEqual(world.lines.map(\.name), ["平溪線", "宜蘭線", "深澳線"])
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        XCTAssertEqual(world.lines[0].stops, ["瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[1].stops, ["四腳亭", "瑞芳", "猴硐", "三貂嶺"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[2].stops, ["八斗子", "海科館", "瑞芳"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines.map(\.trainsInService.peak), [2, 1, 1])
        XCTAssertEqual(world.trains.map(\.name), ["平溪線列車 1", "平溪線列車 2", "宜蘭線列車 1", "深澳線列車 1"])
        XCTAssertEqual(world.trains.map(\.cars), [3, 3, 3, 3])
        for train in world.trains {
            XCTAssertFalse(world.stationsStoppedAt(by: train.id).isEmpty, "\(train.name) stands at its first platform")
        }

        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance, "what it built was added to a new game's money, and paid")
        XCTAssertEqual(RealWorldDemo.lineNames(in: .english), ["Pingxi Line", "Yilan Line", "Shenao Line"])
        XCTAssertEqual(RealWorldDemo.trainName(line: "Pingxi Line", number: 2, in: .english), "Pingxi Line Train 2")
    }

    /// Every node joins the edges on either side (their directions agree),
    /// so trains run the whole way: from Sijiaoting to Jingtong, and from
    /// Badouzi into Ruifang's platforms.
    func testTheTrackRunsThrough() throws {
        let (_, world) = try Self.built.get()
        // Every edge at a node goes on from it, but at the three terminals.
        for node in world.network.nodes where node.ends.count > 1 {
            XCTAssertTrue(node.ends.allSatisfy { !$0.exits.isEmpty }, "every edge at node \(node.id) goes on")
        }
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 1 }.count, 3, "Sijiaoting, Jingtong and Badouzi")
        // The junction west of Ruifang: the Yilan Line west, the main track
        // and the loop east, and the Shenao Line.
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 4 }.count, 1)
    }

    // MARK: - Running

    func testTheDemoRunsAtOnce() throws {
        var (_, world) = try Self.built.get()
        // A tick is a game minute at a new game's speed: an hour.
        try world.advance(ticks: 60)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertTrue(world.lines.allSatisfy { $0.lastDispatch != nil }, "every line sent its trains out")
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        let shenao = try XCTUnwrap(world.train(id: world.lines[2].trains[0]))
        XCTAssertTrue(shenao.timetable.contains { $0.station == ids["瑞芳"] }, "the Shenao Line's train runs through the junction to Ruifang")
        let carried = world.stations.map { world.passengerLedger(of: $0.id).arrived }.reduce(0, +)
        XCTAssertGreaterThan(carried, 0, "passengers rode")
    }
}
