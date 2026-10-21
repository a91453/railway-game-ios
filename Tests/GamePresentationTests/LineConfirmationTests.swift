import GameCore
@testable import GamePresentation
import XCTest

/// The new line's confirmation card (decision 303): its times of day cut
/// to the line's hours, the headway at each, the trains to buy and the
/// price; that its settings at first open the line exactly as the draft's
/// ✓ did before; and what each setting does to the line it opens.
@MainActor
final class LineConfirmationTests: XCTestCase {
    private static let middle = Int64(524_288)
    private static let metre = WorldCoordinate.unitsPerMetre

    // MARK: - Times of day

    private func periods(open: Int, close: Int, in language: DisplayLanguage = .english) -> [String] {
        LineConfirmation.periods(of: .standard, open: open, close: close, in: language).map { "\($0.period.rawValue) \($0.hours)" }
    }

    /// The standard day from 06:00 to midnight: four times of day, the
    /// daytime and the night each in two pieces.
    func testANewLinesDayHasFourTimesOfDay() {
        XCTAssertEqual(periods(open: 360, close: 1440), [
            "morningPeak 07:00–10:00",
            "daytime 10:00–16:00, 20:00–21:00",
            "eveningPeak 16:00–20:00",
            "night 06:00–07:00, 21:00–24:00",
        ])
        XCTAssertEqual(periods(open: 360, close: 1440, in: .traditionalChinese)[1], "daytime 10:00–16:00、20:00–21:00")
    }

    /// The line's hours cut the times of day; one it never runs at is
    /// left out.
    func testTheHoursCutTheTimesOfDay() {
        XCTAssertEqual(periods(open: 480, close: 1140), [
            "morningPeak 08:00–10:00", "daytime 10:00–16:00", "eveningPeak 16:00–19:00",
        ])
        XCTAssertEqual(periods(open: 1000, close: 1100), ["eveningPeak 16:40–18:20"])
    }

    /// Hours past midnight run on into the next morning's night.
    func testHoursPastMidnightRunIntoTheNight() {
        XCTAssertEqual(periods(open: 360, close: 1500).last, "night 06:00–07:00, 21:00–01:00")
        XCTAssertEqual(periods(open: 0, close: 1800).last, "night 00:00–07:00, 21:00–06:00")
    }

    /// Decision 23: the round trip shared between the trains, rounded
    /// up, never under two minutes. The competitor's picture 19: a round
    /// trip of 25 minutes, 3 trains every 9, 2 every 13, 1 every 25.
    func testTheHeadwaySharesTheRoundTrip() {
        XCTAssertEqual(LineConfirmation.headway(roundTrip: 25, trains: 3), 9)
        XCTAssertEqual(LineConfirmation.headway(roundTrip: 25, trains: 2), 13)
        XCTAssertEqual(LineConfirmation.headway(roundTrip: 25, trains: 1), 25)
        XCTAssertEqual(LineConfirmation.headway(roundTrip: 25, trains: 0), 25)
        XCTAssertEqual(LineConfirmation.headway(roundTrip: 25, trains: 20), 2)
        XCTAssertEqual(LineConfirmation.Row(period: .daytime, hours: "", trains: 1, headway: 9).headwayText(in: .english), "About every 9 min")
        XCTAssertEqual(LineConfirmation.Row(period: .night, hours: "", trains: 1, headway: 90).headwayText(in: .traditionalChinese), "約每 1 小時 30 分一班")
    }

    /// The settings stay in range: an hour's day at least, no later than
    /// 06:00 the next morning, one to twenty trains.
    func testTheSettingsStayInRange() {
        let card = LineConfirmation(name: "Line 1")
        XCTAssertEqual(card.open, 360)
        XCTAssertEqual(card.close, 1440)
        XCTAssertEqual(card.trains, TrainsInService(peak: 1, offPeak: 1, low: 1))
        XCTAssertEqual(card.movingOpen(by: -600).open, 0)
        XCTAssertEqual(card.movingOpen(by: 1200).open, 1380)
        XCTAssertEqual(card.movingClose(by: -1200).close, 420)
        XCTAssertEqual(card.movingClose(by: 600).close, 1800)
        XCTAssertEqual(card.setting(.peak, to: 0).trains.peak, 1)
        XCTAssertEqual(card.setting(.peak, to: 99).trains.peak, 20)
        XCTAssertEqual(card.setting(.offPeak, to: 3).setting(.peak, to: 2).trainsNeeded, 3)
        XCTAssertEqual(LineConfirmation.colors.map(\.rgb), LinePalette.safeColors)
    }

    // MARK: - On a map

