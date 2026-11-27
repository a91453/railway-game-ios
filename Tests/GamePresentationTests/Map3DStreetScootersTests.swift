import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1037: the studio's scooters and riders, and how many of a
/// street's vehicles are scooters where.
final class Map3DStreetScootersTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    /// The ridden ones are the studio's, one mesh each with its rider, in
    /// the game's colours, the paint the instance's, the lamps lit; the
    /// far ones no more than decision 259's blocks.
    func testTheStudiosScootersDecode() throws {
        let limits: [Map3DStreetModel: Int] = [.stepScooter: 700, .electricScooter: 700, .deliveryScooter: 700, .stepScooterPair: 830,
                                               .scooter: 160, .scooterPair: 210]
        for (kind, most) in limits {
            let model = try XCTUnwrap(Map3DScooterModels.model(kind), "\(kind)")
            XCTAssertEqual(model.name, kind.modelName)
            XCTAssertEqual(pack.models[try XCTUnwrap(pack.index(of: kind.modelName))].triangleCount, model.triangleCount, "\(kind): the pack's")
            XCTAssertLessThanOrEqual(model.triangleCount, most, "\(kind)")
            XCTAssertTrue(model.vertices.allSatisfy { Map3DScooterModels.palette.contains($0.color) }, "\(kind)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, "\(kind) on its wheels")
            XCTAssertTrue(model.vertices.contains { $0.color >> 24 == 0 }, "\(kind): its paint")
            XCTAssertTrue((1.4...2.0).contains(model.length), "\(kind): \(model.length) m")
            XCTAssertTrue((1.3...1.8).contains(model.maximum.z), "\(kind): \(model.maximum.z) m, the helmet")
            if kind.far != kind { XCTAssertTrue(model.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(kind): its lamps") }
        }
        // Two up, no top case where the pillion sits; alone, one.
        let alone = try XCTUnwrap(Map3DScooterModels.model(.stepScooter)), two = try XCTUnwrap(Map3DScooterModels.model(.stepScooterPair))
        XCTAssertTrue(alone.vertices.contains { $0.color == Map3DScooter.topCase })
        XCTAssertFalse(two.vertices.contains { $0.color == Map3DScooter.topCase })
        XCTAssertTrue(two.vertices.contains { $0.color == Map3DStreetModel.pillionShirt })
        XCTAssertNil(Map3DScooterModels.model(.car))
    }

    /// The share of the drawn vehicles that are scooters, on a long road
    /// both ways (the ones riding beside another counted): within 3 points
    /// of Taipei's 46%, the rest of Taiwan's 57%, Japan's and Hong Kong's
    /// 3%, and none in Finland; Japan's and Hong Kong's the step-through
    /// alone, none two up or beside another.
    func testTheShareOfScooters() throws {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(4_000, 0, 0)]))
        let scooters = Set(Map3DStreetModel.allCases.filter(\.isScooter).compactMap { pack.index(of: $0.modelName) })
        let twoUp = Set([Map3DStreetModel.stepScooterPair, .scooterPair].compactMap { pack.index(of: $0.modelName) })
        let stepThrough = Set([Map3DStreetModel.stepScooter, .scooter].compactMap { pack.index(of: $0.modelName) })
        for (region, taipei, share) in [(Map3DStreetRegion.taiwan, true, 0.46), (.taiwan, false, 0.57), (.japan, false, 0.03),
                                        (.hongKong, false, 0.03), (.finland, false, 0)] {
            var life = Map3DStreetLife()
            life.region = region
            var lane = Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 11, perHundred: 6, scooters: true, seed: (1, 2))
            lane.taipei = taipei
            life.lanes = [lane]
            var drawn = 0, scootersDrawn = 0, pairs = 0, others = 0
            for x in stride(from: Float(200), to: 3_800, by: 300) {
                let frame = life.frame(target: Map3DPoint(x, 0, 0), distance: 150, time: 77, detail: .full, activity: .init(),
                                       limits: Map3DStreetLimits(people: 0, vehicles: 100_000, buses: 30))
                for instance in frame.instances {
                    drawn += 1
                    guard scooters.contains(instance.model) else { continue }
                    scootersDrawn += 1
                    if twoUp.contains(instance.model) { pairs += 1 }
                    if !stepThrough.contains(instance.model) { others += 1 }
                }
            }
            XCTAssertGreaterThan(drawn, 800, "\(region)")
            XCTAssertEqual(Double(scootersDrawn) / Double(drawn), share, accuracy: 0.03, "\(region), Taipei \(taipei)")
            if region == .taiwan {
                XCTAssertGreaterThan(pairs, 0)
                XCTAssertGreaterThan(others, 0, "the e-scooter and the delivery one")
            } else {
                XCTAssertEqual(pairs, 0, "\(region)")
                XCTAssertEqual(others, 0, "\(region): the 125 cc step-through alone")
            }
        }
        XCTAssertEqual(Map3DStreetScooters.slotShare(drawn: 0.46), 0.3846, accuracy: 0.001)
        XCTAssertEqual(Map3DStreetScooters.slotShare(drawn: 0.57), 0.4931, accuracy: 0.001)
    }

    /// Taipei City's outline holds its districts and not New Taipei's.
    func testTaipeiCitysOutline() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let outline = try XCTUnwrap(Map3DStreetScooters.taipei(in: frame, region: .taiwan))
        func inside(_ latitude: Double, _ longitude: Double) -> Bool {
            let at = frame.worldPosition(latitude: latitude, longitude: longitude)
            return Map3DStreetScooters.contains(outline, x: at.x, y: at.y)
        }
        XCTAssertTrue(inside(25.0478, 121.5170), "Taipei Main Station")
        XCTAssertTrue(inside(25.0421, 121.5079), "Ximending")
        XCTAssertTrue(inside(25.0330, 121.5654), "Taipei 101")
        XCTAssertTrue(inside(25.1316, 121.4987), "Beitou")
        XCTAssertFalse(inside(25.0143, 121.4672), "Banqiao, New Taipei")
        XCTAssertFalse(inside(25.0626, 121.4589), "Sanchong, New Taipei")
        XCTAssertFalse(inside(24.9910, 121.5100), "Yonghe, New Taipei")
        XCTAssertFalse(inside(22.6273, 120.3014), "Kaohsiung")
        XCTAssertNil(Map3DStreetScooters.taipei(in: frame, region: .japan))
        XCTAssertNil(Map3DStreetScooters.taipei(in: nil, region: .taiwan))
    }

    /// Decision 1037: the full scooters nearer, so a street costs no more
    /// triangles than with the program's ones at 350 m.
    func testTheFullScootersReach() {
        XCTAssertEqual(Map3DScooter.detailReach(in: .taiwan), 240)
        XCTAssertEqual(Map3DScooter.detailReach(in: .hongKong), 150)
        XCTAssertEqual(Map3DScooter.detailReach(in: .japan), 150)
    }
}
