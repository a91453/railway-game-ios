@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 481: the lines panel in two levels. Which line's page is open,
/// what opens and closes it, the stack the panel shows for it, the lines
/// before and after it, and the short list's second line.
@MainActor
final class LinesPanelNavigationTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let first = LineID(rawValue: 1)
    private static let second = LineID(rawValue: 2)

    /// Alpha, Beta, Gamma and Delta on one straight track, and two lines
    /// over it.
    private func session() throws -> GameSession {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .normal)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.createLine(named: "Short", stops: [stops[1], stops[3]])
        return GameSession(world: world)
    }

    func testAGameStartsOnTheListWithItsFirstLineSelected() throws {
        let session = try session()
        XCTAssertEqual(session.selectedLineID, Self.first)
        XCTAssertTrue(session.linesPanelListsLinesFirst)
        XCTAssertNil(session.openedLineID)
        XCTAssertNil(session.openedLine)
    }

    func testOpeningALineSelectsItAndBackKeepsItSelected() throws {
        let session = try session()
        session.openLine(Self.second)
        XCTAssertEqual(session.selectedLineID, Self.second)
        XCTAssertEqual(session.openedLine?.name, "Short")

        // Opening the selected line opens it too (selecting alone does not).
        session.closeLineDetails()
        XCTAssertNil(session.openedLine)
        XCTAssertEqual(session.selectedLineID, Self.second)
        session.openLine(Self.second)
        XCTAssertEqual(session.openedLineID, Self.second)

        // Selecting another (a copy of the line, a lesson) while the page is
        // open shows that one: the page's controls change the selected line.
        session.selectLine(Self.first)
        XCTAssertEqual(session.openedLineID, Self.first)
        session.closeLineDetails()
        session.selectLine(Self.second)
        XCTAssertNil(session.openedLineID, "selecting alone does not open the page")
        session.openLine(Self.second)

        session.openLine(LineID(rawValue: 99))
        XCTAssertEqual(session.openedLineID, Self.second, "a line the world does not have is ignored")
    }

    func testThePanelStaysOneFormWhileANewLineIsPicked() throws {
        let session = try session()
        session.openLine(Self.first)
        session.selectStation(StationID(rawValue: 1))
        session.addSelectedStationToLineDraft()
        XCTAssertFalse(session.linesPanelListsLinesFirst)
        XCTAssertNil(session.openedLine, "the draft comes first, on the one form")
        session.clearLineDraft()
        XCTAssertEqual(session.openedLine?.id, Self.first)
    }

    func testRemovingTheOpenedLineGoesBackToTheList() throws {
        let session = try session()
        session.openLine(Self.second)
        session.removeSelectedLine()
        XCTAssertNil(session.world.line(id: Self.second))
        XCTAssertNil(session.openedLineID)
        XCTAssertEqual(session.selectedLineID, Self.first)
    }

    func testTheStackHoldsTheLinePageAloneWhileALineIsOpened() {
        XCTAssertEqual(LinesPanelPage.path([], opened: true), [.line])
        XCTAssertEqual(LinesPanelPage.path([.network], opened: true), [.line], "a line opened from the map replaces the page")
        XCTAssertEqual(LinesPanelPage.path([.line], opened: true), [.line])
        XCTAssertEqual(LinesPanelPage.path([.line], opened: false), [])
        XCTAssertEqual(LinesPanelPage.path([.forSale], opened: false), [.forSale])
    }

    func testLeavingTheLinePageClosesIt() throws {
        let session = try session()
        session.openLine(Self.first)
        session.linesPanelPathChanged(to: [.line])
        XCTAssertEqual(session.openedLineID, Self.first)
        session.linesPanelPathChanged(to: [])
        XCTAssertNil(session.openedLineID)
    }

    func testTheArrowsFollowTheListOrEveryLine() {
        let ids = (1...4).map { LineID(rawValue: $0) }
        let shown = [ids[2], ids[0], ids[3]]
        XCTAssertTrue(LineNeighbours.around(ids[2], shown: shown, all: ids) == (nil, ids[0]))
        XCTAssertTrue(LineNeighbours.around(ids[0], shown: shown, all: ids) == (ids[2], ids[3]))
        XCTAssertTrue(LineNeighbours.around(ids[3], shown: shown, all: ids) == (ids[0], nil))
        // Left out by the search: every line's order.
        XCTAssertTrue(LineNeighbours.around(ids[1], shown: shown, all: ids) == (ids[0], ids[2]))
        XCTAssertTrue(LineNeighbours.around(LineID(rawValue: 9), shown: shown, all: ids) == (nil, nil))
        XCTAssertEqual(LineNeighbours.positionText(ids[0], shown: shown, all: ids, in: .english), "Line 2 of 3")
        XCTAssertEqual(LineNeighbours.positionText(ids[1], shown: shown, all: ids, in: .traditionalChinese), "第 2 條，共 4 條")
        XCTAssertNil(LineNeighbours.positionText(ids[0], shown: [ids[0]], all: [ids[0]], in: .english))
    }

    // MARK: - The short list's second line

    private func day(_ index: Int64, riders: Int64) -> LineOperatingDay {
        var tally = LineTally()
        tally.boardings = riders
        return LineOperatingDay(LineDay(day: index, tally: tally))
    }

    func testTheRowSaysWhoRodeAndWhetherItPaid() {
        let yesterday = day(1, riders: 12_340)
        let report = LineReport(line: Self.first, name: "Red", today: nil, yesterday: yesterday, days: [yesterday])
        XCTAssertEqual(report.compactRowText(in: .english), "Yesterday 12,340 riders · profit \(yesterday.profit.moneyText)")
        XCTAssertEqual(report.compactRowText(in: .traditionalChinese), "昨日 12,340 人次 · 損益 \(yesterday.profit.moneyText)")
        XCTAssertEqual(report.lostMoneyYesterday, yesterday.profit < .zero)
        // Decision 486: a narrow row puts the profit under the riders.
        XCTAssertEqual(report.compactRowParts(in: .traditionalChinese), ["昨日 12,340 人次", "損益 \(yesterday.profit.moneyText)"])

        let new = LineReport(line: Self.first, name: "Red", today: day(0, riders: 40), yesterday: nil, days: [])
        XCTAssertEqual(new.compactRowText(in: .english), "Today so far 40 riders")
        XCTAssertFalse(new.lostMoneyYesterday)
        let none = LineReport(line: Self.first, name: "Red", today: nil, yesterday: nil, days: [])
        XCTAssertEqual(none.compactRowText(in: .traditionalChinese), "昨日還沒有紀錄")
        XCTAssertEqual(none.compactRowParts(in: .traditionalChinese).count, 1)
    }

    func testTheNetworkRowSaysHowItIsSet() throws {
        let session = try session()
        XCTAssertEqual(
            NetworkSwitches.summary(of: session.world, in: .english),
            "Traffic control \(session.world.isTrafficControlEnabled ? "on" : "off") · "
                + (session.world.passengerRoutingMode == .network ? "network routes" : "direct routes only")
                + " · standard service day"
        )
        XCTAssertEqual(NetworkSwitches.forSaleTitle(count: 2, in: .traditionalChinese), "可收購的真實路線（2）")
        XCTAssertEqual(NetworkSwitches.forSaleTitle(count: 0, in: .english), "Real lines for sale")
    }

    // MARK: - Groups and lines that need a look (decision 481, later)

    func testALongListGroupsItsLinesByKindInAFixedOrder() throws {
        let session = try session()
        var world = session.world
        world.enableFreight()
        try world.createLine(named: "Freight", stops: [StationID(rawValue: 1), StationID(rawValue: 4)])
        let freight = try XCTUnwrap(world.lines.last).id
        try world.setLineFreight(freight, to: true)
        try world.setLinePerformance(Self.second, to: .highSpeed)
        let groups = world.lineGroups(world.lines.reversed())
        XCTAssertEqual(groups.map(\.group), [.own, .highSpeed, .freight], "the list's order, empty groups left out")
        XCTAssertEqual(groups.map { $0.lines.map(\.name) }, [["Main"], ["Short"], ["Freight"]])
        XCTAssertEqual(LineGroup.highSpeed.title(in: .traditionalChinese), "高鐵")
        XCTAssertEqual(LineGroup.acquired.title(in: .traditionalChinese), "收購的路線")

        XCTAssertEqual(LineGroup.folded(from: "freight,nonsense,own"), [.own, .freight], "an unknown name is left out")
        XCTAssertEqual(LineGroup.stored([.freight, .own]), "own,freight")
        XCTAssertEqual(LineGroup.folded(from: ""), [])
    }

    func testALineWithoutTrainsOrLosingMoneyNeedsALook() throws {
        var world = try session().world
        let main = try XCTUnwrap(world.line(id: Self.first))
        XCTAssertEqual(world.lineAttention(main), [.noTrains])
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch(), filter: .attention).map(\.name), ["Main", "Short"])

        // A day on: still no trains, so no fares, and both lose money.
        try world.advance(ticks: 1_440 + 120)
        let reasons = world.lineAttention(try XCTUnwrap(world.line(id: Self.first)))
        XCTAssertEqual(reasons.first, .noTrains)
        if world.lineAccounts != nil {
            XCTAssertEqual(reasons, [.noTrains, .losing])
        }
        XCTAssertEqual(LineAttention.label([.noTrains, .losing], in: .traditionalChinese), "需要注意：沒有列車、昨日虧損")
        XCTAssertEqual(LineAttention.label([.overfull], in: .english), "Needs attention: a train was over full")
        XCTAssertNil(LineAttention.label([], in: .english))
        XCTAssertEqual(LineFilter.attention.displayName(in: .traditionalChinese), "需要注意")
    }

    // MARK: - Decision 486: the controls over the list

    func testAShortPanelPutsTheControlsInOneRowThatScrollsAway() {
        XCTAssertEqual(LinesListControls.style(compactHeight: true), .inline)
        XCTAssertEqual(LinesListControls.style(compactHeight: false), .pinned)
    }

    func testTheInlineSearchFieldShowsOnceOpenedAndWhileSomethingIsTyped() {
        let empty = ListSearch()
        let typed = ListSearch("Ji")
        XCTAssertTrue(LinesListControls.pinned.showsSearchField(opened: false, search: empty))
        XCTAssertFalse(LinesListControls.inline.showsSearchField(opened: false, search: empty))
        XCTAssertTrue(LinesListControls.inline.showsSearchField(opened: true, search: empty))
        // A search under way keeps its field, so the rows it hides can be
        // brought back.
        XCTAssertTrue(LinesListControls.inline.showsSearchField(opened: false, search: typed))
    }

    func testTheInlineSortSaysOnlyTheOrderAndVoiceOverSaysItIsTheSort() {
        XCTAssertEqual(LinesListControls.sortTitle(nil, short: false, in: .english), "Sort: Made order")
        XCTAssertEqual(LinesListControls.sortTitle(nil, short: true, in: .traditionalChinese), "建立順序")
        let order = LineReportSort.allCases[0]
        XCTAssertEqual(LinesListControls.sortTitle(order, short: true, in: .english), order.displayName(in: .english))
        XCTAssertEqual(LinesListControls.sortLabel(order, in: .traditionalChinese), "排序：\(order.displayName(in: .traditionalChinese))")
        XCTAssertEqual(LinesListControls.filterLabel(.losing, in: .traditionalChinese), "顯示：只看虧損")
    }
}
