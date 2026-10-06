import Foundation
import GameCore
import GamePresentation
import XCTest

final class RealStationDataTests: XCTestCase {
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private static func makeStationData() throws -> RealStationData {
        try RealStationData(
            classes: bundledFile("tra_station_class.json"),
            infos: bundledFile("tra_station_info.json"),
            codes: bundledFile("trtc_codes.json"),
            platforms: bundledFile("tra_platforms.json"),
            sections: bundledFile("tra_track_sections.json")
        )
    }

    // MARK: - Station Classes

    func testStationClassesLoadAndClassifyCorrectly() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.stationClasses.count, 210, "210 TRA station classifications")

        // Specific classifications
        XCTAssertEqual(data.stationClass(forStation: "臺北"), .special)
        XCTAssertEqual(data.stationClass(forStation: "台北"), .special, "Supports character normalization")
        XCTAssertEqual(data.stationClass(forStation: "台中"), .special)
        XCTAssertEqual(data.stationClass(forStation: "高雄"), .special)
        XCTAssertEqual(data.stationClass(forStation: "花蓮"), .special)

        XCTAssertEqual(data.stationClass(forStation: "基隆"), .first)
        XCTAssertEqual(data.stationClass(forStation: "板橋"), .first)
        XCTAssertEqual(data.stationClass(forStation: "新竹"), .first)
        XCTAssertEqual(data.stationClass(forStation: "瑞芳"), .first, "The bundled reference lists 瑞芳 as 一等")

        XCTAssertEqual(data.stationClass(forStation: "八堵"), .second)

        XCTAssertEqual(data.stationClass(forStation: "四腳亭"), .third)
        XCTAssertEqual(data.stationClass(forStation: "三貂嶺"), .third)

        // Tier levels
        XCTAssertEqual(TRAStationClass.special.tier, 0)
        XCTAssertEqual(TRAStationClass.first.tier, 1)
        XCTAssertEqual(TRAStationClass.second.tier, 2)
        XCTAssertEqual(TRAStationClass.third.tier, 3)
        XCTAssertEqual(TRAStationClass.simple.tier, 4)
        XCTAssertEqual(TRAStationClass.halt.tier, 4)

        // Localization
        XCTAssertEqual(TRAStationClass.special.name(in: .traditionalChinese), "特等站")
        XCTAssertEqual(TRAStationClass.special.name(in: .english), "Special Class")
    }

    // MARK: - Station Info

    func testStationInfoLoadsAndQueries() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.stationInfos.count, 246, "246 TRA station info records")

        let keelung = try XCTUnwrap(data.stationInfo(forStation: "基隆"))
        XCTAssertEqual(keelung.id, "0900")
        XCTAssertEqual(keelung.name, "基隆")
        XCTAssertTrue(keelung.address.contains("基隆市"))
        XCTAssertEqual(keelung.latitude, 25.13191, accuracy: 0.001)
        XCTAssertEqual(keelung.longitude, 121.73837, accuracy: 0.001)

        // Lookup by ID
        let byID = try XCTUnwrap(data.stationInfo(id: "0900"))
        XCTAssertEqual(byID.name, "基隆")

        let taipei = try XCTUnwrap(data.stationInfo(forStation: "台北"))
        XCTAssertEqual(taipei.id, "1000")
    }

    // MARK: - TRTC Station Codes

    func testXinchengAliasesResolveTheSameOfficialStationData() throws {
        let data = try Self.makeStationData()
        let platform = try XCTUnwrap(data.platforms["新城"])
        let northSection = try XCTUnwrap(data.trackSections["崇德|新城"])
        let southSection = try XCTUnwrap(data.trackSections["新城|景美"])
        for name in ["新城", "新城 (太魯閣)", "新城(太魯閣)", "新城　（太魯閣）"] {
            XCTAssertEqual(data.stationInfo(forStation: name)?.id, "7030", name)
            XCTAssertEqual(data.stationClass(forStation: name), .second, name)
            XCTAssertEqual(data.platform(forStation: name), platform, name)
            XCTAssertEqual(data.trackSection(between: name, and: "崇德"), northSection, name)
            XCTAssertEqual(data.trackSection(between: "景美", and: name), southSection, name)
        }
        XCTAssertNil(data.stationInfo(forStation: "新城北"), "Aliases must not match by prefix")
    }

    func testZuoyingOldCityAliasResolvesOfficialMetadata() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.stationInfo(forStation: "左營(舊城)")?.id, "4350")
        XCTAssertEqual(data.platform(forStation: "左營 (舊城)"), data.platforms["左營"])
        XCTAssertEqual(data.stationClass(forStation: "左營(舊城)"), .simple)
        XCTAssertEqual(data.stationInfo(forStation: "新左營")?.id, "4340")
    }

    func testDiscoveryNameConnectsToMetadataWithoutChangingItsIdentity() throws {
        let data = try Self.makeStationData()
        let railways = try RealRailways(
            lines: Self.bundledFile("track_lines.geojson"),
            stations: Self.bundledFile("track_stations.geojson"),
            names: Self.bundledFile("station_names.json")
        )
        let station = try XCTUnwrap(railways.stations.first { $0.id == "tra_sched|新城 (太魯閣)" })
        let name = station.name(in: .traditionalChinese)
        XCTAssertEqual(name, "新城 (太魯閣)")
        XCTAssertEqual(railways.stations(matching: "新城(太魯閣)").map(\.id), [station.id])
        XCTAssertEqual(data.stationInfo(forStation: name)?.id, "7030")
        XCTAssertEqual(data.stationClass(forStation: name), .second)
        XCTAssertNotNil(data.platform(forStation: name))
        XCTAssertEqual(data.tracksBetween(stationA: name, stationB: "崇德"), 2)
    }

    func testTRTCStationCodesLoadAndQuery() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.trtcCodes.count, 122, "122 TRTC station code records")

        let dingpu = try XCTUnwrap(data.trtcStation(code: "BL01"))
        XCTAssertEqual(dingpu.name, "頂埔")
        XCTAssertEqual(dingpu.placements.first?.line, "BL")

        // Stations with multiple codes (interchange stations)
        let tpeCodes = data.trtcCodes(forStation: "台北車站")
        XCTAssertTrue(tpeCodes.contains("BL12"))
        XCTAssertTrue(tpeCodes.contains("R10"))
    }

    // MARK: - Platforms

    func testPlatformsLoadAndMeasure() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.platforms.count, 239, "197 measured + 42 derived platforms")
        XCTAssertEqual(data.estimatedPlatformLengthsByTier, [378, 330, 307, 270, 188])

        let keelungPlatform = try XCTUnwrap(data.platform(forStation: "基隆"))
        XCTAssertFalse(keelungPlatform.isDerived)
        XCTAssertGreaterThan(keelungPlatform.lengthMetres, 150)

        let fuzhouPlatform = try XCTUnwrap(data.platform(forStation: "浮洲"))
        XCTAssertTrue(fuzhouPlatform.isDerived)

        // Estimated length by station class
        XCTAssertEqual(data.estimatedPlatformLength(for: .special), 378)
        XCTAssertEqual(data.estimatedPlatformLength(for: .first), 330)
        XCTAssertEqual(data.estimatedPlatformLength(for: .third), 270)
        XCTAssertEqual(data.estimatedPlatformLength(for: .simple), 188)
    }

    // MARK: - Track Sections (Single/Double Track)

    func testTrackSectionsLoadAndQuery() throws {
        let data = try Self.makeStationData()
        XCTAssertEqual(data.trackSections.count, 243, "243 adjacent station pairs")

        // Double track section
        let qiduBadu = try XCTUnwrap(data.trackSection(between: "七堵", and: "八堵"))
        XCTAssertEqual(qiduBadu.tracks, 2)
        XCTAssertTrue(qiduBadu.isDoubleTrack)
        XCTAssertEqual(data.tracksBetween(stationA: "七堵", stationB: "八堵"), 2)
        XCTAssertEqual(data.tracksBetween(stationA: "八堵", stationB: "七堵"), 2, "Order independent")
        XCTAssertTrue(data.isDoubleTrack(between: "七堵", and: "八堵"))

        // Single track section (Pingxi Line)
        let shifenWanggu = try XCTUnwrap(data.trackSection(between: "十分", and: "望古"))
        XCTAssertEqual(shifenWanggu.tracks, 1)
        XCTAssertFalse(shifenWanggu.isDoubleTrack)
        XCTAssertEqual(data.tracksBetween(stationA: "望古", stationB: "十分"), 1)
    }
}
