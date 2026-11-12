import Foundation
import XCTest
@testable import GamePresentation

/// The real intercity coach routes the app bundles (decision 706).
final class RealCoachesTests: XCTestCase {
    private func bundled() throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealCoaches/\(RealCoaches.file)"))
    }

    /// The file reads, and holds the freeway coaches and the long highway
    /// buses the tool chose.
    func testTheFileReads() throws {
        let coaches = try RealCoaches(data: bundled())
        XCTAssertEqual(coaches.fetched, "2026-11-12")
        XCTAssertEqual(coaches.routes.count, 715)
        XCTAssertEqual(coaches.routes.filter { $0.kind == .freeway }.count, 540)
        XCTAssertEqual(Set(coaches.routes.map(\.id)).count, coaches.routes.count, "ids are unique")
        XCTAssertEqual(coaches.routes.filter(\.minutesEstimated).count, 12)
        XCTAssertEqual(coaches.routes.filter { $0.fare == nil }.count, 81)
        // The file stays a size the app can read at once (3.75 MB when
        // written; a jump means the selection changed).
        XCTAssertLessThan(try bundled().count, 4_500_000)
        // Taiwan's main island, no farther.
        XCTAssertGreaterThan(coaches.southWest.latitude, 21.8)
        XCTAssertLessThan(coaches.northEast.latitude, 25.4)
        XCTAssertGreaterThan(coaches.southWest.longitude, 120.0)
        XCTAssertLessThan(coaches.northEast.longitude, 122.1)
    }

    /// Every route's stops are in order along its shape and in time, the
    /// shape is one piece as long as the file says, every stop is on it,
    /// and it leaves at least once a week at a speed a coach runs.
    func testStopsFollowTheShapeAndTheClock() throws {
        for route in try RealCoaches(data: bundled()).routes {
            XCTAssertGreaterThanOrEqual(route.stops.count, 2, route.id)
            let legs = zip(route.shape, route.shape.dropFirst()).map { $0.distance(to: $1) }
            // The tool leaves out a route with two points more than 10 km
            // apart.
            XCTAssertLessThanOrEqual(legs.max() ?? 0, 10_001, route.id)
            XCTAssertEqual(legs.reduce(0, +), Double(route.metres), accuracy: 2 + Double(route.metres) * 0.001, route.id)
            XCTAssertTrue(zip(route.stops, route.stops.dropFirst()).allSatisfy { $0.metres <= $1.metres && $0.minutes <= $1.minutes }, route.id)
            XCTAssertEqual(route.stops[0].minutes, 0, route.id)
            for stop in route.stops {
                let distance = stop.coordinate.distance(to: route.coordinate(atMetres: Double(stop.metres)))
                XCTAssertLessThan(distance, 1, "\(route.id) \(stop.name)")
            }
            let kilometresAnHour = Double(route.metres) / 1_000 / (Double(route.runMinutes) / 60)
            XCTAssertTrue((14 ... 112).contains(kilometresAnHour), "\(route.id): \(kilometresAnHour) km/h")
            XCTAssertFalse(route.departures.isEmpty, route.id)
            XCTAssertEqual((0 ..< 7).reduce(0) { $0 + route.departures(on: $1).count },
                           route.departures.reduce(0) { $0 + $1.days.nonzeroBitCount }, route.id)
            XCTAssertFalse(route.operators.isEmpty, route.id)
            if route.kind == .highway {
                XCTAssertGreaterThanOrEqual(Set(route.stops.map(\.city).filter { !$0.isEmpty }).count, 2, route.id)
                // The tool asks 30 km of the stops' own positions; a stop's
                // point here is on the shape, up to 500 m from it, and the
                // nearest route is 28.75 km by those.
                XCTAssertGreaterThanOrEqual(route.stops.map { $0.coordinate.distance(to: route.stops[0].coordinate) }.max() ?? 0, 28_500, route.id)
            }
        }
    }

    /// Three known routes, as TDX has them.
    func testKnownRoutes() throws {
        let coaches = try RealCoaches(data: bundled())
        // Kuo-Kuang's 1818, Taipei to Zhongli: 42 km in 51 minutes for
        // NT$ 77; its weekday daytime is "every 15 to 20 minutes" in TDX,
        // which the tool turns into departures.
        let zhongli = try XCTUnwrap(coaches.routes.first { $0.id == "THB181801_0" })
        XCTAssertEqual(zhongli.name, "1818")
        XCTAssertEqual(zhongli.kind, .freeway)
        XCTAssertEqual(zhongli.operators, ["國光客運"])
        XCTAssertEqual(zhongli.headsign, "臺北→中壢")
        XCTAssertEqual(zhongli.englishHeadsign, "Taipei→Zhongli")
        XCTAssertEqual(zhongli.stops.count, 16)
        XCTAssertEqual(zhongli.stops.first?.name, "臺北車站(鄭州)")
        XCTAssertEqual(zhongli.stops.first?.city, "TPE")
        XCTAssertEqual(zhongli.stops.last?.name, "中央東路")
        XCTAssertEqual(zhongli.stops.last?.city, "TAO")
        XCTAssertEqual(Double(zhongli.metres), 42_200, accuracy: 100)
        XCTAssertEqual(zhongli.runMinutes, 51)
        XCTAssertEqual(zhongli.fare, 77)
        XCTAssertEqual(zhongli.departures(on: 2).count, 57)
        XCTAssertEqual(zhongli.departures(on: 2).first, 6 * 60 + 20)
        XCTAssertEqual(zhongli.departures(on: 6).count, 55)
        XCTAssertEqual(zhongli.departuresFromHeadways, 101)
        // Passengers board in Taipei and alight in Zhongli.
        XCTAssertEqual(zhongli.stops.first?.boarding, .boardingOnly)
        XCTAssertEqual(zhongli.stops.last?.boarding, .alightingOnly)
        // Its first stop is beside Taipei Main Station.
        let mainStation = RealRailways.Coordinate(latitude: 25.04775, longitude: 121.51711)
        XCTAssertLessThan(try XCTUnwrap(zhongli.stops.first).coordinate.distance(to: mainStation), 600)
        XCTAssertTrue(coaches.routes(near: mainStation, within: 600).contains { $0.id == zhongli.id })

        // UBus's 1618F, Taipei to Chiayi: 253 km, five on a Wednesday and
        // eight on a Sunday.
        let chiayi = try XCTUnwrap(coaches.routes.first { $0.id == "THB1618F1_0" })
        XCTAssertEqual(chiayi.subRoute, "1618F")
        XCTAssertEqual(chiayi.stops.last?.name, "嘉義市轉運中心")
        XCTAssertEqual(chiayi.runMinutes, 260)
        XCTAssertEqual(chiayi.fare, 378)
        XCTAssertEqual(chiayi.departures(on: 2).count, 5)
        XCTAssertEqual(chiayi.departures(on: 6).count, 8)
        XCTAssertEqual(chiayi.departuresFromHeadways, 0)

        // The coast road's 8119, Taitung to Hualien: a highway bus, not a
        // freeway coach, 172 km and 212 stops, once a day.
        let coast = try XCTUnwrap(coaches.routes.first { $0.id == "THB811901_0" })
        XCTAssertEqual(coast.kind, .highway)
        XCTAssertEqual(coast.stops.count, 212)
        XCTAssertEqual(coast.stops.first?.city, "TTT")
        XCTAssertEqual(coast.stops.last?.city, "HUA")
        XCTAssertEqual(coast.departures(on: 0), [6 * 60 + 30])
        XCTAssertEqual(coast.fare, 547)
    }

    /// A file out of shape is refused, not half read.
    func testAFileOutOfShapeIsRefused() throws {
        func file(_ route: String, schema: Int = 1) -> Data {
            Data(#"{"schema":\#(schema),"scale":100000,"origin":{"source":"tdx","fetched":"2026-11-12"},"bounds":[12100000,2480000,12100000,2480100],"inputs":[],"routes":[\#(route)]}"#.utf8)
        }
        let good = #"{"key":"A_0","route":"A","name":"1","subRoute":"1","direction":0,"kind":"freeway","operators":["x"],"headsign":"","headsignEn":"","metres":111,"shape":[12100000,2480000,0,100],"stopNames":["a","b"],"stopMetres":[0,111],"stopCities":["TPE","TAO"],"stopMinutes":[0,5],"tripMinutes":[360,420],"tripDays":[127,31]}"#
        let route = try XCTUnwrap(try RealCoaches(data: file(good)).routes.first)
        XCTAssertEqual(route.stops.map(\.name), ["a", "b"])
        XCTAssertEqual(route.stops.map(\.boarding), [.both, .both])
        XCTAssertEqual(route.departures(on: 5), [360])
        XCTAssertEqual(route.departures(on: 0), [360, 420])
        XCTAssertNil(route.fare)
        XCTAssertFalse(route.minutesEstimated)
        func refused(_ old: String, _ new: String, line: UInt = #line) {
            XCTAssertTrue(good.contains(old), line: line)
            XCTAssertThrowsError(try RealCoaches(data: file(good.replacingOccurrences(of: old, with: new))), line: line)
        }
        XCTAssertThrowsError(try RealCoaches(data: file(good, schema: 2)))
        refused(#""stopMetres":[0,111]"#, #""stopMetres":[111,0]"#)
        refused(#""stopMetres":[0,111]"#, #""stopMetres":[0,500]"#)
        refused(#""shape":[12100000,2480000,0,100]"#, #""shape":[12100000,2480000]"#)
        refused(#""stopNames":["a","b"]"#, #""stopNames":["a"]"#)
        refused(#""stopCities":["TPE","TAO"]"#, #""stopCities":["TPE"]"#)
        refused(#""stopMinutes":[0,5]"#, #""stopMinutes":[5,0]"#)
        refused(#""stopMinutes":[0,5]"#, #""stopMinutes":[0,0]"#)
        refused(#""tripMinutes":[360,420]"#, #""tripMinutes":[420,360]"#)
        refused(#""tripMinutes":[360,420]"#, #""tripMinutes":[360,1440]"#)
        refused(#""tripMinutes":[360,420],"tripDays":[127,31]"#, #""tripMinutes":[],"tripDays":[]"#)
        refused(#""tripDays":[127,31]"#, #""tripDays":[127,0]"#)
        refused(#""tripDays":[127,31]"#, #""tripDays":[127,31],"fare":0"#)
        refused(#""tripDays":[127,31]"#, #""tripDays":[127,31],"stopBoarding":[1,2]"#)
        refused(#""kind":"freeway""#, #""kind":"tram""#)
    }
}
