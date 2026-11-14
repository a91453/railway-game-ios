import Foundation
@testable import GamePresentation
import XCTest

/// Decision 743: Hong Kong's street traffic: double-deckers, minibuses and
/// taxis, few motorcycles; Taiwan's as before.
final class Map3DHongKongVehiclesTests: XCTestCase {
    private static let models = Map3DRealTrainsTests.resources.appendingPathComponent("Models")
    private let hongKongModels: Set<Map3DStreetModel> = [.doubleDecker, .minibus, .taxi]

    private func lane(seed: Int32) throws -> Map3DStreetLife.Lane {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(2_000, 0, 0)]))
        var lane = Map3DStreetLife.Lane(path: path, half: 5, twoWay: true, speed: 11, perHundred: 6, scooters: true, seed: (seed, 7))
        lane.buses = true
        return lane
    }

    private func vehicles(_ region: Map3DStreetRegion) throws -> [Map3DStreetLife.Vehicle] {
        var all: [Map3DStreetLife.Vehicle] = []
        for seed in Int32(0)..<20 {
            let lane = try lane(seed: seed)
            for index in 0..<200 {
                all.append(Map3DStreetLife.vehicle(index, of: 200, lane: lane, direction: 1, spacing: 20, buses: true, besides: true,
                                                   region: region))
            }
        }
        return all
    }

    func testHongKongsTrafficIsTaxisMinibusesAndDoubleDeckers() throws {
        let hongKong = try vehicles(.hongKong)
        let share = { (model: Map3DStreetModel) in Float(hongKong.filter { $0.model == model }.count) / Float(hongKong.count) }
        XCTAssertEqual(share(.taxi), 0.25, accuracy: 0.04)
        XCTAssertEqual(share(.minibus), 0.05, accuracy: 0.02)
        XCTAssertGreaterThan(share(.doubleDecker), 0)
        // Few motorcycles, none two up or beside another.
        XCTAssertLessThan(hongKong.filter(\.model.isScooter).count, hongKong.count / 20)
        XCTAssertTrue(hongKong.allSatisfy { $0.beside == nil && $0.model != .stepScooterPair && $0.model != .scooterPair })
        // No Taiwanese single-deck city buses; one bus in seven single-deck.
        let buses = hongKong.filter(\.model.isBus)
        XCTAssertTrue(buses.allSatisfy { $0.model == .doubleDecker || $0.model == .midiBus })
        // The taxis in their three colours, red the most.
        let taxis = hongKong.filter { $0.model == .taxi }.map(\.tint)
        XCTAssertGreaterThan(taxis.filter { $0 == Map3DHongKongVehicles.taxiPaints[0].paint }.count, taxis.count * 3 / 4)
        XCTAssertTrue(taxis.contains(Map3DHongKongVehicles.taxiPaints[1].paint))
        // Taiwan's has none of them.
        XCTAssertTrue(try vehicles(.taiwan).allSatisfy { !hongKongModels.contains($0.model) })
    }

    func testTheirStandInsAreInThePackAfterHongKongsSignals() throws {
        let pack = Map3DModelPack.standard
        let lastSignal = try XCTUnwrap(pack.index(of: Map3DHongKongSignal.modelName(try XCTUnwrap(Map3DSignalTiming.Light.allCases.last))))
        for (offset, model) in Map3DHongKongVehicles.models.enumerated() {
            let index = try XCTUnwrap(pack.index(of: model.modelName))
            XCTAssertEqual(index, lastSignal + 1 + offset)
            let size = Map3DHongKongVehicles.size(model), drawn = pack.models[index]
            XCTAssertEqual(drawn.maximum.x - drawn.minimum.x, size.length, accuracy: 0.15, "\(model)")
            XCTAssertEqual(drawn.minimum.z, 0, accuracy: 0.01, "\(model)")
        }
    }

    func testTheBundledFilesAreFittedAndPainted() throws {
        for model in Map3DHongKongVehicles.models {
            let name = try XCTUnwrap(Map3DHongKongVehicles.fileNames[model])
            let url = Self.models.appendingPathComponent(name + "." + Map3DHongKongVehicles.fileExtension)
            let file = try Map3DModelFile(decoding: Data(contentsOf: url), named: name)
            let fitted = Map3DHongKongVehicles.model(model, from: file)
            let size = Map3DHongKongVehicles.size(model)
            XCTAssertEqual(fitted.name, model.modelName)
            XCTAssertEqual(fitted.maximum.x - fitted.minimum.x, size.length, accuracy: 0.01, "\(model)")
            XCTAssertEqual(fitted.maximum.y - fitted.minimum.y, size.width, accuracy: 0.01, "\(model)")
            XCTAssertEqual(fitted.minimum.z, 0, accuracy: 0.01, "\(model)")
            let painted = fitted.vertices.filter { $0.color >> 24 == 0 }
            XCTAssertFalse(painted.isEmpty, "\(model) has paint")
            switch model {
            case .minibus:
                // Only its roof takes the paint (red or green).
                XCTAssertTrue(painted.allSatisfy { $0.z > size.height - 0.6 }, "the minibus's paint is its roof")
            case .taxi:
                XCTAssertTrue(fitted.vertices.contains { $0.color == Map3DHongKongVehicles.roofSilver })
                XCTAssertTrue(fitted.vertices.contains { $0.color == Map3DHongKongVehicles.roofSign })
            default: break
            }
            // In the pack in place of the stand-in.
            let pack = Map3DHongKongVehicles.pack(.standard, files: [model: url])
            XCTAssertEqual(pack.models[try XCTUnwrap(pack.index(of: model.modelName))].vertices.count, fitted.vertices.count)
        }
    }

    func testHongKongHasNoEveningGarbageTrucksOrTaiwansPostBoxes() {
        XCTAssertTrue(Map3DStreetRegion.taiwan.hasEveningGarbageTrucks)
        XCTAssertFalse(Map3DStreetRegion.hongKong.hasEveningGarbageTrucks)
        XCTAssertTrue(Map3DStreetRegion.taiwan.hasTaiwanPostBoxes)
        XCTAssertFalse(Map3DStreetRegion.hongKong.hasTaiwanPostBoxes)
    }
}
