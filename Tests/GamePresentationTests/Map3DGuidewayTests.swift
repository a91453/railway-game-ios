@testable import GamePresentation
import GameCore
import XCTest

/// Decision 947: the guideway trains' lines drawn on their beams.
final class Map3DGuidewayTests: XCTestCase {
    private struct Laid {
        var world: GameWorld
        let edge: TrackEdgeID
        let line: LineID
        let stations: [StationID]
    }

    /// A 15 km straight with two stations and a line between them, its
    /// train of `type` on the track that type runs on (decision 951).
    private func laid(_ type: TrainType) throws -> Laid {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b, system: type.trackSystem)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 14_336, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 10_240, to: 14_336)
        let line = try world.createLine(named: "Line", stops: [west, east]).id
        let train = try world.purchaseTrain(named: "One", as: type).id
        try world.assignTrain(train, to: line)
        return Laid(world: world, edge: edge, line: line, stations: [west, east])
    }

    private func built(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        return builder
    }

    private func colours(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Set<UInt32> {
        Set(meshes.values.flatMap { $0.vertices.map(\.color) })
    }

    func testEachGuidewayTrainsLineIsItsGuideway() throws {
        for (type, kind) in [(TrainType.monorail, Map3DGuideway.Kind.straddle), (.maglev, .maglev), (.skyRail, .suspended)] {
            let laid = try laid(type)
            XCTAssertEqual(Map3DGuideway.edges(in: laid.world), [laid.edge: kind], "\(kind)")
        }
        XCTAssertEqual(Map3DGuideway.edges(in: try laid(.c).world), [:])
    }

    /// `world` as a save from before decision 951 wrote it, its trains
    /// named in `types` made those types: any train ran on any track then.
    private func old(_ world: GameWorld, retyping types: [String: TrainType]) throws -> GameWorld {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        for index in trains.indices {
            guard let name = trains[index]["name"] as? String, let type = types[name] else { continue }
            trains[index]["type"] = type.rawValue
        }
        object["trains"] = trains
        let data = try JSONSerialization.data(withJSONObject: ["saveVersion": 111, "world": object])
        return try JSONDecoder().decode(SavedGame.self, from: data).world
    }

    /// In a save from before decision 951, a line of guideway trains and
    /// another type, or another line of ordinary trains on the same
    /// track, keep it ordinary track.
    func testSharedTrackStaysOrdinaryTrack() throws {
        var mixed = try laid(.c)
        try mixed.world.assignTrain(try mixed.world.purchaseTrain(named: "Two", as: .c).id, to: mixed.line)
        XCTAssertEqual(Map3DGuideway.edges(in: try old(mixed.world, retyping: ["One": .monorail])), [:])

        var shared = try laid(.c)
        let other = try shared.world.createLine(named: "Other", stops: shared.stations).id
        try shared.world.assignTrain(try shared.world.purchaseTrain(named: "Two", as: .c).id, to: other)
        XCTAssertEqual(Map3DGuideway.edges(in: try old(shared.world, retyping: ["One": .monorail])), [:])
        XCTAssertEqual(Map3DGuideway.edges(in: try old(shared.world, retyping: ["One": .monorail, "Two": .maglev])), [:])

        // The whole line's trains of one kind: its guideway, as the save's
        // track itself now is.
        let whole = try old(mixed.world, retyping: ["One": .monorail, "Two": .monorail])
        XCTAssertEqual(Map3DGuideway.edges(in: whole), [mixed.edge: .straddle])
        XCTAssertEqual(whole.network.edge(mixed.edge)?.system, .straddle)

        // A line with no trains runs on nothing.
        var idle = try laid(.monorail)
        _ = try idle.world.createLine(named: "Idle", stops: idle.stations)
        XCTAssertEqual(Map3DGuideway.edges(in: idle.world), [idle.edge: .straddle])
    }

    /// No rails, sleepers or ballast, and no overhead line, but the beam
    /// at the running surface, its supports on the ground.
    func testTheGuidewayIsDrawnInPlaceOfTheTrack() throws {
        let rail = built(try laid(.c).world)
        XCTAssertTrue(colours(rail.meshes).contains(Map3DPalette.railTop))
        for type in [TrainType.monorail, .maglev, .skyRail] {
            let builder = built(try laid(type).world)
            let kind = try XCTUnwrap(Map3DGuideway.Kind(type))
            let base = colours(builder.meshes)
            XCTAssertFalse(base.contains(Map3DPalette.railTop), "\(kind)")
            XCTAssertFalse(base.contains(Map3DPalette.ballast), "\(kind)")
            XCTAssertTrue(base.contains(kind.body[0].colour), "\(kind)")
            XCTAssertTrue(colours(builder.nearMeshes).contains(Map3DGuideway.dark), "\(kind)")
            XCTAssertEqual(builder.guidedTrackLines, Set(builder.trackLines.indices), "\(kind)")
            // The beam's top where the trains' z 0 is drawn (the
            // suspended beam's portal frames' crossbars on it).
            let track = try XCTUnwrap(builder.trackLines.first?.points.first).y
            let top = builder.meshes.values.flatMap(\.vertices).filter { $0.color == kind.body[0].colour }.map(\.y).max()
            let bar = kind == .suspended ? Map3DGuideway.portalBar : 0
            XCTAssertEqual(try XCTUnwrap(top), track + kind.runningSurface + (kind.body.map(\.top).max() ?? 0) + bar, accuracy: 0.01, "\(kind)")
        }
    }

    /// Each platform level with its cars' doors: its line raised so what
    /// stands ``Map3DScene/Builder/platformHeight`` over it stands on it.
    func testThePlatformsAreLevelWithTheDoors() throws {
        let rail = built(try laid(.c).world)
        let railTrack = try XCTUnwrap(rail.trackLines.first?.points.first).y
        XCTAssertEqual(try XCTUnwrap(rail.laidPlatforms.first?.line.first).y, railTrack, accuracy: 0.01)
        for type in [TrainType.monorail, .maglev, .skyRail] {
            let builder = built(try laid(type).world)
            let kind = try XCTUnwrap(Map3DGuideway.Kind(type))
            let track = try XCTUnwrap(builder.trackLines.first?.points.first).y
            XCTAssertEqual(builder.laidPlatforms.count, 2, "\(kind)")
            for platform in builder.laidPlatforms {
                XCTAssertEqual(try XCTUnwrap(platform.line.first).y + Map3DScene.Builder.platformHeight, track + kind.platformTop, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(abs(platform.offset) - platform.width / 2, kind.platformEdge - 0.01, "\(kind)")
            }
        }
    }

    /// The cars as the studio made them about the samples: the straddle
    /// car's and the maglev's skirts end at the rails' height and wrap
    /// their beam (whose underside is lower); the suspended car's floor
    /// is at the rails' height, its bogies inside its box beam.
    func testTheCarsRideTheirBeams() throws {
        for kind in Map3DGuideway.Kind.allCases {
            let models: [Map3DModelPack.Model?] = switch kind {
            case .straddle: [Map3DGuidedMonorail.model(cab: true), Map3DGuidedMonorail.model(cab: false)]
            case .maglev: [Map3DGuidedMaglev.model(cab: true), Map3DGuidedMaglev.model(cab: false)]
            case .suspended: [Map3DGuidedSkyrail.model(cab: true), Map3DGuidedSkyrail.model(cab: false)]
            }
            let bottom = kind.body.map(\.bottom).min()!, top = kind.body.map(\.top).max()!
            for (number, model) in models.enumerated() {
                let model = try XCTUnwrap(model)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.06, "\(kind)")
                // The middle car's door frames' bottoms (the dark frames on
                // its sides; a cab's dark face reaches lower) where the
                // platforms stand.
                if number == 1 {
                    let frames = model.vertices.filter { $0.color == Map3DMTRUrbanLine.meshPalette[5] && abs($0.y) > 1 }.map(\.z)
                    XCTAssertEqual(try XCTUnwrap(frames.min()), kind.platformTop, accuracy: 0.02, "\(kind)")
                }
                switch kind {
                case .straddle, .maglev:
                    XCTAssertLessThan(kind.runningSurface + bottom, model.minimum.z, "\(kind)")
                case .suspended:
                    XCTAssertLessThan(model.maximum.z, kind.runningSurface + top, "\(kind)")
                }
            }
        }
        XCTAssertEqual(Map3DGuidedMonorail.lift, Map3DGuideway.Kind.straddle.runningSurface)
        XCTAssertEqual(Map3DGuidedMaglev.lift, Map3DGuideway.Kind.maglev.runningSurface)
        XCTAssertEqual(Map3DGuidedSkyrail.lift, Map3DGuideway.Kind.suspended.runningSurface)
    }

    /// The suspended beam's portal frames stand clear of its car and not
    /// on its platforms; the others' piers stand only where the beam is
    /// off the ground.
    func testTheSupports() throws {
        XCTAssertGreaterThan(Map3DGuideway.portalHalfSpan - Map3DGuideway.portalLeg / 2, 2.6 / 2 + 0.3)
        XCTAssertEqual(Map3DGuideway.supports(of: .straddle, length: 100), [10, 30, 50, 70, 90])
        XCTAssertEqual(Map3DGuideway.supports(of: .maglev, length: 5), [2.5])
        var mesh = Map3DMesh()
        Map3DGuideway.addSupport(.straddle, at: Map3DPoint(0, 0.85, 0), along: Map3DPoint(1, 0, 0), ground: 0.5, into: &mesh)
        XCTAssertTrue(mesh.vertices.isEmpty)
        Map3DGuideway.addSupport(.straddle, at: Map3DPoint(0, 8, 0), along: Map3DPoint(1, 0, 0), ground: 0, into: &mesh)
        XCTAssertEqual(mesh.vertices.map(\.y).max() ?? 0, 8 + 1.3 - 1.5, accuracy: 0.001)
        // Along its platforms, none.
        let builder = built(try laid(.skyRail).world)
        let legs = builder.meshes.values.flatMap(\.vertices).filter { $0.color == Map3DGuideway.steel || $0.color == Map3DColor.shaded(Map3DGuideway.steel, 0.92) }
        XCTAssertFalse(legs.isEmpty)
        for platform in try XCTUnwrap(builder.guidewayEdges?.hung) {
            let middle = platform[platform.count / 2]
            XCTAssertFalse(legs.contains { abs($0.x - middle.x) < 1 && abs($0.z - middle.z) < 3 && $0.y < middle.y })
        }
    }

    /// The scene key's signature changes when a line takes a guideway
    /// train, and not when an ordinary line does.
    func testTheSignature() throws {
        var laid = try laid(.monorail)
        try laid.world.unassignTrain(try XCTUnwrap(laid.world.trains.first).id)
        let before = Map3DGuidewaySignature(world: laid.world)
        XCTAssertEqual(before, Map3DGuidewaySignature(world: try self.laid(.c).world))
        try laid.world.assignTrain(try laid.world.purchaseTrain(named: "Two", as: .monorail).id, to: laid.line)
        XCTAssertNotEqual(Map3DGuidewaySignature(world: laid.world), before)
    }
}
