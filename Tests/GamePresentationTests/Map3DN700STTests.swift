import XCTest
@testable import GamePresentation

/// N700ST-PAINT: the N700S in the Taiwan High Speed Rail's paint, the
/// player's high-speed trains numbered odd.
final class Map3DN700STTests: XCTestCase {
    /// Each car is the N700S's own, vertex for vertex, but for its lines:
    /// the wide one orange, the narrow one under it black, no blue left.
    func testItIsTheN700SWithAnOrangeAndABlackLine() throws {
        let orange = Map3DTrainShapeRefresh.highSpeedBandColor
        for unit in Map3DN700S.Unit.allCases {
            let n700s = try XCTUnwrap(Map3DN700S.model(unit), unit.rawValue)
            let n700st = try XCTUnwrap(Map3DN700ST.model(unit), unit.rawValue)
            XCTAssertEqual(n700st.name, "n700st-" + unit.rawValue.dropFirst("n700s-".count))
            XCTAssertEqual(n700st.vertices.count, n700s.vertices.count, unit.rawValue)
            var orangeTriangles = 0, blackTriangles = 0
            for first in stride(from: 0, to: n700s.vertices.count, by: 3) {
                let was = n700s.vertices[first], now = n700st.vertices[first]
                XCTAssertEqual([now.x, now.y, now.z, now.layer], [was.x, was.y, was.z, was.layer], "\(unit.rawValue): same shape")
                XCTAssertNotEqual(now.color, Map3DPalette.shinkansenBlue, "\(unit.rawValue): no blue left")
                guard was.color == Map3DPalette.shinkansenBlue else {
                    XCTAssertEqual(now.color, was.color, "\(unit.rawValue): only the lines change")
                    continue
                }
                let top = n700s.vertices[first ..< first + 3].map(\.z).max()!
                if now.color == orange {
                    orangeTriangles += 1
                    XCTAssertGreaterThan(top, 1.73, "\(unit.rawValue): the wide line is orange")
                } else {
                    XCTAssertEqual(now.color, Map3DPalette.dark, unit.rawValue)
                    blackTriangles += 1
                    XCTAssertLessThan(top, 1.72, "\(unit.rawValue): the narrow line under it is black")
                }
            }
            XCTAssertGreaterThan(orangeTriangles, 150, unit.rawValue)
            XCTAssertGreaterThan(blackTriangles, 150, unit.rawValue)
        }
    }

    /// The player's high-speed trains: odd the N700ST, even the 700T. The
    /// Taiwan High Speed Rail's own trains all the 700T; the Nishi-Kyushu
    /// Shinkansen keeps its N700S.
    func testWhichTrainsAreTheN700ST() throws {
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), Map3DN700ST.key)
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: Map3DTHSR700T.key, number: 1), Map3DTHSR700T.key)
        XCTAssertEqual(Map3DRealTrains.formation(system: "kyushushinkansen", id: "NK", name: "").key, Map3DN700S.key)
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.modelIndex(forType: Map3DN700ST.key, carIndex: 0, count: 12))
        XCTAssertEqual(pack.models[head].name, "set-n700st-head")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DN700ST.key, in: .traditionalChinese), "N700ST")
        // A line's teal paint reaches its N700STs too.
        XCTAssertEqual(TrainPaintFamily.named(set: Map3DN700ST.key)?.id, "highSpeed")
    }
}
