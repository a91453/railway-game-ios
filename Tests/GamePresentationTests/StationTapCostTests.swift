import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// CRASH-STATION (a player's report, 118.1, iPhone 15 Pro Max: "it crashes
/// as soon as I tap a station"): what a tap on a station and its panel read
/// from the world, timed per station on a large real network.
@MainActor
final class StationTapCostTests: XCTestCase {
    /// The demo with a sight at each of its first stations, which bring
    /// tourists: the pairs and a line's trace worked out on their own
    /// (decision 644) are those the ridership's one pass gives.
    func testThePairsAndALinesTraceAreTheRiderships() throws {
        var world = DemoWorld.make(in: .english)
        world.setTourism(world.stations.prefix(3).enumerated().map { index, station in
            Attraction(id: AttractionID(rawValue: index + 1), name: "景點\(index)", englishName: "Sight \(index)",
                       point: PlanPoint(x: station.location.x + 300, y: station.location.y), kind: .town, baseStars: 300)
        })
        for mode in [PassengerRoutingMode.network, .direct] {
            world.setPassengerRoutingMode(mode)
            var linked = 0
            for station in world.stations {
                let pairs = world.stationRidership(of: station.id).pairs
                XCTAssertEqual(world.stationDemandPairs(of: station.id), pairs, "\(mode) \(station.name)")
                XCTAssertEqual(world.journeyTrace(of: station.id), JourneyTrace(station: station.id, pairs: pairs), "\(mode) \(station.name)")
                if !pairs.isEmpty { linked += 1 }
            }
            XCTAssertGreaterThan(linked, 2, "the demo's stations exchange trips (\(mode))")
            for line in world.lines {
                // The trace as it was worked out: each stop's pairs from its ridership.
                var stops: [StationID] = []
                for stop in line.stops where !stops.contains(stop) { stops.append(stop) }
                var pairs: [(from: StationID, pair: StationDemandPair)] = []
                for (index, stop) in stops.enumerated() {
                    let later = Set(stops.dropFirst(index + 1))
                    pairs += world.stationRidership(of: stop).pairs.filter { later.contains($0.station) }.map { (from: stop, pair: $0) }
                }
                XCTAssertEqual(world.journeyTrace(ofLine: line.id), JourneyTrace(line: line.id, pairs: pairs), "\(mode) \(line.name)")
            }
        }
    }

    /// What the station panel's ridership and the map's journey traces
    /// cost on Taipei with the Wenhu Line bought, each station's pairs
    /// faster than its ridership. Runs only on request:
    ///
    ///     STATION_COST_REPORT=1 swift test --skip-build --filter StationTapCostTests/testWhatTheTracesCostOnTaipei
    func testWhatTheTracesCostOnTaipei() throws {
        guard ProcessInfo.processInfo.environment["STATION_COST_REPORT"] != nil else {
            throw XCTSkip("set STATION_COST_REPORT=1 to measure the journey traces on Taipei")
        }
        let world = try Self.taipei(lines: ["trtc:BR"]).world
        let clock = ContinuousClock()
        let station = try XCTUnwrap(world.stations.first { $0.name == "南京復興" })
        let ridership = clock.measure { _ = world.stationRidership(of: station.id) }
        let trace = clock.measure { _ = world.journeyTrace(of: station.id) }
        let line = try XCTUnwrap(world.lines.first)
        let lineTrace = clock.measure { _ = world.journeyTrace(ofLine: line.id) }
        print("[STATION-COST] \(station.name): ridership \(ridership), its trace \(trace); \(line.name) (\(line.stops.count) stops): its trace \(lineTrace)")
        XCTAssertLessThan(trace, ridership * 0.75, "the trace no longer shares the pairs among the hours")
        XCTAssertLessThan(lineTrace, ridership * 2, "a line's trace reads each station's day once")
    }

    /// Runs only on request:
    ///
    ///     STATION_COST_REPORT=1 swift test --skip-build --filter StationTapCostTests
    func testWhatATapOnAStationCostsOnTaipei() throws {
        guard ProcessInfo.processInfo.environment["STATION_COST_REPORT"] != nil else {
            throw XCTSkip("set STATION_COST_REPORT=1 to measure a station tap on Taipei")
        }
        let session = try Self.taipei(lines: ProcessInfo.processInfo.environment["STATION_COST_LINES"]?.split(separator: ",").map(String.init) ?? ["trtc:BR"])
        report(session)
    }

