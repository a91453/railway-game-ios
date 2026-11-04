import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 583 (CABLEFOLLOW): the 3D map following a cable car cabin on
/// the Maokong Gondola: its pose moves on without a jump, the way ahead is
/// the way it runs, it is always drawn whole, the triangles stay capped,
/// and the session's follow bar.
final class CabinFollowTests: XCTestCase {
    static let world = Map3DCablewaysTests.world
    static let laid = Map3DCablewaysTests.laid
    static var pack: Map3DModelPack { Map3DModelPack.standard }
    static var gondola: Cableway { world.cableways[0] }

    /// A morning the gondola runs (it stands still on Mondays and in
    /// thunderstorms), at 10:00.
    static let morning: Double = {
        for day in Int64(0)..<14 {
            let second = day * GameTime.secondsPerDay + 10 * 3_600
            if CablewayCabins.runs(world.cableways[0].id, in: world, at: GameTime(seconds: second)) { return Double(second) }
        }
        return 10 * 3_600
    }()

    func index(_ name: String) -> Int { Self.pack.index(of: name)! }

    /// At whole seconds the glide is where the 2D cabins are
    /// (``CablewayCabins/cabins(of:atSecond:open:)``).
    func testTheGlideIsTheCabinsPlaceAtWholeSeconds() {
        let loop = CablewayCabins.loopSeconds(of: Self.gondola)
        for at in stride(from: Int64(0), to: loop, by: 7) {
            let place = CablewayCabins.place(at: at, on: Self.gondola)
            let glide = CablewayCabins.glide(at: Double(at), on: Self.gondola)
            switch (place, glide) {
            case let (.span(leg, permille, outbound), .span(gLeg, share, gOutbound)):
                XCTAssertEqual(leg, gLeg)
                XCTAssertEqual(outbound, gOutbound)
                XCTAssertEqual(Double(permille) / 1_000, share, accuracy: 0.002, "at \(at)")
            case let (.station(stop, outbound), .station(gStop, _, _, leaves)):
                XCTAssertEqual(stop, gStop, "at \(at)")
                XCTAssertEqual(outbound, leaves, "at \(at)")
            default:
                XCTFail("at \(at): \(place) against \(glide)")
            }
        }
    }

    /// Sampled every 0.2 s once round the loop, the followed cabin's grip
    /// never jumps and its heading never snaps: on the spans, through the
    /// stops it passes and round the wheel where it turns.
    func testTheFollowedCabinMovesOnWithoutAJump() throws {
        let id = CabinID(cableway: Self.gondola.id, number: 0)
        let loop = Double(CablewayCabins.loopSeconds(of: Self.gondola))
        var last = try XCTUnwrap(Self.laid.pose(of: id, second: Self.morning))
        var turned: Float = 0
        for step in 1...Int(loop * 5) {
            let second = Self.morning + Double(step) * 0.2
            let pose = try XCTUnwrap(Self.laid.pose(of: id, second: second), "at \(second)")
            // 5 m a second, a span a little longer drawn than measured.
            XCTAssertLessThan((pose.rail - last.rail).length, 1.6, "at \(second)")
            XCTAssertEqual(pose.forward.length, 1, accuracy: 0.001)
            XCTAssertEqual(pose.forward.y, 0, accuracy: 0.001)
            let angle = acosf(min(1, max(-1, pose.forward.dot(last.forward))))
            XCTAssertLessThan(angle, 0.2, "at \(second)")
            turned += angle
            // It hangs under its grip, its floor the cabin's drop below.
            XCTAssertEqual(pose.rail.y - (pose.middle?.y ?? 0), Map3DCableCar.cabinDrop, accuracy: 0.001)
            last = pose
        }
        // Twice round, at the two end wheels, and the corners between.
        XCTAssertGreaterThan(turned, 2 * .pi - 0.1)
    }

