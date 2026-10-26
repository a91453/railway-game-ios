import Foundation
import XCTest
@testable import GamePresentation

/// The real bus routes the app bundles (decision 400, 10i-3).
final class RealBusesTests: XCTestCase {
    /// A file the app bundles (`RailwayGameApp/Resources/RealBuses/`).
    private func bundled(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealBuses/\(name)"))
    }

    private func index() throws -> RealBuses {
        try RealBuses(index: bundled(RealBuses.indexFile))
    }

    private func routes(_ city: String) throws -> [RealBusRoute] {
        let buses = try index()
        let place = try XCTUnwrap(buses.places.first { $0.city == city })
        return try buses.routes(of: place, data: bundled(place.file))
    }

    /// The index lists the reference's twenty places and TDX's two, each
    /// file reads, and holds the routes and estimated headways the index
    /// says.
    func testEveryPlaceReads() throws {
        let buses = try index()
        XCTAssertEqual(buses.places.count, 22)
        XCTAssertEqual(Set(buses.places.filter { $0.source == .tdx }.map(\.city)), ["Taipei", "PingtungCounty"])
        XCTAssertEqual(Set(buses.places.map(\.file)).count, 22, "one file each")
        var total = 0
        for place in buses.places {
            let routes = try buses.routes(of: place, data: bundled(place.file))
            XCTAssertEqual(routes.count, place.routes, place.city)
            XCTAssertEqual(routes.filter(\.headwayEstimated).count, place.estimatedHeadways, place.city)
            XCTAssertEqual(Set(routes.map(\.id)).count, routes.count, "\(place.city): ids are unique")
            total += routes.count
        }
        XCTAssertGreaterThan(total, 5_000)
    }

    /// Every route's stops are in order along its shape, the shape is one
    /// piece as long as the file says, and every stop is on it.
    func testStopsFollowTheShape() throws {
        let buses = try index()
        for place in buses.places {
            for route in try buses.routes(of: place, data: bundled(place.file)) {
                XCTAssertGreaterThanOrEqual(route.shape.count, 2, route.id)
                XCTAssertFalse(route.stops.isEmpty, route.id)
                let legs = zip(route.shape, route.shape.dropFirst()).map { $0.distance(to: $1) }
                // No jump in the shape: the tool leaves out a route with
                // two points more than 5 km apart.
                XCTAssertLessThanOrEqual(legs.max() ?? 0, 5_001, route.id)
                XCTAssertEqual(legs.reduce(0, +), Double(route.metres), accuracy: 2 + Double(route.metres) * 0.001, route.id)
                XCTAssertTrue(zip(route.stops, route.stops.dropFirst()).allSatisfy { $0.metres <= $1.metres }, route.id)
                XCTAssertLessThanOrEqual(route.stops.last?.metres ?? 0, route.metres, route.id)
                for stop in route.stops {
                    let distance = stop.coordinate.distance(to: route.coordinate(atMetres: Double(stop.metres)))
                    XCTAssertLessThan(distance, 1, "\(route.id) \(stop.name)")
                }
                XCTAssertTrue((1 ... 720).contains(route.headwayMinutes), route.id)
            }
        }
    }

    /// A route with no schedule runs every estimated headway, marked as
    /// such: 30 minutes in a city, 60 in a county.
    func testEstimatedHeadwaysAreMarked() throws {
        let taipei = try routes("Taipei")
        XCTAssertTrue(taipei.contains { $0.headwayEstimated })
        XCTAssertTrue(taipei.contains { !$0.headwayEstimated })
        XCTAssertEqual(Set(taipei.filter(\.headwayEstimated).map(\.headwayMinutes)), [30])
        let hsinchuCounty = try routes("HsinchuCounty")
        XCTAssertEqual(Set(hsinchuCounty.filter(\.headwayEstimated).map(\.headwayMinutes)), [60])
        // Hsinchu City's routes all have TDX's schedule.
        XCTAssertFalse(try routes("Hsinchu").contains { $0.headwayEstimated })
    }

