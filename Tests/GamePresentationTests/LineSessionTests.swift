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
    // A dead-end line, stations above every other tile:
    //
    //       A(1,0)  B(3,0)  C(5,0)  D(7,0)
    //         |       |       |       |
    //   o  -  a - o - b - o - c - o - d  -  o
    private static let a = GridPosition(x: 1, y: 1)
    private static let b = GridPosition(x: 3, y: 1)
    private static let stationA = StationID(rawValue: 1)
    private static let stationB = StationID(rawValue: 2)
    private static let stationC = StationID(rawValue: 3)
    private static let stationD = StationID(rawValue: 4)
    private static let main = LineID(rawValue: 1)
    private static let first = TrainID(rawValue: 1)

    private func makeStationWorld(minute: Int64 = 480) throws -> GameWorld {
        var world = try GameWorld(
            width: 9, height: 2, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for x in 1...7 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 8, y: 1), connections: .west)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        return world
    }

    /// Line 1 calls at every station; 5 / 2 / 0 trains; a short working
    /// Beta-Gamma (4 / 1 / 1, 20 minutes apart at low) and an express
    /// Alpha-Delta (2 / 1 / 0). Round trips 20, 8 and 16 minutes.
    private func makeLineWorld() throws -> GameWorld {
        var world = try makeStationWorld()
        try world.createLine(named: "Main", stops: [Self.stationA, Self.stationB, Self.stationC, Self.stationD])
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
        XCTAssertEqual(ServiceWindow.allDay.displayText, "All day")
        XCTAssertEqual(ServiceWindow.standard.displayText, "06:00–24:00")
        XCTAssertEqual(ServiceWindow.hours(open: 1320, close: 1500).displayText, "22:00–01:00 next day")
        XCTAssertEqual(headwayText(minutes: 4), "Every 4 min")
        XCTAssertEqual(headwayText(minutes: 60), "Every 1 h")
        XCTAssertEqual(headwayText(minutes: 90), "Every 1 h 30 min")
        XCTAssertEqual(ServiceLevel.allCases.map(\.title), ["Peak", "Off-peak", "Low"])
    }

    /// Each service with its kind, ends, calls, and at every level what it
    /// runs beside the services before it (Stage Q3's shared room).
    func testServicesAreSummarisedAsTheyRun() throws {
        let world = try makeLineWorld()
        let summaries = world.lineServiceSummaries(Self.main)
        XCTAssertEqual(summaries.map(\.pattern), [nil, 0, 1])
        XCTAssertEqual(summaries.map(\.title), ["All stops Alpha–Delta", "Short working Beta–Gamma", "Express Alpha–Delta"])
        XCTAssertEqual(summaries.map(\.callsText), [
            "Alpha · Beta · Gamma · Delta", "Beta · Gamma", "Alpha · Delta (passes Beta, Gamma)",
        ])
        XCTAssertEqual(summaries[0].levels.map(\.text), ["5 trains · Every 4 min", "2 trains · Every 10 min", "No trains"])
        XCTAssertEqual(summaries[1].levels.map(\.text), ["2 trains · Every 4 min", "1 train · Every 8 min", "1 train · Every 20 min"])
        XCTAssertEqual(summaries[2].levels.map(\.text), ["No trains", "1 train · Every 16 min", "No trains"])
        XCTAssertEqual(summaries.map(\.assigned), [0, 0, 0])
        XCTAssertEqual(world.lineServiceSummaries(LineID(rawValue: 9)), [])

        XCTAssertNil(world.lineCoverageText(Self.main, at: .peak))
        XCTAssertEqual(world.lineCoverageText(Self.main, at: .low), "Not covered: Alpha–Beta, Gamma–Delta")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 480)), "Peak")
        XCTAssertEqual(world.lineStatusText(Self.main, at: GameTime(minutes: 60)), "Closed")

        // Without a route a service says so.
        var cut = world
        try cut.removeTrack(at: GridPosition(x: 6, y: 1))
        XCTAssertEqual(cut.lineServiceSummaries(Self.main)[0].levels[0].text, "No route")
    }

    /// A train on a service: which one, where it is in its trip and whether
    /// it is early or late, derived from the timetable and the clock.
    func testATrainsServiceShowsWhereItIsAndHowLate() throws {
        var world = try makeLineWorld()
        let shuttle = try world.purchaseTrain(named: "Shuttle").id
        try world.placeTrain(shuttle, at: .atNode(Self.b, heading: .east))
        XCTAssertNil(world.trainServiceStatus(of: shuttle), "no line, no service")
        XCTAssertNil(world.trainServiceStatus(of: TrainID(rawValue: 9)))

        try world.assignTrain(shuttle, to: Self.main, pattern: 0)
        XCTAssertEqual(
            world.trainServiceStatus(of: shuttle),
            TrainServiceStatus(serviceName: "Main · Short working Beta–Gamma", stopText: "Waiting to be sent out", punctuality: nil)
        )
        // Without a rate it is not ready: give it one.
        try world.setTrainMovementRate(shuttle, to: 1024)
        try world.advance(ticks: 1)
        // Left Beta at 480, due at Gamma at 482.
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.stopText, "Next: Gamma, due 08:02")
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.punctuality, .onTime)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.stopText, "At Gamma, leaves 08:04")
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.punctuality, .onTime)

        // Held at Gamma with no rate, it falls behind.
        try world.setTrainMovementRate(shuttle, to: 0)
        try world.advance(ticks: 5)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 487))
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.stopText, "Next: Beta, due 08:06")
        XCTAssertEqual(world.trainServiceStatus(of: shuttle)?.punctuality, .late(minutes: 1))

        // A train of its own, waiting before its scheduled arrival, is early.
        let own = try world.purchaseTrain(named: "Own").id
        try world.placeTrain(own, at: .atNode(Self.a, heading: .east))
        try world.setTrainTimetable(own, to: [ScheduledStop(station: Self.stationA, arrival: GameTime(minutes: 490), departure: GameTime(minutes: 495))])
        try world.startTrainService(own)
        XCTAssertEqual(
            world.trainServiceStatus(of: own),
            TrainServiceStatus(serviceName: nil, stopText: "At Alpha, last stop", punctuality: .early(minutes: 3))
        )
        XCTAssertEqual(Punctuality.early(minutes: 3).text, "3 min early")
        XCTAssertEqual(Punctuality.late(minutes: 1).text, "1 min late")
        XCTAssertEqual(Punctuality.onTime.text, "On time")
    }

    // MARK: - Commands

    /// A new line: stations picked on the map, in order, then created
    /// through `createLine`, which GameCore checks.
    @MainActor
    func testANewLineIsPickedFromTheMapAndCreatedByGameCore() throws {
        let start = try makeStationWorld()
        let session = GameSession(world: start)
        XCTAssertNil(session.selectedLineID)

        session.addSelectedStationToLineDraft()
        XCTAssertEqual(session.message?.kind, .failure, "nothing selected")
        session.select(GridPosition(x: 2, y: 1))
        session.addSelectedStationToLineDraft()
        XCTAssertEqual(session.message?.text, "Select a station on the map to add it to the new line.")
        session.select(GridPosition(x: 1, y: 0))
        session.addSelectedStationToLineDraft()
        session.addSelectedStationToLineDraft()
        XCTAssertEqual(session.message?.kind, .failure, "the same station twice in a row")
        XCTAssertEqual(session.lineDraft, [Self.stationA])

        // One stop is refused by GameCore, and the draft is kept.
        session.createLineFromDraft()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidLineStops.playerMessage))
        XCTAssertEqual(session.world, start)
        XCTAssertEqual(session.lineDraft, [Self.stationA])

        session.select(GridPosition(x: 5, y: 0))
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

    /// Counts, targets, windows and patterns each go through one GameCore
    /// command, changing one level and keeping the others.
    @MainActor
    func testLineSettingsGoThroughGameCore() throws {
        var expected = try makeLineWorld()
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
        XCTAssertEqual(session.message?.text, GameError.invalidTrainsInService.playerMessage)
        session.setSelectedLineTargetHeadway(1, at: .low)
        XCTAssertEqual(session.message?.text, GameError.invalidHeadway.playerMessage)
        session.addPatternToSelectedLine(from: 2, to: 1, express: true)
        XCTAssertEqual(session.message?.text, GameError.invalidLinePattern.playerMessage)
        session.removePatternFromSelectedLine(9)
        XCTAssertEqual(session.message?.text, GameError.unknownLinePattern(9).playerMessage)
        XCTAssertEqual(session.world, expected)

        session.removeSelectedLine()
        try expected.removeLine(Self.main)
        XCTAssertEqual(session.world, expected)
        XCTAssertNil(session.selectedLineID)
        session.setSelectedLineTrains(1, at: .peak)
        XCTAssertEqual(session.message?.text, "Create or choose a line first.")
    }

    /// Assigning the selected train, taking it off, and running or
    /// stopping a train's own timetable, each through GameCore.
    @MainActor
    func testTrainServiceCommandsGoThroughGameCore() throws {
        var expected = try makeLineWorld()
        try expected.purchaseTrain(named: "Blue")
        try expected.placeTrain(Self.first, at: .atNode(Self.a, heading: .east))
        let session = GameSession(world: expected)

        session.assignSelectedTrainToSelectedLine(pattern: 1)
        try expected.assignTrain(Self.first, to: Self.main, pattern: 1)
        XCTAssertEqual(session.message?.text, "Blue now runs for Main · Express Alpha–Delta. It leaves once it waits at the first stop.")
        session.assignSelectedTrainToSelectedLine()
        XCTAssertEqual(session.message?.text, GameError.trainOnLine(Self.first).playerMessage)
        session.startSelectedTrainService()
        XCTAssertEqual(session.message?.text, GameError.trainOnLine(Self.first).playerMessage)
        session.unassignSelectedTrain()
        try expected.unassignTrain(Self.first)
        XCTAssertEqual(session.world, expected)

        session.startSelectedTrainService()
        XCTAssertEqual(session.message?.text, GameError.noTimetable(Self.first).playerMessage)
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
        XCTAssertEqual(second.message?.text, GameError.trainServiceNotActive(Self.first).playerMessage)
    }
}
