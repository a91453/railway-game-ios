import GameCore
import GamePresentation
import XCTest

/// Stage L1: the player-facing text in Traditional Chinese, and which
/// language a localization identifier picks. The English text is pinned by
/// the other display tests; these pin the Chinese, written out by hand.
final class LocalizationTests: XCTestCase {
    func testALocalizationPicksItsLanguage() {
        for identifier in ["zh-Hant", "zh-Hant-TW", "zh_TW", "zh-HK", "ZH"] {
            XCTAssertEqual(DisplayLanguage(localization: identifier), .traditionalChinese, identifier)
        }
        for identifier in ["en", "en-GB", "Base", "ja", "fr-CA", "", "-"] {
            XCTAssertEqual(DisplayLanguage(localization: identifier), .english, identifier)
        }
    }

    /// One of every error: each reads in Chinese, not as the English text.
    func testEveryGameErrorHasAChineseMessage() {
        let point = PlanPoint(x: 4_096, y: 7_168)
        let train = TrainID(rawValue: 3)
        let errors: [GameError] = [
            .invalidMapSize(width: 0, height: 5_120), .outOfBounds(point), .invalidName,
            .insufficientFunds(required: 50_000, available: 1_234), .unknownTrain(train), .trainAlreadyPlaced(train),
            .trainNotPlaced(train), .invalidTrainPosition, .invalidMovementRate, .invalidContinuation, .clockOverflow,
            .idsExhausted, .invalidTimetable, .unknownStation(StationID(rawValue: 3)), .trainServiceActive(train),
            .trainServiceNotActive(train), .noTimetable(train), .trainNotAtFirstStop(train), .unknownLine(LineID(rawValue: 3)),
            .invalidLineStops, .invalidTrainPerformance, .invalidServiceWindow, .invalidTrainsInService, .invalidServiceDay,
            .invalidHeadway, .trainOnLine(train), .trainNotOnLine(train), .invalidLinePattern, .unknownLinePattern(2),
            .invalidTrainLength, .unknownTrackNode(.node(7)), .unknownTrackEdge(.edge(3)),
            .invalidTrackGeometry, .trackNodeInUse(.node(2)), .trackEdgeInUse(.edge(2)), .trackTooSteep,
            .invalidTrackStructure, .trackConflict(.edge(4)), .trackTooClose(.edge(6)), .tracksWouldBeTooClose(.edge(6), .edge(7)), .trackEdgeHasPlatform(.edge(5)), .invalidPlatform,
            .trackReserved(train), .trainsShareTrack(TrainID(rawValue: 2), train), .invalidStationDemand, .invalidFareRules,
            .buildingOverlaps(PlacedBuildingID(rawValue: 2)), .buildingOnTrack(.edge(3)), .buildingOnStation(StationID(rawValue: 1)),
            .unknownPlacedBuilding(PlacedBuildingID(rawValue: 4)), .invalidZoneArea,
            .invalidTerrain, .onWater(row: 3, column: 4),
        ]
        XCTAssertEqual(Set(errors).count, 53, "one of every case")
        for error in errors {
            let chinese = error.playerMessage(in: .traditionalChinese)
            XCTAssertNotEqual(chinese, error.playerMessage(in: .english), "\(error)")
            XCTAssertTrue(chinese.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(error): \(chinese)")
            XCTAssertTrue(chinese.hasSuffix("。"), "\(error): \(chinese)")
        }
        XCTAssertEqual(
            GameError.insufficientFunds(required: 50_000, available: 1_234).playerMessage(in: .traditionalChinese),
            "餘額不足：需要 $ 500.00，目前只有 $ 12.34。"
        )
        XCTAssertEqual(GameError.trackEdgeInUse(.edge(2)).playerMessage(in: .traditionalChinese), "軌段 #2 上有列車。請先把列車移出軌道。")
        XCTAssertEqual(GameError.trackNodeInUse(.node(2)).playerMessage(in: .traditionalChinese), "還有軌道接在節點 #2。請先拆除那段軌道。")
        XCTAssertEqual(GameError.invalidTrainLength.playerMessage(in: .traditionalChinese), "列車可以有 1 到 16 節車廂。")
    }

    func testTheMapAndTrainsReadInChinese() throws {
        var world = try makeWorld()
        try world.buildStation(named: "Central", at: PlanPoint(x: 2_560, y: 512))
        let zh = DisplayLanguage.traditionalChinese
        XCTAssertEqual(world.networkSummary(in: zh), "1 座車站 · 0 個軌段")
        XCTAssertEqual(ConstructionTool.allCases.map { $0.title(in: zh) }, ["選取", "路網", "列車", "建築"])

        XCTAssertEqual(TrainPosition.onEdge(TrackTraversal(edge: .edge(2), direction: .backward), offset: 256).displayText(in: zh), "軌段 #2 反向，距起點 256 單位")
        XCTAssertEqual(TrackNodeID.node(1).displayText(in: zh), "節點 #1")
        XCTAssertEqual(TrackEdgeID.edge(2).displayText(in: zh), "軌段 #2")
        let train = try world.purchaseTrain(named: "T1")
        XCTAssertEqual(train.positionText(in: zh), "不在軌道上")
        XCTAssertEqual(train.carsText(in: zh), "1 節車廂")
        XCTAssertEqual(train.movement.rateText(in: zh), "速率 0／分鐘")
        XCTAssertEqual(train.pathText(in: zh), "前方沒有路徑")
    }

    func testTimeSpeedsAndMoneyReadInChinese() {
        let zh = DisplayLanguage.traditionalChinese
        XCTAssertEqual(GameTime(minutes: 8 * 60 + 30).displayText(in: zh), "第 1 日 · 08:30")
        XCTAssertEqual(GameTime(seconds: -1).displayTextWithSeconds(in: zh), "第 0 日 · 23:59:59")
        XCTAssertEqual(GameClock(now: GameTime(minutes: 90), speed: .x1).displayText(in: zh), "第 1 日 · 01:30:00")
        XCTAssertEqual(GameSpeed.allCases.map { $0.label(in: zh) }, ["暫停", "1×", "10×", "60×", "600×", "1200×", "6000×"])
        XCTAssertEqual(
            GameSpeed.allCases.map { $0.accessibilityName(in: zh) },
            ["已暫停", "真實時間", "真實時間的 10 倍", "真實時間的 60 倍", "真實時間的 600 倍", "真實時間的 1200 倍", "真實時間的 6000 倍，快轉"]
        )
        XCTAssertEqual(EconomyMode.allCases.map { $0.displayName(in: zh) }, ["自由模式", "經營模式"])
        XCTAssertEqual(FinancePeriod.allCases.map { $0.displayName(in: zh) }, ["日", "週", "月", "年"])
        XCTAssertEqual(LedgerEntry.Kind.dailyStaff.displayName(in: zh), "員工費用（日結）")
        XCTAssertEqual(LedgerItem.trainStaff.displayName(in: zh), "司機與調度員工")
        XCTAssertEqual(FareRules.standard.displayText(in: zh), "固定票價 · $ 5.00")
        XCTAssertEqual(FareRules.distance(FareRules.standardBands).displayText(in: zh), "階梯票價 · 5 段，$ 0.55 起")
    }

    /// Stage W2b: where a dwell has got to, in both languages.
    func testDwellPhasesReadInBothLanguages() {
        let phases: [DwellPhase] = [.doorsOpening, .boarding, .holding, .doorsClosing, .readyToLeave]
        XCTAssertEqual(
            phases.map { $0.text(in: .english) },
            ["Doors opening", "Passengers boarding", "Doors open", "Doors closing", "Ready to leave"]
        )
        XCTAssertEqual(phases.map { $0.text(in: .traditionalChinese) }, ["開門中", "乘客上下車中", "開門停站", "關門中", "準備發車"])

        // Arrived at 100, passengers until 130, doors closing from 160.
        func at(_ second: Int64, _ exchangeEnd: Int64?, _ closing: Int64?) -> DwellPhase {
            DwellPhase(
                ServiceTimes(arrival: GameTime(seconds: 100), exchangeEnd: exchangeEnd.map(GameTime.init(seconds:)), closing: closing.map(GameTime.init(seconds:))),
                at: GameTime(seconds: second)
            )
        }
        XCTAssertEqual(at(105, nil, nil), .doorsOpening)
        XCTAssertEqual(at(108, 130, nil), .boarding)
        XCTAssertEqual(at(129, 130, nil), .boarding)
        XCTAssertEqual(at(130, 130, nil), .holding)
        XCTAssertEqual(at(160, 130, 160), .doorsClosing)
        XCTAssertEqual(at(168, 130, 160), .doorsClosing)
        XCTAssertEqual(at(169, 130, 160), .readyToLeave)
        XCTAssertEqual(at(500, 130, 160), .readyToLeave, "waiting for its route")
    }

    /// The session writes its messages and suggests names in its language.
    func testTheSessionSpeaksItsLanguage() async throws {
        var built = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        let west = try built.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536))
        let east = try built.buildTrackNode(at: WorldCoordinate(x: 7_680, y: 1_536))
        try built.buildTrackEdge(from: west, to: east)
        let world = built
        await MainActor.run {
            let session = GameSession(world: world, language: .traditionalChinese)
            XCTAssertEqual(session.language, .traditionalChinese)
            XCTAssertEqual(session.stationName, "車站 1")

            session.selectTool(.train)
            session.purchaseTrain()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已購買 列車 1。請選擇要放置它的車站。"))
            session.tapMap(at: PlanPoint(x: 1_536, y: 512), reach: 0)
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "請選擇要放置 列車 1 的車站。"))

            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 4_096, y: 1_536), reach: 256)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已建造車站「車站 1」，月台 64 公尺，位於軌段 #1。"))
            XCTAssertEqual(session.stationName, "車站 2")

            session.selectTool(.train)
            session.selectStation(StationID(rawValue: 1))
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已將 列車 1 放在 車站 1，位於軌段 #1正向。"))

            // The English session is unchanged.
            XCTAssertEqual(GameSession(world: world).stationName, "Station 1")
        }
    }
}
