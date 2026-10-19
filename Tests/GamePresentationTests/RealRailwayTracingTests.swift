import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 213: the network tool traces Taiwan's real railway, on a
/// real-world map at Taipei Main Station with the bundled lines.
@MainActor
final class RealRailwayTracingTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A real-world game at Taipei Main Station with the network tool
    /// laying track, tracing on, and the world points of two TRA stations.
    private func taipei(in language: DisplayLanguage = .traditionalChinese) throws -> (session: GameSession, taipei: PlanPoint, banqiao: PlanPoint) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        // The player's own single track: the real line is double here
        // (decision 247, later), and these tests are about one track.
        session.networkBuildsDouble = false
        let banqiao = try BundledRealData.station("板橋", in: "tra_sched")
        return (session, try BundledRealData.point(tra.coordinate, in: world), try BundledRealData.point(banqiao.coordinate, in: world))
    }

    /// How far `point` is from the nearest real line.
    private func distanceToRealLine(_ point: PlanPoint, in session: GameSession) throws -> Double {
        let traces = try XCTUnwrap(session.realRailwayTraces)
        return try XCTUnwrap(traces.snap(WorldVector(point), within: 1_000 * metre)).distance
    }

    func testATraceFollowsTheRealLineAndIsBuiltAsOneCommand() throws {
        let (session, taipei, banqiao) = try taipei()
        // Taps a little off the line land on it.
        session.tapNetwork(at: PlanPoint(x: taipei.x, y: taipei.y + 640), reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        for anchor in [session.networkStart, session.networkEnd] {
            guard case .point(let point)? = anchor else { return XCTFail("a new point on the line") }
            XCTAssertLessThan(try distanceToRealLine(point, in: session), 1 * metre)
        }
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertNil(preview.traceNote)
        let edges = try XCTUnwrap(preview.traced)
        XCTAssertGreaterThan(edges, 10, "many edges, not one curve")
        // The real Western Trunk Line is 7.2 km from Taipei to Banqiao.
        XCTAssertEqual(Double(preview.length) / metre, 7_200, accuracy: 250)
        // The track keeps to the real line all the way.
        for point in stride(from: 0, to: preview.points.count, by: 8).map({ preview.points[$0] }) {
            XCTAssertLessThan(try distanceToRealLine(point.plan, in: session), 12 * metre)
        }
        XCTAssertFalse(session.networkTracedWay.isEmpty, "the real line lights up under it")
        XCTAssertFalse(session.traceableRealLines.isEmpty)

        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, edges)
        XCTAssertEqual(session.world.economy.balance.amount, before.economy.balance.amount - (preview.cost?.amount ?? 0))
        // Joined end to end: every node but the two ends has two edges.
        let ends = session.world.network.nodes.map(\.ends.count)
        XCTAssertEqual(ends.filter { $0 == 1 }.count, 2)
        XCTAssertEqual(ends.filter { $0 == 2 }.count, edges - 1)
        // One command, logged as itself, and one undo takes it all back.
        guard case .command(.buildTrackChain(let stretches))? = session.commandLog.entries.last?.action else {
            return XCTFail("logged as a chain")
        }
        XCTAssertEqual(stretches.count, edges)
        if case .node? = session.networkStart {} else { XCTFail("the next stretch starts at its end") }
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// The message after a trace says how far and for how much, in words
    /// a player reads: no track-graph terms.
    func testTheTracedMessageSaysHowFarAndForHowMuch() throws {
        let (session, taipei, banqiao) = try taipei(in: .english)
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let pieces = try XCTUnwrap(session.networkPreview?.traced)
        session.buildNetworkTrack()
        let text = try XCTUnwrap(session.message?.text)
        XCTAssertTrue(text.hasPrefix("Traced the real railway for "), text)
        XCTAssertTrue(text.contains("(\(pieces) pieces of track)"), text)
        XCTAssertFalse(text.contains("edge"), text)
    }

    /// Decision 245's gap: a trace a dollar short of its price. The
    /// preview says the whole price and why it cannot be paid, building it
    /// is refused with the same words, and nothing of it is laid.
    func testATraceADollarShortSaysTheWholePriceAndBuildsNothing() throws {
        let (rich, taipei, banqiao) = try taipei(in: .english)
        rich.tapNetwork(at: taipei, reach: reach)
        rich.tapNetwork(at: banqiao, reach: reach)
        let cost = try XCTUnwrap(rich.networkPreview?.cost)
        XCTAssertGreaterThan(cost, .zero)

        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor), balance: cost - Money(1))
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNotNil(preview.traced, "still traced")
        XCTAssertEqual(preview.cost, cost, "the whole price, though the cash is short")
        let problem = try XCTUnwrap(preview.problem)
        let (required, _) = Money.shortfallTexts(required: cost, available: cost - Money(1))
        XCTAssertTrue(problem.contains(required), problem)

        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, problem, "refused in the preview's words")
        XCTAssertEqual(session.world, before, "nothing of it laid")
    }

    func testTheChainCodesAsItIs() throws {
        let (session, taipei, banqiao) = try taipei()
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let plan = try XCTUnwrap(session.tracePlan(from: try XCTUnwrap(session.networkStart), to: try XCTUnwrap(session.networkEnd)))
        let command = PlayerCommand.buildTrackChain(plan.stretches)
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), command)
        XCTAssertThrowsError(try JSONDecoder().decode(PlayerCommand.self, from: Data(#"{"kind":"buildTrackChain"}"#.utf8)))
    }

    /// Where GameCore refuses an edge, the trace stops before it, says
    /// why, and what comes before can be built.
    func testATraceStopsWhereGameCoreRefusesAndSaysWhy() throws {
        let (session, taipei, banqiao) = try taipei()
        // A track across the real line about halfway, laid by hand.
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let way = try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(taipei), within: 50 * metre)).place,
            to: try XCTUnwrap(traces.snap(WorldVector(banqiao), within: 50 * metre)).place
        ))
        let path = WorldPath(way)
        let middle = path.point(at: path.length / 2), across = path.tangent(at: path.length / 2).normal * (150 * metre)
        session.networkTracesRealRailway = false
        session.tapNetwork(at: (middle - across).plan, reach: 1)
        session.tapNetwork(at: (middle + across).plan, reach: 1)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1, session.message?.text ?? "")
        session.clearNetworkDraft()
        session.networkTracesRealRailway = true

        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem, "what comes before can be built")
        let note = try XCTUnwrap(preview.traceNote)
        XCTAssertTrue(note.hasPrefix("描到 "), note)
        XCTAssertFalse(preview.unbuilt.isEmpty)
        XCTAssertEqual(Double(preview.length), path.length / 2, accuracy: 600 * metre)
        XCTAssertFalse(session.networkOverlay?.unbuilt.isEmpty ?? true)

        let built = try XCTUnwrap(preview.traced)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1 + built)
        XCTAssertTrue(session.message?.text.contains("停下") ?? false, session.message?.text ?? "")
    }

    func testOffTheOptionOrTheMapThereIsOneStretch() throws {
        let (session, taipei, banqiao) = try taipei()
        session.networkTracesRealRailway = false
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        XCTAssertNil(session.networkPreview?.traced)
        XCTAssertTrue(session.traceableRealLines.isEmpty)
        XCTAssertTrue(session.networkTracedWay.isEmpty)
        // A blank map has no real railway to trace.
        let blank = GameSession(world: .newGame(), language: .english)
        blank.railways = try BundledRealData.railways()
        XCTAssertFalse(blank.canTraceRealRailway)
        XCTAssertTrue(session.canTraceRealRailway)
    }

    /// Tracing, a drag that starts on a real line draws track rather than
    /// moving the map; off, it moves the map as before.
    func testADragFromARealLineDrawsWhileTracing() throws {
        let (session, taipei, banqiao) = try taipei()
        XCTAssertTrue(session.networkDragDraws(from: taipei, reach: reach))
        session.dragNetwork(from: taipei, to: banqiao, reach: reach)
        XCTAssertNotNil(session.networkPreview?.traced)
        session.endNetworkDrag(from: taipei, to: banqiao, reach: reach)
        session.clearNetworkDraft()
        session.networkTracesRealRailway = false
        XCTAssertFalse(session.networkDragDraws(from: taipei, reach: reach))
    }

    /// Handoff §7.1 (PR526_626 §5, U7): the map reads the traced way at
    /// every redraw, and each read ran a shortest path along the real
    /// lines. It is worked out once for each pair of points.
    func testTheTracedWayIsWorkedOutOnceForEachPairOfPoints() throws {
        let (session, taipei, banqiao) = try taipei()
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let way = session.networkTracedWay
        XCTAssertFalse(way.isEmpty)
        XCTAssertEqual(session.networkTracedWay, way)
        XCTAssertEqual(session.networkOverlay?.tracedWay ?? way, way)
        XCTAssertEqual(session.tracedWaysWorkedOut, 1, "read three times, worked out once")

        session.clearNetworkDraft()
        session.tapNetwork(at: taipei, reach: reach)
        let halfway = PlanPoint(x: (taipei.x + banqiao.x) / 2, y: (taipei.y + banqiao.y) / 2)
        session.dragNetwork(from: taipei, to: halfway, reach: reach)
        _ = session.networkTracedWay
        XCTAssertEqual(session.tracedWaysWorkedOut, 2, "the finger is a new end")
    }

    func testTheTightestRadiusOfAnEdge() {
        func stretch(_ curve: TrackCurve, to: PlanPoint) -> PlayerCommand.TrackStretch {
            PlayerCommand.TrackStretch(
                start: .point(PlanPoint(x: 0, y: 0)), end: .point(to), from: WorldCoordinate(x: 0, y: 0, z: 0),
                to: WorldCoordinate(x: to.x, y: to.y, z: 0), curve: curve, profile: .uniform, structure: .surface, ground: []
            )
        }
        XCTAssertNil(GameSession.tightestRadius(of: stretch(.straight, to: PlanPoint(x: 6_400, y: 0))))
        // A quarter circle of radius 100 m as a cubic (handles 0.5523 r).
        let r = 6_400.0, k = 0.5523 * r
        let quarter = stretch(.cubic(PlanPoint(x: Int64(k), y: 0), PlanPoint(x: Int64(r), y: Int64(r - k))), to: PlanPoint(x: Int64(r), y: Int64(r)))
        XCTAssertEqual(GameSession.tightestRadius(of: quarter) ?? 0, r, accuracy: r * 0.03)
    }

    // MARK: - The real structures (decision 279)

    /// The app's heights.
    private static let heights = try? HeightGrid(
        data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
    )

    /// The Yilan Line traced from Luodong to Xinma over real ground, with
    /// the bundled railways or with them but not their structures: the
    /// built track's kind where Dongshan's station stands, and where the
    /// line runs on the ground midway between Luodong and Dongshan.
    private func dongshan(structures: Bool, structure: TrackStructure = .automatic) throws -> (station: TrackSectionKind?, plain: TrackSectionKind?) {
        let bundled = try BundledRealData.railways()
        let railways = structures ? bundled : try RealRailways(
            lines: BundledRealData.file("track_lines", "geojson"), stations: BundledRealData.file("track_stations", "geojson"),
            names: BundledRealData.file("station_names", "json")
        )
        let dongshan = try BundledRealData.station("冬山", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(dongshan.anchor))
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.heights = try XCTUnwrap(Self.heights)
        session.railways = railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkStructure = structure
        // One track, as the player chose: the real line is double here.
        session.networkBuildsDouble = false
        let luodong = try BundledRealData.point(BundledRealData.station("羅東", in: "tra_sched").coordinate, in: world)
        let xinma = try BundledRealData.point(BundledRealData.station("新馬", in: "tra_sched").coordinate, in: world)
        session.tapNetwork(at: luodong, reach: reach)
        session.tapNetwork(at: xinma, reach: reach)
        XCTAssertNil(try XCTUnwrap(session.networkPreview).problem)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let built = session.world
        func kind(at point: PlanPoint) throws -> TrackSectionKind? {
            var best: (distance: Double, kind: TrackSectionKind)?
            for edge in built.network.edges {
                let geometry = try XCTUnwrap(built.trackGeometry(of: edge.id))
                for span in edge.sectionSpans where span.end > span.start {
                    for sample in geometry.points(from: span.start, to: span.end) {
                        let distance = (WorldVector(sample.plan) - WorldVector(point)).length
                        if best == nil || distance < best!.distance { best = (distance, span.kind) }
                    }
                }
            }
            return best?.kind
        }
        let station = try BundledRealData.point(dongshan.coordinate, in: world)
        let plain = PlanPoint(x: (luodong.x + station.x) / 2, y: (luodong.y + station.y) / 2)
        return (try kind(at: station), try kind(at: plain))
    }

    /// Traced over real ground along the TRA, the track stands on the real
    /// line's viaduct through Dongshan, and on the ground where the real
    /// line is; without the structures, or with a structure the player
    /// chose, as before.
    func testATraceOverRealGroundFollowsTheRealStructures() throws {
        let real = try dongshan(structures: true)
        XCTAssertEqual(real.station, .viaduct, "Dongshan on its viaduct")
        XCTAssertFalse([TrackSectionKind.viaduct, .tunnel].contains(real.plain), "\(String(describing: real.plain))")
        let plain = try dongshan(structures: false)
        XCTAssertNotEqual(plain.station, .viaduct, "without the structures, on the ground")
        let chosen = try dongshan(structures: true, structure: .surface)
        XCTAssertEqual(chosen.station, .surface, "the player's own choice")
    }

    /// The High Speed Rail traced over real ground 3 km either side of
    /// Changhua's station, which stands on the viaduct that carries the line
    /// across the plain: up on a viaduct at the station and at both ends'
    /// halfway points with the structures, on the ground without them.
    func testATraceAlongTheHighSpeedRailFollowsItsViaduct() throws {
        func trace(structures: Bool) throws -> [TrackSectionKind?] {
            let bundled = try BundledRealData.railways()
            let railways = structures ? bundled : try RealRailways(
                lines: BundledRealData.file("track_lines", "geojson"), stations: BundledRealData.file("track_stations", "geojson"),
                names: BundledRealData.file("station_names", "json")
            )
            let changhua = try BundledRealData.station("彰化", in: "thsr_sched")
            var world = GameWorld.newGame(anchor: try XCTUnwrap(changhua.anchor))
            try world.mapGround()
            let session = GameSession(world: world, language: .english)
            session.heights = try XCTUnwrap(Self.heights)
            session.railways = railways
            session.selectTool(.network)
            session.setNetworkMode(.build)
            session.networkTracesRealRailway = true
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let line = try XCTUnwrap(railways.lines.first { $0.system.id == "thsr_sched" && $0.points.count > 100 })
            let path = WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
            let station = try BundledRealData.point(changhua.coordinate, in: world)
            let at = path.project(WorldVector(station))
            let ends = [at - 3_000 * metre, at + 3_000 * metre].map { path.point(at: $0).plan }
            session.tapNetwork(at: ends[0], reach: reach)
            session.tapNetwork(at: ends[1], reach: reach)
            XCTAssertNil(try XCTUnwrap(session.networkPreview).problem)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            let built = session.world
            return try [at - 1_500 * metre, at, at + 1_500 * metre].map { distance in
                let point = WorldVector(path.point(at: distance).plan)
                var best: (distance: Double, kind: TrackSectionKind)?
                for edge in built.network.edges {
                    let geometry = try XCTUnwrap(built.trackGeometry(of: edge.id))
                    for span in edge.sectionSpans where span.end > span.start {
                        for sample in geometry.points(from: span.start, to: span.end) {
                            let away = (WorldVector(sample.plan) - point).length
                            if best == nil || away < best!.distance { best = (away, span.kind) }
                        }
                    }
                }
                return best?.kind
            }
        }
        XCTAssertEqual(try trace(structures: true), [.viaduct, .viaduct, .viaduct])
        XCTAssertFalse(try trace(structures: false).contains(.viaduct), "without the structures, on the plain's ground")
    }

    // MARK: - Single or double, as the real line is (decision 247, later)

    /// A flat real-world game at TRA station `from`, the network tool
    /// tracing, with the two stations' points.
    private func tracing(from: String, to: String, in language: DisplayLanguage = .english) throws -> (session: GameSession, from: PlanPoint, to: PlanPoint) {
        let start = try BundledRealData.station(from, in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(start.anchor))
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        let end = try BundledRealData.station(to, in: "tra_sched")
        return (session, try BundledRealData.point(start.coordinate, in: world), try BundledRealData.point(end.coordinate, in: world))
    }

    /// Shifen to Wanggu on the Pingxi Line, single track all the way in
    /// `tra_track_sections.json`: one track, and the preview says why.
    func testThePingxiLineTracesSingle() throws {
        let (session, shifen, wanggu) = try tracing(from: "十分", to: "望古")
        session.tapNetwork(at: shifen, reach: reach)
        session.tapNetwork(at: wanggu, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.tracedDouble, false)
        XCTAssertEqual(preview.crossoverNote, "Single track, as the real railway is here.")
        XCTAssertFalse(session.networkDoubleShown, "the switch shows what is built")
        XCTAssertFalse(session.networkDoubleChosen)
        let edges = try XCTUnwrap(preview.traced)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains("Single track, as the real railway is here.") ?? false, session.message?.text ?? "")
        guard case .command(.buildTrackChain)? = session.commandLog.entries.last?.action else { return XCTFail("one track") }
        XCTAssertEqual(session.world.network.edges.count, edges)
    }

    /// Luodong to Dongshan on the Yilan Line, double track in the data:
    /// a second track beside the first, in one command, said in both
    /// languages.
    func testTheYilanLineTracesDouble() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let (session, luodong, dongshan) = try tracing(from: "羅東", to: "冬山", in: language)
            session.tapNetwork(at: luodong, reach: reach)
            session.tapNetwork(at: dongshan, reach: reach)
            let preview = try XCTUnwrap(session.networkPreview)
            XCTAssertNil(preview.problem, "\(language)")
            XCTAssertEqual(preview.tracedDouble, true)
            let note = language == .english ? "Double track, as the real railway is here." : "照真實鐵路鋪成複線。"
            XCTAssertEqual(preview.crossoverNote, note)
            XCTAssertFalse(session.networkOverlay?.crossing.isEmpty ?? true, "the second track drawn")
            XCTAssertTrue(session.networkDoubleShown, "the switch shows what is built")
            let edges = try XCTUnwrap(preview.traced)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            XCTAssertTrue(session.message?.text.contains(note) ?? false, session.message?.text ?? "")
            guard case .command(.buildDoubleTrackChain(let main, let parallel, _, _))? = session.commandLog.entries.last?.action else {
                return XCTFail("double track")
            }
            XCTAssertEqual(main.count, edges)
            XCTAssertEqual(parallel.count, edges)
            XCTAssertEqual(session.world.network.edges.count, 2 * edges)
        }
    }

    /// Once the player sets the switch, a trace follows it, either way.
    func testThePlayersChoiceWins() throws {
        do {
            let (session, luodong, dongshan) = try tracing(from: "羅東", to: "冬山")
            session.networkDoubleShown = false
            XCTAssertTrue(session.networkDoubleChosen)
            session.tapNetwork(at: luodong, reach: reach)
            session.tapNetwork(at: dongshan, reach: reach)
            let preview = try XCTUnwrap(session.networkPreview)
            XCTAssertNil(preview.tracedDouble)
            XCTAssertNil(preview.crossoverNote, "nothing said of the real line")
            XCTAssertFalse(session.networkDoubleShown)
            session.buildNetworkTrack()
            guard case .command(.buildTrackChain)? = session.commandLog.entries.last?.action else { return XCTFail("single, as chosen") }
        }
        do {
            let (session, shifen, wanggu) = try tracing(from: "十分", to: "望古")
            session.networkBuildsDouble = true
            session.tapNetwork(at: shifen, reach: reach)
            session.tapNetwork(at: wanggu, reach: reach)
            let preview = try XCTUnwrap(session.networkPreview)
            XCTAssertNil(preview.tracedDouble)
            XCTAssertTrue(session.networkDoubleShown)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            guard case .command(.buildDoubleTrackChain)? = session.commandLog.entries.last?.action else { return XCTFail("double, as chosen") }
        }
    }

    /// The High Speed Rail is not in the data: a trace along it is single,
    /// as before, and says nothing of the real track.
    func testOffTheTRAATraceIsAsBefore() throws {
        let changhua = try BundledRealData.station("彰化", in: "thsr_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(changhua.anchor))
        let session = GameSession(world: world, language: .english)
        let railways = try BundledRealData.railways()
        session.railways = railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let line = try XCTUnwrap(railways.lines.first { $0.system.id == "thsr_sched" && $0.points.count > 100 })
        let path = WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
        let at = path.project(WorldVector(try BundledRealData.point(changhua.coordinate, in: world)))
        session.tapNetwork(at: path.point(at: at - 1_000 * metre).plan, reach: reach)
        session.tapNetwork(at: path.point(at: at + 1_000 * metre).plan, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNotNil(preview.traced)
        XCTAssertNil(preview.tracedDouble)
        XCTAssertNil(preview.crossoverNote)
        XCTAssertFalse(session.networkDoubleShown)
    }
}
