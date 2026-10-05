import Foundation
import GameCore
import GamePresentation
import XCTest

/// Taiwan's real railways under a real-world map: the `Railway/` site's
/// files as the app bundles them, read and drawn as the site draws them.
final class RealRailwaysTests: XCTestCase {
    /// The files the app bundles (`RailwayGameApp/Resources/RealRailways/`),
    /// read from the repository.
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private static func bundled() throws -> RealRailways {
        try RealRailways(
            lines: bundledFile("track_lines.geojson"),
            stations: bundledFile("track_stations.geojson"),
            names: bundledFile("station_names.json")
        )
    }

    private let taipei = RealWorldPlace.standard.anchor

    // MARK: - The site's files

    func testTheBundledFilesReadWhole() throws {
        let railways = try Self.bundled()
        XCTAssertEqual(railways.lines.count, 79, "every piece of every line")
        XCTAssertEqual(railways.stationMarks.count, 608, "every station on every line")
        XCTAssertEqual(railways.stations.count, 544, "once for each name in each system")
        XCTAssertEqual(railways.lines.map(\.id), Array(0 ..< 79), "in the file's order")
        XCTAssertEqual(Set(railways.stations.map(\.id)).count, 544)
        XCTAssertEqual(Set(railways.lines.map(\.system)), Set(RealRailways.System.all), "every system has a line")

        let counts = Dictionary(grouping: railways.stations, by: \.system.id).mapValues(\.count)
        XCTAssertEqual(counts, [
            "tra_sched": 242, "thsr_sched": 12, "afr_sched": 21, "mrt": 119, "tymc": 22,
            "ntdlrt": 14, "ntalrt": 9, "sanying": 12, "krtc": 75, "tmrt": 18,
        ])

        // Pingzhen, on the trunk line since the 2026-10-05 snapshot.
        let pingzhen = try XCTUnwrap(railways.stations.first { $0.id == "tra_sched|平鎮" })
        XCTAssertEqual(pingzhen.coordinate, RealRailways.Coordinate(latitude: 24.944038, longitude: 121.215443))

        // All of it in Taiwan.
        let points = railways.lines.flatMap(\.points) + railways.stationMarks.map(\.coordinate)
        for point in points {
            XCTAssertTrue((21.8 ... 25.4).contains(point.latitude), "\(point)")
            XCTAssertTrue((119.9 ... 122.1).contains(point.longitude), "\(point)")
        }
        XCTAssertTrue(railways.lines.allSatisfy { $0.points.count >= 2 && $0.sortKey >= 0 })
    }

