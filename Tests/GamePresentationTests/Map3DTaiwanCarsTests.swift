import Foundation
@testable import GamePresentation
import XCTest

/// Decision 838: Taiwan's saloon, SUV, van and yellow taxi, from the
/// Kenney Car Kit (`tools/tw-cars/`), in place of decision 259's boxes.
final class Map3DTaiwanCarsTests: XCTestCase {
    private static let models = Map3DRealTrainsTests.resources.appendingPathComponent("Models")

    private static func url(_ model: Map3DStreetModel) throws -> URL {
        models.appendingPathComponent(try XCTUnwrap(Map3DTaiwanCars.fileNames[model]) + "." + Map3DTaiwanCars.fileExtension)
    }

    private static func file(_ model: Map3DStreetModel) throws -> Map3DModelPack.Model {
        let name = try XCTUnwrap(Map3DTaiwanCars.fileNames[model])
        return Map3DTaiwanCars.model(model, from: try Map3DModelFile(decoding: Data(contentsOf: url(model)), named: name))
    }

    /// Each is its real car's size on its wheels, painted in the
    /// instance's colour, its lamps lit at night, with glass and wheels of
    /// its own, and half the triangles of Hong Kong's taxi or fewer.
    func testTheBundledCarsAreTheirRealSizeAndPainted() throws {
        let taxi = try Map3DModelFile(decoding: Data(contentsOf: Self.models.appendingPathComponent("hk-taxi.m3dmodel")), named: "hk-taxi")
        for model in Map3DTaiwanCars.models {
            let car = try Self.file(model), size = Map3DTaiwanCars.size(model)
            XCTAssertEqual(car.name, model.modelName)
            XCTAssertEqual(car.maximum.x - car.minimum.x, size.length, accuracy: 0.02, "\(model) length")
            XCTAssertEqual(car.maximum.y - car.minimum.y, size.width, accuracy: 0.05, "\(model) width")
            XCTAssertEqual(car.maximum.z, size.height, accuracy: 0.05, "\(model) height")
            XCTAssertEqual(car.minimum.z, 0, accuracy: 0.01, "\(model) on the ground")
            XCTAssertGreaterThan(car.triangleCount, 800, "\(model): a car, not decision 259's box")
            XCTAssertLessThan(car.triangleCount * 3, taxi.model.triangleCount * 2, "\(model): well under Hong Kong's taxi")
            // The body takes the instance's paint, and it is most of what
            // is seen from above.
            let paint = car.vertices.filter { $0.color >> 24 == 0 }
            XCTAssertGreaterThan(paint.count, car.vertices.count / 10, "\(model) paint")
            XCTAssertFalse(car.vertices.contains { $0.color == Map3DTaiwanCars.filePaint }, "\(model): no body left white")
            // Head lamps at the front and tail lamps at the back, lit.
            let lit = car.vertices.filter { $0.layer == Map3DVertex.glowing }
            XCTAssertTrue(lit.contains { $0.color == Map3DStreetModel.headlamp && $0.x > size.length / 2 - 0.3 }, "\(model) head lamps")
            XCTAssertTrue(lit.contains { $0.color == Map3DStreetModel.tailLamp && $0.x < -size.length / 2 + 0.3 }, "\(model) tail lamps")
            // The cabin's side glass runs most of its length (the box's
            // wedge, and the kit's door pane, did not).
            let glass = car.vertices.filter { $0.color == Map3DStreetModel.glass && abs($0.y) > size.width / 2 - 0.35 }
            let reach = (glass.map(\.x).max() ?? 0) - (glass.map(\.x).min() ?? 0)
            XCTAssertGreaterThan(reach, size.length * 0.4, "\(model) side glass")
            // Four wheels standing out of the body: tyre on the ground at
            // both ends and both sides.
            let tyres = car.vertices.filter { $0.color == Map3DStreetModel.tyre && $0.z < 0.05 }
            for (front, left) in [(true, true), (true, false), (false, true), (false, false)] {
                XCTAssertTrue(tyres.contains { ($0.x > 0) == front && ($0.y > 0) == left }, "\(model) wheel \(front) \(left)")
            }
        }
        // Only the taxi has a lit sign on its roof, above the saloon's.
        let sign = try Self.file(.yellowTaxi).vertices.filter { $0.layer == Map3DVertex.glowing && $0.z > 1.5 }
        XCTAssertFalse(sign.isEmpty)
        XCTAssertTrue(sign.allSatisfy { $0.color == Map3DHongKongVehicles.roofSign })
        XCTAssertFalse(try Self.file(.car).vertices.contains { $0.z > 1.5 })
        // The SUV and the van stand taller than the saloon.
        XCTAssertGreaterThan(try Self.file(.suv).maximum.z, try Self.file(.car).maximum.z + 0.1)
        XCTAssertGreaterThan(try Self.file(.van).maximum.z, try Self.file(.suv).maximum.z + 0.1)
    }

