import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 441: a depot's maintenance shed beside its sidings, and the
/// Changhua Roundhouse's turntable, from the private reference's Railway
/// Facilities Pack 01 laid again as native recipes.
@MainActor
final class Map3DDepotFacilitiesTests: XCTestCase {
    private func triangles(_ mesh: Map3DMesh) -> Int { mesh.indices.count / 3 }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + triangles($1) }
    }

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    /// The shed is the pack's 408 triangles, 36 m long (its roof 0.35 m
    /// over each end), 16 m wide and 9 m to its ridge (its vent on top);
    /// the turntable's pit 13 m round, its bridge 24 m. Far off, a box
    /// each, and the turntable's pit.
    func testTheModels() throws {
        XCTAssertEqual(triangles(Map3DDepotFacilities.shed), 408)
        let shed = try XCTUnwrap(Map3DDepotFacilities.shed.bounds)
        XCTAssertEqual(shed.min.x, -18.35, accuracy: 0.01)
        XCTAssertEqual(shed.max.x, 18.35, accuracy: 0.01)
        XCTAssertEqual(shed.max.z - shed.min.z, 16, accuracy: 0.6)
        XCTAssertEqual(shed.min.y, 0, accuracy: 0.001)
        XCTAssertEqual(shed.max.y, 9.28, accuracy: 0.05)
        XCTAssertEqual(triangles(Map3DDepotFacilities.turntable), 860)
        let turntable = try XCTUnwrap(Map3DDepotFacilities.turntable.bounds)
        XCTAssertEqual(turntable.max.x, 13, accuracy: 0.01)
        XCTAssertEqual(turntable.min.z, -13, accuracy: 0.05)
        XCTAssertEqual(turntable.min.y, 0, accuracy: 0.001)
        XCTAssertEqual(turntable.max.y, 2.48, accuracy: 0.01)
        XCTAssertEqual(triangles(Map3DDepotFacilities.shedFar), 10)
        XCTAssertEqual(triangles(Map3DDepotFacilities.turntableFar), 22)
        // Every face lit from outside: no normal pointing into the floor.
        for mesh in [Map3DDepotFacilities.shed, Map3DDepotFacilities.turntable] {
            for vertex in mesh.vertices {
                let length = (vertex.nx * vertex.nx + vertex.ny * vertex.ny + vertex.nz * vertex.nz).squareRoot()
                XCTAssertEqual(length, 1, accuracy: 0.01)
            }
        }
    }

    /// The bays open towards the end more track runs on from.
    func testTheBaysFaceTheThroat() {
        XCTAssertEqual(Map3DDepotFacilities.baysFacing(beyondStart: 12, beyondEnd: 0), -1)
        XCTAssertEqual(Map3DDepotFacilities.baysFacing(beyondStart: 0, beyondEnd: 5), 1)
        XCTAssertEqual(Map3DDepotFacilities.baysFacing(beyondStart: 3, beyondEnd: 3), -1)
    }

    /// The depot tool's yard at the east end of a line (DepotToolsTests'):
    /// its depot has the shed, not a station building, beside its
    /// sidings, clear of their track, its bays west towards the line; no
    /// stop boards or bins on its platforms. As a plain station, it has
    /// its building and they again.
    func testADepotHasItsShed() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.tapNetwork(at: PlanPoint(x: 16_400, y: 8_200), reach: 64)
        session.addDepotYard()
        let withDepot = session.world
        let depot = try XCTUnwrap(withDepot.stations.first(where: \.isDepot))
        var plain = withDepot
        try plain.setStationDepot(depot.id, to: false)

        func built(_ world: GameWorld) -> Map3DScene.Builder {
            var builder = builder(world)
            let snapshot = world.railwaySnapshot()
            builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            _ = builder.addStations(snapshot, frame: nil)
            builder.addPlatformProps()
            return builder
        }
        let shed = built(withDepot), house = built(plain)
        XCTAssertEqual(shed.houseFootprints.count, 2)
        XCTAssertEqual(house.houseFootprints.count, 2)
        // Decision 785: the depot yard kit's shed, as many 12 m bays along
        // the sidings (east–west) as fit them, two tracks wide.
        let corners = try XCTUnwrap(shed.houseFootprints.last)
        let along = corners[0] - corners[3], across = corners[1] - corners[0]
        let sidings = try XCTUnwrap(withDepot.railwaySnapshot().platforms.filter { $0.platform.station == depot.id }
            .compactMap { Map3DStreetLife.Path($0.points.map { shed.point($0) })?.length }.max())
        let bays = Map3DDepotYardKit.bays(forSiding: sidings)
        XCTAssertGreaterThanOrEqual(bays, 3)
        XCTAssertEqual(along.length, Float(bays) * 12, accuracy: 0.01)
        XCTAssertLessThanOrEqual(along.length, sidings + 0.01)
        XCTAssertEqual(across.length, Map3DDepotYardKit.part(.shedHead, system: .taiwanRail, tracks: 2).width, accuracy: 0.01)
        // Its bays (the footprint's front) to the west, towards the line.
        XCTAssertLessThan(try XCTUnwrap(along.normalized).x, -0.99)
        // No track within it.
        let middle = corners.reduce(Map3DPoint.zero) { $0 + $1 } * 0.25
        let inside = shed.trackLines.flatMap(\.points).filter { p in
            let d = p - middle
            return abs(d.dot(along.normalized!)) < along.length / 2 - 1 && abs(d.dot(across.normalized!)) < across.length / 2 - 1
        }
        XCTAssertTrue(inside.isEmpty, "\(inside.prefix(3))")
        XCTAssertNotEqual(house.houseFootprints.last, corners)
        // Close up, only West's platform things at the depot's world.
        XCTAssertLessThan(triangles(shed.closeMeshes), triangles(house.closeMeshes))
    }

    /// Decision 785: the shed's system is tall enough for every train its
    /// lines keep there; its bays fit the sidings, 3 to 27.
    func testTheShedFitsItsTrainsAndSidings() {
        XCTAssertEqual(Map3DDepotFacilities.system(for: []), .taiwanRail)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [.apm, .apm]), .wenhu)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [.apm, .c]), .lightRail)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [.a, .apm]), .metro)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [.a, .c]), .lightRail)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [.a, TrainType(rawValue: "HSR")]), .taiwanRail)
        XCTAssertEqual(Map3DDepotFacilities.system(for: [nil]), .taiwanRail)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: 10), 3)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: 150), 12)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: 2_000), Map3DDepotYardKit.maxBays)
        // REVIEW-L23 P3-3: a length that is not a number, or too long for
        // an Int, is counted, not trapped on.
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: .nan), 3)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: .infinity), Map3DDepotYardKit.maxBays)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: -.infinity), 3)
        XCTAssertEqual(Map3DDepotYardKit.bays(forSiding: .greatestFiniteMagnitude), Map3DDepotYardKit.maxBays)
        // The longest shed stays within an app model's 15,000 triangles.
        for system in Map3DDepotYardKit.System.allCases {
            let near = Map3DDepotYardKit.shedMesh(system: system, tracks: 4, bays: Map3DDepotYardKit.maxBays)
            XCTAssertLessThan(triangles(near), 15_000, system.rawValue)
            let bounds = near.bounds!
            XCTAssertEqual(bounds.max.x - bounds.min.x, Float(Map3DDepotYardKit.maxBays) * 12 + 0.7, accuracy: 0.05)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 0.001)
            XCTAssertEqual(triangles(Map3DDepotYardKit.shedFarMesh(system: system, tracks: 4, bays: 5)), 10)
        }
    }

    /// A new game round the Changhua Roundhouse has its turntable where
    /// it stands, its bridge towards the roundhouse; in full close by, its
    /// pit and a box far off. None in Taipei, on a map of nowhere, or
    /// where the player's track runs.
    func testTheRoundhouseTurntable() throws {
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 24.0857, longitudeDegrees: 120.5401)!)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let cells = builder.addRoundhouseTurntable(frame: frame)
        XCTAssertFalse(cells.isEmpty)
        XCTAssertEqual(triangles(builder.nearMeshes), triangles(Map3DDepotFacilities.turntable))
        XCTAssertEqual(triangles(builder.farMeshes), triangles(Map3DDepotFacilities.turntableFar))
        let place = Map3DDepotFacilities.turntablePlace, house = Map3DDepotFacilities.roundhouse
        let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let centre = builder.point(x: at.x, y: at.y, height: 0)
        let bounds = try XCTUnwrap(builder.nearMeshes.values.first?.bounds)
        XCTAssertEqual((bounds.min.x + bounds.max.x) / 2, centre.x, accuracy: 0.5)
        XCTAssertEqual((bounds.min.z + bounds.max.z) / 2, centre.z, accuracy: 0.5)
        // 22.9 m from the roundhouse's middle (5.3 m east, 22.3 m south).
        let toward = frame.worldPosition(latitude: house.latitude, longitude: house.longitude)
        let middle = builder.point(x: toward.x, y: toward.y, height: 0)
        XCTAssertEqual((middle - centre).length, 22.9, accuracy: 0.5)
        // The bridge's yellow plates lie along the line to the roundhouse.
        let way = try XCTUnwrap((middle - centre).normalized)
        let plates = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.platformEdge }
        XCTAssertFalse(plates.isEmpty)
        for plate in plates {
            let d = plate.position - centre
            XCTAssertGreaterThan(abs(Map3DPoint(d.x, 0, d.z).dot(way)), 11.5)
        }

        var blocked = self.builder(world)
        blocked.trackLines = [(stride(from: Float(-200), through: 200, by: 2).map { centre + Map3DPoint($0, 0, 3) }, .surface)]
        XCTAssertTrue(blocked.addRoundhouseTurntable(frame: frame).isEmpty)
        XCTAssertTrue(blocked.nearMeshes.isEmpty)

        let taipei = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        var far = self.builder(taipei)
        XCTAssertTrue(far.addRoundhouseTurntable(frame: try XCTUnwrap(RealWorldFrame(world: taipei))).isEmpty)
        XCTAssertNil(RealWorldFrame(world: GameWorld.newGame()))
    }

    /// The triangles each adds: printed for the decision.
    func testTheTriangleReport() {
        let kit = Map3DDepotYardKit.System.allCases.map { "\($0.rawValue) \(triangles(Map3DDepotYardKit.shedMesh(system: $0, tracks: 2, bays: 3)))–\(triangles(Map3DDepotYardKit.shedMesh(system: $0, tracks: 4, bays: Map3DDepotYardKit.maxBays)))" }
        print("depot yard shed near \(kit.joined(separator: ", "));",
              "turntable near \(triangles(Map3DDepotFacilities.turntable)), far \(triangles(Map3DDepotFacilities.turntableFar))")
    }
}
