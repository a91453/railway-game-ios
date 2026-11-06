import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 615 (CABLE-SUNMOON): the Sun Moon Lake Ropeway's cabins, their
/// see-through glass, and which cable cars run them.
final class Map3DSunMoonCabinTests: XCTestCase {
    static let sunMoon = ScreenshotScene.sunMoonLake.make(in: .traditionalChinese)
    static let maokong = ScreenshotScene.maokong.make(in: .traditionalChinese)

    func testEveryCabinIsClosedSolidsUnderItsBudget() {
        for kind in Map3DCableCar.SunMoonCabin.allCases {
            for far in [false, true] {
                XCTAssertEqual(CableSolids.sunMoonCabin(kind, far: far).openSolids(), [], "\(kind) far \(far)")
            }
            let near = Map3DCableCar.model(kind), far = Map3DCableCar.model(kind, far: true)
            XCTAssertEqual(near.name, "cablecar-cabin-sunmoon-" + kind.rawValue)
            XCTAssertEqual(far.name, near.name + "-far")
            XCTAssertLessThan(near.triangleCount, 9_000, near.name)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(kind): far under half")
            XCTAssertEqual(near.vertices, Map3DCableCar.model(kind).vertices, "the same every time")
        }
    }

    /// The grip on the rope at the origin and the floor as low as the
    /// Maokong cabin's, so it is level with the halls' platforms.
    func testItHangsAsTheMaokongCabinDoes() {
        for kind in Map3DCableCar.SunMoonCabin.allCases {
            let m = Map3DCableCar.model(kind)
            XCTAssertEqual(m.maximum.z, 0.24, accuracy: 0.05, "\(kind): the opener over the grip")
            // The benches' feet stand on the floor.
            let feet = m.vertices.filter { $0.nz < -0.9 && $0.color == Map3DCableCar.SunMoonPaint.steel && abs(abs($0.x) - 0.86) < 0.05 && abs(abs($0.y) - 0.45) < 0.06 && $0.z < -4 && $0.z > -4.42 }
            XCTAssertFalse(feet.isEmpty, "\(kind)")
            XCTAssertTrue(feet.allSatisfy { abs($0.z - CableParts.cabinFloor) < 0.001 }, "\(kind): the floor")
            XCTAssertEqual(m.maximum.x - m.minimum.x, 2.20, accuracy: 0.15, "\(kind): the body's length")
        }
    }

    /// The windows are see-through glass in both cabins' kinds, the crystal
    /// floors clearer than the windows, the standard floors not glass.
    func testTheGlassIsSeeThrough() {
        func glass(_ m: Map3DModelPack.Model) -> [Map3DVertex] { m.vertices.filter(\.isTransparentGlass) }
        let models = Map3DCableCar.SunMoonCabin.allCases.map { Map3DCableCar.model($0) }
            + Map3DCableCar.Cabin.allCases.map { Map3DCableCar.model($0) }
        for m in models {
            let panes = glass(m)
            XCTAssertGreaterThan(panes.count, 300, m.name)
            XCTAssertTrue(panes.allSatisfy { $0.u > 0 && $0.u <= 0.14 }, m.name)
            XCTAssertFalse(m.vertices.contains { $0.layer == Map3DVertex.trainGlass }, "\(m.name): none left opaque")
            let floor = panes.filter { abs($0.nz) > 0.9 && $0.z < CableParts.cabinFloor + 0.001 }
            if m.name.contains("crystal") {
                XCTAssertFalse(floor.isEmpty, "\(m.name): a glass floor")
                XCTAssertTrue(floor.allSatisfy { $0.u == Map3DTransparentGlass.Style().floor }, m.name)
            } else {
                XCTAssertTrue(floor.isEmpty, "\(m.name): a solid floor")
            }
        }
        XCTAssertFalse(Map3DTransparentGlass.Cache(models: models).isEmpty)
    }

