import Foundation
import GameCore
import GamePresentation
import XCTest

/// The city's requests where the app meets them (ARCHITECTURE decision 183):
/// a new free game has them, the measured worlds do not, the goals panel's
/// rows and buttons, and the station master's announcement.
@MainActor
final class CityRequestsSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CityRequestsSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewFreeGameHasThem() throws {
        let world = GameWorld.newGame(eventSeed: 7)
        let requests = try XCTUnwrap(world.cityRequests)
        XCTAssertEqual(requests.seed, 7)
        XCTAssertEqual(requests.trust, 1)
        // A blank map's towns and sights have no station yet: the biggest
        // town is asked for, and tourists for a sight.
        XCTAssertEqual(Set(requests.offers.map(\.kind)), [.newStation, .tourism])
        XCTAssertTrue(world.hasCityRequests)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.hasCityRequests, true)
    }

    func testTheMeasuredWorldsKeepThemOff() {
        XCTAssertNil(DemoWorld.make(in: .english).cityRequests)
        for challenge in Challenge.sandbox {
            XCTAssertNil(GameWorld.newGame(challenge: challenge, eventSeed: 7).cityRequests, challenge.id)
        }
        XCTAssertNil(LiuMingchuanChallenge.make().cityRequests)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertNil(launcher.session?.world.cityRequests)
    }

    /// A new game with two stations and a line with a train, Home with
    /// 1,500 trips a day: the city asks for more riders there.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 7)
        world.setCityRequests(seed: nil)
        world.setTourism(nil)
        world.setLandDemand(false)
        let home = try world.buildStation(named: "Home", at: PlanPoint(x: 20_000, y: 500_000)).id
        let work = try world.buildStation(named: "Work", at: PlanPoint(x: 120_000, y: 500_000)).id
        let line = try world.createLine(named: "Main", stops: [home, work]).id
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(work, to: StationDemand(kind: .office, dailyTrips: 100))
        world.setCityRequests(seed: 7)
        return world
    }

    func testTheRowsSayWhatIsAskedAndWhatItPays() throws {
        let world = try world()
        let row = try XCTUnwrap(world.cityRequestRows(in: .english).first { $0.kind == .stationRiders })
        XCTAssertEqual(row.title, "More riders at Home")
        XCTAssertEqual(row.detail, "From 1500 to 2100 planned trips a day within 60 days.")
        XCTAssertEqual(row.reward, Money(20_000_000))
        XCTAssertFalse(row.isActive)
        XCTAssertEqual(row.progressText, "1500 / 2100 trips a day")
        XCTAssertEqual(row.daysLeft, 30, "open until the next month's offers")
        XCTAssertEqual(row.location, PlanPoint(x: 20_000, y: 500_000))
        let chinese = try XCTUnwrap(world.cityRequestRows(in: .traditionalChinese).first { $0.id == row.id })
        XCTAssertEqual(chinese.title, "Home站運量提升")
        XCTAssertEqual(world.cityTrustText(in: .traditionalChinese), "城市信賴度 ★☆☆☆☆ · 進行中 0 / 1 件")
        XCTAssertEqual(world.citySubsidyText(in: .english), "Subsidies so far $ 0")
    }

    func testTheButtonsTakeOnAndTurnDown() throws {
        let session = GameSession(world: try world())
        let offers = try XCTUnwrap(session.world.cityRequests?.offers)
        let first = try XCTUnwrap(offers.first)
        session.acceptRequest(first.id)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.cityRequests?.active.map(\.id), [first.id])
        let row = try XCTUnwrap(session.world.cityRequestRows(in: .english).first { $0.id == first.id })
        XCTAssertTrue(row.isActive)
        XCTAssertEqual(row.daysLeft, first.days)
        session.declineRequest(first.id)
        XCTAssertEqual(session.world.cityRequests?.trust, 0, "giving one up costs a star")
        XCTAssertEqual(session.world.cityRequestResults(in: .english).map(\.succeeded), [false])
    }

    func testTheStationMasterAnnouncesTheMonthsOffers() throws {
        let world = try world()
        let advice = try XCTUnwrap(StationMasterAdvice(world: world))
        guard case .newCityRequests(let month, let count, let reward, let target) = advice else { return XCTFail("\(advice)") }
        XCTAssertEqual(month, 0)
        XCTAssertEqual(count, world.cityRequests?.offers.count)
        XCTAssertEqual(reward, world.cityRequests?.offers.map(\.reward).max())
        XCTAssertNotNil(target)
        XCTAssertFalse(advice.isWorry)
        XCTAssertTrue(advice.text(in: .traditionalChinese).hasPrefix("城市提出"), advice.text(in: .traditionalChinese))
        // Not once the company's hands are full.
        var full = world
        try full.acceptRequest(try XCTUnwrap(world.cityRequests?.offers.first).id)
        if case .newCityRequests? = StationMasterAdvice(world: full) { XCTFail("no room for another") }
    }
}

extension CityRequestsSessionTests {
    /// A station named "…站" (or one removed, "已拆除的車站") is not
    /// called "…站站".
    func testAStationNamedWithItsOwnStationIsNotSaidTwice() throws {
        var world = try world()
        let row = try XCTUnwrap(world.cityRequestRows(in: .english).first { $0.kind == .stationRiders })
        try world.renameStation(StationID(rawValue: 1), to: "家站")
        let chinese = try XCTUnwrap(world.cityRequestRows(in: .traditionalChinese).first { $0.id == row.id })
        XCTAssertEqual(chinese.title, "家站運量提升")
    }
}
