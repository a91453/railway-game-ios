import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 712: an airport that flies to a city outside Taiwan opens the
/// city's map once it had enough passengers on the company's trains in a
/// day; the device remembers it, the game says so, and the map picker's row
/// of the city is closed until then.
@MainActor
final class AirRoutesTests: XCTestCase {
    private let offered = AirRoutes(offered: [.hongKong])

    /// The whole of Taiwan with `riders` on the company's trains yesterday
    /// at the airport called `name`.
    private func taiwan(_ name: String, riders: Int64) throws -> GameWorld {
        var world = GameWorld.newWholeTaiwanGame()
        let index = try XCTUnwrap(world.airports.firstIndex { $0.englishName == name }, name)
        world.airports[index].yesterdayRiders = riders
        return world
    }

    private func launcher(in directory: URL, demo: Bool = false, overseas: Set<OverseasMap> = [.hongKong]) async -> GameLauncher {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        launcher.isDemoMode = demo
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: overseas, pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        return launcher
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AirRoutesTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - The rule

    /// The five airports with flights to Hong Kong, as the Civil Aviation
    /// Administration's tables list them; Songshan and the rest have none.
    func testTheAirportsThatFlyToHongKong() {
        let flying = GameWorld.newWholeTaiwanGame().airports.filter { $0.flies(to: .hongKong) }.map(\.englishName)
        XCTAssertEqual(flying, [
            "Taoyuan Airport Terminal 1", "Taoyuan Airport Terminal 2", "Taichung International Airport", "Kaohsiung International Airport",
            "Hualien Airport",
        ])
    }

    /// 500 riders in a day at one of them open Hong Kong; 499 do not, nor
    /// any number at an airport with no flights there.
    func testFiveHundredRidersInADayOpenTheCity() throws {
        XCTAssertEqual(OverseasMap.hongKong.ridersToOpen, 500)
        XCTAssertEqual(offered.earned(in: try taiwan("Kaohsiung International Airport", riders: 499)), [])
        XCTAssertEqual(offered.earned(in: try taiwan("Kaohsiung International Airport", riders: 500)), [.hongKong])
        XCTAssertEqual(offered.earned(in: try taiwan("Taichung International Airport", riders: 2_000)), [.hongKong])
        XCTAssertEqual(offered.earned(in: try taiwan("Taipei Songshan Airport", riders: 9_000)), [])
        XCTAssertEqual(offered.earned(in: try taiwan("Penghu Airport", riders: 9_000)), [])
    }

    /// A city the app does not offer is not opened, and one open already
    /// is not opened again.
    func testOnlyAnOfferedClosedCityIsEarned() throws {
        let world = try taiwan("Kaohsiung International Airport", riders: 800)
        XCTAssertEqual(AirRoutes().earned(in: world), [])
        XCTAssertEqual(AirRoutes(offered: [.hongKong], opened: [.hongKong]).earned(in: world), [])
        XCTAssertEqual(AirRoutes(offered: [], opened: [.hongKong]).opened, [], "what is not offered is not open")
    }

    // MARK: - The airport's row

    /// The row of an airport that flies there says how far yesterday was,
    /// then that the flights are open; other airports' rows say nothing,
    /// and none does while the app offers no city.
    func testTheAirportsRowSaysHowFar() throws {
        let world = try taiwan("Kaohsiung International Airport", riders: 320)
        let days = world.airportDays()
        let kaohsiung = try XCTUnwrap(days.first { $0.airport.englishName == "Kaohsiung International Airport" })
        let songshan = try XCTUnwrap(days.first { $0.airport.englishName == "Taipei Songshan Airport" })
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .traditionalChinese, routes: offered),
            "香港航線：昨天 320／500 人搭你的列車，一天滿 500 人就開航，可以到香港經營。"
        )
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .english, routes: offered),
            "Hong Kong flights: 320 of 500 rode your trains yesterday. Reach 500 in a day to open the Hong Kong map."
        )
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .traditionalChinese, routes: AirRoutes(offered: [.hongKong], opened: [.hongKong])),
            "香港航線已開航，可以到香港的地圖經營。"
        )
        XCTAssertNil(songshan.airRouteText(in: .traditionalChinese, routes: offered))
        XCTAssertNil(kaohsiung.airRouteText(in: .traditionalChinese, routes: AirRoutes()))
    }

    // MARK: - The launcher

    /// The launcher keeps the city's map closed, with the way to open it;
    /// a game whose airport had its riders opens it, says so once in the
    /// status line and the news, and the device remembers.
    func testTheLauncherOpensTheCityAndRemembers() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        XCTAssertEqual(launcher.airRoutes, AirRoutes(offered: [.hongKong]))
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
        XCTAssertEqual(launcher.message?.text, OverseasMap.hongKong.howToOpen(in: .traditionalChinese))
        XCTAssertNil(launcher.session)

        let short = GameSession(world: try taiwan("Kaohsiung International Airport", riders: 499), language: .traditionalChinese)
        launcher.checkAirRoutes(of: short)
        XCTAssertEqual(short.airRoutes, AirRoutes(offered: [.hongKong]))
        XCTAssertNil(short.message)
        XCTAssertNil(launcher.preferences.airRoutesOpened)

        let session = GameSession(world: try taiwan("Kaohsiung International Airport", riders: 500), language: .traditionalChinese)
        launcher.checkAirRoutes(of: session)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["hongKong"])
        XCTAssertEqual(session.airRoutes.opened, [.hongKong])
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.message?.text, "台灣↔香港開航了。開新遊戲時，在實景地圖可以選「香港」。")
        XCTAssertEqual(session.news.items.filter { $0.category == .achievement }.count, 1)
        // The next midnight says nothing more.
        session.message = nil
        launcher.checkAirRoutes(of: session)
        XCTAssertNil(session.message)
        XCTAssertEqual(session.news.items.filter { $0.category == .achievement }.count, 1)

        // The next launch has it open, and starts the city's map.
        let next = await self.launcher(in: directory)
        XCTAssertEqual(next.airRoutes.opened, [.hongKong])
        XCTAssertTrue(next.startOverseasMap(.hongKong), next.message?.text ?? "")
        XCTAssertEqual(next.session?.airRoutes.opened, [.hongKong])
    }

    /// A demo's trains are not the player's: its riders open nothing. The
    /// demo mode has every city open without remembering any.
    func testADemoOpensNothingAndTheDemoModeHasAllOpen() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        let demo = GameSession(world: try taiwan("Kaohsiung International Airport", riders: 5_000), language: .english)
        demo.news.isDemo = true
        launcher.checkAirRoutes(of: demo)
        XCTAssertNil(launcher.preferences.airRoutesOpened)
        XCTAssertNil(demo.message)

        launcher.isDemoMode = true
        XCTAssertEqual(launcher.airRoutes.opened, [.hongKong])
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertNil(launcher.preferences.airRoutesOpened)
        launcher.isDemoMode = false
        XCTAssertEqual(launcher.airRoutes.opened, [])
    }

    /// While the app reads no city (``OverseasMaps/open`` empty) nothing is
    /// offered: no game says anything of flights to open, whatever its
    /// airports carried, and a game the launcher starts is told so.
    func testNothingIsOfferedWhileNoCityIsRead() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory, overseas: OverseasMaps.open.subtracting([.hongKong]))
        XCTAssertEqual(launcher.airRoutes, AirRoutes())
        let session = GameSession(world: try taiwan("Kaohsiung International Airport", riders: 5_000), language: .english)
        launcher.checkAirRoutes(of: session)
        XCTAssertNil(session.message)
        XCTAssertNil(launcher.preferences.airRoutesOpened)
        XCTAssertNil(session.world.airportDays().first { $0.airport.flies(to: .hongKong) }?.airRouteText(in: .english, routes: session.airRoutes))
    }

    /// A game the launcher starts knows what is offered, so its airports'
    /// rows show how far they are.
    func testAGameBegunKnowsWhatIsOffered() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.startWholeTaiwan()
        XCTAssertEqual(launcher.session?.airRoutes, AirRoutes(offered: [.hongKong]))
    }

    /// Preferences written before the flights read as none opened, and
    /// the list is kept in the file.
    func testThePreferencesKeepTheOpenedCities() throws {
        let before = try JSONEncoder().encode(LauncherPreferences())
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("airRoutesOpened"))
        XCTAssertNil(try JSONDecoder().decode(LauncherPreferences.self, from: before).airRoutesOpened)
        var preferences = LauncherPreferences()
        preferences.airRoutesOpened = ["hongKong"]
        let read = try JSONDecoder().decode(LauncherPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(read.airRoutesOpened, ["hongKong"])
    }

    // MARK: - Hong Kong's own airport

    /// Hong Kong's map has Hong Kong International Airport, at the Airport
    /// Express's station; its flights to Taiwan carry what Taiwan's
    /// airports' flights to it do, and all of them are international.
    func testHongKongsMapHasItsAirport() throws {
        let world = GameWorld.newOverseasGame(try HongKongMapTests.ground())
        XCTAssertEqual(world.airports.map(\.name), ["香港國際機場"])
        let airport = try XCTUnwrap(world.airports.first)
        XCTAssertEqual(airport.dailyPassengers, 61_000_000 / 365)
        XCTAssertEqual(airport.dailyFlights, 394_730 / 365)
        XCTAssertEqual(airport.destinations.map(\.englishName), ["Taipei Taoyuan", "Kaohsiung", "Taichung", "Hualien", ""])
        XCTAssertTrue(airport.destinations.allSatisfy { !$0.isDomestic })
        XCTAssertEqual(airport.destinations.map(\.yearlyPassengers).reduce(0, +), 61_000_000)
        XCTAssertEqual(airport.destinations.map(\.yearlyFlights).reduce(0, +), 394_730)
        XCTAssertFalse(OverseasMap.allCases.contains { airport.flies(to: $0) })
        // Both ends of each route agree.
        for (key, name) in [("khh", "高雄"), ("rmq", "臺中"), ("hun", "花蓮")] {
            let place = try XCTUnwrap(AirportCatalog.places.first { $0.key == key })
            let there = try XCTUnwrap(AirportCatalog.destinations(of: place).first { $0.name == "香港" })
            let here = try XCTUnwrap(airport.destinations.first { $0.name == name })
            XCTAssertEqual(here.yearlyPassengers, there.yearlyPassengers, key)
            XCTAssertEqual(here.yearlyFlights, there.yearlyFlights, key)
        }
        // Taiwan's maps do not hold it, and a game of Hong Kong read back
        // keeps it.
        XCTAssertFalse(GameWorld.newWholeTaiwanGame().airports.contains { $0.name == "香港國際機場" })
        XCTAssertEqual(AirportCatalog.withAirports(world).airports, world.airports)
    }
}
