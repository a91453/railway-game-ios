import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 214: the depot's tool and panels on decision 209's depots. Tap
/// the end of a track, and sidings fan out from it with a depot that has a
/// platform on each; the station panel makes a station a depot, saying why
/// not; the line panel ticks its depots; a train shows it is leaving,
/// entering or standing in it.
///
/// A straight track from west (x 1024) to east (x 16384) along y 8192,
/// stations West and East on it, the line Main between them.
@MainActor
final class DepotToolsTests: XCTestCase {
    private func world(minutes: Int64 = 600, speed: GameSpeed = .paused) throws -> (GameWorld, west: StationID, east: StationID, end: TrackNodeID) {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: speed)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_288, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 9_216, to: 13_312)
        return (world, west, east, b)
    }

    private func session(_ world: GameWorld) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        return session
    }

    // MARK: - The sidings

    func testATapAtATracksEndLaysSidingsAndADepot() throws {
        let (world, _, _, end) = try world()
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 16_400, y: 8_200), reach: 64)
        XCTAssertEqual(session.networkDepotEnd, end)
        let preview = try XCTUnwrap(session.networkDepotPreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        XCTAssertEqual(preview.tracks.count, DepotYard.defaultSidings)
        XCTAssertEqual(session.networkOverlay?.preview, preview.tracks.first)
        XCTAssertEqual(session.networkOverlay?.crossovers.count, DepotYard.defaultSidings - 1)
        let cost = try XCTUnwrap(preview.cost)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - cost)
        XCTAssertNil(session.networkDepotEnd)

        let after = session.world
        let depot = try XCTUnwrap(after.stations.first { $0.name == "Depot 1" })
        XCTAssertTrue(depot.isDepot)
        let platforms = after.trackPlatforms(of: depot.id)
        XCTAssertEqual(platforms.count, 3, "one on each siding")
        XCTAssertEqual(Set(platforms.map(\.edge)).count, 3)
        for platform in platforms {
            XCTAssertEqual(platform.end - platform.start, Int64(PassingLoopPlan.minimumCars) * Train.carLength, accuracy: 16)
        }
        // A ladder: two turnouts, and each siding's far end a dead end, 5 m
        // apart to the north (left of the way east).
        XCTAssertEqual(after.network.nodes.count { $0.ends.count == 3 }, 2)
        let ends = after.network.nodes.filter { $0.ends.count == 1 && $0.position.x > 16_384 }.map(\.position.y).sorted()
        XCTAssertEqual(ends, [8_192 - 640, 8_192 - 320, 8_192])
                XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(after)), after)
    }

    func testTheNumberOfSidingsAndTheSideAreTheTools() throws {
        let (world, _, _, _) = try world()
        for (count, side) in [(1, PlatformTrackSide.left), (6, .right)] {
            let session = session(world)
            session.networkDepotSidings = count
            session.networkDepotSide = side
            session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
            session.addDepotYard()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            let depot = try XCTUnwrap(session.world.stations.first(where: \.isDepot))
            XCTAssertEqual(session.world.trackPlatforms(of: depot.id).count, count)
            let ys = session.world.network.nodes.filter { $0.ends.count == 1 && $0.position.x > 16_384 }.map(\.position.y)
            XCTAssertEqual(ys.max(), side == .right ? 8_192 + Int64(count - 1) * 320 : 8_192)
        }
    }

    func testOnlyATracksEndTakesSidings() throws {
        let (world, _, _, _) = try world()
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 8_192, y: 8_192), reach: 64)
        XCTAssertNil(session.networkDepotEnd)
        XCTAssertEqual(session.message?.kind, .failure)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
    }

    /// Every number of sidings, on either side, bends out from a track's
    /// end: the S-curves run on ahead, so the plan never fails for want of
    /// one. Were one ever refused, it says so, not "tap the end".
    func testTheSidingsBendOutFromAnyEnd() throws {
        let (world, _, _, end) = try world()
        let session = session(world)
        for sidings in DepotYard.sidings {
            for side in PlatformTrackSide.allCases {
                guard case .success(let plan) = session.depotYardPlan(from: end, sidings: sidings, side: side) else {
                    return XCTFail("\(sidings) sidings on the \(side) side")
                }
                XCTAssertEqual(plan.branches.count, sidings - 1)
            }
        }
        XCTAssertNotEqual(DepotYardProblem.cannotBend.text(in: .traditionalChinese), DepotYardProblem.notAnEnd.text(in: .traditionalChinese))
    }

    /// No room past the world's edge: GameCore refuses, and nothing is
    /// built.
    func testSidingsThatDoNotFitAreRefusedWhole() throws {
        var (world, _, _, _) = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 55_296, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 63_488, y: 2_048))
        try world.buildTrackEdge(from: a, to: b)
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 63_488, y: 2_048), reach: 64)
        XCTAssertNotNil(session.networkDepotPreview?.problem)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
    }

    func testTheSidingsAreLoggedAndReplayed() throws {
        let (world, _, _, _) = try world()
        let session = session(world)
        session.networkDepotSide = .right
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let entries = session.commandLog.entries
        guard case .command(.buildDepotYard)? = entries.last?.action else { return XCTFail("\(entries)") }
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        XCTAssertEqual(report.entries, entries)
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    // MARK: - A line's trains in and out of it

    /// The line Main with one train, given the depot the tool laid: after
    /// the window closes the train runs empty into it ("Entering depot")
    /// and stands there ("In depot", the line's badge), and in the morning
    /// runs out of it ("Leaving depot").
    func testALinesTrainGoesInAndOutOfTheToolsDepot() throws {
        var (world, west, east, _) = try world(minutes: 1_380)
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        try world.setLineServiceWindow(main, to: .standard)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1").id
        // Standing at West's platform: at the node where it ends.
        let first = try world.splitTrackEdge(XCTUnwrap(world.network.edges.first).id, at: 5_120)
        let into = try XCTUnwrap(world.network.edges.first { $0.to == first }).id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: into, direction: .forward), offset: 5_120))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: main)
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.selectLine(main)
        let row = try XCTUnwrap(session.selectedLineDepotRow)
        XCTAssertNil(row.problem)
        let depot = try XCTUnwrap(row.choices.first).station
        session.toggleSelectedLineDepot(depot)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: main)?.depot, depot)
        XCTAssertEqual(session.selectedLineDepotRow?.chosen, [depot])

        // The session pauses the game it opens.
        var running = session.world
        running.resume()
        var seen: [TrainDepotState] = []
        for _ in 0..<(8 * 60) {
            try running.advance(ticks: 1)
            if let state = running.depotState(of: train), seen.last != state { seen.append(state) }
        }
        XCTAssertEqual(seen, [.pullingIn, .inDepot, .pullingOut], "\(seen)")
        // Through the night it stood in the depot: the line's badge and
        // the follow bar said so.
        var night = session.world
        night.resume()
        for _ in 0..<(6 * 60) where night.depotState(of: train) != .inDepot {
            try night.advance(ticks: 1)
        }
        XCTAssertEqual(night.trainsInDepot(of: main), 1)
        // The badge counts the line's own depots only: given another one,
        // the train standing in the first is not in the line's depot.
        var moved = night
        let other = try moved.buildStation(named: "Other", at: PlanPoint(x: 40_960, y: 12_288)).id
        try moved.setStationDepot(other, to: true)
        try moved.setLineDepots(main, to: [other])
        XCTAssertEqual(moved.depotState(of: train), .inDepot)
        XCTAssertEqual(moved.trainsInDepot(of: main), 0)
        XCTAssertEqual(night.followBarInfo(of: train, in: .traditionalChinese)?.status, .depot(.inDepot))
        XCTAssertEqual(night.followBarInfo(of: train, in: .traditionalChinese)?.detail(in: .traditionalChinese).hasSuffix("· 在庫"), true)
        XCTAssertEqual(TrainDepotState.pullingOut.text(in: .traditionalChinese), "出庫中")
        XCTAssertEqual(TrainDepotState.pullingIn.text(in: .traditionalChinese), "入庫中")
    }

    // MARK: - The panels

    func testTheStationPanelSaysWhyAStationCannotBecomeADepot() throws {
        var (world, west, east, _) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        // Middle on an edge of its own between West's and East's.
        for x: Int64 in [9_984, 6_400] {
            let point = try XCTUnwrap(world.trackEdgePoint(near: PlanPoint(x: x, y: 8_192), within: 16))
            _ = try world.splitTrackEdge(point.edge, at: point.distance)
        }
        let between = try XCTUnwrap(world.trackEdgePoint(near: PlanPoint(x: 8_192, y: 8_192), within: 16)).edge
        let middle = try world.buildStation(named: "Middle", at: PlanPoint(x: 8_192, y: 8_704)).id
        try world.addTrackPlatform(middle, on: between, from: 256, to: 3_328)
        let session = GameSession(world: world, language: .traditionalChinese)

        // A line stops at West.
        session.selectStation(west)
        let stopping = try XCTUnwrap(session.selectedStationDepotSwitch)
        XCTAssertFalse(stopping.isDepot)
        XCTAssertEqual(stopping.title(in: .traditionalChinese), "設為機廠")
        XCTAssertEqual(stopping.problem, "「Main」停靠這裡：機廠不載客，先把這站從路線的停靠站拿掉。")
        session.setSelectedStationDepot(true)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)

        // Middle lies on Main's only way: GameCore refuses, naming it.
        session.selectStation(middle)
        XCTAssertNil(session.selectedStationDepotSwitch?.problem)
        session.setSelectedStationDepot(true)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, "設成機廠會讓「Main」開不通：路線不能走機廠的停車線。")
        XCTAssertEqual(session.world, world)

        // Without the line it may, and a line using it holds it.
        var free = world
        try free.removeLine(main)
        let other = GameSession(world: free, language: .traditionalChinese)
        other.selectStation(middle)
        other.setSelectedStationDepot(true)
        XCTAssertEqual(other.message?.kind, .success, other.message?.text ?? "")
        XCTAssertEqual(other.selectedStationDepotSwitch?.isDepot, true)
        XCTAssertEqual(other.selectedStationDepotSwitch?.title(in: .traditionalChinese), "取消機廠")
        guard case .command(.edit(.setStationDepot(middle, true)))? = other.commandLog.entries.last?.action else {
            return XCTFail("logged as the edit")
        }
        other.setSelectedStationDepot(false)
        XCTAssertEqual(other.message?.kind, .success, other.message?.text ?? "")
        XCTAssertFalse(other.world.station(id: middle)?.isDepot ?? true)
    }

    func testTheLinePanelSaysWhenThereIsNoDepotToChoose() throws {
        var (world, west, east, _) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectLine(main)
        XCTAssertEqual(session.selectedLineDepotRow?.choices, [])
        XCTAssertEqual(session.selectedLineDepotRow?.problem?.hasPrefix("還沒有機廠"), true)

        let run = LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 900, departure: 900)])
        try world.setLineRuns(main, to: [run])
        // Decision 221: a line that runs to a timetable chooses a depot too.
        let yard = try world.buildStation(named: "Yard", at: PlanPoint(x: 20_480, y: 12_288)).id
        try world.setStationDepot(yard, to: true)
        let timed = GameSession(world: world, language: .traditionalChinese)
        timed.selectLine(main)
        XCTAssertNil(timed.selectedLineDepotRow?.problem)
        XCTAssertEqual(timed.selectedLineDepotRow?.choices.map(\.station), [yard])
    }
}

