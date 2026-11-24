@testable import GamePresentation
import GameCore
import XCTest

/// Decision 964: the kinds of ordinary track, from the trains run on it.
final class Map3DTrackKindsTests: XCTestCase {
    private struct Laid {
        var world: GameWorld
        let edge: TrackEdgeID
        let line: LineID
        let stations: [StationID]
    }

    /// A 15 km straight with two stations and a line between them, a
    /// train of `type` on it (as ``Map3DGuidewayTests``').
    private func laid(_ type: TrainType?) throws -> Laid {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 14_336, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 10_240, to: 14_336)
        let line = try world.createLine(named: "Line", stops: [west, east]).id
        let train = if let type { try world.purchaseTrain(named: "One", as: type) } else { try world.purchaseTrain(named: "One") }
        try world.assignTrain(train.id, to: line)
        return Laid(world: world, edge: edge, line: line, stations: [west, east])
    }

    private func built(_ world: GameWorld, platforms: Bool = true) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        if platforms { builder.addPlatforms(snapshot) }
        return builder
    }

    private func colours(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Set<UInt32> {
        Set(meshes.values.flatMap { $0.vertices.map(\.color) })
    }

    /// Every type has a kind, and the split is the depot shed's: the
    /// people mover's pads, the light metro's embedded track, the other
    /// metros' third rail, the high-speed set's slab, ballast for the
    /// rest; the guideway trains' ordinary kind is ballast (their track
    /// is their beam, decision 951).
    func testEachTypesKind() {
        XCTAssertEqual(Map3DTrackKind(nil), .ballast)
        XCTAssertEqual(Map3DTrackKind(.apm), .rubber)
        XCTAssertEqual(Map3DTrackKind(.c), .embedded)
        for type in [TrainType.a, .b, .d, .l, .c381] { XCTAssertEqual(Map3DTrackKind(type), .thirdRail, type.rawValue) }
        XCTAssertEqual(Map3DTrackKind(.highSpeed), .slab)
        for type in [TrainType.emu3000, .steam, .alishan, .dr1000, .monorail, .maglev, .skyRail] {
            XCTAssertEqual(Map3DTrackKind(type), .ballast, type.rawValue)
        }
        for type in TrainType.allCases where type.spec.family == .railway { XCTAssertEqual(Map3DTrackKind(type), .ballast, type.rawValue) }
        XCTAssertEqual(Map3DTrackKind.allCases.filter(\.hasOverheadLine), [.ballast, .slab, .embedded])
        XCTAssertEqual(Map3DTrackKind.allCases.filter { !$0.hasRails }, [.rubber])
    }

    func testALinesTrackIsItsTrainsKind() throws {
        for (type, kind) in [(TrainType.a, Map3DTrackKind.thirdRail), (.apm, .rubber), (.c, .embedded), (.highSpeed, .slab)] {
            let laid = try laid(type)
            XCTAssertEqual(Map3DTrackKind.edges(in: laid.world), [laid.edge: kind], "\(kind)")
        }
        XCTAssertEqual(Map3DTrackKind.edges(in: try laid(.emu3000).world), [:])
        XCTAssertEqual(Map3DTrackKind.edges(in: try laid(nil).world), [:])
    }

    /// Trains of two kinds on a line, or another line of another kind on
    /// the same track, leave it ballast; a line with no trains says
    /// nothing; two lines of one kind keep it.
    func testSharedTrackStaysBallast() throws {
        var mixed = try laid(.a)
        try mixed.world.assignTrain(try mixed.world.purchaseTrain(named: "Two", as: .emu3000).id, to: mixed.line)
        XCTAssertEqual(Map3DTrackKind.edges(in: mixed.world), [:])

        var shared = try laid(.apm)
        let other = try shared.world.createLine(named: "Other", stops: shared.stations).id
        XCTAssertEqual(Map3DTrackKind.edges(in: shared.world), [shared.edge: .rubber], "a line with no trains")
        let two = try shared.world.purchaseTrain(named: "Two", as: .apm).id
        try shared.world.assignTrain(two, to: other)
        XCTAssertEqual(Map3DTrackKind.edges(in: shared.world), [shared.edge: .rubber], "two lines of one kind")
        try shared.world.unassignTrain(two)
        try shared.world.assignTrain(try shared.world.purchaseTrain(named: "Three").id, to: other)
        XCTAssertEqual(Map3DTrackKind.edges(in: shared.world), [:], "a line of ballast trains")
    }

    /// Ballast track is drawn as it was; the others have no ballast, a
    /// concrete bed, and their own parts close up.
    func testEachKindIsDrawn() throws {
        let rail = built(try laid(.emu3000).world)
        XCTAssertTrue(colours(rail.meshes).contains(Map3DPalette.ballast))
        XCTAssertTrue(colours(rail.meshes).contains(Map3DPalette.railTop))
        XCTAssertTrue(rail.guidedTrackLines.isEmpty)
        XCTAssertEqual(colours(rail.nearMeshes).intersection([Map3DTrackKind.slabColour, Map3DTrackKind.cover, Map3DTrackKind.lawn]), [])

        for kind in [Map3DTrackKind.slab, .thirdRail, .rubber, .embedded] {
            let type: TrainType = switch kind {
            case .slab: .highSpeed
            case .thirdRail: .a
            case .rubber: .apm
            default: .c
            }
            let builder = built(try laid(type).world)
            let base = colours(builder.meshes), near = colours(builder.nearMeshes)
            XCTAssertFalse(base.contains(Map3DPalette.ballast), "\(kind)")
            XCTAssertEqual(base.contains(Map3DPalette.railTop), kind.hasRails, "\(kind)")
            XCTAssertEqual(base.contains(Map3DTrackKind.padColour), kind == .rubber, "\(kind)")
            XCTAssertEqual(base.contains(Map3DTrackKind.lawn), kind == .embedded, "\(kind)")
            XCTAssertEqual(near.contains(Map3DTrackKind.slabColour), kind != .embedded, "\(kind)")
            XCTAssertEqual(near.contains(Map3DTrackKind.cover), kind == .thirdRail, "\(kind)")
            XCTAssertEqual(near.contains(Map3DTrackKind.insulator), kind == .thirdRail || kind == .rubber, "\(kind)")
            // No overhead line over a third rail or the pads.
            XCTAssertEqual(builder.guidedTrackLines.isEmpty, kind.hasOverheadLine, "\(kind)")
            // Nothing of the track stands over the rails' top but the
            // third rail's cover and the guide bars, both under a car's
            // floor and inside a platform's edge.
            let top = try XCTUnwrap(builder.trackLines.first?.points.first).y
            let track = built(try laid(type).world, platforms: false)
            let highest = (Array(track.meshes.values) + Array(track.nearMeshes.values)).flatMap(\.vertices).map(\.y).max() ?? 0
            let over: Float = kind == .thirdRail ? Map3DTrackKind.coverTop : kind == .rubber ? Map3DTrackKind.guideTop : 0
            XCTAssertEqual(highest, top + over, accuracy: 0.01, "\(kind)")
        }
        XCTAssertLessThan(Map3DTrackKind.thirdRailOffset + Map3DTrackKind.coverWidth / 2, 1.6)
        XCTAssertLessThan(Map3DTrackKind.guideOffset + 0.13, 1.6)
        XCTAssertGreaterThan(Map3DTrackKind.guideOffset, 2.06 / 2 + 0.1)
    }

    /// On a viaduct and in a tunnel: no lawn (the embedded track is paved
    /// there), no ballast in a tunnel, and a metro's or a light rail's
    /// viaduct is a metro's.
    func testOnAViaductAndInATunnel() {
        XCTAssertEqual(Map3DTrackKind.allCases.filter(\.ridesMetroViaduct), [.thirdRail, .rubber, .embedded])
        let world = GameWorld.newGame()
        for kind in [TrackSectionKind.viaduct, .tunnel] {
            for track in [Map3DTrackKind.thirdRail, .rubber, .embedded] {
                var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
                let line = stride(from: Float(0), through: 240, by: 16).map { Map3DPoint($0, kind == .tunnel ? -12 : 12, 100) }
                builder.addTrackPiece(line, kind: kind, viaduct: .metro, track: track)
                builder.addViaducts()
                let base = colours(builder.meshes), all = base.union(colours(builder.nearMeshes))
                XCTAssertEqual(all.contains(Map3DTrackKind.paving), track == .embedded, "\(kind) \(track)")
                XCTAssertFalse(all.contains(Map3DTrackKind.lawn), "\(kind) \(track)")
                XCTAssertEqual(base.contains(Map3DTrackKind.padColour), track == .rubber, "\(kind) \(track)")
                if kind == .tunnel { XCTAssertFalse(base.contains(Map3DPalette.ballast), "\(track)") }
            }
        }
    }

    /// The posts stand every `spacing` metres, half a spacing in.
    func testThePosts() {
        var mesh = Map3DMesh()
        Map3DTrackKind.addPosts(along: [Map3DPoint(0, 1, 0), Map3DPoint(20, 1, 0)], every: 5, offset: 1, across: 0.1, bottom: -0.35, top: 0.2,
                                colour: Map3DTrackKind.insulator, into: &mesh)
        let xs = Set(mesh.vertices.map { ($0.x / 5).rounded(.down) })
        XCTAssertEqual(xs, [0, 1, 2, 3])
        XCTAssertEqual(mesh.vertices.map(\.y).max() ?? 0, 1.2, accuracy: 0.001)
        XCTAssertEqual(mesh.vertices.map(\.y).min() ?? 0, 0.65, accuracy: 0.001)
    }

    /// The scene key's signature: empty while every train runs on
    /// ballast, and changed by a train of another kind coming or going.
    func testTheSignature() throws {
        var laid = try laid(.emu3000)
        let plain = Map3DTrackKindSignature(world: laid.world)
        XCTAssertEqual(plain, Map3DTrackKindSignature(world: try self.laid(nil).world))
        let metro = try laid.world.purchaseTrain(named: "Two", as: .a).id
        XCTAssertEqual(Map3DTrackKindSignature(world: laid.world), plain, "a train on no line")
        try laid.world.assignTrain(metro, to: laid.line)
        let mixed = Map3DTrackKindSignature(world: laid.world)
        XCTAssertNotEqual(mixed, plain)
        try laid.world.unassignTrain(try XCTUnwrap(laid.world.trains.first { $0.name == "One" }).id)
        XCTAssertNotEqual(Map3DTrackKindSignature(world: laid.world), mixed)
        XCTAssertNotEqual(Map3DTrackKindSignature(world: laid.world), plain)
        XCTAssertEqual(Map3DTrackKindSignature(world: laid.world), Map3DTrackKindSignature(world: try self.laid(.a).world))
    }
}