    /// Ahead is the way the cabin runs: the hall it comes to next lies in
    /// front of it on a span, and the streaming's strip ahead lies that
    /// way even when the camera's target stands still or moves the other
    /// way (the window view looking out at the side).
    func testAheadIsTheWayTheCabinRuns() throws {
        let id = CabinID(cableway: Self.gondola.id, number: 3)
        var checked = 0
        for step in 0..<200 {
            let second = Self.morning + Double(step) * 13
            guard case .span = CablewayCabins.glide(of: id.number, on: Self.gondola, atSecond: second) else { continue }
            let pose = try XCTUnwrap(Self.laid.pose(of: id, second: second))
            let hall = try XCTUnwrap(Self.laid.stopAhead(of: id, second: second))
            XCTAssertGreaterThan((hall - pose.rail).dot(pose.forward), 0, "at \(second)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)

        let forward = SIMD2<Float>(0.6, -0.8)
        for motion in [SIMD2<Float>(0, 0), SIMD2<Float>(-3, 4), SIMD2<Float>(40, 0)] {
            let velocity = Map3DStreaming.Window.velocity(motion: motion, ahead: forward)
            let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
            XCTAssertEqual((velocity.x * forward.x + velocity.y * forward.y) / speed, 1, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(speed, 2 * Map3DStreaming.still)
        }
        XCTAssertEqual(Map3DStreaming.Window.velocity(motion: SIMD2(3, 4), ahead: nil), SIMD2(3, 4))
        // The chunk 4.5 km ahead along the rope is wanted, the one as far
        // behind is not.
        let grid = Map3DStreaming(originX: 0, originY: 0, map: WorldRegion(minX: -1e9, minY: -1e9, maxX: 1e9, maxY: 1e9))
        let target = Map3DPoint(0, 0, 0)
        let velocity = Map3DStreaming.Window.velocity(motion: .zero, ahead: forward)
        let ahead = grid.key(of: Map3DPoint(forward.x * 4_500, 0, forward.y * 4_500))
        let behind = grid.key(of: Map3DPoint(-forward.x * 4_500, 0, -forward.y * 4_500))
        let wanted = Set(grid.wanted(target: target, velocity: velocity))
        XCTAssertTrue(wanted.contains(ahead))
        XCTAssertFalse(wanted.contains(behind))
    }

    /// The followed cabin is drawn whole wherever the eye is, even past
    /// the far reach and in a hall full of cabins; the others keep their
    /// caps, so the frame's triangles stay capped.
    func testTheFollowedCabinIsAlwaysDrawnWhole() throws {
        let line = try XCTUnwrap(Self.laid.lines.first)
        let near = Set(["cablecar-cabin-standard", "cablecar-cabin-crystal"].map(index))
        let far = Set(["cablecar-cabin-standard-far", "cablecar-cabin-crystal-far"].map(index))
        let cabins = CablewayCabins.count(of: Self.gondola)
        var most = 0
        for number in stride(from: 0, to: cabins, by: 11) {
            let id = CabinID(cableway: Self.gondola.id, number: number)
            for offset in stride(from: 0.0, to: 1_200, by: 97) {
                let second = Self.morning + offset
                let pose = try XCTUnwrap(Self.laid.pose(of: id, second: second))
                for eye in [pose.rail + Map3DPoint(0, 0.5, 0), pose.rail + Map3DPoint(20, 12, -30), line.halls[0].foot + Map3DPoint(0, 2_500, 0)] {
                    let frame = Self.laid.frame(second: second, eye: eye, target: pose.rail, pack: Self.pack, following: id, ahead: pose.forward)
                    let drawn = frame.instances.filter { near.contains($0.model) }
                    XCTAssertTrue(drawn.contains {
                        (Map3DPoint($0.transform[12], $0.transform[13], $0.transform[14]) - pose.rail).length < 0.01
                    }, "cabin \(number) at \(second)")
                    XCTAssertEqual(drawn.count, frame.nearCabins)
                    XCTAssertEqual(frame.instances.filter { far.contains($0.model) }.count, frame.farCabins)
                    XCTAssertLessThanOrEqual(frame.nearCabins, Map3DCableways.mostNearCabins)
                    XCTAssertLessThanOrEqual(frame.farCabins, Map3DCableways.mostFarCabins)
                    most = max(most, frame.instances.reduce(0) { $0 + Self.pack.models[$1.model].triangleCount })
                }
            }
        }
        XCTAssertLessThan(most, 260_000)
    }

    /// With `ahead`, the cabins drawn whole are those the followed cabin
    /// runs towards, though the camera looks back.
    func testTheCabinsAheadOfTheFollowedOneComeFirst() throws {
        let id = CabinID(cableway: Self.gondola.id, number: 0)
        for step in 0..<40 {
            let second = Self.morning + Double(step) * 31
            guard case .span = CablewayCabins.glide(of: id.number, on: Self.gondola, atSecond: second) else { continue }
            let pose = try XCTUnwrap(Self.laid.pose(of: id, second: second))
            let eye = pose.rail + Map3DPoint(0, 3, 0)
            let back = eye - pose.forward * 50
            func ahead(_ frame: Map3DCableways.Frame) -> Int {
                let near = Set(["cablecar-cabin-standard", "cablecar-cabin-crystal"].map(index))
                return frame.instances.filter { near.contains($0.model) }.count {
                    (Map3DPoint($0.transform[12], $0.transform[13], $0.transform[14]) - eye).dot(pose.forward) > 1
                }
            }
            let looked = Self.laid.frame(second: second, eye: eye, target: back, pack: Self.pack, following: id)
            let ran = Self.laid.frame(second: second, eye: eye, target: back, pack: Self.pack, following: id, ahead: pose.forward)
            XCTAssertGreaterThanOrEqual(ahead(ran), ahead(looked), "at \(second)")
        }
    }

    /// The window view sits in the cabin, a seated eye over its floor near
    /// its middle, within the near plane's 1.2 m of every wall; from a
    /// crystal cabin it looks further down.
    func testTheWindowViewSitsInTheCabin() throws {
        let standard = CabinID(cableway: Self.gondola.id, number: 2)
        let crystal = CabinID(cableway: Self.gondola.id, number: 0)
        XCTAssertFalse(CablewayCabins.isCrystal(standard.number))
        XCTAssertTrue(CablewayCabins.isCrystal(crystal.number))
        var pitches: [Float] = []
        for id in [standard, crystal] {
            let pose = try XCTUnwrap(Self.laid.pose(of: id, second: Self.morning + 30))
            let follow = Map3DFollow(cabin: id, view: .window)
            let camera = follow.camera(following: pose, from: Map3DCamera(target: pose.rail, distance: 300, viewport: (844, 390)), elapsed: 0)
            let middle = try XCTUnwrap(pose.middle)
            let seat = camera.eye - middle
            XCTAssertEqual(seat.y, Map3DCableways.cabinSeatHeight, accuracy: 0.01)
            XCTAssertLessThan(Map3DPoint(seat.x, 0, seat.z).length, Map3DCableCar.cabinWidth / 2)
            XCTAssertLessThan(Map3DCableCar.cabinWidth / 2 - Map3DCableways.cabinSeatAcross, camera.depthRange.near)
            pitches.append(camera.tilt)
        }
        XCTAssertLessThan(pitches[1], pitches[0], "the crystal cabin looks further down")
    }

    func testACabinIsFollowedFromItsThreeViews() {
        let id = CabinID(cableway: Self.gondola.id, number: 1)
        XCTAssertEqual(Map3DFollow.cabinViews, [.window, .aboveBack, .side])
        for view in Map3DFollow.View.allCases {
            let follow = Map3DFollow(cabin: id, view: view)
            XCTAssertTrue(Map3DFollow.cabinViews.contains(follow.view), "\(view)")
            XCTAssertEqual(follow.cabin, id)
            XCTAssertNil(follow.train)
            XCTAssertNil(follow.bus)
        }
        XCTAssertEqual(Map3DFollow(cabin: id, view: .cab).view, .window)
        XCTAssertEqual(Map3DFollow(cabin: id, view: .station).view, .aboveBack)
    }

    /// The card's follow button follows a running cabin; the bar names the
    /// cable car and its next station; following a train lets it go, and
    /// so does closing the 3D map.
    @MainActor
    func testTheSessionFollowsACabinAndShowsItsBar() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.maokong).value
        let session = try XCTUnwrap(launcher.session)
        let gondola = try XCTUnwrap(session.world.cableways.first)
        guard session.world.cabinToFollow(on: gondola.id) != nil else {
            XCTAssertFalse(session.hasCabinToFollow(on: gondola.id))
            throw XCTSkip("the scene's morning stands still (a thunderstorm)")
        }
        session.setMap3DOpen(true)
        session.followCabin(on: gondola.id)
        let id = try XCTUnwrap(session.followedCabinID)
        XCTAssertTrue(session.isFollowingVehicle)
        let bar = try XCTUnwrap(session.cabinFollowBar)
        XCTAssertEqual(bar.name, "纜車 \(gondola.id.rawValue)")
        XCTAssertTrue(bar.stopText.contains("下一站："), bar.stopText)
        XCTAssertTrue(bar.directionText.hasPrefix("往") || bar.directionText.hasPrefix("回"), bar.directionText)
        XCTAssertEqual(bar.kind != nil, CablewayCabins.isCrystal(id.number))
        // The cabin that left its first stop last: outbound, on the first span or in the first hall.
        switch CablewayCabins.glide(of: id.number, on: gondola, atSecond: Double(session.world.clock.now.seconds)) {
        case .span(let leg, _, let outbound): XCTAssertEqual(leg, 0); XCTAssertTrue(outbound)
        case .station(let stop, _, _, _): XCTAssertEqual(stop, 0)
        }
        session.setMap3DOpen(false)
        XCTAssertNil(session.followedCabinID)
        XCTAssertNil(session.cabinFollowBar)
        session.setMap3DOpen(true)
        session.followCabin(id)
        XCTAssertNotNil(session.followedCabinID)
        session.stopFollowingTrain()
        XCTAssertNil(session.followedCabinID)
    }

    /// The next station the bar names is one that boards: the angle
    /// stations between are passed through.
    func testTheBarsNextStationBoards() throws {
        let world = Self.world
        guard CablewayCabins.runs(Self.gondola.id, in: world, at: world.clock.now) else {
            throw XCTSkip("the scene's morning stands still")
        }
        var texts: Set<String> = []
        for number in stride(from: 0, to: CablewayCabins.count(of: Self.gondola), by: 3) {
            let facts = try XCTUnwrap(world.cabinFollowFacts(of: CabinID(cableway: Self.gondola.id, number: number), in: .english))
            XCTAssertFalse(facts.stopText.contains("Angle"))
            texts.insert(facts.stopText)
        }
        XCTAssertGreaterThan(texts.count, 2)
    }

    /// Decision 583: the Maokong demo's stops keep their real names in
    /// the bar; a cable car laid stop by stop has none to match.
    func testTheBarNamesARealCableCarsStops() throws {
        let world = Self.world
        guard CablewayCabins.runs(Self.gondola.id, in: world, at: world.clock.now) else {
            throw XCTSkip("the scene's morning stands still")
        }
        XCTAssertEqual(RealCableway.matching(Self.gondola, in: world), .maokong)
        let real = Set(["Taipei Zoo station", "Taipei Zoo South station", "Zhinan Temple station", "Maokong station"])
        for number in stride(from: 0, to: CablewayCabins.count(of: Self.gondola), by: 5) {
            let facts = try XCTUnwrap(world.cabinFollowFacts(of: CabinID(cableway: Self.gondola.id, number: number), in: .english))
            XCTAssertFalse(facts.stopText.contains("Station "), facts.stopText)
            XCTAssertTrue(real.contains { facts.directionText.hasSuffix($0) }, facts.directionText)
        }
        let chinese = try XCTUnwrap(world.cabinFollowFacts(of: CabinID(cableway: Self.gondola.id, number: 0), in: .traditionalChinese))
        XCTAssertTrue(chinese.directionText.hasSuffix("貓空站") || chinese.directionText.hasSuffix("動物園站"), chinese.directionText)
    }

    /// The screenshots' cabin is out over the longest span, near its middle.
    func testTheCabinOverTheLongestSpanIsOutOnIt() throws {
        let world = Self.world
        guard CablewayCabins.runs(Self.gondola.id, in: world, at: world.clock.now) else {
            throw XCTSkip("the scene's morning stands still")
        }
        let cabin = try XCTUnwrap(world.cabinOverLongestSpan(on: Self.gondola.id))
        let longest = try XCTUnwrap(Self.gondola.legMetres.indices.max { Self.gondola.legMetres[$0] < Self.gondola.legMetres[$1] })
        guard case .span(let leg, let share, _) = CablewayCabins.glide(of: cabin.number, on: Self.gondola, atSecond: Double(world.clock.now.seconds)) else {
            return XCTFail("not out on a span")
        }
        XCTAssertEqual(leg, longest)
        XCTAssertLessThan(abs(share - 0.5), 0.4)
    }
}
