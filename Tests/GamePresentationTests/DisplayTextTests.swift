import GameCore
import GamePresentation
import XCTest

final class DisplayTextTests: XCTestCase {
    /// Stage F3c: the stations and the track network's edges; the grid's
    /// track tiles are gone.
    func testNetworkSummaryCountsStationsAndEdges() throws {
        var world = try makeWorld(balance: 100_000)
        XCTAssertEqual(world.networkSummary(in: .english), "0 stations · 0 edges")
        XCTAssertEqual(world.networkSummary(in: .traditionalChinese), "0 座車站 · 0 個軌段")

        try world.buildStation(named: "Central", at: PlanPoint(x: 512, y: 512))
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 1_536, y: 1_536))
        try world.buildTrackEdge(from: west, to: east)
        XCTAssertEqual(world.networkSummary(in: .english), "1 station · 1 edge")

        try world.buildStation(named: "Harbor", at: PlanPoint(x: 3_584, y: 512))
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 2_560, y: 1_536))
        try world.buildTrackEdge(from: east, to: far)
        XCTAssertEqual(world.networkSummary(in: .english), "2 stations · 2 edges")
        XCTAssertEqual(world.networkSummary(in: .traditionalChinese), "2 座車站 · 2 個軌段")
    }

    /// Stage F3d: the map's VoiceOver label gives how far the world reaches
    /// in kilometres, to the nearest tenth, not a count of tiles.
    func testTheMapLabelGivesTheWorldsSizeInKilometres() throws {
        XCTAssertEqual(WorldBounds.maximum.mapLabel(in: .english), "Map, 16.4 by 16.4 kilometres")
        XCTAssertEqual(WorldBounds.maximum.mapLabel(in: .traditionalChinese), "地圖，16.4 × 16.4 公里")
        // An old save's 512 × 384 m: 0.512 and 0.384 km.
        XCTAssertEqual(try WorldBounds(width: 32_768, height: 24_576).mapLabel(in: .english), "Map, 0.5 by 0.4 kilometres")
        // 50 m rounds up to a tenth; a unit rounds down to none.
        XCTAssertEqual(try WorldBounds(width: 1, height: 3_200).mapLabel(in: .traditionalChinese), "地圖，0.0 × 0.1 公里")
    }
}

final class ErrorMessageTests: XCTestCase {
    func testEveryGameErrorHasAPlayerMessage() {
        let point = PlanPoint(x: 4_096, y: 7_168)
        let messages: [GameError: String] = [
            .invalidMapSize(width: 0, height: 5_120): "A map 0 m by 80 m is not supported.",
            .outOfBounds(point): "x 64 m, y 112 m is outside the map.",
            .invalidName: "Enter a name.",
            .insufficientFunds(required: 50_000, available: 1_234):
                "Not enough cash: this costs $ 500.00 and you have $ 12.34.",
            .unknownTrain(TrainID(rawValue: 3)): "There is no train #3.",
            .trainAlreadyPlaced(TrainID(rawValue: 3)): "Train #3 is already on the track.",
            .trainNotPlaced(TrainID(rawValue: 3)): "Train #3 is not on the track.",
            .invalidTrainPosition: "A train can only be placed on the track, with track behind it for all its cars.",
            .invalidMovementRate: "A train's rate cannot be negative.",
            .invalidContinuation: "The train cannot follow that path: each step must lead to joined track, without turning back.",
            .clockOverflow: "Game time cannot advance any further.",
            .idsExhausted: "This game has no IDs left for anything more of this kind.",
            .invalidTimetable:
                "A timetable's times cannot be negative or go back: each stop leaves no earlier than it arrives, and no later than the next stop arrives. A repeating timetable needs a stop, and a period long enough to start again without going back.",
            .unknownStation(StationID(rawValue: 3)): "There is no station #3.",
            .trainServiceActive(TrainID(rawValue: 3)): "Train #3 is running its timetable. Stop its service first.",
            .trainServiceNotActive(TrainID(rawValue: 3)): "Train #3 is not running a timetable.",
            .noTimetable(TrainID(rawValue: 3)): "Train #3 has no timetable to run.",
            .trainNotAtFirstStop(TrainID(rawValue: 3)):
                "Train #3 must be stopped at its timetable's first station to start its service.",
            .unknownLine(LineID(rawValue: 3)): "There is no line #3.",
            .invalidLineStops: "A line calls at two stations or more, and not at the same station twice in a row. A ring calls at three or more, and not at the same station first and last.",
            .invalidTrainPerformance: "That acceleration, braking or top speed is out of range.",
            .invalidServiceWindow: "A line opens between 00:00 and 23:59 and closes after it opens, by 06:00 the next morning.",
            .invalidTrainsInService: "A line cannot run a negative number of trains.",
            .invalidServiceDay: "The day's service levels must start at 00:00 and change at later times within the day.",
            .invalidHeadway: "A target headway must be between 2 minutes and 24 hours.",
            .trainOnLine(TrainID(rawValue: 3)): "Train #3 runs for a line. Take it off the line first.",
            .trainNotOnLine(TrainID(rawValue: 3)): "Train #3 is not on a line.",
            .invalidLinePattern: "A pattern calls at two of its line's stops or more, in the line's order. A ring has no patterns.",
            .unknownLinePattern(2): "The line has no pattern #3.",
            .invalidTrainLength: "A train has 1 to 16 cars.",
            .trackReserved(TrainID(rawValue: 3)): "Train #3 holds that track under traffic control. Wait for it to clear the route.",
            .trainsShareTrack(TrainID(rawValue: 2), TrainID(rawValue: 3)):
                "Trains #2 and #3 need the same track, so traffic control can't be turned on. Move one of them first.",
            .invalidStationDemand: "A station starts 0 to 1,000,000 trips a day.",
        ]

        for (error, message) in messages {
            XCTAssertEqual(error.playerMessage(in: .english), message)
        }
    }

