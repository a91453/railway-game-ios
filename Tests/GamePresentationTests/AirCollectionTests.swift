import GameCore
@testable import GamePresentation
import XCTest

/// Decision 701: the collection's aircraft page: what it lists, which
/// aircraft goes with which airport, and what its three 3D stages stand.
final class AirCollectionTests: XCTestCase {
    private static let languages = [DisplayLanguage.english, .traditionalChinese]

    // MARK: - What the page lists

    func testThePageListsTheFourAircraftSmallestFirst() {
        XCTAssertEqual(AirCollection.kinds, [.commuter19, .regional70, .narrowJet, .wideJet])
        XCTAssertEqual(AirCollection.kinds.map(AirCollection.seats), [19, 70, 180, 300])
        for language in Self.languages {
            let entries = AirCollection.aircraft(in: language)
            XCTAssertEqual(entries.map(\.id), ["commuter19", "regional70", "narrowJet", "wideJet"])
            XCTAssertEqual(Set(entries.map(\.title)).count, 4)
            for entry in entries {
                // Seats and where it flies, its size, the airports it is seen at.
                XCTAssertEqual(entry.lines.count, 3, entry.id)
                XCTAssertTrue(entry.lines.allSatisfy { !$0.isEmpty })
            }
        }
        let chinese = AirCollection.aircraft(in: .traditionalChinese)
        XCTAssertEqual(chinese.map(\.title), ["十九座雙螺旋槳", "七十座雙渦輪螺旋槳", "窄體噴射客機", "廣體噴射客機"])
        XCTAssertTrue(chinese[0].lines[0].contains("19 個座位"))
        XCTAssertTrue(chinese[0].lines[0].contains("離島"))
        XCTAssertTrue(chinese[1].lines[0].contains("國內線"))
        XCTAssertTrue(chinese[3].lines[0].contains("國際線"))
        // The makers' published sizes, as the models are built to.
        XCTAssertTrue(chinese[0].lines[1].contains("16.56") && chinese[0].lines[1].contains("16.97"), chinese[0].lines[1])
        XCTAssertTrue(chinese[3].lines[1].contains("66.80") && chinese[3].lines[1].contains("64.75"), chinese[3].lines[1])
        XCTAssertTrue(AirCollection.aircraft(in: .english)[2].lines[1].contains("44.51 m long"))
    }

    func testThePageNamesNoOperatorAndNoInternals() {
        // Names a player would read as an airline's or a maker's, and the
        // program's own words.
        let banned = ["航空公司", "航空", "Airlines", "Airways", "Air ", "ATR", "Airbus", "Boeing", "Dornier", "A321", "A350", "study", "studies",
                      "GameCore", "Map3D"]
        for language in Self.languages {
            let scenes = AirCollection.scenes(in: language).map(\.entry)
            let texts = (AirCollection.aircraft(in: language) + scenes).flatMap { [$0.title] + $0.lines } + [AirCollection.note(in: language)]
            for text in texts {
                for word in banned { XCTAssertFalse(text.contains(word), "\(word) in \(text)") }
            }
        }
    }

    // MARK: - Which aircraft goes with which airport

    func testEachAircraftIsSeenAtTheCataloguesAirportsItFliesFrom() {
        func keys(_ kind: AirCollection.Kind) -> [String] { AirCollection.places(of: kind).map(\.key) }
        // The 19-seat type flies to the small islands from Kaohsiung.
        XCTAssertEqual(keys(.commuter19), ["khh"])
        XCTAssertEqual(keys(.regional70), ["tsa", "rmq", "khh"])
        XCTAssertEqual(keys(.narrowJet), ["tpe1", "tpe2", "tsa", "rmq", "khh"])
        XCTAssertEqual(keys(.wideJet), ["tpe1", "tpe2", "tsa", "khh"])
        // Every airport of the catalogue has an aircraft, and a larger
        // type never where no smaller jet is.
        for place in AirportCatalog.places {
            let seen = AirCollection.kinds(atAirportNamed: place.chinese)
            XCTAssertFalse(seen.isEmpty, place.key)
            if seen.contains(.wideJet) { XCTAssertTrue(seen.contains(.narrowJet), place.key) }
        }
        XCTAssertEqual(AirCollection.kinds(atAirportNamed: "臺北松山機場"), [.regional70, .narrowJet, .wideJet])
        XCTAssertEqual(AirCollection.kinds(atAirportNamed: "桃園機場第一航廈"), [.narrowJet, .wideJet])
        XCTAssertEqual(AirCollection.kinds(atAirportNamed: "No such airport"), [])
        // Taoyuan's two terminals read as one airport in a card's list.
        let wide = AirCollection.aircraft(in: .traditionalChinese)[3].lines[2]
        XCTAssertEqual(wide, "看得到的機場：桃園機場、臺北松山機場、高雄國際機場")
        XCTAssertEqual(AirCollection.aircraft(in: .english)[0].lines[2], "Seen at Kaohsiung International Airport")
    }

