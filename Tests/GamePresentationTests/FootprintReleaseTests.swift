import Foundation
@testable import GamePresentation
import XCTest

/// Decision 1026: the bundled Taiwan buildings and the credit name the
/// same Overture release, so the monthly refresh
/// (`tools/overture-footprint-tiles/refresh_release.py`) cannot move one
/// without the other.
final class FootprintReleaseTests: XCTestCase {
    /// The metadata of the app's `taiwan_buildings.pmtiles` (PMTiles v3:
    /// its offset and length at bytes 24 and 32, gzipped).
    static func metadata() throws -> [String: Any] {
        let file = Map3DFrameCostReportTests.baseMap.appendingPathComponent("taiwan_buildings.pmtiles")
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        func number(_ at: Int) -> Int {
            var value: UInt64 = 0
            for byte in (0..<8).reversed() { value = value << 8 | UInt64(data[data.startIndex + at + byte]) }
            return Int(truncatingIfNeeded: value)
        }
        let offset = number(24), length = number(32)
        let packed = [UInt8](data[(data.startIndex + offset)..<(data.startIndex + offset + length)])
        let json = try Inflate.gunzip(packed)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json)) as? [String: Any])
    }

    func testTheBundledBuildingsAreOnTheCreditedRelease() throws {
        let metadata = try Self.metadata()
        XCTAssertEqual(metadata["overture"] as? String, DataSourceCredits.taiwanFootprintRelease)
        XCTAssertEqual(metadata["format"] as? String, "footprints/3")
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let credit = try XCTUnwrap(DataSourceCredits.sections(in: language).flatMap(\.credits).first { $0.id == "overtureBuildings" })
            XCTAssertTrue(credit.notice.contains(DataSourceCredits.taiwanFootprintRelease), credit.notice)
        }
    }
}
