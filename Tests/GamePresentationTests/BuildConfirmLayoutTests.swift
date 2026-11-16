import GameCore
import GamePresentation
import XCTest

/// The map's ✕ and ✓ pill on the screen of TestFlight 67.1's report: an
/// iPhone 17 held on its side (874 points across), the tools down the
/// leading edge and the track card over the trailing third, and a refusal
/// of some 640 points on one line. The pill stood from the tools to under
/// the card, its words cut off at the card's edge.
final class BuildConfirmLayoutTests: XCTestCase {
    private static let viewport = 874.0
    /// The tools column, past the camera housing.
    private static let leading = 130.0
    /// The track card and its gap.
    private static let trailing = 300.0
    /// The refusal on one line, at the caption's size.
    private static let refusalWidth = 640.0

    func testALongRefusalStaysBetweenTheToolsAndTheCard() {
        let widest = BuildConfirmLayout.maximumWidth(viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing)
        XCTAssertEqual(widest, 874 - 130 - 300 - 16)
        XCTAssertLessThan(widest, Self.refusalWidth, "The refusal wraps")
        let width = min(Self.refusalWidth, widest)
        for anchor in [0.0, 300, 437, 700, 874] {
            let x = BuildConfirmLayout.originX(
                anchorX: anchor, width: width, viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing
            )
            XCTAssertGreaterThanOrEqual(x, Self.leading, "Under the tools, anchored at \(anchor)")
            XCTAssertLessThanOrEqual(x + width, Self.viewport - Self.trailing, "Under the card, anchored at \(anchor)")
        }
    }

    func testAShortPillStaysCentredOnItsAnchor() {
        let x = BuildConfirmLayout.originX(
            anchorX: 300, width: 120, viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing
        )
        XCTAssertEqual(x, 240)
    }

    func testASqueezedMapKeepsTheWordsReadable() {
        let widest = BuildConfirmLayout.maximumWidth(viewportWidth: 400, leading: 130, trailing: 300)
        XCTAssertEqual(widest, BuildConfirmLayout.minimumWidth)
        // Wider than the band: at its leading side, not under the tools.
        XCTAssertEqual(BuildConfirmLayout.originX(anchorX: 200, width: widest, viewportWidth: 400, leading: 130, trailing: 300), 138)
    }

    /// Decision 744, a player's report (2026-11-14): choosing where a
    /// station goes, the pill stood over the line the station goes on. A
    /// line rising across the map, the place picked at its middle: the
    /// pill, which first stood under the place, is moved where it covers
    /// neither the place nor the track near it.
    func testThePillKeepsOffTheSiteAndItsTrack() {
        let line = [ScreenPoint(x: 100, y: 100), ScreenPoint(x: 800, y: 300)]
        let anchor = ScreenPoint(x: 450, y: 200)
        let width = 300.0, height = 120.0
        let obstacles = BuildConfirmLayout.siteObstacles([line], around: anchor, reach: width + 16)
        XCTAssertEqual(obstacles.first, ScreenFrame(x: 438, y: 188, width: 24, height: 24), "the place itself first")
        XCTAssertGreaterThan(obstacles.count, 1)
        XCTAssertLessThanOrEqual(obstacles.count, 17)
        let x = anchor.x - width / 2, y = anchor.y + 18
        XCTAssertTrue(
            obstacles.contains { BuildConfirmLayout.overlaps(x: x, y: y, width: width, height: height, $0) },
            "under the place, the pill covers the line"
        )
        let placed = BuildConfirmLayout.keepingOff(
            obstacles, x: x, y: y, width: width, height: height, minX: 8, maxX: 874 - 8 - width, highest: 8, lowest: 402 - 8 - height
        )
        for frame in obstacles {
            XCTAssertFalse(
                BuildConfirmLayout.overlaps(x: placed.x, y: placed.y, width: width, height: height, frame),
                "clear of \(frame)"
            )
        }
    }

    /// Only the pieces near the place count, nearest first, at most the
    /// limit.
    func testOnlyTheNearestPiecesOfTrackCount() {
        let long = [ScreenPoint(x: -5_000, y: 50), ScreenPoint(x: 5_000, y: 50)]
        let obstacles = BuildConfirmLayout.siteObstacles([long], around: ScreenPoint(x: 0, y: 50), reach: 200, limit: 4)
        XCTAssertEqual(obstacles.count, 5)
        for frame in obstacles.dropFirst() {
            XCTAssertLessThanOrEqual(abs(frame.x + frame.width / 2), 200)
        }
        XCTAssertEqual(BuildConfirmLayout.siteObstacles([long], around: ScreenPoint(x: 0, y: 900), reach: 200).count, 1)
    }

