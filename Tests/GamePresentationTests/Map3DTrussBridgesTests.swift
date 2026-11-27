import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1033: 西螺大橋 and 大樹舊鐵橋 laid span by span along
/// OpenStreetMap's line, every piece on one foot, 西螺大橋's road on its
/// deck.
final class Map3DTrussBridgesTests: XCTestCase {
    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                    options: .alwaysMapped))
    }

    /// Every model decodes, near and far, with the size the studio gave
    /// it (README §1), the far one within half the near one's triangles
    /// and no colour it lacks.
    func testTheModels() {
        let sizes: [String: (x: Float, y: Float, z: Float)] = [
            "tw-xiluo-span": (63.59, 8.8, 19.5), "tw-xiluo-end": (63.69, 9.2, 19.5), "tw-xiluo-pier": (2.2, 8.8, 8.3),
            "tw-dashu-span": (64.95, 7.8, 20.8), "tw-dashu-pier": (3.6, 7.8, 9.5),
        ]
        for bridge in Map3DTrussBridge.allCases {
            for name in Set(bridge.pieces.map(\.model)) {
                let near = bridge.model(name, full: true), far = bridge.model(name, full: false)
                let size = try? XCTUnwrap(sizes[name], name)
                for model in [near, far] {
                    XCTAssertFalse(model.vertices.isEmpty, name)
                    guard let size, !model.vertices.isEmpty else { continue }
                    let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
                    XCTAssertEqual(xs.max()! - xs.min()!, size.x, accuracy: 0.05, "\(name) length")
                    XCTAssertEqual(ys.max()! - ys.min()!, size.y, accuracy: 0.05, "\(name) width")
                    XCTAssertEqual(zs.max()!, size.z, accuracy: 0.05, "\(name) height")
                    XCTAssertEqual(zs.min()!, 0, accuracy: 0.01, "\(name) foot")
                }
                XCTAssertLessThanOrEqual(far.indices.count * 2, near.indices.count, "\(name) far")
                XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(name) far colours")
                XCTAssertTrue(Set(near.vertices.map(\.color)).isSubset(of: Set(bridge.palette)), "\(name) palette")
            }
        }
        XCTAssertEqual(Map3DTrussBridge.xiluo.nearTriangles, 29 * 932 + 2 * 968 + 84)
        XCTAssertEqual(Map3DTrussBridge.dashu.nearTriangles, 19 * 932 + 3 * 180)
    }

    /// 西螺大橋's 31 spans and 大樹舊鐵橋's 19 that stand, each pier
    /// under one piece: a span's at its −X end (the turned end span's at
    /// its far end), the lone piers where the next span is gone.
    func testThePiecesStandOnTheirPiers() {
        for (bridge, pitch) in [(Map3DTrussBridge.xiluo, Float(62.5)), (.dashu, 63.5)] {
            let piers = bridge.pieces.map { piece -> Float in
                piece.model.hasSuffix("-pier") ? piece.along : piece.along + (piece.turned ? 1 : -1) * pitch / 2
            }.sorted()
            XCTAssertEqual(piers, bridge.line.piers, "\(bridge)")
            XCTAssertEqual(Set(piers).count, piers.count, "\(bridge): one piece a pier")
        }
        XCTAssertEqual(Map3DTrussBridge.xiluo.pieces.count, 32)
        XCTAssertEqual(Map3DTrussBridge.xiluo.pieces.filter(\.turned).map(\.along), [15 * 62.5])
        XCTAssertEqual(Map3DTrussBridge.dashu.pieces.filter { $0.model == "tw-dashu-span" }.count, 19)
        XCTAssertEqual(Map3DTrussBridge.dashu.line.piers.count, 22)
        // The whole of each, within a few tens of metres of OpenStreetMap's.
        XCTAssertEqual(Map3DTrussBridge.xiluo.line.half * 2, 1_932, accuracy: 10)
        XCTAssertEqual(Map3DTrussBridge.dashu.line.half * 2, 1_552, accuracy: 30)
    }

    /// A game at the bridge, a scene `reach` metres round its middle, with
    /// the app's base map.
    private func scene(_ bridge: Map3DTrussBridge, reach: Double = 1_200) throws
        -> (builder: Map3DScene.Builder, line: Map3DArchBridgeDeck.Placed, frame: RealWorldFrame) {
        let deck = bridge.line
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: deck.latitude, longitudeDegrees: deck.longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: deck.latitude, longitude: deck.longitude)
        let placed = try XCTUnwrap(deck.placed(frame: frame, origin: origin))
        let region = WorldRegion(minX: origin.x - reach * metre, minY: origin.y - reach * metre,
                                 maxX: origin.x + reach * metre, maxY: origin.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: nil)
        _ = builder.addBaseMap(Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        return (builder, placed, frame)
    }

    /// Every piece is built where no track runs, on the lowest ground
    /// under the piers, so none of them stands over the river bed.
    func testEveryPieceIsBuiltOnOneFoot() throws {
        for bridge in Map3DTrussBridge.allCases {
            var (builder, line, frame) = try scene(bridge)
            let foot = builder.foot(of: line)
            for at in line.deck.piers {
                let p = line.point(along: at)
                XCTAssertGreaterThanOrEqual(builder.drawnGround(x: p.x, z: p.z), foot - 0.001, "\(bridge) pier \(at)")
            }
            XCTAssertEqual(builder.addTrussBridges(frame: frame), bridge.pieces.count, "\(bridge)")
        }
    }

    /// 西螺大橋's road crosses on its deck, just over the model's 8.5 m.
    func testTheRoadCrossesXiluoOnItsDeck() throws {
        var (builder, line, _) = try scene(.xiluo)
        let foot = builder.foot(of: line)
        XCTAssertTrue(Map3DArchBridgeDeck.all.contains { $0.latitude == line.deck.latitude })
        var station: Float = -900, found = 0
        while station <= 900 {
            defer { station += 50 }
            var top: Float?
            var offset: Float = -12
            while offset <= 12 {
                defer { offset += 0.5 }
                let p = line.point(along: station) + line.across * offset
                let raised = builder.roadRise(at: Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)),
                                              along: (Double(line.along.x), Double(line.along.z)), onDeck: true)
                guard raised.onBridge else { continue }
                let here = builder.drawnGround(x: p.x, z: p.z) + raised.rise - foot
                top = max(top ?? here, here)
            }
            guard let top else { continue }
            found += 1
            XCTAssertEqual(top, 8.5 + Map3DArchBridgeDeck.roadOver - 0.32, accuracy: 0.1, "\(station) m along")
            XCTAssertTrue(builder.standsOnArchBridge(x: line.point(along: station).x, z: line.point(along: station).z))
        }
        XCTAssertGreaterThan(found, 30, "the base map's road over the bridge")
    }
}