    func testMoneyUsesThousandsSeparators() {
        XCTAssertEqual(Money(0).displayText, "0")
        XCTAssertEqual(Money(999).displayText, "999")
        XCTAssertEqual(Money(1_000).displayText, "1,000")
        XCTAssertEqual(Money(1_000_000).displayText, "1,000,000")
        XCTAssertEqual(Money(-12_345).displayText, "-12,345")
        XCTAssertEqual(Money(.min).displayText, "-9,223,372,036,854,775,808")
    }
}

final class GameTimeDisplayTests: XCTestCase {
    func testGameTimeShowsDayAndTimeOfDay() {
        XCTAssertEqual(GameTime.zero.displayText(in: .english), "Day 1 · 00:00")
        XCTAssertEqual(GameTime(minutes: 9).displayText(in: .english), "Day 1 · 00:09")
        XCTAssertEqual(GameTime(minutes: 8 * 60 + 30).displayText(in: .english), "Day 1 · 08:30")
        XCTAssertEqual(GameTime(minutes: 1_439).displayText(in: .english), "Day 1 · 23:59")
        XCTAssertEqual(GameTime(minutes: 1_440).displayText(in: .english), "Day 2 · 00:00")
        XCTAssertEqual(GameTime(minutes: 10 * 1_440 + 61).displayText(in: .english), "Day 11 · 01:01")
    }

    func testTimesBeforeTheStartCountBackwards() {
        XCTAssertEqual(GameTime(minutes: -1).displayText(in: .english), "Day 0 · 23:59")
    }

    func testTheSecondsShowWhenTheyMatter() {
        XCTAssertEqual(GameTime(seconds: 8 * 3_600 + 30 * 60 + 15).displayTextWithSeconds(in: .english), "Day 1 · 08:30:15")
        XCTAssertEqual(GameTime(seconds: 8 * 3_600 + 30 * 60 + 15).displayText(in: .english), "Day 1 · 08:30")
        XCTAssertEqual(GameTime(seconds: -1).displayTextWithSeconds(in: .english), "Day 0 · 23:59:59")
        // The HUD: whole minutes at a minute a tick or more, seconds below
        // that or between two minutes.
        XCTAssertEqual(GameClock(now: GameTime(minutes: 90), speed: .normal).displayText(in: .english), "Day 1 · 01:30")
        XCTAssertEqual(GameClock(now: GameTime(minutes: 90), speed: .paused).displayText(in: .english), "Day 1 · 01:30")
        XCTAssertEqual(GameClock(now: GameTime(minutes: 90), speed: .x60).displayText(in: .english), "Day 1 · 01:30:00")
        XCTAssertEqual(GameClock(now: GameTime(seconds: 5_401), speed: .paused).displayText(in: .english), "Day 1 · 01:30:01")
    }

    func testSpeedLabels() {
        XCTAssertEqual(GameSpeed.allCases.map { $0.label(in: .english) }, ["Pause", "1×", "10×", "60×", "600×", "1200×", "6000×"])
        XCTAssertEqual(
            GameSpeed.allCases.map { $0.accessibilityName(in: .english) },
            ["Paused", "Real time", "10 times real time", "60 times real time", "600 times real time", "1200 times real time", "6000 times real time, fast forward"]
        )
    }
}