    /// Where the site's shapes are off the real track, the game redraws them
    /// from OpenStreetMap (`tools/real-railways/osm_patches.json`): the
    /// bundled lines carry every stretch the patches list, so copying the
    /// site's original file over them again cannot quietly undo them.
    func testTheStretchesRedrawnFromOpenStreetMapAreBundled() throws {
        struct Patches: Decodable {
            struct Patch: Decodable {
                let id: String
                let lineKey: String
                let points: [[Double]]
            }

            let patches: [Patch]
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let patches = try JSONDecoder().decode(
            Patches.self,
            from: Data(contentsOf: root.appendingPathComponent("tools/real-railways/osm_patches.json"))
        ).patches
        XCTAssertEqual(patches.map(\.id), ["krtc-red-airport", "krtc-orange-yanchengpu", "afr-zhushan"])

        let railways = try Self.bundled()
        for patch in patches {
            let system = String(patch.lineKey.prefix { $0 != "|" })
            let stretch = patch.points.map { RealRailways.Coordinate(latitude: $0[1], longitude: $0[0]) }
            let carried = railways.lines.contains { line in
                line.system.id == system && line.points.count >= stretch.count
                    && (0 ... line.points.count - stretch.count).contains { Array(line.points[$0 ..< $0 + stretch.count]) == stretch }
            }
            XCTAssertTrue(carried, patch.id)
        }
    }

    func testTheFirstLineAsTheSiteHasIt() throws {
        let line = try XCTUnwrap(Self.bundled().lines.first)
        XCTAssertEqual(line.system.id, "tra_sched")
        XCTAssertEqual(line.name, "縱貫線北段（基隆–竹南）")
        XCTAssertEqual(line.sortKey, 0)
        XCTAssertEqual(line.points.first, RealRailways.Coordinate(latitude: 25.13369, longitude: 121.739691))
        XCTAssertEqual(line.points.count, 485)
    }

    /// The site's `railMix`, ported: mixing each line's own colour as the
    /// site does gives every colour its files have mixed in advance, for
    /// every line, look and map theme.
    func testColoursMixAsTheSiteMixesThem() throws {
        struct File: Decodable {
            struct Feature: Decodable {
                let properties: [String: AnyValue]
            }

            let features: [Feature]
        }
        enum AnyValue: Decodable {
            case text(String), number(Double)
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .text(text) } else { self = .number(try container.decode(Double.self)) }
            }

            var text: String? {
                if case .text(let text) = self { text } else { nil }
            }
        }
        let features = try JSONDecoder().decode(File.self, from: Self.bundledFile("track_lines.geojson")).features
        XCTAssertEqual(features.count, 79)
        let looks: [(String, RealRailways.TrackStyle, RealRailways.MapTheme)] = [
            ("colorDark", .auto, .dark),
            ("colorFaintLight", .faint, .light), ("colorFaintDark", .faint, .dark), ("colorFaintSat", .faint, .satellite),
            ("colorHiddenLight", .hidden, .light), ("colorHiddenDark", .hidden, .dark), ("colorHiddenSat", .hidden, .satellite),
        ]
        for feature in features {
            let own = try XCTUnwrap(RealRailways.RGB(hex: try XCTUnwrap(feature.properties["color"]?.text)))
            let palette = RealRailways.Palette(color: own)
            XCTAssertEqual(palette.color(.auto, on: .light), own)
            XCTAssertEqual(palette.color(.auto, on: .satellite), own, "the line's own colour on imagery")
            for (key, style, theme) in looks {
                let mixed = try XCTUnwrap(feature.properties[key]?.text)
                XCTAssertEqual(palette.color(style, on: theme), RealRailways.RGB(hex: mixed), "\(key) of \(own)")
            }
        }
        XCTAssertEqual(RealRailways.MapTheme.light.casing, RealRailways.RGB(hex: "#f2ede2"))
        XCTAssertEqual(RealRailways.MapTheme.dark.casing, RealRailways.RGB(hex: "#10141c"))
        XCTAssertEqual(RealRailways.MapTheme.satellite.casing, RealRailways.RGB(hex: "#24382c"))
    }

    /// Every line in its official colour, none made up and none the site's
    /// (2026-10-05, the author's requests): the TRA, High Speed Rail and
    /// Alishan Forest Railway lines in their operator's, every other line in
    /// its own as its operator or TDX has it. A line's pieces and stations
    /// share it.
    func testEachLineHasItsOfficialColour() throws {
        let railways = try Self.bundled()
        let operators = ["tra_sched": "#005792", "thsr_sched": "#DB5009", "afr_sched": "#C41229"]
        let lines = [
            "文湖線": "#C48C31", "淡水信義線": "#E3002C", "新北投支線": "#F3A5A8", "松山新店線": "#008659",
            "小碧潭支線": "#DAE11B", "中和新蘆線（迴龍）": "#F8B61C", "中和新蘆線（蘆洲）": "#F8B61C",
            "板南線": "#0070BD", "環狀線": "#FFDB00", "機場捷運": "#8246AF", "綠山線": "#FF2A00",
            "藍海線": "#FF2A00", "安坑輕軌": "#9E925E", "三鶯線": "#47C1E1", "紅線": "#E30964",
            "橘線": "#FF9500", "環狀輕軌": "#8FC31F", "綠線": "#84BD00",
        ]
        func palette(_ hex: String) throws -> RealRailways.Palette {
            RealRailways.Palette(color: try XCTUnwrap(RealRailways.RGB(hex: hex), hex))
        }
        for system in RealRailways.System.all {
            XCTAssertEqual(system.operatorColor, operators[system.id].flatMap(RealRailways.RGB.init(hex:)), system.id)
        }
        var drawn: Set<String> = []
        for line in railways.lines {
            if let hex = operators[line.system.id] {
                XCTAssertEqual(line.palette, try palette(hex), line.name)
            } else {
                XCTAssertEqual(line.palette, try palette(try XCTUnwrap(lines[line.name], line.name)), line.name)
                drawn.insert(line.name)
            }
        }
        XCTAssertEqual(drawn, Set(lines.keys), "every line listed is drawn")
        XCTAssertNotEqual(railways.lines.first?.palette.color, RealRailways.RGB(hex: "#2E6FB0"), "not the site's colour for the trunk line")

        // Stations are in their line's colour.
        let lineColors = Set(railways.lines.map(\.palette))
        for mark in railways.stationMarks {
            XCTAssertTrue(lineColors.contains(mark.palette))
        }
        XCTAssertEqual(try XCTUnwrap(railways.stations.first).palette, try palette("#005792"), "Keelung")
        XCTAssertEqual(try XCTUnwrap(railways.stations.first { $0.id == "mrt|頂埔" }).palette, try palette("#0070BD"))
        XCTAssertEqual(try XCTUnwrap(railways.stations.first { $0.id == "mrt|新北投" }).palette, try palette("#F3A5A8"))
        XCTAssertEqual(try XCTUnwrap(railways.stations.first { $0.id == "sanying|頂埔" }).palette, try palette("#47C1E1"))

        XCTAssertEqual(RealRailways.Palette.mix(.init(red: 200, green: 0, blue: 100), into: .init(red: 0, green: 100, blue: 0), keeping: 0.5), .init(red: 100, green: 50, blue: 50))
    }

    func testColoursAreSixHexDigits() {
        XCTAssertEqual(RealRailways.RGB(hex: "#2E6FB0"), RealRailways.RGB(red: 0x2E, green: 0x6F, blue: 0xB0))
        XCTAssertEqual(RealRailways.RGB(hex: "#ffffff"), RealRailways.RGB(red: 255, green: 255, blue: 255))
        for bad in ["", "#", "2E6FB0", "#2E6FB", "#2E6FB0F", "#GG0000", "#+1+1+1", "#-10000"] {
            XCTAssertNil(RealRailways.RGB(hex: bad), bad)
        }
    }

    func testAFileOutOfShapeIsRefused() throws {
        let names = try Self.bundledFile("station_names.json")
        let stations = try Self.bundledFile("track_stations.geojson")
        func lines(_ properties: String, _ coordinates: String) -> Data {
            Data(#"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{\#(properties)},"geometry":{"type":"LineString","coordinates":\#(coordinates)}}]}"#.utf8)
        }
        let good = #""sys":"mrt","name":"板南線","sortKey":0,"lineKey":"mrt|BL""#
        XCTAssertEqual(try RealRailways(lines: lines(good, "[[121.5,25.0],[121.6,25.1]]"), stations: stations, names: names).lines.count, 1)

        XCTAssertThrowsError(try RealRailways(lines: lines(good, "[[121.5,25.0]]"), stations: stations, names: names)) {
            XCTAssertEqual($0 as? RealRailways.LoadError, .invalidCoordinate, "a line needs two points")
        }
        XCTAssertThrowsError(try RealRailways(lines: lines(good, "[[121.5,95.0],[121.6,25.1]]"), stations: stations, names: names)) {
            XCTAssertEqual($0 as? RealRailways.LoadError, .invalidCoordinate)
        }
        let unknown = #""sys":"bus","name":"A","sortKey":0,"lineKey":"bus|A""#
        XCTAssertThrowsError(try RealRailways(lines: lines(unknown, "[[121.5,25.0],[121.6,25.1]]"), stations: stations, names: names)) {
            XCTAssertEqual($0 as? RealRailways.LoadError, .unknownSystem("bus"))
        }
        let uncoloured = #""sys":"mrt","name":"A","sortKey":0,"lineKey":"mrt|A""#
        XCTAssertThrowsError(try RealRailways(lines: lines(uncoloured, "[[121.5,25.0],[121.6,25.1]]"), stations: stations, names: names)) {
            XCTAssertEqual($0 as? RealRailways.LoadError, .noOfficialColor(lineKey: "mrt|A"), "no colour is made up for a line")
        }
    }

    // MARK: - Stations

    func testStationsHaveTheSitesNames() throws {
        let railways = try Self.bundled()
        let taipeiMain = try XCTUnwrap(railways.stations.first { $0.id == "mrt|台北車站" })
        XCTAssertEqual(taipeiMain.name(in: .english), "Taipei Main Station")
        XCTAssertEqual(taipeiMain.name(in: .traditionalChinese), "台北車站")
        XCTAssertEqual(taipeiMain.system.name(in: .english), "Taipei Metro")
        XCTAssertEqual(taipeiMain.system.name(in: .traditionalChinese), "台北捷運")

        let first = try XCTUnwrap(railways.stations.first)
        XCTAssertEqual(first.id, "tra_sched|基隆")
        XCTAssertEqual(first.name(in: .english), "Keelung")

        // The site has no English name for these five: the Chinese one.
        for id in ["tra_sched|左營(舊城)", "tra_sched|枋野", "tra_sched|新城 (太魯閣)", "tra_sched|新馬", "tra_sched|平鎮"] {
            let station = try XCTUnwrap(railways.stations.first { $0.id == id }, id)
            XCTAssertEqual(station.name(in: .english), station.name(in: .traditionalChinese), id)
        }
        XCTAssertEqual(railways.stations.filter { $0.name(in: .english) == $0.name(in: .traditionalChinese) }.count, 5)
    }

    /// The TRA's Taipei is the same point as the place the picker had
    /// before (both OpenStreetMap's, six decimals here and seven there).
    func testAStationsAnchorIsWhereItIs() throws {
        let station = try XCTUnwrap(Self.bundled().stations.first { $0.id == "tra_sched|臺北" })
        XCTAssertEqual(station.coordinate, RealRailways.Coordinate(latitude: 25.047931, longitude: 121.517005))
        XCTAssertEqual(station.anchor, GeoAnchor(latitude: 250_479_310, longitude: 1_215_170_050))
        let anchor = try XCTUnwrap(station.anchor)
        XCTAssertEqual(abs(anchor.latitude - taipei.latitude), 2)
        XCTAssertEqual(abs(anchor.longitude - taipei.longitude), 4)
    }

    /// As the site matches names: 臺 and 台 alike, spaces and case ignored,
    /// in Chinese or English; names it starts first.
    func testStationsMatchAsTheSiteMatchesNames() throws {
        let railways = try Self.bundled()
        XCTAssertEqual(RealRailways.normalized(" 臺北 Main "), "台北main")

        let taipei = railways.stations(matching: "台北").map(\.id)
        XCTAssertEqual(Array(taipei.prefix(4)), ["tra_sched|臺北", "thsr_sched|台北", "mrt|台北101/世貿", "mrt|台北車站"])
        XCTAssertEqual(railways.stations(matching: "臺北").map(\.id), taipei, "臺 is 台")
        XCTAssertEqual(
            Array(taipei.prefix(10)),
            ["tra_sched|臺北", "thsr_sched|台北", "mrt|台北101/世貿", "mrt|台北車站", "mrt|台北小巨蛋", "mrt|台北橋",
             "tymc|台北車站", "ntdlrt|台北海洋大學", "ntalrt|台北小城", "sanying|臺北大學"],
            "the names it starts, in the site's order"
        )
        XCTAssertEqual(taipei.count, 10)
        XCTAssertEqual(railways.stations(matching: "北投").map(\.id), ["mrt|北投", "mrt|新北投"], "then the names it is in")
        XCTAssertEqual(railways.stations(matching: "beitou").map(\.id), ["mrt|北投", "mrt|新北投"])

        XCTAssertEqual(railways.stations(matching: "BANQIAO").map(\.id), ["tra_sched|板橋", "thsr_sched|板橋", "mrt|板橋"])
        XCTAssertEqual(railways.stations(matching: "Taipei Main Station").map(\.id), ["mrt|台北車站", "tymc|台北車站"])
        XCTAssertEqual(railways.stations(matching: "   "), [])
        XCTAssertEqual(railways.stations(matching: "Atlantis"), [])
    }

    // MARK: - Near a map

    /// The lines and stations within a new game's map round Taipei Main
    /// Station: Taipei's metro, the TRA and the High Speed Rail, not
    /// Kaohsiung's metro.
    func testOnlyTheRailwaysNearAMap() throws {
        let railways = try Self.bundled()
        let reach = RealWorldFrame.halfExtent(of: GameWorld.newGameBounds).east
        let lines = railways.lines(near: taipei, within: reach)
        XCTAssertEqual(lines.count, 40)
        XCTAssertEqual(
            Set(lines.map(\.name)),
            ["中和新蘆線（蘆洲）", "中和新蘆線（迴龍）", "安坑輕軌", "小碧潭支線", "文湖線", "松山新店線", "板南線",
             "機場捷運", "淡水信義線", "環狀線", "縱貫線北段（基隆–竹南）", "高鐵"]
        )
        XCTAssertEqual(railways.stationMarks(near: taipei, within: reach).count, 138)
        XCTAssertTrue(railways.stationMarks(near: taipei, within: reach).contains { $0.system.id == "thsr_sched" })

        let newYork = GeoAnchor(latitude: 407_128_000, longitude: -740_060_000)!
        XCTAssertTrue(railways.lines(near: newYork, within: reach).isEmpty, "nothing away from Taiwan")
        XCTAssertTrue(railways.stationMarks(near: newYork, within: reach).isEmpty)
    }

    // MARK: - Settings and credits

    func testTrackStylesAreTheSites() {
        XCTAssertEqual(RealRailways.TrackStyle.allCases.map(\.rawValue), ["auto", "faint", "hidden"], "kept in the settings")
        XCTAssertEqual(RealRailways.TrackStyle.allCases.map { $0.name(in: .english) }, ["Auto", "Faint", "Hide"])
        XCTAssertEqual(RealRailways.TrackStyle.allCases.map { $0.name(in: .traditionalChinese) }, ["自動", "淡化", "隱藏"])
        XCTAssertEqual(RealRailways.System.all.map { $0.name(in: .traditionalChinese) }, [
            "台鐵", "高鐵", "阿里山林鐵", "台北捷運", "桃園機捷", "淡海輕軌", "安坑輕軌", "三鶯線", "高雄捷運", "台中捷運",
        ])
        XCTAssertEqual(RealRailways.Widths.casing, 5.6)
        XCTAssertEqual(RealRailways.Widths.line, 3)
        XCTAssertEqual(RealRailways.Widths.stationsMinimumZoom, 11)
    }

    /// Every source names its licence, in both languages, and links work as
    /// URLs.
    func testEverySourceIsCredited() throws {
        for language in DisplayLanguage.allCases {
            let sections = DataSourceCredits.sections(in: language)
            XCTAssertEqual(sections.map(\.id), ["railways", "places", "map"])
            let credits = sections.flatMap(\.credits)
            XCTAssertEqual(credits.map(\.id), ["tdx", "openStreetMap", "operators", "places", "appleMaps"])
            for credit in credits {
                XCTAssertFalse(credit.title.isEmpty || credit.detail.isEmpty || credit.notice.isEmpty, credit.id)
                for link in credit.links {
                    let url = try XCTUnwrap(URL(string: link.url), link.url)
                    XCTAssertEqual(url.scheme, "https", link.url)
                }
            }
            let openStreetMap = try XCTUnwrap(credits.first { $0.id == "openStreetMap" })
            XCTAssertTrue(openStreetMap.notice.contains("© OpenStreetMap"))
            XCTAssertTrue(openStreetMap.notice.contains("ODbL"))
            XCTAssertTrue(openStreetMap.links.contains { $0.url == "https://opendatacommons.org/licenses/odbl/1-0/" })
            XCTAssertTrue(credits.first { $0.id == "tdx" }?.links.contains { $0.url == "https://data.gov.tw/license" } == true)
        }
        XCTAssertEqual(DataSourceCredits.railwaysOnMap(in: .english), "Railways: MOTC TDX, © OpenStreetMap contributors")
        XCTAssertEqual(DataSourceCredits.railwaysOnMap(in: .traditionalChinese), "鐵道：交通部 TDX、© OpenStreetMap 貢獻者")
        XCTAssertEqual(
            DataSourceCredits.sections(in: .traditionalChinese).first?.credits.first?.notice,
            "依政府資料開放授權條款第 1 版使用。"
        )
    }
}
