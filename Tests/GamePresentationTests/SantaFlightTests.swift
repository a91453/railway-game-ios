import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 831 (SANTA-FLIGHT): Santa's sleigh over the 3D map on
/// Christmas Eve, by the device's own clock: when it flies, where it comes
/// from, how it takes off from Rovaniemi, and what follows it.
final class SantaFlightTests: XCTestCase {
    private let taipei = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0, year: Int = 2026,
                      in calendar: Calendar? = nil) -> Date {
        (calendar ?? taipei).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    func testItFliesFromSixOnChristmasEveToSixOnChristmasMorning() throws {
        XCTAssertNil(SantaFlight.moment(at: date(12, 24, 17, 59, second: 59), calendar: taipei))
        XCTAssertEqual(SantaFlight.moment(at: date(12, 24, 18), calendar: taipei), .init(pass: 0, seconds: 0))
        // Every six minutes a pass: 19:00 is the eleventh's first second.
        XCTAssertEqual(SantaFlight.moment(at: date(12, 24, 19), calendar: taipei), .init(pass: 10, seconds: 0))
        XCTAssertEqual(SantaFlight.moment(at: date(12, 25, 0, 3), calendar: taipei), .init(pass: 60, seconds: 180))
        let last = try XCTUnwrap(SantaFlight.moment(at: date(12, 25, 5, 59, second: 59), calendar: taipei))
        XCTAssertEqual(last.pass, 119)
        XCTAssertNil(SantaFlight.moment(at: date(12, 25, 6), calendar: taipei))
        // Any other night of the event, or the year, nothing.
        XCTAssertNil(SantaFlight.moment(at: date(12, 23, 20), calendar: taipei))
        XCTAssertNil(SantaFlight.moment(at: date(12, 25, 20), calendar: taipei))
        XCTAssertNil(SantaFlight.moment(at: date(12, 31, 22), calendar: taipei))
        XCTAssertNil(SantaFlight.moment(at: date(6, 24, 20), calendar: taipei))
        // The player's own evening, wherever the device is: 20:00 in
        // Rovaniemi is 02:00 in Taipei the next day.
        let helsinki = WinterEvent.calendar(in: TimeZone(identifier: "Europe/Helsinki")!)
        XCTAssertEqual(SantaFlight.moment(at: date(12, 24, 20, in: helsinki), calendar: helsinki)?.pass, 20)
        XCTAssertEqual(SantaFlight.moment(at: date(12, 24, 20, in: helsinki), calendar: taipei)?.pass, 80)
        // The settings' "Festive decorations" off: none.
        XCTAssertNil(SantaFlight.moment(at: date(12, 24, 20), switchedOn: false, calendar: taipei))
    }

    func testOverTaiwanItComesFromRovaniemiAndPassesOverThePlaceLookedAt() throws {
        // Taipei Main Station; Rovaniemi lies north-north-west (some 335°
        // on the great circle), so the sleigh flies south-south-east.
        let anchor = Map3DPoint(500, 10, -200)
        let track = SantaFlight.track(over: anchor, latitude: 25.0478, longitude: 121.5170) { _, _ in 10 }
        let bearing = Double(atan2(track.forward.x, -track.forward.z)) * 180 / .pi
        XCTAssertEqual((bearing + 360).truncatingRemainder(dividingBy: 360), 155, accuracy: 10)
        XCTAssertFalse(track.fromRunway)
        XCTAssertEqual(track.length, 2 * SantaFlight.reach)
        XCTAssertEqual(track.level, SantaFlight.cruise)
        XCTAssertEqual(track.seconds, 180)
        // Half way, it is right over the place, 250 m up, and level.
        let over = try XCTUnwrap(SantaFlight.drawn(pass: 3, on: track, seconds: 90))
        XCTAssertEqual(over.ground.x, anchor.x, accuracy: 0.01)
        XCTAssertEqual(over.ground.z, anchor.z, accuracy: 0.01)
        XCTAssertEqual(over.ground.y + over.height, 260, accuracy: 0.01)
        XCTAssertEqual(over.pitch, 0)
        XCTAssertEqual(over.flight, Map3DAircraft.FlightID(santa: 3))
        XCTAssertEqual(SantaFlight.stage(of: try XCTUnwrap(over.phase)), .flying)
        // Gone once past the place by its reach, until the next pass.
        XCTAssertNotNil(SantaFlight.drawn(pass: 3, on: track, seconds: 180))
        XCTAssertNil(SantaFlight.drawn(pass: 3, on: track, seconds: 181))
        // Over a mountain it keeps its clearance.
        let mountain = SantaFlight.track(over: anchor, latitude: 25.0478, longitude: 121.5170) { x, _ in x > 1_500 ? 900 : 10 }
        XCTAssertEqual(mountain.level, 900 - 10 + SantaFlight.clearance)
    }

    func testOverHongKongItComesFromTheNorthWest() {
        let track = SantaFlight.track(over: Map3DPoint(0, 0, 0), latitude: 22.2988, longitude: 114.1722) { _, _ in 0 }
        let bearing = Double(atan2(track.forward.x, -track.forward.z)) * 180 / .pi
        XCTAssertEqual((bearing + 360).truncatingRemainder(dividingBy: 360), 145, accuracy: 10)
    }

    func testOnTheRovaniemiMapItTakesOffFromTheAirportsRunway() throws {
        // A 16 km map round the town and the airport, 8 km north of the
        // station.
        let bounds = GameWorld.newGame().bounds
        let frame = RealWorldFrame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 66.53, longitudeDegrees: 25.78)), bounds: bounds)
        let ends = try XCTUnwrap(SantaFlight.runwayEnds(frame: frame, bounds: bounds))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        // Some 3 km long, runway 21's threshold north-east of its other end.
        let east = (ends.to.x - ends.from.x) / metre, south = (ends.to.y - ends.from.y) / metre
        XCTAssertEqual((east * east + south * south).squareRoot(), 3_000, accuracy: 150)
        XCTAssertLessThan(east, 0)
        XCTAssertGreaterThan(south, 0)
        // A map round Taipei has it nowhere.
        let taipeiFrame = RealWorldFrame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)), bounds: bounds)
        XCTAssertNil(SantaFlight.runwayEnds(frame: taipeiFrame, bounds: bounds))

        // Off the runway's threshold, towards the town 4 km south-west.
        let runway = (from: Map3DPoint(0, 100, 0), to: Map3DPoint(-1_500, 100, 2_600))
        let town = Map3DPoint(-2_000, 100, 3_500)
        let track = SantaFlight.track(over: town, latitude: 66.4985, longitude: 25.7124, runway: runway) { _, _ in 100 }
        XCTAssertTrue(track.fromRunway)
        XCTAssertEqual(track.start, runway.from)
        let away = Map3DPoint(town.x, 0, town.z).length
        XCTAssertEqual(track.length, away + SantaFlight.reach, accuracy: 0.5)
        let rolling = try XCTUnwrap(SantaFlight.drawn(pass: 0, on: track, seconds: 0))
        XCTAssertEqual(rolling.height, 0)
        XCTAssertEqual(SantaFlight.stage(of: try XCTUnwrap(rolling.phase)), .takingOff)
        XCTAssertGreaterThan(rolling.pitch, 0)
        // Up at 250 m after some 1.6 km, then level over the town.
        let up = try XCTUnwrap(SantaFlight.drawn(pass: 0, on: track, seconds: Double(away / SantaFlight.speed)))
        XCTAssertEqual(up.height, SantaFlight.cruise)
        XCTAssertEqual(up.ground.x, town.x, accuracy: 0.5)
        XCTAssertEqual(SantaFlight.stage(of: try XCTUnwrap(up.phase)), .flying)
        // A place too far for one pass, or the airport itself: it keeps to
        // the runway's way.
        let far = SantaFlight.track(over: Map3DPoint(0, 100, -20_000), latitude: 66.4985, longitude: 25.7124, runway: runway) { _, _ in 100 }
        XCTAssertEqual(far.forward.x, runway.to.x / 3_002.0, accuracy: 0.01)
        XCTAssertEqual(far.length, SantaFlight.reach)
        XCTAssertLessThan(far.seconds, SantaFlight.every)
    }

    func testTheSkyKeepsAPassWhereItBeganAndForgetsItAfter() throws {
        var sky = SantaFlight.Sky()
        var laid = 0
        func track(over x: Float) -> () -> SantaFlight.Track? {
            { laid += 1; return SantaFlight.track(over: Map3DPoint(x, 0, 0), latitude: 25.0478, longitude: 121.5170) { _, _ in 0 } }
        }
        let start = date(12, 24, 21)
        let first = try XCTUnwrap(sky.sleigh(at: start, origin: (0, 0), switchedOn: true, still: false, calendar: taipei, track: track(over: 0)))
        // The camera moves on: the pass flies where it began.
        let later = try XCTUnwrap(sky.sleigh(at: start.addingTimeInterval(90), origin: (0, 0), switchedOn: true, still: false,
                                             calendar: taipei, track: track(over: 5_000)))
        XCTAssertEqual(laid, 1)
        XCTAssertEqual(later.ground.x, 0, accuracy: 0.01)
        XCTAssertEqual(later.flight, first.flight)
        // The follow camera finds it by its pass.
        let id = try XCTUnwrap(first.flight)
        XCTAssertEqual(sky.sleigh(of: id, at: start.addingTimeInterval(90), switchedOn: true, still: false, calendar: taipei)?.ground,
                       later.ground)
        XCTAssertTrue(Map3DAircraft.canFollow(later))
        // Gone after its 180 s; the next pass flies over the new place.
        XCTAssertNil(sky.sleigh(of: id, at: start.addingTimeInterval(200), switchedOn: true, still: false, calendar: taipei))
        XCTAssertNil(sky.sleigh(at: start.addingTimeInterval(200), origin: (0, 0), switchedOn: true, still: false, calendar: taipei,
                                track: track(over: 5_000)))
        let next = try XCTUnwrap(sky.sleigh(at: start.addingTimeInterval(360 + 90), origin: (0, 0), switchedOn: true, still: false,
                                            calendar: taipei, track: track(over: 5_000)))
        XCTAssertEqual(next.ground.x, 5_000, accuracy: 0.01)
        XCTAssertNil(sky.sleigh(of: id, at: start.addingTimeInterval(360 + 90), switchedOn: true, still: false, calendar: taipei))
        // Reduce Motion: nothing flies by itself.
        XCTAssertNil(sky.sleigh(at: start.addingTimeInterval(360 + 91), origin: (0, 0), switchedOn: true, still: true, calendar: taipei,
                                track: track(over: 5_000)))
        // A blank map: no way.
        XCTAssertNil(sky.sleigh(at: start, origin: (0, 0), switchedOn: true, still: false, calendar: taipei) { nil })
    }

    func testTheFollowBarSaysOnlyWhatItIs() throws {
        let track = SantaFlight.track(over: Map3DPoint(0, 0, 0), latitude: 25.0478, longitude: 121.5170) { _, _ in 0 }
        let drawn = try XCTUnwrap(SantaFlight.drawn(pass: 1, on: track, seconds: 10))
        let state = Map3DAircraft.State(flight: try XCTUnwrap(drawn.flight), kind: drawn.kind, phase: try XCTUnwrap(drawn.phase), airport: nil)
        let zh = SantaFlight.followFacts(of: state, in: .traditionalChinese, speed: nil)
        XCTAssertEqual(zh.name, "聖誕老人的雪橇")
        XCTAssertEqual(zh.directionText, "從羅瓦涅米機場出發")
        XCTAssertEqual(zh.stopText, "飛過地圖上空")
        XCTAssertEqual(GameWorld.newGame().aircraftFollowFacts(of: state, in: .english).name, "Santa's sleigh")
        // Followed from behind, close: as long as the team, not an
        // aircraft's.
        let pose = Map3DAircraft.pose(of: drawn)
        XCTAssertEqual(pose.length, Map3DAircraft.sideLength(SantaFlight.Model.length))
        XCTAssertEqual((pose.nose - pose.rail).length, SantaFlight.Model.length / 2, accuracy: 0.01)
        XCTAssertEqual(SantaFlight.views, [.back, .side])
        XCTAssertEqual(SantaFlight.view(.window), .back)
    }

    func testTheBellsAreHeardAsItPassesNear() throws {
        let track = SantaFlight.track(over: Map3DPoint(0, 0, 0), latitude: 25.0478, longitude: 121.5170) { _, _ in 0 }
        var camera = Map3DCamera()
        camera.target = Map3DPoint(0, 0, 0)
        camera.distance = 400
        let over = try XCTUnwrap(SantaFlight.drawn(pass: 0, on: track, seconds: 90))
        let near = try XCTUnwrap(SantaFlight.sound(of: over, camera: camera))
        XCTAssertGreaterThan(near.volume, 0.3)
        let coming = try XCTUnwrap(SantaFlight.drawn(pass: 0, on: track, seconds: 10))
        XCTAssertNil(SantaFlight.sound(of: coming, camera: camera), "3 km off: not heard")
        XCTAssertNil(SantaFlight.sound(of: nil, camera: camera))
    }

    func testTheStandInModelIsInThePackAfterTheWinterDecorations() throws {
        let pack = Map3DModelPack.standard
        let index = try XCTUnwrap(pack.index(of: SantaFlight.Model.name))
        let winter = try XCTUnwrap(Map3DWinterLights.drawn.last.flatMap { pack.index(of: $0.name) })
        XCTAssertEqual(index, winter + 1)
        let model = pack.models[index]
        XCTAssertLessThan(model.triangleCount, 2_000)
        XCTAssertEqual(model.maximum.x - model.minimum.x, SantaFlight.Model.length, accuracy: 0.3)
        // Rudolph's nose and the lantern are lit at night.
        XCTAssertTrue(model.vertices.contains { $0.layer == Map3DVertex.glowing && $0.color == SantaFlight.Model.noseLamp })
    }
}
