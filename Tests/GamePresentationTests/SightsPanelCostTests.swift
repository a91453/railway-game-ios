import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// CRASH-SIGHTS (a player's report, 115.1: "it keeps jumping to the
/// sights and crashing"): the sights panel read the world, so it worked
/// its rows out again at every tick while it stayed open, and each row
/// built the day's whole network to ask whether tourists can ride to its
/// sight. On Taipei with the Wenhu Line bought, one row took a tenth of a
/// second on Linux (more than a tick at speed); a network serving more
/// sights took seconds, and the game froze until the system closed it.
@MainActor
final class SightsPanelCostTests: XCTestCase {
    /// Home and Foot with a train, the panel's sight by Foot, one by Home,
    /// and one some 6 km away that no station serves; on the network router, as a real map
    /// plays.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 7)
        world.setTourism(nil)
        world.setCityRequests(seed: nil)
        world.setLandDemand(false)
        world.setPassengerRoutingMode(.network)
        world.setDistanceDemand(false)
        world.setOutsideConnections(true)
        let home = try world.buildStation(named: "Home", at: PlanPoint(x: 20_000, y: 500_000)).id
        let foot = try world.buildStation(named: "Foot", at: PlanPoint(x: 26_000, y: 500_000)).id
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "老街", englishName: "Old Street",
                       point: PlanPoint(x: 27_000, y: 500_000), kind: .town, baseStars: 350),
            Attraction(id: AttractionID(rawValue: 2), name: "海邊", englishName: "Beach",
                       point: PlanPoint(x: 27_000, y: 100_000), kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 3), name: "廟", englishName: "Temple",
                       point: PlanPoint(x: 21_000, y: 500_000), kind: .town, baseStars: 250),
        ])
        return world
    }

    /// The statuses worked out together are each sight's own.
    func testTheStatusesTogetherAreEachSightsOwn() throws {
        for mode in [PassengerRoutingMode.network, .direct] {
            var world = try world()
            world.setPassengerRoutingMode(mode)
            let together = world.attractionStatuses()
            let sights = try XCTUnwrap(world.tourism?.attractions)
            XCTAssertEqual(together.count, sights.count)
            for sight in sights {
                XCTAssertEqual(together[sight.id], world.attractionStatus(of: sight.id), "\(sight.englishName) \(mode)")
            }
            XCTAssertEqual(together[AttractionID(rawValue: 2)], .noStation, "\(mode)")
            if mode == .direct { XCTAssertEqual(together[AttractionID(rawValue: 1)], .ok) }
            XCTAssertEqual(world.attractionRows(in: .english).map(\.status), sights.sorted { $0.stars > $1.stars }.map { world.attractionStatus(of: $0.id) })
        }
    }

    /// The panel's rows are worked out once a day, and again after a
    /// command, not at every tick (the panel's body runs at every tick).
    func testThePanelsRowsAreNotWorkedOutAtEveryTick() throws {
        let session = GameSession(world: try world(), language: .english)
        // Ten game minutes a tick.
        session.setSpeed(.fast)
        let first = session.sightsPanelRows
        XCTAssertEqual(first.map(\.name), ["Old Street", "Beach", "Temple"])
        XCTAssertEqual(session.sightRowsWorkedOut, 1)
        // The rest of this day.
        let day = session.world.clock.now.seconds / GameTime.secondsPerDay
        var ticks = 0
        while true {
            session.advance(ticks: 1)
            ticks += 1
            guard session.world.clock.now.seconds / GameTime.secondsPerDay == day else { break }
            XCTAssertEqual(session.sightsPanelRows, first)
            XCTAssertLessThan(ticks, 145)
        }
        XCTAssertGreaterThan(ticks, 1)
        XCTAssertEqual(session.sightRowsWorkedOut, 1, "none again within the day (\(ticks) ticks)")
        // The next day, once.
        _ = session.sightsPanelRows
        _ = session.sightsPanelRows
        XCTAssertEqual(session.sightRowsWorkedOut, 2, "once on the next day")
        // A command: the shop's level shows at once.
        session.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertEqual(session.sightsPanelRows.first { $0.id == AttractionID(rawValue: 1) }?.souvenir, 1)
        XCTAssertEqual(session.sightRowsWorkedOut, 3)
    }

    /// What the panel's rows cost on Taipei with the Wenhu Line bought,
    /// each sight's status asked alone (as before) and together. Runs only
    /// on request:
    ///
    ///     SIGHTS_COST_REPORT=1 swift test --skip-build --filter SightsPanelCostTests
    func testWhatTheRowsCostOnTaipei() throws {
        guard ProcessInfo.processInfo.environment["SIGHTS_COST_REPORT"] != nil else {
            throw XCTSkip("set SIGHTS_COST_REPORT=1 to measure the sights panel on Taipei")
        }
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.metroRuns["trtc:BR"])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "mrt") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var opened = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(200_000_000_000), land: [])
        opened.setLandOnDemand()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let session = GameSession(world: opened, language: .english)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        let wenhu = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: wenhu)), session.message?.text ?? "")
        // A game minute at real time.
        session.setSpeed(.x1)
        var world = session.world
        try world.advance(ticks: 600)
        // As a network reaching more sights: 15 more by the one reached.
        var sights = try XCTUnwrap(world.tourism?.attractions)
        let reached = try XCTUnwrap(sights.first { world.attractionStatus(of: $0.id) == .ok })
        let top = sights.map(\.id.rawValue).max() ?? 0
        sights += (1...15).map { index in
            Attraction(id: AttractionID(rawValue: top + index), name: "\(reached.name)\(index)", englishName: "\(reached.englishName) \(index)",
                       point: PlanPoint(x: reached.point.x + Int64(index) * 64, y: reached.point.y), kind: reached.kind, baseStars: reached.baseStars)
        }
        world.setTourism(sights)
        let clock = ContinuousClock()
        var alone: [AttractionID: AttractionStatus] = [:]
        let aloneTime = clock.measure { for sight in sights { alone[sight.id] = world.attractionStatus(of: sight.id) } }
        var together: [AttractionID: AttractionStatus] = [:]
        let togetherTime = clock.measure { together = world.attractionStatuses() }
        let rowsTime = clock.measure { _ = world.attractionRows(in: .english) }
        XCTAssertEqual(alone, together)
        print("""
        [SIGHTS] \(world.passengerRoutingMode), \(sights.count) sights, \(alone.values.filter { $0 == .ok }.count) reached, \
        \(world.stations.count) stations: each alone \(aloneTime), together \(togetherTime), the panel's rows \(rowsTime)
        """)
    }
}
