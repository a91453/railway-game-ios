import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 696: the railway museum's own hall, sheds and display tracks,
/// and its exhibits standing on them.
final class Map3DRailwayMuseumTests: XCTestCase {
    private typealias Museum = Map3DRailwayMuseum

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    /// Every museum, from the empty one to twelve exhibits, stands inside
    /// its 64 m square (drawn 62 m) on the ground, within 9,000 triangles
    /// (the amusement park's six models are some 6,000; twelve tracks'
    /// sleepers are a third of the museum's).
    func testEveryMuseumStandsInsideItsSquare() throws {
        let half = Float(Double(PlacedBuildingKind.railwayMuseum.side) / Map3DScene.Builder.metre) / 2 - 1
        XCTAssertEqual(Museum.meshes.count, Tourism.exhibitsCounted + 1)
        for (exhibits, mesh) in Museum.meshes.enumerated() {
            let bounds = try XCTUnwrap(mesh.bounds)
            for value in [bounds.min.x, bounds.min.z, -bounds.max.x, -bounds.max.z] {
                XCTAssertGreaterThanOrEqual(value, -half - 0.001, "\(exhibits) exhibits")
            }
            XCTAssertGreaterThanOrEqual(bounds.min.y, 0, "\(exhibits) exhibits")
            XCTAssertLessThanOrEqual(mesh.triangleCount, 9_000, "\(exhibits) exhibits")
        }
        // More than the twelve that count change nothing.
        XCTAssertEqual(Museum.mesh(exhibits: 20).triangleCount, Museum.meshes[12].triangleCount)
    }

    /// What the hall is known by (the old Taipei Workshop): the front gable
    /// stands above the roof's ridge under a white crown, the nave above
    /// its aisles, red brick banded in white, and red paving in the yard.
    func testTheHallIsTheRedBrickWorkshop() throws {
        var b = StationKitBuilder()
        Museum.hall(&b)
        let hall = b.mesh
        let top = try XCTUnwrap(hall.bounds?.max.y)
        XCTAssertGreaterThan(top, Museum.ridge + 1, "the crown stands over the ridge")
        XCTAssertGreaterThan(Museum.ridge, Museum.aisleTop + 4, "the nave stands over its aisles")
        XCTAssertGreaterThan(Museum.naveEave, Museum.aisleTop, "with its own windows over their roofs")
        // The highest thing is white and at the front.
        let crown = hall.vertices.filter { $0.y > top - 0.3 }
        XCTAssertTrue(crown.allSatisfy { $0.x > Museum.hallFront - 1 })
        XCTAssertTrue(crown.contains { $0.color == Museum.white || $0.color == Map3DColor.shaded(Museum.white, 0.95) })
        let colours = Set(hall.vertices.map(\.color))
        XCTAssertTrue(colours.contains(Museum.brick))
        XCTAssertTrue(colours.contains(Museum.white))
        XCTAssertTrue(Museum.meshes[0].vertices.contains { $0.color == Museum.paving }, "red from straight above")
        // The roof is not the walls' colour, nor the company's yellow of the
        // stand-in it had.
        XCTAssertNotEqual(Museum.slate, Museum.brick)
        XCTAssertFalse(Set(Museum.meshes[12].vertices.map(\.color)).contains(Map3DPalette.player))
    }

    /// The museum grows with its collection: the six tracks before the hall
    /// are there from the start, the left shed comes with the seventh
    /// exhibit and the right one with the tenth, each with its tracks.
    func testTheShedsComeWithTheExhibits() throws {
        XCTAssertEqual((0...12).map(Museum.sheds(exhibits:)), [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2])
        XCTAssertEqual(Museum.trackOffsets.count, Tourism.exhibitsCounted)
        XCTAssertEqual(Museum.hallTracks + 2 * Museum.shedTracks, Tourism.exhibitsCounted)
        func roofs(_ exhibits: Int) -> Int { Museum.boxes(exhibits: exhibits).count }
        XCTAssertEqual([0, 6, 7, 9, 10, 12].map(roofs), [3, 3, 4, 4, 5, 5])
        XCTAssertEqual(Museum.meshes[0].triangleCount, Museum.meshes[6].triangleCount, "empty tracks wait for their exhibits")
        XCTAssertGreaterThan(Museum.meshes[7].triangleCount, Museum.meshes[6].triangleCount)
        XCTAssertGreaterThan(Museum.meshes[10].triangleCount, Museum.meshes[9].triangleCount)
        // The left shed is on the left (−z), where the seventh track is.
        XCTAssertLessThan(Museum.trackOffsets[6], 0)
        XCTAssertEqual(Museum.shedSides(exhibits: 7), [-1])
        let left = try XCTUnwrap(Museum.meshes[7].bounds), none = try XCTUnwrap(Museum.meshes[6].bounds)
        XCTAssertEqual(left.max.y, none.max.y, "a shed is lower than the hall")
    }

