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
            [r.standsSignalsAtKerb, r.hasCountdownBoxes, r.signalsRoundabouts, r.hasUtilityPoles, r.hasVendingMachines, r.hasFinnishFurniture]
        }
        XCTAssertEqual(flags(.taiwan), [false, true, true, true, true, false])
        XCTAssertEqual(flags(.hongKong), [true, false, false, true, true, false])
        XCTAssertEqual(flags(.finland), [true, false, false, false, false, true])
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
            // Decision 846's later note: Finland's sign at each crossing,
            // one a way, on the pavement just before the bars; none in
            // Hong Kong.
            XCTAssertEqual(markings.crossingSigns.count, region == .finland ? 8 : 0)
            for sign in markings.crossingSigns {
                let crosswalk = try XCTUnwrap(crosswalks.min { Map3DRoadMarkings.distance($0.centre, sign.foot) < Map3DRoadMarkings.distance($1.centre, sign.foot) })
                let offset = Point(x: sign.foot.x - crosswalk.centre.x, z: sign.foot.z - crosswalk.centre.z)
                // Before the bars the way its traffic goes, off the carriageway.
                XCTAssertEqual(offset.x * sign.along.x + offset.z * sign.along.z, -(Map3DRoadMarkings.crosswalkDepth / 2 + 0.5), accuracy: 0.01)
                XCTAssertGreaterThan(abs(offset.x * sign.along.z - offset.z * sign.along.x), crosswalk.width / 2)
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

    /// Decision 846's second later note: Finland's give-way line on each
    /// road coming into the ring, at the ring's edge, across the lanes
    /// coming in only, its triangles pointing back at the traffic; none in
    /// Hong Kong. A one-way road into the ring: kerb to kerb; out of it:
    /// none.
    func testFinlandsRoundaboutHasGiveWayLines() throws {
        XCTAssertFalse(Map3DRoadMarkings(roundabout(), region: .hongKong).marks.contains { $0.kind == .giveWay })
        let markings = Map3DRoadMarkings(roundabout(), region: .finland)
        let teeth = markings.marks.filter { $0.kind == .giveWay }
        let half = Double(Map3DBaseMap.RoadKind.secondary.width(ramp: false)) / 2
        let ringHalf = Double(Map3DBaseMap.RoadKind.tertiary.width(ramp: false)) / 2
        // Four a road (a secondary road's 4 m each way), four roads.
        XCTAssertEqual(teeth.count, 16)
        for tooth in teeth {
            XCTAssertEqual(tooth.length, Map3DRoadMarkings.giveWayLength)
            XCTAssertEqual(tooth.width, Map3DRoadMarkings.giveWayWidth)
            // The road it is on: the way out of the four nearest it.
            let out = try XCTUnwrap([3.0, 9, 15, 21].map { Point(x: cos($0 / 24 * 2 * .pi), z: sin($0 / 24 * 2 * .pi)) }
                .max { $0.x * tooth.centre.x + $0.z * tooth.centre.z < $1.x * tooth.centre.x + $1.z * tooth.centre.z })
            let radial = Map3DRoadMarkings.distance(tooth.centre, Point(x: 0, z: 0))
            // Just outside the ring's kerb, before the crossing.
            XCTAssertGreaterThan(radial, 15 + ringHalf)
            XCTAssertLessThan(radial, 15 + ringHalf + Map3DRoadMarkings.kerbGap)
            // Its traffic goes in toward the ring.
            XCTAssertLessThan(out.x * tooth.along.x + out.z * tooth.along.z, -0.9)
            // On the half Finland's incoming traffic keeps to: its right.
            let right = Point(x: -tooth.along.z, z: tooth.along.x)
            let side = tooth.centre.x * right.x + tooth.centre.z * right.z
            XCTAssertGreaterThan(side, 0)
            XCTAssertLessThan(side, half)
        }
        // Decision 846's fourth later note: a give-way sign each road
        // coming in, on the kerb of its traffic's side beside the line,
        // looking at that traffic; none in Hong Kong.
        XCTAssertTrue(Map3DRoadMarkings(roundabout(), region: .hongKong).giveWaySigns.isEmpty)
        XCTAssertEqual(markings.giveWaySigns.count, 4)
        for sign in markings.giveWaySigns {
            let radial = Map3DRoadMarkings.distance(sign.foot, Point(x: 0, z: 0))
            XCTAssertGreaterThan(radial, 15 + ringHalf)
            XCTAssertLessThan(radial, 15 + ringHalf + Map3DRoadMarkings.kerbGap + 1)
            XCTAssertLessThan(sign.foot.x * sign.along.x + sign.foot.z * sign.along.z, 0)
            let right = Point(x: -sign.along.z, z: sign.along.x)
            XCTAssertGreaterThan(sign.foot.x * right.x + sign.foot.z * right.z, half)
        }
        // One-way: one road into the ring, one out of it.
        var roads = roundabout()
        roads[1] = Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: roads[1].points.reversed(), bounds: everywhere, oneway: true)
        roads[2].oneway = true
        let oneWay = Map3DRoadMarkings(roads, region: .finland).marks.filter { $0.kind == .giveWay }
        let into = roads[1].points.last!, outOf = roads[2].points.first!
        func near(_ p: Point) -> Int { oneWay.count { Map3DRoadMarkings.distance($0.centre, p) < 10 } }
        XCTAssertEqual(near(into), 8)
        XCTAssertEqual(near(outOf), 0)
        XCTAssertEqual(oneWay.count, 8 + 4 + 4)
        XCTAssertEqual(Map3DRoadMarkings(roads, region: .finland).giveWaySigns.count, 3)
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
        // Decision 846's second later note: their give-way lines, every
        // triangle near a ring; none in Taiwan's look.
        let teeth = finland.marks.filter { $0.kind == .giveWay }
        XCTAssertGreaterThanOrEqual(teeth.count, finland.roundabouts.count * 4)
        for tooth in teeth {
            XCTAssertTrue(finland.roundabouts.contains { Map3DRoadMarkings.distance(tooth.centre, $0.centre) < $0.radius + 20 })
        }
        XCTAssertFalse(taiwan.marks.contains { $0.kind == .giveWay })
        // Its fourth later note: a give-way sign at each road coming in.
        XCTAssertGreaterThanOrEqual(finland.giveWaySigns.count, finland.roundabouts.count * 2)
        XCTAssertLessThanOrEqual(finland.giveWaySigns.count, teeth.count)
        XCTAssertTrue(taiwan.giveWaySigns.isEmpty)
        print("Rovaniemi: \(finland.roundabouts.count) roundabouts, \(teeth.count) give-way triangles, \(finland.giveWaySigns.count) give-way signs")
    }

    /// Decision 846's fourth later note: a divided road's other carriageway
    /// found across its median, the one running the other way alone, near
    /// enough.
    func testTheOtherCarriagewayIsFound() {
        func way(_ z: Double, _ forward: Bool) -> Map3DBaseMap.Road {
            let points = [Point(x: -200, z: z), Point(x: 0, z: z), Point(x: 200, z: z)]
            return Map3DBaseMap.Road(kind: .primary, isRamp: false, points: forward ? points : points.reversed(), bounds: everywhere, oneway: true)
        }
        // Eastbound at z 0; westbound 14 m to its left (north, −z).
        let ways = Map3DScene.Builder.carriageways([way(0, true), way(-14, false), way(-60, false)])
        let left = Point(x: 0, z: -1), east = Point(x: 1, z: 0)
        XCTAssertEqual(try XCTUnwrap(ways.gap(from: Point(x: 30, z: 0), along: east, toward: left, half: 4.5)), 14, accuracy: 1e-9)
        // None to its right, none running the same way, none too far.
        XCTAssertNil(ways.gap(from: Point(x: 30, z: 0), along: east, toward: Point(x: 0, z: 1), half: 4.5))
        XCTAssertNil(Map3DScene.Builder.carriageways([way(0, true), way(-14, true)]).gap(from: Point(x: 30, z: 0), along: east, toward: left, half: 4.5))
        XCTAssertNil(Map3DScene.Builder.carriageways([way(0, true), way(-40, false)]).gap(from: Point(x: 30, z: 0), along: east, toward: left, half: 4.5))
        // Nor one so near that the two primary roads' 9 m touch with no
        // median between.
        XCTAssertNil(Map3DScene.Builder.carriageways([way(0, true), way(-9.5, false)]).gap(from: Point(x: 30, z: 0), along: east, toward: left, half: 4.5))
        // Two-way roads are not carriageways.
        var twoWay = way(-14, false)
        twoWay.oneway = false
        XCTAssertNil(Map3DScene.Builder.carriageways([way(0, true), twoWay]).gap(from: Point(x: 30, z: 0), along: east, toward: left, half: 4.5))
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

    /// Rovaniemi's scene: Finland's own signals, pedestrian signals,
    /// street lights and crossing signs (decision 846's later note), none
    /// of Hong Kong's or Taiwan's signals, countdowns, street lights,
    /// utility poles or vending machines.
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
        typealias Unit = Map3DFinlandStreet.Unit
        XCTAssertTrue(used.contains(Unit.walkStop.rawValue))
        XCTAssertTrue(used.contains(Unit.signalGreen.rawValue) || used.contains(Unit.signalRed.rawValue))
        XCTAssertTrue(used.contains(Unit.lamp.rawValue))
        XCTAssertTrue(used.contains(Unit.crossingSign.rawValue))
        // Decision 846's fourth later note: the second batch too.
        var count: [String: Int] = [:]
        for chunk in scene.chunks { for prop in chunk.props { count[catalog.names[prop.model], default: 0] += 1 } }
        print("Rovaniemi scene: \(count[Unit.shelter.rawValue] ?? 0) shelters, \(count[Unit.busStop.rawValue] ?? 0) bus stop signs, "
              + "\(count[Unit.lampDouble.rawValue] ?? 0) double lights, \(count[Unit.lamp.rawValue] ?? 0) lights, \(count[Unit.giveWaySign.rawValue] ?? 0) give-way signs")
        XCTAssertTrue(used.contains(Unit.shelter.rawValue))
        XCTAssertTrue(used.contains(Unit.lampDouble.rawValue))
        XCTAssertTrue(used.contains(Unit.giveWaySign.rawValue))
        let others = [Map3DProp.signalGo, .signalStop, .lamp, .busStop, .pole, .vending].map(\.modelName)
            + [Signal.stopName, Signal.onesName(0), Signal.tensName(1), Signal.plainStopName, Map3DSceneryProp.busStopPole.modelName]
            + Map3DSignalTiming.Light.allCases.map(Map3DHongKongSignal.modelName)
        XCTAssertTrue(used.isDisjoint(with: others), "\(used.intersection(others))")
    }
}