extension DepotToolsTests {
    /// Decision 221: the line panel ticks several depots. The list stands
    /// nearest the line's ends first, the line keeps its ticked depots in
    /// that order, unticking the last leaves its trains at its ends, a
    /// station is held as long as any line ticks it, and every tick is one
    /// edit the command log replays.
    func testTheLinePanelTicksSeveralDepots() throws {
        var (world, west, east, _) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        // Far first, so its number is lower than Near's.
        let far = try world.buildStation(named: "Far", at: PlanPoint(x: 30_720, y: 12_288)).id
        let near = try world.buildStation(named: "Near", at: PlanPoint(x: 14_336, y: 10_240)).id
        try world.setStationDepot(far, to: true)
        try world.setStationDepot(near, to: true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectLine(main)
        let row = try XCTUnwrap(session.selectedLineDepotRow)
        XCTAssertEqual(row.choices.map(\.station), [near, far])
        XCTAssertEqual(row.choices.map(\.isChosen), [false, false])
        XCTAssertEqual(row.chosen, [])

        session.toggleSelectedLineDepot(far)
        XCTAssertEqual(session.message?.text, "「Main」的列車現在停機廠「Far」：首班前出庫、收班後入庫。")
        session.toggleSelectedLineDepot(near)
        XCTAssertEqual(session.message?.text, "「Main」的列車現在也會回機廠「Near」：每列車回最近的那一個。")
        XCTAssertEqual(session.world.line(id: main)?.depots, [near, far])
        XCTAssertEqual(session.selectedLineDepotRow?.choices.map(\.isChosen), [true, true])
        guard case .command(.edit(.setLineDepots(main, [near, far])))? = session.commandLog.entries.last?.action else {
            return XCTFail("logged as the edit")
        }

        // Its second depot is held as well as its first.
        session.selectStation(far)
        XCTAssertEqual(session.selectedStationDepotSwitch?.problem, "「Main」把列車停在這裡：先到路線面板取消勾選這個機廠。")
        session.selectLine(main)

        session.toggleSelectedLineDepot(near)
        XCTAssertEqual(session.message?.text, "「Main」的列車不再回機廠「Near」。")
        XCTAssertEqual(session.world.line(id: main)?.depots, [far])
        session.toggleSelectedLineDepot(far)
        XCTAssertEqual(session.message?.text, "「Main」的列車現在停在路線兩端。")
        XCTAssertEqual(session.world.line(id: main)?.depots, [])
        XCTAssertEqual(session.selectedLineDepotRow?.choices.map(\.isChosen), [false, false])

        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    func testTheHelpPageHasADepotEntry() {
        XCTAssertTrue(HelpGuide.entries(matching: "機廠").contains { $0.id == "depot" })
        XCTAssertTrue(HelpGuide.entries(matching: "depot sidings").contains { $0.id == "depot" })
    }
}
