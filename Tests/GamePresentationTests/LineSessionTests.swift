import GameCore
import GamePresentation
import XCTest

/// The lines panel (Phase 4 Stage R): text derived for lines, their
/// services and the trains that run them, and the session's line commands.
///
/// Every session command is compared with the same command applied to
/// GameCore directly, so the session can neither add, drop nor alter one.
/// Expected text is written out by hand.
final class LineSessionTests: XCTestCase {
    // A dead-end line of the track network on row 1 (nodes at columns
    // 0–8, edges 1–8 eastward, see `TestLine`), stations above every other
    // node, each with platforms on the half of each edge there nearer it:
    //
    //   row 0:      A       B       C       D
    //   row 1:  o - o - o - o - o - o - o - o - o
    private static let line = TestLine(tiles: 9, row: 1)
    private static let stationA = StationID(rawValue: 1)
    private static let stationB = StationID(rawValue: 2)
    private static let stationC = StationID(rawValue: 3)
    private static let stationD = StationID(rawValue: 4)
    private static let main = LineID(rawValue: 1)
    private static let first = TrainID(rawValue: 1)
    /// Line 1's performance (Stage W2c): a crawl at 1 km/h, about a link a
    /// minute, so a stop is 120 s from the next and Alpha 350 s from Delta
    /// (as in `LinePatternTests`).
    private static let crawl = TrainPerformance(acceleration: 250, braking: 250, topSpeed: 1)

