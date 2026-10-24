@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 403 (續二): the followed train's horn on the 3D map, by the
/// kind of train, from the follow bar's button and by itself.
final class TrainHornTests: XCTestCase {
    /// A train of type `code` (`nil` for the standard car).
    private func horn(of code: String?) throws -> TrainHorn {
        var world = try GameWorld(bounds: WorldBounds(width: 4_096, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        let id = try world.purchaseTrain(named: "T").id
        if let code { try world.setTrainType(id, to: try XCTUnwrap(TrainType(rawValue: code))) }
        return TrainHorn.of(try XCTUnwrap(world.train(id: id)))
    }

    func testEachKindOfTrainHasItsHorn() throws {
        XCTAssertEqual(try horn(of: nil), .electric, "the standard car sounds as its running sound, electric")
        for code in ["EMU3000", "EMU100", "E200CK", "E500CK", "HAIFENG", "SHANLAN", "MINGRI", "STAR"] {
            XCTAssertEqual(try horn(of: code), .electric, code)
        }
        for code in ["R100CK", "R200CK", "BLUE"] {
            XCTAssertEqual(try horn(of: code), .diesel, "\(code) is hauled by a diesel")
        }
        for code in ["STEAM", "SUMMER"] {
            XCTAssertEqual(try horn(of: code), .steam, code)
        }
        XCTAssertEqual(try horn(of: "HSR"), .highSpeed)
        for code in ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL"] {
            XCTAssertEqual(try horn(of: code), .metro, code)
        }
        // Every type has one of the five.
        for type in TrainType.allCases {
            XCTAssertTrue(TrainHorn.allCases.contains(try horn(of: type.rawValue)))
        }
    }

    func testAPhotoOfARealWorldMapCreditsItsData() {
        XCTAssertEqual(DataSourceCredits.map3DPhoto(realWorld: false, in: .english), "", "the player's own map owes nothing")
        let credit = DataSourceCredits.map3DPhoto(realWorld: true, in: .traditionalChinese)
        for name in ["OpenStreetMap", "Overture Maps", "Copernicus DEM", "交通部 TDX"] {
            XCTAssertTrue(credit.contains(name), name)
        }
    }

    func testOnlyTheRailwaysHornsBlowByThemselves() {
        XCTAssertEqual(TrainHorn.allCases.filter(\.blowsByItself), [.electric, .diesel, .steam])
    }

    func testEveryHornIsABundledFileInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let listed = Set((manifest?["files"] as? [[String: Any]] ?? []).compactMap { $0["file"] as? String })
        for horn in TrainHorn.allCases {
            let cue = SoundCue.horn(horn)
            XCTAssertEqual(cue.category, .effects, "follows the effects' volume")
            let file = "\(cue.resource.name).\(cue.resource.extension)"
            XCTAssertTrue(listed.contains(file), "\(file) is in the manifest")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
        }
    }

    func testItBlowsNearingAStopAndIntoATunnelOnce() {
        let train = TrainID(rawValue: 1), other = TrainID(rawValue: 2)
        let stop = TrainHorn.Place.Stop(stop: 1, cycle: 0)
        func place(_ id: TrainID = train, nearing: TrainHorn.Place.Stop? = nil, tunnel: Bool = false) -> TrainHorn.Place {
            TrainHorn.Place(train: id, nearing: nearing, inTunnel: tunnel)
        }
        XCTAssertFalse(TrainHorn.blowsByItself(from: nil, to: place(nearing: stop, tunnel: true)), "not as following begins")
        XCTAssertTrue(TrainHorn.blowsByItself(from: place(), to: place(nearing: stop)), "within a kilometre of the stop")
        XCTAssertFalse(TrainHorn.blowsByItself(from: place(nearing: stop), to: place(nearing: stop)), "once a stop")
        XCTAssertTrue(TrainHorn.blowsByItself(from: place(nearing: stop), to: place(nearing: .init(stop: 2, cycle: 0))),
                      "a stop less than a kilometre past the last")
        XCTAssertTrue(TrainHorn.blowsByItself(from: place(), to: place(tunnel: true)), "into a tunnel")
        XCTAssertFalse(TrainHorn.blowsByItself(from: place(tunnel: true), to: place(tunnel: true)), "not again inside it")
        XCTAssertFalse(TrainHorn.blowsByItself(from: place(tunnel: true), to: place()), "nor out of it")
        XCTAssertFalse(TrainHorn.blowsByItself(from: place(other), to: place(nearing: stop, tunnel: true)), "not for another train just followed")
    }

