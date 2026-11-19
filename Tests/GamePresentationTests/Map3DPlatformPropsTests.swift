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
    private func builder(system: String, width: Float = 3.2, world: GameWorld = .newGame()) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: world)
        let line = stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, Map3DScene.railLift, 0) }
        builder.laidPlatforms = [Builder.LaidPlatform(station: StationID(rawValue: 1), line: line, offset: 1.6 + width / 2, width: width,
                                                      structure: .surface)]
        builder.stationSystems[StationID(rawValue: 1)] = system
        return builder
    }

    private func boards(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        // Decision 882: not the name boards at the back.
        meshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.sidewalk && $0.y > Map3DScene.railLift + 2.5 && $0.z < 4 }
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

    // MARK: Furniture (decision 874)

    /// To the nearest 0.1 m.
    private func tenths(_ values: [Float]) -> [Int] { values.map { Int(($0 * 10).rounded()) } }

    /// The old version's module on a side platform under the sky: the
    /// half that faces the track, every 40 m; no square column, and no
    /// sign without a roof.
    func testASidePlatformHasTheOldModulesHalfAtItsBack() {
        let pieces = Props.furniture(length: 200, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [], roof: nil)
        // Each module: two benches (seat and back), the machine, two boards (post and panel).
        XCTAssertEqual(pieces.count, 5 * 9)
        XCTAssertFalse(pieces.contains { $0.colour == Map3DPalette.tunnelWall }, "no column to a ceiling")
        XCTAssertFalse(pieces.contains { $0.lit })
        XCTAssertEqual(pieces.filter { $0.colour == Map3DPalette.trainRed }.count, 5)
        for piece in pieces {
            XCTAssertGreaterThanOrEqual(piece.near, 0)
            XCTAssertLessThanOrEqual(piece.far, 3.2 - Props.furnitureWalk + 0.001, "a walk left inside the yellow line")
            XCTAssertGreaterThanOrEqual(piece.bottom, 0)
            XCTAssertLessThan(piece.top, 2.5, "under a canopy 3.2 m up")
            XCTAssertTrue(piece.along - piece.length / 2 >= 0 && piece.along + piece.length / 2 <= 200)
        }
        // As big as under ground: a bench's back 1.53 m in the module, a metre here.
        let back = pieces.filter { $0.colour == Map3DPalette.timber }.map(\.top).max() ?? 0
        XCTAssertEqual(back, 1.53 * 4.85 / 7.34, accuracy: 0.001)
        // Shorter than a module, or too narrow to walk past a bench: none.
        XCTAssertTrue(Props.furniture(length: 39, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [], roof: nil).isEmpty)
        XCTAssertTrue(Props.furniture(length: 200, depth: 2.2, island: false, rightHalf: true, forward: true, bins: [], roof: nil).isEmpty)
    }

    func testTheSignsHangUnderTheRoofClearOfItsColumns() {
        let roof: ClosedRange<Float> = 40...160
        let pieces = Props.furniture(length: 200, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [], roof: roof,
                                     signTop: Props.signTopUnderCanopy)
        let signs = pieces.filter { $0.colour == Map3DPalette.dark }, faces = pieces.filter(\.lit)
        // The module's right sign 15.88 m along it: under the roof in the second to the fourth module.
        XCTAssertEqual(tenths(signs.map(\.along)), [559, 959, 1359])
        XCTAssertEqual(faces.count, 3)
        for sign in signs {
            XCTAssertEqual(sign.top, 3.15, accuracy: 0.001)
            XCTAssertGreaterThan(sign.bottom, 2.4, "over the heads")
            XCTAssertGreaterThanOrEqual(sign.near, Props.signInset)
            XCTAssertLessThanOrEqual(sign.far, 3.2 - Props.signInset + 0.001, "not out over the track")
        }
        for face in faces { XCTAssertTrue(face.near > signs[0].near && face.far < signs[0].far && face.top < 3.15) }
        // A column where a sign would hang: the sign moves a metre, clear of it.
        let moved = Props.furniture(length: 200, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [], roof: roof,
                                    signTop: Props.signTopUnderCanopy, columns: [56, 96.5])
        XCTAssertEqual(tenths(moved.filter { $0.colour == Map3DPalette.dark }.map(\.along)), [549, 949, 1359])
        // The canopy's columns: at the ends of its pieces.
        XCTAssertEqual(tenths(Props.canopyColumns(length: 100, share: 0.6)), [200, 275, 350, 425, 500, 575, 650, 725, 800])
    }

    func testTheFurnitureKeepsClearOfTheBins() {
        // The first bench is 1 to 7 m along its module, the machine 17.5 to 18.7 m.
        let pieces = Props.furniture(length: 200, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [5, 60], roof: nil)
        XCTAssertEqual(pieces.count, 5 * 9 - 2 - 1)
        for piece in pieces {
            for bin in [Float(5), 60] {
                XCTAssertGreaterThanOrEqual(abs(piece.along - bin), piece.length / 2 + 1.3 + Props.furnitureBinClearance)
            }
        }
    }

    /// An island's two halves each lay their own side of the module, the
    /// other way along when their lines run against it, so they meet.
    func testAnIslandsHalvesMirrorEachOther() {
        let right = Props.furniture(length: 200, depth: 3, island: true, rightHalf: true, forward: true, bins: [], roof: 0...200)
        let left = Props.furniture(length: 200, depth: 3, island: true, rightHalf: false, forward: false, bins: [], roof: 0...200)
        // The benches, machine and boards stand across the middle: both halves have them, at the same place.
        func floor(_ pieces: [Props.Furniture]) -> [Float] { pieces.filter { $0.colour != Map3DPalette.dark && !$0.lit }.map(\.along).sorted() }
        XCTAssertEqual(tenths(floor(right)), tenths(floor(left).map { 200 - $0 }.sorted()))
        // The signs differ: one over each half.
        XCTAssertEqual(tenths(right.filter(\.lit).map(\.along)), [159, 559, 959, 1359, 1759])
        XCTAssertEqual(tenths(left.filter(\.lit).map { 200 - $0.along }), [239, 639, 1039, 1439, 1839])
        // A narrow island's furniture is narrower with it; one under 3 m has none.
        let narrow = Props.furniture(length: 200, depth: 1.6, island: true, rightHalf: true, forward: true, bins: [], roof: nil)
        XCTAssertFalse(narrow.isEmpty)
        XCTAssertTrue(narrow.allSatisfy { $0.far <= 1.6 - Props.furnitureWalk + 0.001 })
        XCTAssertTrue(Props.furniture(length: 200, depth: 1.4, island: true, rightHalf: true, forward: true, bins: [], roof: nil).isEmpty)
    }

    func testThePlatformsFurnitureIsLaidCloseUpOnlyAtItsBack() {
        var b = builder(system: "tra_sched")
        b.addPlatformProps()
        func timber(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
            meshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.timber }
        }
        let benches = timber(b.closeMeshes)
        XCTAssertFalse(benches.isEmpty)
        // The platform from z 1.6 to 4.8: the benches against its back.
        XCTAssertTrue(benches.allSatisfy { $0.z >= 4.8 - 0.88 && $0.z <= 4.801 })
        let top = Map3DScene.railLift + Builder.platformHeight
        XCTAssertTrue(benches.allSatisfy { $0.y > top && $0.y < top + 1.1 })
        XCTAssertTrue(b.closeMeshes.values.flatMap(\.vertices).contains { $0.color == Map3DPalette.trainRed }, "the machine")
        // Its signs under the canopy, over the platform.
        let signs = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.dark && $0.y > top + 2.4 }
        XCTAssertFalse(signs.isEmpty)
        XCTAssertTrue(signs.allSatisfy { $0.z > 1.6 && $0.z < 4.8 && $0.y <= top + 3.151 })
        for meshes in [b.meshes, b.nearMeshes, b.farMeshes, b.standInMeshes] { XCTAssertTrue(timber(meshes).isEmpty) }
        // Under a shell of its own (no kit canopy): no sign.
        var shell = builder(system: "mrt")
        shell.shellRoofed = [StationID(rawValue: 1)]
        shell.addPlatformProps()
        XCTAssertFalse(timber(shell.closeMeshes).isEmpty)
        XCTAssertFalse(shell.closeMeshes.values.flatMap(\.vertices).contains { $0.color == Map3DPalette.dark && $0.y > top + 2.4 })
        // Too narrow: none.
        var narrow = builder(system: "tra_sched", width: 2.2)
        narrow.addPlatformProps()
        XCTAssertTrue(timber(narrow.closeMeshes).isEmpty)
    }

    /// Two halves of an island whose lines run opposite ways: their
    /// benches back to back on the island's middle.
    func testAnIslandsBenchesStandBackToBack() {
        var b = builder(system: "tra_sched")
        let there = stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, Map3DScene.railLift, 0) }
        let back = stride(from: Float(100), through: -100, by: -20).map { Map3DPoint($0, Map3DScene.railLift, 9.2) }
        b.laidPlatforms = [there, back].map {
            Builder.LaidPlatform(station: StationID(rawValue: 1), line: $0, offset: 1.6 + 1.5, width: 3, structure: .elevated, island: true)
        }
        b.addPlatformProps()
        let timber = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.timber }
        let near = timber.filter { $0.z < 4.6 - 0.01 }, far = timber.filter { $0.z > 4.6 + 0.01 }
        XCTAssertFalse(near.isEmpty)
        // Where neither half has a bin in the way, a double bench.
        let both = Set(near.map { ($0.x * 10).rounded() }).intersection(far.map { ($0.x * 10).rounded() })
        XCTAssertGreaterThanOrEqual(both.count, 12)
        XCTAssertTrue(timber.allSatisfy { abs($0.z - 4.6) <= 0.88 })
    }

    /// Decision 874's preview (`tools/platform-furniture/preview.py`):
    /// the scene's own meshes round three stations on flat ground, an
    /// island and a side platform on the ground and a side platform on a
    /// viaduct. Only when asked.
    @MainActor
    func testWriteTheFurniturePreviewsMeshes() throws {
        guard let out = ProcessInfo.processInfo.environment["PLATFORM_FURNITURE_PREVIEW"] else {
            throw XCTSkip("PLATFORM_FURNITURE_PREVIEW=<file.json> writes the preview's meshes")
        }
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 32_768),
                                  economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        // Two tracks 10 m apart, 2 km long; a third on a viaduct 10 m up, 60 m to the south.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 12_800))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 122_880, y: 12_800))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 13_440))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 122_880, y: 13_440))
        let e = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 17_280, z: 640))
        let f = try world.buildTrackNode(at: WorldCoordinate(x: 122_880, y: 17_280, z: 640))
        try world.buildTrackEdge(from: a, to: b)
        try world.buildTrackEdge(from: c, to: d)
        try world.buildTrackEdge(from: e, to: f, structure: .elevated)
        let island = try world.buildStation(named: "高雄", at: PlanPoint(x: 25_600, y: 12_000))
        try world.addTrackPlatform(island.id, on: .edge(1), from: 290 * 64, to: 510 * 64)
        try world.addTrackPlatform(island.id, on: .edge(2), from: 290 * 64, to: 510 * 64)
        let side = try world.buildStation(named: "板橋", at: PlanPoint(x: 76_800, y: 12_000))
        try world.addTrackPlatform(side.id, on: .edge(1), from: 1_090 * 64, to: 1_310 * 64)
        let raised = try world.buildStation(named: "松山機場", at: PlanPoint(x: 25_600, y: 18_000))
        try world.addTrackPlatform(raised.id, on: .edge(3), from: 290 * 64, to: 510 * 64)
        let scene = Map3DScene(world: world)
        var positions: [Float] = [], colours: [Int] = [], lit: [Bool] = [], indices: [Int] = []
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.close] {
                let first = lit.count
                for vertex in mesh.vertices {
                    positions += [vertex.x, vertex.y, vertex.z]
                    colours.append(Int(vertex.color & 0xFF_FFFF))
                    lit.append(vertex.glows)
                }
                indices += mesh.indices.map { first + Int($0) }
            }
        }
        func middle(_ x: Int64, _ y: Int64, _ z: Int64 = 0) -> [Float] {
            let point = scene.point(WorldCoordinate(x: x, y: y, z: z))
            return [point.x, point.y, point.z]
        }
        let json: [String: Any] = ["island": middle(25_600, 13_120), "side": middle(76_800, 12_800), "raised": middle(25_600, 17_280, 640),
                                   "positions": positions, "colours": colours, "lit": lit, "indices": indices]
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: out))
    }

    // MARK: Name boards (decision 882)

    func testTheGlyphsWriteTheGamesStationNames() {
        let glyphs = Map3DBoardGlyphs.glyphs
        XCTAssertGreaterThan(glyphs.count, 3_000)
        for character in "高雄臺北車站鶯歌板橋松山機場福岡博多ロヴァニエミRovaniemiäöÅ0123456789" {
            let glyph = glyphs[character]
            XCTAssertNotNil(glyph, String(character))
            XCTAssertTrue(glyph?.rectangles.allSatisfy { $0.x + $0.width <= 16 && $0.y + $0.height <= 16 } ?? false)
        }
        // A Chinese character a whole cell square; a Latin letter narrower.
        XCTAssertEqual(glyphs["站"]?.width, 16)
        XCTAssertLessThan(glyphs["i"]?.width ?? 16, 8)
        // A line: the characters side by side; one with no glyph left out.
        let line = Map3DBoardGlyphs.layout("高雄")
        XCTAssertEqual(line.width, 32)
        XCTAssertTrue(line.rectangles.contains { $0.x >= 16 })
        XCTAssertEqual(Map3DBoardGlyphs.layout("高\u{E000}雄").width, 32)
        XCTAssertEqual(Map3DBoardGlyphs.layout("\u{E000}").width, 0)
    }

    func testANameBoardStandsInTheModulesGapClearOfTheBins() {
        // 200 m: five modules from 0 m; the middle one's and every second one out.
        XCTAssertEqual(tenths(Props.nameBoards(length: 200, depth: 3.2, island: false, forward: true, bins: [])), [249, 1049, 1849])
        // The other way along: the same gap, counted from the far end.
        XCTAssertEqual(tenths(Props.nameBoards(length: 200, depth: 3.2, island: false, forward: false, bins: [])), [151, 951, 1751])
        // A bin in the way: moved within the gap, or left out.
        let moved = Props.nameBoards(length: 200, depth: 3.2, island: false, forward: true, bins: [101])
        XCTAssertEqual(moved.count, 3)
        XCTAssertGreaterThanOrEqual(abs(moved[1] - 101), 1.5 + 1.3 + Props.furnitureBinClearance)
        XCTAssertTrue((102.8...106.9).contains(moved[1]))
        XCTAssertEqual(tenths(Props.nameBoards(length: 200, depth: 3.2, island: false, forward: true, bins: [104.8])), [249, 1849])
        // Clear of the canopy's columns, which would stand before it; the
        // other way along, of the bins where they are.
        let columns = Props.canopyColumns(length: 200, share: 0.6)
        for forward in [true, false] {
            let boards = Props.nameBoards(length: 200, depth: 3.2, island: false, forward: forward, bins: [], columns: columns)
            XCTAssertFalse(boards.isEmpty)
            for board in boards {
                XCTAssertTrue(columns.allSatisfy { abs($0 - board) >= 1.5 + Props.nameBoardColumnClearance })
            }
        }
        let reversed = Props.nameBoards(length: 200, depth: 3.2, island: false, forward: false, bins: [99])
        XCTAssertEqual(reversed.count, 3)
        XCTAssertGreaterThanOrEqual(abs(reversed[1] - 99), 1.5 + 1.3 + Props.furnitureBinClearance)
        // Short, narrow: one or none.
        XCTAssertEqual(Props.nameBoards(length: 50, depth: 3.2, island: false, forward: true, bins: []).count, 1)
        XCTAssertTrue(Props.nameBoards(length: 30, depth: 3.2, island: false, forward: true, bins: []).isEmpty)
        XCTAssertTrue(Props.nameBoards(length: 200, depth: 2.2, island: false, forward: true, bins: []).isEmpty)
        XCTAssertEqual(Props.nameBoards(length: 200, depth: 1.6, island: true, forward: true, bins: []).count, 3)
        // Never on the furniture's floor pieces.
        let furniture = Props.furniture(length: 200, depth: 3.2, island: false, rightHalf: true, forward: true, bins: [], roof: nil)
            .filter { $0.bottom < 2 }
        for board in Props.nameBoards(length: 200, depth: 3.2, island: false, forward: true, bins: []) {
            for piece in furniture {
                XCTAssertGreaterThanOrEqual(abs(piece.along - board), piece.length / 2 + Props.nameBoardLength / 2)
            }
        }
    }

    func testANameBoardIsLaidCloseUpAtTheBackFacingTheTrack() throws {
        var world = GameWorld.newGame()
        let station = try world.buildStation(named: "高雄", at: PlanPoint(x: 0, y: 0))
        var b = builder(system: "tra_sched", world: world)
        b.laidPlatforms = b.laidPlatforms.map {
            Builder.LaidPlatform(station: station.id, line: $0.line, offset: $0.offset, width: $0.width, structure: $0.structure)
        }
        b.stationSystems[station.id] = "tra_sched"
        b.addPlatformProps()
        let top = Map3DScene.railLift + Builder.platformHeight
        let all = b.closeMeshes.values.flatMap(\.vertices)
        // The face, white in a grey frame, from 1.36 to 2.41 m up, against
        // the back (z 4.8), lit at night, facing the track; the green band across it.
        let face = all.filter { $0.color == Map3DPalette.sidewalk && $0.y > top + 1.3 && $0.z > 4 && $0.layer == Map3DVertex.nightLit }
        XCTAssertFalse(face.isEmpty)
        XCTAssertTrue(face.allSatisfy {
            abs($0.z - 4.695) < 0.001 && $0.y >= top + 1.359 && $0.y <= top + 2.411 && $0.layer == Map3DVertex.nightLit && $0.nz < -0.99
        })
        XCTAssertTrue(all.contains { $0.color == Props.nameBoardGreen && $0.z > 4 })
        // The name over the band, in front of the face.
        let ink = all.filter { $0.color == Map3DPalette.playerRim && $0.y > top + 1.3 && $0.z > 4 }
        XCTAssertFalse(ink.isEmpty)
        let band = top + 1.36 + 1.05 * Props.nameBoardBand.upperBound
        XCTAssertTrue(ink.allSatisfy { abs($0.z - 4.687) < 0.001 && $0.nz < -0.99 && $0.y >= band - 0.001 && $0.y <= top + 2.411 })
        // Three boards, each name's two characters.
        let xs = ink.map(\.x).sorted()
        XCTAssertEqual(zip(xs, xs.dropFirst()).filter { $1 - $0 > 5 }.count + 1, 3)
        XCTAssertLessThanOrEqual((xs.last ?? 0) - (xs.first ?? 0), 160 + 1.3)
        for meshes in [b.meshes, b.nearMeshes, b.farMeshes, b.standInMeshes] {
            XCTAssertFalse(meshes.values.flatMap(\.vertices).contains { $0.color == Map3DPalette.playerRim && $0.z > 4 })
        }
    }

    /// A real station's board: its English name small under its name, and
    /// an arrow at each end of the green band.
    func testANameBoardWritesItsSecondNameSmallUnderItsName() throws {
        var plain = Map3DMesh(), both = Map3DMesh()
        let out = Map3DPoint(0, 0, -1)
        Builder.addNameBoard(&plain, foot: Map3DPoint(0, 0, 0), out: out, name: "臺南", underground: false)
        Builder.addNameBoard(&both, foot: Map3DPoint(0, 0, 0), out: out, name: "臺南", second: "Tainan", underground: false)
        func ink(_ mesh: Map3DMesh) -> [Map3DVertex] { mesh.vertices.filter { $0.color == Map3DPalette.playerRim } }
        XCTAssertGreaterThan(ink(both).count, ink(plain).count)
        // 臺 written 台, which stays clear on the grid.
        XCTAssertEqual(Builder.boardText("臺南"), "台南")
        var simple = Map3DMesh()
        Builder.addNameBoard(&simple, foot: Map3DPoint(0, 0, 0), out: out, name: "台南", underground: false)
        XCTAssertEqual(ink(simple).count, ink(plain).count)
        // The name smaller with a second name under it, all over the band.
        let band = Props.nameBoardFoot + Props.nameBoardFrame + (Props.nameBoardHeight - 2 * Props.nameBoardFrame) * Props.nameBoardBand.upperBound
        XCTAssertTrue(ink(both).allSatisfy { $0.y >= band - 0.001 && $0.nz < -0.99 })
        let plainTop = try XCTUnwrap(ink(plain).map(\.y).max()), plainLow = try XCTUnwrap(ink(plain).map(\.y).min())
        let bothLow = try XCTUnwrap(ink(both).map(\.y).min())
        XCTAssertLessThan(bothLow, plainLow)
        XCTAssertLessThanOrEqual(try XCTUnwrap(ink(both).map(\.y).max()), plainTop + 0.001)
        // Two white arrows on the band, inside the face.
        let arrows = both.vertices.filter { $0.color == Map3DPalette.sidewalk && $0.layer != Map3DVertex.nightLit }
        XCTAssertEqual(arrows.count, 6)
        XCTAssertTrue(arrows.allSatisfy { abs($0.x) <= Props.nameBoardLength / 2 - Props.nameBoardFrame + 0.001 })
        if let out = ProcessInfo.processInfo.environment["PLATFORM_NAME_BOARD_PREVIEW"] {
            var positions: [Float] = [], colours: [Int] = [], lit: [Bool] = []
            for v in both.vertices { positions += [v.x, v.y, v.z]; colours.append(Int(v.color & 0xFF_FFFF)); lit.append(v.glows) }
            let json: [String: Any] = ["positions": positions, "colours": colours, "lit": lit, "indices": both.indices.map { Int($0) }]
            try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: out))
        }
    }

    /// Decision 436's count for its budget: what one platform adds.
    func testTrianglesAPlatformAdds() throws {
        // Decision 882: its name boards with a long name.
        var world = GameWorld.newGame()
        let station = try world.buildStation(named: "松山機場", at: PlanPoint(x: 0, y: 0))
        XCTAssertEqual(station.id, StationID(rawValue: 1))
        for system in ["tra_sched", "mrt"] {
            var b = builder(system: system, world: world)
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
