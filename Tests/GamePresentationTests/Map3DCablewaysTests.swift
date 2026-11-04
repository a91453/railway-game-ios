import GameCore
@testable import GamePresentation
import XCTest

/// Decision 575 續 (CABLEMAP): the Maokong Gondola laid in the 3D map:
/// where its halls, towers and cabins stand, which are drawn whole and
/// which far, and how many triangles a frame takes at most.
final class Map3DCablewaysTests: XCTestCase {
    static let world = ScreenshotScene.maokong.make(in: .traditionalChinese)
    static let scene = Map3DScene(world: world)
    static let laid = Map3DCableways(world: world, scene: scene)
    static var pack: Map3DModelPack { Map3DModelPack.standard }

    func index(_ name: String) -> Int { Self.pack.index(of: name)! }

    func testTheDrawnModelsAreInTheGamesPackAndTheRestInTheStudies() {
        for model in Map3DCableCar.drawn {
            XCTAssertNotNil(Map3DModelPack.standard.index(of: model.name), model.name)
            XCTAssertNil(Map3DModelPack.studies.index(of: model.name), model.name)
        }
        for model in Map3DCableCar.studyModels {
            XCTAssertNotNil(Map3DModelPack.studies.index(of: model.name), model.name)
            XCTAssertNil(Map3DModelPack.standard.index(of: model.name), model.name)
        }
        XCTAssertNotNil(Map3DCableways.Models(Self.pack))
    }

