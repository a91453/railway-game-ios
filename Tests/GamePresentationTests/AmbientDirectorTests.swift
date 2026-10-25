import GameCore
@testable import GamePresentation
import XCTest

/// Decision 414: the idle mode's director (``AmbientDirector``): which
/// train, station or line it shows, from where, and for how long.
final class AmbientDirectorTests: XCTestCase {
    private typealias Cast = AmbientDirector.Cast

    /// Six trains, each on a line of its own, three stations, two lines.
    private func cast(trains: Int = 6) -> Cast {
        Cast(
            trains: (1...max(trains, 1)).prefix(trains).map { Cast.Train(id: TrainID(rawValue: $0), line: LineID(rawValue: $0)) },
            stations: (1...3).map { Cast.Station(id: StationID(rawValue: $0), waiting: Int64($0) * 10) },
            lines: (1...2).map { Cast.Line(id: LineID(rawValue: $0), trains: 1) }
        )
    }

    /// Plays `count` shots, each to its end.
    private func shots(_ count: Int, cast: Cast, seed: UInt64 = 1, allows3D: Bool = false) -> [AmbientDirector.Shot] {
        var director = AmbientDirector(seed: seed)
        var now = 0.0
        var shots: [AmbientDirector.Shot] = []
        while shots.count < count {
            if let shot = director.update(cast: cast, now: now, allows3D: allows3D) { shots.append(shot) }
            now += 1
        }
        return shots
    }

    private func kind(_ shot: AmbientDirector.Shot) -> AmbientDirector.Kind {
        switch shot.subject {
        case .train: .train
        case .station: .station
        case .line: .line
        }
    }

    /// Trains most of the time, a station and a line between, round and
    /// round; a train 60–120 s as the site's tour, a station or a line
    /// 20–30 s.
    func testTheShotsGoTrainTrainStationTrainLine() {
        let shots = shots(10, cast: cast())
        XCTAssertEqual(shots.map(kind), [.train, .train, .station, .train, .line, .train, .train, .station, .train, .line])
        for shot in shots {
            let range = kind(shot) == .train ? AmbientDirector.trainSeconds : AmbientDirector.stillSeconds
            XCTAssertTrue(range.contains(shot.seconds), "\(shot)")
        }
        XCTAssertEqual(AmbientDirector.trainSeconds, 60...120)
    }

    /// The shot stays until its time is up, then the next comes at once.
    func testAShotStaysForItsTime() throws {
        var director = AmbientDirector(seed: 7)
        let first = try XCTUnwrap(director.update(cast: cast(), now: 100, allows3D: false))
        XCTAssertNil(director.update(cast: cast(), now: 100 + first.seconds - 0.5, allows3D: false))
        XCTAssertNotNil(director.update(cast: cast(), now: 100 + first.seconds, allows3D: false))
        XCTAssertEqual(director.startedAt, 100 + first.seconds)
    }

    /// A train that leaves the track (or a line closed) ends its shot at
    /// once, rather than looking at nothing.
    func testAShotEndsWhenItsSubjectGoes() throws {
        var director = AmbientDirector(seed: 3)
        let first = try XCTUnwrap(director.update(cast: cast(), now: 0, allows3D: false))
        guard case .train(let id) = first.subject else { return XCTFail("a train first") }
        let without = Cast(trains: cast().trains.filter { $0.id != id }, stations: cast().stations, lines: cast().lines)
        let next = try XCTUnwrap(director.update(cast: without, now: 1, allows3D: false))
        XCTAssertNotEqual(next.subject, first.subject)
    }

    /// None of the last five trains is shown again while there are
    /// others (the site's `TOUR_RECENT`).
    func testTheLastFiveTrainsAreNotShownAgain() {
        let trains = shots(20, cast: cast()).compactMap { shot -> TrainID? in
            if case .train(let id) = shot.subject { return id }
            return nil
        }
        for index in trains.indices {
            let before = trains[max(0, index - AmbientDirector.recent)..<index]
            XCTAssertFalse(before.contains(trains[index]), "train \(index): \(trains)")
        }
    }

    /// Each line as often as another, whatever trains it runs: one train
    /// on line 2 against nine on line 1 is the first shot about half the
    /// time.
    func testEachLineIsShownAsOftenAsAnother() {
        let trains = (1...9).map { Cast.Train(id: TrainID(rawValue: $0), line: LineID(rawValue: 1)) }
            + [Cast.Train(id: TrainID(rawValue: 10), line: LineID(rawValue: 2))]
        let busy = Cast(trains: trains, stations: cast().stations, lines: cast().lines)
        var lone = 0
        for seed in 1...1_000 {
            var director = AmbientDirector(seed: UInt64(seed))
            if director.update(cast: busy, now: 0, allows3D: false)?.subject == .train(TrainID(rawValue: 10)) { lone += 1 }
        }
        XCTAssertTrue((420...580).contains(lone), "\(lone) of 1,000")
    }

