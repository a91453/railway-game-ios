import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 436: the platforms' small things close up and the
/// cab cars' destination signs.
final class Map3DPlatformPropsTests: XCTestCase {
    private typealias Props = Map3DPlatformProps
    private typealias Builder = Map3DScene.Builder

    private func formation(_ cars: Int, _ carLength: Float = 20, doors: Int = 2) -> Props.Formation {
        Props.Formation(cars: cars, carLength: carLength, doors: doors)
    }

    // MARK: Where the boards stand

    func testEachLengthOfTrainStopsInThePlatformsMiddleItsHeadHalfItsLengthPast() {
        // 200 m: the 12-car train (240 m) does not fit; the 4-car is
        // there twice, marked once.
        let marks = Props.stopMarks(length: 200, formations: [formation(8), formation(12), formation(4), formation(10), formation(4)],
                                    kind: .railway)
        XCTAssertEqual(marks.map(\.cars).sorted(), [4, 4, 8, 8, 10, 10])
        XCTAssertEqual(marks.filter { $0.heading > 0 }.map { [$0.cars: $0.along] }, [[4: 140], [8: 180], [10: 200]])
        XCTAssertEqual(marks.filter { $0.heading < 0 }.map { [$0.cars: $0.along] }, [[10: 0], [8: 20], [4: 60]])
    }

    func testWithNoTrainCallingARailwayPlatformMarksTaiwanRailwaysUsualLengths() {
        let marks = Props.stopMarks(length: 245, formations: [], kind: .railway)
        XCTAssertEqual(Set(marks.map(\.cars)), [4, 8, 10, 12])
        // A short platform only what fits.
        XCTAssertEqual(Set(Props.stopMarks(length: 100, formations: [], kind: .railway).map(\.cars)), [4])
        XCTAssertTrue(Props.stopMarks(length: 60, formations: [], kind: .railway).isEmpty)
    }

    func testAtMostFourLengthsTheLongest() {
        let marks = Props.stopMarks(length: 400, formations: (1...12).map { formation($0) }, kind: .railway)
        XCTAssertEqual(Set(marks.map(\.cars)), [9, 10, 11, 12])
    }

    func testAMetroPlatformMarksItsLongestTrainAndEachOfItsDoors() {
        let six = formation(6, 22, doors: 4), four = formation(4, 22, doors: 4)
        let marks = Props.stopMarks(length: 150, formations: [four, six], kind: .metro)
        XCTAssertEqual(marks.map(\.cars), [6, 6])
        XCTAssertEqual(marks.map(\.along), [9, 141])
        let doors = Props.doorCentres(length: 150, formations: [four, six], kind: .metro)
        XCTAssertEqual(doors.count, 24)
        XCTAssertEqual(doors.first ?? 0, 9 + 2.75, accuracy: 0.001)
        XCTAssertEqual(doors.last ?? 0, 141 - 2.75, accuracy: 0.001)
        // Evenly along each car: 5.5 m apart.
        for (a, b) in zip(doors, doors.dropFirst()) { XCTAssertEqual(b - a, 5.5, accuracy: 0.001) }
        XCTAssertTrue(Props.doorCentres(length: 150, formations: [six], kind: .railway).isEmpty, "a railway's doors differ by train")
    }

    func testAStationIsAMetroByItsKitSystemOrItsTrains() {
        XCTAssertEqual(Props.kind(system: "mrt", calling: 0, metroTrains: 0), .metro)
        XCTAssertEqual(Props.kind(system: "tra_sched", calling: 0, metroTrains: 0), .railway)
        XCTAssertEqual(Props.kind(system: "game", calling: 2, metroTrains: 2), .metro)
        XCTAssertEqual(Props.kind(system: "game", calling: 2, metroTrains: 1), .railway)
        XCTAssertEqual(Props.kind(system: nil, calling: 0, metroTrains: 0), .railway)
    }