    /// Two known routes, as TDX has them.
    func testKnownRoutes() throws {
        // Hsinchu City's 81, from the reference: Guqifeng to Xinzhuang
        // Station.
        let hsinchu81 = try XCTUnwrap(routes("Hsinchu").first { $0.id == "Hsinchu/HSZ0007_81_0" })
        XCTAssertEqual(hsinchu81.name, "81")
        XCTAssertEqual(hsinchu81.direction, 0)
        XCTAssertEqual(hsinchu81.stops.first?.name, "古奇峰")
        XCTAssertEqual(hsinchu81.stops.last?.name, "新莊車站")
        XCTAssertEqual(hsinchu81.stops.count, 21)
        XCTAssertFalse(hsinchu81.headwayEstimated)
        // Taipei's 234, from TDX: 37 stops, Huanziyuan to Hankou Street,
        // about 14 km, every 15 minutes on a weekday (TDX's 7–20).
        let taipei234 = try XCTUnwrap(routes("Taipei").first { $0.id == "Taipei/TPE10132_0" })
        XCTAssertEqual(taipei234.name, "234")
        XCTAssertEqual(taipei234.stops.count, 37)
        XCTAssertEqual(taipei234.stops.first?.name, "歡仔園")
        XCTAssertEqual(taipei234.stops.last?.name, "漢口街")
        XCTAssertEqual(Double(taipei234.metres), 13_900, accuracy: 100)
        XCTAssertEqual(taipei234.headwayMinutes, 15)
        XCTAssertFalse(taipei234.headwayEstimated)
        // Its last stop, Hankou Street, is a little over a kilometre from
        // Taipei Main Station.
        let mainStation = RealRailways.Coordinate(latitude: 25.04775, longitude: 121.51711)
        XCTAssertLessThan(try XCTUnwrap(taipei234.stops.last).coordinate.distance(to: mainStation), 1_500)
    }

    /// Only the places whose routes may reach a point are read.
    func testPlacesNearAPoint() throws {
        let buses = try index()
        let mainStation = RealRailways.Coordinate(latitude: 25.04775, longitude: 121.51711)
        let near = Set(buses.places(near: mainStation, within: 600).map(\.city))
        XCTAssertTrue(near.isSuperset(of: ["Taipei", "NewTaipei"]), "\(near)")
        XCTAssertFalse(near.contains("Kaohsiung"))
        XCTAssertFalse(near.contains("PenghuCounty"))
        let makung = RealRailways.Coordinate(latitude: 23.5669, longitude: 119.5786)
        XCTAssertEqual(buses.places(near: makung, within: 600).map(\.city), ["PenghuCounty"])
    }

    /// A file out of shape is refused, not half read.
    func testAFileOutOfShapeIsRefused() throws {
        let buses = try index()
        let place = try XCTUnwrap(buses.places.first { $0.city == "Hsinchu" })
        func file(_ route: String, city: String = "Hsinchu", schema: Int = 1) -> Data {
            Data(#"{"schema":\#(schema),"city":"\#(city)","routes":[\#(route)]}"#.utf8)
        }
        let good = #"{"key":"A_0","route":"A","name":"1","subRoute":"","direction":0,"headway":10,"headwayEstimated":false,"metres":111,"shape":[12100000,2480000,0,100],"stopNames":["a","b"],"stopMetres":[0,111]}"#
        XCTAssertEqual(try buses.routes(of: place, data: file(good)).first?.stops.map(\.name), ["a", "b"])
        XCTAssertThrowsError(try buses.routes(of: place, data: file(good, schema: 2)))
        XCTAssertThrowsError(try buses.routes(of: place, data: file(good, city: "Taipei")))
        let outOfOrder = good.replacingOccurrences(of: #""stopMetres":[0,111]"#, with: #""stopMetres":[111,0]"#)
        XCTAssertThrowsError(try buses.routes(of: place, data: file(outOfOrder)))
        let pastTheEnd = good.replacingOccurrences(of: #""stopMetres":[0,111]"#, with: #""stopMetres":[0,500]"#)
        XCTAssertThrowsError(try buses.routes(of: place, data: file(pastTheEnd)))
        let onePoint = good.replacingOccurrences(of: #""shape":[12100000,2480000,0,100]"#, with: #""shape":[12100000,2480000]"#)
        XCTAssertThrowsError(try buses.routes(of: place, data: file(onePoint)))
        let noHeadway = good.replacingOccurrences(of: #""headway":10"#, with: #""headway":0"#)
        XCTAssertThrowsError(try buses.routes(of: place, data: file(noHeadway)))
        let missingName = good.replacingOccurrences(of: #""stopNames":["a","b"]"#, with: #""stopNames":["a"]"#)
        XCTAssertThrowsError(try buses.routes(of: place, data: file(missingName)))
    }
}
