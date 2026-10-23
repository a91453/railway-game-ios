import Foundation
import GameCore
import Observation
@testable import GamePresentation
import XCTest

/// Decision 367 (§22.2 25a; TestFlight 83.1, iPhone 17 Pro, the whole
/// High Speed Rail at 600×: 5 fps, the longest frame 202 ms of which 200 ms
/// "other", SwiftUI working the views out again): what the screen reads of
/// the session the FIRST time after each tick, the map open and nothing
/// selected. Each read after a tick is timed once, as SwiftUI asks for it
/// once a render; reading it twenty times in a row, as
/// ``LongGameCostReportTests`` does, timed a memo nineteen times. Run on
/// request:
///
///     FAST_FORWARD_READS=50 swift test -c release -Xswiftc -enable-testing \
///       --filter FastForwardReadsReportTests
///
/// `FAST_FORWARD_SPEED=6000` runs it at 6000× (decision 377).
@MainActor
final class FastForwardReadsReportTests: XCTestCase {
    func testWhatTheScreenReadsAfterEachTickOnTheHighSpeedRail() throws {
        guard let value = ProcessInfo.processInfo.environment["FAST_FORWARD_READS"] else {
            throw XCTSkip("set FAST_FORWARD_READS=<ticks> to time what the screen reads after each tick")
        }
        let ticks = try XCTUnwrap(Int(value).flatMap { (1...10_000).contains($0) ? $0 : nil }, "FAST_FORWARD_READS is 1 to 10,000 ticks")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let world = try HighSpeedDemo.make(
            in: .traditionalChinese, railways: railways, population: data.population, places: data.places, water: data.water, coverage: data.coverage
        )
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.coverage = data.coverage
        session.railways = railways
        // Decision 377: `FAST_FORWARD_SPEED=6000` for 6000×, as TestFlight
        // 84.1 was read at.
        let fast = ProcessInfo.processInfo.environment["FAST_FORWARD_SPEED"] == "6000"
        session.setSpeed(fast ? .fast : .normal)
        let reads = Self.reads(of: session)
        let clock = ContinuousClock()
        var total: [String: Duration] = [:], longest: [String: Duration] = [:]
        var stepped = Duration.zero
        for _ in 0..<ticks {
            stepped += clock.measure { session.advance(realElapsed: GameSession.tickInterval) }
            for (label, read) in reads {
                let spent = clock.measure { read() }
                total[label, default: .zero] += spent
                longest[label] = max(longest[label] ?? .zero, spent)
            }
        }
        let all = total.values.reduce(Duration.zero, +)
        var rows = [
            "sights \(session.world.tourism?.attractions.count ?? 0), sight marks shown \(session.sightMarksTakeTouches), stations \(session.world.stations.count), trains \(session.world.trains.count), lines \(session.world.lines.count), at \(session.world.clock.now.seconds / 60 % 1_440) min, \(ticks) ticks at \(fast ? "6000" : "600")×",
            "session.advance (GameCore and after), a tick: \(LongGameCostReportTests.ms(stepped, per: ticks)) ms",
            "every read below, a tick: \(LongGameCostReportTests.ms(all, per: ticks)) ms",
            "",
            "| First read after a tick | ms a tick | longest ms |", "| --- | --: | --: |",
        ]
        for (label, spent) in total.sorted(by: { $0.value > $1.value }) {
            rows.append("| \(label) | \(LongGameCostReportTests.ms(spent, per: ticks)) | \(LongGameCostReportTests.ms(longest[label] ?? .zero)) |")
        }
        rows += ["", "| Decision 377: told to look again, of \(ticks) more ticks | before | now |", "| --- | --: | --: |"]
        rows += Self.lookAgain(over: ticks, session).map { "| \($0.label) | \($0.before) | \($0.now) |" }
        print(rows.joined(separator: "\n"))
    }

    /// Decision 377: how many of `ticks` ticks change what each view read
    /// of the session before decision 377 and what it reads now (a change
    /// tells SwiftUI to work the view out again).
    static func lookAgain(over ticks: Int, _ session: GameSession) -> [(label: String, before: Int, now: Int)] {
        let views: [(String, before: () -> Void, now: () -> Void)] = [
            ("MapAlertBubbles", { _ = session.world.mapAlerts() + session.situationAlerts }, { _ = session.mapBubbles }),
            ("MapAttractionMarks", {
                for sight in session.world.tourism?.attractions ?? [] { _ = session.world.stars(of: sight) }
            }, { _ = session.mapSights }),
            ("StationMasterView's stationMasterRefreshKey", { _ = session.world.clock.now.seconds / GameTime.secondsPerHour }, {
                _ = session.stationMasterRefreshKey
            }),
            ("HUDView (round its four layouts)", {
                _ = session.world.economy.balance
                _ = session.world.scenario
                _ = session.world.hasTourism
            }, {
                _ = session.screenFacts
                _ = session.language
            }),
        ]
        final class Flag: @unchecked Sendable { var raised = false }
        var counts = views.map { _ in (before: 0, now: 0) }
        for _ in 0..<ticks {
            let flags = views.map { _ in (before: Flag(), now: Flag()) }
            for (index, view) in views.enumerated() {
                withObservationTracking(view.before) { flags[index].before.raised = true }
                withObservationTracking(view.now) { flags[index].now.raised = true }
            }
            session.advance(realElapsed: GameSession.tickInterval)
            for index in views.indices {
                if flags[index].before.raised { counts[index].before += 1 }
                if flags[index].now.raised { counts[index].now += 1 }
            }
        }
        return views.indices.map { (views[$0].0, counts[$0].before, counts[$0].now) }
    }

