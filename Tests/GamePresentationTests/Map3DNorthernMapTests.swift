import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 799: Rovaniemi's 3D map lays its rails at Finland's 1,524 mm
/// and draws its ground under snow; every other map is drawn as before.
final class Map3DNorthernMapTests: XCTestCase {
    /// The distance between the inner faces of the two rails of a straight
    /// piece of track laid in `world`'s scene, metres.
    private func gaugeDrawn(in world: GameWorld) -> Float {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.addTrackPiece([Map3DPoint(0, 0, 50), Map3DPoint(100, 0, 50)], kind: .surface)
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh) }
        let tops = mesh.vertices.filter { $0.color == Map3DPalette.railTop }.map { $0.z - 50 }
        XCTAssertEqual(tops.count, 2 * 4)
        return (tops.filter { $0 > 0 }.min() ?? 0) - (tops.filter { $0 < 0 }.max() ?? 0)
    }

    func testRovaniemisRailsAreAtTheFinnishGauge() throws {
        let rovaniemi = GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground())
        XCTAssertEqual(Map3DTrackGauge.metres(world: rovaniemi), 1.524)
        XCTAssertEqual(gaugeDrawn(in: rovaniemi), 1.524, accuracy: 0.001)
    }

    /// Taiwan's maps (the generated one with no anchor, and one anchored
    /// at Taipei Main Station) and Hong Kong's keep the 1,067 mm they were
    /// drawn at.
    func testTheOtherMapsKeepTheirGauge() throws {
        let taipei = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let hongKong = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        for world in [GameWorld.newGame(), taipei, hongKong] {
            XCTAssertEqual(Map3DTrackGauge.metres(world: world), 1.067)
            XCTAssertEqual(gaugeDrawn(in: world), 1.067, accuracy: 0.001)
            XCTAssertFalse(Map3DSnowGround.covers(world))
        }
    }

    /// Under snow the greens of the ground are whites, the wood a paler
    /// wood, and what is not ground keeps its colour.
    func testTheSnowTakesTheGreensOfTheGround() throws {
        XCTAssertTrue(Map3DSnowGround.covers(GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground())))
        var mesh = Map3DMesh()
        let kept = [Map3DPalette.ground, Map3DPalette.water, Map3DPalette.cover(.wetland), Map3DPalette.paved, Map3DPalette.ballast,
                    Map3DPalette.railTop, Map3DPalette.road(.primary), Map3DPalette.sidewalk, Map3DPalette.plaza]
        let greens = [Map3DPalette.farm, Map3DPalette.cover(.grass), Map3DPalette.park, Map3DPalette.yard, Map3DPalette.cover(.wood),
                      Map3DPalette.cover(.sand), Map3DPalette.embankment, Map3DPalette.ground(mixing: [.yard, .yard, .paved, .plain])]
        for colour in kept + greens {
            mesh.addQuad(Map3DPoint(0, 0, 0), Map3DPoint(1, 0, 0), Map3DPoint(1, 0, 1), Map3DPoint(0, 0, 1), color: colour)
        }
        let before = mesh.vertices.map(\.color)
        Map3DSnowGround.cover(&mesh)
        let after = mesh.vertices.map(\.color)
        XCTAssertEqual(Array(after.prefix(kept.count * 4)), Array(before.prefix(kept.count * 4)))
        let snowed = Set(after.suffix(greens.count * 4))
        XCTAssertTrue(snowed.isDisjoint(with: greens), "no green left")
        XCTAssertEqual(snowed, [Map3DSnowGround.field, Map3DPalette.ground, Map3DSnowGround.wood, Map3DPalette.paved,
                                Map3DPalette.ground(mixing: [.plain, .plain, .paved, .plain])])
        // Every colour the snow gives is the palette's own but the wood.
        let palette = Set([Map3DPalette.sidewalk, Map3DPalette.ground]).union(Map3DPalette.groundMixes)
        XCTAssertEqual(Set(Map3DSnowGround.colours.values).subtracting(palette), [Map3DSnowGround.wood])
    }

    /// The scene round Rovaniemi's station: no field, grass, park or
    /// summer wood colour is left on the ground, and the snowy wood is
    /// there (the town stands among woods).
    func testRovaniemisSceneIsUnderSnow() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 66.4977, longitude: 25.7143)
        let baseMap = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap)
        var colours = Set<UInt32>()
        for chunk in scene.chunks { colours.formUnion(chunk.mesh.vertices.map(\.color)) }
        XCTAssertTrue(colours.contains(Map3DSnowGround.wood))
        XCTAssertTrue(colours.isDisjoint(with: [Map3DPalette.farm, Map3DPalette.park, Map3DPalette.cover(.wood), Map3DPalette.yard]))
    }
}