    /// With the 3D map allowed, every other train is followed on it, from
    /// each view in turn, beside it first; stations and lines stay on the
    /// 2D map. Without it (3D off, or Reduce Motion), all on the 2D map.
    func testEveryOtherTrainIsFollowedIn3D() {
        let shots = shots(20, cast: cast(), allows3D: true)
        let trainStages = shots.filter { kind($0) == .train }.map(\.stage)
        XCTAssertEqual(Array(trainStages.prefix(6)), [.map3D(.side), .map2D, .map3D(.back), .map2D, .map3D(.station), .map2D])
        XCTAssertTrue(shots.filter { kind($0) != .train }.allSatisfy { $0.stage == .map2D })
        XCTAssertTrue(self.shots(20, cast: cast(), allows3D: false).allSatisfy { $0.stage == .map2D })
    }

    /// Turning 3D off (Reduce Motion turned on) during a 3D shot cuts to a
    /// 2D one at once.
    func testA3DShotEndsWhen3DIsNoLongerAllowed() throws {
        var director = AmbientDirector(seed: 1)
        let first = try XCTUnwrap(director.update(cast: cast(), now: 0, allows3D: true))
        XCTAssertEqual(first.stage, .map3D(.side))
        XCTAssertEqual(director.update(cast: cast(), now: 1, allows3D: false)?.stage, .map2D)
    }

    /// No train on the track: the stations and the lines; nothing at all
    /// without a station.
    func testWithoutTrainsItShowsStationsAndLines() {
        let shots = shots(6, cast: cast(trains: 0))
        XCTAssertTrue(shots.allSatisfy { kind($0) != .train }, "\(shots)")
        var director = AmbientDirector(seed: 1)
        XCTAssertNil(director.update(cast: Cast(trains: [], stations: [], lines: []), now: 0, allows3D: true))
        XCTAssertNil(director.shot)
    }

    /// The same seed, the same shots: a test replays them.
    func testTheSameSeedGivesTheSameShots() {
        XCTAssertEqual(shots(12, cast: cast(), seed: 42), shots(12, cast: cast(), seed: 42))
        XCTAssertNotEqual(shots(12, cast: cast(), seed: 42), shots(12, cast: cast(), seed: 43))
    }

    /// From a world: its stations and lines, a station's shot round it and
    /// a line's round its stops, each named.
    func testTheCastAndShotsOfAWorld() throws {
        let world = try newGameLine(through: [PlanPoint(x: 32_768, y: 65_536), PlanPoint(x: 160_000, y: 65_536)])
        XCTAssertTrue(AmbientDirector.isAvailable(in: world))
        XCTAssertFalse(AmbientDirector.isAvailable(in: .newGame()))
        let cast = Cast(world: world)
        XCTAssertEqual(cast.stations.count, 2)
        XCTAssertEqual(cast.lines.count, 1)
        XCTAssertEqual(cast.trains.map(\.line), cast.trains.map { _ in cast.lines.first?.id })

        let station = try XCTUnwrap(world.stations.first)
        let region = try XCTUnwrap(AmbientDirector.region(of: .station(station.id), in: world))
        let reach = AmbientDirector.stationReach * Double(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(region.width, 2 * reach)
        XCTAssertTrue(region.contains(WorldCoordinate(x: station.location.x, y: station.location.y)))
        XCTAssertEqual(AmbientDirector.caption(of: .station(station.id), in: world, language: .traditionalChinese), station.name)

        let line = try XCTUnwrap(world.lines.first)
        let whole = try XCTUnwrap(AmbientDirector.region(of: .line(line.id), in: world))
        for stop in world.stations {
            XCTAssertTrue(whole.contains(WorldCoordinate(x: stop.location.x, y: stop.location.y)))
        }
        XCTAssertEqual(AmbientDirector.caption(of: .line(line.id), in: world, language: .english), line.name)
        if let train = world.trains.first {
            XCTAssertEqual(AmbientDirector.caption(of: .train(train.id), in: world, language: .english), "\(line.name) · \(train.name)")
        }
        XCTAssertNil(AmbientDirector.region(of: .station(StationID(rawValue: 999)), in: world))
    }
}
