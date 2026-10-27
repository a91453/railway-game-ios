import Foundation
@testable import GamePresentation
import XCTest

/// Decision 437: the evening garbage truck — out only in the evening,
/// on a street, stopping along it, the same for the same moment, and its
/// tune falling with distance.
final class Map3DGarbageTruckTests: XCTestCase {
    /// A town street 400 m long along x, collected on.
    static func street(seed: (Int32, Int32) = (5, 6), collects: Bool = true, length: Float = 400) -> Map3DStreetLife.Lane {
        let path = Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(length, 0, 0)])!
        var lane = Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 8, perHundred: 2, scooters: true, seed: seed)
        lane.collects = collects
        return lane
    }

    /// The first day from 0 the street is worked on.
    static func workedDay(_ lane: Map3DStreetLife.Lane) -> Int64 {
        (0..<100).first { Map3DGarbageTruck.works(lane, day: $0) }!
    }

    static let evening: Double = 19.5 * 3_600

    func testOutOnlyInTheEvening() {
        XCTAssertEqual(Map3DGarbageTruck.presence(atSecond: 12 * 3_600), 0)
        XCTAssertEqual(Map3DGarbageTruck.presence(atSecond: 17.9 * 3_600), 0)
        XCTAssertEqual(Map3DGarbageTruck.presence(atSecond: 21.1 * 3_600), 0)
        XCTAssertEqual(Map3DGarbageTruck.presence(atSecond: Self.evening), 1)
        XCTAssertEqual(Map3DGarbageTruck.presence(atSecond: 18 * 3_600 + 300), 0.5, accuracy: 0.001)
        let lane = Self.street(), day = Self.workedDay(lane)
        for second in stride(from: 0.0, to: 86_400, by: 600) {
            let frame = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: second, time: 1_000)
            if !Map3DGarbageTruck.evening.contains(second) { XCTAssertTrue(frame.trucks.isEmpty, "\(second)") }
        }
        let evening = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening,
                                              time: 1_000)
        XCTAssertEqual(evening.leader?.model, .garbageTruck)
    }

    func testOnlyCloseUpAndOnTownStreets() {
        let lane = Self.street(), day = Self.workedDay(lane)
        let far = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 900, day: day, second: Self.evening, time: 0)
        XCTAssertTrue(far.trucks.isEmpty)
        let main = Map3DGarbageTruck.frame(lanes: [Self.street(collects: false)], target: Map3DPoint(200, 0, 0), distance: 200, day: day,
                                           second: Self.evening, time: 0)
        XCTAssertTrue(main.trucks.isEmpty)
        let short = Map3DGarbageTruck.frame(lanes: [Self.street(length: 40)], target: Map3DPoint(20, 0, 0), distance: 200, day: day,
                                            second: Self.evening, time: 0)
        XCTAssertTrue(short.trucks.isEmpty)
        // A third of the streets or so are worked on a day.
        let worked = (0..<300).filter { Map3DGarbageTruck.works(Self.street(seed: (Int32($0), 9)), day: 3) }.count
        XCTAssertTrue((60...140).contains(worked), "\(worked)")
    }

    func testOneTruckNearestTheView() {
        let lanes = (0..<6).map { index -> Map3DStreetLife.Lane in
            let z = Float(index) * 40
            let path = Map3DStreetLife.Path([Map3DPoint(0, 0, z), Map3DPoint(300, 0, z)])!
            var lane = Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 8, perHundred: 2, scooters: true, seed: (Int32(index), 1))
            lane.collects = true
            return lane
        }
        for day: Int64 in 0..<20 {
            let frame = Map3DGarbageTruck.frame(lanes: lanes, target: Map3DPoint(150, 0, 100), distance: 300, day: day, second: Self.evening,
                                                time: 500, follows: false)
            XCTAssertLessThanOrEqual(frame.trucks.count, 1)
        }
    }

    func testStaysOnTheStreet() {
        let lane = Self.street(), day = Self.workedDay(lane)
        for time in stride(from: 0.0, to: 3_000, by: 7) {
            let frame = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening,
                                                time: time)
            for truck in frame.trucks {
                XCTAssertTrue((0...400).contains(truck.point.x), "\(time)")
                XCTAssertLessThanOrEqual(abs(truck.point.z), lane.half, "\(time)")
                XCTAssertEqual(abs(truck.along.x), 1, accuracy: 0.001)
            }
        }
    }

    func testStopsAlongItsRound() {
        let lane = Self.street(), day = Self.workedDay(lane)
        func point(_ time: Double) -> Map3DPoint? {
            Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: time,
                                    follows: false).leader?.point
        }
        // Count the seconds it stands still and the stops it makes over
        // one round, out and back.
        var still = 0, stops = 0, wasStill = false
        var previous = point(0)
        for time in stride(from: 1.0, through: 1_200, by: 1) {
            let now = point(time)
            let standing = now.map { a in previous.map { ($0 - a).length < 0.001 } ?? false } ?? false
            if standing { still += 1 }
            if standing, !wasStill { stops += 1 }
            wasStill = standing
            previous = now
        }
        // 800 m out and back: five legs of 160 m, each 80 s driving and
        // 30 s waiting, so in 1,200 s about 11 stops and 330 s standing.
        XCTAssertTrue((9...12).contains(stops), "\(stops)")
        XCTAssertTrue((250...360).contains(still), "\(still)")
        // Reduce Motion: it stands at one stop.
        let a = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: 10,
                                        still: true)
        let b = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: 900,
                                        still: true)
        XCTAssertEqual(a.leader?.point, b.leader?.point)
    }

    func testTheSameMomentDrawsTheSame() {
        let lane = Self.street(), day = Self.workedDay(lane)
        let a = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: 777)
        let b = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: 777)
        XCTAssertEqual(a.trucks.map(\.point), b.trucks.map(\.point))
        XCTAssertEqual(a.trucks.map(\.size), b.trucks.map(\.size))
    }

    func testRecyclingTruckFollowsWhenThereIsRoom() {
        let lane = Self.street(), day = Self.workedDay(lane)
        // Mid-street, where both are wholly drawn.
        let time = (0..<2_000).map(Double.init).first { time in
            let frame = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening,
                                                time: time)
            return frame.trucks.count == 2 && frame.trucks.allSatisfy { $0.size == 1 }
        }!
        let both = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening, time: time)
        XCTAssertEqual(both.trucks.map(\.model), [.garbageTruck, .recyclingTruck])
        let gap = (both.trucks[0].point - both.trucks[1].point).length
        XCTAssertEqual(gap, Map3DGarbageTruck.followGap, accuracy: 0.5)
        XCTAssertEqual(both.instances.count, 2)
        XCTAssertEqual(both.clear.count, 2)
        let alone = Map3DGarbageTruck.frame(lanes: [lane], target: Map3DPoint(200, 0, 0), distance: 200, day: day, second: Self.evening,
                                            time: time, follows: false)
        XCTAssertEqual(alone.trucks.map(\.model), [.garbageTruck])
        let full = Map3DStreetLimits(people: 1_400, vehicles: 400, buses: 40)
        XCTAssertTrue(Map3DGarbageTruck.follows(full, of: full))
        XCTAssertFalse(Map3DGarbageTruck.follows(Map3DStreetLimits(people: 600, vehicles: 150, buses: 40), of: full))
    }

    func testTuneFallsWithDistance() {
        var frame = Map3DGarbageTruck.Frame()
        frame.trucks = [Map3DGarbageTruck.Truck(model: .garbageTruck, point: .zero, along: Map3DPoint(1, 0, 0), size: 1)]
        var volumes: [Double] = []
        for distance: Float in [60, 150, 300, 450, 600] {
            let camera = Map3DCamera(target: .zero, distance: distance, heading: 0, viewport: (390, 844))
            volumes.append(Map3DGarbageTruck.sound(of: frame, camera: camera)?.volume ?? 0)
        }
        XCTAssertEqual(volumes[0], 1, accuracy: 0.13)
        for (a, b) in zip(volumes, volumes.dropFirst()) { XCTAssertGreaterThan(a, b) }
        XCTAssertNil(Map3DGarbageTruck.sound(of: frame, camera: Map3DCamera(target: .zero, distance: 2_000, heading: 0, viewport: (390, 844))))
        XCTAssertNil(Map3DGarbageTruck.sound(of: Map3DGarbageTruck.Frame(), camera: Map3DCamera(distance: 100)))
        // From the right of the view, it is heard on the right.
        let camera = Map3DCamera(target: .zero, distance: 200, heading: 0, viewport: (390, 844))
        frame.trucks = [Map3DGarbageTruck.Truck(model: .garbageTruck, point: camera.right * 80, along: Map3DPoint(1, 0, 0), size: 1)]
        XCTAssertGreaterThan(Map3DGarbageTruck.sound(of: frame, camera: camera)?.pan ?? 0, 0)
    }

    func testTheMapDrawsThemWithTheBusesAndWithinItsBudget() {
        var life = Map3DStreetLife()
        let lane = Self.street(), day = Self.workedDay(lane)
        life.lanes = [lane]
        let camera = Map3DCamera(target: Map3DPoint(200, 0, 0), distance: 200, heading: 0, viewport: (390, 844))
        // Two days' seconds, so the clock's day is `day`'s: none without
        // a clock or a tier that draws the streets.
        XCTAssertTrue(Map3DGarbageTruck.frame(in: life, camera: camera, clock: nil, glides: false, now: 0, still: false,
                                              budget: Map3DMotionBudget(tier: .higher)).trucks.isEmpty)
        let trucks = Map3DGarbageTruck.frame(lanes: life.lanes, target: camera.target, distance: camera.distance, day: day,
                                             second: Self.evening, time: 500)
        let buses = Map3DBuses.Frame().adding(trucks)
        XCTAssertEqual(buses.instances.count, trucks.trucks.count)
        XCTAssertEqual(buses.clear.count, trucks.trucks.count)
        XCTAssertFalse(trucks.trucks.isEmpty)
    }

    func testBoxBuiltTrucksStandIn() {
        for model in [Map3DStreetModel.garbageTruck, .recyclingTruck] {
            let built = model.model()
            XCTAssertEqual(built.name, model.modelName)
            XCTAssertFalse(model.isBus)
            XCTAssertNotNil(Map3DStreetLife.models[model])
            XCTAssertLessThanOrEqual(built.maximum.z, Map3DGarbageTruck.size.height.garbage + 0.2)
        }
    }

    /// The models the app bundles, converted from the owner's Meshy batch.
    static let bundled: [Map3DStreetModel: URL] = Dictionary(uniqueKeysWithValues: Map3DGarbageTruck.fileNames.map { model, name in
        (model, URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/Models/\(name).\(Map3DGarbageTruck.fileExtension)"))
    })

    func testBundledTrucksReplaceTheBoxBuiltOnes() throws {
        let pack = Map3DGarbageTruck.pack(Map3DModelPack.standard, files: Self.bundled)
        XCTAssertEqual(pack.models.count, Map3DModelPack.standard.models.count)
        for model in [Map3DStreetModel.garbageTruck, .recyclingTruck] {
            let index = try XCTUnwrap(Map3DStreetLife.models[model])
            let read = pack.models[index], built = Map3DModelPack.standard.models[index]
            XCTAssertEqual(read.name, model.modelName)
            XCTAssertGreaterThan(read.vertices.count, built.vertices.count * 3, "\(model)")
            let extent = read.maximum - read.minimum
            XCTAssertEqual(extent.x, Map3DGarbageTruck.size.length, accuracy: 0.2)
            XCTAssertEqual(extent.y, Map3DGarbageTruck.size.width, accuracy: 0.2)
            XCTAssertEqual(read.minimum.z, 0, accuracy: 0.01)
            // In the game's colours.
            let colours = Set(read.vertices.map(\.color))
            XCTAssertTrue(colours.contains(model == .garbageTruck ? Map3DGarbageTruck.yellow : Map3DGarbageTruck.green), "\(model)")
        }
        // A file that cannot be read leaves the box-built one.
        let missing = Map3DGarbageTruck.pack(Map3DModelPack.standard, files: [.garbageTruck: URL(fileURLWithPath: "/nonexistent")])
        let index = try XCTUnwrap(Map3DStreetLife.models[.garbageTruck])
        XCTAssertEqual(missing.models[index].vertices.count, Map3DModelPack.standard.models[index].vertices.count)
    }
}
