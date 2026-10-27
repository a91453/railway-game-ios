import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The panels' and tools' edits as values (ARCHITECTURE decision 193,
/// later): each is logged in its place, keeps its form through the log's
/// file, does what its function's closure did, and a game made of them
/// replays to the same world.
@MainActor
final class CommandEditTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)

    /// Alpha, Beta, Gamma and Delta along one straight track, money to
    /// spend, paused.
    private func stationsWorld() throws -> (GameWorld, [StationID]) {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 100_000_000, speed: .paused)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        return (world, stops)
    }

    /// A game played through the panels: a line drawn and staffed, an
    /// express, a train bought, fitted, placed and assigned, time running,
    /// the line re-formed, a rename undone and redone, a loan, the routing,
    /// a timetable refused, the express taken off.
    private func playedSession() throws -> GameSession {
        let (world, stops) = try stationsWorld()
        let session = GameSession(world: world)
        for stop in stops {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        session.renameSelectedLine(to: "Main")
        session.setSelectedLineAllDay(true)
        session.staffSelectedLine(headway: 10)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.addPatternToSelectedLine(from: 0, to: 3, express: true)
        session.setSelectedLineTargetHeadway(15, at: .offPeak)
        session.setSelectedLineTrains(1, at: .peak, pattern: 0)
        session.purchaseTrain()
        session.setSelectedTrainCars(2)
        session.selectStation(stops[0])
        session.placeSelectedTrain()
        XCTAssertNotNil(session.world.train(id: try XCTUnwrap(session.selectedTrainID))?.position, session.message?.text ?? "")
        session.assignSelectedTrainToSelectedLine(pattern: 0)
        session.setSpeed(.normal)
        session.advance(ticks: 45)
        session.reformSelectedLine(type: nil, cars: 2)
        session.advance(ticks: 20)
        session.selectStation(stops[1])
        session.renameSelectedStation(to: "Beta Square")
        session.undo()
        session.redo()
        session.borrowLoanStep()
        session.repayLoanStep()
        session.setPassengerRoutingMode(.network)
        session.setFareRules(.flat(Money(300)))
        session.advance(ticks: 90)
        // A timetable for a train on a line is refused, and logged so.
        session.addStopToSelectedTrainTimetable(stops[2])
        XCTAssertEqual(session.message?.kind, .failure)
        session.removePatternFromSelectedLine(0)
        session.advance(ticks: 30)
        return session
    }

    func testAGamePlayedThroughThePanelsIsLoggedAndReplaysToTheSameWorld() throws {
        let session = try playedSession()
        let entries = session.commandLog.entries
        let unrecorded = entries.compactMap { entry -> String? in
            if case .unrecorded(let caller) = entry.action { return caller }
            return nil
        }
        XCTAssertEqual(unrecorded, [], "every edit has a value")
        let edits = entries.compactMap { entry -> String? in
            if case .command(.edit(let edit)) = entry.action { return edit.name }
            return nil
        }
        for name in ["createLine", "renameLine", "staffLine", "addLinePattern", "purchaseTrain", "placeTrain", "assignTrain", "reformLine", "renameStation", "borrow", "setFareRules", "setTrainTimetable"] {
            XCTAssertTrue(edits.contains(name), "\(name) in \(edits)")
        }
        XCTAssertTrue(entries.contains { $0.refused }, "a refused edit is logged too")
        XCTAssertEqual(session.world.trains.count, 2, "one staffing the line, one bought")

        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        XCTAssertEqual(report.entries, entries, "every edit keeps its form through the file")
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    /// Every kind of edit keeps its form through the log's file; one whose
    /// value this build cannot read stops the replay instead of the report.
    func testEveryEditKeepsItsFormThroughItsFile() throws {
        let train = TrainID(rawValue: 3), line = LineID(rawValue: 2), station = StationID(rawValue: 4)
        let demand = StationDemand(kind: .office, dailyTrips: 900)
        let stop = ScheduledStop(station: station, arrival: GameTime(seconds: 60), departure: GameTime(seconds: 120))
        let edits: [PlayerCommand.Edit] = [
            .setTrafficControl(true), .setDisruptions(Disruptions(level: DisruptionLevel.allCases[0], country: "TW", seed: 7)),
            .setDisruptions(nil), .setPassengerRoutingMode(.network), .setEconomyMode(.free), .setFareRules(.flat(Money(300))),
            .setDayPass(Money(1_500)), .setDayPass(nil), .borrow(Money(1_000)), .repayLoan(Money(1_000)), .setServiceDay(try makeWorld().serviceDay),
            .purchaseTrain(name: "列車 1"), .sellTrain(train), .setTrainCars(train, cars: 3), .setTrainType(train, .highSpeed),
            .setTrainType(train, nil), .setTrainRate(train, rate: 40), .resumeTrain(train),
            .sendTrain(train, along: [PlayerCommand.Edit.Step(TrackTraversal(edge: .edge(2), direction: .backward))], stoppingAt: 512),
            .reverseTrain(train), .unplaceTrain(train), .setTrainPerformance(train, .standard),
            .setTrainTimetable(train, [stop], period: 3_600), .startTrainService(train), .stopTrainService(train),
            .assignTrain(train, line, pattern: 1), .unassignTrain(train), .placeTrain(train, at: station, heading: .west),
            .staffLine(line, headway: 10, type: .highSpeed, cars: 4, language: .traditionalChinese),
            .reformLine(line, type: nil, cars: 2, language: .english),
            .addLineTrains(line, count: 2, type: nil, cars: 1, targets: TargetHeadways(peak: 10, low: 30), language: .english),
            .removeLineTrains(line, count: 1, targets: TargetHeadways(peak: 20, offPeak: 20, low: 20)),
            .renameStation(station, name: "北門"), .removeStation(station), .setStationDemand(station, demand), .setStationDemand(station, nil),
            .applyStationDemand(demand, to: [station, StationID(rawValue: 5)]), .setStationOperationMode(station, StationOperationMode.allCases[0]),
            .linkTransfer(station, StationID(rawValue: 5)), .unlinkTransfer(station), .buildFreightYard(station), .removeFreightYard(station),
            .buildStationRoad(station), .turnOnRoads(towns: [PlanPoint(x: 900, y: 1_200)]),
            .setFreightProduct(station, CargoKind.allCases[0]),
            .createLine(name: "Main", stops: [station, StationID(rawValue: 5)], targets: TargetHeadways(peak: 10, offPeak: 15)),
            .createLine(name: "Branch", stops: [station], targets: nil), .duplicateLine(line, name: "Main - Fork"), .removeLine(line),
            .renameLine(line, name: "Main"), .setLineColor(line, LineColor(rgb: 0x3366CC)), .setLineColor(line, nil),
            .setLineCode(line, LineCode("BL")), .setLineCode(line, nil),
            .setLineStops(line, [station]), .reverseLineStops(line), .setLineRoutes(line, [], pattern: nil),
            .setLineWindow(line, .allDay), .setLineRing(line, true), .setLineTrains(line, TrainsInService(peak: 3, offPeak: 2, low: 1), pattern: 0),
            .setLineTargets(line, TargetHeadways(peak: 10), pattern: nil), .addLinePattern(line, calls: [0, 3]), .removeLinePattern(line, index: 0),
            .setLinePerformance(line, .standard), .setLineFreight(line, true),
            .placeBuilding(PlacedBuildingKind.allCases[0], at: PlanPoint(x: 900, y: 1_200)), .sellBuilding(PlacedBuildingID(rawValue: 2)),
            .demolishBuilding(PlacedBuildingID(rawValue: 2)), .setZone(.init(Zone.allCases[0]), rows: 2...4, columns: 0...0),
            .setZone(.init(nil), rows: 0...1, columns: 3...5), .buyMapTile(MapTile(row: 1, column: 2)),
            .acceptRequest(4), .declineRequest(5), .investInSouvenirShop(AttractionID(rawValue: 6)),
            .buildStationCommerce(station), .upgradeStationCommerce(station), .demolishStationCommerce(station),
            .setStationDepot(station, true), .setLineDepot(line, station), .setLineDepot(line, nil),
            .setLineDepots(line, [station, StationID(rawValue: 5)]),
        ]
        let entries = edits.enumerated().map { CommandLog.Entry(time: Int64($0.offset), action: .command(.edit($0.element))) }
        let data = try JSONEncoder().encode(entries)
        XCTAssertEqual(try JSONDecoder().decode([CommandLog.Entry].self, from: data), entries)
        XCTAssertEqual(Set(edits.map(\.name)).count, edits.count - 9, "each kind, nine of them twice")
        XCTAssertEqual(PlayerCommand.edit(.reverseTrain(train)).name, "reverseTrain")

        // A zone this build does not know: read back as not recorded.
        let unknown = Data(#"{"time":0,"action":"command","command":{"kind":"edit","edit":{"setZone":{"_0":"lava","rows":[0,1],"columns":[0,1]}}}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CommandLog.Entry.self, from: unknown).action, .unrecorded("a command this build cannot read"))
    }

    /// An edit that is one `GameWorld` command makes what that command
    /// makes, or throws what it throws, as its function's closure did.
    func testASingleCommandsEditMakesWhatItsCommandMakes() throws {
        let (base, stops) = try stationsWorld()
        var world = base
        let made = try world.createLine(named: "Main", stops: stops)
        let train = try world.purchaseTrain(named: "Train 1")
        let cases: [(PlayerCommand.Edit, (inout GameWorld) throws(GameError) -> Void)] = [
            (.renameStation(stops[0], name: "North"), { world throws(GameError) in try world.renameStation(stops[0], to: "North") }),
            (.renameStation(stops[0], name: ""), { world throws(GameError) in try world.renameStation(stops[0], to: "") }),
            (.setLineStops(made.id, [stops[0], stops[2]]), { world throws(GameError) in try world.setLineStops(made.id, to: [stops[0], stops[2]]) }),
            (.setLineStops(made.id, [stops[0]]), { world throws(GameError) in try world.setLineStops(made.id, to: [stops[0]]) }),
            (.reverseLineStops(made.id), { world throws(GameError) in try world.reverseLineStops(made.id) }),
            (.setLineRing(made.id, true), { world throws(GameError) in try world.setLineRing(made.id, to: true) }),
            (.setTrainCars(train.id, cars: 3), { world throws(GameError) in try world.setTrainCars(train.id, to: 3) }),
            (.setTrainCars(train.id, cars: 99), { world throws(GameError) in try world.setTrainCars(train.id, to: 99) }),
            (.reverseTrain(train.id), { world throws(GameError) in try world.reverseTrain(train.id) }),
            (.sellTrain(train.id), { world throws(GameError) in try world.sellTrain(train.id) }),
            (.removeLine(made.id), { world throws(GameError) in try world.removeLine(made.id) }),
            (.removeStation(stops[3]), { world throws(GameError) in try world.removeStation(stops[3]) }),
            (.borrow(CompanyAccounts.loanStep), { world throws(GameError) in try world.borrow(CompanyAccounts.loanStep) }),
            (.repayLoan(CompanyAccounts.loanStep), { world throws(GameError) in try world.repayLoan(CompanyAccounts.loanStep) }),
        ]
        for (edit, closure) in cases {
            let session = GameSession(world: world)
            var byEdit = world, byClosure = world
            let editError = Result { () throws(GameError) in _ = try session.apply(edit, to: &byEdit) }.failure
            let closureError = Result { () throws(GameError) in try closure(&byClosure) }.failure
            XCTAssertEqual(editError, closureError, edit.name)
            XCTAssertEqual(byEdit, byClosure, edit.name)
            session.perform(edit) { _, _, _ in "" }
            XCTAssertEqual(session.world, editError == nil ? byClosure : world, edit.name)
            XCTAssertEqual(session.commandLog.entries.last?.refused, editError != nil, edit.name)
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
