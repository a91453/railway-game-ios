import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 699: the airports on the 3D map: the airfields' file, what the
/// scene lays of them, and the aircraft parked, landing and leaving.
final class Map3DAirfieldsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let airfields = Result {
        try RealAirfields(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_airfields.json")))
    }

    /// Metres between two places, near enough.
    private func metres(_ a: RealAirfields.Point, _ b: RealAirfields.Point) -> Double {
        let east = (a.longitude - b.longitude) * 111_320 * cos(a.latitude * .pi / 180), north = (a.latitude - b.latitude) * 110_574
        return (east * east + north * north).squareRoot()
    }

    // MARK: - The file

    /// Every terminal of the game's catalogue stands by an airfield of the
    /// file with a runway a jet can use, parking positions and aprons.
    func testTheCataloguesAirportsHaveTheirAirfields() throws {
        let fields = try Self.airfields.get().fields
        for place in AirportCatalog.places {
            let terminal = RealAirfields.Point(latitude: place.latitude, longitude: place.longitude)
            let field = try XCTUnwrap(fields.first { metres($0.at, terminal) < 4_000 }, place.key)
            let longest = field.runways.map { metres($0.line[0], $0.line[$0.line.count - 1]) }.max() ?? 0
            XCTAssertGreaterThan(longest, 2_400, place.key)
            XCTAssertGreaterThanOrEqual(field.stands.count, 6, place.key)
            XCTAssertFalse(field.aprons.isEmpty, place.key)
            XCTAssertFalse(field.taxiways.isEmpty, place.key)
        }
        XCTAssertEqual(fields.first { $0.iata == "TPE" }?.runways.count, 2)
        XCTAssertGreaterThan(fields.first { $0.iata == "TPE" }?.bridges.count ?? 0, 40)
    }