    /// The tracks keep apart, and no shed stands on a hall track or the hall.
    func testTheTracksKeepApart() {
        let sorted = Museum.trackOffsets.sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, Map3DTrains.carWidth + 1.2, "room to walk between two exhibits")
        }
        for index in 0..<Museum.hallTracks {
            XCTAssertLessThan(abs(Museum.trackOffsets[index]), Museum.aisleOuter, "before the hall")
        }
        for index in Museum.hallTracks..<Museum.trackOffsets.count {
            let across = abs(Museum.trackOffsets[index])
            XCTAssertGreaterThan(across - Map3DTrains.carWidth / 2, Museum.shedCentre - Museum.shedHalf + 0.5, "inside its shed's walls")
            XCTAssertLessThan(across + Map3DTrains.carWidth / 2, Museum.shedCentre + Museum.shedHalf - 0.5)
        }
        XCTAssertGreaterThan(Museum.shedCentre - Museum.shedHalf, Museum.aisleOuter, "the sheds stand clear of the hall")
    }

    /// Every type of train the game has stands on any track without
    /// reaching into the hall, past its buffer stop or out of the plot.
    func testEveryTypeFitsItsTrack() throws {
        XCTAssertGreaterThan(Museum.start(ofTrack: 0), Museum.hallFront + 0.9, "the hall tracks stop before the hall's front")
        XCTAssertLessThanOrEqual(Museum.end(ofTrack: 0), 29.5)
        let pack = Map3DModelPack.standard
        for type in TrainType.allCases {
            let exhibit = try XCTUnwrap(Museum.exhibits(of: [type]).first)
            guard let model = pack.modelIndex(forType: exhibit.key, carIndex: 0, count: Museum.cars(of: exhibit.key)) else { continue }
            let length = pack.models[model].length
            for track in [0, Museum.hallTracks] {
                let front = Museum.frontOfExhibit(onTrack: track, length: length)
                XCTAssertLessThanOrEqual(front, 29, "\(type.spec.code) inside the gate")
                XCTAssertGreaterThan(front - length, Museum.start(ofTrack: track) + 0.6, "\(type.spec.code) clear of track \(track)'s buffer stop")
            }
        }
    }

    /// Each exhibit is one car on its own track, the first twelve; a type
    /// with no model of its own is a box; none has lamps lit or a label.
    func testTheExhibitsStandOnTheirTracks() throws {
        let types = Array(TrainType.allCases.prefix(14))
        let pack = Map3DModelPack.standard
        var frame = Map3DTrains.Frame()
        let base = Map3DPoint(100, 5, -40), facing = Map3DPoint(0, 0, 1)
        Museum.add(to: &frame, exhibits: types, at: base, facing: facing, pack: pack, eye: base + Map3DPoint(0, 60, 60))
        let exhibits = Museum.exhibits(of: types)
        XCTAssertEqual(exhibits.count, Tourism.exhibitsCounted)
        XCTAssertEqual(exhibits.map(\.track), Array(0..<12))
        let modelled = exhibits.filter { pack.modelIndex(forType: $0.key, carIndex: 0, count: Museum.cars(of: $0.key)) != nil }.count
        XCTAssertEqual(frame.instances.count, modelled)
        XCTAssertGreaterThan(modelled, 6)
        XCTAssertEqual(frame.boxes.triangleCount, (exhibits.count - modelled) * 10)
        XCTAssertTrue(frame.ends.isEmpty)
        XCTAssertTrue(frame.heads.isEmpty)
        XCTAssertFalse(frame.shadows.isEmpty)
        // With no pack every exhibit is a box; far off too.
        var plain = Map3DTrains.Frame()
        Museum.add(to: &plain, exhibits: types, at: base, facing: facing, pack: nil, eye: nil)
        XCTAssertTrue(plain.instances.isEmpty)
        XCTAssertEqual(plain.boxes.triangleCount, 12 * 10)
        // Each instance stands on its track: its place across the yard is
        // the track's, to the museum's right (−x in the scene when it faces +z).
        for (instance, exhibit) in zip(frame.instances, exhibits.filter { pack.modelIndex(forType: $0.key, carIndex: 0, count: Museum.cars(of: $0.key)) != nil }) {
            let right = facing.cross(.up)
            let across = (Map3DPoint(instance.transform[12], instance.transform[13], instance.transform[14]) - base).dot(right)
            XCTAssertEqual(across, Museum.trackOffsets[exhibit.track], accuracy: 0.01)
            XCTAssertEqual(instance.transform[13], base.y + Museum.railTop, accuracy: 0.6)
        }
    }

    /// In the scene the museum is its own model close up and brick boxes
    /// under grey roofs from farther; five exhibits lay the same hall as
    /// none, and the laid museum reads them from the world.
    func testTheSceneDrawsTheMuseum() throws {
        let world = ScreenshotScene.museumWorld(in: .english)
        let museum = try XCTUnwrap(world.railwayMuseum)
        XCTAssertEqual(Museum.shown(in: world), museum.exhibits.count)
        var builder = builder(world)
        builder.addPlacedBuildings()
        let close = builder.closeMeshes.values.reduce(0) { $0 + $1.triangleCount }
        XCTAssertEqual(close, Museum.meshes[museum.exhibits.count].triangleCount)
        let far = builder.farMeshes.values.flatMap(\.vertices)
        XCTAssertEqual(builder.farMeshes.values.reduce(0) { $0 + $1.triangleCount }, 10 * 4)
        XCTAssertTrue(far.contains { $0.color == Museum.slate })
        XCTAssertFalse(far.contains { $0.color == Map3DPalette.player })
        XCTAssertEqual(builder.standInMeshes.values.reduce(0) { $0 + $1.triangleCount }, 10 * 4)
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot())
        let laid = try XCTUnwrap(Museum.Laid(world: world, scene: scene))
        XCTAssertEqual(laid.exhibits, museum.exhibits)
        var frame = Map3DTrains.Frame()
        laid.add(to: &frame, pack: .standard, eye: laid.base)
        XCTAssertEqual(frame.instances.count + frame.boxes.triangleCount / 10, museum.exhibits.count)
    }

    /// The look sheet's model has the hall and an exhibit's car.
    func testTheLookModelHoldsTheExhibits() {
        let empty = Museum.lookModel(exhibits: [])
        XCTAssertEqual(empty.triangleCount, Museum.meshes[0].triangleCount)
        let one = Museum.lookModel(exhibits: [.emu3000], far: true)
        XCTAssertGreaterThan(one.triangleCount, empty.triangleCount)
        XCTAssertGreaterThan(Museum.hallModel().triangleCount, 1_000)
    }
}
