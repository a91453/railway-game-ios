import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// FIX-L19-P3: the small faults review L19 found
/// (`docs/research/REVIEW_L19_2026-11-12.md`), each with what it was.
@MainActor
final class ReviewL19FixTests: XCTestCase {
    /// `FollowAircraftTests`' field: a runway, a taxiway and forty stands.
    private func field(seed: Int32 = 7) -> Map3DAircraft.Laid.Field {
        var field = Map3DAircraft.Laid.Field(
            seed: seed, airports: [0],
            stands: (0..<40).map { .init(nose: Map3DPoint(400 + Float($0) * 60, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57) },
            runways: [.init(a: Map3DPoint(0, 0, 0), b: Map3DPoint(3_000, 0, 0), length: 3_000)], wide: 0.3, propeller: 0.2
        )
        field.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(600, 0, 200), Map3DPoint(100, 0, 200), Map3DPoint(100, 0, 0)],
                           [Map3DPoint(1_800, 0, 200), Map3DPoint(2_900, 0, 200)]])
        return field
    }

    private func traffic(day: Int64, each: Int) -> Map3DAircraft.Traffic {
        Map3DAircraft.Traffic(day: day, landings: [Array(repeating: each, count: 24)], takeOffs: [Array(repeating: each, count: 24)])
    }

    // MARK: - P3-4

    /// The flights seen before midnight are the same flights after it,
    /// where the old day's numbers put them, though the new day has other
    /// numbers; and those of the new day's first hour, first drawn before
    /// midnight, stay as drawn then.
    func testMidnightDoesNotMoveTheAircraftInTheAir() throws {
        let yesterday = traffic(day: 0, each: 20), today = traffic(day: 1, each: 30)
        let laid = Map3DAircraft.Laid(fields: [field()])
        let midnight = Double(GameTime.secondsPerDay)
        let before = laid.aircraft(second: midnight - 20, traffic: yesterday).filter { $0.flight != nil }
        XCTAssertGreaterThan(before.count, 1)
        XCTAssertTrue(before.contains { $0.flight?.hours == 23 } && before.contains { $0.flight?.hours == 24 })
        let after = laid.aircraft(second: midnight + 20, traffic: today)
        // What the old day's numbers alone would draw then.
        let asLaid = Map3DAircraft.Laid(fields: [field()])
        var same = 0, movedWithoutTheFix = 0
        let fresh = Map3DAircraft.Laid(fields: [field()])
        for aircraft in before {
            let id = try XCTUnwrap(aircraft.flight)
            guard let expected = asLaid.aircraft(of: id, second: midnight + 20, traffic: yesterday) else { continue }
            let found = try XCTUnwrap(after.first { $0.flight == id }, "\(id) gone at midnight")
            XCTAssertEqual(found.ground, expected.ground)
            XCTAssertEqual(found.height, expected.height)
            XCTAssertEqual(found.phase, expected.phase)
            XCTAssertEqual(laid.aircraft(of: id, second: midnight + 20, traffic: today)?.ground, expected.ground)
            same += 1
            // Laid anew with the new day's numbers it would be elsewhere.
            if fresh.aircraft(of: id, second: midnight + 20, traffic: today)?.ground != expected.ground { movedWithoutTheFix += 1 }
        }
        XCTAssertGreaterThan(same, 1)
        XCTAssertGreaterThan(movedWithoutTheFix, 0)
    }

    /// An hour's flights land the way their own day's season has it, so
    /// the day the direction turns does not turn those already landing.
    func testAnHoursFlightsLandTheWayOfTheirOwnDay() throws {
        // 30 September of the first year: the next day lands north-east.
        let day = try XCTUnwrap((0..<400).map(Int64.init).first {
            !Map3DAircraft.Laid.landsNorthEast(day: $0) && Map3DAircraft.Laid.landsNorthEast(day: $0 + 1)
        })
        let numbers = traffic(day: day, each: 6), laid = Map3DAircraft.Laid(fields: [field()])
        let midnight = Double((day + 1) * GameTime.secondsPerDay)
        let before = laid.aircraft(second: midnight - 20, traffic: numbers).filter { $0.flight?.hours == (day + 1) * 24 - 1 }
        let after = laid.aircraft(second: midnight + 5, traffic: traffic(day: day + 1, each: 6))
        XCTAssertFalse(before.isEmpty)
        for aircraft in before {
            guard let then = after.first(where: { $0.flight == aircraft.flight }) else { continue }
            // 25 seconds on, not at the runway's other end.
            XCTAssertLessThan((then.ground - aircraft.ground).length, 25 * 90, "\(String(describing: aircraft.flight))")
        }
    }

    // MARK: - P3-7

    /// When the kept hours pass their limit, those round the hour asked
    /// for stay: none of them is laid again.
    func testTheHoursDrawnNowAreKeptWhenTheOldOnesGo() {
        let kept = Map3DAircraft.Laid.Kept()
        typealias Hour = Map3DAircraft.Laid.Kept.Hour
        var made = 0
        let fields = 13, last = Int64(Map3DAircraft.Laid.Kept.mostHours / fields + 4)
        for hour in 0...last {
            for field in 0..<fields {
                for near in (hour - 2)...(hour + 2) where near >= 0 {
                    _ = kept.plans(Hour(field: field, hours: near)) {
                        made += 1
                        return []
                    }
                }
            }
        }
        // Each hour of each field laid once, however often the old go.
        XCTAssertEqual(made, fields * Int(last + 3))
        XCTAssertLessThanOrEqual(kept.hoursCount, Map3DAircraft.Laid.Kept.mostHours + 1)
        XCTAssertGreaterThanOrEqual(kept.hoursCount, fields * 5)
    }

    // MARK: - P3-3

    /// By day the map asks for no lamps; each type's shape is one value.
    func testNoLampsAreWorkedOutByDay() throws {
        let numbers = traffic(day: 0, each: 6), laid = Map3DAircraft.Laid(fields: [field()])
        let flight = try XCTUnwrap(Map3DAircraft.Laid.flights(of: laid.fields[0], day: 0, hour: 10, traffic: numbers).first)
        let pack = Map3DModelPack(models: Map3DAircraft.drawn), eye = Map3DPoint(600, 30, 300)
        var night = Map3DTrains.Frame(), day = Map3DTrains.Frame()
        laid.add(to: &night, pack: pack, second: flight.time - 20, traffic: numbers, eye: eye, blink: 0)
        laid.add(to: &day, pack: pack, second: flight.time - 20, traffic: numbers, eye: eye, blink: 0, lit: false)
        XCTAssertFalse(night.lamps.isEmpty)
        XCTAssertTrue(day.lamps.isEmpty)
        XCTAssertEqual(day.instances.count, night.instances.count)
        for kind in Map3DAircraft.Kind.allCases {
            XCTAssertGreaterThan(Map3DAircraftStudies.shape(kind).hull.count, 4)
        }
    }

    // MARK: - P3-9, P3-10

    /// An aircraft has one name: the follow bar's is the collection's, and
    /// the collection's scenes use it too.
    func testAnAircraftHasOneName() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            for kind in Map3DAircraft.Kind.allCases {
                XCTAssertEqual(kind.text(in: language), AirCollection.name(kind, in: language))
            }
        }
        let city = AirCollection.scenes(in: .traditionalChinese).first { $0.exhibit == .cityAirport }?.entry.lines.joined() ?? ""
        XCTAssertTrue(city.contains(AirCollection.name(.regional70, in: .traditionalChinese)))
        XCTAssertTrue(city.contains(AirCollection.name(.narrowJet, in: .traditionalChinese)))
        let island = AirCollection.scenes(in: .traditionalChinese).first { $0.exhibit == .islandAirport }?.entry.lines.joined() ?? ""
        XCTAssertTrue(island.contains(AirCollection.name(.commuter19, in: .traditionalChinese)))
        XCTAssertEqual(Map3DAircraft.Phase.takeOffRoll.text(in: .traditionalChinese), "起飛中")
    }

    /// The release notes call the real-world map what the rest of the game
    /// calls it.
    func testTheReleaseNotesCallTheMapWhatTheGameDoes() {
        for entry in WhatsNew.entries {
            for line in entry.items + entry.fixes {
                XCTAssertFalse(line.chinese.contains("真實地圖"), line.chinese)
                XCTAssertFalse(line.english.contains("real map"), line.english)
            }
        }
    }

    // MARK: - P3-13, P3-14, P3-15

    func testTheAirportsDayOffTheMainActorIsTheWorlds() async {
        let world = ScreenshotScene.airport.make(in: .traditionalChinese)
        let days = await AirCollection.airportDays(of: world)
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days, world.airportDays())
    }

    /// The stage to open carries its aircraft: two cards are two values.
    func testTheStageShownCarriesItsAircraft() {
        typealias Shown = Map3DCollectionShowcase.Exhibit.Shown
        XCTAssertNotEqual(Shown(.aircraft, focus: 1), Shown(.aircraft, focus: 2))
        XCTAssertNotEqual(Shown(.aircraft, focus: 1).id, Shown(.aircraft, focus: 2).id)
        XCTAssertEqual(Shown(.cityAirport).focus, 0)
        XCTAssertNotEqual(Shown(.cityAirport).id, Shown(.islandAirport).id)
    }

    /// A drag that began elsewhere than the one kept starts from where
    /// the handle stands now: a drag the system cancelled leaves nothing.
    func testACancelledDragDoesNotStartTheNext() {
        typealias Drag = ManualDrive.Lever.Drag
        let power = ManualDrive.Notch(step: 5), brake = ManualDrive.Notch(step: -5)
        let first = Drag.began(atX: 20, y: 40, on: power, held: nil)
        XCTAssertEqual(first.notch, power)
        // The same drag goes on from its first notch, wherever the handle is by now.
        XCTAssertEqual(Drag.began(atX: 20, y: 40, on: ManualDrive.Notch(step: 2), held: first), first)
        // Cancelled, never ended; the handle is at B5 when the next begins.
        let next = Drag.began(atX: 22, y: 130, on: brake, held: first)
        XCTAssertEqual(next.notch, brake)
        XCTAssertEqual(ManualDrive.Lever.notch(from: next.notch, dragged: 0.01), brake)
    }

    // MARK: - P3-16

    /// With a station under the finger, an aircraft is followed only when
    /// its middle is under it too, not when its long body reaches there.
    func testAStationUnderTheFingerComesBeforeAnAircraftsBody() throws {
        let numbers = traffic(day: 0, each: 6), laid = Map3DAircraft.Laid(fields: [field()])
        let flight = try XCTUnwrap(Map3DAircraft.Laid.flights(of: laid.fields[0], day: 0, hour: 10, traffic: numbers).first)
        let second = flight.time + 2
        let aircraft = try XCTUnwrap(laid.aircraft(of: flight.id, second: second, traffic: numbers))
        let pose = Map3DAircraft.pose(of: aircraft)
        let camera = Map3DCamera(target: pose.rail, distance: 120, viewport: (844, 390))
        let middle = try XCTUnwrap(camera.screenPoint(of: pose.rail)), nose = try XCTUnwrap(camera.screenPoint(of: pose.nose))
        let long = ((nose.x - middle.x) * (nose.x - middle.x) + (nose.y - middle.y) * (nose.y - middle.y)).squareRoot()
        XCTAssertGreaterThan(long, 40)
        // Toward the nose, past the plain reach.
        let x = middle.x + (nose.x - middle.x) * 0.8, y = middle.y + (nose.y - middle.y) * 0.8
        XCTAssertNotNil(laid.followable(atX: x, y: y, camera: camera, second: second, traffic: numbers, within: 30))
        XCTAssertNil(laid.followable(atX: x, y: y, camera: camera, second: second, traffic: numbers, within: 30, tight: true))
        XCTAssertNotNil(laid.followable(atX: middle.x + 5, y: middle.y, camera: camera, second: second, traffic: numbers, within: 30, tight: true))
    }

    /// The station a tap would select is found without selecting it.
    func testTheStationUnderATapIsFoundWithoutSelectingIt() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(world.stations.first)
        let session = GameSession(world: world, language: .english)
        let space = Map3DPick.Space(originX: Double(station.location.x) - 2_000, originY: Double(station.location.y) + 900)
        let ground = Map3DPick.ground(of: world, in: space)
        let anchor = try XCTUnwrap(Map3DTap.anchor(of: station.id, in: world, space: space, ground: ground))
        let camera = Map3DCamera(target: anchor, distance: 200, heading: 0.6, viewport: (844, 390))
        let at = try XCTUnwrap(camera.screenPoint(of: anchor))
        let hit = try XCTUnwrap(Map3DPick.pick(atX: at.x, y: at.y, camera: camera, space: space, bounds: world.bounds, nodes: [], ground: ground))
        let reach = Map3DTap.reach(at: hit.point, camera: camera)
        XCTAssertEqual(session.stationUnderMap3D(at: hit, reach: reach), station.id)
        XCTAssertNil(session.selectedStation)
        let away = try XCTUnwrap(Map3DPick.pick(atX: at.x + 300, y: at.y, camera: camera, space: space, bounds: world.bounds, nodes: [], ground: ground))
        XCTAssertNil(session.stationUnderMap3D(at: away, reach: Map3DTap.reach(at: away.point, camera: camera)))
        XCTAssertEqual(session.tapMap3D(at: hit, reach: reach), station.id)
    }

    // MARK: - P3-17

    /// A real station's building says its real name while the game's
    /// station has it (or a name not in Chinese); a station the player
    /// named has its own, or only "車站".
    func testTheNameBoardsSayTheGamesStationsName() {
        typealias Kit = StationKitBuilder
        XCTAssertEqual(Kit.boardName(real: "集集", game: nil), "集集車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "集集"), "集集車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "集集車站"), "集集車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "集集站"), "集集車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "Jiji"), "集集車站")
        XCTAssertEqual(Kit.boardName(real: "保安", game: "Bao'an"), "保安車站")
        // The player's own: written when the strokes can, else just "車站".
        XCTAssertEqual(Kit.boardName(real: "集集", game: "保安"), "保安車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "安"), "安車站")
        XCTAssertEqual(Kit.boardName(real: "集集", game: "水里"), "車站")
        XCTAssertEqual(Kit.boardName(real: "保安", game: "新集集"), "車站")
        XCTAssertEqual(Kit.boardName(real: "保安", game: "站"), "站車站")
    }

    /// The building drawn for a station of another name has fewer strokes
    /// (no real name), and the kit's own model is as it was.
    func testABuildingOfAnotherNameDoesNotCarryTheRealOne() throws {
        for (name, profile) in [("集集", Map3DStationKit.Profile.jiji), ("保安", .baoan)] {
            let station = try XCTUnwrap(Map3DStationKit.stations.first { $0.system == "tra_sched" && $0.name == name })
            XCTAssertEqual(station.profile, profile)
            var real = StationKitBuilder(), same = StationKitBuilder(), own = StationKitBuilder()
            real.house(station)
            same.gameName = name
            same.house(station)
            own.gameName = "水里"
            own.house(station)
            XCTAssertEqual(real.mesh.vertices.count, same.mesh.vertices.count, name)
            XCTAssertLessThan(own.mesh.vertices.count, real.mesh.vertices.count, name)
        }
    }
}
