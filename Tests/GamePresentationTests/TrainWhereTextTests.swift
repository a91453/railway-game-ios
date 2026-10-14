import GameCore
@testable import GamePresentation
import XCTest

/// Author's report, 2026-10-14: the train card said "Track #1 backward,
/// 11264 units along". It says where the train is by its stations, and how
/// far it has left in metres or kilometres.
final class TrainWhereTextTests: XCTestCase {
    func testEveryPlacedTrainIsPlacedByAStationNotByItsTrack() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 120)
        let names = Set(world.stations.map(\.name))
        var placed = 0
        for train in world.trains where train.position != nil {
            placed += 1
            let english = try XCTUnwrap(world.trainWhereText(of: train.id, in: .english))
            XCTAssertTrue(names.contains { english == "Near \($0)" || english.hasSuffix(" from \($0)") }, english)
            let chinese = try XCTUnwrap(world.trainWhereText(of: train.id, in: .traditionalChinese))
            XCTAssertTrue(chinese.hasPrefix("在 ") || chinese.hasPrefix("距 "), chinese)
            for text in [english, chinese, world.trainPathStatusText(of: train.id, in: .english),
                         world.trainPathStatusText(of: train.id, in: .traditionalChinese)] {
                XCTAssertFalse(text.contains("units") || text.contains("單位"), text)
            }
        }
        XCTAssertGreaterThan(placed, 0, "the demo's lines run trains")
    }

    func testATrainOnATripSaysWhereItIsGoingAndHowFar() throws {
        var world = DemoWorld.make(in: .english)
        var checked = 0
        for _ in 0..<120 {
            try world.advance(ticks: 1)
            for train in world.trains {
                guard case .travellingToStop(let stop, _)? = train.execution else { continue }
                let name = try XCTUnwrap(world.station(id: train.timetable[stop].station)?.name)
                let english = world.trainPathStatusText(of: train.id, in: .english)
                XCTAssertTrue(english.hasPrefix("Heading to \(name)"), english)
                let chinese = world.trainPathStatusText(of: train.id, in: .traditionalChinese)
                XCTAssertTrue(chinese.hasPrefix("開往 \(name)"), chinese)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "a demo train ran between stops")
    }

    func testTheWordsOfTheDistances() {
        XCTAssertEqual(NetworkBuilding.distanceText(11_264, in: .traditionalChinese), "176 公尺")
        XCTAssertEqual(NetworkBuilding.distanceText(76_800, in: .english), "1.2 km")
        XCTAssertEqual(GameSession.metresSpanText(952, 5_048), "15–79")
        XCTAssertNil(DemoWorld.make(in: .english).trainWhereText(of: TrainID(rawValue: 9_999), in: .english))
    }
}
