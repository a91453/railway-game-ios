import GameCore
import XCTest
@testable import GamePresentation

/// Decision 918: the five more people seen close up.
final class Map3DPedestrianTests: XCTestCase {
    private typealias Kind = Map3DPedestrian.Kind

    /// Each decodes in the game's colours, its own height, standing on
    /// the ground, at most 360 triangles; what marks each is there.
    func testEachModelDecodesInTheGamesColours() throws {
        let heights: [Kind: Float] = [.office: 1.72, .student: 1.60, .elderly: 1.52, .umbrella: 2.05, .traveller: 1.74]
        let marks: [Kind: UInt32] = [.office: Map3DPalette.sidewalk, .student: Map3DPalette.sidewalk, .elderly: Map3DPalette.tankSteel,
                                     .umbrella: Map3DPalette.tankBlue, .traveller: Map3DStreetModel.tyre]
        for kind in Kind.firstBatch {
            for walking in [false, true] {
                let name = Map3DPedestrian.name(kind, walking: walking)
                let model = try XCTUnwrap(Map3DPedestrian.model(kind, walking: walking), name)
                XCTAssertEqual(model.name, name)
                XCTAssertLessThanOrEqual(model.triangleCount, 360, name)
                XCTAssertTrue(model.vertices.allSatisfy { Map3DPedestrian.palette.contains($0.color) }, name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, name)
                // Mid-stride a figure is up to 8 cm lower (the student's
                // 1.52 m), as the studio measured them.
                let height = try XCTUnwrap(heights[kind])
                XCTAssertLessThanOrEqual(model.maximum.z, height + 0.02, name)
                XCTAssertGreaterThanOrEqual(model.maximum.z, height - (walking ? 0.09 : 0.02), name)
                XCTAssertTrue(model.vertices.contains { $0.color == Map3DStreetModel.skin }, name)
                XCTAssertTrue(model.vertices.contains { $0.color == marks[kind] }, name)
                XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, name)
                // No wider than a person with a bag or an umbrella.
                XCTAssertLessThan(model.maximum.y - model.minimum.y, 1.3, name)
            }
            // Mid-stride, the feet are apart along the way it faces.
            let standing = try XCTUnwrap(Map3DPedestrian.model(kind, walking: false)), walking = try XCTUnwrap(Map3DPedestrian.model(kind, walking: true))
            let feet = { (model: Map3DModelPack.Model) -> Float in
                let low = model.vertices.filter { $0.z < 0.12 }.map(\.x)
                return (low.max() ?? 0) - (low.min() ?? 0)
            }
            if kind != .traveller { XCTAssertGreaterThan(feet(walking), feet(standing) + 0.1, "\(kind)") }
        }
        XCTAssertEqual(Map3DPedestrian.drawn.count, 10)
        XCTAssertEqual(Set(Map3DStreetLife.pedestrianModels.keys), Set((Map3DPedestrian.drawn + Map3DPedestrian.secondDrawn).map(\.name)))
    }

    /// The elder, the umbrella's holder and the traveller wear the
    /// instance's colour; the office worker's and the student's shirts
    /// stay white.
    func testWhoWearsTheInstancesColour() throws {
        for kind in Kind.firstBatch {
            let model = try XCTUnwrap(Map3DPedestrian.model(kind, walking: false))
            let tinted = model.vertices.contains { $0.color >> 24 == 0 }
            XCTAssertEqual(tinted, kind != .office && kind != .student, "\(kind)")
        }
    }

    // MARK: Decision 1037

    /// The second batch's nine decode in the game's colours, standing on
    /// the ground, a person's height and width, within the studio brief's
    /// triangles (a cart or a pram 420, the others 360).
    func testTheSecondBatchDecodesInTheGamesColours() throws {
        XCTAssertEqual(Kind.secondBatch.count, 9)
        XCTAssertEqual(Map3DPedestrian.secondDrawn.count, 17, "the jogger's one, running")
        for kind in Kind.secondBatch {
            for walking in kind == .jogger ? [false] : [false, true] {
                let name = Map3DPedestrian.name(kind, walking: walking)
                let model = try XCTUnwrap(Map3DPedestrian.model(kind, walking: walking), name)
                XCTAssertEqual(model.name, name)
                XCTAssertLessThanOrEqual(model.triangleCount, kind == .grandmaCart || kind == .motherStroller ? 420 : 360, name)
                XCTAssertTrue(model.vertices.allSatisfy { Map3DPedestrianBatch2.palette.contains($0.color) }, name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, name)
                XCTAssertGreaterThan(model.maximum.z, kind == .schoolboy ? 1.1 : 1.4, name)
                XCTAssertLessThan(model.maximum.z, 1.95, name)
                XCTAssertTrue(model.vertices.contains { $0.color == Map3DStreetModel.skin }, name)
                XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, name)
                XCTAssertLessThan(model.maximum.y - model.minimum.y, 1.3, name)
            }
        }
        XCTAssertEqual(Map3DPedestrian.name(.jogger, walking: false), "ped-jogger-running")
        XCTAssertEqual(Set(Map3DPedestrian.names).count, 27)
    }

    /// Each place's table holds 24, the commuter first; nobody pushes a
    /// cart, jogs, works or holds an umbrella on a platform, and the
    /// jogger and the worker are on the pavement alone.
    func testEachPlacesTableHoldsTwentyFour() {
        let places: [Map3DStreetLife.Spot.Kind] = [.platform, .stationFront, .shops, .temple, .sidewalk]
        for place in places {
            let column = Map3DPedestrian.column(place)
            XCTAssertEqual(Map3DPedestrian.table.map { $0.counts[column] }.reduce(0, +), Map3DPedestrian.slots, "\(place)")
            let who = (0..<Map3DPedestrian.slots).map { Map3DPedestrian.kind(slot: $0, at: place, clock: Map3DPedestrian.Clock(minute: 420, restDay: false), region: .taiwan) }
            XCTAssertNil(who[0], "\(place): the commuter first")
            if place != .sidewalk {
                XCTAssertFalse(who.contains(.jogger), "\(place)")
                XCTAssertFalse(who.contains(.worker), "\(place)")
            }
        }
        let platform = (0..<24).map { Map3DPedestrian.kind(slot: $0, at: .platform, clock: Map3DPedestrian.Clock(minute: 600, restDay: false), region: .taiwan) }
        for kind in [Kind.umbrella, .grandmaCart, .motherStroller, .jogger, .worker, .delivery] { XCTAssertFalse(platform.contains(kind), "\(kind)") }
        XCTAssertEqual(Set(Map3DPedestrian.table.map(\.who)).count, Kind.allCases.count + 1, "every kind, and the commuter, once")
        // Out of range, the nearest slot.
        XCTAssertEqual(Map3DPedestrian.kind(slot: -3, at: .shops, clock: .morning, region: .taiwan),
                       Map3DPedestrian.kind(slot: 0, at: .shops, clock: .morning, region: .taiwan))
    }

    /// Those out only at some hours are someone else outside them, so a
    /// place keeps its 24; a rest day sends the schoolboy and the worker
    /// home and a tourist into the commuter's first slot.
    func testWhoIsOutByTheHourAndTheDay() {
        func who(_ place: Map3DStreetLife.Spot.Kind, _ minute: Int, rest: Bool = false, region: Map3DStreetRegion = .taiwan) -> [Kind?] {
            (0..<24).map { Map3DPedestrian.kind(slot: $0, at: place, clock: Map3DPedestrian.Clock(minute: minute, restDay: rest), region: region) }
        }
        let sevenThirty = who(.sidewalk, 450)
        XCTAssertTrue(sevenThirty.contains(.schoolboy))
        XCTAssertTrue(sevenThirty.contains(.worker))
        XCTAssertTrue(sevenThirty.contains(.jogger))
        XCTAssertTrue(sevenThirty.contains(.grandmaCart))
        XCTAssertFalse(sevenThirty.contains(.motherStroller), "from nine")
        XCTAssertFalse(sevenThirty.contains(.delivery), "from half past ten")
        let noon = who(.sidewalk, 720 + 30)
        XCTAssertFalse(noon.contains(.schoolboy))
        XCTAssertTrue(noon.contains(.worker))
        XCTAssertFalse(noon.contains(.jogger))
        XCTAssertFalse(noon.contains(.grandmaCart), "the morning market over")
        XCTAssertTrue(noon.contains(.motherStroller))
        XCTAssertTrue(noon.contains(.delivery))
        // Each swapped for its stand-in, slot by slot.
        for (slot, kind) in sevenThirty.enumerated() {
            switch kind {
            case .jogger: XCTAssertEqual(noon[slot], .phone)
            case .grandmaCart: XCTAssertEqual(noon[slot], .elderly)
            case .schoolboy: XCTAssertNil(noon[slot])
            default: break
            }
        }
        let midnight = who(.sidewalk, 60)
        XCTAssertFalse(midnight.contains(.worker))
        XCTAssertFalse(midnight.contains(.delivery))
        XCTAssertFalse(midnight.contains(.motherStroller))
        let saturday = who(.sidewalk, 450, rest: true)
        XCTAssertFalse(saturday.contains(.schoolboy))
        XCTAssertFalse(saturday.contains(.worker))
        XCTAssertTrue(saturday.contains(.jogger))
        for place: Map3DStreetLife.Spot.Kind in [.platform, .stationFront, .shops, .temple, .sidewalk] {
            let weekday = who(place, 600), holiday = who(place, 600, rest: true)
            XCTAssertNil(weekday[0])
            XCTAssertEqual(holiday[0], .tourist, "\(place)")
            XCTAssertEqual(holiday.filter { $0 == .tourist }.count, weekday.filter { $0 == .tourist }.count + 1, "\(place)")
        }
        // Finland: no jogger or tourist in the snow, the commuter instead.
        for minute in [450, 1_100] {
            for rest in [false, true] {
                for place: Map3DStreetLife.Spot.Kind in [.platform, .stationFront, .shops, .temple, .sidewalk] {
                    let finnish = who(place, minute, rest: rest, region: .finland), taiwanese = who(place, minute, rest: rest)
                    XCTAssertFalse(finnish.contains(.jogger))
                    XCTAssertFalse(finnish.contains(.tourist))
                    for slot in 0..<24 where taiwanese[slot] == .jogger || taiwanese[slot] == .tourist { XCTAssertNil(finnish[slot]) }
                    XCTAssertEqual(who(place, minute, rest: rest, region: .japan), taiwanese, "Japan's as Taiwan's")
                }
            }
        }
    }

    /// The head counts are decision 259's; measured once (§1.4), the
    /// busiest of each place walks well under the HCM's A level of 16
    /// people a minute across each metre of the way.
    func testTheCrowdsWalkUnderTheHCMsALevel() {
        // People a minute a metre: those walking (not standing) of
        // `people` on `length` metres `band` wide, at the fastest pace.
        func flow(_ people: Int, length: Float, band: Float, standing: Float) -> Float {
            Float(people) * (1 - standing) / length / band * 1.5 * 60
        }
        // The densest shops (an office block's, density 4): 11 in 40 m,
        // 1.2 m either side of the line.
        let shops = flow(Int((100 / 40 * Float(3 + 2 * 4)).rounded()), length: 100, band: 2.4, standing: Map3DStreetLife.Spot.Kind.shops.standing)
        XCTAssertLessThan(shops, 8)
        // A pavement's 4 in 100 m, on the narrowest (a 2 m pavement's
        // 0.6 m either side).
        XCTAssertLessThan(flow(4, length: 100, band: 1.2, standing: 0), 5)
        // The busiest station front (2 + 58) along a 100 m platform, 2.5 m
        // either side.
        let front = flow(Map3DStreetLife.frontCrowd(trips: 10_000_000), length: 100, band: 5, standing: Map3DStreetLife.Spot.Kind.stationFront.standing)
        XCTAssertLessThan(front, 16)
        // A temple's 12 on a 10 m forecourt 3 m either side.
        XCTAssertLessThan(flow(12, length: 10, band: 6, standing: Map3DStreetLife.Spot.Kind.temple.standing), 16)
    }
}
