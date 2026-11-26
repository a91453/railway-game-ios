@testable import GamePresentation
import XCTest

/// SPLIT-HOTSPOTS-2 (CAR-DOOR-SHARED): the door every ported car shares.
/// Each car's own tests check its doors against its mesh; these check the
/// rules of ``Map3DCarDoor`` alone.
final class Map3DCarDoorTests: XCTestCase {
    /// A door on both walls (side 0) takes a point on either wall; one on
    /// a wall takes only that wall's; none takes a point inside the car.
    func testTheWallsADoorIsOn() {
        let both = Map3DCarDoor(x: 1...2, z: 1...3)
        let left = Map3DCarDoor(x: 1...2, z: 1...3, side: 1)
        let narrow = Map3DCarDoor(x: 1...2, z: 1...3, side: -1, wall: 1.2)
        XCTAssertTrue(both.contains(Map3DPoint(1.5, 1.6, 2)))
        XCTAssertTrue(both.contains(Map3DPoint(1.5, -1.6, 2)))
        XCTAssertFalse(both.contains(Map3DPoint(1.5, 1.4, 2)), "inside the car")
        XCTAssertTrue(left.contains(Map3DPoint(1.5, 1.6, 2)))
        XCTAssertFalse(left.contains(Map3DPoint(1.5, -1.6, 2)), "the other wall")
        XCTAssertTrue(narrow.contains(Map3DPoint(1.5, -1.3, 2)), "the Keikyu's 2.80 m body")
        XCTAssertFalse(narrow.contains(Map3DPoint(1.5, 1.3, 2)))
    }

    /// Half a millimetre of slack by default, any other when asked.
    func testTheSlack() {
        let door = Map3DCarDoor(x: 1...2, z: 1...3)
        XCTAssertTrue(door.contains(Map3DPoint(2.0004, 1.6, 2)))
        XCTAssertFalse(door.contains(Map3DPoint(2.001, 1.6, 2)))
        XCTAssertTrue(door.contains(Map3DPoint(2.001, 1.6, 2), margin: 0.002))
        XCTAssertFalse(door.contains(Map3DPoint(1.995, 1.6, 2), margin: -0.01))
    }

    /// A slanted top: the door reaches as high as the line between its
    /// points, the first point's height before it and the last's after.
    func testASlantedTop() {
        let door = Map3DCarDoor(x: 5...6, z: 1...3, crew: true, side: 1, top: [SIMD2(5, 3), SIMD2(6, 2)])
        XCTAssertEqual(door.height(at: 4.9), 3)
        XCTAssertEqual(door.height(at: 5.5), 2.5, accuracy: 1e-6)
        XCTAssertEqual(door.height(at: 6.1), 2)
        XCTAssertTrue(door.contains(Map3DPoint(5.5, 1.6, 2.4)))
        XCTAssertFalse(door.contains(Map3DPoint(5.5, 1.6, 2.6)), "above the slant")
        XCTAssertEqual(Map3DCarDoor(x: 1...2, z: 1...3).height(at: 1.5), 3, "a square top")
    }

    /// The triangles a car keeps for each wall.
    func testTheTrianglesOfEachWall() {
        let door = Map3DCarDoor(x: 1...2, z: 1...3, left: 10..<20, right: 30..<40)
        XCTAssertEqual(door.triangles(side: 1), 10..<20)
        XCTAssertEqual(door.triangles(side: -1), 30..<40)
        XCTAssertEqual(Map3DCarDoor(x: 1...2, z: 1...3).triangles(side: 1), 0..<0)
    }
}