    // MARK: - The airports of the game's map

    func testAMapsAirportsAreListedWithTheirDay() {
        let world = ScreenshotScene.airportWorld(in: .traditionalChinese)
        let days = world.airportDays()
        XCTAssertEqual(days.count, 2)
        for language in Self.languages {
            let entries = AirCollection.mapAirports(days, in: language)
            XCTAssertEqual(entries.map(\.id), ["airport.1", "airport.2"])
            XCTAssertEqual(entries.map(\.title), days.map { $0.airport.title(in: language) })
            for (entry, day) in zip(entries, days) {
                // The day's flights and passengers, as the sights panel counts them.
                XCTAssertTrue(entry.lines[0].contains(day.flights.groupedText), entry.lines[0])
                XCTAssertTrue(entry.lines[0].contains(day.passengers.groupedText), entry.lines[0])
                XCTAssertEqual(entry.lines.count, 2)
            }
            XCTAssertFalse(AirCollection.mapAirportsTitle(in: language).isEmpty)
        }
        let chinese = AirCollection.mapAirports(days, in: .traditionalChinese)
        XCTAssertEqual(chinese[0].lines[1], "看得到：七十座雙渦輪螺旋槳、窄體噴射客機、廣體噴射客機")
        XCTAssertEqual(chinese[1].lines[1], "看得到：七十座雙渦輪螺旋槳、窄體噴射客機")
        // No airports, no list.
        XCTAssertTrue(AirCollection.mapAirports([], in: .english).isEmpty)
    }

    // MARK: - The 3D stages

    func testThePageOpensTheAircraftStageAndListsBothAirports() {
        XCTAssertEqual(FerryCollection.Page.aircraft.exhibit, .aircraft)
        XCTAssertEqual(AirCollection.scenes(in: .english).map(\.exhibit), [.cityAirport, .islandAirport])
        let exhibits: [Map3DCollectionShowcase.Exhibit] = [.aircraft, .cityAirport, .islandAirport]
        XCTAssertEqual(Map3DCollectionShowcase.Exhibit.allCases.filter(\.isAir), exhibits)
        for exhibit in exhibits {
            for language in Self.languages {
                XCTAssertFalse(exhibit.title(in: language).isEmpty)
                XCTAssertFalse(exhibit.openTitle(in: language).isEmpty)
            }
        }
        XCTAssertEqual(Set(exhibits.map { $0.openTitle(in: .traditionalChinese) }).count, 3)
    }

