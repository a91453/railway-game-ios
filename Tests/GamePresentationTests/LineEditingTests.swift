import GameCore
import GamePresentation
import XCTest

/// Stage C2: editing a line's stops (`setLineStops`) and the service day
/// (`setServiceDay`), one command per control; and when each level runs,
/// as the `Ci/` reference's tooltip lists it.
@MainActor
final class LineEditingTests: XCTestCase {
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)

    func testStopsAreInsertedMovedAndRemoved() throws {
        let session = GameSession(world: try makeLine())
        session.insertStopIntoSelectedLine(gamma, at: 2)
        XCTAssertEqual(session.selectedLine?.stops, [alpha, beta, gamma])
        XCTAssertEqual(session.message?.text, "Main now calls at Alpha – Beta – Gamma.")
        session.insertStopIntoSelectedLine(gamma, at: 0)
        XCTAssertEqual(session.selectedLine?.stops, [gamma, alpha, beta, gamma])
        session.moveStopOfSelectedLine(at: 0, by: 1)
        XCTAssertEqual(session.selectedLine?.stops, [alpha, gamma, beta, gamma])
        session.moveStopOfSelectedLine(at: 0, by: -1)
        XCTAssertEqual(session.selectedLine?.stops, [alpha, gamma, beta, gamma], "nothing before the first stop")
        session.removeStopFromSelectedLine(at: 1)
        XCTAssertEqual(session.selectedLine?.stops, [alpha, beta, gamma])

        // GameCore refuses a station twice in a row and fewer than two stops.
        session.insertStopIntoSelectedLine(beta, at: 1)
        XCTAssertEqual(session.message?.text, GameError.invalidLineStops.playerMessage(in: .english))
        XCTAssertEqual(session.selectedLine?.stops, [alpha, beta, gamma])
        session.removeStopFromSelectedLine(at: 0)
        session.removeStopFromSelectedLine(at: 0)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.selectedLine?.stops, [beta, gamma])

        let chinese = GameSession(world: try makeLine(), language: .traditionalChinese)
        chinese.insertStopIntoSelectedLine(gamma, at: 2)
        XCTAssertEqual(chinese.message?.text, "Main 改停 Alpha – Beta – Gamma。")
    }

    func testRemovingAStopAbandonsThoseWaitingForIt() throws {
        var world = try makeLine()
        try world.setLineStops(LineID(rawValue: 1), to: [alpha, beta, gamma])
        for station in [alpha, beta, gamma] {
            try world.setStationDemand(station, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        }
        world.setSpeed(.normal)
        try world.advance(ticks: 480)
        let session = GameSession(world: world)
        session.removeStopFromSelectedLine(at: 2)
        XCTAssertEqual(session.world.waitingPassengers(at: alpha).filter { $0.destination == gamma }, [])
        XCTAssertGreaterThan(session.world.passengerLedger(of: alpha).abandoned, 0, "GameCore's abandoned")
    }

    func testTheReferenceTooltipRangesOfTheStandardDay() {
        let day = ServiceDay.standard
        XCTAssertEqual(day.ranges(of: .peak), ["07:00–10:00", "16:00–20:00"])
        XCTAssertEqual(day.ranges(of: .offPeak), ["10:00–16:00", "20:00–21:00"])
        XCTAssertEqual(day.ranges(of: .low), ["00:00–07:00", "21:00–24:00"])
        XCTAssertEqual(
            day.summaryText(in: .english),
            "Peak 07:00–10:00, 16:00–20:00 · Off-peak 10:00–16:00, 20:00–21:00 · Low 00:00–07:00, 21:00–24:00"
        )
        XCTAssertEqual(
            day.summaryText(in: .traditionalChinese),
            "尖峰 07:00–10:00、16:00–20:00 · 離峰 10:00–16:00、20:00–21:00 · 低峰 00:00–07:00、21:00–24:00"
        )
        XCTAssertEqual(day.bandText(1, in: .english), "From 07:00 · Peak")
        XCTAssertEqual(day.bandText(1, in: .traditionalChinese), "07:00 起 · 尖峰")
        // Neighbouring bands of one level read as one range.
        let joined = ServiceDay(bands: [.init(start: 0, level: .peak), .init(start: 600, level: .peak), .init(start: 900, level: .low)])
        XCTAssertEqual(joined.ranges(of: .peak), ["00:00–15:00"])
        XCTAssertEqual(joined.summaryText(in: .english), "Peak 00:00–15:00 · Low 15:00–24:00")
    }

    func testTheServiceDayIsEditedBandByBand() throws {
        let session = GameSession(world: try makeLine())
        session.setServiceDayBand(2, to: .peak)
        XCTAssertEqual(session.world.serviceDay.ranges(of: .peak), ["07:00–20:00"])
        XCTAssertEqual(session.message?.text, "Service day: From 10:00 · Peak.")

        session.moveServiceDayBand(1, by: -30)
        XCTAssertEqual(session.world.serviceDay.bands[1], ServiceDay.Band(start: 390, level: .peak))
        session.moveServiceDayBand(1, by: -1_000)
        XCTAssertEqual(session.world.serviceDay.bands[1].start, 1, "a minute after the band before it")
        XCTAssertFalse(ServiceDayEditing.canMove(1, later: false, in: session.world.serviceDay))
        session.moveServiceDayBand(1, by: 1_000)
        XCTAssertEqual(session.world.serviceDay.bands[1].start, 599, "a minute before the next")
        XCTAssertFalse(ServiceDayEditing.canMove(0, later: true, in: session.world.serviceDay), "the first band starts at 00:00")
        session.moveServiceDayBand(0, by: 30)
        XCTAssertEqual(session.world.serviceDay.bands[0].start, 0)

        session.removeServiceDayBand(1)
        XCTAssertEqual(session.world.serviceDay.bands.map(\.start), [0, 600, 960, 1200, 1260])
        session.removeServiceDayBand(0)
        XCTAssertEqual(session.world.serviceDay.bands.map(\.start), [0, 600, 960, 1200, 1260], "the first band stays")

        session.resetServiceDay()
        XCTAssertEqual(session.world.serviceDay, .standard)
        XCTAssertEqual(session.message?.text, "Service day: \(ServiceDay.standard.summaryText(in: .english)).")
    }

    func testAddingSplitsTheLongestBandAtItsMiddle() throws {
        let session = GameSession(world: try makeLine())
        // 00:00–07:00 is the longest; its middle, 03:30, starts a second low band.
        session.addServiceDayBand()
        XCTAssertEqual(session.world.serviceDay.bands.map(\.start), [0, 210, 420, 600, 960, 1200, 1260])
        XCTAssertEqual(session.world.serviceDay.bands[1].level, .low)
        XCTAssertEqual(session.message?.text, "Service day: From 03:30 · Low.")
        XCTAssertEqual(session.world.serviceDay.ranges(of: .low), ServiceDay.standard.ranges(of: .low), "nothing runs differently")

        let short = ServiceDay(bands: (0..<24).map { ServiceDay.Band(start: $0 * 60, level: .offPeak) })
        XCTAssertEqual(ServiceDayEditing.splittingLongest(short), short, "no band longer than an hour")
        var world = try makeLine()
        try world.setServiceDay(short)
        let full = GameSession(world: world)
        full.addServiceDayBand()
        XCTAssertEqual(full.message, StatusMessage(kind: .failure, text: "Every band is an hour or shorter."))
    }

    /// Alpha, Beta and Gamma, no track; line Main calling at Alpha and Beta.
    private func makeLine() throws -> GameWorld {
        var world = try makeWorld(width: 8, height: 4, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        try world.createLine(named: "Main", stops: [alpha, beta])
        return world
    }
}
