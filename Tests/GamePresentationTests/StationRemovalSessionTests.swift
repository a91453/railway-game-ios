import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 83: demolishing the selected station from the
/// station panel (`removeSelectedStation`), its messages, and Undo
/// (decision 82), which puts the station and its lines back.
@MainActor
final class StationRemovalSessionTests: XCTestCase {
    private let west = StationID(rawValue: 1)
    private let middle = StationID(rawValue: 2)
    private let east = StationID(rawValue: 3)

    /// West, Middle and East, no track; Shuttle (West–Middle) and Long
    /// (West–Middle–East).
    private func makeSession(language: DisplayLanguage = .english) throws -> GameSession {
        var world = try makeWorld(width: 16_384, balance: 100_000)
        for (name, x) in [("West", 1_024), ("Middle", 6_144), ("East", 12_288)] {
            try world.buildStation(named: name, at: PlanPoint(x: Int64(x), y: 3_072))
        }
        try world.createLine(named: "Shuttle", stops: [west, middle])
        try world.createLine(named: "Long", stops: [west, middle, east])
        return GameSession(world: world, language: language)
    }

    func testDemolishingTheSelectedStationAndUndoingIt() throws {
        let session = try makeSession()
        let before = session.world
        session.selectStation(middle)

        session.removeSelectedStation()

        XCTAssertNil(session.world.station(id: middle))
        XCTAssertNil(session.selectedStation)
        XCTAssertEqual(session.world.lines.map(\.name), ["Long"])
        XCTAssertEqual(session.world.lines.first?.stops, [west, east])
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Demolished Middle. Too few stops were left on Shuttle, so the line went too."))

        session.undo()
        XCTAssertEqual(session.world, before)

        session.selectStation(east)
        session.removeSelectedStation()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Demolished East. Its lines no longer call there."))
    }

    func testTheMessagesAreInTheSessionsLanguage() throws {
        let session = try makeSession(language: .traditionalChinese)
        session.removeSelectedStation()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "請先在地圖上選擇車站。"))
        session.selectStation(middle)
        session.removeSelectedStation()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已拆除 Middle。Shuttle 剩下的車站不足，路線也一併刪除。"))
        session.undo()
        session.selectStation(east)
        session.removeSelectedStation()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已拆除 East。路線不再停靠這站。"))
    }

    /// A line's train running through the station refuses it, and the
    /// message says to take the train off its line first; nothing changes
    /// and there is nothing to undo.
    func testALinesRunningTrainRefusesItWithAMessageAboutTheLine() throws {
        var world = try makeWorld(width: 16_384, balance: 1_000_000, speed: .normal)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 3_072))
        let edge = try world.buildTrackEdge(from: a, to: b)
        try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584))
        try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584))
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(StationID(rawValue: 2), on: edge, from: 9_216, to: 13_312)
        let tram = try world.purchaseTrain(named: "Tram").id
        try world.setTrainCars(tram, to: 2)
        try world.placeTrain(tram, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 5_120))
        try world.setTrainContinuation(tram, along: [], stoppingAt: 5_120)
        try world.setTrainMovementRate(tram, to: 1_024)
        let line = try world.createLine(named: "Shuttle", stops: [west, StationID(rawValue: 2)]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(tram, to: line)
        try world.advance(ticks: 1)
        XCTAssertNotNil(world.train(id: tram)?.execution)
        let session = GameSession(world: world)
        session.selectStation(StationID(rawValue: 2))

        session.removeSelectedStation()

        XCTAssertEqual(session.world, world)
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Train #1 of Shuttle serves East. Take it off the line and stop its service first."))
    }
}