    /// Surface track to a portal at 192 m, then a tunnel (as
    /// `Map3DTunnelTests`): the head is in the tunnel past the portal.
    func testTheHeadIsInATunnelPastThePortal() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 16_384))
        let down = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 16_384, z: -256))
        let open = try world.buildTrackEdge(from: a, to: portal)
        let tunnel = try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        let train = try world.purchaseTrain(named: "Mole").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: open, direction: .forward), offset: 5_000))
        XCTAssertEqual(world.hornPlace(of: train)?.inTunnel, false)
        XCTAssertNil(world.hornPlace(of: train)?.nearing, "no timetable, no stop")
        var inside = world
        try inside.unplaceTrain(train)
        try inside.placeTrain(train, at: .onEdge(TrackTraversal(edge: tunnel, direction: .forward), offset: 2_000))
        XCTAssertEqual(inside.hornPlace(of: train)?.inTunnel, true)
        try inside.unplaceTrain(train)
        try inside.placeTrain(train, at: .onEdge(TrackTraversal(edge: tunnel, direction: .backward), offset: 2_000))
        XCTAssertEqual(inside.hornPlace(of: train)?.inTunnel, true, "either way along it")
        XCTAssertNil(world.hornPlace(of: TrainID(rawValue: 99)))
    }

    /// Station A, 1 km east, a quarter circle, 1 km north, station B, one
    /// standard train on the line A–B (as `Map3DDriverHUDTests`); run at
    /// 60× until it is 1.1 to 1.6 km from B.
    @MainActor
    private func session(speed: GameSpeed) throws -> (GameSession, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let r: Int64 = 300 * 64, k = r * 5523 / 10_000, x: Int64 = 8_192, y: Int64 = 8_192
        let points = [
            WorldCoordinate(x: x, y: y), WorldCoordinate(x: x + 4_096, y: y), WorldCoordinate(x: x + 68_096, y: y),
            WorldCoordinate(x: x + 68_096 + r, y: y + r), WorldCoordinate(x: x + 68_096 + r, y: y + r + 64_000),
            WorldCoordinate(x: x + 68_096 + r, y: y + r + 68_096),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        _ = try world.buildTrackEdge(from: nodes[2], to: nodes[3], curve: .cubic(
            PlanPoint(x: points[2].x + k, y: points[2].y), PlanPoint(x: points[3].x, y: points[3].y - k)))
        _ = try world.buildTrackEdge(from: nodes[3], to: nodes[4])
        let last = try world.buildTrackEdge(from: nodes[4], to: nodes[5])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + 2_048, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: points[4].x + 512, y: points[4].y + 2_048)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Main", stops: [a, b])
        let line = LineID(rawValue: 1)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setRealisticOperation(true)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        world.setSpeed(.x60)
        for _ in 0..<1_000 {
            try world.advance(ticks: 1)
            if let left = world.map3DDriverHUD(of: train, in: .english)?.metresToNext, world.map3DDriverHUD(of: train, in: .english)?.place == .next("B"),
               (1_100...1_600).contains(left) { break }
        }
        XCTAssertGreaterThan(try XCTUnwrap(world.map3DDriverHUD(of: train, in: .english)?.metresToNext), 1_000)
        world.setSpeed(speed)
        return (GameSession(world: world), train)
    }

    /// Runs `session` until the train stands at B; the horns heard.
    @MainActor
    private func horns(_ session: GameSession, train: TrainID) -> [SoundCue] {
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        for _ in 0..<5_000 {
            session.advance(ticks: 1)
            if case .waitingAtStop(1, _)? = session.world.train(id: train)?.execution { break }
        }
        XCTAssertEqual(session.world.map3DDriverHUD(of: train, in: .english)?.place, .at("B"), "it reached B")
        return heard.filter { if case .horn = $0 { true } else { false } }
    }

    @MainActor
    func testFollowedOnThe3DMapAt1xItBlowsOnceNearingTheStop() throws {
        let (session, train) = try session(speed: .x1)
        session.followTrain(train)
        session.setMap3DOpen(true)
        XCTAssertEqual(horns(session, train: train), [.horn(.electric)])
    }

    @MainActor
    func testItDoesNotBlowByItselfFasterOffThe3DMapOrUnfollowed() throws {
        let (fast, train) = try session(speed: .x10)
        fast.followTrain(train)
        fast.setMap3DOpen(true)
        XCTAssertEqual(horns(fast, train: train), [], "at 10× stops come too often")
        let (flat, same) = try session(speed: .x1)
        flat.followTrain(same)
        XCTAssertEqual(horns(flat, train: same), [], "on the 2D map")
        let (alone, train3) = try session(speed: .x1)
        alone.setMap3DOpen(true)
        XCTAssertEqual(horns(alone, train: train3), [], "no train followed")
    }

    @MainActor
    func testTheButtonBlowsTheFollowedTrainsHorn() throws {
        let (session, train) = try session(speed: .x1)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.soundHorn()
        XCTAssertEqual(heard, [], "nothing followed, nothing blown")
        session.followTrain(train)
        session.soundHorn()
        XCTAssertEqual(heard, [.horn(.electric)])
    }
}
