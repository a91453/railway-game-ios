import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 606 (IDLEREAL): the idle mode follows the real timetables'
/// trains too: picked as the site's `pickTourTrain` picks, in turn with the
/// player's own trains, named in a line ("普悠瑪號 往樹林").
final class AmbientRealTrainsTests: XCTestCase {
    private typealias Cast = AmbientDirector.Cast

    private func real(_ count: Int, weight: Double = 1) -> [Cast.RealTrain] {
        (0..<count).map { Cast.RealTrain(id: RealTrainID(system: "tra", line: "L", place: "區間車#\($0)"), weight: weight) }
    }

    private func cast(own: Int, real count: Int) -> Cast {
        Cast(trains: (0..<own).map { Cast.Train(id: TrainID(rawValue: $0 + 1), line: LineID(rawValue: $0 + 1)) },
             stations: [Cast.Station(id: StationID(rawValue: 1), waiting: 0)],
             lines: [Cast.Line(id: LineID(rawValue: 1), trains: own)],
             realTrains: real(count))
    }

    /// Plays `count` shots, each to its end.
    private func shots(_ count: Int, cast: Cast, seed: UInt64 = 1, allows3D: Bool = true) -> [AmbientDirector.Shot] {
        var director = AmbientDirector(seed: seed)
        var now = 0.0
        var shots: [AmbientDirector.Shot] = []
        while shots.count < count {
            if let shot = director.update(cast: cast, now: now, allows3D: allows3D) { shots.append(shot) }
            now += 1
        }
        return shots
    }

    private func realID(_ shot: AmbientDirector.Shot) -> RealTrainID? {
        if case .realTrain(let id) = shot.subject { id } else { nil }
    }

    private func isOwnTrain(_ shot: AmbientDirector.Shot) -> Bool {
        if case .train = shot.subject { true } else { false }
    }

