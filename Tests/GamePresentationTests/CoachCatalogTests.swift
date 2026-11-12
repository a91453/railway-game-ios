import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// The coach stops a real-world map gets (decision 706).
final class CoachCatalogTests: XCTestCase {
    private static let taipei = GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219)

    private func network() throws -> CoachNetwork {
        try CoachNetwork(data: RealWorldDataLoadTests.file("coach_network", "json"))
    }

    func testTheFileReads() throws {
        let network = try network()
        XCTAssertEqual(network.hubs.count, 934)
        XCTAssertEqual(network.hubs.reduce(0) { $0 + $1.links.count }, 11_546)
        let city = try XCTUnwrap(network.hubs.first { $0.name == "市府轉運站" })
        XCTAssertEqual(city.coaches, 1_603)
        XCTAssertEqual(city.coordinate.latitude, 25.04079, accuracy: 0.0001)
        XCTAssertEqual(city.coordinate.longitude, 121.56444, accuracy: 0.0001)
        // To Keelung's, 26 minutes for NT$ 57 on 169 coaches a Wednesday.
        let keelung = try XCTUnwrap(network.hubs.firstIndex { $0.name == "基隆轉運站" })
        let link = try XCTUnwrap(city.links.first { $0.to == keelung })
        XCTAssertEqual([link.coaches, link.minutes, link.fare], [169, 26, 56])
        for hub in network.hubs {
            XCTAssertLessThanOrEqual(hub.links.count, 16, hub.name)
            XCTAssertEqual(hub.hours.count, 24, hub.name)
            // A link leads at least 10 km away.
            for link in hub.links {
                XCTAssertGreaterThan(hub.coordinate.distance(to: network.hubs[link.to].coordinate), 9_990, hub.name)
            }
        }
        XCTAssertEqual(RealWorldData.load(file: RealWorldDataLoadTests.file).coaches, network)
    }

    func testARealMapGetsTheStopsInsideIt() throws {
        let network = try network()
        var world = GameWorld.newGame(anchor: Self.taipei)
        XCTAssertEqual(world.coachStops, [], "a new game has none until the launcher gives them")
        let given = CoachCatalog.withCoachStops(world, network: network)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let inside = network.hubs.filter {
            let position = frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            return position.x >= 0 && position.y >= 0 && position.x < Double(world.bounds.width) && position.y < Double(world.bounds.height)
        }
        XCTAssertGreaterThan(inside.count, 0)
        XCTAssertEqual(given.coachStops.count, min(inside.count, CoachRules.maximumStops))
        XCTAssertEqual(given.coachStops.map(\.id), Array(1 ... given.coachStops.count))
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(SavedGame(world: given))))
        // Taipei Bus Station: its coach loads at 24 passengers a coach.
        let station = try XCTUnwrap(given.coachStops.first { $0.name == "臺北轉運站" })
        let hub = try XCTUnwrap(network.hubs.first { $0.name == "臺北轉運站" })
        XCTAssertEqual(station.dailyCoaches, hub.coaches)
        XCTAssertEqual(station.dailyPassengers, (hub.boarding + hub.alighting) * 24 / 100)
        for stop in given.coachStops {
            XCTAssertLessThanOrEqual(stop.links.count, CoachRules.maximumLinks)
            XCTAssertTrue(stop.links.allSatisfy { $0.to != stop.id && (1 ... given.coachStops.count).contains($0.to) }, stop.name)
        }
        // Given again, nothing changes; a counted day is kept.
        XCTAssertEqual(CoachCatalog.withCoachStops(given, network: network), given)
        world = given
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertEqual(world.coachStops.first { $0.name == "臺北轉運站" }?.yesterdayPassengers, station.dailyPassengers * 1_090 / 1_000,
                       "a new game begins on a holiday")
        XCTAssertEqual(CoachCatalog.withCoachStops(world, network: network).coachStops, world.coachStops)
    }

    func testABlankMapGetsNone() throws {
        let world = GameWorld.newGame()
        XCTAssertEqual(CoachCatalog.withCoachStops(world, network: try network()), world)
    }

    func testTheSentences() throws {
        let stop = CoachStop(id: 1, name: "站", point: PlanPoint(x: 1, y: 1), dailyCoaches: 100, dailyPassengers: 2_400,
                             hours: Array(repeating: 1, count: 24))
        var world = GameWorld.newGame(anchor: Self.taipei)
        world.setCoachStops([stop])
        // A new game begins on a holiday: 1,090 thousandths of a weekday.
        let day = try XCTUnwrap(world.coachDays().first)
        XCTAssertEqual(day.summary(in: .english),
                       "109 coaches call today, with 2,616 passengers getting on and off. None of them ride your trains yet: this station needs a line to stations where people live.")
        XCTAssertEqual(day.summary(in: .traditionalChinese), "今天 109 班客運停靠，2,616 人上下車。還沒有人轉搭你的車：這一站要有路線通到有人住的車站。")
        XCTAssertNil(stop.yesterdayText(in: .english))
    }

    func testAFileOutOfShapeIsRefused() throws {
        let good = #"{"schema":1,"scale":100000,"hubs":[{"name":"a","x":12100000,"y":2500000,"coaches":9,"boarding":100,"alighting":100,"hours":[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"links":[0,9,30,60]}]}"#
        XCTAssertEqual(try CoachNetwork(data: Data(good.utf8)).hubs.count, 1)
        func refused(_ old: String, _ new: String, line: UInt = #line) {
            XCTAssertTrue(good.contains(old), old, line: line)
            XCTAssertThrowsError(try CoachNetwork(data: Data(good.replacingOccurrences(of: old, with: new).utf8)), new, line: line)
        }
        refused(#""schema":1"#, #""schema":2"#)
        refused(#""coaches":9"#, #""coaches":0"#)
        refused(#""links":[0,9,30,60]"#, #""links":[1,9,30,60]"#)
        refused(#""links":[0,9,30,60]"#, #""links":[0,9,30]"#)
        refused(#""hours":[1,"#, #""hours":["#)
    }
}