    func testTheBinsKeepClearOfTheDoorsAndTheBoards() {
        let doors = Props.doorCentres(length: 150, formations: [formation(6, 22, doors: 4)], kind: .metro)
        let boards = Props.stopMarks(length: 150, formations: [formation(6, 22, doors: 4)], kind: .metro).map(\.along)
        let bins = Props.bins(length: 150, doors: doors, boards: boards)
        XCTAssertFalse(bins.isEmpty)
        for bin in bins {
            XCTAssertTrue(doors.allSatisfy { abs($0 - bin) >= Props.binDoorClearance + 1.3 }, "bin at \(bin)")
            XCTAssertTrue(boards.allSatisfy { abs($0 - bin) >= Props.binBoardClearance + 1.3 }, "bin at \(bin)")
            XCTAssertTrue(bin >= 30 && bin <= 120, "under the canopy")
        }
        // Every 40 m on a long platform.
        let long = Props.bins(length: 300, doors: [], boards: [])
        XCTAssertEqual(long.count, 5)
        for (a, b) in zip(long, long.dropFirst()) { XCTAssertEqual(b - a, Props.binSpacing, accuracy: 0.001) }
    }

    func testTheEdgeLightsAreAMetrosAndTheCanopyLampsUnderEachPiece() {
        let lights = Props.edgeLights(length: 100, kind: .metro)
        XCTAssertEqual(lights.count, 20)
        XCTAssertEqual(lights.first ?? 0, 2.5, accuracy: 0.001)
        XCTAssertTrue(Props.edgeLights(length: 100, kind: .railway).isEmpty)
        // 100 m: its canopy 60 m in eight pieces, a lamp under each middle.
        let lamps = Props.canopyLamps(length: 100)
        XCTAssertEqual(lamps.count, 8)
        XCTAssertEqual(lamps.first ?? 0, 20 + 3.75, accuracy: 0.001)
    }

    // MARK: Laid in the scene

