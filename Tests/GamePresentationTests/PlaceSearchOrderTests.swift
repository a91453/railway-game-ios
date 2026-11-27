import Foundation
@testable import GamePresentation
import XCTest

/// 2026-11-27: a place searched by name comes first in the real-world map
/// picker (``PlaceSearchOrder``), and so do the list's own cities and
/// stations named exactly as typed.
final class PlaceSearchOrderTests: XCTestCase {
    func testThePlaceNamedAsTypedComesFirst() {
        let found = ["北九州市小倉北区", "小倉駅", "北九州小倉城", "小倉城庭園", "小倉城"]
        XCTAssertEqual(
            PlaceSearchOrder.ordered(found, query: "小倉城") { $0 },
            ["小倉城", "小倉城庭園", "北九州小倉城", "北九州市小倉北区", "小倉駅"],
            "the name itself, the names it starts, the names it is in, then the rest as found"
        )
    }

    func testNamesAreComparedAsTheListComparesThem() {
        XCTAssertEqual(PlaceSearchOrder.ordered(["Taipei 101", "臺北"], query: "台北") { $0 }, ["臺北", "Taipei 101"])
        XCTAssertEqual(PlaceSearchOrder.ordered(["Kokura Station", "Kokura Castle"], query: " kokura castle ") { $0 },
                       ["Kokura Castle", "Kokura Station"])
    }

    func testAnEmptySearchKeepsTheOrderFound() {
        XCTAssertEqual(PlaceSearchOrder.ordered(["b", "a"], query: "  ") { $0 }, ["b", "a"])
        XCTAssertEqual(PlaceSearchOrder.ordered([String](), query: "a") { $0 }, [])
    }

    /// The list's own stations: the one named as typed before longer
    /// names that start the same, then as before.
    func testTheStationNamedAsTypedComesFirst() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/RealRailways")
        func file(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(name)) }
        let railways = try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json")
        )
        XCTAssertEqual(Array(railways.stations(matching: "蘇澳").map(\.id).prefix(2)), ["tra_sched|蘇澳", "tra_sched|蘇澳新"])
        XCTAssertEqual(Array(railways.stations(matching: "中山").map(\.id).prefix(2)), ["mrt|中山", "mrt|中山國中"])
        XCTAssertEqual(Array(railways.stations(matching: "台中").map(\.id).prefix(3)),
                       ["tra_sched|臺中", "thsr_sched|台中", "tra_sched|臺中港"])
    }

    /// The list's own cities: the one named as typed first.
    func testTheCityNamedAsTypedComesFirst() {
        for place in RealWorldPlace.groups.flatMap(\.places) {
            XCTAssertEqual(RealWorldPlace.matching(place.english).first?.id, place.id, place.english)
        }
    }
}
