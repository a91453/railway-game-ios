import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 802: the 3D map draws Rovaniemi's streets and buildings as
/// Finland's; Taiwan's maps are drawn as they were. Decision 812: Hong
/// Kong's buildings as Hong Kong's.
final class Map3DRegionLookTests: XCTestCase {
    private typealias Point = Map3DBaseMap.Point

    private func anchor(_ latitude: Double, _ longitude: Double) throws -> GeoAnchor {
        try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
    }

    private func rovaniemi() throws -> GameWorld { GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground()) }

    private func hongKong() throws -> GameWorld { GameWorld.newOverseasGame(try HongKongBaseMapTests.ground()) }

    private func taipei() throws -> GameWorld { GameWorld.newGame(anchor: try anchor(25.0478, 121.5170)) }

    // MARK: The look by where the map is

    /// Taiwan's maps, with an anchor or none, keep every part of Taiwan's
    /// look; Hong Kong's has its own streets and (decision 812) buildings,
    /// and Taiwan's gauge and bare ground.
    func testTaiwanAndHongKongKeepTheirLook() throws {
        for world in [GameWorld.newGame(), try taipei(), GameWorld.newWholeTaiwanGame()] {
            XCTAssertEqual(Map3DRegionLook(world: world), .taiwan)
        }
        XCTAssertEqual(Map3DRegionLook(anchor: try anchor(24.4369, 118.3186)), .taiwan, "Kinmen")
        XCTAssertEqual(Map3DRegionLook.taiwan, Map3DRegionLook(streets: .taiwan, buildings: .taiwan, snow: false, gauge: 1.067))
        XCTAssertEqual(Map3DRegionLook(world: try hongKong()), Map3DRegionLook(streets: .hongKong, buildings: .hongKong, snow: false, gauge: 1.067))
    }

    func testRovaniemiHasFinlandsLook() throws {
        let look = Map3DRegionLook(world: try rovaniemi())
        XCTAssertEqual(look, Map3DRegionLook(streets: .finland, buildings: .nordic, snow: true, gauge: 1.524))
        // The three that asked the anchor on their own answer as the look.
        XCTAssertEqual(Map3DStreetRegion(world: try rovaniemi()), .finland)
        XCTAssertTrue(Map3DSnowGround.covers(try rovaniemi()))
        XCTAssertEqual(Map3DTrackGauge.metres(world: try rovaniemi()), 1.524)
        // Helsinki is Finland too; Tromsø is north but not Finland: snow,
        // and everything else as before.
        XCTAssertEqual(Map3DRegionLook(anchor: try anchor(60.1719, 24.9414)), look)
        XCTAssertEqual(Map3DRegionLook(anchor: try anchor(69.6492, 18.9553)),
                       Map3DRegionLook(streets: .taiwan, buildings: .taiwan, snow: true, gauge: 1.067))
    }

    /// What each region's streets have: Taiwan's and Hong Kong's as
    /// decisions 732 and 743 left them.
    func testTheStreetsOfEachRegion() {
        typealias Flags = [Bool]
        func flags(_ r: Map3DStreetRegion) -> Flags {
            [r.keepsLeft, r.hasScooterBoxes, r.hasRedKerbs, r.hasPaintedWalkways, r.hasYellowCentreLines, r.animatesPedestrianSignals,
             r.hasRedAmber, r.hasEveningGarbageTrucks, r.hasTaiwanPostBoxes, r.hasKerbLines, r.hasScooters, r.hasYellowTaxis]
        }
        XCTAssertEqual(flags(.taiwan), [false, true, true, true, true, true, false, true, true, true, true, true])
        XCTAssertEqual(flags(.hongKong), [true, false, false, false, false, false, true, false, false, true, true, false])
        XCTAssertEqual(flags(.finland), [false, false, false, false, false, false, true, false, false, false, false, false])
        XCTAssertEqual(Map3DStreetRegion.taiwan.sidewalk, Map3DPalette.sidewalk)
        XCTAssertEqual(Map3DStreetRegion.hongKong.sidewalk, Map3DPalette.sidewalk)
        XCTAssertEqual(Map3DStreetRegion.finland.sidewalk, Map3DPalette.paved)
        XCTAssertEqual(Map3DStreetRegion.finland.trafficSide, 1)
    }

    // MARK: Streets

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)]) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
    }

    /// Finland's roads have their crossings, stop lines and arrows, and
    /// none of Taiwan's scooter boxes, kerb lines or painted walkways.
    func testFinlandsRoadsHaveNoneOfTaiwansPaint() {
        let roads = [road(.trunk, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, -200), (0, 0), (0, 200)]),
                     road(.minor, [(-200, 120), (0, 120), (200, 120)])]
        func taiwanOnly(_ kind: Map3DRoadMarkings.Kind) -> Bool {
            switch kind {
            case .scooterBox, .kerb, .walkway: true
            default: false
            }
        }
        let taiwan = Map3DRoadMarkings(roads), finland = Map3DRoadMarkings(roads, region: .finland)
        XCTAssertTrue(taiwan.marks.contains { $0.kind == .kerb(red: true) })
        XCTAssertTrue(taiwan.marks.contains { $0.kind == .scooterBox(turn: false) })
        XCTAssertTrue(taiwan.marks.contains { $0.kind == .walkway(line: false) })
        XCTAssertFalse(finland.marks.contains { taiwanOnly($0.kind) })
        // The rest is Taiwan's, mark for mark (both drive on the right).
        XCTAssertEqual(finland.marks.map(\.kind), taiwan.marks.map(\.kind).filter { !taiwanOnly($0) })
        XCTAssertEqual(finland.signals.count, taiwan.signals.count)
    }

    private func vehicles(_ region: Map3DStreetRegion?) throws -> [Map3DStreetLife.Vehicle] {
        var all: [Map3DStreetLife.Vehicle] = []
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(2_000, 0, 0)]))
        for seed in Int32(0)..<10 {
            var lane = Map3DStreetLife.Lane(path: path, half: 5, twoWay: true, speed: 11, perHundred: 6, scooters: true, seed: (seed, 7))
            lane.buses = true
            for index in 0..<200 {
                all.append(region.map { Map3DStreetLife.vehicle(index, of: 200, lane: lane, direction: 1, spacing: 20, buses: true, besides: true, region: $0) }
                    ?? Map3DStreetLife.vehicle(index, of: 200, lane: lane, direction: 1, spacing: 20, buses: true, besides: true))
            }
        }
        return all
    }

    /// No scooter and no yellow taxi on Finland's streets; Taiwan's
    /// traffic is vehicle for vehicle what it was.
    func testFinlandsTrafficHasNoScooters() throws {
        let finland = try vehicles(.finland), taiwan = try vehicles(.taiwan)
        XCTAssertFalse(finland.contains { $0.model.isScooter || $0.beside != nil })
        let yellow = try XCTUnwrap(Map3DStreetLife.carPaints.last)
        XCTAssertFalse(finland.contains { !$0.model.isBus && $0.tint == yellow })
        XCTAssertTrue(taiwan.contains { $0.model.isScooter })
        XCTAssertTrue(taiwan.contains { $0.model == .car && $0.tint == yellow })
        let plain = try vehicles(nil)
        XCTAssertEqual(taiwan.map(\.model), plain.map(\.model))
        XCTAssertEqual(taiwan.map(\.tint), plain.map(\.tint))
    }

    // MARK: Buildings

    /// The near mesh of real buildings of `kind` and `storeys`, 8 × 11 m,
    /// at forty places in `world`.
    private func buildings(in world: GameWorld, kind: Map3DScene.Builder.RealKind, storeys: Int) -> Map3DMesh {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.target = .near
        for place in 0..<40 {
            let at = Map3DPoint(Float(place % 8) * 40, 0, Float(place / 8) * 40)
            let ring = [Map3DPoint(0, 0, 0), Map3DPoint(8, 0, 0), Map3DPoint(8, 0, 11), Map3DPoint(0, 0, 11)].map { $0 + at }
            builder.addRealBuilding([[ring]], ground: 0, height: Float(storeys) * 3.2, storeys: storeys, kind: kind)
        }
        return builder.nearMeshes.values.reduce(into: Map3DMesh()) { $0.append($1) }
    }

    private func sameMesh(_ a: Map3DMesh, _ b: Map3DMesh) -> Bool {
        a.indices == b.indices && a.vertices.count == b.vertices.count
            && zip(a.vertices, b.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z && $0.color == $1.color && $0.layer == $1.layer }
    }

    /// The same building is drawn the same on a generated map and a map
    /// of Taipei: vertex for vertex.
    func testTaiwansBuildingsAreDrawnAlike() throws {
        for (kind, storeys) in [(Map3DScene.Builder.RealKind.house, 2), (.shophouse, 4), (.flats, 6), (.flats, 14), (.office, 12), (.temple, 1),
                                (.civic, 3), (.industry, 1)] {
            let plain = buildings(in: GameWorld.newGame(), kind: kind, storeys: storeys)
            XCTAssertFalse(plain.vertices.isEmpty)
            XCTAssertTrue(sameMesh(plain, buildings(in: try taipei(), kind: kind, storeys: storeys)), "\(kind) in Taipei")
        }
    }

    /// Decision 812: Hong Kong's buildings are drawn as Hong Kong's: no
    /// Taiwanese water tank, no blue, green or red waterproofing on a
    /// roof; a tower of flats crowned with its lift room and tank; shops
    /// on a tenement's pavement with no arcade; an office in the glass of
    /// its palette; the same kinds Taiwan's draws alike drawn otherwise.
    func testHongKongsBuildingsAreHongKongs() throws {
        let world = try hongKong()
        let tanks: Set<UInt32> = [Map3DPalette.tankBlue, Map3DPalette.tankSteel]
        let taiwanRoofs = Set(Map3DPalette.cityRoofs.map(\.color).filter { $0 != Map3DPalette.roof } + Map3DPalette.tinRoofs)
        for (kind, storeys) in [(Map3DScene.Builder.RealKind.house, 2), (.shophouse, 4), (.flats, 6), (.flats, 14), (.office, 12), (.civic, 3),
                                (.industry, 1)] {
            let mesh = buildings(in: world, kind: kind, storeys: storeys)
            XCTAssertFalse(mesh.vertices.isEmpty)
            XCTAssertFalse(sameMesh(mesh, buildings(in: GameWorld.newGame(), kind: kind, storeys: storeys)), "\(kind) \(storeys)")
            XCTAssertFalse(mesh.vertices.contains { tanks.contains($0.color) }, "\(kind) \(storeys)")
            XCTAssertFalse(mesh.vertices.contains { taiwanRoofs.contains($0.color) }, "\(kind) \(storeys)")
        }
        // A tower's crown: its machine room and tank 7.4 m over its roof
        // (14 storeys, 44.8 m), on every one of the forty.
        let tower = buildings(in: world, kind: .flats, storeys: 14)
        XCTAssertEqual(tower.vertices.map(\.y).max() ?? 0, 14 * 3.2 + Map3DHongKong.crownHeight + 2.4, accuracy: 0.01)
        let tops = tower.vertices.filter { abs($0.y - (14 * 3.2 + Map3DHongKong.crownHeight + 2.4)) < 0.01 }
        XCTAssertEqual(Set(tops.map { Int(($0.x / 40).rounded(.down)) + 8 * Int(($0.z / 40).rounded(.down)) }).count, 40)
        // A tenement's walls and an office's glass from their palettes.
        func walls(_ mesh: Map3DMesh) -> Set<UInt32> { Set(mesh.vertices.filter { $0.ny == 0 && $0.y > 6 }.map(\.color)) }
        let tenement = Set(Map3DHongKong.tenementWalls.flatMap { wall in (0...8).map { Map3DColor.shaded(wall, 1 - 0.01 * Float($0)) } })
        XCTAssertFalse(walls(buildings(in: world, kind: .flats, storeys: 6)).isDisjoint(with: tenement))
        let glass = Map3DHongKong.glass.map { Map3DLook.colour($0) }
        XCTAssertTrue(walls(buildings(in: world, kind: .office, storeys: 12)).contains { wall in
            glass.contains { near(Map3DLook.colour(wall), $0, by: 24) }
        })
    }

    /// Whether two colours are within `step` of each other in every channel.
    private func near(_ a: UInt32, _ b: UInt32, by step: Int = 3) -> Bool {
        (0..<3).allSatisfy { abs(Int((a >> ($0 * 8)) & 0xFF) - Int((b >> ($0 * 8)) & 0xFF)) <= step }
    }

    /// A Taiwanese house's roof has a water tank or a sheet-steel room on
    /// most; a Finnish one's has neither, and a ridge over its eaves.
    func testAFinnishHouseStandsUnderAPitchedRoofWithNothingOnIt() throws {
        let tanks: Set<UInt32> = [Map3DPalette.tankBlue, Map3DPalette.tankSteel]
        let taiwan = buildings(in: GameWorld.newGame(), kind: .house, storeys: 2)
        XCTAssertTrue(taiwan.vertices.contains { tanks.contains($0.color) })
        let finland = buildings(in: try rovaniemi(), kind: .house, storeys: 2)
        XCTAssertFalse(finland.vertices.contains { tanks.contains($0.color) })
        // Eaves at 6.4 m, the ridge a quarter of the 8 m span above them;
        // nothing higher (a Taiwanese tank stands 2.2 m over the roof).
        XCTAssertEqual(finland.vertices.map(\.y).max() ?? 0, 6.4 + 4 * Map3DNordic.pitch, accuracy: 0.01)
        // 40 houses: 8 triangles of walls and 6 of roof each, 4 more than
        // under a flat roof.
        XCTAssertEqual(finland.triangleCount, 40 * 14)
        // A block of flats keeps its flat roof, with nothing on it but its plant.
        let flats = buildings(in: try rovaniemi(), kind: .house, storeys: 4)
        XCTAssertFalse(flats.vertices.contains { tanks.contains($0.color) })
    }

    /// On a Finnish map a place of worship is no Taiwanese temple: no
    /// temple red or orange roof.
    func testNoTaiwaneseTempleInFinland() throws {
        let temple: Set<UInt32> = [Map3DPalette.templeWall, Map3DPalette.templeRoof]
        XCTAssertTrue(buildings(in: GameWorld.newGame(), kind: .temple, storeys: 1).vertices.contains { temple.contains($0.color) })
        XCTAssertFalse(buildings(in: try rovaniemi(), kind: .temple, storeys: 1).vertices.contains { temple.contains($0.color) })
    }

    /// A house the game lays along a road: Taiwan's as it was whether the
    /// look is named or not; Finland's a box and a pitched roof, far fewer
    /// triangles, with no sign.
    func testTheHousesAlongTheRoads() {
        func house(_ look: Map3DRegionLook?, flats: Bool, far: Bool) -> (mesh: Map3DMesh, close: Map3DMesh, blades: Int) {
            var mesh = Map3DMesh(), close = Map3DMesh(), blades: [Map3DSign] = []
            for seed in Int32(0)..<30 {
                let r = { (salt: Int32) in map3DRandom(seed, 11, salt: salt) }
                let middle = Map3DPoint(Float(seed) * 20, 0, 0), front = Map3DPoint(0, 0, 1), wall = Map3DPalette.houseWalls[0].color
                if let look {
                    Map3DScene.Builder.addTownHouse(&mesh, close: &close, blades: &blades, middle: middle, front: front, width: 9, depth: 12,
                                                    flats: flats, shops: true, wall: wall, far: far, look: look, r: r)
                } else {
                    Map3DScene.Builder.addTownHouse(&mesh, close: &close, blades: &blades, middle: middle, front: front, width: 9, depth: 12,
                                                    flats: flats, shops: true, wall: wall, far: far, r: r)
                }
            }
            return (mesh, close, blades.count)
        }
        let finland = Map3DRegionLook(streets: .finland, buildings: .nordic, snow: true, gauge: 1.524)
        for flats in [false, true] {
            for far in [false, true] {
                let plain = house(nil, flats: flats, far: far), taiwan = house(.taiwan, flats: flats, far: far)
                XCTAssertTrue(sameMesh(plain.mesh, taiwan.mesh) && sameMesh(plain.close, taiwan.close) && plain.blades == taiwan.blades)
                let nordic = house(finland, flats: flats, far: far)
                XCTAssertLessThanOrEqual(nordic.mesh.triangleCount, 30 * 26, "flats \(flats), far \(far)")
                XCTAssertLessThan(nordic.mesh.triangleCount, taiwan.mesh.triangleCount)
                XCTAssertTrue(nordic.close.isEmpty)
                XCTAssertEqual(nordic.blades, 0)
                let tanks: Set<UInt32> = [Map3DPalette.tankBlue, Map3DPalette.tankSteel]
                XCTAssertFalse(nordic.mesh.vertices.contains { tanks.contains($0.color) })
            }
        }
        // Decision 812: Hong Kong's: no Taiwanese tank, sign or close
        // detail; a tower crowned.
        let hongKong = Map3DRegionLook(streets: .hongKong, buildings: .hongKong, snow: false, gauge: 1.067)
        for flats in [false, true] {
            for far in [false, true] {
                let houses = house(hongKong, flats: flats, far: far)
                XCTAssertFalse(houses.mesh.vertices.isEmpty)
                XCTAssertTrue(houses.close.isEmpty)
                XCTAssertEqual(houses.blades, 0)
                XCTAssertFalse(houses.mesh.vertices.contains { [Map3DPalette.tankBlue, Map3DPalette.tankSteel].contains($0.color) })
            }
        }
        // A wooden house: one or two floors and its roof.
        let houses = house(finland, flats: false, far: false).mesh
        XCTAssertLessThanOrEqual(houses.vertices.map(\.y).max() ?? 0, 0.4 + 2 * Map3DNordic.storey + 4.5 * Map3DNordic.pitch)
    }

    // MARK: Colours

    /// The Nordic and Hong Kong palettes are written as the map draws them: through the
    /// city's look each colour comes out within a step of what was written.
    func testThePaletteIsDrawnAsWritten() {
        func near(_ a: UInt32, _ b: UInt32) -> Bool {
            (0..<3).allSatisfy { abs(Int((a >> ($0 * 8)) & 0xFF) - Int((b >> ($0 * 8)) & 0xFF)) <= 3 }
        }
        // Decision 812: Hong Kong's too.
        for written: UInt32 in [0xE2B65E, 0xB5523E, 0xF2EFE6, 0xA2A8B1, 0xBC8478, 0xC6CBD8, 0x9DB3A3, 0xF2EFE8, 0xE9C8BA, 0xD9C9AE, 0xA9BDBB,
                                0x608E9D, 0xCFD0CC] {
            let colour = Map3DColor.rgb(written)
            XCTAssertTrue(near(Map3DLook.colour(Map3DLook.source(drawing: colour)), colour), String(written, radix: 16))
        }
        // A roof under snow is drawn between its colour and the snow.
        let blue = Map3DPalette.hallRoofs[0], drawn = Map3DLook.colour(blue), snowed = Map3DLook.colour(Map3DSnowGround.roof(blue))
        func channels(_ c: UInt32) -> [Int] { (0..<3).map { Int((c >> ($0 * 8)) & 0xFF) } }
        for (index, value) in channels(snowed).enumerated() {
            let from = channels(drawn)[index], to = channels(Map3DSnowGround.roofSnow)[index]
            XCTAssertTrue((min(from, to) - 3...max(from, to) + 3).contains(value))
            XCTAssertGreaterThan(abs(value - from), abs(to - from) / 4)
        }
    }

    /// The scene round Rovaniemi's centre, with its streets and
    /// buildings: no yellow centre line, no water tank, and the pale
    /// paving beside the roads.
    func testRovaniemisSceneHasNoneOfTaiwansStreets() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 66.5028, longitude: 25.7285)
        let baseMap = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap, footprints: try RovaniemiBuildingsTests.tiles())
        var colours = Set<UInt32>()
        for chunk in scene.chunks { colours.formUnion(chunk.mesh.vertices.map(\.color)) }
        XCTAssertTrue(colours.isDisjoint(with: [Map3DPalette.centreLine, Map3DPalette.tankBlue]))
        XCTAssertTrue(colours.contains(Map3DPalette.paved))
        XCTAssertGreaterThan(scene.triangleCount, 50_000)
    }
}