    /// What the always-shown views read of the session in their bodies.
    static func reads(of session: GameSession) -> [(String, () -> Void)] {
        [
            ("nextSteps", { _ = session.nextSteps }),
            ("trafficOverlay", { _ = session.trafficOverlay }),
            ("situationAlerts", { _ = session.situationAlerts }),
            ("cityRequestMarks", { _ = session.cityRequestMarks }),
            ("mapStopSuggestion", { _ = session.mapStopSuggestion }),
            ("realStationSuggestions", { _ = session.realStationSuggestions }),
            ("offersRealStations", { _ = session.offersRealStations }),
            ("buyableRealLines", { _ = session.buyableRealLines }),
            ("realLinesForSaleNote", { _ = session.realLinesForSaleNote }),
            ("hasCityRequestOffers", { _ = session.hasCityRequestOffers }),
            ("world.hasCityRequests", { _ = session.world.hasCityRequests }),
            ("cityRequestsButtonValue", { _ = session.cityRequestsButtonValue }),
            ("worstLosingLine", { _ = session.worstLosingLine }),
            ("stationMasterRefreshKey", { _ = session.stationMasterRefreshKey }),
            ("offersCoverageShortcut", { _ = session.offersCoverageShortcut }),
            ("mapExpansionOverlay", { _ = session.mapExpansionOverlay }),
            ("showsMapExpansionButton", { _ = session.showsMapExpansionButton }),
            ("isFreePlayLocked", { _ = session.isFreePlayLocked }),
            ("runsLinesForThePlayer", { _ = session.runsLinesForThePlayer }),
            ("selectionText()", { _ = session.selectionText() }),
            ("lineMenuChoices", { _ = session.lineMenuChoices }),
            ("trainMenuChoices", { _ = session.trainMenuChoices }),
            ("stationMenuChoices", { _ = session.stationMenuChoices }),
            ("viewingSpeed", { _ = session.viewingSpeed }),
            ("speedChoices", { _ = session.speedChoices }),
            ("nightSkip", { _ = session.nightSkip }),
            ("networkOverlay", { _ = session.networkOverlay }),
            ("buildingOverlay", { _ = session.buildingOverlay }),
            ("routePreview", { _ = session.routePreview }),
            ("showsSightsButton", { _ = session.showsSightsButton }),
            ("world.hasTourism", { _ = session.world.hasTourism }),
            ("showsFreight", { _ = session.showsFreight }),
            ("watchedTrainIDs", { _ = session.watchedTrainIDs }),
            ("traceableRealLines", { _ = session.traceableRealLines }),
            ("canLayDemoRealLines", { _ = session.canLayDemoRealLines }),
            ("world.todaySymbol()", { _ = session.world.todaySymbol() }),
            ("world.forecast()", { _ = session.world.forecast() }),
            ("MapLayers.waitingPassengerCounts", { _ = MapLayers.waitingPassengerCounts(in: session.world) }),
            ("LineBadge.codes", { _ = LineBadge.codes(for: session.world.lines) }),
            ("world.depotRuns()", { _ = session.world.depotRuns() }),
            ("TrainMotion(world:)", { _ = TrainMotion(world: session.world, time: 0) }),
            ("MapWeather(world:)", { _ = MapWeather(world: session.world) }),
            ("RealWorldFrame(world:)", { _ = RealWorldFrame(world: session.world) }),
            ("world.todayHoliday()", { _ = session.world.todayHoliday() }),
            // MapAlertBubbles reads its `placed` twice a body.
            ("MapAlertBubbles: world.mapAlerts() + situationAlerts, twice", {
                for _ in 0..<2 { _ = session.world.mapAlerts() + session.situationAlerts }
            }),
            // MapAttractionMarks: every sight's stars (every sight is on the
            // screen with the whole of Taiwan in view), and each shown
            // mark's station and its stars twice more.
            ("MapAttractionMarks: stars of every sight", {
                for sight in session.world.tourism?.attractions ?? [] { _ = session.world.stars(of: sight) }
            }),
            ("MapAttractionMarks: each mark's station and stars text twice", {
                for sight in session.world.tourism?.attractions ?? [] {
                    _ = session.world.attractionStation(of: sight.id)
                    _ = session.world.starsText(of: sight)
                    _ = session.world.starsText(of: sight)
                }
            }),
        ]
    }
}