    func testTheLiveriesTakeTurnsAndTheCrystalOnesStayCrystal() {
        var seen: Set<Map3DCableCar.SunMoonCabin> = []
        for number in 0..<60 {
            let livery = Map3DCableCar.sunMoonCabin(number)
            seen.insert(livery)
            XCTAssertEqual(livery == .crystal, CablewayCabins.isCrystal(number), "\(number)")
        }
        XCTAssertEqual(seen, Set(Map3DCableCar.SunMoonCabin.allCases))
    }

    /// Where the cable car is picks its cabins: the ropeway at Sun Moon
    /// Lake runs Sun Moon Lake's, Maokong's gondola Maokong's, and a cable
    /// car laid 6 km from the ropeway's stations Maokong's too.
    func testThePlacePicksTheCabins() throws {
        let lake = try XCTUnwrap(Self.sunMoon.cableways.first)
        XCTAssertEqual(lake.stops.count, 2)
        XCTAssertEqual(Map3DCableways.look(of: lake, in: Self.sunMoon), .sunMoonLake)
        XCTAssertEqual(Map3DCableways.look(of: try XCTUnwrap(Self.maokong.cableways.first), in: Self.maokong), .maokong)
        XCTAssertEqual(RealCableway.matching(lake, in: Self.sunMoon), .sunMoonLake)
        // Moved west (a world unit is a millimetre).
        let units = Int64(WorldCoordinate.unitsPerMetre)
        func moved(_ metres: Int64) -> [CablewayStop] {
            lake.stops.map { stop in
                let p = stop.cell.middle
                return CablewayStop(cell: CellPosition(containing: PlanPoint(x: p.x - metres * units, y: p.y)), boards: stop.boards)
            }
        }
        XCTAssertEqual(Map3DCableways.look(ofStops: moved(4_000), in: Self.sunMoon), .sunMoonLake, "the lake's west shore")
        XCTAssertEqual(Map3DCableways.look(ofStops: moved(8_000), in: Self.sunMoon), .maokong, "past the reach of both stations")
    }

    /// The 3D map draws the Sun Moon Lake cabins on the ropeway there,
    /// never Maokong's, and the frame stays under the cable cars' cap.
    func testTheFrameDrawsSunMoonLakeCabins() throws {
        let scene = Map3DScene(world: Self.sunMoon)
        let laid = Map3DCableways(world: Self.sunMoon, scene: scene)
        let pack = Map3DModelPack.standard
        let line = try XCTUnwrap(laid.lines.first)
        let sunMoon = Set(Map3DCableCar.SunMoonCabin.allCases.flatMap { [$0.rawValue, $0.rawValue + "-far"] }
            .compactMap { pack.index(of: "cablecar-cabin-sunmoon-" + $0) })
        XCTAssertEqual(sunMoon.count, 8)
        let maokong = Set(["standard", "crystal", "standard-far", "crystal-far"].compactMap { pack.index(of: "cablecar-cabin-" + $0) })
        let middle = Map3DCableways.ropePoint(line.spans[0], share: 0.5)
        let frame = laid.frame(second: 10 * 3_600 + 7, eye: middle + Map3DPoint(60, 40, 0), target: middle, pack: pack)
        let cabins = frame.instances.filter { sunMoon.contains($0.model) || maokong.contains($0.model) }
        XCTAssertGreaterThan(cabins.count, 4)
        XCTAssertTrue(cabins.allSatisfy { sunMoon.contains($0.model) })
        XCTAssertEqual(cabins.count, frame.nearCabins + frame.farCabins)
        XCTAssertLessThanOrEqual(frame.nearCabins, Map3DCableways.mostNearSunMoonCabins)
        XCTAssertLessThanOrEqual(frame.farCabins, Map3DCableways.mostFarSunMoonCabins)
        XCTAssertLessThan(frame.instances.reduce(0) { $0 + pack.models[$1.model].triangleCount }, 260_000)
    }
}
