import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 264: simple rules' service. A new line gets its
/// first train, "Add a Train" puts one more on in one tap, and single track
/// carrying more trains than it has places to pass gets a passing loop that
/// becomes a stop of every line through it; each one command, one Undo.
@MainActor
final class AutoServiceTests: XCTestCase {
    /// The first town to the second (seed 1), one straight edge with a
    /// platform at each end, and on from the first town's end to a third
    /// station 4 km further: stations A, B and C (C beyond A), no line.
    private func stations(rules: NewGameRules = .simple) throws -> (world: GameWorld, a: StationID, b: StationID, c: StationID) {
        var world = GameWorld.newGame(rules: rules)
        world.setTourism(nil)
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        let from = towns[0], to = towns[1]
        let platform = Int64(4) * world.platformCarLength
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let span = (dx * dx + dy * dy).squareRoot()
        func along(_ point: PlanPoint, _ metres: Double) -> WorldCoordinate {
            WorldCoordinate(x: point.x + Int64(dx / span * metres), y: point.y + Int64(dy / span * metres))
        }
        let start = try world.buildTrackNode(at: along(from, -Double(platform)))
        let end = try world.buildTrackNode(at: along(to, Double(platform)))
        let main = try world.buildTrackEdge(from: start, to: end)
        let length = world.trackEdge(main)?.length ?? 0
        let a = try world.buildStation(named: "A", at: from).id
        try world.addTrackPlatform(a, on: main, from: platform / 2, to: platform + platform / 2)
        let b = try world.buildStation(named: "B", at: to).id
        try world.addTrackPlatform(b, on: main, from: length - platform - platform / 2, to: length - platform / 2)
        let reach = Double(4_000 * WorldCoordinate.unitsPerMetre)
        let far = try world.buildTrackNode(at: along(from, -reach))
        let branch = try world.buildTrackEdge(from: far, to: start)
        let c = try world.buildStation(named: "C", at: PlanPoint(x: along(from, -reach + Double(platform)).x, y: along(from, -reach + Double(platform)).y)).id
        try world.addTrackPlatform(c, on: branch, from: platform / 2, to: platform + platform / 2)
        return (world, a, b, c)
    }

