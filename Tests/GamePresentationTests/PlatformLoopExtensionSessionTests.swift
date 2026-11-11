import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 691: a platform between a station's two turnouts lengthened by
/// moving the turnouts out, the platform beside it with it, in one command.
final class PlatformLoopExtensionSessionTests: XCTestCase {
    /// ``PlatformTrackSessionTests``' world: a straight track 480 m long
    /// west to east, with station Middle's 96 m (6-car) platform halfway.
    private func world(balance: Money = 10_000_000) throws -> (GameWorld, TrackPlatform) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: balance, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 16_384, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: 12_288, to: 18_432)
        return (world, try XCTUnwrap(world.trackPlatforms(of: station).first))
    }

    /// The station after the platform track tool, its new platform (the
    /// one filling its track) and the old one.
    @MainActor
    private func station(
        _ layout: PlatformTrackLayout, _ side: PlatformTrackSide = .left, balance: Money = 10_000_000, language: DisplayLanguage = .english
    ) throws -> (GameSession, new: TrackPlatform, old: TrackPlatform) {
        let (world, platform) = try world(balance: balance)
        let session = GameSession(world: world, language: language)
        session.addPlatformTrack(beside: platform, layout: layout, side: side)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let platforms = session.world.trackPlatforms(of: platform.station)
        return (session, try XCTUnwrap(platforms.first { $0.start == 0 }), try XCTUnwrap(platforms.first { $0.start != 0 }))
    }

    /// The report from the players of 0.6.0 (125): the platform track's
    /// platform fills its track, and the menu was empty.
    @MainActor
    func testThePlatformTracksPlatformCanBeLengthened() throws {
        let (session, new, old) = try station(.side)
        let offered = session.world.platformExtensions(of: new)
        XCTAssertFalse(offered.isEmpty, "the menu was empty before decision 691")
        XCTAssertEqual(offered.first?.cars, 7)
        XCTAssertEqual(offered.first?.station?.platforms, 2)
        XCTAssertEqual(offered.first?.station?.movesTurnouts, true)
        // From the old platform the same lengths: no longer only as far as
        // the turnouts 50 m away.
        XCTAssertEqual(session.world.platformExtensions(of: old).map(\.cars), offered.map(\.cars))
        XCTAssertGreaterThan(try XCTUnwrap(offered.last?.cars), 12)

        let choices = session.platformExtensionMenuChoices(for: new)
        let eight = try XCTUnwrap(choices.first { $0.id.cars == 8 })
        let cost = try XCTUnwrap(eight.id.station?.cost)
        XCTAssertGreaterThan(cost, .zero)
        XCTAssertEqual(eight.title, "8 cars · 128 m")
        XCTAssertEqual(eight.detail, "Adds 32 m · both platforms · moves the turnouts out · \(cost.moneyText)")
        let (chinese, same, _) = try station(.side, language: .traditionalChinese)
        XCTAssertEqual(same, new)
        XCTAssertEqual(
            chinese.platformExtensionMenuChoices(for: new).first { $0.id.cars == 8 }?.detail,
            "加長 32 公尺 · 兩座月台一起 · 轉轍器往外移 · \(cost.moneyText)"
        )
    }

    /// One command: both platforms 8 cars long, the turnouts farther
    /// apart, every piece of track the one it was; paid once, undone once,
    /// and the log replays to the same world.
    @MainActor
    func testLengtheningMovesTheTurnoutsOutInOneCommand() throws {
        let (session, new, old) = try station(.side)
        let before = session.world
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: new).first { $0.id.cars == 8 })
        let cost = try XCTUnwrap(choice.id.station?.cost)
        session.extendPlatform(choice.id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.message?.text, "Middle’s platforms now take 8 cars (128 m), for \(cost.moneyText).")
        let after = session.world
        XCTAssertEqual(after.economy.balance, before.economy.balance - cost)
        XCTAssertEqual(after.network.nodes.map(\.id), before.network.nodes.map(\.id))
        XCTAssertEqual(after.network.edges.map(\.id), before.network.edges.map(\.id))
        let platforms = after.trackPlatforms(of: new.station)
        XCTAssertEqual(platforms.count, 2)
        // The one filling its track still fills it: a turnout stands a
        // few centimetres past what the cars need.
        for platform in platforms {
            XCTAssertTrue((8 * 1_024...8 * 1_024 + 8).contains(platform.length), "\(platform.length)")
        }
        XCTAssertEqual(platforms.first { $0.edge == new.edge }?.start, 0)
        XCTAssertEqual(platforms.first { $0.edge == new.edge }?.end, after.network.edge(new.edge)?.length)
        XCTAssertEqual(Set(platforms.map(\.edge)), [new.edge, old.edge])
        for platform in platforms {
            XCTAssertEqual(after.platformCars(of: platform), 8)
            let edge = try XCTUnwrap(after.network.edge(platform.edge))
            XCTAssertGreaterThanOrEqual(platform.start, 0)
            XCTAssertLessThanOrEqual(platform.end, edge.length)
        }
        // The two platforms still stand side by side.
        let spans = try platforms.map { platform -> ClosedRange<Int64> in
            let edge = try XCTUnwrap(after.network.edge(platform.edge))
            let from = try XCTUnwrap(after.network.node(edge.from)).position.x
            return (from + platform.start)...(from + platform.end)
        }
        XCTAssertLessThanOrEqual(abs(spans[0].lowerBound - spans[1].lowerBound), 8)
        XCTAssertLessThanOrEqual(abs(spans[0].upperBound - spans[1].upperBound), 8)
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.extendPlatformLoop(new, start: choice.id.start, end: choice.id.end)))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(after)), after)

        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.6.0", build: "1", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, after)

        session.undo()
        XCTAssertEqual(session.world, before)
        session.redo()
        XCTAssertEqual(session.world, after)

        // Longer again, to the longest offered, from the other platform.
        let grown = try XCTUnwrap(after.trackPlatforms(of: new.station).first { $0.edge == old.edge })
        let longest = try XCTUnwrap(session.platformExtensionMenuChoices(for: grown).last)
        session.extendPlatform(longest.id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.trackPlatforms(of: new.station).map { session.world.platformCars(of: $0) }, [longest.id.cars, longest.id.cars])
        XCTAssertTrue(session.platformExtensionMenuChoices(for: try XCTUnwrap(session.world.trackPlatforms(of: new.station).first)).isEmpty
            || longest.id.cars < Train.maximumCars)
    }

    /// An island platform track 11 m out lengthens the same way.
    @MainActor
    func testAnIslandPlatformTrackLengthensToo() throws {
        let (session, new, _) = try station(.island, .right)
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: new).first { $0.id.cars == 10 })
        XCTAssertEqual(choice.id.station?.platforms, 2)
        session.extendPlatform(choice.id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let platforms = session.world.trackPlatforms(of: new.station)
        XCTAssertEqual(platforms.map { session.world.platformCars(of: $0) }, [10, 10])
        let edge = try XCTUnwrap(session.world.network.edge(new.edge))
        XCTAssertEqual(session.world.network.node(edge.from)?.position.y, 8_192 + 704, "still 11 m south")
        XCTAssertEqual(session.world.network.node(edge.to)?.position.y, 8_192 + 704)
    }

    /// A platform track on each side of the main track (three tracks, a
    /// pair of loops): all three platforms grow together.
    @MainActor
    func testAPairOfPlatformTracksLengthensTogether() throws {
        let (session, _, old) = try station(.side, .left)
        session.addPlatformTrack(beside: old, layout: .side, side: .right)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let before = session.world
        XCTAssertEqual(before.trackPlatforms(of: old.station).count, 3)
        for platform in before.trackPlatforms(of: old.station) {
            let choices = session.platformExtensionMenuChoices(for: platform)
            XCTAssertFalse(choices.isEmpty, "\(platform)")
        }
        let asked = try XCTUnwrap(before.trackPlatforms(of: old.station).last)
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: asked).first { $0.id.cars == 9 })
        XCTAssertEqual(choice.id.station?.platforms, 3)
        XCTAssertEqual(choice.detail?.contains("3 platforms"), true, choice.detail ?? "")
        session.extendPlatform(choice.id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.trackPlatforms(of: old.station).map { session.world.platformCars(of: $0) }, [9, 9, 9])
        XCTAssertEqual(session.world.network.edges.map(\.id), before.network.edges.map(\.id))
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// Without the money nothing changes, and the session says what it
    /// was short for.
    @MainActor
    func testWithoutTheMoneyNothingChanges() throws {
        let (session, new, _) = try station(.side)
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: new).last)
        let spent = Money(10_000_000 - session.world.economy.balance.amount)
        // The same station with one coin left after its platform track.
        let (broke, same, _) = try station(.side, balance: Money(spent.amount + 1))
        XCTAssertEqual(same, new)
        let poor = broke.world
        XCTAssertEqual(poor.economy.balance, Money(1))
        broke.extendPlatform(choice.id)
        XCTAssertEqual(broke.message?.kind, .failure)
        XCTAssertEqual(broke.world, poor)
        // The menu still lists it with its price.
        XCTAssertEqual(broke.platformExtensionMenuChoices(for: new).last?.id, choice.id)
    }

    /// Where a platform lies on the map: its two ends.
    private func ends(of platform: TrackPlatform, in world: GameWorld) throws -> [WorldCoordinate] {
        let geometry = try XCTUnwrap(world.trackGeometry(of: platform.edge))
        return [geometry.location(at: platform.start).position, geometry.location(at: platform.end).position]
    }

    /// A train standing on the station's track: refused, nothing changed.
    /// Once it is gone the same request goes through.
    @MainActor
    func testATrainInTheStationRefusesIt() throws {
        let (session, new, _) = try station(.side)
        var world = session.world
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 2)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: new.edge, direction: .forward), offset: 4_096))
        try world.setTrainContinuation(train, along: [], stoppingAt: 4_096)
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: new).first { $0.id.cars == 8 })
        let before = world
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: choice.id.start, end: choice.id.end)) {
            XCTAssertEqual($0 as? GameError, .trackReserved(train))
        }
        XCTAssertEqual(world, before)
    }

    /// Requests the track cannot meet change nothing: an unknown station,
    /// a platform that is not there, one not longer, one past the room.
    @MainActor
    func testWhatCannotBeDoneChangesNothing() throws {
        let (session, new, old) = try station(.side)
        var world = session.world
        let before = world
        let room = try XCTUnwrap(world.platformLoopRoom(of: new))
        XCTAssertGreaterThan(room.before, 0)
        XCTAssertGreaterThan(room.after, 0)
        XCTAssertThrowsError(try world.extendPlatformLoop(StationID(rawValue: 99), on: new.edge, from: new.start, toStart: -1_024, end: new.end))
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: 5, toStart: -1_024, end: new.end))
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: new.start, end: new.end))
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: 512, end: new.end))
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: -room.before - 64, end: new.end))
        XCTAssertThrowsError(try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: new.start, end: new.end + room.after + 64))
        XCTAssertEqual(world, before)
        // All the room there is, one way only.
        try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: new.start, end: new.end + room.after)
        let longer = try XCTUnwrap(world.trackPlatforms(of: new.station).first { $0.edge == new.edge }?.length)
        XCTAssertTrue((new.length + room.after...new.length + room.after + 8).contains(longer), "\(longer)")
        XCTAssertEqual(try ends(of: XCTUnwrap(world.trackPlatforms(of: new.station).first { $0.edge == new.edge }), in: world).first?.x,
                       try ends(of: new, in: before).first?.x)
        XCTAssertNotNil(old)
    }

    /// Platforms of other stations along the line stay where they are on
    /// the map though the track under them was measured again, a line's
    /// chosen platform is still the one it chose, and its trains still
    /// find their way.
    @MainActor
    func testTheRestOfTheLineStaysWhereItIs() throws {
        let (session, new, old) = try station(.side)
        var world = session.world
        let main = try XCTUnwrap(world.network.edge(old.edge))
        let outer = world.network.edges.filter { $0.id != old.edge && ($0.from == main.from || $0.to == main.from || $0.from == main.to || $0.to == main.to) }
            .filter { edge in world.trackGeometry(of: edge.id).map { $0.startHeight == $0.endHeight && $0.points.allSatisfy { $0.plan.y == 8_192 } } ?? false }
        XCTAssertEqual(outer.count, 2)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 4_096, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 28_672, y: 8_704)).id
        for (station, edge) in zip([west, east], outer.sorted { (world.network.node($0.from)?.position.x ?? 0) < (world.network.node($1.from)?.position.x ?? 0) }) {
            let from = try XCTUnwrap(world.network.node(edge.from)).position.x, to = try XCTUnwrap(world.network.node(edge.to)).position.x
            let centre: Int64 = station == west ? 4_096 : 28_672
            let along = from < to ? centre - from : from - centre
            try world.addTrackPlatform(station, on: edge.id, from: along - 1_024, to: along + 1_024)
        }
        let line = try world.createLine(named: "Line", stops: [west, new.station, east]).id
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: new)])
        let westPlatform = try XCTUnwrap(world.trackPlatforms(of: west).first), eastPlatform = try XCTUnwrap(world.trackPlatforms(of: east).first)
        let before = world
        let room = try XCTUnwrap(world.platformLoopRoom(of: new))
        let grow = min(room.before, room.after, 2_048)
        try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: -grow, end: new.end + grow)

        XCTAssertEqual(try ends(of: XCTUnwrap(world.trackPlatforms(of: west).first), in: world), try ends(of: westPlatform, in: before))
        XCTAssertEqual(try ends(of: XCTUnwrap(world.trackPlatforms(of: east).first), in: world), try ends(of: eastPlatform, in: before))
        let grown = try XCTUnwrap(world.trackPlatforms(of: new.station).first { $0.edge == new.edge })
        XCTAssertTrue((new.length + 2 * grow...new.length + 2 * grow + 8).contains(grown.length), "\(grown.length)")
        let after = try XCTUnwrap(world.line(id: line))
        XCTAssertEqual(after.routePreferences.map(\.platform), [grown])
        XCTAssertTrue(world.lineRouteChoices(line, from: 0, to: 1).contains { $0.platform == grown })
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// A train out on the line, on its way to stop on the station's main
    /// track: the station is lengthened under its path, and it stops at
    /// the same place on the ground.
    @MainActor
    func testATrainOnItsWayStopsWhereItWasGoingTo() throws {
        let (session, new, old) = try station(.side)
        var world = session.world
        let main = try XCTUnwrap(world.network.edge(old.edge))
        let outer = try XCTUnwrap(world.network.edges.first { $0.to == main.from && $0.id != old.edge })
        // The line beyond the turnout in two pieces: the train on the far one.
        let joint = try world.splitTrackEdge(outer.id, at: 2_048)
        let away = try XCTUnwrap(world.network.edges.first { $0.to == joint })
        let approach = try XCTUnwrap(world.network.edges.first { $0.from == joint && $0.to == main.from })
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 2)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: away.id, direction: .forward), offset: 1_536))
        try world.setTrainContinuation(train, along: [approach.id, main.id].map { TrackTraversal(edge: $0, direction: .forward) }, stoppingAt: 6_144)
        let stop = try XCTUnwrap(world.trackGeometry(of: main.id)).location(at: 6_144).position
        let choice = try XCTUnwrap(world.platformExtensions(of: new).first { $0.cars == 10 })
        try world.extendPlatformLoop(new.station, on: new.edge, from: new.start, toStart: choice.start, end: choice.end)
        XCTAssertEqual(world.trackPlatforms(of: new.station).map { world.platformCars(of: $0) }, [10, 10])
        let end = try XCTUnwrap(world.train(id: train)?.movement.end)
        XCTAssertGreaterThan(end, 6_144, "the main track starts farther west now")
        XCTAssertEqual(try XCTUnwrap(world.trackGeometry(of: main.id)).location(at: end).position, stop)

        world.setSpeed(.normal)
        try world.setTrainMovementRate(train, to: 64)
        for _ in 0..<600 where world.train(id: train)?.movement.rate != 0 { try world.advance(ticks: 60) }
        guard case .onEdge(let traversal, let offset)? = world.train(id: train)?.position else { return XCTFail("the train left the track") }
        XCTAssertEqual(traversal, TrackTraversal(edge: main.id, direction: .forward))
        XCTAssertEqual(try XCTUnwrap(world.trackGeometry(of: main.id)).location(at: offset).position, stop)
    }


    func testTheCommandKeepsItsFormThroughItsFile() throws {
        let command = PlayerCommand.extendPlatformLoop(TrackPlatform(station: StationID(rawValue: 3), edge: .edge(7), start: 0, end: 900), start: -200, end: 1_200)
        XCTAssertEqual(command.name, "extendPlatformLoop")
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertThrowsError(try JSONDecoder().decode(
            PlayerCommand.self, from: Data(#"{"kind":"extendPlatformLoop","station":3,"edge":7,"startDistance":0,"endDistance":900}"#.utf8)
        ))
    }
}
