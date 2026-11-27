import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1035: the studio's small temple pieces (cut-tile dragons,
/// dragon columns, Tudigong) on the kit temples, a shrine's smaller lions,
/// and the dogs and pigeons of some temple squares and station forecourts.
final class Map3DTemplePropTests: XCTestCase {
    private func size(_ model: Map3DModelPack.Model) -> (x: Float, y: Float, z: Float) {
        (model.maximum.x - model.minimum.x, model.maximum.y - model.minimum.y, model.maximum.z - model.minimum.z)
    }

    /// Each piece decodes at the studio's size and within its triangles,
    /// its far shape far smaller, its foot on the ground.
    func testTheModels() throws {
        let triangles: [Map3DTempleProp: Int] = [
            .ridgeDragons: 540, .ridgeDragonsFar: 76, .dragonPillar: 580, .dragonPillarFar: 60, .tudigong: 538, .tudigongFar: 80,
            .streetDog: 286, .streetDogFar: 52, .pigeon: 120,
        ]
        for prop in Map3DTempleProp.allCases {
            let model = try XCTUnwrap(prop.model, "\(prop)")
            XCTAssertEqual(model.triangleCount, triangles[prop], "\(prop)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, "\(prop) stands on its foot")
        }
        let dragons = size(try XCTUnwrap(Map3DTempleProp.ridgeDragons.model))
        XCTAssertEqual(dragons.y, 2.4, accuracy: 0.15, "along the ridge")
        XCTAssertEqual(dragons.z, 1.2, accuracy: 0.15)
        XCTAssertEqual(size(try XCTUnwrap(Map3DTempleProp.dragonPillar.model)).z, 3.2, accuracy: 0.15)
        XCTAssertEqual(size(try XCTUnwrap(Map3DTempleProp.tudigong.model)).z, 1.2, accuracy: 0.1)
        XCTAssertEqual(size(try XCTUnwrap(Map3DTempleProp.streetDog.model)).x, 0.85, accuracy: 0.1)
        XCTAssertEqual(size(try XCTUnwrap(Map3DTempleProp.pigeon.model)).x, 0.32, accuracy: 0.05)
        for (near, far) in [(Map3DTempleProp.ridgeDragons, Map3DTempleProp.ridgeDragonsFar), (.dragonPillar, .dragonPillarFar),
                            (.tudigong, .tudigongFar), (.streetDog, .streetDogFar)] {
            let a = size(try XCTUnwrap(near.model)), b = size(try XCTUnwrap(far.model))
            XCTAssertEqual(a.x, b.x, accuracy: 0.15, "\(far)")
            XCTAssertEqual(a.z, b.z, accuracy: 0.15, "\(far)")
        }
    }

    /// The dragons sit on the hall's ridge, the columns stand on the
    /// gate's pad under its eaves, and the shrine's lions are 1.2 m.
    func testWhereThePiecesStand() throws {
        let places = Map3DScene.Builder.templePropPlaces
        let height = try XCTUnwrap(places.pillarHeight, "the gate leaves room for the columns")
        XCTAssertGreaterThanOrEqual(height, 2.6)
        XCTAssertLessThanOrEqual(height, 3.2)
        XCTAssertGreaterThan(places.ridgeY, 4, "on the ridge, not the square")
        // The temple's top: the dragons over the hall's ridge, by their
        // own height at most.
        let temple = try XCTUnwrap(Map3DScene.Builder.templeModels[.temple]?.mesh.bounds)
        let bare = try XCTUnwrap(Map3DScene.Builder.templeModels(props: .none)[.temple]?.mesh.bounds)
        XCTAssertGreaterThan(temple.max.y, bare.max.y)
        XCTAssertLessThanOrEqual(temple.max.y, bare.max.y + 1.3)
        // Nothing of the pieces outside the temple's square.
        XCTAssertEqual(temple.min.x, bare.min.x, accuracy: 0.01)
        XCTAssertEqual(temple.max.x, bare.max.x, accuracy: 0.01)
        XCTAssertEqual(temple.min.z, bare.min.z, accuracy: 0.01)
        // The shrine's lions: the tallest thing before its side hall's
        // front columns (from 1.45 m) but Tudigong's 1.2 m plinth and all.
        let small = try XCTUnwrap(Map3DScene.Builder.templeModels[.small]?.mesh)
        let lions = small.vertices.filter { $0.position.x > 2 && $0.position.x < 3.2 && abs(abs($0.position.z) - 2.2) < 0.8 }
        let top = try XCTUnwrap(lions.map(\.position.y).max())
        XCTAssertEqual(top - 0.12, 1.2, accuracy: 0.1)
        // Tudigong at the hall's door, on its platform.
        let figure = small.vertices.filter { abs($0.position.x - Map3DScene.Builder.tudigongX) < 0.5 && abs($0.position.z) < 0.5 }
        XCTAssertGreaterThan(try XCTUnwrap(figure.map(\.position.y).max()), 0.12 + 0.35 + 1.0)
    }

    /// Dogs in Taiwan only, pigeons everywhere but Finland, each square's
    /// the same every time, in about the shares the rules give.
    func testTheAnimals() throws {
        let spots = try XCTUnwrap(Map3DScene.Builder.templeAnimalSpots(.temple, side: 1))
        XCTAssertNil(Map3DScene.Builder.templeAnimalSpots(.large, side: 1))
        var dogs = 0, flocks = 0
        let dog = try XCTUnwrap(Map3DTempleProp.streetDog.model).triangleCount, pigeon = try XCTUnwrap(Map3DTempleProp.pigeon.model).triangleCount
        for seed in 0..<400 {
            let animals = Map3DScene.Builder.squareAnimals(seed: (Int32(seed), 7), dog: 0.3, pigeons: 0.4, dogs: true, birds: true, spots: spots)
            let again = Map3DScene.Builder.squareAnimals(seed: (Int32(seed), 7), dog: 0.3, pigeons: 0.4, dogs: true, birds: true, spots: spots)
            XCTAssertEqual(animals.vertices.map(\.position), again.vertices.map(\.position))
            // One dog or none, and a flock of two to five or none.
            let count = animals.indices.count / 3
            let hasDog = (count - dog) >= 0 && (count - dog) % pigeon == 0
            let birds = (count - (hasDog ? dog : 0)) / pigeon
            XCTAssertEqual(count, (hasDog ? dog : 0) + birds * pigeon)
            XCTAssertTrue(birds == 0 || (2...5).contains(birds), "\(birds)")
            if hasDog { dogs += 1 }
            if birds > 0 { flocks += 1 }
            // Every bird and dog on the square, clear of the hall and the gate.
            for vertex in animals.vertices {
                XCTAssertGreaterThan(vertex.position.x, 0.9)
                XCTAssertLessThan(vertex.position.x, 5)
                XCTAssertLessThan(abs(vertex.position.z), 8)
            }
            XCTAssertTrue(Map3DScene.Builder.squareAnimals(seed: (Int32(seed), 7), dog: 0.3, pigeons: 0.4, dogs: false, birds: false,
                                                           spots: spots).isEmpty)
        }
        XCTAssertEqual(Double(dogs) / 400, 0.3, accuracy: 0.07)
        XCTAssertEqual(Double(flocks) / 400, 0.4, accuracy: 0.07)
    }

    /// Decision 1035's measure: on the scenes with the most temples
    /// (Taipei's middle, Tainan's, Lukang's), the temples with their
    /// pieces and animals are at least nine in ten of those drawn before.
    func testTheDensestScenesKeepTheirTemples() throws {
        let temples = try RealTemples(data: Data(contentsOf: Map3DLandmarksTests.templesFile))
        let bare = Map3DScene.Builder.templeModels(props: .none)
        for (name, latitude, longitude) in [("Taipei", 25.0478, 121.5170), ("Tainan", 22.9971, 120.2127), ("Lukang", 24.0556, 120.4346)] {
            let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            func drawn(_ models: [RealTemples.Size: Map3DScene.Builder.TempleModel]?, animals: Bool) -> Int {
                let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
                var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
                _ = builder.addTemples(temples, frame: frame, clearOf: [], models: models, animals: animals)
                // Each temple drawn has one 10-triangle box in its hall.
                return builder.nearMeshes.values.reduce(0) { $0 + $1.indices.count / 3 } / 10
            }
            let before = drawn(bare, animals: false), after = drawn(nil, animals: true)
            print("Decision 1035: \(name) \(after) of \(before) temples")
            XCTAssertGreaterThan(before, 0, name)
            XCTAssertGreaterThanOrEqual(Double(after), Double(before) * 0.9, name)
        }
    }
}