    /// Line A–B over three edges, A's platform on a short one at the west
    /// end, B's on one at the east end, 4 km of single track between them,
    /// and three trains: one waiting at each end, where the line's trips
    /// start each way, and one halfway along the single track, where the
    /// passing loop it needs goes in.
    private func endsTaken(rules: NewGameRules) throws -> (world: GameWorld, line: LineID, a: StationID, b: StationID, between: TrainID) {
        var world = GameWorld.newGame(rules: rules)
        world.setTourism(nil)
        let platform = Int64(4) * world.platformCarLength
        let end = 2 * platform
        let span = 4_000 * WorldCoordinate.unitsPerMetre
        let x = world.bounds.width / 2 - span / 2, y = world.bounds.height / 2
        let nodes = try [x, x + end, x + end + span, x + 2 * end + span].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: y)) }
        let west = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let middle = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let east = try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + platform, y: y)).id
        try world.addTrackPlatform(a, on: west, from: platform / 2, to: platform + platform / 2)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: x + end + span + platform, y: y)).id
        try world.addTrackPlatform(b, on: east, from: platform / 2, to: platform + platform / 2)
        let line = try world.createLine(named: "Line 1", stops: [a, b]).id
        let journey = try XCTUnwrap(world.lineJourney(line))
        let back = try XCTUnwrap(GameSession.farEndJourney(of: line, in: world))
        for (name, start) in [("West", journey), ("East", back)] {
            let train = try world.purchaseTrain(named: name).id
            try GameSession.placeAtStart(train, of: start, in: &world)
            try world.assignTrain(train, to: line)
        }
        let between = try world.purchaseTrain(named: "Between").id
        let length = try XCTUnwrap(world.trackEdge(middle)?.length)
        try world.placeTrain(between, at: .onEdge(TrackTraversal(edge: middle, direction: .forward), offset: length / 2))
        try world.assignTrain(between, to: line)
        return (world, line, a, b, between)
    }

    /// Realistic rules: the line card's loop goes in where the train
    /// between the ends stands, and with both ends taken that train has
    /// nowhere to go back to. The loop waits, the train stays on its line,
    /// and the message says to tap again once it has passed.
    func testALoopWaitsWhenTheTrainInItsWayCannotGoBack() throws {
        let (world, line, _, _, between) = try endsTaken(rules: .realistic)
        let session = GameSession(world: world)
        session.selectLine(line)
        let plans = session.passingLoopsNeeded(for: line, trains: 3, in: world)
        XCTAssertEqual(plans.count, 1)
        var trial = world
        do throws(GameError) {
            _ = try session.apply(AutoService(newLine: nil, line: line, loops: plans, trains: 0, cars: Train.minimumCars, language: .english), to: &trial)
            XCTFail("the train in the way has nowhere to go back to")
        } catch {
            XCTAssertEqual(error, .trackReserved(between))
        }

        session.addPassingLoopToSelectedLine()
        let text = session.message?.text ?? ""
        XCTAssertEqual(session.message?.kind, .failure, text)
        XCTAssertTrue(text.contains("Tap again once it has passed"), text)
        XCTAssertEqual(session.world.lines, world.lines)
        XCTAssertEqual(session.world.stations, world.stations)
        XCTAssertEqual(session.world.trains, world.trains)
        XCTAssertEqual(session.world.economy.balance, world.economy.balance)
        XCTAssertEqual(session.world.assignedLine(of: between), line)
    }

    /// Simple rules: "Add a Train" on the same line needs that loop first,
    /// so it waits too, and nothing is bought.
    func testAddATrainWaitsWhenTheTrainInTheLoopsWayCannotGoBack() throws {
        let (world, line, _, _, between) = try endsTaken(rules: .simple)
        let session = GameSession(world: world)
        XCTAssertTrue(session.runsLinesForThePlayer)
        session.selectLine(line)
        session.addTrainToSelectedLine()
        let text = session.message?.text ?? ""
        XCTAssertEqual(session.message?.kind, .failure, text)
        XCTAssertTrue(text.contains("Tap again once it has passed"), text)
        XCTAssertEqual(session.world.lines, world.lines)
        XCTAssertEqual(session.world.trains, world.trains)
        XCTAssertEqual(session.world.economy.balance, world.economy.balance)
        XCTAssertEqual(session.world.assignedLine(of: between), line)
    }

    /// Simple rules: a second line over the same single track still opens,
    /// without the loop; the first line keeps its trains, and the message
    /// says the loop goes in with a train added once the other has passed.
    func testANewLineOpensWithoutItsLoopWhenTheTrainInTheWayCannotGoBack() throws {
        let (world, line, a, b, between) = try endsTaken(rules: .simple)
        let session = GameSession(world: world)
        for stop in [a, b] {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        XCTAssertEqual(session.lineOpeningPreview?.loop, false)
        session.createLineFromDraft()
        let text = session.message?.text ?? ""
        XCTAssertEqual(session.message?.kind, .success, text)
        XCTAssertEqual(session.world.lines.count, 2, text)
        XCTAssertTrue(session.world.stations.allSatisfy { $0.operationMode != .closed }, "no loop")
        XCTAssertEqual(session.world.line(id: line), world.line(id: line))
        XCTAssertEqual(session.world.assignedLine(of: between), line)
        XCTAssertEqual(session.world.train(id: between)?.position, world.train(id: between)?.position)
        XCTAssertTrue(text.contains("Once it has passed, tap Add a Train"), text)
    }

    private func draftLine(_ stops: [StationID], in session: GameSession) {
        for stop in stops {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
    }

    func testANewLineComesWithItsFirstTrainAndOneUndoTakesItBack() throws {
        let (world, a, b, _) = try stations()
        let session = GameSession(world: world)
        XCTAssertTrue(session.runsLinesForThePlayer)
        let before = session.world
        draftLine([a, b], in: session)
        let line = try XCTUnwrap(session.world.lines.first)
        XCTAssertEqual(line.stops.first, a)
        XCTAssertEqual(line.stops.last, b)
        XCTAssertEqual(line.trains.count, 1, "the first train comes with the line")
        let train = try XCTUnwrap(session.world.train(id: line.trains[0]))
        XCTAssertNotNil(train.position, "placed where the line's trips start")
        XCTAssertEqual(train.cars, AutoService.maximumCars, "four cars fit its platforms")
        XCTAssertNotNil(line.targetHeadways.peak)
        XCTAssertEqual(line.stops.count, 3, "ready for a second train: a passing loop between A and B")
        let loop = try XCTUnwrap(session.world.station(id: line.stops[1]))
        XCTAssertEqual(loop.operationMode, .closed)
        XCTAssertEqual(session.world.trackPlatforms(of: loop.id).count, 2)
        XCTAssertTrue(session.message?.text.contains("passing loop") == true, session.message?.text ?? "")
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertTrue(session.message?.text.contains("and a train") == true, session.message?.text ?? "")

        session.undo()
        XCTAssertEqual(session.world.lines, before.lines)
        XCTAssertEqual(session.world.trains, before.trains)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance)
    }

    /// The loop the line came with lets "Add a Train" put a second train on
    /// in one tap; a third needs another loop, which cannot go in under the
    /// trains running there, and the message says so.
    func testAddATrainPutsASecondTrainOnAndOneUndoTakesItBack() throws {
        let (world, a, b, _) = try stations()
        let session = GameSession(world: world)
        draftLine([a, b], in: session)
        let before = session.world
        let line = try XCTUnwrap(session.world.lines.first)
        XCTAssertGreaterThanOrEqual(session.world.lineMaximumTrains(line.id) ?? 0, 2)
        session.addTrainToSelectedLine()
        let after = try XCTUnwrap(session.world.line(id: line.id))
        XCTAssertEqual(after.trains.count, 2, session.message?.text ?? "")
        XCTAssertEqual(after.stops, line.stops, "no other loop")
        XCTAssertTrue(after.trains.allSatisfy { session.world.train(id: $0)?.position != nil }, "both on the track")
        XCTAssertTrue(session.message?.text.contains("now runs 2 trains") == true, session.message?.text ?? "")

        session.undo()
        XCTAssertEqual(session.world.lines, before.lines)
        XCTAssertEqual(session.world.trains, before.trains)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance)
    }

    /// CORE_LOOP §1.2: a second line from C over the first's single track
    /// gets a loop on the shared track, a stop of both lines.
    func testASecondLineOverTheFirstsSingleTrackGetsALoopBothLinesStopAt() throws {
        let (world, a, b, c) = try stations()
        let session = GameSession(world: world)
        draftLine([a, b], in: session)
        draftLine([c, a, b], in: session)
        XCTAssertEqual(session.world.lines.count, 2, session.message?.text ?? "")
        let loops = session.world.stations.filter { $0.operationMode == .closed }
        XCTAssertEqual(loops.count, 1)
        let loop = try XCTUnwrap(loops.first)
        for line in session.world.lines {
            XCTAssertEqual(line.trains.count, 1)
            XCTAssertTrue(line.stops.contains(loop.id), line.name)
        }
        XCTAssertEqual(session.world.lines[0].stops, [a, loop.id, b])
        XCTAssertEqual(session.world.lines[1].stops, [c, a, loop.id, b])
    }

    /// The draft's preview says what opening it brings and costs, and the
    /// line opens for that price.
    func testThePreviewNamesTheTrainAndTheLoopAndTheirPrice() throws {
        let (world, a, b, _) = try stations()
        let session = GameSession(world: world)
        for stop in [a, b] {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        let preview = try XCTUnwrap(session.lineOpeningPreview)
        XCTAssertTrue(preview.train)
        XCTAssertTrue(preview.loop)
        XCTAssertTrue(preview.text(in: .traditionalChinese).hasPrefix("含一列車與一處待避線 · "))
        XCTAssertEqual(session.mapLineDraft?.opening, preview)
        let balance = session.world.economy.balance
        session.createLineFromDraft()
        XCTAssertEqual(Money(balance.amount - session.world.economy.balance.amount), preview.cost)
    }

    /// A line whose single track is shorter than 2 km opens with its train
    /// and no loop: its trains are seldom between the stations.
    func testAShortLineOpensWithoutALoop() throws {
        var world = GameWorld.newGame(rules: .simple)
        world.setTourism(nil)
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let platform = Int64(4) * world.platformCarLength
        let span = 1_200 * WorldCoordinate.unitsPerMetre
        let west = try world.buildTrackNode(at: WorldCoordinate(x: middle.x, y: middle.y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: middle.x + span, y: middle.y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: middle.x + platform, y: middle.y)).id
        try world.addTrackPlatform(a, on: edge, from: platform / 2, to: platform + platform / 2)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: middle.x + span - platform, y: middle.y)).id
        try world.addTrackPlatform(b, on: edge, from: span - platform - platform / 2, to: span - platform / 2)
        let session = GameSession(world: world)
        draftLine([a, b], in: session)
        let line = try XCTUnwrap(session.world.lines.first)
        XCTAssertEqual(line.stops, [a, b])
        XCTAssertEqual(line.trains.count, 1)
    }

    /// Over the demo's Line 1, whose trains stand at both its ends, a new
    /// line still opens; its train waits off the track, and the message
    /// says why.
    func testALineWhoseEndsAreTakenStillOpens() throws {
        let session = GameSession(world: DemoWorld.make(in: .english))
        XCTAssertTrue(session.runsLinesForThePlayer)
        let line1 = session.world.lines[0]
        let lines = session.world.lines.count
        draftLine([line1.stops[0], line1.stops[2]], in: session)
        XCTAssertEqual(session.world.lines.count, lines + 1)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertTrue(session.message?.text.contains("waits off the track") == true, session.message?.text ?? "")
    }

    /// Realistic rules: two lines over the same single track with no place
    /// to pass (CORE_LOOP §1.2, where decision 255 turns a train back
    /// early). The station master and the line card say so, and the card's
    /// button builds the loop under the trains standing there, a stop of
    /// both lines, the trains back at their lines' starts; one Undo.
    func testRealisticRulesOfferAPassingLoopWhereTwoLinesCannotPass() throws {
        let (world, a, b, c) = try stations(rules: .realistic)
        let session = GameSession(world: world)
        draftLine([a, b], in: session)
        session.staffSelectedLine(headway: 60)
        draftLine([c, a, b], in: session)
        session.staffSelectedLine(headway: 60)
        let lines = session.world.lines.map(\.id)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(session.world.lines.allSatisfy { $0.trains.count == 1 }, session.message?.text ?? "")
        XCTAssertNotNil(session.world.sharedSingleTrackShortfall(of: lines[1]))
        XCTAssertEqual(
            StationMasterAdvice(world: session.world, worstLosingLine: { nil }),
            .noPlaceToPass(line: lines[0], name: session.world.lines[0].name)
        )
        session.selectLine(lines[1])
        let shortfall = try XCTUnwrap(session.selectedLinePassingShortfall)
        XCTAssertEqual(shortfall.others, [lines[0]])
        XCTAssertTrue(session.passingShortfallText(shortfall).contains("between A and B"), session.passingShortfallText(shortfall))

        let before = session.world
        session.addPassingLoopToSelectedLine()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let loop = try XCTUnwrap(session.world.stations.first { $0.operationMode == .closed })
        XCTAssertEqual(session.world.line(id: lines[0])?.stops, [a, loop.id, b])
        XCTAssertEqual(session.world.line(id: lines[1])?.stops, [c, a, loop.id, b])
        for line in session.world.lines {
            XCTAssertEqual(line.trains.count, 1, line.name)
            XCTAssertNotNil(session.world.train(id: line.trains[0])?.position, line.name)
        }
        XCTAssertNil(session.world.sharedSingleTrackShortfall(of: lines[1]))
        XCTAssertNil(session.selectedLinePassingShortfall)

        session.undo()
        XCTAssertEqual(session.world.lines, before.lines)
        XCTAssertEqual(session.world.stations, before.stations)
        XCTAssertEqual(session.world.trains, before.trains)
    }

    /// A passing loop the player cannot afford is refused as the loop it
    /// is, not as "add a train": its plan buys no train.
    func testAPassingLoopRefusedForCashIsNamedAsTheLoop() throws {
        let (world, a, b, c) = try stations(rules: .realistic)
        let setup = GameSession(world: world)
        draftLine([a, b], in: setup)
        setup.staffSelectedLine(headway: 60)
        draftLine([c, a, b], in: setup)
        setup.staffSelectedLine(headway: 60)
        var poor = setup.world
        poor.economy.settle(Money(1_000 - poor.economy.balance.amount))
        let session = GameSession(world: poor)
        session.selectLine(poor.lines[1].id)
        XCTAssertNotNil(session.selectedLinePassingShortfall)
        session.addPassingLoopToSelectedLine()
        let text = session.message?.text ?? ""
        XCTAssertEqual(session.message?.kind, .failure, text)
        XCTAssertTrue(text.contains("build this passing loop"), text)
        XCTAssertFalse(text.contains("add a train"), text)
    }

    /// Realistic rules and the tutorial ask the player, as before.
    func testRealisticRulesAndTheTutorialLeaveTheTrainsToThePlayer() throws {
        let (world, a, b, _) = try stations(rules: .realistic)
        let session = GameSession(world: world)
        XCTAssertFalse(session.runsLinesForThePlayer)
        draftLine([a, b], in: session)
        XCTAssertEqual(session.world.lines.first?.trains, [])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutoServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        let tutorial = try XCTUnwrap(launcher.session)
        XCTAssertFalse(tutorial.runsLinesForThePlayer)
        tutorial.skipTutorial()
        XCTAssertFalse(tutorial.runsLinesForThePlayer, "the tutorial's game stays as it teaches")
    }

    /// The command log keeps it, and a replay makes it again.
    func testTheCommandIsWrittenAndReadBack() throws {
        let (world, a, b, _) = try stations()
        let session = GameSession(world: world)
        let plan = try XCTUnwrap(session.autoServicePlan(creating: "Line 1", stops: [a, b], targets: nil))
        XCTAssertEqual(plan.loops.count, 1)
        XCTAssertEqual(plan.trains, 1)
        let command = PlayerCommand.autoService(plan)
        let read = try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(read, command)
        XCTAssertEqual(command.name, "autoService")
        XCTAssertEqual(command.actionText(in: .traditionalChinese), "開這條線並配一列車")
    }
}
