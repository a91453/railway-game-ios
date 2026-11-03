import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 561: the Taoyuan Airport MRT's trains drawn as #1700's cars,
/// the commuter train's four of the 1000 and the express's five of the
/// 2000, each trip by its kind in the timetable.
final class Map3DTaoyuanAirportOperationTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    /// The line's trains are the 1000; an express trip's (its place key
    /// marked `E`) the 2000, five cars, the day before's too.
    func testTheLineAndAnExpressTrip() {
        let line = Map3DRealTrains.formation(system: "tymc", id: "A", name: "機場捷運")
        XCTAssertEqual(line, Map3DRealTrains.Formation(key: Map3DTrainSet.taoyuanAirport1000Key, cars: 4))
        for place in ["平日#E12", "-假日#E0", "E3"] {
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "tymc", place: place),
                           Map3DRealTrains.Formation(key: Map3DTrainSet.taoyuanAirport2000Key, cars: 5), place)
        }
        for place in ["平日#12", "-假日#0", "3", "h1"] {
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "tymc", place: place), line, place)
        }
        // Only the Airport MRT's trips are told apart by kind.
        let other = Map3DRealTrains.Formation(key: "kaohsiung", cars: 3)
        XCTAssertEqual(Map3DRealTrains.formation(of: other, system: "krtc", place: "平日#E12"), other)
        XCTAssertEqual(RealTrainTraffic.expressKey(trip: 7, kind: "2"), "E7")
        XCTAssertEqual(RealTrainTraffic.expressKey(trip: 7, kind: "1"), "7")
        XCTAssertEqual(RealTrainTraffic.expressKey(trip: 7, kind: nil), "7")
        // A bought line's trains, all stopping trains, are the 1000.
        XCTAssertEqual(RealLineStock.setKey(ofRealLine: "tymc:A"), Map3DTrainSet.taoyuanAirport1000Key)
        XCTAssertEqual(Map3DTrainSet.variant(of: Map3DTrainSet.taoyuanAirport1000Key, number: 3), Map3DTrainSet.taoyuanAirport1000Key)
    }

    /// The bundled timetable: each set's runs keyed by their trips, as many
    /// express as the set's trips of kind 2, and a train's number its trip.
    func testTheBundledTimetablesExpressTrips() throws {
        let operations = try XCTUnwrap(try BundledRealData.railways().operations)
        let timetable = try XCTUnwrap(operations.timetable(forSystem: "tymc")?.lines["A"])
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        let line = try XCTUnwrap(traffic.lines.first { $0.system == "tymc" })
        guard case .sets(_, let sets) = line.schedule else { return XCTFail("\(line.schedule)") }
        for (name, trips) in timetable.sets {
            let runs = try XCTUnwrap(sets[name], name)
            let keys = runs.runs.indices.map(runs.key)
            let express = keys.filter { RealTrainTraffic.isExpress(place: "\(name)#\($0)") }
            XCTAssertEqual(express.count, trips.filter { $0.kind == "2" }.count, name)
            XCTAssertFalse(express.isEmpty, name)
            XCTAssertLessThan(express.count, keys.count, name)
            XCTAssertEqual(Set(keys).count, keys.count, "\(name): one key a run")
            for key in keys {
                let trip = trips[Map3DTrainSet.number(ofRealTrain: key)]
                XCTAssertEqual(RealTrainTraffic.isExpress(place: key), trip.kind == "2", "\(name) \(key)")
            }
        }
    }

    /// The cars in their order: DMC1 MC1 MC2 DMC2 and DME1 ME1 ME3 ME4
    /// DMB, each at its own length, near and far.
    func testTheCarsInTheirOrder() throws {
        for far in [false, true] {
            let suffix = far ? "Far" : ""
            let commuter = Map3DTrainSet.taoyuanAirport1000Key + suffix, express = Map3DTrainSet.taoyuanAirport2000Key + suffix
            let four = try XCTUnwrap(pack.layout(forType: commuter, count: 4), commuter)
            XCTAssertEqual(four.map { pack.models[$0.model].name }, ["head", "car", "centre", "tail"].map { "set-\(commuter)-\($0)" })
            XCTAssertEqual(four.map(\.length).reduce(0, +), 2 * 20.78 + 2 * 20.25, accuracy: 0.3)
            let five = try XCTUnwrap(pack.layout(forType: express, count: 5), express)
            XCTAssertEqual(five.map { pack.models[$0.model].name }, ["head", "car", "centre", "fourth", "tail"].map { "set-\(express)-\($0)" })
            XCTAssertEqual(five.map(\.length).reduce(0, +), 2 * 20.78 + 3 * 20.25, accuracy: 0.3)
        }
        // Near within the trams' reach, the far cars then.
        for key in [Map3DTrainSet.taoyuanAirport1000Key, Map3DTrainSet.taoyuanAirport2000Key] {
            XCTAssertEqual(Map3DTrainSet.reach(of: key), Map3DTrainSet.tramReach, key)
            let head = try XCTUnwrap(pack.index(of: "set-\(key)-head"))
            XCTAssertEqual(pack.model(head, forType: key, count: 4, at: 700), pack.index(of: "set-\(key)Far-head"), key)
        }
    }
}
