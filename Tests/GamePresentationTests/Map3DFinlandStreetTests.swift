import GameCore
import XCTest
@testable import GamePresentation

/// Decision 846's later note: Finland's street furniture
/// (``Map3DFinlandStreet``), the local studio's models in place of the
/// stand-ins.
final class Map3DFinlandStreetTests: XCTestCase {
    private typealias Unit = Map3DFinlandStreet.Unit

    /// Each model decodes, with the triangles and the size the studio
    /// delivered, standing on its foot, and only its lit parts glow.
    func testTheModelsAreAsDelivered() throws {
        // Triangles, glowing triangles, height (metres).
        let delivered: [Unit: (triangles: Int, glowing: Int, height: Float)] = [
            .signalRed: (242, 6, 3.65), .signalRedAmber: (242, 12, 3.65), .signalAmber: (242, 6, 3.65), .signalGreen: (242, 6, 3.65),
            .walkStop: (254, 8, 2.74), .walkDark: (254, 0, 2.74), .walkWalk: (254, 14, 2.74),
            .lamp: (112, 2, 9.97), .busStop: (200, 0, 2.63), .crossingSign: (143, 0, 2.43),
        ]
        XCTAssertEqual(Set(delivered.keys), Set(Unit.allCases))
        for unit in Unit.allCases {
            let model = try XCTUnwrap(Map3DFinlandStreet.model(unit), "\(unit)")
            let expected = try XCTUnwrap(delivered[unit])
            XCTAssertEqual(model.name, unit.rawValue)
            XCTAssertEqual(model.triangleCount, expected.triangles, "\(unit)")
            XCTAssertEqual(model.vertices.filter { $0.layer == Map3DVertex.glowing }.count, expected.glowing * 3, "\(unit)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.001, "\(unit)")
            XCTAssertEqual(model.maximum.z, expected.height, accuracy: 0.01, "\(unit)")
            for vertex in model.vertices where vertex.layer == Map3DVertex.glowing {
                XCTAssertTrue(Map3DFinlandStreet.lit.contains(vertex.color))
            }
        }
        XCTAssertEqual(Map3DFinlandStreet.drawn.map(\.name), Unit.allCases.map(\.rawValue))
    }

    /// Each stands as the model it replaces: a signal's and the crossing
    /// sign's faces toward −x, a pedestrian signal's toward its left, the
    /// street light's arm and the bus stop's plate toward their left.
    func testTheModelsFaceAsTheOnesTheyReplace() throws {
        func glowing(_ unit: Unit) throws -> [Map3DVertex] {
            try XCTUnwrap(Map3DFinlandStreet.model(unit)).vertices.filter { $0.layer == Map3DVertex.glowing }
        }
        // The signal's lit light looks toward −x, at Hong Kong's heights.
        for (unit, heights) in [(Unit.signalRed, [Map3DHongKongSignal.lightHeights[0]]), (.signalAmber, [Map3DHongKongSignal.lightHeights[1]]),
                                (.signalGreen, [Map3DHongKongSignal.lightHeights[2]])] {
            let lens = try glowing(unit)
            XCTAssertTrue(lens.allSatisfy { $0.nx < -0.9 }, "\(unit)")
            let middle = (lens.map(\.z).min()! + lens.map(\.z).max()!) / 2
            XCTAssertEqual(middle, heights[0], accuracy: 0.02, "\(unit)")
        }
        // The pedestrian's figure looks toward the model's left.
        XCTAssertTrue(try glowing(.walkStop).allSatisfy { $0.ny > 0.9 })
        XCTAssertTrue(try glowing(.walkWalk).allSatisfy { $0.ny > 0.9 })
        // The walking figure under the standing one.
        XCTAssertLessThan(try glowing(.walkWalk).map(\.z).max()!, try glowing(.walkStop).map(\.z).min()!)
        // The street light's head: lit underneath, out over the road at
        // the model's left, about where Taiwan's is (the pool under it).
        let head = try glowing(.lamp)
        XCTAssertTrue(head.allSatisfy { $0.nz < -0.9 })
        let reach = (head.map(\.y).min()! + head.map(\.y).max()!) / 2
        XCTAssertEqual(reach, Map3DProp.lampReach, accuracy: 0.3)
        // The bus stop's plate looks at the road, on its left; the
        // crossing's sign at the traffic, toward −x.
        let blue = Map3DLook.colour(Map3DPalette.canopy)
        let plate = try XCTUnwrap(Map3DFinlandStreet.drawn.first { $0.name == Unit.busStop.rawValue }).vertices.filter { $0.color == blue }
        XCTAssertFalse(plate.isEmpty)
        XCTAssertTrue(plate.contains { $0.ny > 0.9 })
        let sign = try XCTUnwrap(Map3DFinlandStreet.drawn.first { $0.name == Unit.crossingSign.rawValue }).vertices.filter { $0.color == blue }
        XCTAssertTrue(sign.contains { $0.nx < -0.9 })
    }

    /// The renderer shows Finland's signals as the clock says, red and
    /// amber together before green, and its pedestrian faces with no
    /// countdown; Hong Kong's and Taiwan's as before.
    func testTheClockTurnsFinlandsLights() throws {
        let pack = Map3DModelPack.standard
        let signals = try XCTUnwrap(Map3DSignalTiming.Models(pack: pack))
        let finland = try XCTUnwrap(signals.finland), hongKong = try XCTUnwrap(signals.hongKong)
        XCTAssertEqual(pack.models[finland.green].name, Map3DFinlandStreet.placedName(.main))
        XCTAssertEqual(pack.models[finland.red].name, Map3DFinlandStreet.placedName(.cross))
        func clock(_ second: Int64) -> Map3DSignalTiming.Clock {
            Map3DSignalTiming.Clock(GameClock(now: GameTime(seconds: second), speed: .x1), region: .finland)
        }
        var main = Set<Int>(), cross = Set<Int>()
        for second in Int64(0)..<Map3DSignalTiming.cycle {
            main.insert(signals.model(finland.green, group: 1, clock: clock(second)))
            cross.insert(signals.model(finland.red, group: 1, clock: clock(second)))
            // Hong Kong's stay Hong Kong's.
            XCTAssertTrue([hongKong.red, hongKong.redAmber, hongKong.amber, hongKong.green].contains(signals.model(hongKong.green, group: 1, clock: clock(second))))
        }
        let all: Set<Int> = [finland.red, finland.redAmber, finland.amber, finland.green]
        XCTAssertEqual(main, all)
        XCTAssertEqual(cross, all)
        XCTAssertEqual(signals.model(finland.green, group: 1, clock: nil), finland.green)
        XCTAssertEqual(signals.model(finland.red, group: 1, clock: nil), finland.red)

        let walks = try XCTUnwrap(Map3DPedestrianSignal.Models(pack: pack))
        let faces = try XCTUnwrap(walks.finland), plain = try XCTUnwrap(walks.plain)
        XCTAssertEqual(walks.placedPlain(.finland), faces.stop)
        XCTAssertEqual(walks.placedPlain(.hongKong), plain.stop)
        XCTAssertTrue(walks.places(faces.stop))
        var shown = Set<Int>()
        for second in Int64(0)..<Map3DSignalTiming.cycle {
            for time in [0.2, 0.7] {
                let model = walks.model(faces.stop, group: 1, clock: clock(second), time: Double(second) + time, pace: Map3DPedestrianSignal.Pace(),
                                        reduceMotion: false)
                shown.insert(try XCTUnwrap(model))
            }
        }
        XCTAssertEqual(shown, [faces.stop, faces.dark, faces.walk])
        let run = Map3DPropRuns.Run(model: faces.stop, group: 0, first: 0, count: 3)
        XCTAssertEqual(walks.triangles([run], in: pack), 3 * 254)
    }
}
