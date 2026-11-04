import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 569: a new station on a real-world map is named after a
/// landmark right there, and is offered the names of the landmarks, park,
/// road and crossing round it.
final class StationLandmarkNamingTests: XCTestCase {
    private static let bundled: PlaceNames? = {
        let directory = BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld")
        guard var names = (try? Data(contentsOf: directory.appendingPathComponent("taiwan_place_names.json"))).flatMap({ try? PlaceNames(data: $0) })
        else { return nil }
        names.landmarks = (try? Data(contentsOf: directory.appendingPathComponent("taiwan_station_landmarks.json")))
            .flatMap { try? StationLandmarks(data: $0) }
        return names
    }()

    private func bundled() throws -> PlaceNames {
        let names = try XCTUnwrap(Self.bundled, "The app's place names file reads")
        XCTAssertNotNil(names.landmarks, "The app's landmarks file reads")
        return names
    }

    private func landmarks() throws -> StationLandmarks {
        try XCTUnwrap(try bundled().landmarks)
    }

    // MARK: - Crossing names

    func testACrossingIsNamedAsTaiwansMetroNamesIt() {
        XCTAssertEqual(StationLandmarks.crossingName("南京東路", "復興北路"), "南京復興")
        XCTAssertEqual(StationLandmarks.crossingName("南京東路三段", "復興北路"), "南京復興")
        XCTAssertEqual(StationLandmarks.crossingName("凱旋四路", "中華五路"), "凱旋中華")
        XCTAssertEqual(StationLandmarks.crossingName("忠孝東路", "敦化南路"), "忠孝敦化")
        XCTAssertEqual(StationLandmarks.crossingName("臺灣大道", "文心路"), "臺灣文心")
        XCTAssertEqual(StationLandmarks.crossingName("一心二路", "三多四路"), "一心三多")
        XCTAssertEqual(StationLandmarks.roadStem("中山北路二段"), "中山")
        XCTAssertEqual(StationLandmarks.roadStem("八德路"), "八德")
        XCTAssertEqual(StationLandmarks.roadStem("民權西路"), "民權")
    }

    func testACrossingThatShortensBadlyHasNoName() {
        // The same road on both sides.
        XCTAssertNil(StationLandmarks.crossingName("南京東路", "南京西路"))
        XCTAssertNil(StationLandmarks.crossingName("中山路", "中山北路"))
        // One character left.
        XCTAssertNil(StationLandmarks.crossingName("中一路", "復興路"))
        XCTAssertNil(StationLandmarks.roadStem("北路"))
        // No road.
        XCTAssertNil(StationLandmarks.crossingName("台1線", "復興路"))
    }

    func testACrossingsEnglishNameDropsTheRoadsKindSideAndNumber() {
        XCTAssertEqual(StationLandmarks.crossingName(english: "Nanjing East Road", "Fuxing North Road"), "Nanjing Fuxing")
        XCTAssertEqual(StationLandmarks.crossingName(english: "Kaisyuan 4th Road", "JhongHua 5th Road"), "Kaisyuan JhongHua")
        XCTAssertEqual(StationLandmarks.roadStem(english: "Section 1, Minsheng North Road"), "Minsheng")
        XCTAssertEqual(StationLandmarks.roadStem(english: "Zhongxiao E. Rd."), "Zhongxiao")
        XCTAssertNil(StationLandmarks.crossingName(english: "Nanjing East Road", "Nanjing West Road"))
    }

    // MARK: - The bundled file

    func testTheBundledFileHasTaiwansLandmarksRoadsAndCrossings() throws {
        let file = try landmarks()
        XCTAssertGreaterThan(file.landmarks.count, 1_500)
        for kind in StationLandmarks.Kind.allCases {
            XCTAssertGreaterThan(file.landmarks.filter { $0.kind == kind }.count, 100, "\(kind)")
        }
        XCTAssertGreaterThan(file.roads.count, 4_000)
        XCTAssertGreaterThan(file.crossings.count, 10_000)
        // None in Xiamen, which the extract reaches.
        XCTAssertTrue(file.landmarks(near: RealRailways.Coordinate(latitude: 24.48, longitude: 118.09), within: 5_000).isEmpty)
    }

    func testTaipeisAndKaohsiungsCrossingsAreNamed() throws {
        let file = try landmarks()
        // Nanjing Fuxing (Taipei Metro), and Kaixuan Zhonghua (Kaohsiung's
        // light rail, C7).
        let nanjingFuxing = RealRailways.Coordinate(latitude: 25.05190, longitude: 121.54400)
        XCTAssertEqual(file.crossings(near: nanjingFuxing, within: 150).first?.thing.chinese, "南京復興")
        XCTAssertEqual(file.crossings(near: nanjingFuxing, within: 150).first?.thing.english, "NanJing Fuxing")
        let kaixuanZhonghua = RealRailways.Coordinate(latitude: 22.59352, longitude: 120.30988)
        XCTAssertEqual(file.crossings(near: kaixuanZhonghua, within: 150).first?.thing.chinese, "凱旋中華")
        // The road: Minquan West Road, west of the station of that name.
        let minquan = RealRailways.Coordinate(latitude: 25.06270, longitude: 121.51800)
        XCTAssertEqual(file.road(near: minquan, within: 150)?.thing.chinese, "民權西路")
    }

