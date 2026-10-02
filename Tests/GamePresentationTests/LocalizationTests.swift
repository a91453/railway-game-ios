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
        let position = GridPosition(x: 4, y: 7)
        let train = TrainID(rawValue: 3)
        let errors: [GameError] = [
            .invalidMapSize(width: 0, height: 5), .outOfBounds(position), .tileOccupied(position),
            .invalidTrackConnections, .invalidName, .insufficientFunds(required: 50_000, available: 1_234),
            .noTrackToRemove(position), .trackInUse(position), .unknownTrain(train), .trainAlreadyPlaced(train),
            .trainNotPlaced(train), .invalidTrainPosition, .invalidMovementRate, .invalidContinuation, .clockOverflow,
            .idsExhausted, .invalidTimetable, .unknownStation(StationID(rawValue: 3)), .trainServiceActive(train),
            .trainServiceNotActive(train), .noTimetable(train), .trainNotAtFirstStop(train), .unknownLine(LineID(rawValue: 3)),
            .invalidLineStops, .invalidLineRate, .invalidServiceWindow, .invalidTrainsInService, .invalidServiceDay,
            .invalidHeadway, .trainOnLine(train), .trainNotOnLine(train), .invalidLinePattern, .unknownLinePattern(2),
            .invalidStationTile(position), .invalidTrainLength, .unknownTrackNode(.node(7)), .unknownTrackEdge(.edge(3)),
            .invalidTrackGeometry, .trackNodeInUse(.node(2)), .trackEdgeInUse(.edge(2)), .trackTooSteep,
            .invalidTrackStructure, .trackConflict(.edge(4)), .trackEdgeHasPlatform(.edge(5)), .invalidPlatform,
            .trackReserved(train), .trainsShareTrack(TrainID(rawValue: 2), train), .invalidStationDemand, .invalidFareRules,
        ]
        XCTAssertEqual(Set(errors).count, 49, "one of every case")
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
        XCTAssertEqual(GameError.trackInUse(position).playerMessage(in: .traditionalChinese), "(4, 7) 的軌道上有列車。請先把列車移出軌道。")
        XCTAssertEqual(GameError.trackNodeInUse(.node(2)).playerMessage(in: .traditionalChinese), "還有軌道接在節點 #2。請先拆除那段軌道。")
        XCTAssertEqual(GameError.invalidTrainLength.playerMessage(in: .traditionalChinese), "列車可以有 1 到 16 節車廂。")
    }

    func testTheMapAndTrainsReadInChinese() throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.east, .west])
        try world.buildStation(named: "Central", at: GridPosition(x: 2, y: 0))
        try world.buildTurnout(at: GridPosition(x: 3, y: 1), connections: [.east, .south, .west], stem: .west)
        try world.buildCrossing(at: GridPosition(x: 4, y: 1))
        let zh = DisplayLanguage.traditionalChinese
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 0, y: 0), in: zh), "空地")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 1, y: 0), in: zh), "軌道 · 直線 東–西")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 2, y: 0), in: zh), "車站 · Central")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 3, y: 1), in: zh), "道岔 · 東–南–西，共用端 西")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 4, y: 1), in: zh), "平面交叉 · 北–南 跨 東–西")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 99, y: 0), in: zh), "地圖外")
        XCTAssertEqual(world.networkSummary(in: zh), "1 座車站 · 3 格軌道")
        XCTAssertEqual(TrackConnections([.north, .east]).summary(in: zh), "彎道 北–東")
        XCTAssertEqual(TrackPiece.allCases.map { $0.title(in: zh) }, ["直線", "彎道", "T 字岔", "十字"])
        XCTAssertEqual(ConstructionTool.allCases.map { $0.title(in: zh) }, ["選取", "軌道", "車站", "拆除", "列車"])

        let position = TrainPosition.atNode(GridPosition(x: 1, y: 0), heading: .east)
        XCTAssertEqual(position.displayText(in: zh), "在 (1, 0)，面向東")
        XCTAssertEqual(TrainPosition.onEdge(TrackTraversal(edge: .edge(2), direction: .backward), offset: 256).displayText(in: zh), "軌段 #2 反向，距起點 256 單位")
        XCTAssertEqual(TrackNodeID.tile(GridPosition(x: 1, y: 2)).displayText(in: zh), "格 (1, 2)")
        XCTAssertEqual(TrackEdgeID.link(GridPosition(x: 1, y: 2), GridPosition(x: 2, y: 2)).displayText(in: zh), "連結 (1, 2)–(2, 2)")
        let train = try world.purchaseTrain(named: "T1")
        XCTAssertEqual(train.positionText(in: zh), "不在軌道上")
        XCTAssertEqual(train.carsText(in: zh), "1 節車廂")
        XCTAssertEqual(train.movement.rateText(in: zh), "速率 0／分鐘")
        XCTAssertEqual(train.movement.pathText(in: zh), "前方沒有路徑")
    }

    func testTimeSpeedsAndMoneyReadInChinese() {
        let zh = DisplayLanguage.traditionalChinese
        XCTAssertEqual(GameTime(minutes: 8 * 60 + 30).displayText(in: zh), "第 1 日 · 08:30")
        XCTAssertEqual(GameTime(seconds: -1).displayTextWithSeconds(in: zh), "第 0 日 · 23:59:59")
        XCTAssertEqual(GameClock(now: GameTime(minutes: 90), speed: .x1).displayText(in: zh), "第 1 日 · 01:30:00")
        XCTAssertEqual(GameSpeed.allCases.map { $0.label(in: zh) }, ["暫停", "1×", "10×", "60×", "600×", "1200×"])
        XCTAssertEqual(
            GameSpeed.allCases.map { $0.accessibilityName(in: zh) },
            ["已暫停", "真實時間", "真實時間的 10 倍", "真實時間的 60 倍", "真實時間的 600 倍", "真實時間的 1200 倍"]
        )
        XCTAssertEqual(EconomyMode.allCases.map { $0.displayName(in: zh) }, ["自由模式", "經營模式"])
        XCTAssertEqual(FinancePeriod.allCases.map { $0.displayName(in: zh) }, ["日", "週", "月", "年"])
        XCTAssertEqual(LedgerEntry.Kind.dailyStaff.displayName(in: zh), "員工費用（日結）")
        XCTAssertEqual(LedgerItem.trainStaff.displayName(in: zh), "司機與調度員工")
        XCTAssertEqual(FareRules.standard.displayText(in: zh), "固定票價 · $ 5.00")
        XCTAssertEqual(FareRules.distance(FareRules.standardBands).displayText(in: zh), "階梯票價 · 5 段，$ 0.55 起")
    }

    /// The session writes its messages and suggests names in its language.
    @MainActor
    func testTheSessionSpeaksItsLanguage() throws {
        var world = try makeWorld(width: 8, height: 4, balance: 100_000)
        try world.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.east, .west])
        let session = GameSession(world: world, language: .traditionalChinese)
        XCTAssertEqual(session.language, .traditionalChinese)
        XCTAssertEqual(session.stationName, "車站 1")

        session.selectTool(.train)
        session.purchaseTrain()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已購買 列車 1。請選擇一格軌道放置它。"))
        session.select(GridPosition(x: 1, y: 1))
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已將 列車 1 放在 (1, 1)，面向東。"))

        session.selectTool(.buildTrack)
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "(1, 1) 這一格已經有東西了。"))
        session.select(GridPosition(x: 2, y: 1))
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已在 (2, 1) 鋪設直線軌道。"))

        session.selectTool(.buildStation)
        session.select(GridPosition(x: 1, y: 0))
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已在 (1, 0) 建造車站「車站 1」。"))
        XCTAssertEqual(session.stationName, "車站 2")

        // The English session is unchanged.
        XCTAssertEqual(GameSession(world: world).stationName, "Station 1")
    }
}
