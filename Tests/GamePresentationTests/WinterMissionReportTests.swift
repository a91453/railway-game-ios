import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 814: what a new game's first line gives the winter missions
/// day by day, so their numbers (3 stations lit, 6 evening trains to the
/// market, 1,000 riders a day) can be judged against what a new player
/// reaches in the event's first week. Asserts nothing; runs only on
/// request:
///
///     WINTER_REPORT=14 swift test --skip-build --filter WinterMissionReportTests
final class WinterMissionReportTests: XCTestCase {
    func testANewGamesFirstLines() throws {
        guard let value = ProcessInfo.processInfo.environment["WINTER_REPORT"] else {
            throw XCTSkip("set WINTER_REPORT=<days> to print the winter missions' report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil }, "WINTER_REPORT is a whole number of days")
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        // BalanceReportTests' first line, open as a new line is (06:00 to
        // midnight), and decision 137's line between two towns.
        for (title, start) in [("A first line, 06:00-24:00", try firstLine()), ("Two towns (seed 1)", try newGameLine(through: [towns[0], towns[1]]))] {
            var world = start
            let line = try XCTUnwrap(world.lines.first)
            var rows = [
                "### \(title): \(Set(line.stops).count) stations, \(line.assignedTrains.count) train(s), round trip \(world.lineJourney(line.id)?.roundTripMinutes ?? 0) min",
                "",
                "| Day | Lit stations | Evening trains to the market | Riders yesterday | After midnight |",
                "| --: | --: | --: | --: | :-: |",
            ]
            for day in 1...days {
                try world.advance(ticks: 1_440)
                let facts = WinterMissionFacts(world: world)
                rows.append("| \(day) | \(facts.stationsLitAtNight) | \(facts.eveningMarketDepartures) | \(facts.yesterdayRiders) | \(facts.hasLineAfterMidnight ? "yes" : "no") |")
            }
            print(rows.joined(separator: "\n") + "\n")
        }
    }

    /// BalanceReportTests' first line (as BusTourismReportTests copies it):
    /// three stations on a 28-tile track across the new game's middle, one
    /// train of four cars, open from 06:00 to midnight.
    private func firstLine() throws -> GameWorld {
        var world = GameWorld.newGame()
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = GameWorld.newGameBounds.width / 2 - 16 * tile, y = GameWorld.newGameBounds.height / 2
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * tile, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 30 * tile, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: x + 2 * tile + middle, y: y)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .standard)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        return world
    }
}
