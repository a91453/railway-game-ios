import GameCore
import GamePresentation
import XCTest

final class DisplayTextTests: XCTestCase {
    func testTrackShapeNames() {
        XCTAssertEqual(TrackConnections().shapeName, "No connections")
        XCTAssertEqual(TrackConnections.south.shapeName, "Dead end")
        XCTAssertEqual(TrackConnections([.north, .south]).shapeName, "Straight")
        XCTAssertEqual(TrackConnections([.east, .west]).shapeName, "Straight")
        XCTAssertEqual(TrackConnections([.north, .east]).shapeName, "Curve")
        XCTAssertEqual(TrackConnections([.south, .west]).shapeName, "Curve")
        XCTAssertEqual(TrackConnections([.north, .east, .west]).shapeName, "T-junction")
        XCTAssertEqual(TrackConnections([.north, .east, .south, .west]).shapeName, "Four-way")
    }

    func testTrackSummaryListsDirectionsInCompassOrder() {
        XCTAssertEqual(TrackConnections([.west, .north]).summary, "Curve N–W")
        XCTAssertEqual(TrackConnections([.south, .north]).summary, "Straight N–S")
        XCTAssertEqual(TrackConnections().summary, "No connections")
    }

    func testTileSummaries() throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.east, .west])
        try world.buildStation(named: "Central", at: GridPosition(x: 2, y: 0))

        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 0, y: 0)), "Empty")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 1, y: 0)), "Track · Straight E–W")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 2, y: 0)), "Station · Central")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 99, y: 0)), "Outside the map")

        try world.buildTurnout(at: GridPosition(x: 3, y: 1), connections: [.east, .south, .west], stem: .west)
        try world.buildCrossing(at: GridPosition(x: 4, y: 1))
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 3, y: 1)), "Turnout · E–S–W, stem W")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 4, y: 1)), "Level crossing · N–S over E–W")
    }

    func testNetworkSummaryCountsStationsAndTrackTiles() throws {
        var world = try makeWorld()
        XCTAssertEqual(world.networkSummary, "0 stations · 0 track tiles")

        try world.buildStation(named: "Central", at: GridPosition(x: 0, y: 0))
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.east, .west])
        XCTAssertEqual(world.networkSummary, "1 station · 1 track tile")

        try world.buildStation(named: "Harbor", at: GridPosition(x: 3, y: 0))
        try world.buildTrack(at: GridPosition(x: 2, y: 0), connections: [.east, .west])
        XCTAssertEqual(world.networkSummary, "2 stations · 2 track tiles")
    }
}

final class ErrorMessageTests: XCTestCase {
    func testEveryGameErrorHasAPlayerMessage() {
        let position = GridPosition(x: 4, y: 7)
        let messages: [GameError: String] = [
            .invalidMapSize(width: 0, height: 5): "A 0 × 5 map is not supported.",
            .outOfBounds(position): "(4, 7) is outside the map.",
            .tileOccupied(position): "Tile (4, 7) is already occupied.",
            .invalidTrackConnections: "Choose at least one direction for the track.",
            .invalidName: "Enter a name.",
            .insufficientFunds(required: 50_000, available: 1_234):
                "Not enough cash: this costs 50,000 and you have 1,234.",
            .noTrackToRemove(position): "There is no track to remove at (4, 7).",
            .trackInUse(position): "A train is on the track at (4, 7). Take the train off the track first.",
            .unknownTrain(TrainID(rawValue: 3)): "There is no train #3.",
            .trainAlreadyPlaced(TrainID(rawValue: 3)): "Train #3 is already on the track.",
            .trainNotPlaced(TrainID(rawValue: 3)): "Train #3 is not on the track.",
            .invalidTrainPosition: "A train can only be placed on a track tile or between two joined track tiles, with track behind it for all its cars.",
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
            .invalidLineStops: "A line calls at two stations or more, and not at the same station twice in a row.",
            .invalidLineRate: "A line's speed must be at least 1.",
            .invalidServiceWindow: "A line opens between 00:00 and 23:59 and closes after it opens, by 06:00 the next morning.",
            .invalidTrainsInService: "A line cannot run a negative number of trains.",
            .invalidServiceDay: "The day's service levels must start at 00:00 and change at later times within the day.",
            .invalidHeadway: "A target headway must be between 2 minutes and 24 hours.",
            .trainOnLine(TrainID(rawValue: 3)): "Train #3 runs for a line. Take it off the line first.",
            .trainNotOnLine(TrainID(rawValue: 3)): "Train #3 is not on a line.",
            .invalidLinePattern: "A pattern calls at two of its line's stops or more, in the line's order.",
            .unknownLinePattern(2): "The line has no pattern #3.",
            .invalidStationTile(GridPosition(x: 4, y: 2)): "A station can only grow onto an empty tile beside one of its tiles, not (4, 2).",
            .invalidTrainLength: "A train has 1 to 16 cars.",
            .trackReserved(TrainID(rawValue: 3)): "Train #3 holds that track under traffic control. Wait for it to clear the route.",
            .trainsShareTrack(TrainID(rawValue: 2), TrainID(rawValue: 3)):
                "Trains #2 and #3 need the same track, so traffic control can't be turned on. Move one of them first.",
            .invalidStationDemand: "A station starts 0 to 1,000,000 trips a day.",
        ]

        for (error, message) in messages {
            XCTAssertEqual(error.playerMessage, message)
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
        XCTAssertEqual(GameTime.zero.displayText, "Day 1 · 00:00")
        XCTAssertEqual(GameTime(minutes: 9).displayText, "Day 1 · 00:09")
        XCTAssertEqual(GameTime(minutes: 8 * 60 + 30).displayText, "Day 1 · 08:30")
        XCTAssertEqual(GameTime(minutes: 1_439).displayText, "Day 1 · 23:59")
        XCTAssertEqual(GameTime(minutes: 1_440).displayText, "Day 2 · 00:00")
        XCTAssertEqual(GameTime(minutes: 10 * 1_440 + 61).displayText, "Day 11 · 01:01")
    }

    func testTimesBeforeTheStartCountBackwards() {
        XCTAssertEqual(GameTime(minutes: -1).displayText, "Day 0 · 23:59")
    }

    func testSpeedLabels() {
        XCTAssertEqual(GameSpeed.allCases.map(\.label), ["Pause", "1×", "2×"])
        XCTAssertEqual(GameSpeed.allCases.map(\.accessibilityName), ["Paused", "Normal speed", "Double speed"])
    }
}
