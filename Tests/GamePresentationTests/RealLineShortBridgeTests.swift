@testable import GameCore
@testable import GamePresentation
import XCTest

/// BRANCH-SHORT-BRIDGE (decision 950): a real line's short bridges are
/// laid as bridges where the track already stands over the ground there.
final class RealLineShortBridgeTests: XCTestCase {
    private let metre = RealWorldDemo.metre

    private func path() -> WorldPath {
        WorldPath([WorldVector(x: 1_000 * metre, y: 1_000 * metre), WorldVector(x: 4_000 * metre, y: 1_000 * metre)])
    }

    private func rise(_ path: WorldPath) throws -> TrackRise {
        try XCTUnwrap(TrackRise(path: path, ground: { _ in 0 }, water: { _ in false }, levels: []))
    }

    /// Which short bridges get nodes: not a long one (decision 279 bounds
    /// it), not one near a station or another forced node, and one shorter
    /// than 16 m lengthened to 16 m about its middle.
    func testTheShortBridgesKept() throws {
        let path = path(), rise = try rise(path)
        let carried = [
            TrackRise.Carried(range: 500 * metre...582 * metre, kind: .bridge),
            TrackRise.Carried(range: 1_000 * metre...1_400 * metre, kind: .bridge),
            TrackRise.Carried(range: 1_600 * metre...1_607 * metre, kind: .bridge),
            TrackRise.Carried(range: 2_000 * metre...2_040 * metre, kind: .bridge),
            TrackRise.Carried(range: 2_500 * metre...2_540 * metre, kind: .bridge),
            TrackRise.Carried(range: 2_700 * metre...2_740 * metre, kind: .tunnel),
        ]
        let found = RealLineAcquisition.shortBridges(
            carried, length: path.length, forced: [0, path.length, 2_050 * metre], keepOut: [2_520 * metre...2_600 * metre], rise: rise
        )
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0], 500 * metre...582 * metre)
        XCTAssertEqual(found[1].lowerBound, 1_595.5 * metre, accuracy: 1e-6)
        XCTAssertEqual(found[1].upperBound, 1_611.5 * metre, accuracy: 1e-6)
    }

    /// The edge between a bridge's ends is a bridge where the track is over
    /// the ground, and stays automatic where it is under it.
    func testABridgeOnlyOverTheGround() throws {
        let world = GameWorld.newGame(
            anchor: try XCTUnwrap(GeoAnchor(latitude: 250_000_000, longitude: 1_215_000_000)), bounds: GameWorld.newGameBounds,
            balance: Money(1_000_000_000), land: [], rules: .simple
        )
        let y = Int64(1_000 * metre)
        func nodes(_ z: Int64) -> [WorldCoordinate] {
            [0, 500, 582, 1_000].map { WorldCoordinate(x: Int64(($0 + 1_000) * metre), y: y, z: z) }
        }
        let distances = [0, 500, 582, 1_000].map { $0 * metre }
        let curves = [TrackCurve](repeating: .straight, count: 3)
        let bridges = [500 * metre...582 * metre]
        let over = RealLineAcquisition.shortBridgeStructures(
            nodes: nodes(64), curves: curves, distances: distances, bridges: bridges, structure: .automatic, in: world
        )
        XCTAssertEqual(over, [.automatic, .bridge, .automatic])
        let under = RealLineAcquisition.shortBridgeStructures(
            nodes: nodes(-64), curves: curves, distances: distances, bridges: bridges, structure: .automatic, in: world
        )
        XCTAssertNil(under)
        // A piece keeps its own structure where it has none of its own.
        let piece = RealLineAcquisition.Piece(
            nodes: nodes(64), start: nil, end: nil, curves: curves, distances: distances, structure: .automatic, together: false, ground: []
        )
        XCTAssertEqual(piece.structure(ofEdge: 1), .automatic)
        var bridged = piece
        bridged.structures = over
        XCTAssertEqual(bridged.structure(ofEdge: 1), .bridge)
    }
}
