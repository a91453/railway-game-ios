import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 846: the street furniture follows the region. Hong Kong's and
/// Finland's roundabouts have no signals; Finland's signals stand at the
/// kerb with red and amber before green; Hong Kong's and Finland's
/// pedestrian signals have no countdown's box; Finland has none of
/// Taiwan's utility poles or vending machines. Taiwan's streets are as
/// they were.
final class Map3DRoundaboutTests: XCTestCase {
    private typealias Point = Map3DBaseMap.Point
    private typealias Signal = Map3DPedestrianSignal

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [Point]) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points, bounds: everywhere)
    }

    /// A ring of `radius` round the origin, 24 points, closed; four
    /// secondary roads coming in from 200 m out, each meeting it at a
    /// point of it (not where it closes).
    private func roundabout(radius: Double = 15) -> [Map3DBaseMap.Road] {
        let ring = (0...24).map { index -> Point in
            let angle = Double(index % 24) / 24 * 2 * .pi
            return Point(x: cos(angle) * radius, z: sin(angle) * radius)
        }
        var roads = [road(.tertiary, ring)]
        for index in [3, 9, 15, 21] {
            let p = ring[index], out = Point(x: p.x / radius, z: p.z / radius)
            roads.append(road(.secondary, [p, Point(x: p.x + out.x * 200, z: p.z + out.z * 200)]))
        }
        return roads
    }

    func testTheRegionsStreetFurniture() {
        func flags(_ r: Map3DStreetRegion) -> [Bool] {
            [r.standsSignalsAtKerb, r.hasCountdownBoxes, r.signalsRoundabouts, r.hasUtilityPoles, r.hasVendingMachines]
        }
        XCTAssertEqual(flags(.taiwan), [false, true, true, true, true])
        XCTAssertEqual(flags(.hongKong), [true, false, false, true, true])
        XCTAssertEqual(flags(.finland), [true, false, false, false, false])
    }

    /// Finland's and Hong Kong's roundabouts: no signal, pedestrian signal,
    /// stop line or arrow; a crossing on each road coming in, clear of the
    /// ring; no light to wait at. Taiwan's keeps its signals.
    func testARoundaboutHasNoSignals() throws {
        for region in [Map3DStreetRegion.finland, .hongKong] {
            let markings = Map3DRoadMarkings(roundabout(), region: region)
            XCTAssertEqual(markings.junctions.count, 4, "\(region)")
            let ring = try XCTUnwrap(markings.roundabouts.first)
            XCTAssertEqual(markings.roundabouts.count, 1)
            XCTAssertEqual(ring.radius, 15, accuracy: 0.5)
            XCTAssertLessThan(Map3DRoadMarkings.distance(ring.centre, Point(x: 0, z: 0)), 0.5)
            XCTAssertEqual(markings.signals.count, 0)
            XCTAssertEqual(markings.walks.count, 0)
            XCTAssertEqual(markings.stops.count, 0)
            XCTAssertEqual(markings.crossings.count, 0)
            XCTAssertFalse(markings.marks.contains { $0.kind == .stopLine })
            let crosswalks = markings.marks.filter { $0.kind == .crosswalk }
            XCTAssertEqual(crosswalks.count, 4)
            for crosswalk in crosswalks {
                let out = Map3DRoadMarkings.distance(crosswalk.centre, ring.centre)
                XCTAssertGreaterThan(out, 15 + 2)
                XCTAssertLessThan(out, 15 + 15)
            }
        }
        let taiwan = Map3DRoadMarkings(roundabout())
        XCTAssertTrue(taiwan.roundabouts.isEmpty)
        XCTAssertGreaterThan(taiwan.signals.count, 0)
    }

    /// A junction where a road coming in splits round its island, near a
    /// ring: bare. One farther out keeps its signals.
    func testTheSplitBeforeARingIsBare() {
        let ring = Map3DRoadMarkings.Ring(centre: Point(x: 0, z: 0), radius: 15)
        let arms: [Map3DRoadMarkings.Arm] = []
        XCTAssertEqual(Map3DRoadMarkings.layout(at: Point(x: 50, z: 0), arms: arms, rings: [ring]), .bare)
        XCTAssertEqual(Map3DRoadMarkings.layout(at: Point(x: 15 + Map3DRoadMarkings.ringApproach + 1, z: 0), arms: arms, rings: [ring]), .signals)
        XCTAssertEqual(Map3DRoadMarkings.layout(at: Point(x: 0, z: 0), arms: arms, rings: [ring]), .signals)
        XCTAssertEqual(Map3DRoadMarkings.layout(at: Point(x: 16, z: 0), arms: arms, rings: []), .signals)
    }

    /// A road bending through a T junction, as tight as a ring, is not one:
    /// no road round the rest of the circle.
    func testABendIsNotARoundabout() {
        let radius = 30.0
        let bend = (0...8).map { index -> Point in
            let angle = Double(index) / 8 * .pi / 2
            return Point(x: cos(angle) * radius, z: sin(angle) * radius)
        }
        let roads = [road(.secondary, [Point(x: radius, z: -150)] + bend + [Point(x: -150, z: radius)]),
                     road(.secondary, [bend[4], Point(x: 200, z: 200)])]
        let markings = Map3DRoadMarkings(roads, region: .finland)
        XCTAssertEqual(markings.junctions.count, 1)
        XCTAssertTrue(markings.roundabouts.isEmpty)
        XCTAssertGreaterThan(markings.signals.count, 0)
    }

    func testTheCircleThroughThreePoints() throws {
        let circle = try XCTUnwrap(Map3DRoadMarkings.circle(Point(x: 10, z: 0), Point(x: 0, z: 10), Point(x: -10, z: 0)))
        XCTAssertEqual(circle.centre.x, 0, accuracy: 1e-9)
        XCTAssertEqual(circle.centre.z, 0, accuracy: 1e-9)
        XCTAssertEqual(circle.radius, 10, accuracy: 1e-9)
        XCTAssertNil(Map3DRoadMarkings.circle(Point(x: 0, z: 0), Point(x: 1, z: 1), Point(x: 2, z: 2)))
    }

    /// Rovaniemi's town: its roundabouts found, and their signals gone.
    func testRovaniemisRoundaboutsHaveNoSignals() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: 66.4990, longitude: 25.7200)
        let reach = 2_500.0
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: frame.middleX, originY: frame.middleY)
        let finland = Map3DRoadMarkings(map.roads, region: .finland), taiwan = Map3DRoadMarkings(map.roads, region: .taiwan)
        XCTAssertGreaterThanOrEqual(finland.roundabouts.count, 12)
        for ring in finland.roundabouts {
            XCTAssertTrue(Map3DRoadMarkings.ringRadii.contains(ring.radius))
            XCTAssertFalse(finland.signals.contains { Map3DRoadMarkings.distance($0.foot, ring.centre) < ring.radius + 20 },
                           "a signal at the ring round \(ring.centre)")
        }
        XCTAssertEqual(finland.junctions, taiwan.junctions)
        XCTAssertLessThan(finland.signals.count, taiwan.signals.count * 2 / 3)
    }

    // MARK: Pedestrian signals with no countdown

    func testThePlainFacesShowTheClockWithNoCountdown() throws {
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Signal.Models(pack: pack))
        let plain = try XCTUnwrap(models.plain)
        XCTAssertEqual(models.placed.plain, plain.stop)
        XCTAssertTrue(models.places(plain.stop))
        XCTAssertEqual(pack.models[plain.stop].name, Signal.plainStopName)
        func clock(_ second: Int64) -> Map3DSignalTiming.Clock {
            Map3DSignalTiming.Clock(GameClock(now: GameTime(seconds: second), speed: .x1), region: .finland)
        }
        var shown = Set<Int>()
        for second in Int64(0)..<Map3DSignalTiming.cycle {
            for time in [0.2, 0.7] {
                let model = models.model(plain.stop, group: 1, clock: clock(second), time: Double(second) + time, pace: Signal.Pace(), reduceMotion: false)
                shown.insert(try XCTUnwrap(model))
            }
        }
        XCTAssertEqual(shown, [plain.stop, plain.dark, plain.walk])
        // The two lights alone: fewer triangles than Taiwan's face, no box beside them.
        let taiwan = pack.models[models.placed.head], plainFace = pack.models[plain.stop]
        XCTAssertLessThan(plainFace.triangleCount, taiwan.triangleCount)
        XCTAssertLessThan(plainFace.maximum.x - plainFace.minimum.x, taiwan.maximum.x - taiwan.minimum.x)
        let run = Map3DPropRuns.Run(model: plain.stop, group: 0, first: 0, count: 3)
        XCTAssertEqual(models.triangles([run], in: pack), 3 * [plain.stop, plain.dark, plain.walk].map { pack.models[$0].triangleCount }.max()!)
    }

    /// Rovaniemi's scene: Hong Kong's kerbside signals and the plain
    /// pedestrian signals, none of Taiwan's signals, countdowns, utility
    /// poles or vending machines.
    func testRovaniemisStreetsHaveFinlandsFurniture() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 66.5028, longitude: 25.7285)
        let baseMap = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap, footprints: try RovaniemiBuildingsTests.tiles())
        let catalog = Map3DModelCatalog.standard
        var used = Set<String>()
        for chunk in scene.chunks { used.formUnion(chunk.props.map { catalog.names[$0.model] }) }
        XCTAssertTrue(used.contains(Signal.plainStopName))
        XCTAssertTrue(used.contains(Map3DHongKongSignal.placedName(.main)) || used.contains(Map3DHongKongSignal.placedName(.cross)))
        let taiwans = [Map3DProp.signalGo, .signalStop, .pole, .vending].map(\.modelName) + [Signal.stopName, Signal.onesName(0), Signal.tensName(1)]
        XCTAssertTrue(used.isDisjoint(with: taiwans), "\(used.intersection(taiwans))")
    }
}