    /// The same on decision 421's test game, Taipei with `STATION_COST_BENCH`
    /// lines (20 by default) of the player's own:
    ///
    ///     STATION_COST_REPORT=1 swift test --skip-build --filter StationTapCostTests/testWhatATapOnAStationCostsWithManyLines
    func testWhatATapOnAStationCostsWithManyLines() async throws {
        guard ProcessInfo.processInfo.environment["STATION_COST_REPORT"] != nil else {
            throw XCTSkip("set STATION_COST_REPORT=1 to measure a station tap with many lines")
        }
        let count = Int(ProcessInfo.processInfo.environment["STATION_COST_BENCH"] ?? "") ?? 20
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StationTapCostTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData { Map3DOpenEveryStartTests.data }.value
        let opened = await launcher.openFrameTimeBench(lines: count)
        let session = try XCTUnwrap(opened)
        session.setSpeed(.x1)
        session.advance(ticks: 600)
        report(session)
    }

    private func report(_ session: GameSession) {
        let world = session.world
        let clock = ContinuousClock()
        var worst: [String: (Duration, String)] = [:]
        func time(_ name: String, _ station: Station, _ body: () -> Void) {
            let spent = clock.measure(body)
            if spent > (worst[name]?.0 ?? .zero) { worst[name] = (spent, station.name) }
        }
        let language = DisplayLanguage.traditionalChinese
        for station in world.stations {
            session.selectStation(station.id)
            time("tag", station) { _ = StationTag(world: world, station: station.id) }
            time("selectionText", station) { _ = session.selectionText() }
            time("operations", station) { _ = StationOperations(world: world, station: station.id, use: session.platformUse) }
            time("departureBoard", station) { _ = DepartureBoard(world: world, station: station.id) }
            time("ridership", station) { _ = world.stationRidership(of: station.id) }
            time("modeShift", station) { _ = world.stationModeShift(of: station.id) }
            time("menu", station) { _ = session.stationMenuChoices; _ = session.transferMenuChoices(for: station.id) }
            time("stamp", station) { _ = session.stationStampStatus(of: station.id) }
            time("expansion", station) { _ = session.stationExpansionCard(of: station.id) }
            time("crossover", station) { _ = session.stationCrossoverOffer(for: station.id) }
            time("commerce", station) { _ = session.stationCommerceCard(of: station.id) }
            time("catchment", station) { _ = session.stationCatchmentPopulation(of: station.id) }
            time("depot", station) { _ = session.selectedStationDepotSwitch }
            time("realDetails", station) { _ = session.realStationDetails(of: station.id) }
            time("buyable", station) { _ = session.buyableRealLine(at: station.id) }
            time("ownTrackHelp", station) { _ = session.ownTrackPlatformHelp(for: station) }
            time("platformMenus", station) {
                for platform in world.trackPlatforms(of: station.id) { _ = session.platformTrackMenuChoices(beside: platform) }
            }
            time("texts", station) {
                _ = world.weatherTexts(at: station.id, in: language)
                _ = world.waitingBreakdown(at: station.id, in: language)
                _ = world.transferGroupText(of: station.id)
                _ = world.townGrowthText(of: station.id, in: language)
                _ = world.stationFlowText(at: station.id, in: language)
                _ = world.passengerLedgerRows(of: station.id, in: language)
                _ = world.landCatchmentText(of: station.id, in: language)
                _ = world.demandEventTexts(at: station.id, in: language)
                _ = world.crowdedStationNote(at: station.id, in: language)
                _ = world.cityGrowthText(of: station.id, in: language)
                _ = world.catchmentLandValueText(of: station.id, in: language)
                _ = world.catchmentBuildingsText(of: station.id, in: language)
            }
            time("roadOffer", station) { _ = world.stationRoadOffer(of: station.id, in: language) }
            time("busCards", station) { _ = world.busRouteCards(feeding: station.id, in: language) }
        }
        let report = worst.sorted { $0.value.0 > $1.value.0 }.map { "\($0.key) \($0.value.0) (\($0.value.1))" }
        print("[STATION-COST] \(world.stations.count) stations, \(world.lines.count) lines, \(world.trains.count) trains:\n  " + report.joined(separator: "\n  "))
    }

    /// Taipei with `lines` (real line IDs) bought, a game minute run.
    static func taipei(lines: [String]) throws -> GameSession {
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.metroRuns["trtc:BR"])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "mrt") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var opened = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(200_000_000_000), land: [])
        opened.setLandOnDemand()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let session = GameSession(world: opened, language: .traditionalChinese)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        for id in lines {
            guard let line = session.buyableRealLines.first(where: { $0.id == id }) else {
                print("[STATION-COST] \(id) is not on sale: \(session.buyableRealLines.map(\.id))")
                continue
            }
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        }
        session.setSpeed(.x1)
        session.advance(ticks: 600)
        return session
    }
}
