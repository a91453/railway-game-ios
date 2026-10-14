import GameCore
@testable import GamePresentation
import XCTest

/// Decision 224 (3B): two stations a new line would join, side by side.
final class StationPairComparisonTests: XCTestCase {
    func testTwoStationsOfTheDemoJoinedByTrackHaveTheirFiguresAndTheRunBetweenThem() throws {
        let world = DemoWorld.make(in: .english)
        let line = try XCTUnwrap(world.lines.first)
        let a = line.stops[0], b = line.stops[1]
        let pair = try XCTUnwrap(StationPairComparison(world: world, from: a, to: b))
        XCTAssertEqual(pair.from.station, a)
        XCTAssertEqual(pair.to.name, world.station(id: b)?.name)
        XCTAssertEqual(pair.from.dailyTrips, world.stationDemand(of: a)?.dailyTrips)
        XCTAssertTrue(pair.from.lines.contains(line.id))
        let track = try XCTUnwrap(pair.trackMetres, "the demo's line runs between its first two stops")
        XCTAssertGreaterThanOrEqual(track + 1, pair.straightMetres, "the track is no shorter than the straight line")
        XCTAssertGreaterThan(try XCTUnwrap(pair.runSeconds), 0)
        for measure in pair.measures {
            XCTAssertEqual(max(pair.fraction(measure, of: pair.from), pair.fraction(measure, of: pair.to)), 1, accuracy: 1e-9)
        }
    }

    func testTheSameStationOrAnUnknownOneHasNoComparison() throws {
        let world = DemoWorld.make(in: .english)
        let a = try XCTUnwrap(world.stations.first).id
        XCTAssertNil(StationPairComparison(world: world, from: a, to: a))
        XCTAssertNil(StationPairComparison(world: world, from: a, to: StationID(rawValue: 9_999)))
    }

    func testTheWords() {
        func side(_ trips: Int64?) -> StationPairComparison.Side {
            .init(station: StationID(rawValue: 1), name: "A", residents: nil, jobs: nil, dailyTrips: trips, lines: [])
        }
        let joined = StationPairComparison(from: side(4_280), to: side(1_070), straightMetres: 12_000, trackMetres: 13_640, runSeconds: 830)
        XCTAssertEqual(joined.distanceText(in: .traditionalChinese), "13.6 km")
        XCTAssertEqual(joined.timeText(in: .traditionalChinese), "約 14 分")
        XCTAssertEqual(joined.measures, [.dailyTrips])
        XCTAssertEqual(joined.fraction(.dailyTrips, of: joined.to), 0.25, accuracy: 1e-9)
        let apart = StationPairComparison(from: side(nil), to: side(nil), straightMetres: 850, trackMetres: nil, runSeconds: nil)
        XCTAssertEqual(apart.distanceText(in: .traditionalChinese), "相距 850 m")
        XCTAssertEqual(apart.timeText(in: .traditionalChinese), "還沒有軌道")
        XCTAssertTrue(apart.measures.isEmpty)
        XCTAssertEqual(StationPairComparison.valueText(4_280), "4,280")
        XCTAssertEqual(StationPairComparison.valueText(nil), "—")
    }
}
