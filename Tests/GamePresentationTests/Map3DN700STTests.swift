import XCTest
@testable import GamePresentation

/// N700ST-PAINT: the N700S in the Taiwan High Speed Rail's paint, the
/// player's high-speed trains numbered odd.
final class Map3DN700STTests: XCTestCase {
    /// Each car is the N700S's size, its lengths, width and height, with
    /// its own mesh in the N700ST's paint: no blue, orange and black lines.
    func testEachCarIsTheN700SsSizeInTheN700STsPaint() throws {
        let orange = Map3DTrainShapeRefresh.highSpeedBandColor
        for (unit, triangles) in zip(Map3DN700S.Unit.allCases, [5_413, 3_384, 3_682]) {
            let n700s = try XCTUnwrap(Map3DN700S.model(unit), unit.rawValue)
            let n700st = try XCTUnwrap(Map3DN700ST.model(unit), unit.rawValue)
            XCTAssertEqual(n700st.name, "n700st-" + unit.rawValue.dropFirst("n700s-".count))
            XCTAssertEqual(n700st.triangleCount, triangles, unit.rawValue)
            for (now, was) in [(n700st.minimum, n700s.minimum), (n700st.maximum, n700s.maximum)] {
                XCTAssertEqual(now.x, was.x, accuracy: 0.002, unit.rawValue)
                XCTAssertEqual(now.y, was.y, accuracy: 0.003, unit.rawValue)
                XCTAssertEqual(now.z, was.z, accuracy: 0.003, unit.rawValue)
            }
            XCTAssertFalse(n700st.vertices.contains { $0.color == Map3DPalette.shinkansenBlue }, unit.rawValue)
            XCTAssertGreaterThan(n700st.vertices.filter { $0.color == orange }.count, 3 * 150, unit.rawValue)
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(n700st), unit.rawValue)
        }
    }

    /// The colour of `model`'s side wall at (`x`, `z`) on the side `sign`
    /// is on (+1 the left), seen from that side: the colour of the
    /// outermost face covering it.
    private func colour(_ model: Map3DModelPack.Model, x: Float, z: Float, side sign: Float) -> UInt32? {
        var best: (y: Float, color: UInt32)?
        for first in stride(from: 0, to: model.vertices.count, by: 3) {
            let p = model.vertices[first..<first + 3].map { $0 }
            guard p.allSatisfy({ $0.y * sign > 1.0 }) else { continue }
            func cross(_ a: Map3DVertex, _ b: Map3DVertex) -> Float { (b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x) }
            let turns = [cross(p[0], p[1]), cross(p[1], p[2]), cross(p[2], p[0])]
            guard turns.allSatisfy({ $0 > 1e-7 }) || turns.allSatisfy({ $0 < -1e-7 }) else { continue }
            let y = p.map { $0.y * sign }.max()!
            if best.map({ y > $0.y }) ?? true { best = (y, p[0].color) }
        }
        return best?.color
    }

    /// Under the windows of every car a narrow black line over a wider
    /// orange one (as on the 700T), the white body under them and the grey
    /// skirt at the bottom, on both sides.
    func testTheSidesHaveABlackLineOverAnOrangeOne() throws {
        let orange = Map3DTrainShapeRefresh.highSpeedBandColor, white = Map3DTrainShapeRefresh.highSpeedBodyColor
        let places: [(Map3DN700S.Unit, Float)] = [(.cab, -5), (.middle, 0), (.middle, 5), (.pantograph, 0)]
        for (unit, x) in places {
            let model = try XCTUnwrap(Map3DN700ST.model(unit))
            for sign in [Float(1), -1] {
                let name = "\(unit.rawValue) at x \(x), side \(sign)"
                XCTAssertEqual(colour(model, x: x, z: 1.79, side: sign), Map3DPalette.dark, name)
                XCTAssertEqual(colour(model, x: x, z: 1.63, side: sign), orange, name)
                XCTAssertEqual(colour(model, x: x, z: 1.25, side: sign), white, name)
                XCTAssertEqual(colour(model, x: x, z: 0.80, side: sign), Map3DPalette.steel, name)
            }
        }
    }

    /// The cab car: by its first doors a large orange block from the skirt
    /// up to the lines, and behind it a black band parallel to its front
    /// edge; a black mask round the driver's windows; the nose white.
    func testTheCabCarHasTheOrangeBlockTheBlackBandAndTheMask() throws {
        let cab = try XCTUnwrap(Map3DN700ST.model(.cab))
        let orange = Map3DTrainShapeRefresh.highSpeedBandColor, white = Map3DTrainShapeRefresh.highSpeedBodyColor
        for sign in [Float(1), -1] {
            // The block under the driver's door, white ahead of its
            // slanting front edge; the band behind it, white behind that.
            XCTAssertEqual(colour(cab, x: 7.6, z: 1.20, side: sign), white, "ahead of the block, side \(sign)")
            XCTAssertEqual(colour(cab, x: 5.6, z: 1.20, side: sign), orange, "block, side \(sign)")
            XCTAssertEqual(colour(cab, x: 4.8, z: 1.05, side: sign), orange, "block, side \(sign)")
            XCTAssertEqual(colour(cab, x: 3.6, z: 1.20, side: sign), Map3DPalette.dark, "band, side \(sign)")
            XCTAssertEqual(colour(cab, x: 2.0, z: 1.20, side: sign), white, "behind the band, side \(sign)")
        }
        // The mask: dark faces over the nose round the windscreen, as
        // much of it each side of the centre line (to 10%: the old car's
        // two sides are cut a little apart).
        var area: [Float] = [0, 0]
        for first in stride(from: 0, to: cab.vertices.count, by: 3) {
            let p = cab.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
            guard cab.vertices[first].color == Map3DPalette.dark, p.allSatisfy({ $0.x > 6.5 && $0.z > 2.0 }) else { continue }
            area[(p[0].y + p[1].y + p[2].y) > 0 ? 0 : 1] += (p[1] - p[0]).cross(p[2] - p[0]).length / 2
        }
        XCTAssertGreaterThan(area.min() ?? 0, 0.5, "the mask, square metres each side")
        XCTAssertEqual(area[0], area[1], accuracy: area[0] * 0.1, "the mask, left and right")
        // Ahead of the mask the nose is white: no orange on it.
        XCTAssertFalse(cab.vertices.contains { $0.color == orange && $0.x > 9.6 })
    }

    /// Each door is a piece of its own, as the N700S's (``Map3DN700S/doors(_:)``):
    /// its triangles follow the body's, on its own side, within its box.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DN700S.Unit.allCases.map { Map3DN700ST.doors($0).count }, [3, 2, 2])
        XCTAssertEqual(Map3DN700ST.doors(.cab).map(\.crew), [true, false, false])
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700ST.model(unit))
            let doors = Map3DN700ST.doors(unit)
            let runs = doors.flatMap { [$0.left, $0.right] }.sorted { $0.lowerBound < $1.lowerBound }
            XCTAssertEqual(runs.last?.upperBound, model.triangleCount, unit.rawValue)
            for (run, next) in zip(runs, runs.dropFirst()) { XCTAssertEqual(run.upperBound, next.lowerBound, unit.rawValue) }
            for (door, was) in zip(doors, Map3DN700S.doors(unit)) {
                XCTAssertEqual(door.x.lowerBound, was.x.lowerBound, accuracy: 0.003, unit.rawValue)
                XCTAssertEqual(door.x.upperBound, was.x.upperBound, accuracy: 0.003, unit.rawValue)
                for sign in [Float(1), -1] {
                    let name = "\(unit.rawValue): the door at x \(door.x), side \(sign)"
                    var glass = 0
                    for triangle in door.triangles(side: sign) {
                        let points = model.vertices[3 * triangle..<3 * triangle + 3]
                        XCTAssertTrue(points.allSatisfy { door.contains(Map3DPoint($0.x, $0.y, $0.z)) && $0.y * sign > 1.5 }, name)
                        if points.first?.color == Map3DTrainStyle.glass { glass += 1 }
                    }
                    XCTAssertGreaterThan(glass, 0, name)
                }
            }
        }
    }

    /// The player's high-speed trains: odd the N700ST, even the 700T. The
    /// Taiwan High Speed Rail's own trains all the 700T; the Nishi-Kyushu
    /// Shinkansen keeps its own N700S, the Kamome.
    func testWhichTrainsAreTheN700ST() throws {
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), Map3DN700ST.key)
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: Map3DTHSR700T.key, number: 1), Map3DTHSR700T.key)
        XCTAssertEqual(Map3DRealTrains.formation(system: "kyushushinkansen", id: "NK", name: "").key, Map3DN700SKamome.key)
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.modelIndex(forType: Map3DN700ST.key, carIndex: 0, count: 12))
        XCTAssertEqual(pack.models[head].name, "set-n700st-head")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DN700ST.key, in: .traditionalChinese), "N700ST")
        // A line's teal paint reaches its N700STs too.
        XCTAssertEqual(TrainPaintFamily.named(set: Map3DN700ST.key)?.id, "highSpeed")
    }
}