    // MARK: Decision 800 (the owner's report from 0.6.0 (134))

    /// A phone held sideways: a pill's words stand beside its ✕ ✓, so it
    /// is half as tall; upright, on an iPad, and for a pill of only ✕ ✓,
    /// as before. Decision 803: every build's pill, but the new line's,
    /// whose station pair drawer rides beside its words already.
    func testAPillWithWordsStandsBesideItsButtonsOnAShortScreen() {
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: true, hasWords: true), .beside)
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: true, hasWords: false), .stacked)
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: false, hasWords: true), .stacked)
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: true, hasWords: true, ridesWithDrawer: true), .stacked)
    }

    // MARK: Decision 803, continued (the owner: "字不會太多嗎")

    /// A refusal with fixes on a phone held sideways: why across the top
    /// and one row of the fixes and ✕ ✓, its buttons a finger's least, so
    /// the pill (6 + 22 + 4 + 44 + 6 points) leaves a stretch across the
    /// middle of some 195 points in sight. Upright and on an iPad it
    /// stays stacked, its buttons 48 points.
    func testARefusalWithFixesIsOneStripOnAShortScreen() {
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: true, hasWords: true, hasFixes: true), .strip)
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: false, hasWords: true, hasFixes: true), .stacked)
        XCTAssertEqual(BuildConfirmLayout.arrangement(compactHeight: true, hasWords: true, hasFixes: false), .beside)
        XCTAssertEqual(BuildConfirmLayout.buttonHeight(.strip), 44)
        XCTAssertEqual(BuildConfirmLayout.buttonHeight(.stacked), 48)
        XCTAssertEqual(BuildConfirmLayout.buttonHeight(.beside), 48)
        let pill = 2 * StationPairDrawerLayout.pillPadding + 22 + 4 + BuildConfirmLayout.buttonHeight(.strip)
        // Above or below a line across the middle of 195 points, with the
        // gap `keepingOff` leaves and the line's own width.
        XCTAssertLessThanOrEqual(pill + BuildConfirmLayout.margin + BuildConfirmLayout.trackHalfWidth, 195 / 2)
    }

    /// The pill is as wide as its widest child, words no wider than they
    /// wrap at, all within the map's clear band; every child gets that.
    func testThePillIsAsWideAsItsWidestChild() {
        // A one-line reason, the row of fixes and ✕ ✓.
        XCTAssertEqual(BuildConfirmLayout.columnWidth([(150, 340), (420, nil)], limit: 600), 420)
        // A long sentence wraps at its cap rather than widening the pill.
        XCTAssertEqual(BuildConfirmLayout.columnWidth([(900, 340), (120, nil)], limit: 600), 340)
        XCTAssertEqual(BuildConfirmLayout.columnWidth([(900, .infinity), (120, nil)], limit: 600), 600)
        XCTAssertEqual(BuildConfirmLayout.columnWidth([(900, 340), (420, nil)], limit: 300), 300)
        XCTAssertEqual(BuildConfirmLayout.columnWidth([(100, 340)], limit: nil), 100)
        XCTAssertEqual(BuildConfirmLayout.columnWidth([], limit: 300), 0)
    }

    /// The two fixes are one width: the wider one's, or half the row they
    /// are given; one over another only where the row cannot hold both.
    func testTheFixesAreOneWidth() {
        var cells = BuildConfirmLayout.equalCells(ideal: [120, 160], available: nil, spacing: 6)
        XCTAssertEqual(cells.cell, 160)
        XCTAssertFalse(cells.stacked)
        cells = BuildConfirmLayout.equalCells(ideal: [120, 160], available: 406, spacing: 6)
        XCTAssertEqual(cells.cell, 200)
        XCTAssertFalse(cells.stacked)
        // Offered what it asked for, a rounding short: still side by side
        // and no narrower than the words need.
        cells = BuildConfirmLayout.equalCells(ideal: [120, 160], available: 325.9999, spacing: 6)
        XCTAssertEqual(cells.cell, 160)
        XCTAssertFalse(cells.stacked)
        cells = BuildConfirmLayout.equalCells(ideal: [120, 160], available: 300, spacing: 6)
        XCTAssertEqual(cells.cell, 300)
        XCTAssertTrue(cells.stacked)
        cells = BuildConfirmLayout.equalCells(ideal: [120, 160], available: 100, spacing: 6)
        XCTAssertEqual(cells.cell, 160)
        XCTAssertTrue(cells.stacked)
        cells = BuildConfirmLayout.equalCells(ideal: [160], available: 100, spacing: 6)
        XCTAssertFalse(cells.stacked, "one fix has nothing to stand over")
        XCTAssertEqual(BuildConfirmLayout.equalCells(ideal: [], available: 100, spacing: 6).cell, 0)
    }

    /// The pill waits for the finger whichever build it draws: a stretch
    /// of track (decision 803), a road, a building moved; and only the
    /// tool in hand counts.
    func testThePillWaitsForTheFingerOfTheToolInHand() {
        func draws(_ tool: ConstructionTool, track: Bool = false, road: Bool = false, building: Bool = false, roads: Bool = true) -> Bool {
            BuildConfirmLayout.fingerDraws(track: track, road: road, building: building, tool: tool, roadsMode: roads)
        }
        XCTAssertTrue(draws(.network, track: true))
        XCTAssertTrue(draws(.bus, road: true))
        XCTAssertTrue(draws(.building, building: true))
        XCTAssertFalse(draws(.bus, road: true, roads: false), "a bus route is tapped, not drawn")
        XCTAssertFalse(draws(.network, road: true, building: true))
        XCTAssertFalse(draws(.select, track: true, road: true, building: true))
        XCTAssertFalse(draws(.train, track: true, road: true, building: true))
    }

    // MARK: Decision 803 (the owner, 2026-11-16: too cluttered)

    /// No ✕ ✓ under the finger that draws; they come when it lets go.
    func testNoPillWhileAFingerDraws() {
        XCTAssertFalse(BuildConfirmLayout.pillShows(fingerDraws: true))
        XCTAssertTrue(BuildConfirmLayout.pillShows(fingerDraws: false))
    }

    /// The HUD's row is the length and the height, and one small mark: a
    /// refusal the pill says is not said twice; while a finger draws (no
    /// pill) a warning sign stands for it; a refusal comes before a join.
    func testTheHUDCarriesOneMark() {
        XCTAssertEqual(BuildConfirmLayout.hudMark(refused: true, pillSaysProblem: true, joins: true), BuildConfirmLayout.HUDMark.none)
        XCTAssertEqual(BuildConfirmLayout.hudMark(refused: true, pillSaysProblem: false, joins: true), .refused)
        XCTAssertEqual(BuildConfirmLayout.hudMark(refused: false, pillSaysProblem: false, joins: true), .joins)
        XCTAssertEqual(BuildConfirmLayout.hudMark(refused: false, pillSaysProblem: false, joins: false), BuildConfirmLayout.HUDMark.none)
    }

    /// A stretch's pill has ✕ ✓ and its price alone, but for a real line
    /// for sale along it; refused too (continued), its notes are the
    /// details card's.
    func testAStretchSaysOnlyWhatItOffers() {
        XCTAssertNil(BuildConfirmLayout.stretchCaption(offer: [nil, nil]))
        XCTAssertEqual(BuildConfirmLayout.stretchCaption(offer: ["For sale", nil]), "For sale")
        XCTAssertEqual(BuildConfirmLayout.stretchCaption(offer: ["For sale", "Short"]), "For sale\nShort")
        XCTAssertNil(BuildConfirmLayout.stretchCaption(offer: [nil, ""]))
    }

    /// With a real session: a stretch on open ground can be built, and
    /// its pill has no words; over water it is refused, and the fixes are
    /// at most one up and one down, each short title naming the end it
    /// moves.
    @MainActor
    func testARefusalOffersAtMostTwoFixesThatNameTheirEnd() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000)),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: side * side))!])
        try world.setWater([CellPosition(row: 0, column: 2)])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkSnapsToTrack = false
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        let card = try XCTUnwrap(session.networkHeightCard)
        XCTAssertNotNil(session.networkPreview?.problem)
        XCTAssertLessThanOrEqual(card.fixes.count, 2)
        XCTAssertLessThanOrEqual(card.fixes.filter { $0.change > 0 }.count, 1)
        XCTAssertLessThanOrEqual(card.fixes.filter { $0.change < 0 }.count, 1)
        // Continued: the pill writes one short line and the button a word
        // or two; the whole sentence and which end moves are VoiceOver's.
        let refusal = try XCTUnwrap(session.networkPreview.flatMap(BuildConfirmLayout.refusal(of:)))
        XCTAssertEqual(refusal.shown, "Over water: bridge or tunnel")
        XCTAssertEqual(refusal.spoken, session.networkPreview?.problem)
        for fix in card.fixes {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let ends = ["end", "start", "both ends", "終點", "起點", "兩端"]
                XCTAssertTrue(ends.contains { fix.title(in: language).contains($0) }, fix.title(in: language))
                XCTAssertFalse(ends.contains { fix.buttonTitle(in: language).contains($0) }, fix.buttonTitle(in: language))
                XCTAssertFalse(fix.buttonTitle(in: language).contains { $0.isASCII && $0.isNumber }, fix.buttonTitle(in: language))
            }
        }
    }

    /// The report's "NT$ 0" on both fixes: with unlimited funds the fix's
    /// price is nothing, as what ✓ then charges is, and the pill writes
    /// no price; with funds that count it writes it.
    @MainActor
    func testAFreeFixWritesNoPrice() throws {
        func fixes(unlimited: Bool) throws -> [NetworkHeightFix] {
            var world = GameWorld(
                bounds: try WorldBounds(width: 262_144, height: 262_144),
                economy: GameEconomy(balance: Money(100_000_000)),
                clock: GameClock(speed: .paused)
            )
            let side = GroundBlock.side
            try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: side * side))!])
            try world.setWater([CellPosition(row: 0, column: 2)])
            world.setUnlimitedFunds(unlimited)
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.networkSnapsToTrack = false
            session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
            session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
            return try XCTUnwrap(session.networkHeightCard).fixes
        }
        let free = try fixes(unlimited: true)
        XCTAssertEqual(free.count, 2)
        for fix in free {
            XCTAssertEqual(fix.cost, .zero, "nothing is charged with unlimited funds")
            XCTAssertNil(BuildConfirmLayout.priceText(of: fix.cost, in: .traditionalChinese), "so no price is written")
        }
        let paid = try fixes(unlimited: false)
        XCTAssertEqual(paid.count, 2)
        for fix in paid {
            XCTAssertGreaterThan(fix.cost, .zero)
            XCTAssertEqual(BuildConfirmLayout.priceText(of: fix.cost, in: .english), fix.cost.compactText(in: .english))
        }
        XCTAssertNil(BuildConfirmLayout.priceText(of: nil, in: .english))
    }

    /// The report's screen: an iPhone on its side (874 by 402), a short
    /// stretch drawn down the middle, its end the lower one. Under the
    /// end the pill stood over nothing of it, but held up off the dock it
    /// covered the stretch and its flags; it is moved beside them.
    func testThePillKeepsOffTheStretchDrawnAndItsFlags() {
        let start = ScreenPoint(x: 430, y: 150), end = ScreenPoint(x: 450, y: 250)
        let width = 420.0, height = 110.0
        let obstacles = BuildConfirmLayout.stretchObstacles(
            [start, end], flags: [start, end], around: end, reach: 2 * (width + 16)
        )
        XCTAssertEqual(obstacles[0], ScreenFrame(x: 438, y: 238, width: 24, height: 24), "the end itself first")
        XCTAssertEqual(obstacles[1], BuildConfirmLayout.flagFrame(at: start))
        XCTAssertEqual(obstacles[2], ScreenFrame(x: 436, y: 214, width: 28, height: 28), "the end's flag stands over it")
        XCTAssertGreaterThan(obstacles.count, 3, "and the stretch's pieces")
        // The dock leaves the map's lowest 80 points: the pill cannot
        // stand under the end, and is held up over the stretch.
        let lowest = 402 - 80 - 8 - height
        let x = end.x - width / 2, y = min(end.y + 18, lowest)
        XCTAssertTrue(obstacles.contains { BuildConfirmLayout.overlaps(x: x, y: y, width: width, height: height, $0) })
        let placed = BuildConfirmLayout.keepingOff(
            obstacles, x: x, y: y, width: width, height: height, minX: 8, maxX: 874 - 8 - width, highest: 70, lowest: lowest
        )
        for frame in obstacles {
            XCTAssertFalse(
                BuildConfirmLayout.overlaps(x: placed.x, y: placed.y, width: width, height: height, frame),
                "clear of \(frame)"
            )
        }
    }

    /// A trace of thousands of points is thinned before it is cut into
    /// pieces, its end kept.
    func testALongTraceIsThinned() {
        let trace = (0..<5_000).map { ScreenPoint(x: Double($0) / 10, y: 100) }
        let obstacles = BuildConfirmLayout.stretchObstacles(trace, flags: [], around: trace[4_999], reach: 300)
        XCTAssertEqual(obstacles[0], ScreenFrame(x: 499.9 - 12, y: 88, width: 24, height: 24))
        XCTAssertLessThanOrEqual(obstacles.count, 17)
        XCTAssertTrue(obstacles.dropFirst().contains { $0.x + $0.width >= 499.9 }, "the piece that reaches the end")
    }
}
