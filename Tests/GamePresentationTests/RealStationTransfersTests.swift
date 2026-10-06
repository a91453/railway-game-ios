import Foundation
import GameCore
import GamePresentation
import XCTest

final class RealStationTransfersTests: XCTestCase {
    private static func transfers() throws -> RealStationTransfers {
        try RealStationTransfers(data: BundledRealData.file("station_transfers", "json"))
    }

    func testTheSitesTransferName() {
        XCTAssertEqual(RealStationTransfers.transferStationName("臺北"), "台北")
        XCTAssertEqual(RealStationTransfers.transferStationName("台北車站"), "台北")
        XCTAssertEqual(RealStationTransfers.transferStationName("台北火車站"), "台北")
        XCTAssertEqual(RealStationTransfers.transferStationName("高鐵台中站"), "台中")
        XCTAssertEqual(RealStationTransfers.transferStationName("臺鐵新竹"), "新竹")
        XCTAssertEqual(RealStationTransfers.transferStationName(" 板橋 "), "板橋")
        // NFKC: a full-width letter reads as its ASCII one.
        XCTAssertEqual(RealStationTransfers.transferStationName("Ａ1"), "A1")
    }

    func testTheFileLoads() throws {
        let transfers = try Self.transfers()
        XCTAssertEqual(transfers.maximumDistanceMetres, 450)
        XCTAssertEqual(transfers.stations.count, 563)
        XCTAssertEqual(transfers.groups.count, 58)
        XCTAssertEqual(transfers.routes.count, 31)
        XCTAssertEqual(transfers.routes["THSR:THSR"]?.label, "高鐵", "The site's fallback label")
    }

    func testTaipeiMainStationsTransfers() throws {
        let transfers = try Self.transfers()
        let taipei = RealRailways.Coordinate(latitude: 25.04775, longitude: 121.51711)
        let tra = try XCTUnwrap(transfers.station(inSystem: "TRA", named: "臺北", near: taipei))
        XCTAssertEqual(tra.key, "TRA:1000")
        let partners = transfers.partners(of: tra).map(\.key)
        XCTAssertTrue(partners.contains("THSR:1000"))
        XCTAssertTrue(partners.contains("TRTC:BL12"))
        XCTAssertTrue(partners.contains("TYMC:A1"))
        XCTAssertFalse(partners.contains("TRA:1000"))
        let routes = transfers.transferRoutes(at: tra)
        XCTAssertFalse(routes.contains { $0.system == "TRA" }, "Not its own system's")
        XCTAssertTrue(routes.contains { $0.key == "THSR:THSR" })
        XCTAssertEqual(Set(routes.map(\.key)).count, routes.count, "Each once")
        // Any system, by name and within 450 m.
        XCTAssertNotNil(transfers.station(named: "台北車站", near: taipei))
        XCTAssertNil(transfers.station(named: "台北", near: RealRailways.Coordinate(latitude: 25.06, longitude: 121.51)))
    }

    func testAnotherSchemaIsRefused() {
        let data = Data(#"{"schemaVersion":2,"criteria":{"maxDistanceM":450},"routes":{},"stations":{},"transferStations":[]}"#.utf8)
        XCTAssertThrowsError(try RealStationTransfers(data: data)) { error in
            XCTAssertEqual(error as? RealStationTransfers.FormatError, .unsupportedSchema(2))
        }
    }
}
