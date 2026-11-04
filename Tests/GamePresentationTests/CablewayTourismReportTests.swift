import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 586: the tourists the Maokong sight (`AttractionCatalog`'s
/// `t009`) sends up the Maokong Gondola (``RealCableway/maokong``) once it
/// meets a station, run only when asked (`CABLE_TOURISM_REPORT=<days>`,
/// seconds in a debug build). On the Maokong demo's map (a new real-world
/// game round Muzha, as ``ScreenshotScene/maokong``), for each day from
/// day 0: whether the gondola runs, the tourists the sight draws
/// (``GameWorld/touristsExpected(for:onDay:)``, the rail stations' own
/// rule), their rides up and down, those rides' fares, and the gondola's
/// running. It plays no minutes: the riders it already has (those between
/// its stops, HEALTH-112's 667 a day) are added in the decision. It asserts
/// nothing: the numbers are in the decision.
@MainActor
final class CablewayTourismReportTests: XCTestCase {
    func testTheMaokongSightsTourists() throws {
        guard let wanted = ProcessInfo.processInfo.environment["CABLE_TOURISM_REPORT"], let days = Int64(wanted), days > 0 else {
            throw XCTSkip("Set CABLE_TOURISM_REPORT=<days> to measure the Maokong Gondola's tourists (decision 586).")
        }
        let place = try XCTUnwrap(ScreenshotScene.maokong.place)
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude)))
        let stops = try XCTUnwrap(RealCableway.maokong.stops(in: world))
        let cableway = try world.createCableway(stops: stops, legMetres: RealCableway.maokong.legMetres)
        let sight = try XCTUnwrap(world.tourism?.attractions.first { $0.englishName == "Maokong" })
        print("""

        ### Maokong sight's tourists up the gondola (decision 586), days 0 to \(days - 1)
        sight: \(sight.stars) hundredths of a star, \(sight.kind); gondola running NT$\(cableway.dailyCost.amount / 100) a day

        | day | weekday | holiday | runs | tourists | rides | fares |
        | --: | --: | --- | --- | --: | --: | --: |
        """)
        var rides: Int64 = 0, open: Int64 = 0
        for day in 0..<days {
            let runs = world.cablewayIsOpen(cableway.id, onDay: day)
            let tourists = runs ? world.touristsExpected(for: sight, onDay: day) : 0
            rides += 2 * tourists
            if runs { open += 1 }
            print("| \(day) | \(StationDemand.weekday(ofDay: day)) | \(world.holiday(onDay: day) != nil ? "yes" : "") | \(runs ? "yes" : "no") "
                + "| \(tourists) | \(2 * tourists) | \(2 * tourists * Cableway.fare.amount / 100) |")
        }
        print("| all | | | \(open) days | | \(rides) | \(rides * Cableway.fare.amount / 100) |\n")
    }
}
