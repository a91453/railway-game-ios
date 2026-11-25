import GameCore
import XCTest
@testable import GamePresentation

/// Decision 986: the Keikyu New 1000 at its real 18 m
/// (``Map3DKeikyuNew1000``), the train of the type `KEIKYU1000`: the
/// general train's 20 m cars (``Map3DRedCommuter``) shortened as a whole,
/// their wheels where the gauge puts them.
final class Map3DKeikyuNew1000At18Tests: XCTestCase {
    /// Each 18 m car beside the 20 m car it was made from, near and far.
    private func pairs() throws -> [(name: String, short: Map3DModelPack.Model, long: Map3DModelPack.Model)] {
        var pairs: [(name: String, short: Map3DModelPack.Model, long: Map3DModelPack.Model)] = []
        for far in [false, true] {
            pairs.append(("cab" + (far ? " far" : ""), try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far)),
                          try XCTUnwrap(Map3DRedCommuter.cab(far: far))))
            pairs.append(("middle" + (far ? " far" : ""), try XCTUnwrap(Map3DKeikyuNew1000.middle(far: far)),
                          try XCTUnwrap(Map3DRedCommuter.middle(far: far))))
        }
        return pairs
    }

    /// Where along the car each wheel's foot is (the vertices under
    /// 0.30 m, below the bogie frames), front to back.
    private func wheels(_ model: Map3DModelPack.Model) -> [ClosedRange<Float>] {
        var found: [ClosedRange<Float>] = []
        for x in model.vertices.filter({ $0.z < 0.30 }).map(\.x).sorted() {
            if let last = found.last, x - last.upperBound < 0.5 {
                found[found.count - 1] = last.lowerBound...x
            } else {
                found.append(x...x)
            }
        }
        return found
    }

    /// 18.00 m from coupler to coupler; across and upward the 20 m car's
    /// own size (2.80 m wide, 3.904 m tall), its triangles and its
    /// colours.
    func testEveryCarIsEighteenMetresAndOtherwiseTheTwentyMetreCars() throws {
        for (name, short, long) in try pairs() {
            XCTAssertEqual(short.minimum.x, -9.00, accuracy: 0.005, name)
            XCTAssertEqual(short.maximum.x, 9.00, accuracy: 0.005, name)
            XCTAssertEqual(short.length, Map3DKeikyuNew1000.carLength, accuracy: 0.005, name)
            XCTAssertEqual(short.minimum.y, long.minimum.y, accuracy: 0.001, name)
            XCTAssertEqual(short.maximum.y, long.maximum.y, accuracy: 0.001, name)
            XCTAssertEqual(short.maximum.y, 1.40, accuracy: 0.005, name)
            XCTAssertEqual(short.minimum.z, 0, accuracy: 0.002, name)
            XCTAssertEqual(short.maximum.z, long.maximum.z, accuracy: 0.001, name)
            XCTAssertEqual(short.triangleCount, long.triangleCount, name)
            XCTAssertEqual(Set(short.vertices.map(\.color)), Set(long.vertices.map(\.color)), name)
            XCTAssertEqual(short.vertices.filter(\.glows).count, long.vertices.filter(\.glows).count, name)
        }
    }

    /// The wheels were moved, not squashed: each is as long as the 20 m
    /// car's, a bogie's two axles are as far apart (2.125 m), the bogie's
    /// middle is nine tenths as far from the car's, and a wheel's tread
    /// stands 0.630 to 0.805 m from the middle of the track, so an axle's
    /// two wheels are 1.435 m apart, centre to centre.
    func testTheWheelsStayRoundAndOnTheGauge() throws {
        for (name, short, long) in try pairs() {
            let shortWheels = wheels(short), longWheels = wheels(long)
            XCTAssertEqual(shortWheels.count, 4, name)
            XCTAssertEqual(longWheels.count, 4, name)
            guard shortWheels.count == 4, longWheels.count == 4 else { continue }
            func middle(_ range: ClosedRange<Float>) -> Float { (range.lowerBound + range.upperBound) / 2 }
            for (a, b) in zip(shortWheels, longWheels) {
                XCTAssertEqual(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound, accuracy: 0.002, "\(name): a wheel's length")
            }
            for bogie in [0, 2] {
                let base = middle(shortWheels[bogie + 1]) - middle(shortWheels[bogie])
                XCTAssertEqual(base, 2.125, accuracy: 0.005, "\(name): a bogie's wheelbase")
                XCTAssertEqual(base, middle(longWheels[bogie + 1]) - middle(longWheels[bogie]), accuracy: 0.002, name)
                let centre = (middle(shortWheels[bogie]) + middle(shortWheels[bogie + 1])) / 2
                let before = (middle(longWheels[bogie]) + middle(longWheels[bogie + 1])) / 2
                XCTAssertEqual(centre, before * 0.9, accuracy: 0.005, "\(name): the bogie's place")
            }
            let feet = short.vertices.filter { $0.z < 0.30 }.map { abs($0.y) }
            XCTAssertEqual(feet.min() ?? 0, 0.630, accuracy: 0.002, name)
            XCTAssertEqual(feet.max() ?? 0, 0.805, accuracy: 0.002, name)
            XCTAssertEqual((feet.min() ?? 0) + (feet.max() ?? 0), 1.435, accuracy: 0.003, "\(name): the gauge")
        }
    }

    /// The lamps are the cab's own lenses at its face, the white band and
    /// the body where the 20 m car has them.
    func testTheLampsAndTheBandAreWhereTheyWere() throws {
        for far in [false, true] {
            let cab = try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far))
            let lit = cab.vertices.filter(\.glows)
            XCTAssertTrue(lit.contains { $0.color == Map3DTrainStyle.headlamp })
            XCTAssertTrue(lit.contains { $0.color == Map3DPalette.lantern })
            XCTAssertGreaterThan(lit.map(\.x).min() ?? 0, 8.8)
            XCTAssertFalse(try XCTUnwrap(Map3DKeikyuNew1000.middle(far: far)).vertices.contains(where: \.glows))
        }
        let middle = try XCTUnwrap(Map3DKeikyuNew1000.middle())
        let side = middle.vertices.filter { abs($0.x) < 7 && $0.y > 1.39 }
        let white = side.filter { $0.color == Map3DPalette.acUnit }.map(\.z)
        XCTAssertEqual(white.min() ?? 0, 1.915, accuracy: 0.01)
        XCTAssertEqual(white.max() ?? 0, 3.24, accuracy: 0.01)
        XCTAssertTrue(side.contains { $0.color == Map3DTrainStyle.glass && $0.layer == Map3DVertex.trainGlass })
    }

    /// The type's train is this set, laid at its own 18 m a car with no
    /// gap, the cab turned round at the back, and a far set of its own.
    func testTheTypesTrainIsLaidAtEighteenMetresACar() throws {
        XCTAssertEqual(Map3DTrainSet.byType[TrainType.keikyuNew1000.rawValue], Map3DKeikyuNew1000.key)
        let set = try XCTUnwrap(Map3DTrainSet.byKey[Map3DKeikyuNew1000.key])
        XCTAssertTrue(set.ownLengths)
        XCTAssertEqual(set.far, Map3DKeikyuNew1000.key + "Far")
        XCTAssertNotNil(Map3DTrainSet.byKey[Map3DKeikyuNew1000.key + "Far"])
        let pack = Map3DModelPack.standard
        for count in [4, 6, 8, 12] {
            let layout = try XCTUnwrap(pack.layout(forType: TrainType.keikyuNew1000.rawValue, count: count), "\(count) cars")
            XCTAssertEqual(layout.count, count)
            for car in layout {
                XCTAssertEqual(car.length, 18.00, accuracy: 0.005)
                XCTAssertEqual(car.gap, 0, accuracy: 0.005)
            }
            XCTAssertEqual(pack.models[layout[0].model].name, "set-keikyuNew1000-head")
            XCTAssertEqual(pack.models[layout[count - 1].model].name, "set-keikyuNew1000-tail")
        }
        XCTAssertEqual(Map3DShowcase.entry(Map3DKeikyuNew1000.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DKeikyuNew1000.key)?.chinese, "京急新1000形")
    }

    /// The fit the change is for: the length the game gives a car of the
    /// type (its slot on the track and at a platform) is the length the
    /// car is drawn, so an eight-car train takes 144 m of both; and the
    /// car stands as the 20 m car does beside a platform and under the
    /// game's structures.
    func testTheDrawnCarFillsTheTypesSlotAndClearsThePlatform() throws {
        let slot = Float(TrainType.keikyuNew1000.carLength) / Float(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(slot, Map3DKeikyuNew1000.carLength, accuracy: 0.001)
        let cab = try XCTUnwrap(Map3DKeikyuNew1000.cab())
        XCTAssertEqual(cab.length, slot, accuracy: 0.005)
        XCTAssertLessThan(cab.maximum.y, Map3DScene.Builder.platformEdge)
        XCTAssertEqual(Map3DScene.Builder.platformHeight - 1.00, 0.15, accuracy: 0.001)
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.contactHeight)
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.boreCrown)
    }

    /// The general train of four cars or more keeps its 20 m cars: this
    /// change does not move it.
    func testTheGeneralTrainKeepsItsTwentyMetreCars() throws {
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: "", count: 4))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 80.0, accuracy: 0.05)
        XCTAssertEqual(pack.models[layout[0].model].name, "set-redCommuter-head")
    }
}