    /// The files take the stand-ins' places; one that cannot be read
    /// leaves its stand-in.
    func testTheFilesReplaceTheStandIns() throws {
        let standard = Map3DModelPack.standard
        for model in Map3DTaiwanCars.models {
            let pack = Map3DTaiwanCars.pack(standard, files: [model: try Self.url(model)])
            let index = try XCTUnwrap(pack.index(of: model.modelName))
            XCTAssertEqual(index, standard.index(of: model.modelName))
            XCTAssertEqual(pack.models[index].vertices.count, try Self.file(model).vertices.count, "\(model)")
            XCTAssertEqual(pack.models.count, standard.models.count)
            let missing = Map3DTaiwanCars.pack(standard, files: [model: URL(fileURLWithPath: "/nonexistent")])
            XCTAssertEqual(missing.models[index].vertices, standard.models[index].vertices, "\(model)")
        }
        // The SUV's and the taxi's stand-ins right after Santa's sleigh,
        // before the route bus (decision 840: the reindeer between them;
        // decision 846: then the pedestrian signals with no countdown).
        let sleigh = try XCTUnwrap(standard.index(of: SantaFlight.Model.name))
        XCTAssertEqual(standard.index(of: Map3DStreetModel.suv.modelName), sleigh + 1)
        XCTAssertEqual(standard.index(of: Map3DStreetModel.yellowTaxi.modelName), sleigh + 2)
        let between = Map3DReindeerHerd.drawn.count + Map3DPedestrianSignal.plainDrawn.count + Map3DFinlandStreet.Unit.allCases.count
            + Map3DYellowTit.drawn.count
        XCTAssertEqual(standard.models[sleigh + 3 + between].name, Map3DLowFloorBus.routeModel().name)
    }

    private func vehicles(_ region: Map3DStreetRegion, scooters: Bool) throws -> [Map3DStreetLife.Vehicle] {
        var all: [Map3DStreetLife.Vehicle] = []
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(2_000, 0, 0)]))
        for seed in Int32(0)..<20 {
            let lane = Map3DStreetLife.Lane(path: path, half: 5, twoWay: true, speed: 11, perHundred: 6, scooters: scooters, seed: (seed &* 997, 3))
            for index in 0..<200 {
                all.append(Map3DStreetLife.vehicle(index, of: 200, lane: lane, direction: 1, spacing: 20, buses: false, besides: true,
                                                   region: region))
            }
        }
        return all
    }

    /// Saloons, SUVs and vans about 45, 40 and 15 in a hundred; every car
    /// in the taxis' yellow a taxi with its sign, in Taiwan only.
    func testTaiwansCarsAreSaloonsSUVsVansAndYellowTaxis() throws {
        let yellow = try XCTUnwrap(Map3DStreetLife.carPaints.last)
        for scooters in [false, true] {
            let cars = try vehicles(.taiwan, scooters: scooters).filter { !$0.model.isScooter && !$0.model.isBus }
            let taxis = cars.filter { $0.model == .yellowTaxi }
            XCTAssertTrue(taxis.allSatisfy { $0.tint == yellow })
            XCTAssertFalse(cars.contains { $0.model != .yellowTaxi && $0.tint == yellow }, "a yellow car is a taxi")
            XCTAssertEqual(Float(taxis.count) / Float(cars.count), 1 / Float(Map3DStreetLife.carPaints.count), accuracy: 0.03)
            let private_ = cars.filter { $0.model != .yellowTaxi }
            let share = { (model: Map3DStreetModel) in Float(private_.filter { $0.model == model }.count) / Float(private_.count) }
            XCTAssertEqual(share(.car), 0.45, accuracy: 0.05, "scooters \(scooters)")
            XCTAssertEqual(share(.suv), 0.40, accuracy: 0.05, "scooters \(scooters)")
            XCTAssertEqual(share(.van), 0.15, accuracy: 0.04, "scooters \(scooters)")
        }
        for region in [Map3DStreetRegion.finland, .hongKong] {
            XCTAssertFalse(try vehicles(region, scooters: true).contains { $0.model == .yellowTaxi }, "\(region)")
        }
        XCTAssertTrue(try vehicles(.finland, scooters: false).contains { $0.model == .suv })
    }
}