    func testTaipeisAndKaohsiungsLandmarksAreThere() throws {
        let file = try landmarks()
        func names(_ latitude: Double, _ longitude: Double, _ kind: StationLandmarks.Kind) -> [String] {
            file.landmarks(near: RealRailways.Coordinate(latitude: latitude, longitude: longitude), within: 1_000)
                .filter { $0.thing.kind == kind }.map(\.thing.name.chinese)
        }
        XCTAssertTrue(names(25.0173, 121.5397, .university).contains("臺灣大學"), "\(names(25.0173, 121.5397, .university))")
        XCTAssertTrue(names(25.0373, 121.5126, .school).contains("第一女中"), "\(names(25.0373, 121.5126, .school))")
        XCTAssertTrue(names(25.1200, 121.5200, .hospital).contains { $0.contains("榮民總醫院") }, "\(names(25.1200, 121.5200, .hospital))")
        XCTAssertTrue(names(25.0320, 121.5360, .park).contains("大安森林公園"), "\(names(25.0320, 121.5360, .park))")
        XCTAssertTrue(names(22.6219, 120.2983, .park).contains { $0.contains("中央公園") }, "\(names(22.6219, 120.2983, .park))")
        XCTAssertTrue(names(22.6316, 120.3003, .market).contains("六合夜市"), "\(names(22.6316, 120.3003, .market))")
    }

    // MARK: - Naming

    private func world(at latitude: Double, _ longitude: Double) throws -> GameWorld {
        GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
    }