    /// The site's `TOUR_W`, four times for a rare or named train, 1 for a
    /// train of another system.
    func testTheSitesWeights() {
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "其他", rare: false), 24)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "莒光/復興", rare: false), 10)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "自強", rare: false), 5)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "區間快", rare: false), 2)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "區間車", rare: false), 1)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: "自強", rare: true), 20)
        XCTAssertEqual(AmbientRealTrains.tourWeight(kind: nil, rare: false), 1)
        XCTAssertEqual(AmbientRealTrains.tourCap, 0.03)
        XCTAssertEqual(AmbientDirector.recent, 5)
    }

    /// A heavy train is held to 3 % of all the weights together: among a
    /// hundred local trains, a train of weight 100 is picked about as
    /// often as 3 of them (the site's `TOUR_CAP`), not as 100.
    func testTheCapHoldsAHeavyTrain() throws {
        let weights = [100.0] + Array(repeating: 1.0, count: 100)
        let held = 200 * AmbientRealTrains.tourCap
        let draws = 10_000
        let first = (0..<draws).filter { AmbientDirector.tourPick(weights: weights, unit: (Double($0) + 0.5) / Double(draws)) == 0 }.count
        XCTAssertEqual(Double(first) / Double(draws), held / (held + 100), accuracy: 0.001)
        XCTAssertNil(AmbientDirector.tourPick(weights: [], unit: 0.5))
        XCTAssertEqual(AmbientDirector.tourPick(weights: [1, 1], unit: 0.99), 1)
        // Without the cap the heavier wins more often (few candidates held alike).
        let rare = (0..<draws).filter { AmbientDirector.tourPick(weights: [4] + Array(repeating: 1, count: 40), unit: (Double($0) + 0.5) / Double(draws)) == 0 }.count
        XCTAssertGreaterThan(rare, draws / 41)
    }

    /// None of the last five real trains comes again while there are
    /// others.
    func testTheLastFiveAreNotShownAgain() {
        let ids = shots(60, cast: cast(own: 0, real: 8)).compactMap(realID)
        XCTAssertGreaterThan(ids.count, 30)
        for index in ids.indices {
            XCTAssertFalse(ids[max(0, index - AmbientDirector.recent)..<index].contains(ids[index]), "\(index)")
        }
    }

    /// With trains of the player's own, a real train in turn with them;
    /// with none, a real train every time; each followed 60–120 s on the
    /// 3D map, from beside it, behind, above and the cab in turn.
    func testRealTrainsTakeTurnsWithTheOwn() throws {
        let trains = shots(20, cast: cast(own: 3, real: 6)).filter { isOwnTrain($0) || realID($0) != nil }
        XCTAssertGreaterThan(trains.count, 8)
        for (a, b) in zip(trains, trains.dropFirst()) {
            XCTAssertNotEqual(isOwnTrain(a), isOwnTrain(b), "\(a) then \(b)")
        }
        let alone = shots(10, cast: cast(own: 0, real: 6))
        let real = alone.filter { realID($0) != nil }
        XCTAssertEqual(real.count, alone.count - alone.filter { if case .station = $0.subject { true } else if case .line = $0.subject { true } else { false } }.count)
        XCTAssertEqual(real.map(\.stage), (0..<real.count).map { .map3D(AmbientDirector.realViews3D[$0 % 4]) })
        XCTAssertEqual(AmbientDirector.realViews3D, [.side, .back, .aboveBack, .cab])
        for shot in real { XCTAssertTrue(AmbientDirector.trainSeconds.contains(shot.seconds)) }
    }

    /// Only on the 3D map: without it (off in Settings, or Reduce Motion),
    /// the player's own trains as before.
    func testNoneWithoutThe3DMap() {
        XCTAssertTrue(shots(15, cast: cast(own: 2, real: 6), allows3D: false).allSatisfy { realID($0) == nil })
    }

    /// A real train no longer running (or lost from the 3D map) ends its
    /// shot at once.
    func testAShotEndsWhenItsTrainIsGone() throws {
        var director = AmbientDirector(seed: 3)
        let full = cast(own: 0, real: 3)
        let first = try XCTUnwrap(director.update(cast: full, now: 0, allows3D: true))
        let id = try XCTUnwrap(realID(first))
        XCTAssertNil(director.update(cast: full, now: 5, allows3D: true))
        let without = Cast(trains: [], stations: full.stations, lines: full.lines, realTrains: full.realTrains.filter { $0.id != id })
        let next = try XCTUnwrap(director.update(cast: without, now: 6, allows3D: true))
        XCTAssertNotEqual(next.subject, first.subject)
    }

    // MARK: - Decision 606 (續): watching the train followed

    /// Its name shows only once it is found on built ground; found where
    /// the ground is not built three checks in a row, the director passes
    /// on, sooner than the eight a train in a tunnel is given.
    func testATrainOnBareGroundIsPassedOnAfterThreeChecks() {
        typealias Watch = AmbientDirector.RealTrainWatch
        var watch = Watch()
        XCTAssertEqual(watch.check(found: true, built: false), .waiting, "no name before the ground shows")
        XCTAssertEqual(watch.check(found: true, built: true), .seen)
        XCTAssertEqual(watch.check(found: true, built: false), .waiting)
        XCTAssertEqual(watch.check(found: true, built: false), .waiting)
        XCTAssertEqual(watch.check(found: true, built: false), .lost)
        XCTAssertEqual(AmbientDirector.realTrainBareChecks, 3)

        // Built again in between: counted afresh.
        var back = Watch()
        for _ in 0..<5 {
            XCTAssertEqual(back.check(found: true, built: false), .waiting)
            XCTAssertEqual(back.check(found: true, built: true), .seen)
        }

        // Not found (a tunnel): eight checks, whatever the ground.
        var tunnel = Watch()
        for _ in 1..<AmbientDirector.realTrainLostChecks {
            XCTAssertEqual(tunnel.check(found: false, built: false), .waiting)
        }
        XCTAssertEqual(tunnel.check(found: false, built: false), .lost)
        // Out of the tunnel on bare ground: three more, not one.
        var out = Watch()
        _ = out.check(found: true, built: false)
        _ = out.check(found: true, built: false)
        XCTAssertEqual(out.check(found: false, built: false), .waiting)
        XCTAssertEqual(out.check(found: true, built: false), .waiting)
        XCTAssertEqual(out.misses, 0)
        XCTAssertEqual(out.bare, 1)
    }

    // MARK: - With the real timetables

    private let weekday = RealServiceDay(weekday: 3)
    private let tuesday = RealServiceDay(weekday: 2)

    private func trains() throws -> AmbientRealTrains {
        let railways = try XCTUnwrap(Map3DRealTrainsTests.railways)
        let operations = try XCTUnwrap(railways.operations)
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        return AmbientRealTrains(traffic: traffic, operations: operations, frame: frame, railways: railways)
    }

    /// Each running train a candidate, a Taroko four times an express
    /// (rare), a Puyuma an express's 5; named "普悠瑪號 往<its last stop>",
    /// in English with the station's English name.
    func testTheTrainsAndTheirNames() throws {
        let trains = try trains()
        let second = 10.0 * 3_600
        let candidates = trains.candidates(at: second, on: weekday, dayBefore: tuesday)
        XCTAssertGreaterThan(candidates.count, 100)
        XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count, "unique")
        let puyuma = try XCTUnwrap(candidates.first { $0.id.place.hasPrefix("自強(普,障)#") })
        XCTAssertEqual(puyuma.weight, 5)
        if let taroko = candidates.first(where: { $0.id.place.hasPrefix("自強(太,障)#") }) { XCTAssertEqual(taroko.weight, 20) }
        let number = try XCTUnwrap(AmbientRealTrains.traNumber(ofPlace: puyuma.id.place))
        let last = try XCTUnwrap(trains.tra[number]?.destination)
        XCTAssertEqual(trains.caption(of: puyuma.id, at: second, on: weekday, dayBefore: tuesday, language: .traditionalChinese), "普悠瑪號 往\(last)")
        let english = try XCTUnwrap(trains.caption(of: puyuma.id, at: second, on: weekday, dayBefore: tuesday, language: .english))
        XCTAssertTrue(english.hasPrefix("Puyuma to "), english)
        XCTAssertFalse(english.contains { ("\u{4E00}"..."\u{9FFF}").contains($0) }, english)
        XCTAssertNotNil(trains.location(of: puyuma.id, at: second, on: weekday, dayBefore: tuesday))
        // A High Speed Rail train by its number; a metro train by its line.
        let thsr = try XCTUnwrap(candidates.first { $0.id.system == "thsr" })
        let hsr = try XCTUnwrap(trains.caption(of: thsr.id, at: second, on: weekday, dayBefore: tuesday, language: .traditionalChinese))
        XCTAssertTrue(hsr.hasPrefix("高鐵 ") && hsr.contains(" 次 往"), hsr)
        let bannan = try XCTUnwrap(candidates.first { $0.id.system == "trtc" && $0.id.line == "BL" })
        let blue = try XCTUnwrap(trains.caption(of: bannan.id, at: second, on: weekday, dayBefore: tuesday, language: .traditionalChinese))
        XCTAssertTrue(blue.hasPrefix("板南線 往"), blue)
        XCTAssertEqual(thsr.weight, 1)
        // Gone once it no longer runs.
        XCTAssertNil(trains.caption(of: RealTrainID(system: "tra", line: "x", place: "y"), at: second, on: weekday, dayBefore: tuesday,
                                    language: .english))
    }

    /// The names of Taiwan Railway's models, as the site's special trains
    /// file names its stock.
    func testTheModelsNames() {
        XCTAssertEqual(AmbientRealTrains.traName(model: "自強(普,障)", kind: "自強").chinese, "普悠瑪號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "自強(太,障)", kind: "自強").chinese, "太魯閣號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "自強(3000障)", kind: "自強").chinese, "新自強號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "自強(PP障12)", kind: "自強").chinese, "推拉式自強號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "自強(D31)", kind: "自強").chinese, "柴聯自強號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "莒光(專)", kind: "莒光/復興").chinese, "莒光號")
        XCTAssertEqual(AmbientRealTrains.traName(model: "區間快", kind: "區間快").english, "Fast Local")
        XCTAssertEqual(AmbientRealTrains.traName(model: "區間車", kind: "區間車").chinese, "區間車")
        XCTAssertEqual(AmbientRealTrains.namedTrains["5898"]?.chinese, "藍皮解憂號")
    }

    /// On the 3D map in Taipei, a Wenhu line train on its viaduct has a
    /// pose to follow: facing level, its middle within its length of the
    /// front; a train not running has none.
    func testAPoseOnThe3DMap() throws {
        // As ``Map3DRealTrainsTests``: a line 10 km across round Taipei Main
        // Station, so the scene reaches its widest.
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let at = try XCTUnwrap(RealWorldFrame(world: world)).worldPosition(latitude: 25.0478, longitude: 121.5170)
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let centre = (x: Int64(at.x), y: Int64(at.y))
        let built = try LineBuilder.line(through: [PlanPoint(x: centre.x - across, y: centre.y + across / 2),
                                                   PlanPoint(x: centre.x, y: centre.y + across / 3),
                                                   PlanPoint(x: centre.x + across, y: centre.y + across / 2)], in: world)
        let scene = Map3DScene(world: built, focus: (at.x, at.y), railways: try XCTUnwrap(Map3DRealTrainsTests.railways))
        let real = try XCTUnwrap(scene.realTrains)
        let second = 8.0 * 3_600
        var poses: [Map3DFollow.Pose] = []
        for line in real.traffic.lines where line.line.id == "BR" {
            for place in real.traffic.places(of: line, at: second, on: weekday, dayBefore: tuesday) {
                let id = RealTrainID(system: line.system, line: line.line.id, place: place.key)
                if let pose = real.pose(of: id, second: second, day: weekday, dayBefore: tuesday) { poses.append(pose) }
            }
        }
        let pose = try XCTUnwrap(poses.first, "a Wenhu train in view")
        XCTAssertEqual(pose.forward.y, 0)
        XCTAssertEqual(pose.forward.length, 1, accuracy: 0.001)
        let middle = try XCTUnwrap(pose.middle)
        XCTAssertLessThan((middle - pose.nose).length, pose.length)
        XCTAssertNil(real.pose(of: RealTrainID(system: "trtc", line: "BR", place: "none"), second: second, day: weekday, dayBefore: tuesday))
    }
}
