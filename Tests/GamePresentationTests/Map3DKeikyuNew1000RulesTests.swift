import XCTest
@testable import GamePresentation

/// Revision 6 of the Keikyu New 1000 (``Map3DKeikyuNew1000``, decision 986):
/// the rules the owner's old cars ported since keep (decision 978's 800
/// series, `tools/texture-palette/port_check.py`): each door its own piece,
/// the gangways kept apart on a curve, and only the lamps a train shows at
/// each end lit.
final class Map3DKeikyuNew1000RulesTests: XCTestCase {
    private func corners(_ model: Map3DModelPack.Model) -> [(points: [Map3DPoint], color: UInt32)] {
        stride(from: 0, to: model.vertices.count, by: 3).map { first in
            (model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }, model.vertices[first].color)
        }
    }

    /// Each door (its frame, its two leaves and their windows) is cut out
    /// of the wall along its outline, at the place ``Map3DKeikyuNew1000/doors(cab:)``
    /// gives: no triangle crosses it, and it holds as many faces as the
    /// tool's node of it, none of the wall's (at the half millimetre of
    /// slack ``Map3DKeikyuNew1000/Door/contains(_:margin:)`` takes).
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DKeikyuNew1000.doors(cab: true).count, 8)
        XCTAssertEqual(Map3DKeikyuNew1000.doors(cab: true).map(\.crew), [true, true] + Array(repeating: false, count: 6))
        XCTAssertEqual(Map3DKeikyuNew1000.doors(cab: false).count, 6)
        XCTAssertEqual(Map3DKeikyuNew1000.doors(cab: false).map(\.side), [1, -1, 1, -1, 1, -1])
        for cab in [true, false] {
            let model = try XCTUnwrap(cab ? Map3DKeikyuNew1000.cab() : Map3DKeikyuNew1000.middle())
            let walls = corners(model).filter { $0.points.allSatisfy { abs($0.y) > 1.2 } }
            for door in Map3DKeikyuNew1000.doors(cab: cab) {
                let name = "\(cab ? "cab" : "middle"): the door at x \(door.x), side \(door.side)"
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, door.crew ? 0.6 : 1.3, name)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.8, name)
                var own = 0, glass = 0, frame = 0
                for (points, color) in walls where points[0].y * door.side > 0 {
                    if points.allSatisfy({ door.contains($0) }) {
                        own += 1
                        if color == Map3DTrainStyle.glass { glass += 1 }
                        if color == Map3DPalette.steel { frame += 1 }
                    } else {
                        XCTAssertFalse(points.contains { door.contains($0, margin: -0.01) }, "\(name): a triangle crosses it")
                    }
                }
                // As revision-6's `report.json` counts them.
                XCTAssertEqual(own, door.crew ? 18 : 44, name)
                XCTAssertGreaterThan(frame, 5, name)
                if !door.crew { XCTAssertGreaterThan(glass, 0, name) }
            }
        }
    }

    /// The narrow gangway's mouth is a shallow V seen from above: at the
    /// joint in the middle, drawn back 5 cm a metre towards its sides (2.5
    /// cm at its sides, 0.5 m out), at both of the middle car's ends and
    /// the cab car's back; the cab's face is as it was.
    func testTheGangwaysMouthIsAShallowV() throws {
        for (name, model, ends) in [("cab", try XCTUnwrap(Map3DKeikyuNew1000.cab()), [Float(-1)]),
                                    ("middle", try XCTUnwrap(Map3DKeikyuNew1000.middle()), [-1, 1]),
                                    ("cab far", try XCTUnwrap(Map3DKeikyuNew1000.cab(far: true)), [-1]),
                                    ("middle far", try XCTUnwrap(Map3DKeikyuNew1000.middle(far: true)), [-1, 1])] {
            for end in ends {
                let mouth = model.vertices.filter { $0.x * end > 8.9 }
                XCTAssertFalse(mouth.isEmpty, name)
                XCTAssertTrue(mouth.allSatisfy { $0.color == Map3DPalette.dark && abs($0.y) <= 0.5005 }, "\(name): the gangway alone")
                for vertex in mouth {
                    XCTAssertEqual(vertex.x * end, 9 - 0.05 * abs(vertex.y), accuracy: 0.0011, "\(name): the V at \(vertex.y)")
                }
                XCTAssertEqual(mouth.map { abs($0.y) }.max() ?? 0, 0.5, accuracy: 0.001, name)
            }
        }
    }

    /// On a curve two cars turn about the joint's middle: up to 4 degrees
    /// to each other (2 each), no point of a car's end crosses the joint.
    func testTheGangwaysKeepApartOnACurve() throws {
        let turn = Float(2) * .pi / 180
        for (name, model, ends) in [("cab", try XCTUnwrap(Map3DKeikyuNew1000.cab()), [Float(-1)]),
                                    ("middle", try XCTUnwrap(Map3DKeikyuNew1000.middle()), [-1, 1])] {
            for end in ends {
                var nearest = -Float.infinity
                for vertex in model.vertices where vertex.x * end > 8 {
                    nearest = max(nearest, (vertex.x * end - 9) * cos(turn) + abs(vertex.y) * sin(turn))
                }
                XCTAssertLessThanOrEqual(nearest, 0.0005, "\(name): \(nearest)")
            }
        }
    }

    /// The cab car's face has a white lamp and a red one a side: the first
    /// car's white ones glow and the last car's red ones, and nothing else,
    /// as the real train's do; near and far.
    func testOnlyTheLampsOfEachEndAreLit() throws {
        for far in [false, true] {
            let set = Map3DTrainSet.keikyuNew1000(far: far)
            let cars = set.build()
            let first = cars.head.vertices.filter { $0.layer == Map3DVertex.glowing }
            let last = try XCTUnwrap(cars.tail).vertices.filter { $0.layer == Map3DVertex.glowing }
            XCTAssertFalse(first.isEmpty, "far \(far)")
            XCTAssertFalse(last.isEmpty, "far \(far)")
            XCTAssertTrue(first.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 8.8 }, "far \(far)")
            XCTAssertTrue(last.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < -8.8 }, "far \(far)")
            for sign in [Float(1), -1] {
                XCTAssertEqual(first.filter { $0.y * sign > 0 }.count, last.filter { $0.y * sign > 0 }.count, "far \(far)")
            }
            XCTAssertFalse(try XCTUnwrap(cars.middle).vertices.contains { $0.layer == Map3DVertex.glowing })
        }
    }
}