    func testALandmarkRightThereNamesTheStation() throws {
        let railways = try BundledRealData.railways()
        let names = try bundled()
        // No real station within 800 m of any of them.
        let examples: [(Double, Double, String, String)] = [
            (25.02381, 121.50554, "青年公園", "Youth Park"),  // Taipei, Wanhua
            (22.67968, 120.32393, "高雄榮民總醫院", "Kaohsiung Veterans General Hospital"),  // Kaohsiung, Zuoying
            (22.62144, 120.31390, "復華高中", "Fuhwa Senior High School"),  // Kaohsiung, Lingya
        ]
        for (latitude, longitude, chinese, english) in examples {
            let at = RealRailways.Coordinate(latitude: latitude, longitude: longitude)
            XCTAssertNil(railways.nearestStation(to: at, maximumDistanceMetres: GameSession.realStationNamingDistanceMetres), chinese)
            let world = try world(at: latitude, longitude)
            let here = try BundledRealData.point(at, in: world)
            XCTAssertEqual(GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names), chinese)
            let shown = GameSession.suggestedStationName(for: world, at: here, in: .english, railways: railways, placeNames: names)
            XCTAssertTrue(shown == english || shown == chinese, "\(chinese): \(shown)")
            // Without the landmarks, the place, as before.
            var plain = names
            plain.landmarks = nil
            XCTAssertNotEqual(GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: plain), chinese)
        }
    }

    func testALandmarkThatIsARealStationsNameIsNotOffered() throws {
        let railways = try BundledRealData.railways()
        let names = try bundled()
        // Daan Forest Park is a Taipei Metro station's name: away from the
        // station, the park does not name another.
        let middle = RealRailways.Coordinate(latitude: 25.0300, longitude: 121.5355)
        let world = try world(at: middle.latitude, middle.longitude)
        let here = try BundledRealData.point(middle, in: world)
        XCTAssertNotEqual(
            GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names, maximumDistanceMetres: 0),
            "大安森林公園"
        )
    }

    func testARealStationStillComesFirst() throws {
        let railways = try BundledRealData.railways()
        let tra = try BundledRealData.station("猴硐", in: "tra_sched")
        let world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let houtong = try BundledRealData.point(tra.coordinate, in: world)
        XCTAssertEqual(
            GameSession.suggestedStationName(for: world, at: houtong, in: .traditionalChinese, railways: railways, placeNames: try bundled()),
            "猴硐"
        )
        let choices = GameSession.stationNameChoices(for: world, at: houtong, in: .traditionalChinese, railways: railways, placeNames: try bundled())
        XCTAssertEqual(choices.first, StationNameChoice(name: "猴硐", kind: .realStation))
    }

    func testTheChoicesOfferTheLandmarksRoadAndCrossing() throws {
        let railways = try BundledRealData.railways()
        let names = try bundled()
        // Kaohsiung, Liuhe Night Market's east end at Zhongshan 1st Road.
        let at = RealRailways.Coordinate(latitude: 22.6317, longitude: 120.3010)
        let world = try world(at: at.latitude, at.longitude)
        let here = try BundledRealData.point(at, in: world)
        let choices = GameSession.stationNameChoices(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names)
        XCTAssertLessThanOrEqual(choices.count, GameSession.stationNameChoiceLimit)
        XCTAssertEqual(
            choices.first?.name,
            GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names)
        )
        XCTAssertEqual(Set(choices.map(\.name)).count, choices.count, "Each name once")
        XCTAssertTrue(choices.contains { $0.kind == .crossing || $0.kind == .road }, "\(choices)")
        for choice in choices where choice.kind != .realStation {
            XCTAssertTrue(railways.stations(named: choice.name, near: nil).isEmpty, "\(choice.name) is a real station's name")
        }
        // English: the English names, the Chinese one where there is none.
        let english = GameSession.stationNameChoices(for: world, at: here, in: .english, railways: railways, placeNames: names)
        XCTAssertEqual(english.count, choices.count)
    }

    func testATakenLandmarkIsNotOfferedAgain() throws {
        let railways = try BundledRealData.railways()
        let names = try bundled()
        let park = RealRailways.Coordinate(latitude: 25.02381, longitude: 121.50554)
        var world = try world(at: park.latitude, park.longitude)
        let here = try BundledRealData.point(park, in: world)
        _ = try world.buildStation(named: "青年公園", at: PlanPoint(x: here.x + 50, y: here.y))
        let next = GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names)
        XCTAssertNotEqual(next, "青年公園")
        XCTAssertFalse(next.hasPrefix("車站"), next)
        let choices = GameSession.stationNameChoices(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names)
        XCTAssertFalse(choices.contains { $0.name == "青年公園" })
    }

    func testABusStopsNameIsTidiedForAStation() {
        XCTAssertEqual(GameSession.busStopStationName("前鎮高中(中山四路)"), "前鎮高中")
        XCTAssertEqual(GameSession.busStopStationName("五分埔商圈（中坡北）"), "五分埔商圈")
        XCTAssertEqual(GameSession.busStopStationName("榮總(往石牌)"), "榮總")
        // A station's own stops.
        XCTAssertNil(GameSession.busStopStationName("捷運三多商圈站(中山二路)"))
        XCTAssertNil(GameSession.busStopStationName("臺北車站(忠孝)"))
        XCTAssertNil(GameSession.busStopStationName("高鐵左營站"))
        XCTAssertNil(GameSession.busStopStationName("鳳山火車站"))
        XCTAssertNil(GameSession.busStopStationName("(往市區)"))
    }

    @MainActor
    func testTheNearestBusStopIsOfferedTidied() throws {
        let names = try bundled()
        let at = RealRailways.Coordinate(latitude: 25.0300, longitude: 121.5355)
        let world = try world(at: at.latitude, at.longitude)
        let here = try BundledRealData.point(at, in: world)
        // Two stops: a metro station's (left out) and a school's.
        let files = try BusStopLabelsTests.busFiles([
            ("捷運大安森林公園站(新生南路)", at.latitude + 0.0003, at.longitude),
            ("某某高中(新生南路)", at.latitude + 0.0006, at.longitude),
        ])
        let buses = try RealBusLibrary(index: files.index, file: files.file)
                let choices = GameSession.stationNameChoices(for: world, at: here, in: .traditionalChinese, placeNames: names, realBuses: buses)
        XCTAssertTrue(choices.contains(StationNameChoice(name: "某某高中", kind: .busStop)), "\(choices)")
        XCTAssertFalse(choices.contains { $0.name.contains("捷運") })
    }

    /// L9-11: a bus stop's name has no English, so in English it is not
    /// offered (the station would be named in Chinese).
    @MainActor
    func testABusStopIsNotOfferedInEnglish() throws {
        let names = try bundled()
        let at = RealRailways.Coordinate(latitude: 25.0300, longitude: 121.5355)
        let world = try world(at: at.latitude, at.longitude)
        let here = try BundledRealData.point(at, in: world)
        let files = try BusStopLabelsTests.busFiles([
            ("捷運大安森林公園站(新生南路)", at.latitude + 0.0003, at.longitude),
            ("某某高中(新生南路)", at.latitude + 0.0006, at.longitude),
        ])
        let buses = try RealBusLibrary(index: files.index, file: files.file)
        let english = GameSession.stationNameChoices(for: world, at: here, in: .english, placeNames: names, realBuses: buses)
        XCTAssertFalse(english.contains { $0.kind == .busStop }, "\(english)")
        XCTAssertFalse(english.contains { $0.name.contains("某") }, "\(english)")
        let chinese = GameSession.stationNameChoices(for: world, at: here, in: .traditionalChinese, placeNames: names, realBuses: buses)
        XCTAssertTrue(chinese.contains(StationNameChoice(name: "某某高中", kind: .busStop)), "\(chinese)")
    }

    func testAMapWithoutRealGroundHasNoChoices() throws {
        XCTAssertEqual(
            GameSession.stationNameChoices(
                for: GameWorld.newGame(), at: PlanPoint(x: 1_000, y: 1_000), in: .traditionalChinese, placeNames: try bundled()
            ),
            []
        )
    }

    @MainActor
    func testTheSessionOffersTheChoicesWithTheName() throws {
        let world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.placeNames = try bundled()
        XCTAssertFalse(session.stationNameChoices.isEmpty)
        XCTAssertEqual(session.stationNameChoices.first?.name, session.stationName)
    }
}
