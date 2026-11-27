import XCTest
@testable import GamePresentation

/// Decision 1028 (continued): JR Kyushu's 885 series, the Relay Kamome's
/// train, the owner's old cars ported by the local studio.
final class Map3DKyushu885Tests: XCTestCase {
    func testBothUnitsDecodeAtTheRealSize() throws {
        for unit in Map3DKyushu885.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu885.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 2.91, accuracy: 0.01, "\(unit.rawValue) is 2.91 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.z, unit.isCab ? 3.825 : 3.734, accuracy: 0.01, unit.rawValue)
            XCTAssertTrue(Map3DKyushu885.registration.triangles.contains(model.triangleCount), unit.rawValue)
            XCTAssertTrue(Map3DKyushu885.registration.length.contains(model.length), unit.rawValue)
        }
        // The real set: two 21.65 m cab cars and four 20.50 m middle cars,
        // 125.3 m in all.
        XCTAssertEqual(2 * Map3DKyushu885.Unit.cab.pitch + 4 * Map3DKyushu885.Unit.middle.pitch, 125.3, accuracy: 0.001)
    }

    /// The wheels stand on the 1,067 mm gauge, and only they reach the rail.
    func testTheWheelsStandOnTheNarrowGauge() throws {
        for unit in Map3DKyushu885.Unit.allCases {
            let low = try XCTUnwrap(Map3DKyushu885.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.067 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.067 / 2 + 0.15, unit.rawValue)
        }
    }

    /// Only the palette's colours: a white body, the blue front frame and
    /// line, and nothing that is not the mesh's palette.
    func testTheColoursAreThePalettes() throws {
        let colours = Set(Map3DKyushu885.meshPalette)
        for unit in Map3DKyushu885.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu885.model(unit))
            let used = Set(model.vertices.map(\.color))
            XCTAssertTrue(used.isSubset(of: colours), unit.rawValue)
            XCTAssertTrue(used.contains(Map3DPalette.mtrAirportBlue), "\(unit.rawValue): the blue line")
        }
        // The lamps are on the cab car only.
        let middle = Set(try XCTUnwrap(Map3DKyushu885.model(.middle)).vertices.map(\.color))
        XCTAssertFalse(middle.contains(Map3DTrainStyle.headlamp))
        XCTAssertFalse(middle.contains(Map3DPalette.lantern))
    }

    /// Each door is the run of triangles the studio's tool wrote as its
    /// node, all of them inside its outline on its own wall, and no other
    /// triangle on that wall is.
    func testEachDoorIsAPieceOfItsOwn() throws {
        for unit in Map3DKyushu885.Unit.allCases {
            let vertices = try XCTUnwrap(Map3DKyushu885.model(unit)).vertices
            let doors = Map3DKyushu885.doors(unit)
            var taken = Set<Int>()
            for door in doors {
                let run = door.triangles(side: door.side)
                XCTAssertFalse(run.isEmpty, unit.rawValue)
                for triangle in run {
                    taken.insert(triangle)
                    for corner in vertices[3 * triangle ..< 3 * triangle + 3] {
                        XCTAssertTrue(door.contains(Map3DPoint(corner.x, corner.y, corner.z)),
                                      "\(unit.rawValue): triangle \(triangle) is outside its door")
                    }
                }
            }
            XCTAssertEqual(taken.count, doors.map { $0.triangles(side: $0.side).count }.reduce(0, +), "\(unit.rawValue): no triangle in two doors")
            for triangle in 0 ..< vertices.count / 3 where !taken.contains(triangle) {
                let corners = vertices[3 * triangle ..< 3 * triangle + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                XCTAssertFalse(doors.contains { door in corners.allSatisfy { door.contains($0) } },
                               "\(unit.rawValue): wall triangle \(triangle) lies in a door")
            }
        }
    }

    /// The Relay Kamome is drawn as the 885 series, six cars, and its
    /// odd-numbered trains as the 787 series, where it was the Taroko
    /// until it had its own.
    func testTheRelayKamomeRunsTheSeries885() {
        let line = Map3DRealTrains.japanFormation(system: "jrkyushu", id: "RK", name: "")
        XCTAssertEqual(line, .init(key: Map3DKyushu885.key, cars: 6, alternate: Map3DKyushu787.key))
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DKyushu885.key, in: .english), "Series 885")
    }
}