    /// A builder with one platform 200 m along x beside the track at z 0,
    /// of a station whose kit system is `system`.
    private func builder(system: String, width: Float = 3.2) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: GameWorld.newGame())
        let line = stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, Map3DScene.railLift, 0) }
        builder.laidPlatforms = [Builder.LaidPlatform(station: StationID(rawValue: 1), line: line, offset: 1.6 + width / 2, width: width,
                                                      structure: .surface)]
        builder.stationSystems[StationID(rawValue: 1)] = system
        return builder
    }

    private func boards(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.sidewalk && $0.y > Map3DScene.railLift + 2.5 }
    }

    private func glowing(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices).filter { $0.layer == Map3DVertex.glowing }
    }

    func testARailwayPlatformsPropsAreLaidCloseUpOnly() {
        var b = builder(system: "tra_sched")
        b.addPlatformProps()
        XCTAssertFalse(boards(b.closeMeshes).isEmpty)
        // The boards stand past the yellow line, clear of the train.
        XCTAssertTrue(boards(b.closeMeshes).allSatisfy { $0.z > 2.0 && $0.z < 3.0 })
        XCTAssertFalse(glowing(b.closeMeshes).isEmpty, "the canopy's lamps, lit at night")
        // The bins: the commercial kit's, at the platform's back.
        let binColours = Set([StationKitBuilder.commBlue])
        XCTAssertTrue(b.closeMeshes.values.flatMap(\.vertices).contains { binColours.contains($0.color) && $0.z > 3.5 })
        // Not in the full or the simplified city, nor the base.
        for meshes in [b.meshes, b.nearMeshes, b.farMeshes, b.standInMeshes] {
            XCTAssertTrue(boards(meshes).isEmpty && glowing(meshes).isEmpty)
        }
    }

    func testAMetroPlatformHasQueueLinesAtTheDoorsAndLightsAlongItsEdge() {
        var b = builder(system: "mrt")
        b.addPlatformProps()
        let top = Map3DScene.railLift + Builder.platformHeight
        let queue = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.platformEdge && abs($0.y - top - 0.012) < 0.001 }
        XCTAssertFalse(queue.isEmpty)
        let lights = glowing(b.closeMeshes)
        XCTAssertFalse(lights.isEmpty)
        XCTAssertTrue(lights.allSatisfy { $0.z > 1.6 && $0.z < 1.8 }, "at the edge, inside the yellow line")
        // A railway platform has neither.
        var railway = builder(system: "tra_sched")
        railway.addPlatformProps()
        XCTAssertTrue(railway.closeMeshes.values.flatMap(\.vertices).allSatisfy {
            !($0.color == Map3DPalette.platformEdge && abs($0.y - top - 0.012) < 0.001)
        })
    }

    func testANarrowPlatformHasNoBins() {
        var b = builder(system: "tra_sched", width: 2.2)
        b.addPlatformProps()
        XCTAssertFalse(b.closeMeshes.values.flatMap(\.vertices).contains { $0.color == StationKitBuilder.commBlue })
    }

    /// Decision 436's count for its budget: what one platform adds.
    func testTrianglesAPlatformAdds() {
        for system in ["tra_sched", "mrt"] {
            var b = builder(system: system)
            b.addPlatformProps()
            let triangles = b.closeMeshes.values.reduce(0) { $0 + $1.triangleCount }
            print("Decision 436: a 200 m \(system) platform adds \(triangles) triangles close up")
            XCTAssertLessThan(triangles, 2_500)
        }
    }

    // MARK: Destination signs

    func testTheLocalAndTzeChiangCabCarsCarryASignInFrontOfTheirCab() throws {
        let pack = Map3DModelPack.standard
        for (name, facing, service) in [("set-emu900-head", Float(1), Map3DHeadSign.Service.local), ("set-emu900-tail", -1, .local),
                                        ("set-emu800-head", 1, .local), ("set-emu500-head", 1, .local),
                                        ("set-emu3000-head", 1, .express), ("set-puyuma-head", 1, .express),
                                        ("set-taroko-head", 1, .express), ("set-emu900Far-head", 1, .local)] {
            let index = try XCTUnwrap(pack.index(of: name))
            let sign = try XCTUnwrap(pack.headSigns[index], name)
            let model = pack.models[index]
            XCTAssertEqual(sign.facing, facing, name)
            XCTAssertEqual(sign.service, service, name)
            // At the cab's end, under the roof.
            let end = facing > 0 ? model.maximum.x : -model.minimum.x
            XCTAssertLessThanOrEqual(sign.middle.x * facing, end + 0.05, name)
            XCTAssertGreaterThan(sign.middle.x * facing, end - 2.5, name)
            XCTAssertEqual(sign.middle.z, model.maximum.z - 0.75, accuracy: 0.001)
        }
        // No sign on a middle car, a locomotive or a metro car.
        for name in ["set-emu900-car", "set-pushPull-head", "set-metroC381-head"] {
            if let index = pack.index(of: name) { XCTAssertNil(pack.headSigns[index], name) }
        }
        XCTAssertEqual(Map3DHeadSign.Service.local.colour, Map3DColor.rgb(0x2E6FB0))
        XCTAssertEqual(Map3DHeadSign.Service.express.colour, Map3DColor.rgb(0xC0392B))
    }

    func testASignIsDrawnCloseUpOnlyLitAtNight() throws {
        let pack = Map3DModelPack.standard
        let index = try XCTUnwrap(pack.index(of: "set-emu900-head"))
        var frame = Map3DTrains.Frame()
        frame.instances = [Map3DTrains.instance(of: pack.models[index], index: index, from: Map3DPoint(-21.5, 0, 0),
                                                to: Map3DPoint(0, 0, 0), stripe: 0)]
        var near = frame
        Map3DHeadSign.add(to: &near, signs: pack.headSigns, eye: Map3DPoint(30, 5, 0))
        XCTAssertEqual(near.boxes.triangleCount, 4, "a board and its strip")
        XCTAssertEqual(near.boxes.vertices.filter { $0.layer == Map3DVertex.glowing }.count, 4)
        // In front of the cab (its front at x 0), over the windscreen,
        // facing forward.
        XCTAssertTrue(near.boxes.vertices.allSatisfy { $0.x > -2 && $0.x < 0.1 && $0.y > 2.9 && $0.y < 3.6 && $0.nx > 0.5 })
        var far = frame
        Map3DHeadSign.add(to: &far, signs: pack.headSigns, eye: Map3DPoint(Map3DHeadSign.reach + 50, 5, 0))
        XCTAssertTrue(far.boxes.isEmpty)
    }
}
