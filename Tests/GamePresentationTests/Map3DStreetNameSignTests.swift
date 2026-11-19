import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 846's third later note: Finland's street name signs, a blue
/// plate on a post at a junction's corner for each road's name, from the
/// base map's road names; none in Taiwan or Hong Kong.
final class Map3DStreetNameSignTests: XCTestCase {
    private typealias Point = Map3DBaseMap.Point

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ points: [Point], _ name: String?) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: points, bounds: everywhere, name: name)
    }

    /// A crossing of Hallituskatu (east–west) and Koskikatu (north–south).
    private var crossing: [Map3DBaseMap.Road] {
        [road([Point(x: -200, z: 0), Point(x: 0, z: 0), Point(x: 200, z: 0)], "Hallituskatu"),
         road([Point(x: 0, z: -200), Point(x: 0, z: 0), Point(x: 0, z: 200)], "Koskikatu")]
    }

    func testAJunctionOfTwoNamedRoadsHasASignForEach() throws {
        XCTAssertTrue(Map3DRoadMarkings(crossing, region: .taiwan).streetNames.isEmpty)
        XCTAssertTrue(Map3DRoadMarkings(crossing, region: .hongKong).streetNames.isEmpty)
        let signs = Map3DRoadMarkings(crossing, region: .finland).streetNames
        XCTAssertEqual(signs.map(\.name).sorted(), ["Hallituskatu", "Koskikatu"])
        let half = Double(Map3DBaseMap.RoadKind.secondary.width(ramp: false)) / 2
        for sign in signs {
            // Along the road it names, on the pavement off both roads.
            let alongX = abs(sign.along.x) > 0.99
            XCTAssertEqual(alongX, sign.name == "Hallituskatu")
            XCTAssertGreaterThan(abs(sign.foot.x), half)
            XCTAssertGreaterThan(abs(sign.foot.z), half)
            XCTAssertLessThan(abs(sign.foot.x) + abs(sign.foot.z), 4 * half)
        }
        // Clear of the signals and pedestrian signals.
        let markings = Map3DRoadMarkings(crossing, region: .finland)
        for sign in signs {
            for foot in markings.signals.map(\.foot) + markings.walks.map(\.foot) {
                XCTAssertGreaterThan(Map3DRoadMarkings.distance(sign.foot, foot), 1)
            }
        }
    }

    func testOneNameOrNoneHasNoSign() {
        var roads = crossing
        roads[1] = road(roads[1].points, nil)
        XCTAssertTrue(Map3DRoadMarkings(roads, region: .finland).streetNames.isEmpty)
        roads[1] = road(roads[1].points, "Hallituskatu")
        XCTAssertTrue(Map3DRoadMarkings(roads, region: .finland).streetNames.isEmpty)
    }

    /// The letters of Finland's names (ä, ö, å) are among the glyphs.
    func testFinnishLettersHaveGlyphs() {
        for character in "Hallituskatu Pöykkölä Jääkärinkatu Åkerlundinkatu" where !character.isWhitespace {
            XCTAssertNotNil(Map3DBoardGlyphs.glyphs[character], "\(character)")
        }
    }

    /// A plate: as long as its name needs, within its bounds; the name's
    /// letters on both faces.
    func testThePlate() throws {
        var mesh = Map3DMesh()
        let text = Map3DBoardGlyphs.layout("Koskikatu")
        Map3DScene.Builder.addStreetNameSign(&mesh, foot: Map3DPoint(0, 0, 0), along: Map3DPoint(1, 0, 0), text: text)
        let xs = mesh.vertices.map(\.position.x), ys = mesh.vertices.map(\.position.y)
        XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, Map3DScene.Builder.streetNamePlateLongest + 0.001)
        XCTAssertEqual(ys.max()!, Map3DScene.Builder.streetNamePlateFoot + Map3DScene.Builder.streetNamePlateHeight, accuracy: 0.001)
        let white = mesh.vertices.filter { $0.color == Map3DPalette.sidewalk }
        XCTAssertEqual(white.count % 2, 0)
        XCTAssertTrue(white.contains { $0.position.z > 0 } && white.contains { $0.position.z < 0 })
    }

    /// Rovaniemi's town: its roads named from the base map, and signs at
    /// its junctions.
    func testRovaniemisJunctionsHaveStreetNames() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: 66.4990, longitude: 25.7200)
        let reach = 2_500.0
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: frame.middleX, originY: frame.middleY, names: true)
        let unnamed = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: frame.middleX, originY: frame.middleY)
        XCTAssertTrue(unnamed.roads.allSatisfy { $0.name == nil })
        let named = map.roads.filter { $0.name != nil }
        XCTAssertGreaterThan(named.count, map.roads.count / 3)
        XCTAssertTrue(named.contains { $0.name == "Hallituskatu" })
        let signs = Map3DRoadMarkings(map.roads, region: .finland).streetNames
        XCTAssertGreaterThan(signs.count, 40)
        XCTAssertTrue(Map3DRoadMarkings(map.roads, region: .taiwan).streetNames.isEmpty)
        for (index, sign) in signs.enumerated() {
            XCTAssertFalse(signs[..<index].contains { $0.name == sign.name && Map3DRoadMarkings.distance($0.foot, sign.foot) < Map3DRoadMarkings.streetNameApart })
        }
        print("Rovaniemi: \(named.count) of \(map.roads.count) roads named, \(signs.count) signs, \(Set(signs.map(\.name)).count) names")
    }
}