    /// A straight single track 6 km long, a station 2.5 km either side of
    /// its middle: room for a passing loop between them. `spent` trains
    /// bought first, standing off the track, to leave less money.
    private func session(rules: NewGameRules = .simple, language: DisplayLanguage = .english, spent: Int = 0) throws -> (GameSession, [StationID]) {
        var world = GameWorld.newGame(rules: rules)
        world.setTourism(nil)
        for index in 0..<spent { _ = try world.purchaseTrain(named: "Spare \(index + 1)") }
        let platform = 4 * world.platformCarLength
        func point(_ east: Int64) -> WorldCoordinate {
            WorldCoordinate(x: Self.middle + east * Self.metre, y: Self.middle)
        }
        let main = try world.buildTrackEdge(from: try world.buildTrackNode(at: point(-3_000)), to: try world.buildTrackNode(at: point(3_000)))
        var stations: [StationID] = []
        for (index, east) in [Int64(-2_500), 2_500].enumerated() {
            let id = try world.buildStation(named: ["West", "East"][index], at: PlanPoint(x: Self.middle + east * Self.metre, y: Self.middle - 64 * Self.metre)).id
            let from = (east + 3_000) * Self.metre - platform / 2
            try world.addTrackPlatform(id, on: main, from: from, to: from + platform)
            stations.append(id)
        }
        let session = GameSession(world: world, language: language)
        session.startPickingLineStops(announces: false)
        for station in stations {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
        return (session, stations)
    }

    /// The ✓ raises the card; nothing is bought until Confirm, and Back
    /// leaves the draft as it was.
    func testTheCardComesUpBeforeAnythingIsBought() throws {
        let (session, _) = try session()
        let before = session.world
        session.confirmLineDraft()
        let card = try XCTUnwrap(session.lineConfirmation)
        XCTAssertEqual(card.name, "Line 1")
        XCTAssertEqual(session.world, before)
        session.cancelLineConfirmation()
        XCTAssertNil(session.lineConfirmation)
        XCTAssertEqual(session.lineDraftStops.count, 2)
    }

    /// The card at first shows the line as the draft's ✓ opened it before:
    /// one train for every time of day, the same price.
    func testTheCardStartsAtWhatOpeningTheLineDidBefore() throws {
        let (session, _) = try session()
        let opening = try XCTUnwrap(session.lineOpeningPreview)
        session.confirmLineDraft()
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(preview.cost, opening.cost)
        XCTAssertEqual(preview.trainsToBuy, 1)
        XCTAssertEqual(preview.direction, "Round trip")
        XCTAssertEqual(preview.firstTrain, "06:00")
        XCTAssertEqual(preview.lastTrain, "24:00")
        XCTAssertTrue(preview.figures.hasSuffix("· 2 stops"), preview.figures)
        XCTAssertEqual(preview.rows.map(\.period), [.morningPeak, .daytime, .eveningPeak, .night])
        XCTAssertEqual(Set(preview.rows.map(\.headway)).count, 1, "one train: every time of day the same")
        XCTAssertEqual(preview.purchaseText(in: .english), "Buy 1 train · \(opening.cost.moneyText)")
        XCTAssertNil(preview.shortfall)

        // Confirming it unchanged opens the same line as before.
        let (old, _) = try self.session()
        old.createLineFromDraft()
        session.confirmLine()
        XCTAssertNil(session.lineConfirmation)
        XCTAssertTrue(session.lineDraft.isEmpty)
        XCTAssertEqual(session.world, old.world)
    }

    /// More trains at a time of day: more to buy, a shorter headway there,
    /// the price of the trains and loops on top; Confirm sets the line's
    /// name, colour and hours and each level's target in one command, and
    /// one Undo takes it all back.
    func testEachSettingGoesOnTheLine() throws {
        let (session, _) = try session()
        let before = session.world
        let one = try XCTUnwrap(session.lineOpeningPreview).cost
        session.confirmLineDraft()
        let blue = try XCTUnwrap(LineColor(rgb: 0x0072B2))
        session.updateLineConfirmation {
            var card = $0.setting(.peak, to: 2).movingOpen(by: 60).movingClose(by: -120)
            card.name = "Harbour Line"
            card.color = blue
            return card
        }
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(preview.trainsToBuy, 2)
        XCTAssertNil(preview.trackLimit)
        XCTAssertGreaterThan(preview.cost.amount, one.amount)
        XCTAssertEqual(preview.firstTrain, "07:00")
        XCTAssertEqual(preview.lastTrain, "22:00")
        XCTAssertEqual(preview.rows.map(\.trains), [2, 1, 2, 1])
        let peak = preview.rows[0].headway, daytime = preview.rows[1].headway, night = preview.rows[3].headway
        XCTAssertEqual(preview.rows[2].headway, peak, "the two peaks share their trains")
        XCTAssertLessThan(peak, daytime)
        XCTAssertEqual(daytime, night)

        let balance = session.world.economy.balance
        session.confirmLine()
        XCTAssertNil(session.lineConfirmation)
        let line = try XCTUnwrap(session.world.lines.last)
        XCTAssertEqual(line.name, "Harbour Line")
        XCTAssertEqual(line.color, blue)
        XCTAssertEqual(line.window, .hours(open: 420, close: 1320))
        XCTAssertEqual(line.trains.count, 2)
        XCTAssertEqual(line.targetHeadways, TargetHeadways(peak: peak, offPeak: daytime, low: night))
        XCTAssertEqual(balance.amount - session.world.economy.balance.amount, preview.cost.amount)

        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// The preview is worked out once for each setting and command, and
    /// the card leaves the world as it is.
    func testThePreviewIsWorkedOutOnce() throws {
        let (session, _) = try session()
        session.confirmLineDraft()
        let before = session.world
        let first = session.lineConfirmationPreview
        XCTAssertNotNil(session.lineConfirmationMemo)
        XCTAssertEqual(session.lineConfirmationPreview, first)
        session.updateLineConfirmation { $0.setting(.low, to: 2) }
        XCTAssertNotEqual(session.lineConfirmationPreview, first)
        XCTAssertEqual(session.world, before)
    }

    /// More trains than can wait at the line's ends: the card buys only
    /// those that start, says so, and none is left standing off the track.
    func testTheCardBuysOnlyTheTrainsThatCanStart() throws {
        let (session, _) = try session()
        session.confirmLineDraft()
        session.updateLineConfirmation { $0.setting(.peak, to: 5) }
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(preview.trainsToBuy, 2)
        XCTAssertEqual(preview.rows.map(\.trains), [2, 1, 2, 1])
        XCTAssertEqual(preview.trackLimit, "2 trains can wait at the line's ends at once. Once they leave, add more with Add a Train.")
        session.confirmLine()
        XCTAssertEqual(session.world.lines.last?.trains.count, 2)
        XCTAssertEqual(session.world.trains.count, 2, "no train bought to stand idle")
    }

    /// Too little money: the card says so, and Confirm buys nothing.
    func testTheCardSaysWhenTheMoneyIsShort() throws {
        let (session, _) = try session(spent: 8)
        session.confirmLineDraft()
        XCTAssertNil(session.lineConfirmationPreview?.shortfall, "one train is still paid for")
        session.updateLineConfirmation { $0.setting(.peak, to: 2) }
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertGreaterThan(preview.cost.amount, session.world.economy.balance.amount)
        XCTAssertNotNil(preview.shortfall)
        let before = session.world
        session.confirmLine()
        XCTAssertEqual(session.world, before)
        XCTAssertNotNil(session.lineConfirmation, "the card stays up")
        XCTAssertEqual(session.message?.text, preview.shortfall)
    }

    /// A second line along the first one's track, its card asking for two
    /// trains: the cash left after eight spare trains and the first line
    /// pays for one.
    private func secondLineCard() throws -> GameSession {
        let (session, stations) = try session(spent: 8)
        session.confirmLineDraft()
        session.confirmLine()
        XCTAssertEqual(session.world.lines.count, 1)
        session.startPickingLineStops(announces: false)
        for station in stations {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
        session.confirmLineDraft()
        session.updateLineConfirmation { $0.setting(.peak, to: 2) }
        return session
    }

    /// The cash moves on while the card is up (the first line's running
    /// costs, hour by hour): the shortfall follows the cash there is, not
    /// the cash when the card was worked out, so Confirm turns off once it
    /// no longer pays.
    func testTheShortfallFollowsTheCash() throws {
        let session = try secondLineCard()
        let first = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertNil(first.shortfall)
        for _ in 0..<30 where session.world.economy.canAfford(first.cost) {
            session.advance(ticks: 600)
        }
        XCTAssertFalse(session.world.economy.canAfford(first.cost), "the running costs took the cash below the price")
        let later = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(later.cost, first.cost)
        let shortfall = try XCTUnwrap(later.shortfall)
        XCTAssertTrue(shortfall.contains(session.world.economy.balance.moneyText), shortfall)
    }

    /// One train is one: the track limit's words for a single train.
    func testTheTrackLimitOfOneTrain() throws {
        let session = try secondLineCard()
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(preview.trainsToBuy, 1)
        XCTAssertEqual(preview.trackLimit, "1 train can wait at the line's ends at once. Once it leaves, add more with Add a Train.")
    }

    /// Realistic rules run no line for the player: the ✓ makes the line at
    /// once, as before, with no card.
    func testRealisticRulesMakeTheLineAtOnce() throws {
        let (session, _) = try session(rules: .realistic)
        session.confirmLineDraft()
        XCTAssertNil(session.lineConfirmation)
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertTrue(session.world.lines[0].trains.isEmpty)
    }

    /// Both languages.
    func testTheCardSpeaksChinese() throws {
        let (session, _) = try session(language: .traditionalChinese)
        session.confirmLineDraft()
        XCTAssertEqual(session.lineConfirmation?.name, "路線 1")
        let preview = try XCTUnwrap(session.lineConfirmationPreview)
        XCTAssertEqual(preview.direction, "來回")
        XCTAssertTrue(preview.figures.hasSuffix("· 2 站"), preview.figures)
        XCTAssertTrue(preview.purchaseText(in: .traditionalChinese).hasPrefix("還要買 1 列 · "))
        XCTAssertEqual(LineConfirmation.Period.allCases.map { $0.title(in: .traditionalChinese) }, ["早尖峰", "白天", "晚尖峰", "夜間"])
        session.updateLineConfirmation { $0.movingClose(by: 60) }
        XCTAssertEqual(session.lineConfirmationPreview?.lastTrain, "翌日 01:00")
    }
}
