import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 702 (FOLLOW-AIR): the 3D map's camera following an aircraft
/// that lands, leaves or taxis: which can be followed and until when, its
/// three views, its lamps at night, and what the session keeps of it.
final class FollowAircraftTests: XCTestCase {
    /// A field with a taxiway from the runway to its stands, as
    /// `Map3DAirfieldsTests` lays one.
    private func field() -> Map3DAircraft.Laid.Field {
        var field = Map3DAircraft.Laid.Field(
            seed: 7, airports: [0],
            stands: (0..<40).map { .init(nose: Map3DPoint(400 + Float($0) * 60, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57) },
            runways: [.init(a: Map3DPoint(0, 0, 0), b: Map3DPoint(3_000, 0, 0), length: 3_000)], wide: 0.3, propeller: 0.2
        )
        field.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(600, 0, 200), Map3DPoint(100, 0, 200), Map3DPoint(100, 0, 0)],
                           [Map3DPoint(1_800, 0, 200), Map3DPoint(2_900, 0, 200)]])
        return field
    }

    private func traffic(landings: Int = 4, takeOffs: Int = 4) -> Map3DAircraft.Traffic {
        Map3DAircraft.Traffic(day: 0, landings: [Array(repeating: landings, count: 24)], takeOffs: [Array(repeating: takeOffs, count: 24)])
    }

    private func drawn(_ kind: Map3DAircraft.Kind = .narrowJet, phase: Map3DAircraft.Phase = .approach, height: Float = 0, pitch: Float = 0,
                       flying: Bool = true) -> Map3DAircraft.Drawn {
        Map3DAircraft.Drawn(ground: Map3DPoint(100, 5, 200), height: height, forward: Map3DPoint(1, 0, 0), pitch: pitch, kind: kind, livery: 0,
                            flying: flying, flight: .init(field: 7, hours: 9, landing: true, index: 0), phase: phase)
    }

    // MARK: - Which, and until when

    /// Every flight of an hour has its own ID, and the ID finds the same
    /// aircraft the map draws, each second it is drawn.
    func testAFlightsIDFindsItsAircraft() throws {
        let laid = Map3DAircraft.Laid(fields: [field()]), traffic = traffic()
        var met: Set<Map3DAircraft.FlightID> = []
        for second in stride(from: 9.0 * 3_600, to: 10 * 3_600, by: 20) {
            let all = laid.aircraft(second: second, traffic: traffic)
            let flights = all.compactMap(\.flight)
            XCTAssertEqual(flights.count, Set(flights).count, "at \(second)")
            for aircraft in all {
                guard let id = aircraft.flight else {
                    XCTAssertNil(aircraft.phase)
                    continue
                }
                met.insert(id)
                let found = try XCTUnwrap(laid.aircraft(of: id, second: second, traffic: traffic))
                XCTAssertEqual(found.ground, aircraft.ground)
                XCTAssertEqual(found.phase, aircraft.phase)
                XCTAssertEqual(found.kind, aircraft.kind)
            }
        }
        XCTAssertGreaterThan(met.count, 8)
        XCTAssertTrue(met.contains { $0.landing } && met.contains { !$0.landing })
        XCTAssertEqual(laid.airport(of: try XCTUnwrap(met.first)), 0)
    }

    /// A landing is followed from its approach to its stand, where the
    /// camera lets go; a take-off from its push back until it has climbed
    /// 3.6 km out; and neither while it stands at its stand.
    func testFollowedWhileItMovesAndLetGoAtItsStandAndInTheAir() throws {
        let field = field(), laid = Map3DAircraft.Laid(fields: [field]), traffic = traffic(landings: 1, takeOffs: 1)
        let stand = try XCTUnwrap(field.rotation.first)
        for landing in [true, false] {
            let flights = Map3DAircraft.Laid.flights(of: field, day: 0, hour: 10, traffic: traffic).filter { $0.landing == landing }
            let flight = try XCTUnwrap(flights.first)
            XCTAssertNotNil(flight.stand, "\(stand)")
            var phases: [Map3DAircraft.Phase] = [], followed: [Bool] = []
            for second in stride(from: flight.time - 4_000, through: flight.time + 4_000, by: 2) {
                guard let aircraft = laid.aircraft(of: flight.id, second: second, traffic: traffic) else { continue }
                let phase = try XCTUnwrap(aircraft.phase)
                if phases.last != phase { phases.append(phase) }
                let follows = laid.followed(flight.id, second: second, traffic: traffic) != nil
                XCTAssertEqual(follows, Map3DAircraft.canFollow(aircraft))
                if phase == .parked { XCTAssertFalse(follows) }
                if phase != .parked, phase != .climb { XCTAssertTrue(follows, "\(phase)") }
                if phase == .climb { XCTAssertEqual(follows, Double(aircraft.height) < Map3DAircraft.followedOut * Map3DAircraft.climb) }
                if followed.last != follows { followed.append(follows) }
            }
            XCTAssertEqual(phases, landing ? [.approach, .landingRoll, .taxiIn, .parked] : [.parked, .pushBack, .taxiOut, .lineUp, .takeOffRoll, .climb])
            // Once: followed, then let go (a landing), or the other way and
            // let go again in the air.
            XCTAssertEqual(followed, landing ? [true, false] : [false, true, false])
        }
    }

    /// With Reduce Motion nothing moves, so nothing is followed; nor with
    /// no traffic, nor past the map's edge.
    func testNothingIsFollowedStillOrPastTheMapsEdge() throws {
        var laid = Map3DAircraft.Laid(fields: [field()])
        let traffic = traffic(landings: 6, takeOffs: 0)
        let flight = try XCTUnwrap(Map3DAircraft.Laid.flights(of: laid.fields[0], day: 0, hour: 10, traffic: traffic).first)
        // 30 seconds before it touches down: some 2 km out, west of the runway.
        let second = flight.time - 30
        let out = try XCTUnwrap(laid.followed(flight.id, second: second, traffic: traffic))
        XCTAssertEqual(out.drawn.phase, .approach)
        XCTAssertLessThan(out.drawn.ground.x, -1_000)
        XCTAssertEqual(out.airport, 0)
        XCTAssertNil(laid.followed(flight.id, second: second, traffic: traffic, still: true))
        XCTAssertNil(laid.followed(flight.id, second: second, traffic: nil))
        XCTAssertNotNil(laid.followable(nearest: .zero, second: second, traffic: traffic))
        laid.edges = (-500...4_000, -2_000...2_000)
        XCTAssertNil(laid.followed(flight.id, second: second, traffic: traffic))
        XCTAssertNotNil(laid.followed(flight.id, second: flight.time, traffic: traffic), "over the map again by the runway")
    }

    /// A tap finds the moving aircraft under the finger, not a parked one.
    func testATapFindsTheMovingAircraftUnderIt() throws {
        let laid = Map3DAircraft.Laid(fields: [field()]), traffic = traffic(landings: 6, takeOffs: 0)
        let flight = try XCTUnwrap(Map3DAircraft.Laid.flights(of: laid.fields[0], day: 0, hour: 10, traffic: traffic).first)
        let second = flight.time + 2
        let aircraft = try XCTUnwrap(laid.aircraft(of: flight.id, second: second, traffic: traffic))
        let body = Map3DAircraft.pose(of: aircraft).rail
        let camera = Map3DCamera(target: body, distance: 400, viewport: (844, 390))
        let screen = try XCTUnwrap(camera.screenPoint(of: body))
        let found = try XCTUnwrap(laid.followable(atX: screen.x + 4, y: screen.y - 3, camera: camera, second: second, traffic: traffic, within: 30))
        XCTAssertEqual(found.flight, flight.id)
        XCTAssertEqual(found.state.kind, aircraft.kind)
        XCTAssertNil(laid.followable(atX: screen.x + 4, y: screen.y - 3, camera: camera, second: second, traffic: traffic, still: true, within: 30))
        // Over a stand whose aircraft is parked: none.
        let parked = try XCTUnwrap(laid.aircraft(second: second, traffic: traffic).first { !$0.flying })
        let over = Map3DCamera(target: parked.ground, distance: 200, viewport: (844, 390))
        let at = try XCTUnwrap(over.screenPoint(of: parked.ground))
        XCTAssertNil(laid.followable(atX: at.x, y: at.y, camera: over, second: second, traffic: traffic, within: 10))
    }

    // MARK: - The views

    func testAnAircraftHasThreeViews() {
        XCTAssertEqual(Map3DFollow.aircraftViews, [.back, .side, .window])
        for view in Map3DFollow.View.allCases {
            XCTAssertTrue(Map3DFollow.aircraftViews.contains(Map3DFollow.aircraftView(view)))
        }
        XCTAssertEqual(Map3DFollow.aircraftView(.cab), .window)
        XCTAssertEqual(Map3DFollow.aircraftView(.aboveBack), .back)
        let id = Map3DAircraft.FlightID(field: 7, hours: 9, landing: true, index: 0)
        let follow = Map3DFollow(aircraft: id, view: .station, length: 44.51)
        XCTAssertEqual(follow.view, .back)
        XCTAssertEqual(follow.aircraft, id)
        XCTAssertNil(follow.train)
        // The bigger the aircraft, the farther the camera starts.
        let scales = Map3DAircraft.Kind.allCases.map { Map3DFollow.aircraftScale(length: Map3DAircraftStudies.dimensions($0).length) }
        XCTAssertEqual(scales, scales.sorted())
        XCTAssertTrue(scales.allSatisfy { Map3DFollow.scales.contains($0) })
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(Map3DFollow.aircraftViews.map { $0.aircraftText(in: language) }).count, 3)
            XCTAssertEqual(Set(Map3DFollow.aircraftViews.map { $0.aircraftHint(in: language) }).count, 3)
        }
        XCTAssertEqual(Map3DFollow.View.window.aircraftText(in: .traditionalChinese), "機艙窗")
    }

    /// The camera looks at the middle of the body, from behind it and from
    /// beside it with all of it in view; the window's eye is on its left
    /// side at its cabin windows' height, in the air as on the ground.
    func testTheCameraLooksAtTheBodyAndTheWindowIsOnItsLeft() throws {
        for kind in Map3DAircraft.Kind.allCases {
            let size = Map3DAircraftStudies.dimensions(kind), shape = Map3DAircraftStudies.shape(kind)
            for height: Float in [0, 300] {
                let aircraft = drawn(kind, height: height, pitch: height > 0 ? 0.05 : 0)
                let pose = Map3DAircraft.pose(of: aircraft)
                XCTAssertEqual(pose.rail.y, 5 + height + shape.centre, accuracy: 0.5, "\(kind)")
                XCTAssertEqual(pose.rail.x, 100, accuracy: 0.5)
                XCTAssertNil(pose.ground)
                let id = try XCTUnwrap(aircraft.flight)
                let start = Map3DCamera(target: pose.rail, distance: 300, viewport: (844, 390))
                // Behind: the eye behind the tail and above the body.
                let back = Map3DFollow(aircraft: id, view: .back, length: size.length).camera(following: pose, from: start, elapsed: 0, turnsAtOnce: true)
                XCTAssertLessThan(back.eye.x, 100 - size.length / 2 - 10, "\(kind)")
                XCTAssertGreaterThan(back.eye.y, pose.rail.y)
                XCTAssertEqual(back.eye.z, 200, accuracy: 1)
                // Beside: to its left (−z when it faces +x), at least its length away.
                let side = Map3DFollow(aircraft: id, view: .side, length: size.length).camera(following: pose, from: start, elapsed: 0, turnsAtOnce: true)
                XCTAssertLessThan(side.eye.z, 200 - size.length * 0.8, "\(kind)")
                // The window: just outside the body's left side, looking out.
                let window = Map3DFollow(aircraft: id, view: .window, length: size.length).camera(following: pose, from: start, elapsed: 0, turnsAtOnce: true)
                let eye = window.eye
                XCTAssertEqual(200 - eye.z, shape.halfWidth, accuracy: 0.6, "\(kind)")
                XCTAssertTrue((pose.rail.y - 0.3...pose.rail.y + shape.halfHeight + 0.6).contains(eye.y), "\(kind) \(eye.y) \(pose.rail.y)")
                XCTAssertLessThan(abs(eye.x - 100), size.length / 2)
                XCTAssertLessThan(window.target.z, eye.z - 30)
            }
        }
    }

    // MARK: - The lamps

    /// A moving aircraft carries a red lamp on its left wing tip and a
    /// green one on its right; its landing lights only on the runway and
    /// in the air; its beacon and strobes flash; one at its stand none.
    func testTheLampsOfAMovingAircraft() {
        func isRed(_ spot: Map3DGlow.Spot) -> Bool { spot.red > 0.9 && spot.green < 0.3 }
        func isGreen(_ spot: Map3DGlow.Spot) -> Bool { spot.green > 0.9 && spot.red < 0.3 }
        func isWhite(_ spot: Map3DGlow.Spot) -> Bool { spot.red > 0.9 && spot.green > 0.9 }
        for kind in Map3DAircraft.Kind.allCases {
            let span = Map3DAircraftStudies.dimensions(kind).wingspan
            let taxiing = Map3DAircraft.lamps(of: drawn(kind, phase: .taxiIn), blink: nil)
            // Facing +x, its left is −z.
            let red = taxiing.filter(isRed).min { $0.centre.z < $1.centre.z }
            let green = taxiing.filter(isGreen).max { $0.centre.z < $1.centre.z }
            XCTAssertEqual(red.map { 200 - $0.centre.z } ?? 0, span / 2, accuracy: span * 0.12, "\(kind)")
            XCTAssertEqual(green.map { $0.centre.z - 200 } ?? 0, span / 2, accuracy: span * 0.12, "\(kind)")
            XCTAssertTrue(taxiing.allSatisfy { $0.radius > 0 && $0.strength > 0 && $0.centre.y > 5 })
            let landing = Map3DAircraft.lamps(of: drawn(kind, phase: .approach, height: 80), blink: nil)
            XCTAssertGreaterThan(landing.filter(isWhite).count, taxiing.filter(isWhite).count, "the landing lights")
            XCTAssertGreaterThan(landing.filter(isWhite).map(\.radius).max() ?? 0, taxiing.filter(isWhite).map(\.radius).max() ?? 0)
            XCTAssertTrue(landing.allSatisfy { $0.centre.y > 80 })
        }
        XCTAssertTrue(Map3DAircraft.lamps(of: drawn(phase: .parked, flying: false), blink: 3).isEmpty)
        // Over its cycle the beacon is lit some of the time and the strobes
        // some other; never more lamps than a frame can hold many of.
        let counts = stride(from: 0.0, to: Map3DAircraft.beaconEvery, by: 0.02).map { Map3DAircraft.lamps(of: drawn(phase: .approach, height: 80), blink: $0).count }
        XCTAssertGreaterThan(Set(counts).count, 1)
        XCTAssertLessThanOrEqual(counts.max() ?? 0, 12)
        XCTAssertLessThan(Double(counts.filter { $0 == counts.max() }.count) / Double(counts.count), 0.4, "a flash is short")
        // Taxiing, no strobes at all.
        let taxi = Set(stride(from: 0.0, to: Map3DAircraft.beaconEvery, by: 0.02).map { Map3DAircraft.lamps(of: drawn(phase: .taxiOut), blink: $0).count })
        XCTAssertEqual(taxi.count, 2, "only the beacon comes and goes")
    }

    /// The map adds the lamps of the moving aircraft near the eye, and
    /// draws the one followed whole however many are nearer.
    func testTheFrameHasTheLampsAndTheFollowedAircraftWhole() throws {
        let laid = Map3DAircraft.Laid(fields: [field()]), traffic = traffic(landings: 6, takeOffs: 0)
        let flight = try XCTUnwrap(Map3DAircraft.Laid.flights(of: laid.fields[0], day: 0, hour: 10, traffic: traffic).first)
        let second = flight.time - 20
        let aircraft = try XCTUnwrap(laid.aircraft(of: flight.id, second: second, traffic: traffic))
        let pack = Map3DModelPack(models: Map3DAircraft.drawn)
        let near = try XCTUnwrap(pack.index(of: Map3DAircraft.name(aircraft.kind)))
        // The eye by the stands, 1.5 km and more from the aircraft on its
        // approach (within the glows' reach): drawn as its far model,
        // unless it is the one followed.
        let eye = Map3DPoint(600, 30, 300)
        XCTAssertGreaterThan((aircraft.ground - eye).length, Map3DAircraft.nearReach)
        XCTAssertLessThan((aircraft.ground - eye).length, Map3DGlow.reach)
        var plain = Map3DTrains.Frame()
        laid.add(to: &plain, pack: pack, second: second, traffic: traffic, eye: eye, blink: 0)
        XCTAssertFalse(plain.instances.contains { $0.model == near && abs($0.transform[12] - aircraft.ground.x) < 1 })
        XCTAssertFalse(plain.lamps.isEmpty)
        var followed = Map3DTrains.Frame()
        laid.add(to: &followed, pack: pack, second: second, traffic: traffic, eye: eye, following: flight.id, blink: 0)
        XCTAssertTrue(followed.instances.contains { $0.model == near && abs($0.transform[12] - aircraft.ground.x) < 1 })
        // With Reduce Motion: no moving aircraft, no lamps.
        var still = Map3DTrains.Frame()
        laid.add(to: &still, pack: pack, second: second, traffic: traffic, eye: eye, still: true)
        XCTAssertTrue(still.lamps.isEmpty)
    }

    // MARK: - The runway's ground

    /// On a runway that rises between its ends (an island's hill), an
    /// aircraft rolls on the ground along it, not on the straight line
    /// between its ends (under the runway); past the ends, level.
    func testAnAircraftRollsOnTheGroundAlongTheRunway() throws {
        let runway = Map3DAircraft.Laid.Runway(a: Map3DPoint(0, 10, 0), b: Map3DPoint(900, 12, 0), length: 900,
                                                 heights: (0...45).map { 10 + 2 * Float($0) / 45 + 8 * sinf(.pi * Float($0) / 45) })
        XCTAssertEqual(runway.height(at: 0), 10, accuracy: 0.01)
        XCTAssertEqual(runway.height(at: 900), 12, accuracy: 0.01)
        XCTAssertEqual(runway.height(at: 450), 19, accuracy: 0.05)
        XCTAssertEqual(runway.height(at: -200), 10, accuracy: 0.01)
        XCTAssertEqual(runway.height(at: 2_000), 12, accuracy: 0.01)
        let field = Map3DAircraft.Laid.Field(seed: 7, airports: [0], stands: [], runways: [runway], wide: 0, propeller: 1)
        let flight = Map3DAircraft.Laid.Flight(time: 1_000, landing: true, runway: 0, kind: .commuter19, livery: 0)
        for northEast in [true, false] {
            var highest: Float = 0
            for second in stride(from: 1_000.0, through: 1_040, by: 1) {
                guard let pose = Map3DAircraft.Laid.pose(of: flight, on: field, second: second, northEast: northEast) else { continue }
                XCTAssertEqual(pose.ground.y, runway.height(at: pose.ground.x), accuracy: 0.01, "at \(second)")
                highest = max(highest, pose.ground.y)
            }
            XCTAssertGreaterThan(highest, 15, "over the hill, not through it")
        }
        // With no heights (a field laid by hand): the straight line.
        let flat = Map3DAircraft.Laid.Runway(a: Map3DPoint(0, 10, 0), b: Map3DPoint(900, 12, 0), length: 900)
        XCTAssertEqual(flat.height(at: 450), 11, accuracy: 0.01)
    }

    // MARK: - The small airfields

    /// An island's field: a short runway, no taxiways mapped, three stands
    /// on an apron beside its middle. Its stands are joined to the runway
    /// and all take flights; a landing turns round on the runway, rolls
    /// back and in to its stand, and a take-off comes out of its stand,
    /// rolls to the runway's start and turns round there. Neither leaves
    /// the runway's ends nor jumps.
    func testASmallFieldsFlightsReachItsStands() throws {
        var field = Map3DAircraft.Laid.Field(
            seed: 7, airports: [0],
            stands: (0..<3).map { .init(nose: Map3DPoint(480 + Float($0) * 40, 0, 90), forward: Map3DPoint(0, 0, 1), room: 30) },
            runways: [.init(a: Map3DPoint(0, 0, 0), b: Map3DPoint(1_000, 0, 0), length: 1_000)], wide: 0, propeller: 1
        )
        field.layTaxiways([])
        XCTAssertEqual(field.links.count, 3)
        XCTAssertEqual(Set(field.rotation), [0, 1, 2])
        let traffic = traffic(landings: 1, takeOffs: 1)
        for northEast in [true, false] {
            for flight in Map3DAircraft.Laid.flights(of: field, day: 0, hour: 10, traffic: traffic) {
                XCTAssertEqual(flight.kind, .commuter19, "a seventy-seater needs 1,200 m")
                XCTAssertNotNil(flight.stand, flight.landing ? "a landing" : "a take-off")
                var phases: [Map3DAircraft.Phase] = [], last: Map3DAircraft.Drawn?
                for second in stride(from: flight.time - 4_000, through: flight.time + 4_000, by: 1) {
                    guard let pose = Map3DAircraft.Laid.pose(of: flight, on: field, second: second, northEast: northEast) else {
                        last = nil
                        continue
                    }
                    if phases.last != pose.phase, let phase = pose.phase { phases.append(phase) }
                    if pose.height == 0 {
                        XCTAssertTrue((-5...1_005).contains(pose.ground.x), "on the field at \(second): \(pose.ground.x)")
                        XCTAssertTrue((-15...100).contains(pose.ground.z), "at \(second): \(pose.ground.z)")
                    }
                    if let last, last.height == 0, pose.height == 0, abs(second - flight.time) > 45 {
                        XCTAssertLessThan((pose.ground - last.ground).length, 10, "at \(second)")
                    }
                    last = pose
                }
                XCTAssertEqual(phases, flight.landing ? [.approach, .landingRoll, .taxiIn, .parked]
                               : [.parked, .pushBack, .taxiOut, .lineUp, .takeOffRoll, .climb], "\(northEast)")
            }
        }
        // A field with taxiways keeps its own: nothing is added.
        var mapped = self.field()
        let links = mapped.links.count
        mapped.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(600, 0, 200), Map3DPoint(100, 0, 200), Map3DPoint(100, 0, 0)],
                            [Map3DPoint(1_800, 0, 200), Map3DPoint(2_900, 0, 200)]])
        XCTAssertEqual(mapped.links.count, links)
        // And one with no stand near its runway is left as it was.
        var bare = Map3DAircraft.Laid.Field(seed: 7, airports: [0], stands: [], runways: field.runways, wide: 0, propeller: 1)
        bare.layTaxiways([])
        XCTAssertTrue(bare.links.isEmpty)
    }

    // MARK: - The session

    @MainActor
    func testTheSessionFollowsAnAircraftUntilToldItIsGone() throws {
        let session = GameSession(world: ScreenshotScene.airport.make(in: .traditionalChinese), language: .traditionalChinese)
        let id = Map3DAircraft.FlightID(field: 7, hours: 9, landing: true, index: 0)
        let other = Map3DAircraft.FlightID(field: 7, hours: 9, landing: false, index: 1)
        session.setMap3DOpen(true)
        XCTAssertFalse(session.isFollowingVehicle)
        session.followAircraft(.init(flight: id, kind: .narrowJet, phase: .approach, airport: 0))
        XCTAssertTrue(session.isFollowingAircraft)
        XCTAssertTrue(session.isFollowingVehicle)
        XCTAssertEqual(session.followedAircraftID, id)
        let bar = try XCTUnwrap(session.aircraftFollowBar)
        XCTAssertEqual(bar.name, "窄體客機")
        XCTAssertEqual(bar.directionText, "降落臺北松山機場")
        XCTAssertEqual(bar.stopText, "進場中")
        // What it does next; another flight's news is not this one's.
        session.noteFollowedAircraft(.init(flight: id, kind: .narrowJet, phase: .taxiIn, airport: 0), of: id)
        XCTAssertEqual(session.aircraftFollowBar?.stopText, "滑行到機位")
        session.noteFollowedAircraft(nil, of: other)
        XCTAssertTrue(session.isFollowingAircraft)
        // At its stand: let go.
        session.noteFollowedAircraft(nil, of: id)
        XCTAssertFalse(session.isFollowingAircraft)
        XCTAssertNil(session.aircraftFollowBar)
        XCTAssertFalse(session.isFollowingVehicle)
        // The bar's button, and closing the 3D map, let go too.
        session.followAircraft(.init(flight: other, kind: .regional70, phase: .taxiOut, airport: 1))
        XCTAssertEqual(session.aircraftFollowBar?.directionText, "從臺中國際機場起飛")
        session.stopFollowingTrain()
        XCTAssertNil(session.followedAircraftID)
        session.followAircraft(.init(flight: other, kind: .regional70, phase: .taxiOut, airport: nil))
        XCTAssertEqual(session.aircraftFollowBar?.directionText, "起飛")
        session.setMap3DOpen(false)
        XCTAssertNil(session.followedAircraftID)
        XCTAssertNil(session.aircraftFollowBar)
    }

    /// Every phase and type has its words in both languages.
    func testTheBarsWords() {
        let phases: [Map3DAircraft.Phase] = [.approach, .landingRoll, .taxiIn, .parked, .pushBack, .taxiOut, .lineUp, .takeOffRoll, .climb]
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(phases.map { $0.text(in: language) }).count, phases.count)
            XCTAssertEqual(Set(Map3DAircraft.Kind.allCases.map { $0.text(in: language) }).count, 4)
        }
    }
}
