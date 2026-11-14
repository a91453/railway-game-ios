import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 732: the 3D map's streets follow the place the map is of: on
/// Hong Kong's map the traffic keeps left, its signals show red and amber
/// before green and its green man stands still with no countdown; Taiwan's
/// streets are as they were.
final class Map3DStreetRegionTests: XCTestCase {
    private typealias Timing = Map3DSignalTiming
    private typealias Signal = Map3DPedestrianSignal
    private typealias Point = Map3DBaseMap.Point

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)]) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
    }

    /// A trunk road along x and a secondary along z crossing at the
    /// origin: four arms, the trunk's wide enough for two lanes each way.
    private var crossroads: [Map3DBaseMap.Road] {
        [road(.trunk, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, -200), (0, 0), (0, 200)])]
    }

    private func clock(_ second: Int64, region: Map3DStreetRegion, paused: Bool = false) -> Timing.Clock {
        var clock = GameClock(now: GameTime(seconds: second), speed: .x1)
        if paused { clock.pause() }
        return Timing.Clock(clock, region: region)
    }

    func testTheRegionIsHongKongOnlyOnHongKongsMap() throws {
        XCTAssertEqual(Map3DStreetRegion(world: GameWorld.newGame()), .taiwan)
        // Taipei Main Station, Kinmen and Hong Kong's airport station.
        let taipei = try XCTUnwrap(GeoAnchor(latitude: 250_477_000, longitude: 1_215_171_000))
        let kinmen = try XCTUnwrap(GeoAnchor(latitude: 244_360_000, longitude: 1_183_180_000))
        let airport = try XCTUnwrap(GeoAnchor(latitude: 223_159_010, longitude: 1_139_365_170))
        XCTAssertEqual(Map3DStreetRegion(anchor: taipei), .taiwan)
        XCTAssertEqual(Map3DStreetRegion(anchor: kinmen), .taiwan)
        XCTAssertEqual(Map3DStreetRegion(anchor: airport), .hongKong)
        let ground = try HongKongBaseMapTests.ground()
        XCTAssertEqual(Map3DStreetRegion(world: GameWorld.newOverseasGame(ground)), .hongKong)
        XCTAssertEqual(Map3DStreetRegion(world: GameWorld.newWholeTaiwanGame()), .taiwan)
    }

    func testHongKongsTrafficStopsAndIsSignalledOnTheLeft() {
        let taiwan = Map3DRoadMarkings(crossroads), hongKong = Map3DRoadMarkings(crossroads, region: .hongKong)
        let stops = hongKong.marks.filter { $0.kind == .stopLine }
        XCTAssertEqual(stops.count, 4)
        for stop in stops {
            // Across the incoming half: the left of the way in.
            let right = Point(x: -stop.along.z, z: stop.along.x)
            XCTAssertLessThan(Map3DRoadMarkings.dot(right, stop.centre), -0.5)
        }
        XCTAssertEqual(hongKong.signals.count, 4)
        for signal in hongKong.signals {
            let right = Point(x: -signal.along.z, z: signal.along.x)
            let half = abs(signal.along.x) > 0.9 ? 5.5 : 4.0
            XCTAssertLessThan(Map3DRoadMarkings.dot(right, signal.foot), -half, "at the kerb on the left of the way in")
        }
        // The same signals as Taiwan's, facing the same roads in the same
        // groups (nearer the junction: no scooter box before the stop
        // line).
        XCTAssertEqual(taiwan.signals.map(\.road), hongKong.signals.map(\.road))
        XCTAssertEqual(taiwan.signals.map(\.group), hongKong.signals.map(\.group))
        // The trunk's two lanes each way: the inner one through and right
        // (the turn arrow mirrored), nearer the middle.
        let arrows = hongKong.marks.filter { if case .arrow = $0.kind { return true } else { return false } }
        XCTAssertFalse(arrows.isEmpty)
        for arrow in arrows {
            guard case .arrow(let turn, let mirrored) = arrow.kind else { continue }
            XCTAssertTrue(mirrored)
            if turn {
                let right = Point(x: -arrow.along.z, z: arrow.along.x)
                XCTAssertLessThan(abs(Map3DRoadMarkings.dot(right, arrow.centre)), 2.75)
            }
        }
        XCTAssertTrue(arrows.contains { $0.kind == .arrow(left: true, mirrored: true) })
        // Taiwan's are as before.
        XCTAssertTrue(taiwan.marks.allSatisfy { if case .arrow(_, let mirrored) = $0.kind { return !mirrored } else { return true } })
    }

    func testHongKongsRoadsHaveNoScooterBoxesRedKerbsOrPaintedWalkways() {
        let lane = road(.minor, [(-300, 40), (300, 40)])
        let roads = crossroads + [lane]
        let taiwan = Map3DRoadMarkings(roads), hongKong = Map3DRoadMarkings(roads, region: .hongKong)
        func count(_ markings: Map3DRoadMarkings, _ test: (Map3DRoadMarkings.Kind) -> Bool) -> Int {
            markings.marks.filter { test($0.kind) }.count
        }
        func scooter(_ kind: Map3DRoadMarkings.Kind) -> Bool { if case .scooterBox = kind { return true } else { return false } }
        func walkway(_ kind: Map3DRoadMarkings.Kind) -> Bool { if case .walkway = kind { return true } else { return false } }
        XCTAssertGreaterThan(count(taiwan, scooter), 0)
        XCTAssertGreaterThan(count(taiwan) { $0 == .kerb(red: true) }, 0)
        XCTAssertGreaterThan(count(taiwan, walkway), 0)
        XCTAssertEqual(count(hongKong, scooter), 0)
        XCTAssertEqual(count(hongKong) { $0 == .kerb(red: true) }, 0)
        XCTAssertEqual(count(hongKong, walkway), 0)
        // The kerb lines are there, yellow, as many as Taiwan's red and
        // yellow together.
        XCTAssertEqual(count(hongKong) { $0 == .kerb(red: false) }, count(taiwan) { if case .kerb = $0 { return true } else { return false } })
    }

    func testHongKongsSignalsShowRedAndAmberJustBeforeGreen() {
        for road in [Timing.Road.main, .cross] {
            let other: Timing.Road = road == .main ? .cross : .main
            var redAmber: [Int64] = []
            for second in Int64(0)..<Timing.cycle {
                let light = Timing.light(road, at: second, region: .hongKong)
                // Taiwan's never.
                XCTAssertEqual(Timing.light(road, at: second, region: .taiwan), Timing.light(road, at: second))
                guard light == .redAmber else {
                    XCTAssertEqual(light, Timing.light(road, at: second), "\(road) at \(second)")
                    continue
                }
                redAmber.append(second)
                // Red before, green within two seconds after, the other
                // road red meanwhile.
                XCTAssertEqual(Timing.light(road, at: second), .red)
                XCTAssertTrue((1...Timing.redAmberSeconds).contains { Timing.light(road, at: second + $0) == .green })
                XCTAssertEqual(Timing.light(other, at: second), .red)
            }
            // The main road's two seconds (the crossing road red from
            // 67 s), the crossing road's one (the main road amber to 35 s).
            XCTAssertEqual(redAmber, road == .main ? [68, 69] : [35], "\(road)")
        }
        let models = Timing.Models(pack: .standard)
        XCTAssertNotNil(models?.hongKong)
    }

    func testTheRendererDrawsHongKongsSignalsWithTheirOwnLights() throws {
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Timing.Models(pack: pack))
        let index = { (light: Timing.Light) in try XCTUnwrap(pack.index(of: Map3DHongKongSignal.modelName(light))) }
        let green = try index(.green), red = try index(.red), amber = try index(.amber), redAmber = try index(.redAmber)
        XCTAssertEqual(Map3DHongKongSignal.placedName(.main), Map3DHongKongSignal.modelName(.green))
        XCTAssertEqual(Map3DHongKongSignal.placedName(.cross), Map3DHongKongSignal.modelName(.red))
        XCTAssertEqual(models.model(green, group: 0, clock: nil), green)
        XCTAssertEqual(models.model(red, group: 0, clock: nil), red)
        XCTAssertEqual(models.model(green, group: 0, clock: clock(33, region: .hongKong)), amber)
        XCTAssertEqual(models.model(green, group: 0, clock: clock(68, region: .hongKong)), redAmber)
        XCTAssertEqual(models.model(red, group: 0, clock: clock(35, region: .hongKong)), redAmber)
        XCTAssertEqual(models.model(red, group: 0, clock: clock(40, region: .hongKong)), green)
        // Taiwan's signals never show red and amber, whatever the clock.
        let taiwanRed = try XCTUnwrap(pack.index(of: Map3DProp.signalStop.modelName))
        XCTAssertEqual(models.model(taiwanRed, group: 0, clock: clock(35, region: .hongKong)), taiwanRed)
        // The four are one shape: only the lit lights differ.
        let shapes = [green, red, amber, redAmber].map { pack.models[$0] }
        XCTAssertEqual(Set(shapes.map(\.vertices.count)).count, 1)
        XCTAssertEqual(Set(shapes.map { $0.vertices.map(\.x) }).count, 1)
        // Standing on the ground (the pack's +z up), as tall as its post.
        XCTAssertEqual(shapes[0].minimum.z, 0, accuracy: 0.01)
        XCTAssertEqual(shapes[0].maximum.z, Map3DHongKongSignal.postHeight, accuracy: 0.01)
    }

    func testHongKongsGreenManStandsStillWithNoCountdown() {
        let pace = Signal.Pace()
        let stride = Signal.still(.hongKong)
        XCTAssertGreaterThan(stride, 0)
        XCTAssertLessThan(stride, Signal.frames)
        for second in Int64(0)..<Timing.cycle {
            for time in [0.2, 0.7] {
                let face = Signal.face(.main, group: 0, clock: clock(second, region: .hongKong), time: Double(second) + time, pace: pace,
                                       reduceMotion: false)
                XCTAssertNil(face.count, "no countdown at \(second)")
                switch face.figure {
                case .walk(let frame): XCTAssertEqual(frame, stride, "at \(second)")
                case .dark:
                    // Flashing only in the green's last seconds.
                    XCTAssertLessThanOrEqual(Signal.left(.main, at: second) ?? 0, Signal.flashing)
                    XCTAssertGreaterThan(Signal.left(.main, at: second) ?? 0, 0)
                case .stop: XCTAssertNil(Signal.left(.main, at: second))
                }
            }
        }
        // Taiwan's still counts down.
        XCTAssertNotNil(Signal.face(.main, group: 0, clock: clock(5, region: .taiwan), time: 5.2, pace: pace, reduceMotion: false).count)
    }

    func testHongKongsTrafficKeepsLeft() {
        XCTAssertEqual(Map3DStreetRegion.taiwan.trafficSide, 1)
        XCTAssertEqual(Map3DStreetRegion.hongKong.trafficSide, -1)
        XCTAssertTrue(Map3DStreetRegion.hongKong.keepsLeft)
        XCTAssertFalse(Map3DStreetRegion.taiwan.keepsLeft)
    }
}
