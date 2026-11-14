import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 712: the maps flights reach. The player's first real map is
/// open, Taiwan's or a city's; on a map that is open, an airport that
/// flies to another opens it once it had enough passengers on the
/// company's trains in a day. The device remembers it, the game says so,
/// and the map picker's row of a closed map says what opens it.
@MainActor
final class AirRoutesTests: XCTestCase {
    private let taiwan = AirMap.taiwan.id
    private let hongKong = OverseasMap.hongKong.rawValue
    /// A player who began in Taiwan.
    private var fromTaiwan: AirRoutes { AirRoutes(cities: [.hongKong], opened: [taiwan]) }
    /// A player who began in Hong Kong, in a game there.
    private var fromHongKong: AirRoutes { AirRoutes(cities: [.hongKong], opened: [hongKong], here: hongKong) }

    /// The whole of Taiwan with `riders` on the company's trains yesterday
    /// at the airport called `name`.
    private func taiwanWorld(_ name: String, riders: Int64) throws -> GameWorld {
        var world = GameWorld.newWholeTaiwanGame()
        let index = try XCTUnwrap(world.airports.firstIndex { $0.englishName == name }, name)
        world.airports[index].yesterdayRiders = riders
        return world
    }

    /// Hong Kong's map with `riders` at its airport yesterday.
    private func hongKongWorld(riders: Int64) throws -> GameWorld {
        var world = GameWorld.newOverseasGame(try HongKongMapTests.ground())
        world.airports[0].yesterdayRiders = riders
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
    /// Hong Kong's airport flies to Taiwan, and no Taiwan airport's
    /// domestic flights count as flights to Taiwan.
    func testTheAirportsThatFlyToEachMap() throws {
        let airports = GameWorld.newWholeTaiwanGame().airports
        XCTAssertEqual(airports.filter { $0.flies(to: .hongKong) }.map(\.englishName), [
            "Taoyuan Airport Terminal 1", "Taoyuan Airport Terminal 2", "Taichung International Airport", "Kaohsiung International Airport",
            "Hualien Airport",
        ])
        XCTAssertEqual(airports.filter { $0.flies(to: AirMap.taiwan) }.map(\.englishName), [])
        let there = try hongKongWorld(riders: 0).airports
        XCTAssertEqual(there.filter { $0.flies(to: AirMap.taiwan) }.map(\.name), ["香港國際機場"])
        XCTAssertTrue(AirMap.taiwan.airports.isSuperset(of: ["臺北桃園", "高雄", "臺中", "花蓮"]))
        XCTAssertFalse(AirMap.taiwan.airports.contains("香港"))
    }

    /// 500 riders in a day at one of them open Hong Kong; 499 do not, nor
    /// any number at an airport with no flights there.
    func testFiveHundredRidersInADayOpenTheCity() throws {
        XCTAssertEqual(AirRoute.standardRiders, 500)
        XCTAssertEqual(fromTaiwan.routes, [AirRoute(from: taiwan, to: hongKong, riders: 500), AirRoute(from: hongKong, to: taiwan, riders: 500)])
        XCTAssertEqual(fromTaiwan.earned(in: try taiwanWorld("Kaohsiung International Airport", riders: 499)), [])
        XCTAssertEqual(fromTaiwan.earned(in: try taiwanWorld("Kaohsiung International Airport", riders: 500)), [AirMap(.hongKong)])
        XCTAssertEqual(fromTaiwan.earned(in: try taiwanWorld("Taichung International Airport", riders: 2_000)), [AirMap(.hongKong)])
        XCTAssertEqual(fromTaiwan.earned(in: try taiwanWorld("Taipei Songshan Airport", riders: 9_000)), [])
        XCTAssertEqual(fromTaiwan.earned(in: try taiwanWorld("Penghu Airport", riders: 9_000)), [])
    }

    /// The other way round: a player who began in Hong Kong opens Taiwan
    /// from Hong Kong's airport, by the same count.
    func testHongKongOpensTaiwanTheSameWay() throws {
        XCTAssertTrue(fromHongKong.canStart(hongKong))
        XCTAssertFalse(fromHongKong.canStart(taiwan))
        XCTAssertEqual(fromHongKong.earned(in: try hongKongWorld(riders: 499)), [])
        XCTAssertEqual(fromHongKong.earned(in: try hongKongWorld(riders: 500)), [.taiwan])
        // A game on Taiwan's map opens nothing towards Taiwan.
        var inTaiwan = fromHongKong
        inTaiwan.here = taiwan
        XCTAssertEqual(inTaiwan.earned(in: try hongKongWorld(riders: 5_000)), [])
    }

    /// A map the app does not offer is not opened, and one open already
    /// is not opened again. Before a first map is chosen any can start.
    func testOnlyAnOfferedClosedMapIsEarned() throws {
        let world = try taiwanWorld("Kaohsiung International Airport", riders: 800)
        XCTAssertEqual(AirRoutes().earned(in: world), [])
        XCTAssertEqual(AirRoutes(cities: [.hongKong], opened: [taiwan, hongKong]).earned(in: world), [])
        XCTAssertEqual(AirRoutes(cities: [], opened: [hongKong]).opened, [], "what is not offered is not open")
        let new = AirRoutes(cities: [.hongKong])
        XCTAssertTrue(new.canStart(taiwan) && new.canStart(hongKong))
        XCTAssertTrue(AirRoutes().canStart(taiwan), "with no city to open, Taiwan is as it always was")
    }

    /// Adding a map is data: a third one, with an airport name and its
    /// routes, is opened, listed and described by the same rule, and a
    /// route can ask its own count.
    func testAThirdMapIsOnlyData() throws {
        let tokyo = AirMap(id: "tokyo", english: "Tokyo", chinese: "東京", airports: ["東京成田", "東京羽田"])
        var routes = AirRoutes(
            maps: [.taiwan, AirMap(.hongKong), tokyo],
            routes: [
                AirRoute(from: taiwan, to: hongKong), AirRoute(from: hongKong, to: taiwan),
                AirRoute(from: taiwan, to: "tokyo", riders: 800), AirRoute(from: "tokyo", to: taiwan), AirRoute(from: "tokyo", to: "nowhere"),
            ],
            opened: [taiwan]
        )
        XCTAssertEqual(routes.routes.count, 4, "a route to a map that is not offered is dropped")
        XCTAssertFalse(routes.canStart("tokyo"))
        XCTAssertEqual(routes.earned(in: try taiwanWorld("Taoyuan Airport Terminal 1", riders: 600)), [AirMap(.hongKong)])
        XCTAssertEqual(routes.earned(in: try taiwanWorld("Taoyuan Airport Terminal 1", riders: 800)), [AirMap(.hongKong), tokyo])
        XCTAssertEqual(routes.earned(in: try taiwanWorld("Taipei Songshan Airport", riders: 800)), [tokyo], "Songshan flies to Haneda, not to Hong Kong")
        XCTAssertEqual(routes.earned(in: try taiwanWorld("Penghu Airport", riders: 9_000)), [])
        routes.best = ["tokyo": 320]
        XCTAssertEqual(
            routes.howToOpen("tokyo", in: .traditionalChinese),
            "還沒開航。在台灣的地圖上，讓一座飛東京的機場一天有 800 人搭你的列車，就會開航。目前最多的一天：320／800 人。"
        )
        // Hong Kong has no route to Tokyo: a game there opens only Taiwan.
        routes.opened = [hongKong]
        routes.here = hongKong
        XCTAssertEqual(routes.earned(in: try hongKongWorld(riders: 9_000)), [.taiwan])
        // Songshan's row counts towards Tokyo by Tokyo's own count.
        routes.opened = [taiwan]
        routes.here = taiwan
        let songshan = try XCTUnwrap(try taiwanWorld("Taipei Songshan Airport", riders: 40).airportDays().first { $0.airport.englishName == "Taipei Songshan Airport" })
        XCTAssertEqual(songshan.airRouteText(in: .traditionalChinese, routes: routes), "東京航線：昨天 40／800 人搭你的列車，一天滿 800 人就開航，可以到東京經營。")
    }

    // MARK: - The picker's row

    /// A closed map's row says from where and how many, in both languages,
    /// and the best day once there is one.
    func testAClosedMapsRowSaysWhatOpensIt() {
        XCTAssertEqual(
            fromTaiwan.howToOpen(hongKong, in: .traditionalChinese),
            "還沒開航。在台灣的地圖上，讓一座飛香港的機場一天有 500 人搭你的列車，就會開航。"
        )
        XCTAssertEqual(
            fromHongKong.howToOpen(taiwan, in: .traditionalChinese),
            "還沒開航。在香港的地圖上，讓一座飛台灣的機場一天有 500 人搭你的列車，就會開航。"
        )
        var some = fromHongKong
        some.best = [taiwan: 1_234]
        XCTAssertEqual(
            some.howToOpen(taiwan, in: .english),
            "Not open yet. On a map of Hong Kong, carry 500 passengers in one day to or from an airport that flies to Taiwan, and its flights open this map. Best day so far: 1,234 of 500."
        )
    }

    // MARK: - The airport's row

    /// The row of an airport that flies there says how far yesterday was,
    /// then that the flights are open; other airports' rows say nothing,
    /// and none does while the app offers no city.
    func testTheAirportsRowSaysHowFar() throws {
        let world = try taiwanWorld("Kaohsiung International Airport", riders: 320)
        let days = world.airportDays()
        let kaohsiung = try XCTUnwrap(days.first { $0.airport.englishName == "Kaohsiung International Airport" })
        let songshan = try XCTUnwrap(days.first { $0.airport.englishName == "Taipei Songshan Airport" })
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .traditionalChinese, routes: fromTaiwan),
            "香港航線：昨天 320／500 人搭你的列車，一天滿 500 人就開航，可以到香港經營。"
        )
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .english, routes: fromTaiwan),
            "Hong Kong flights: 320 of 500 rode your trains yesterday. Reach 500 in a day to open the Hong Kong map."
        )
        XCTAssertEqual(
            kaohsiung.airRouteText(in: .traditionalChinese, routes: AirRoutes(cities: [.hongKong], opened: [taiwan, hongKong])),
            "香港航線已開航。回開始畫面按「新遊戲」→「實景地圖」，清單最上面就有「香港」。"
        )
        XCTAssertNil(songshan.airRouteText(in: .traditionalChinese, routes: fromTaiwan))
        XCTAssertNil(kaohsiung.airRouteText(in: .traditionalChinese, routes: AirRoutes()))
        // Hong Kong's airport, in a game there.
        let airport = try XCTUnwrap(try hongKongWorld(riders: 77).airportDays().first)
        XCTAssertEqual(airport.airRouteText(in: .traditionalChinese, routes: fromHongKong), "台灣航線：昨天 77／500 人搭你的列車，一天滿 500 人就開航，可以到台灣經營。")
    }

    // MARK: - The launcher

    /// A player from before the maps were chosen began in Taiwan: the
    /// launcher keeps the city's map closed, with the way to open it; a
    /// game whose airport had its riders opens it, says so once in the
    /// status line and the news, and the device remembers, with the best
    /// day before that.
    func testTheLauncherOpensTheCityAndRemembers() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var before = LauncherPreferences()
        before.hasLaunched = true
        before.write(to: directory.appendingPathComponent(GameLauncher.preferencesFileName))
        let launcher = await launcher(in: directory)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan"])
        XCTAssertEqual(launcher.airRoutes, fromTaiwan)
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
        XCTAssertEqual(launcher.message?.text, fromTaiwan.howToOpen(hongKong, in: .traditionalChinese))
        XCTAssertNil(launcher.session)

        let short = GameSession(world: try taiwanWorld("Kaohsiung International Airport", riders: 499), language: .traditionalChinese)
        launcher.checkAirRoutes(of: short)
        XCTAssertEqual(short.airRoutes.opened, [taiwan])
        XCTAssertNil(short.message)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan"])
        XCTAssertEqual(launcher.preferences.airRouteBest, ["hongKong": 499])
        XCTAssertTrue(launcher.airRoutes.howToOpen(hongKong, in: .traditionalChinese).hasSuffix("目前最多的一天：499／500 人。"))

        let session = GameSession(world: try taiwanWorld("Kaohsiung International Airport", riders: 500), language: .traditionalChinese)
        launcher.checkAirRoutes(of: session)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan", "hongKong"])
        XCTAssertEqual(session.airRoutes.opened, [taiwan, hongKong])
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.message?.text, "台灣↔香港開航了。回開始畫面按「新遊戲」→「實景地圖」，清單最上面就有「香港」。")
        XCTAssertEqual(session.news.items.filter { $0.category == .achievement }.count, 1)
        // The next midnight says nothing more.
        session.message = nil
        launcher.checkAirRoutes(of: session)
        XCTAssertNil(session.message)
        XCTAssertEqual(session.news.items.filter { $0.category == .achievement }.count, 1)

        // The next launch has it open, and starts the city's map.
        let next = await self.launcher(in: directory)
        XCTAssertEqual(next.airRoutes.opened, [taiwan, hongKong])
        XCTAssertTrue(next.startOverseasMap(.hongKong), next.message?.text ?? "")
        XCTAssertEqual(next.session?.airRoutes.opened, [taiwan, hongKong])
        XCTAssertEqual(next.session?.airRoutes.here, hongKong)
    }

    /// A player who opened Hong Kong in the build before keeps it, with
    /// Taiwan.
    func testAPlayerOfTheBuildBeforeKeepsBoth() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var before = LauncherPreferences()
        before.hasLaunched = true
        before.airRoutesOpened = ["hongKong"]
        before.write(to: directory.appendingPathComponent(GameLauncher.preferencesFileName))
        let launcher = await launcher(in: directory)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan", "hongKong"])
    }

    /// A new player chooses the first map: Hong Kong can be it. Taiwan is
    /// then closed, its whole map and its places, until Hong Kong's
    /// airport had its riders; the next launch still knows.
    func testANewPlayerCanBeginInHongKong() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, [])
        XCTAssertTrue(launcher.airRoutes.canStart(taiwan) && launcher.airRoutes.canStart(hongKong))
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["hongKong"])
        XCTAssertEqual(launcher.session?.airRoutes.here, hongKong)
        let first = try XCTUnwrap(launcher.session)

        let again = await self.launcher(in: directory)
        XCTAssertEqual(again.airRoutes.opened, [hongKong])
        again.startWholeTaiwan()
        XCTAssertNil(again.session)
        XCTAssertEqual(again.message?.text, "還沒開航。在香港的地圖上，讓一座飛台灣的機場一天有 500 人搭你的列車，就會開航。")
        again.startNewGame(at: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        XCTAssertNil(again.session)
        XCTAssertNil(again.openRealWorldGame(at: try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6273, longitudeDegrees: 120.3014))))
        XCTAssertNil(again.session)

        var world = first.world
        world.airports[0].yesterdayRiders = 640
        let session = GameSession(world: world, language: .traditionalChinese)
        again.checkAirRoutes(of: session)
        XCTAssertEqual(again.preferences.airRoutesOpened, ["hongKong", "taiwan"])
        XCTAssertEqual(session.message?.text, "香港↔台灣開航了。回開始畫面按「新遊戲」→「實景地圖」，清單最上面就有「全台灣」。")
        again.startWholeTaiwan()
        XCTAssertEqual(again.session?.airRoutes.here, taiwan)
    }

    /// And Taiwan first closes Hong Kong, as before.
    func testANewPlayerWhoBeginsInTaiwan() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.startWholeTaiwan()
        XCTAssertNotNil(launcher.session)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan"])
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
    }

    /// A demo's trains are not the player's: its riders open nothing. The
    /// demo mode has every map open without remembering any.
    func testADemoOpensNothingAndTheDemoModeHasAllOpen() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.rememberAirRoutes([taiwan])
        let demo = GameSession(world: try taiwanWorld("Kaohsiung International Airport", riders: 5_000), language: .english)
        demo.news.isDemo = true
        launcher.checkAirRoutes(of: demo)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan"])
        XCTAssertNil(launcher.preferences.airRouteBest)
        XCTAssertNil(demo.message)

        launcher.isDemoMode = true
        XCTAssertEqual(launcher.airRoutes.opened, [taiwan, hongKong])
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertEqual(launcher.preferences.airRoutesOpened, ["taiwan"])
        launcher.isDemoMode = false
        XCTAssertEqual(launcher.airRoutes.opened, [taiwan])
    }

    /// While the app reads no city (``OverseasMaps/open`` empty) nothing is
    /// offered: no game says anything of flights to open, whatever its
    /// airports carried, a game the launcher starts is told so, and
    /// Taiwan starts as it always did.
    func testNothingIsOfferedWhileNoCityIsRead() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory, overseas: OverseasMaps.open.subtracting([.hongKong]))
        XCTAssertEqual(launcher.airRoutes, AirRoutes())
        let session = GameSession(world: try taiwanWorld("Kaohsiung International Airport", riders: 5_000), language: .english)
        launcher.checkAirRoutes(of: session)
        XCTAssertNil(session.message)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, [])
        XCTAssertNil(session.world.airportDays().first { $0.airport.flies(to: .hongKong) }?.airRouteText(in: .english, routes: session.airRoutes))
        launcher.startWholeTaiwan()
        XCTAssertNotNil(launcher.session)
        XCTAssertEqual(launcher.preferences.airRoutesOpened, [])
    }

    /// A game the launcher starts knows what is offered, so its airports'
    /// rows show how far they are.
    func testAGameBegunKnowsWhatIsOffered() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.startWholeTaiwan()
        XCTAssertEqual(launcher.session?.airRoutes, fromTaiwan)
    }

    /// Preferences written before the flights read as none opened, and
    /// the list is kept in the file.
    func testThePreferencesKeepTheOpenedMaps() throws {
        let before = try JSONEncoder().encode(LauncherPreferences())
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("air"))
        XCTAssertNil(try JSONDecoder().decode(LauncherPreferences.self, from: before).airRoutesOpened)
        var preferences = LauncherPreferences()
        preferences.airRoutesOpened = ["hongKong", "taiwan"]
        preferences.airRouteBest = ["taiwan": 120]
        let read = try JSONDecoder().decode(LauncherPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(read.airRoutesOpened, ["hongKong", "taiwan"])
        XCTAssertEqual(read.airRouteBest, ["taiwan": 120])
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