    func testTheFourAircraftStandNoseToNoseWithClearWingTips() {
        let parked = Map3DAirShowcase.parked(.aircraft)
        XCTAssertEqual(parked.map(\.kind), AirCollection.kinds)
        for aircraft in parked {
            XCTAssertEqual(aircraft.middle.x + aircraft.length / 2, 0, accuracy: 0.001)
            XCTAssertEqual(aircraft.forward, Map3DPoint(1, 0, 0))
        }
        for (a, b) in zip(parked, parked.dropFirst()) {
            XCTAssertEqual(b.middle.z - a.middle.z - (a.wingspan + b.wingspan) / 2, Map3DAirShowcase.wingGap, accuracy: 0.001)
        }
        // The mesh holds each model's triangles as they are, turned to the scene.
        let mesh = Map3DAirShowcase.mesh(.aircraft)
        let models = AirCollection.kinds.map { Map3DAircraftStudies.model($0) }
        XCTAssertGreaterThan(mesh.vertices.count, models.map(\.vertexCount).reduce(0, +))
        let bounds = try? XCTUnwrap(mesh.bounds)
        // On the ground (y up); the floodlight masts stand just over the wide-body's fin.
        XCTAssertEqual(bounds?.min.y ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(bounds?.max.y ?? 0, 18.35, accuracy: 0.06)
        XCTAssertGreaterThan(bounds?.max.y ?? 0, Map3DAircraftStudies.dimensions(.wideJet).height)
        let layout = Map3DCollectionShowcase.layout(.aircraft)
        XCTAssertTrue(layout.pieces.isEmpty)
        XCTAssertGreaterThanOrEqual(bounds?.min.x ?? -.infinity, layout.low.x - 0.01)
        XCTAssertLessThanOrEqual(bounds?.max.z ?? .infinity, layout.high.z + 0.01)
        XCTAssertGreaterThanOrEqual(bounds?.min.z ?? -.infinity, layout.low.z - 0.01)
    }

    func testACardOpensTheStageOnItsAircraft() {
        let parked = Map3DAirShowcase.parked(.aircraft)
        for (index, aircraft) in parked.enumerated() {
            let layout = Map3DCollectionShowcase.layout(.aircraft, focus: index)
            XCTAssertEqual(layout.focus.x, aircraft.middle.x, accuracy: 0.001)
            XCTAssertEqual(layout.focus.z, aircraft.middle.z, accuracy: 0.001)
            // Far enough to take the whole aircraft in.
            XCTAssertGreaterThan(layout.closeDistance, max(aircraft.length, aircraft.wingspan))
            let camera = Map3DCollectionShowcase.camera(.closeUp, layout: layout, viewport: (844, 390))
            // Ahead of the nose and to one side, above the ground.
            XCTAssertGreaterThan(camera.eye.x, 0, "\(aircraft.kind)")
            XCTAssertGreaterThan(camera.eye.y, 1)
        }
        // Out of range: the first.
        XCTAssertEqual(Map3DCollectionShowcase.layout(.aircraft, focus: 9), Map3DCollectionShowcase.layout(.aircraft))
        XCTAssertNotEqual(Map3DCollectionShowcase.layout(.aircraft, focus: 3), Map3DCollectionShowcase.layout(.aircraft))
    }

    func testTheCityAirportsJetsStandAtTheirBridges() {
        let bridges = Map3DAirportStudies.connections(.cityTerminal).jetbridges
        let door = Map3DAircraftStudies.metadata(.narrowJet).door
        let stands = Map3DAirShowcase.cityStands
        XCTAssertEqual(stands.map(\.kind), [.narrowJet, .narrowJet, .regional70])
        for (stand, bridge) in zip(stands, [bridges[1], bridges[2]]) {
            // Nose-in (turned half round): the door at the bridge's cab, a stand-off away.
            XCTAssertEqual(stand.x - door.x, bridge.exit.x, accuracy: 0.001)
            XCTAssertEqual(stand.y - door.y - bridge.exit.y, Map3DAirShowcase.bridgeStandOff, accuracy: 0.001)
        }
        // Their wing tips clear each other, and the turboprop's stand clears both.
        XCTAssertGreaterThan(stands[1].y - stands[0].y, Map3DAircraftStudies.dimensions(.narrowJet).wingspan)
        XCTAssertGreaterThan(stands[2].y - stands[1].y,
                             (Map3DAircraftStudies.dimensions(.narrowJet).wingspan + Map3DAircraftStudies.dimensions(.regional70).wingspan) / 2)
        XCTAssertEqual(Map3DAirShowcase.parked(.cityAirport).map(\.kind), stands.map(\.kind))
        XCTAssertEqual(Map3DAirShowcase.parked(.islandAirport).map(\.kind), [.commuter19])
    }

    func testEachStageStandsItsModelsOnTheGroundInsideWhatTheCameraShows() {
        for exhibit in Map3DCollectionShowcase.Exhibit.allCases where exhibit.isAir {
            for far in [false, true] {
                let layout = Map3DCollectionShowcase.layout(exhibit, far: far)
                XCTAssertEqual(layout.far, far)
                let mesh = Map3DAirShowcase.mesh(exhibit, far: far)
                XCTAssertFalse(mesh.isEmpty, "\(exhibit)")
                let bounds = try? XCTUnwrap(mesh.bounds)
                XCTAssertEqual(bounds?.min.y ?? -1, 0, accuracy: 0.001, "\(exhibit)")
                for (low, high, from, to) in [(bounds?.min.x, bounds?.max.x, layout.low.x, layout.high.x),
                                              (bounds?.min.z, bounds?.max.z, layout.low.z, layout.high.z),
                                              (bounds?.min.y, bounds?.max.y, layout.low.y, layout.high.y)] {
                    XCTAssertGreaterThanOrEqual(low ?? -.infinity, from - 0.01, "\(exhibit)")
                    XCTAssertLessThanOrEqual(high ?? .infinity, to + 0.01, "\(exhibit)")
                }
                // Every normal is a unit vector still, after the turn.
                XCTAssertTrue(mesh.vertices.allSatisfy { abs($0.nx * $0.nx + $0.ny * $0.ny + $0.nz * $0.nz - 1) < 0.001 })
                // The ground chunk draws all of it at every distance: grass, then the stage.
                let ground = Map3DCollectionShowcase.ground(layout)
                XCTAssertEqual(ground.baseIndexCount, ground.mesh.indices.count)
                XCTAssertEqual(ground.mesh.triangleCount, mesh.triangleCount + 2)
                XCTAssertEqual(ground.mesh.vertices[0].color, Map3DStudyColor.grass)
                XCTAssertTrue(Map3DCollectionShowcase.frame(layout).instances.isEmpty)
            }
            // The far stage is lighter, and the near one has lamps to light at night.
            let near = Map3DAirShowcase.mesh(exhibit), far = Map3DAirShowcase.mesh(exhibit, far: true)
            XCTAssertLessThan(far.triangleCount, near.triangleCount, "\(exhibit)")
            XCTAssertTrue(near.vertices.contains { $0.glows }, "\(exhibit)")
            XCTAssertLessThan(near.triangleCount, 120_000, "\(exhibit)")
        }
        // The other pages stand nothing in the ground.
        XCTAssertTrue(Map3DAirShowcase.mesh(.ferries).isEmpty)
        XCTAssertTrue(Map3DAirShowcase.parked(.cableways).isEmpty)
    }

    func testAnAirportIsLookedAtFromItsApron() {
        // The city's: from behind the first jet (it faces the terminal, −x)
        // on its open side (+z: no other aircraft there).
        let city = Map3DCollectionShowcase.layout(.cityAirport)
        let first = Map3DAirShowcase.parked(.cityAirport)[0], second = Map3DAirShowcase.parked(.cityAirport)[1]
        XCTAssertLessThan(second.middle.z, first.middle.z)
        let close = Map3DCollectionShowcase.camera(.closeUp, layout: city, viewport: (844, 390))
        XCTAssertGreaterThan(close.eye.x, first.middle.x)
        XCTAssertGreaterThan(close.eye.z, first.middle.z)
        let side = Map3DCollectionShowcase.camera(.side, layout: city, viewport: (844, 390))
        XCTAssertGreaterThan(side.eye.z, first.middle.z + first.wingspan / 2)
        XCTAssertEqual(side.eye.x, first.middle.x, accuracy: 0.5)
        // The island's: from the runway's side (+x), the terminal behind.
        let island = Map3DCollectionShowcase.layout(.islandAirport)
        let plane = Map3DAirShowcase.parked(.islandAirport)[0]
        for view in [Map3DShowcase.View.closeUp, .side] {
            XCTAssertGreaterThan(Map3DCollectionShowcase.camera(view, layout: island, viewport: (844, 390)).eye.x, plane.middle.x, "\(view)")
        }
    }
}