    func testEachStopHasItsHallAndEachSpanItsTowers() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let gondola = try XCTUnwrap(Self.world.cableways.first)
        XCTAssertEqual(line.halls.count, gondola.stops.count)
        XCTAssertEqual(line.halls.first?.kind, .terminal)
        XCTAssertEqual(line.halls.last?.kind, .terminal)
        XCTAssertEqual(line.spans.count, gondola.legMetres.count)
        for (leg, span) in line.spans.enumerated() {
            // No two supports farther apart than the towers' spacing.
            for (a, b) in zip(span.supports, span.supports.dropFirst()) {
                XCTAssertLessThanOrEqual(Map3DPoint(b.x - a.x, 0, b.z - a.z).length, Map3DCableways.towerSpacing + 0.5, "leg \(leg)")
            }
            XCTAssertEqual(span.towers.count, span.supports.count - 2)
            // The ropes leave the halls at the station's rope height and
            // cross the towers at theirs.
            XCTAssertEqual(span.supports[0].y - line.halls[leg].foot.y, Map3DCableCar.stationRopeHeight, accuracy: 0.01)
            for (tower, support) in zip(span.towers, span.supports.dropFirst()) {
                XCTAssertEqual(support.y - tower.y, Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight), accuracy: 0.01)
            }
        }
        // Maokong's 4 km want some 47 towers.
        XCTAssertEqual(line.spans.reduce(0) { $0 + $1.towers.count }, 47, accuracy: 6)
    }

    func testTheRopeSagsBetweenSupportsAndMeetsThem() throws {
        let span = try XCTUnwrap(Self.laid.lines.first?.spans.first)
        let pieces = Float(span.supports.count - 1)
        for (i, support) in span.supports.enumerated() {
            let p = Map3DCableways.ropePoint(span, share: Float(i) / pieces)
            XCTAssertEqual((p - support).length, 0, accuracy: 0.01)
        }
        let a = span.supports[0], b = span.supports[1]
        let middle = Map3DCableways.ropePoint(span, share: 0.5 / pieces)
        XCTAssertLessThan(middle.y, (a.y + b.y) / 2)
    }

    /// A cabin on a span hangs from its rope: outbound on the right of the
    /// way to the last stop, back on the left, facing the way it goes.
    func testTheCabinsRideTheirRopes() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let eye = line.spans[1].supports[1] + Map3DPoint(0, 40, 0)
        let frame = Self.laid.frame(second: 10 * 3_600, eye: eye, target: line.spans[1].supports[1], pack: Self.pack)
        let cabinModels = Set(["cablecar-cabin-standard", "cablecar-cabin-crystal", "cablecar-cabin-standard-far", "cablecar-cabin-crystal-far"]
            .map(index))
        let cabins = frame.instances.filter { cabinModels.contains($0.model) }
        XCTAssertEqual(cabins.count, frame.nearCabins + frame.farCabins)
        XCTAssertGreaterThan(frame.nearCabins, 0)
        var onARope = 0
        for cabin in cabins {
            let at = Map3DPoint(cabin.transform[12], cabin.transform[13], cabin.transform[14])
            let facing = Map3DPoint(cabin.transform[0], cabin.transform[1], cabin.transform[2])
            for span in line.spans {
                let a = span.supports.first!, b = span.supports.last!
                let flat = Map3DPoint(b.x - a.x, 0, b.z - a.z)
                let share = Map3DPoint(at.x - a.x, 0, at.z - a.z).dot(flat) / flat.dot(flat)
                guard share > 0.02, share < 0.98 else { continue }
                let middle = Map3DCableways.ropePoint(span, share: share)
                let across = Map3DPoint(at.x - middle.x, 0, at.z - middle.z).dot(span.left)
                guard abs(abs(across) - Map3DCableCar.ropeSpacing / 2) < 0.05 else { continue }
                XCTAssertEqual(at.y, middle.y, accuracy: 0.3, "on the rope")
                // Right of the way it faces: its facing crossed with its
                // offset points down.
                XCTAssertEqual(facing.dot(span.along) > 0, across < 0, "outbound on the right")
                onARope += 1
            }
        }
        XCTAssertGreaterThan(onARope, 0)
    }

    /// Decision 358: whole near the eye, far beyond, nothing past the far
    /// reach; a weak device's nearer reach makes more far.
    func testFarModelsBeyondTheNearReachAndNothingPastTheFar() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let target = line.spans[1].supports[1]
        let near = Self.laid.frame(second: 10 * 3_600, eye: target + Map3DPoint(0, 80, 80), target: target, pack: Self.pack)
        let tower = index("cablecar-tower"), towerFar = index("cablecar-tower-far")
        let eye = target + Map3DPoint(0, 80, 80)
        for instance in near.instances where instance.model == tower || instance.model == towerFar {
            let at = Map3DPoint(instance.transform[12], instance.transform[13], instance.transform[14])
            XCTAssertEqual(instance.model == tower, (at - eye).length < Map3DCableways.nearReach)
            XCTAssertLessThan((at - eye).length, Map3DCableways.farReach)
        }
        let weak = Self.laid.frame(second: 10 * 3_600, eye: eye, target: target, pack: Self.pack, reach: 0.5)
        XCTAssertLessThanOrEqual(weak.nearCabins, near.nearCabins)
        XCTAssertLessThan(weak.instances.filter { $0.model == tower }.count, near.instances.filter { $0.model == tower }.count)
        // From far over the next town, nothing.
        let away = Self.laid.frame(second: 10 * 3_600, eye: target + Map3DPoint(0, 500, 6_000), target: target + Map3DPoint(0, 0, 6_000),
                                   pack: Self.pack)
        XCTAssertTrue(away.instances.isEmpty)
    }

    /// At most ``Map3DCableways/mostNearCabins`` whole and
    /// ``Map3DCableways/mostFarCabins`` far in any frame, the ones in
    /// front of the camera first: the frame's triangles stay under
    /// 260,000 wherever the eye is along the line.
    func testAFramesTrianglesAreCapped() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let cabinModels = Set(["cablecar-cabin-standard", "cablecar-cabin-crystal"].map(index))
        var most = 0
        for span in line.spans {
            for support in span.supports {
                for lift: Float in [30, 120, 600] {
                    let eye = support + Map3DPoint(lift, lift, 0)
                    let frame = Self.laid.frame(second: 10 * 3_600 + 7, eye: eye, target: support, pack: Self.pack)
                    XCTAssertLessThanOrEqual(frame.nearCabins, Map3DCableways.mostNearCabins)
                    XCTAssertLessThanOrEqual(frame.farCabins, Map3DCableways.mostFarCabins)
                    XCTAssertEqual(frame.instances.filter { cabinModels.contains($0.model) }.count, frame.nearCabins)
                    let triangles = frame.instances.reduce(0) { $0 + Self.pack.models[$1.model].triangleCount }
                    most = max(most, triangles)
                }
            }
        }
        XCTAssertLessThan(most, 260_000)
        XCTAssertGreaterThan(CablewayCabins.count(of: Self.world.cableways[0]), Map3DCableways.mostNearCabins + Map3DCableways.mostFarCabins)
    }

    /// The cabins in front of the camera come before those behind it:
    /// where more are near than are drawn whole, looking either way
    /// along the line draws more of them ahead than behind.
    func testTheCabinsInFrontComeFirst() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let hall = line.halls[1]
        let eye = hall.foot + Map3DPoint(0, 30, 0)
        let near = Set(["cablecar-cabin-standard", "cablecar-cabin-crystal"].map(index))
        for look in [hall.along, -hall.along] {
            let frame = Self.laid.frame(second: 10 * 3_600, eye: eye, target: hall.foot + look * 100, pack: Self.pack)
            XCTAssertEqual(frame.nearCabins, Map3DCableways.mostNearCabins, "more near than drawn whole")
            let whole = frame.instances.filter { near.contains($0.model) }
            let ahead = whole.filter { Map3DPoint($0.transform[12] - eye.x, 0, $0.transform[14] - eye.z).dot(look) > 0 }
            XCTAssertGreaterThan(ahead.count, whole.count - ahead.count)
        }
    }

    func testTheSameMomentIsTheSameFrame() {
        let line = Self.laid.lines[0]
        let a = Self.laid.frame(second: 40_000.25, eye: line.halls[1].foot + Map3DPoint(0, 90, 0), target: line.halls[1].foot, pack: Self.pack)
        let b = Self.laid.frame(second: 40_000.25, eye: line.halls[1].foot + Map3DPoint(0, 90, 0), target: line.halls[1].foot, pack: Self.pack)
        XCTAssertEqual(a.instances.map(\.floats), b.instances.map(\.floats))
        XCTAssertEqual(a.instances.map(\.model), b.instances.map(\.model))
    }
}
