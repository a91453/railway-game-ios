import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The real lines the demo mode lays (decision 351) run their own system's
/// trains: High Speed Rail sets on the High Speed Rail, metro cars on a
/// metro, trams on a light rail.
@MainActor
final class DemoRealLinesTrainTypeTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A demo game on the whole of Taiwan with unlimited funds, and the
    /// view holding `stations` of `system` and `margin` metres round them.
    private func taiwan(round stations: [String], of system: String, margin: Double = 2_000) throws -> (session: GameSession, view: WorldRegion) {
        var world = HighSpeedDemo.newWorld(paying: Money(0), eventSeed: 1)
        try world.mapGround()
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.heights = try HeightGrid(
            data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
        )
        session.railways = try BundledRealData.railways()
        session.news.isDemo = true
        let points = try stations.map { try BundledRealData.point(try BundledRealData.station($0, in: system).coordinate, in: world) }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }, reach = margin * metre
        let view = WorldRegion(
            minX: try XCTUnwrap(xs.min()) - reach, minY: try XCTUnwrap(ys.min()) - reach,
            maxX: try XCTUnwrap(xs.max()) + reach, maxY: try XCTUnwrap(ys.max()) + reach
        )
        return (session, view)
    }

    /// The world after the one line `key` is laid between `stations`: its
    /// first three without them.
    private func laid(_ key: String, between named: [String]? = nil) async throws -> GameWorld {
        let system = String(key.split(separator: "|")[0])
        let stations = try named ?? XCTUnwrap(BundledRealData.railways().stops[key]).prefix(3).map(\.chinese)
        let (session, view) = try taiwan(round: stations, of: system)
        let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.lineKey == key }
        XCTAssertEqual(outcome?.lines, 1, session.message?.text ?? "")
        return session.world
    }

    /// The key of the set a train is drawn as in the 3D map.
    private func drawn(_ train: Train) -> String? {
        Map3DTrainSet.set(forKey: Map3DTrainSet.key(type: train.type, performance: train.performance), count: train.cars)?.key
    }

    /// The High Speed Rail from Taichung to Changhua: 12-car High Speed
    /// Rail sets, every one on the track, on a high-speed line, drawn as
    /// the set.
    func testTheHighSpeedRailRunsHighSpeedSets() async throws {
        let world = try await laid("thsr_sched|THSR", between: ["台中", "彰化"])
        let line = try XCTUnwrap(world.lines.first)
        XCTAssertTrue(line.name.hasPrefix("高鐵"), line.name)
        XCTAssertFalse(world.trains.isEmpty)
        for train in world.trains {
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.performance, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 12, train.name)
            XCTAssertNotNil(train.position, "\(train.name) stands on the track")
            XCTAssertTrue(line.assignedTrains.contains(train.id), train.name)
            XCTAssertEqual(train.capacity, 12 * 80, train.name)
            XCTAssertEqual(drawn(train), "highSpeed", train.name)
        }
        XCTAssertTrue(line.isHighSpeed, "a high-speed line")
    }

    /// Each system's type: the lines on sale as ``RealBranchLine`` has
    /// them, and every line of the bundled data one the game offers.
    func testEachSystemHasItsOwnType() throws {
        func type(_ key: String) -> TrainType? {
            DemoRealLines.trainType(ofLine: key, system: String(key.split(separator: "|")[0]))
        }
        XCTAssertEqual(type("thsr_sched|THSR"), .highSpeed)
        XCTAssertEqual(type("afr_sched|AFR_MAIN"), .alishan)
        XCTAssertEqual(type("mrt|BL"), .a)
        XCTAssertEqual(type("mrt|BR"), .apm)
        XCTAssertEqual(type("mrt|Y"), .b)
        XCTAssertEqual(type("krtc|KR"), .a)
        XCTAssertEqual(type("krtc|C"), .c)
        XCTAssertEqual(type("tmrt|TG"), .b)
        XCTAssertNil(type("tra_sched|PINGXI"), "the game's first car")
        XCTAssertNil(type("mtr|ISL"), "a system it does not name")
        for line in RealBranchLine.urbanLines {
            let sold = RealBranchLine(
                network: line.network, english: line.english, chinese: line.chinese, stops: [], system: line.system, tier: line.tier
            )
            XCTAssertEqual(type("\(line.system)|\(line.network)"), sold.trainType, line.chinese)
        }
        let offered = Set(TrainType.offered)
        for key in try BundledRealData.railways().stops.keys {
            if let type = type(key) { XCTAssertTrue(offered.contains(type), key) }
        }
    }

    /// A platform holds its line's train: a car more than it of standard
    /// cars, and with real car lengths the twelve 25 m cars of a High
    /// Speed Rail set.
    func testAPlatformHoldsItsLinesTrain() {
        let standard = Train.realStandardCarLength
        XCTAssertEqual(DemoRealLines.platformLength(cars: 8, of: nil, carLength: standard, real: true), 9 * standard)
        XCTAssertEqual(DemoRealLines.platformLength(cars: 6, of: .a, carLength: standard, real: true), 7 * standard, "as before")
        XCTAssertEqual(DemoRealLines.platformLength(cars: 12, of: .highSpeed, carLength: standard, real: true), 12 * TrainType.highSpeed.carLength)
        XCTAssertEqual(DemoRealLines.platformLength(cars: 12, of: .highSpeed, carLength: Train.carLength, real: false), 13 * Train.carLength)
        for key in ["thsr_sched|THSR", "afr_sched|AFR_MAIN", "mrt|BL", "mrt|BR", "mrt|Y", "krtc|KR", "krtc|C", "tymc|A", "ntdlrt|V", "tra_sched|PINGXI"] {
            let system = String(key.split(separator: "|")[0])
            let cars = DemoRealLines.cars(ofSystem: system), type = DemoRealLines.trainType(ofLine: key, system: system)
            let pitch = Train.carPitch(of: type, real: true)
            XCTAssertGreaterThanOrEqual(
                DemoRealLines.platformLength(cars: cars, of: type, carLength: standard, real: true), Int64(cars - 1) * pitch, key
            )
        }
    }

    /// A metro line, a light rail and a TRA line: the heavy metro's cars,
    /// trams, and the game's first car, every train on the track.
    func testAMetroALightRailAndTheTRARunTheirOwn() async throws {
        for (key, type, set) in [("mrt|BL", TrainType.a as TrainType?, "metroC381" as String?), ("ntalrt|K", .c, "fiveSectionLRT"), ("tra_sched|PINGXI", nil, nil)] {
            let world = try await laid(key)
            let line = try XCTUnwrap(world.lines.first, key)
            XCTAssertFalse(world.trains.isEmpty, key)
            XCTAssertFalse(line.isHighSpeed, key)
            for train in world.trains {
                XCTAssertEqual(train.type, type, "\(key) \(train.name)")
                XCTAssertNotNil(train.position, "\(key) \(train.name) stands on the track")
                XCTAssertTrue(line.assignedTrains.contains(train.id), "\(key) \(train.name)")
                if let set { XCTAssertEqual(drawn(train), set, "\(key) \(train.name)") }
            }
        }
    }
}