    private static func makeStationWorld(minute: Int64 = 480) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 9_216, height: 2_048), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try Self.line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            try Self.line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        return world
    }

    /// Line 1 calls at every station; 5 / 2 / 0 trains; a short working
    /// Beta-Gamma (4 / 1 / 1, 20 minutes apart at low) and an express
    /// Alpha-Delta (2 / 1 / 0). Round trips 20, 8 and 16 minutes, with
    /// `crawl`.
    private static func makeLineWorld() throws -> GameWorld {
        var world = try makeStationWorld()
        try world.createLine(named: "Main", stops: [Self.stationA, Self.stationB, Self.stationC, Self.stationD])
        try world.setLinePerformance(Self.main, to: Self.crawl)
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 5, offPeak: 2, low: 0))
        try world.addLinePattern(Self.main, calling: [1, 2])
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 4, offPeak: 1, low: 1), pattern: 0)
        try world.setLineTargetHeadways(Self.main, to: TargetHeadways(low: 20), pattern: 0)
        try world.addLinePattern(Self.main, calling: [0, 3])
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 2, offPeak: 1, low: 0), pattern: 1)
        return world
    }

    // MARK: - Text

    func testTimesWindowsAndHeadwaysReadAsClockTimes() {
        XCTAssertEqual(clockText(minuteOfDay: 0), "00:00")
        XCTAssertEqual(clockText(minuteOfDay: 365), "06:05")
        XCTAssertEqual(clockText(minuteOfDay: 1500), "01:00")
        XCTAssertEqual(GameTime(minutes: 1440 + 510).clockText, "08:30")
        XCTAssertEqual(ServiceWindow.allDay.displayText(in: .english), "All day")
        XCTAssertEqual(ServiceWindow.standard.displayText(in: .english), "06:00–24:00")
        XCTAssertEqual(ServiceWindow.hours(open: 1320, close: 1500).displayText(in: .english), "22:00–01:00 next day")
        XCTAssertEqual(headwayText(minutes: 4, in: .english), "Every 4 min")
        XCTAssertEqual(headwayText(minutes: 60, in: .english), "Every 1 h")
        XCTAssertEqual(headwayText(minutes: 90, in: .english), "Every 1 h 30 min")
        XCTAssertEqual(ServiceLevel.allCases.map { $0.title(in: .english) }, ["Peak", "Off-peak", "Low"])
        // The line panel's stepper and target menu.
        XCTAssertEqual(levelSettingText(.peak, trains: 2, target: nil, in: .english), "Peak: 2 wanted")
        XCTAssertEqual(levelSettingText(.offPeak, trains: 2, target: 5, in: .english), "Off-peak: every 5 min")
        XCTAssertEqual(targetHeadwayText(nil, in: .english), "Target: none")
        XCTAssertEqual(targetHeadwayText(90, in: .english), "Target: every 1 h 30 min")
    }

    /// The same text in Traditional Chinese (Stage L1).
    func testLinesReadInTraditionalChinese() throws {
        XCTAssertEqual(ServiceWindow.allDay.displayText(in: .traditionalChinese), "全天")
        XCTAssertEqual(ServiceWindow.hours(open: 1320, close: 1500).displayText(in: .traditionalChinese), "22:00–01:00（翌日）")
        XCTAssertEqual(headwayText(minutes: 4, in: .traditionalChinese), "每 4 分鐘一班")
        XCTAssertEqual(headwayText(minutes: 60, in: .traditionalChinese), "每 1 小時一班")
        XCTAssertEqual(headwayText(minutes: 90, in: .traditionalChinese), "每 1 小時 30 分鐘一班")
        XCTAssertEqual(ServiceLevel.allCases.map { $0.title(in: .traditionalChinese) }, ["尖峰", "離峰", "低峰"])
        XCTAssertEqual(levelSettingText(.peak, trains: 2, target: nil, in: .traditionalChinese), "尖峰：上線 2 列")
        XCTAssertEqual(levelSettingText(.low, trains: 0, target: 20, in: .traditionalChinese), "低峰：每 20 分鐘一班")
        XCTAssertEqual(targetHeadwayText(nil, in: .traditionalChinese), "目標：無")
        XCTAssertEqual(targetHeadwayText(5, in: .traditionalChinese), "目標：每 5 分鐘一班")
        XCTAssertEqual(Punctuality.onTime.text(in: .traditionalChinese), "準點")
        XCTAssertEqual(Punctuality.early(minutes: 2).text(in: .traditionalChinese), "早到 2 分")
        XCTAssertEqual(Punctuality.late(minutes: 5).text(in: .traditionalChinese), "誤點 5 分")

        let world = try Self.makeLineWorld()
        let summaries = world.lineServiceSummaries(Self.main, in: .traditionalChinese)
        XCTAssertEqual(summaries.map(\.title), ["普通車 Alpha–Delta", "區間車 Beta–Gamma", "快車 Alpha–Delta"])
        XCTAssertEqual(summaries[2].callsText, "Alpha · Delta（通過 Beta、Gamma）")
        XCTAssertEqual(summaries[0].levels.map { $0.text(in: .traditionalChinese) }, ["5 列 · 每 4 分鐘一班", "2 列 · 每 10 分鐘一班", "沒有列車"])
        XCTAssertEqual(world.lineCoverageText(Self.main, at: .low, in: .traditionalChinese), "沒有服務：Alpha–Beta、Gamma–Delta")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 480), in: .traditionalChinese), "尖峰")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 180), in: .traditionalChinese), "已收班")
    }

    /// Each service with its kind, ends, calls, and at every level what it
    /// runs beside the services before it (Stage Q3's shared room).
    func testServicesAreSummarisedAsTheyRun() throws {
        let world = try Self.makeLineWorld()
        let summaries = world.lineServiceSummaries(Self.main, in: .english)
        XCTAssertEqual(summaries.map(\.pattern), [nil, 0, 1])
        XCTAssertEqual(summaries.map(\.title), ["All stops Alpha–Delta", "Short working Beta–Gamma", "Express Alpha–Delta"])
        XCTAssertEqual(summaries.map(\.callsText), [
            "Alpha · Beta · Gamma · Delta", "Beta · Gamma", "Alpha · Delta (passes Beta, Gamma)",
        ])
        XCTAssertEqual(summaries[0].levels.map { $0.text(in: .english) }, ["5 trains · Every 4 min", "2 trains · Every 10 min", "No trains"])
        XCTAssertEqual(summaries[1].levels.map { $0.text(in: .english) }, ["2 trains · Every 4 min", "1 train · Every 8 min", "1 train · Every 20 min"])
        XCTAssertEqual(summaries[2].levels.map { $0.text(in: .english) }, ["No trains", "1 train · Every 16 min", "No trains"])
        XCTAssertEqual(summaries.map(\.assigned), [0, 0, 0])
        XCTAssertEqual(world.lineServiceSummaries(LineID(rawValue: 9), in: .english), [])

        XCTAssertNil(world.lineCoverageText(Self.main, at: .peak, in: .english))
        XCTAssertEqual(world.lineCoverageText(Self.main, at: .low, in: .english), "Not covered: Alpha–Beta, Gamma–Delta")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 480), in: .english), "Peak")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 60), in: .english), "Closed")

        // Without a route a service says so: edge 7, between Gamma and
        // Delta, and Delta's platform on it, removed.
        var cut = world
        try cut.removeTrackPlatform(Self.stationD, on: .edge(7), from: 512)
        try cut.removeTrackEdge(.edge(7))
        XCTAssertEqual(cut.lineServiceSummaries(Self.main, in: .english)[0].levels[0].text(in: .english), "No route")
    }

    /// A train on a service: which one, where it is in its trip, whether it
    /// is early or late (GameCore's lateness, in whole minutes) and, at a
    /// stop, where its dwell has got to (Stage W2b).
    func testATrainsServiceShowsWhereItIsAndHowLate() throws {
        var world = try Self.makeLineWorld()
        let shuttle = try world.purchaseTrain(named: "Shuttle").id
        try world.placeTrain(shuttle, at: Self.line.at(3, facingEast: true))
        XCTAssertNil(world.trainServiceStatus(of: shuttle, in: .english), "no line, no service")
        XCTAssertNil(world.trainServiceStatus(of: TrainID(rawValue: 9), in: .english))

        try world.assignTrain(shuttle, to: Self.main, pattern: 0)
        XCTAssertEqual(
            world.trainServiceStatus(of: shuttle, in: .english),
            TrainServiceStatus(serviceName: "Main · Short working Beta–Gamma", stopText: "Waiting to be sent out", punctuality: nil)
        )
        // Without a rate it is not ready: give it one.
        try world.setTrainMovementRate(shuttle, to: 1024)
        try world.advance(ticks: 1)
        // Sent out at 480, it left Beta at 480:42, due at Gamma at 482:42.
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.stopText, "Next: Gamma, due 08:02")
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.punctuality, .onTime)
        XCTAssertNil(world.trainServiceStatus(of: shuttle, in: .english)?.dwell)
        try world.advance(ticks: 2)
        // At Gamma since 482:42, its doors open until 484:33 for 484:42.
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.stopText, "At Gamma, leaves 08:04")
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.punctuality, .onTime)
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.dwell, .holding)

        // Held with no rate, it leaves Gamma on time but falls behind: 78 s
        // past its arrival at Beta (486:42) at 488.
        try world.setTrainMovementRate(shuttle, to: 0)
        try world.advance(ticks: 5)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 488))
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.stopText, "Next: Beta, due 08:06")
        XCTAssertEqual(world.lateness(of: shuttle), 78)
        XCTAssertEqual(world.trainServiceStatus(of: shuttle, in: .english)?.punctuality, .late(minutes: 1))

        // A train of its own that arrived (started) before its scheduled
        // arrival is early: by 2 minutes, while its doors open.
        let own = try world.purchaseTrain(named: "Own").id
        try world.placeTrain(own, at: Self.line.at(1, facingEast: true))
        try world.setTrainTimetable(own, to: [ScheduledStop(station: Self.stationA, arrival: GameTime(minutes: 490), departure: GameTime(minutes: 495))])
        try world.startTrainService(own)
        XCTAssertEqual(
            world.trainServiceStatus(of: own, in: .english),
            TrainServiceStatus(serviceName: nil, stopText: "At Alpha, last stop", punctuality: .early(minutes: 2), dwell: .doorsOpening)
        )
        XCTAssertEqual(Punctuality.early(minutes: 3).text(in: .english), "3 min early")
        XCTAssertEqual(Punctuality.late(minutes: 1).text(in: .english), "1 min late")
        XCTAssertEqual(Punctuality.onTime.text(in: .english), "On time")
    }

    // MARK: - Commands

    /// A new line: stations picked on the map, in order, then created
    /// through `createLine`, which GameCore checks.
    func testANewLineIsPickedFromTheMapAndCreatedByGameCore() async throws {
        try await MainActor.run {
            let start = try Self.makeStationWorld()
            let session = GameSession(world: start)
            XCTAssertNil(session.selectedLineID)

            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.message?.kind, .failure, "nothing selected")
            session.tapMap(at: PlanPoint(x: 2_560, y: 1_536), reach: 0)
            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.message?.text, "Select a station on the map to add it to the new line.")
            session.selectStation(Self.stationA)
            session.addSelectedStationToLineDraft()
            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.message?.kind, .failure, "the same station twice in a row")
            XCTAssertEqual(session.lineDraft, [Self.stationA])

            // One stop is refused by GameCore, and the draft is kept.
            session.createLineFromDraft()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidLineStops.playerMessage(in: .english)))
            XCTAssertEqual(session.world, start)
            XCTAssertEqual(session.lineDraft, [Self.stationA])

            session.selectStation(Self.stationC)
            session.addSelectedStationToLineDraft()
            session.createLineFromDraft()
            var expected = start
            try expected.createLine(named: "Line 1", stops: [Self.stationA, Self.stationC])
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.selectedLineID, Self.main)
            XCTAssertEqual(session.lineDraft, [])
            XCTAssertEqual(session.message?.kind, .success)

            session.addSelectedStationToLineDraft()
            session.removeLastLineDraftStop()
            XCTAssertEqual(session.lineDraft, [])
        }
    }

    /// Counts, targets, windows and patterns each go through one GameCore
    /// command, changing one level and keeping the others.
    func testLineSettingsGoThroughGameCore() async throws {
        try await MainActor.run {
            var expected = try Self.makeLineWorld()
            let session = GameSession(world: expected)
            XCTAssertEqual(session.selectedLineID, Self.main, "the first line is selected")

            session.setSelectedLineTrains(3, at: .offPeak)
            try expected.setLineTrainsInService(Self.main, to: TrainsInService(peak: 5, offPeak: 3, low: 0))
            session.setSelectedLineTrains(0, at: .peak, pattern: 1)
            try expected.setLineTrainsInService(Self.main, to: TrainsInService(peak: 0, offPeak: 1, low: 0), pattern: 1)
            session.setSelectedLineTargetHeadway(15, at: .peak, pattern: 0)
            try expected.setLineTargetHeadways(Self.main, to: TargetHeadways(peak: 15, low: 20), pattern: 0)
            session.setSelectedLineTargetHeadway(nil, at: .low, pattern: 0)
            try expected.setLineTargetHeadways(Self.main, to: TargetHeadways(peak: 15), pattern: 0)
            session.setSelectedLineAllDay(true)
            try expected.setLineServiceWindow(Self.main, to: .allDay)
            session.addPatternToSelectedLine(from: 0, to: 2, express: false)
            try expected.addLinePattern(Self.main, calling: [0, 1, 2])
            XCTAssertEqual(session.message?.text, "Added Short working Alpha–Gamma to Main as pattern 3.")
            session.addPatternToSelectedLine(from: 1, to: 3, express: true)
            try expected.addLinePattern(Self.main, calling: [1, 3])
            session.removePatternFromSelectedLine(0)
            try expected.removeLinePattern(Self.main, at: 0)
            XCTAssertEqual(session.world, expected)

            // Refusals are GameCore's, and change nothing.
            session.setSelectedLineTrains(-1, at: .low)
            XCTAssertEqual(session.message?.text, GameError.invalidTrainsInService.playerMessage(in: .english))
            session.setSelectedLineTargetHeadway(1, at: .low)
            XCTAssertEqual(session.message?.text, GameError.invalidHeadway.playerMessage(in: .english))
            session.addPatternToSelectedLine(from: 2, to: 1, express: true)
            XCTAssertEqual(session.message?.text, GameError.invalidLinePattern.playerMessage(in: .english))
            session.removePatternFromSelectedLine(9)
            XCTAssertEqual(session.message?.text, GameError.unknownLinePattern(9).playerMessage(in: .english))
            XCTAssertEqual(session.world, expected)

            session.removeSelectedLine()
            try expected.removeLine(Self.main)
            XCTAssertEqual(session.world, expected)
            XCTAssertNil(session.selectedLineID)
            session.setSelectedLineTrains(1, at: .peak)
            XCTAssertEqual(session.message?.text, "Create or choose a line first.")
        }
    }

    /// Assigning the selected train, taking it off, and running or
    /// stopping a train's own timetable, each through GameCore.
    func testTrainServiceCommandsGoThroughGameCore() async throws {
        try await MainActor.run {
            var expected = try Self.makeLineWorld()
            try expected.purchaseTrain(named: "Blue")
            try expected.placeTrain(Self.first, at: Self.line.at(1, facingEast: true))
            let session = GameSession(world: expected)

            session.assignSelectedTrainToSelectedLine(pattern: 1)
            try expected.assignTrain(Self.first, to: Self.main, pattern: 1)
            try expected.useTrainPerformanceForMovement(Self.first)
            XCTAssertEqual(session.message?.text, "Blue now runs for Main · Express Alpha–Delta. It leaves once it waits at the first stop.")
            session.assignSelectedTrainToSelectedLine()
            XCTAssertEqual(session.message?.text, GameError.trainOnLine(Self.first).playerMessage(in: .english))
            session.startSelectedTrainService()
            XCTAssertEqual(session.message?.text, GameError.trainOnLine(Self.first).playerMessage(in: .english))
            session.unassignSelectedTrain()
            try expected.unassignTrain(Self.first)
            XCTAssertEqual(session.world, expected)

            session.startSelectedTrainService()
            XCTAssertEqual(session.message?.text, GameError.noTimetable(Self.first).playerMessage(in: .english))
            let stop = ScheduledStop(station: Self.stationA, arrival: GameTime(minutes: 480), departure: GameTime(minutes: 490))
            try expected.setTrainTimetable(Self.first, to: [stop])
            let withTimetable = expected
            let second = GameSession(world: withTimetable)
            second.startSelectedTrainService()
            try expected.startTrainService(Self.first)
            XCTAssertEqual(second.world, expected)
            second.stopSelectedTrainService()
            try expected.stopTrainService(Self.first)
            XCTAssertEqual(second.world, expected)
            second.stopSelectedTrainService()
            XCTAssertEqual(second.message?.text, GameError.trainServiceNotActive(Self.first).playerMessage(in: .english))
        }
    }
}