    /// A runway's first name is the number painted at its first point: the
    /// way it runs from there, in tens of degrees.
    func testARunwaysNamesFollowItsLine() throws {
        for field in try Self.airfields.get().fields {
            for runway in field.runways where runway.ref.contains("/") {
                let first = runway.line[0], last = runway.line[runway.line.count - 1]
                let east = (last.longitude - first.longitude) * cos(first.latitude * .pi / 180), north = last.latitude - first.latitude
                let heading = (atan2(east, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                let name = Double(runway.ref.split(separator: "/")[0].filter(\.isNumber)) ?? 0
                let off = abs((heading - name * 10 + 540).truncatingRemainder(dividingBy: 360) - 180)
                // Names follow the magnetic heading, a few degrees off.
                XCTAssertLessThan(off, 20, "\(field.iata) \(runway.ref) runs \(heading)")
            }
        }
    }

    func testAFileOutOfShapeIsRefused() {
        XCTAssertThrowsError(try RealAirfields(data: Data(#"{"airports":[{"iata":"X","icao":"","at":[1],"runways":[],"taxiways":[],"aprons":[],"stands":[],"bridges":[],"towers":[]}]}"#.utf8)))
        XCTAssertThrowsError(try RealAirfields(data: Data(#"{"airports":[{"iata":"X","icao":"","at":[1,2],"runways":[{"width":45,"line":[1,2]}],"taxiways":[],"aprons":[],"stands":[],"bridges":[],"towers":[]}]}"#.utf8)))
    }

    // MARK: - The scene

    /// A real-world map round Songshan: with the airfields, the scene has
    /// the runway's asphalt along its whole length, its paint, the aprons'
    /// concrete and lights for the night; without them, none.
    func testTheSceneLaysTheRunwayItsPaintAndItsAprons() throws {
        let fields = try Self.airfields.get()
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0694, longitudeDegrees: 121.5525)))
        var land = RealNoBuildLand(areas: [])
        func count(_ colour: UInt32, in scene: Map3DScene) -> Int {
            let drawn = Map3DLook.colour(colour)
            return scene.chunks.reduce(0) { $0 + $1.mesh.vertices.filter { $0.color == drawn || $0.color == colour }.count }
        }
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let bare = Map3DScene(world: world, baseMap: tiles, noBuild: land)
        land.airfields = fields
        let scene = Map3DScene(world: world, baseMap: tiles, noBuild: land)
        typealias Paint = Map3DScene.Builder.Airfield
        XCTAssertEqual(count(Paint.asphalt, in: bare), 0)
        XCTAssertGreaterThan(count(Paint.asphalt, in: scene), 100)
        XCTAssertGreaterThan(count(Paint.paint, in: scene), 300, "the runway's marks")
        XCTAssertGreaterThan(count(Paint.apron, in: scene), 100)
        XCTAssertGreaterThan(count(Paint.yellow, in: scene), 100, "the taxiways' centre lines")
        // The asphalt reaches both ends of runway 10/28.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let runway = try XCTUnwrap(fields.fields.first { $0.iata == "TSA" }?.runways.first)
        let asphalt = Map3DLook.colour(Paint.asphalt)
        for end in [runway.line[0], runway.line[runway.line.count - 1]] {
            let at = frame.worldPosition(latitude: end.latitude, longitude: end.longitude)
            let point = scene.point(worldX: at.x, worldY: at.y, height: 0)
            let near = scene.chunks.contains { chunk in
                chunk.mesh.vertices.contains { ($0.color == asphalt || $0.color == Paint.asphalt) && abs($0.x - point.x) < 80 && abs($0.z - point.z) < 80 }
            }
            XCTAssertTrue(near, "asphalt at the runway's end")
        }
        XCTAssertGreaterThan(scene.chunks.reduce(0) { $0 + $1.shadows.triangleCount } - bare.chunks.reduce(0) { $0 + $1.shadows.triangleCount }, 500,
                             "the night lights' pools")
    }

    // MARK: - The aircraft

    private func field(runways: Int = 1, length: Float = 3_000, wide: Float = 0.3, propeller: Float = 0.2) -> Map3DAircraft.Laid.Field {
        Map3DAircraft.Laid.Field(
            seed: 7, airports: [0],
            stands: (0..<10).map { .init(nose: Map3DPoint(Float($0) * 60, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57) },
            runways: (0..<runways).map { .init(a: Map3DPoint(0, 0, Float($0) * 1_500), b: Map3DPoint(length, 0, Float($0) * 1_500), length: length) },
            wide: wide, propeller: propeller
        )
    }

    private func traffic(landings: Int, takeOffs: Int) -> Map3DAircraft.Traffic {
        Map3DAircraft.Traffic(day: 0, landings: [Array(repeating: landings, count: 24)], takeOffs: [Array(repeating: takeOffs, count: 24)])
    }

    /// An hour's flights are as many as the airport counts, inside the
    /// hour, the same each time asked, and no take-off starts within 75
    /// seconds of a landing on its runway.
    func testAnHoursFlightsAreTheAirportsCount() {
        for runways in [1, 2] {
            let field = field(runways: runways), traffic = traffic(landings: 20, takeOffs: 18)
            let flights = Map3DAircraft.Laid.flights(of: field, day: 3, hour: 9, traffic: traffic)
            XCTAssertEqual(flights.filter(\.landing).count, 20)
            XCTAssertEqual(flights.filter { !$0.landing }.count, 18)
            let start = 3.0 * 86_400 + 9 * 3_600
            XCTAssertTrue(flights.allSatisfy { $0.time >= start && $0.time < start + 3_600 + 400 })
            XCTAssertEqual(flights.map(\.time), Map3DAircraft.Laid.flights(of: field, day: 3, hour: 9, traffic: traffic).map(\.time))
            for takeOff in flights where !takeOff.landing {
                XCTAssertFalse(flights.contains { $0.landing && $0.runway == takeOff.runway && abs($0.time - takeOff.time) < 75 })
            }
            XCTAssertEqual(Set(flights.map(\.runway)).count, runways)
        }
        XCTAssertTrue(Map3DAircraft.Laid.flights(of: field(), day: 3, hour: 9, traffic: traffic(landings: 0, takeOffs: 0)).isEmpty)
    }

    /// A landing comes down its glide path to the runway, touches down on
    /// it, slows and is gone before the far end; a take-off rolls from
    /// rest, lifts off on the runway and climbs away.
    func testALandingComesDownAndATakeOffClimbs() throws {
        let field = field()
        let landing = Map3DAircraft.Laid.Flight(time: 1_000, landing: true, runway: 0, kind: .narrowJet, livery: 0)
        var last: Float = .infinity, seen = 0
        for second in stride(from: 880.0, through: 1_000, by: 5) {
            guard let pose = Map3DAircraft.Laid.pose(of: landing, on: field, second: second, northEast: true) else { continue }
            XCTAssertLessThanOrEqual(pose.height, last)
            last = pose.height
            seen += 1
        }
        XCTAssertGreaterThan(seen, 15)
        let down = try XCTUnwrap(Map3DAircraft.Laid.pose(of: landing, on: field, second: 1_000, northEast: true))
        XCTAssertEqual(down.height, 0)
        XCTAssertTrue((0...3_000).contains(down.ground.x))
        // 60 m/s out, about 3° of glide path.
        let out = try XCTUnwrap(Map3DAircraft.Laid.pose(of: landing, on: field, second: 960, northEast: true))
        XCTAssertEqual(out.height / (down.ground.x - out.ground.x), Float(Map3DAircraft.glide), accuracy: 0.002)
        for second in stride(from: 1_000.0, through: 1_400, by: 5) {
            if let pose = Map3DAircraft.Laid.pose(of: landing, on: field, second: second, northEast: true) {
                XCTAssertEqual(pose.height, 0)
                XCTAssertLessThan(pose.ground.x, 3_000)
            }
        }
        XCTAssertNil(Map3DAircraft.Laid.pose(of: landing, on: field, second: 1_400, northEast: true))
        XCTAssertNil(Map3DAircraft.Laid.pose(of: landing, on: field, second: 800, northEast: true))

        let takeOff = Map3DAircraft.Laid.Flight(time: 1_000, landing: false, runway: 0, kind: .narrowJet, livery: 0)
        let waiting = try XCTUnwrap(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 990, northEast: true))
        let rolling = try XCTUnwrap(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 1_020, northEast: true))
        let climbing = try XCTUnwrap(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 1_060, northEast: true))
        XCTAssertEqual(waiting.height, 0)
        XCTAssertEqual(rolling.height, 0)
        XCTAssertGreaterThan(rolling.ground.x, waiting.ground.x + 300)
        XCTAssertGreaterThan(climbing.height, 100)
        XCTAssertGreaterThan(climbing.pitch, 0.1)
        XCTAssertNil(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 1_300, northEast: true))
        // The other way in summer: from the runway's other end.
        let summer = try XCTUnwrap(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 990, northEast: false))
        XCTAssertGreaterThan(summer.ground.x, 2_800)
        XCTAssertLessThan(summer.forward.x, 0)
    }

    /// A field with a taxiway from the runway to a stand: a landing
    /// taxis off the runway, along the taxiway and in to its stand, and
    /// stands there for the turnaround; a take-off stands there, is pushed
    /// back, taxis out and lines up. Neither jumps on the way.
    func testAFlightTaxisBetweenTheRunwayAndItsStand() throws {
        var field = field()
        field.stands = [.init(nose: Map3DPoint(600, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57)]
        field.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(600, 0, 200), Map3DPoint(100, 0, 200), Map3DPoint(100, 0, 0)]])
        XCTAssertEqual(field.links.count, 2)
        XCTAssertEqual(field.rotation, [0])
        XCTAssertNotNil(field.stands[0].node)
        let parked = Map3DPoint(600, 0, 300) - Map3DPoint(0, 0, 1) * (Map3DAircraftStudies.dimensions(.narrowJet).length / 2)
        for landing in [true, false] {
            let flight = Map3DAircraft.Laid.Flight(time: 10_000, landing: landing, runway: 0, kind: .narrowJet, livery: 0, stand: 0)
            var last: Map3DAircraft.Drawn?, wasParked = false, moved = false
            for second in stride(from: 6_500.0, through: 13_500, by: 1) {
                guard let pose = Map3DAircraft.Laid.pose(of: flight, on: field, second: second, northEast: true) else {
                    last = nil
                    continue
                }
                if let last {
                    let step = (pose.ground - last.ground).length
                    XCTAssertLessThan(step, pose.height > 0 || last.height > 0 || abs(second - 10_000) < 45 ? 95 : 10, "at \(second)")
                    // Never turned right round in a second.
                    XCTAssertGreaterThan(pose.forward.dot(last.forward), 0.2, "at \(second)")
                }
                if !pose.flying {
                    XCTAssertEqual((pose.ground - parked).length, 0, accuracy: 0.01)
                    XCTAssertEqual(pose.stand, 0)
                    wasParked = true
                } else {
                    moved = true
                }
                last = pose
            }
            XCTAssertTrue(wasParked && moved, landing ? "a landing" : "a take-off")
        }
        // A landing stands at its stand 20 minutes after; a take-off 20
        // minutes before.
        let landing = Map3DAircraft.Laid.Flight(time: 10_000, landing: true, runway: 0, kind: .narrowJet, livery: 0, stand: 0)
        XCTAssertEqual(Map3DAircraft.Laid.pose(of: landing, on: field, second: 11_200, northEast: true)?.flying, false)
        let takeOff = Map3DAircraft.Laid.Flight(time: 10_000, landing: false, runway: 0, kind: .narrowJet, livery: 0, stand: 0)
        XCTAssertEqual(Map3DAircraft.Laid.pose(of: takeOff, on: field, second: 8_800, northEast: true)?.flying, false)
    }

    /// With Reduce Motion nothing flies or taxis: only the parked ones.
    func testNothingMovesWithReducedMotion() {
        var field = field()
        field.stands = (0..<45).map { .init(nose: Map3DPoint(Float($0) * 60, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57) }
        field.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(0, 0, 200), Map3DPoint(0, 0, 0)],
                           [Map3DPoint(1_800, 0, 200), Map3DPoint(2_700, 0, 200)]])
        XCTAssertGreaterThan(field.rotation.count, 25)
        let laid = Map3DAircraft.Laid(fields: [field])
        let traffic = traffic(landings: 4, takeOffs: 4)
        var flew = false
        for second in stride(from: 40_000.0, to: 47_200, by: 30) {
            XCTAssertTrue(laid.aircraft(second: second, traffic: traffic, still: true).allSatisfy { !$0.flying })
            flew = flew || laid.aircraft(second: second, traffic: traffic).contains { $0.flying }
        }
        XCTAssertTrue(flew)
        // No two aircraft at one stand.
        for second in stride(from: 40_000.0, to: 47_200, by: 60) {
            let stands = laid.aircraft(second: second, traffic: traffic).compactMap(\.stand)
            XCTAssertEqual(stands.count, Set(stands).count, "at \(second)")
        }
    }

    /// October to March they land towards the north-east.
    func testTheyLandIntoTheMonsoon() {
        XCTAssertTrue(Map3DAircraft.Laid.landsNorthEast(day: 0))
        XCTAssertFalse(Map3DAircraft.Laid.landsNorthEast(day: 6 * 30))
        XCTAssertTrue(Map3DAircraft.Laid.landsNorthEast(day: 10 * 30))
    }

    /// The types follow the airport and what fits: no wide-bodied jet on a
    /// short runway or a narrow stand.
    func testTheTypesFitTheRunwayAndTheStand() {
        let big = field(wide: 0.4, propeller: 0)
        XCTAssertEqual(Map3DAircraft.Laid.kind(big, share: 0.1, runway: 3_600), .wideJet)
        XCTAssertEqual(Map3DAircraft.Laid.kind(big, share: 0.6, runway: 3_600), .narrowJet)
        XCTAssertEqual(Map3DAircraft.Laid.kind(big, share: 0.1, runway: 2_000), .narrowJet)
        XCTAssertEqual(Map3DAircraft.Laid.kind(big, share: 0.1, runway: 3_600, room: 40), .narrowJet)
        XCTAssertEqual(Map3DAircraft.Laid.kind(big, share: 0.1, runway: 3_600, room: 30), .regional70)
        let small = field(length: 1_200, wide: 0, propeller: 1)
        XCTAssertEqual(Map3DAircraft.Laid.kind(small, share: 0.5, runway: 1_200), .regional70)
        XCTAssertEqual(Map3DAircraft.Laid.kind(small, share: 0.9, runway: 1_200), .commuter19)
    }

    /// The pack has each type near and far, lighter far, its livery left
    /// clear for the tint.
    func testThePackHasTheAircraft() throws {
        let pack = Map3DModelPack.standard
        for kind in Map3DAircraft.Kind.allCases {
            let near = pack.models[try XCTUnwrap(pack.index(of: Map3DAircraft.name(kind)))]
            let far = pack.models[try XCTUnwrap(pack.index(of: Map3DAircraft.name(kind, far: true)))]
            XCTAssertLessThan(far.vertexCount, near.vertexCount)
            XCTAssertEqual(near.length, Map3DAircraftStudies.dimensions(kind).length, accuracy: 0.1)
        }
        for model in Map3DAircraft.drawn where model.name.hasPrefix("aircraft-") {
            XCTAssertTrue(model.vertices.contains { $0.color >> 24 == 0 }, model.name)
        }
    }
}
