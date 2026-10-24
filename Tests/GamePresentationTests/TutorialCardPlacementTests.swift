import GamePresentation
import XCTest

private typealias Frame = TutorialCardPlacement.Frame
private typealias Size = TutorialCardPlacement.Size

/// Where the tutorial's card goes on a phone held on its side (decision
/// 106), the screen of the owner's device report of 2026-10-12: at the line
/// step the card stood over the lines panel, Pick on Map and Create Line
/// could not be tapped, and Next never came. The frames are that screen's,
/// an iPhone of 874 × 402 points with its safe area (62 points each side,
/// 21 below), measured from the screenshots, in the game screen's
/// coordinates (inside the safe area: 750 × 381).
final class TutorialCardPlacementTests: XCTestCase {
    /// The game screen inside the safe area.
    private static let screen = Frame(x: 0, y: 0, width: 750, height: 381)

    // The HUD, the tools and the dock: always on screen in the tutorial.
    private static let cash = Frame(x: 28, y: 15, width: 115, height: 40)
    private static let speed = Frame(x: 399, y: 15, width: 91, height: 40)
    private static let menu = Frame(x: 572, y: 15, width: 39, height: 40)
    private static let networkTool = Frame(x: 13, y: 73, width: 65, height: 41)
    private static let tools = [
        networkTool,
        Frame(x: 13, y: 118, width: 65, height: 39),
        Frame(x: 13, y: 162, width: 65, height: 39),
        Frame(x: 13, y: 205, width: 65, height: 40),
    ]
    private static let linesButton = Frame(x: 82, y: 311, width: 48, height: 51)

    // The details card at the trailing side, with the network tool's options.
    private static let detailsCard = Frame(x: 440, y: 69, width: 300, height: 270)
    private static let networkModes = Frame(x: 455, y: 155, width: 270, height: 31)
    private static let actionButton = Frame(x: 455, y: 282, width: 270, height: 44)
    private static let zoomBesideCard = Frame(x: 327, y: 234, width: 89, height: 43)
    /// The map the pill, the tools, the dock and the details card leave.
    private static let mapBesideCard = Frame(x: 81, y: 59, width: 359, height: 243)

    // The lines panel beside the map instead (decision 106).
    private static let sidePanel = Frame(x: 365, y: 69, width: 375, height: 302)
    private static let linePick = Frame(x: 381, y: 175, width: 343, height: 44)
    private static let lineCreate = Frame(x: 381, y: 311, width: 343, height: 44)
    private static let zoomBesidePanel = Frame(x: 252, y: 234, width: 89, height: 43)
    private static let mapBesidePanel = Frame(x: 81, y: 59, width: 284, height: 243)

    // The map steps on a phone with the details card folded (decision 188),
    // from the accessibility tree of a UI test run (38259103200) on that
    // phone: the map to the trailing edge, the zoom buttons down beside the
    // dock, the Map Layers button and the dock.
    private static let mapAlone = Frame(x: 82, y: 60, width: 668, height: 242)
    private static let zoomAlone = Frame(x: 637.7, y: 314, width: 88.3, height: 44)
    private static let layers = Frame(x: 94, y: 246, width: 44, height: 44)
    private static let dock = [
        Frame(x: 21, y: 313, width: 48, height: 48),
        Frame(x: 83, y: 313, width: 48, height: 48),
        Frame(x: 137, y: 313, width: 48, height: 48),
    ]
    /// The middle of the screen, where the map opens on the town to build in.
    private static let screenCentre = Frame(x: 365, y: 191, width: 20, height: 20)

    /// The line step's card as the device laid it out: 278 points tall at
    /// 340 wide, its explanation four lines of about 20 points. Narrower,
    /// it wraps to more lines; offered less height than it needs, its
    /// explanation scrolls, down to its title and buttons.
    private static func lineStepCard(_ proposal: Size) -> Size {
        let lines = (1_200 / (proposal.width - 32)).rounded(.up)
        let height = 198 + lines * 20
        return Size(width: proposal.width, height: max(150, min(height, proposal.height)))
    }

    /// The card folded to its title.
    private static func foldedCard(_ proposal: Size) -> Size {
        Size(width: min(230, proposal.width), height: 48)
    }

    private static var hud: [Frame] { [cash, speed, menu] + tools + [linesButton] }

    /// The line step with the lines panel open, before this fix: neither
    /// the panel nor its buttons were known to the card, which went over
    /// them, as on the device.
    func testTheLineStepCoveredTheLinesPanelBeforeThePanelWasKnown() {
        let placement = TutorialCardPlacement(
            target: Self.linesButton, controls: Self.hud + [Self.zoomBesidePanel], required: [Self.linesButton], map: Self.mapBesidePanel
        )
        let card = placement.frame(in: Self.screen, measure: Self.lineStepCard)
        XCTAssertTrue(card.intersects(Self.linePick) || card.intersects(Self.lineCreate), "card \(card)")
    }

    /// The line step with the lines panel open: whatever the card shows,
    /// open or folded, it keeps clear of the panel, so Pick on Map and
    /// Create Line stay free, and of the Lines button. The panel's buttons
    /// may be known (reported through the screen state) or not (marks do
    /// not leave its NavigationStack: the card covered Pick on Map by 15
    /// points in the first CI run of this fix, run 38243536829), both at
    /// the card's widths on a phone (320) and elsewhere (340).
    func testTheLineStepKeepsTheLinesPanelFree() {
        for buttonsKnown in [true, false] {
            for maxWidth in [320.0, 340] {
                let buttons = buttonsKnown ? [Self.linePick, Self.lineCreate] : []
                let placement = TutorialCardPlacement(
                    target: Self.linesButton,
                    controls: Self.hud + [Self.zoomBesidePanel] + buttons,
                    panels: [Self.sidePanel],
                    required: [Self.linesButton] + buttons,
                    map: Self.mapBesidePanel,
                    maxWidth: maxWidth
                )
                let shown = Self.shownCard(placement)
                let context = "buttons known: \(buttonsKnown), width \(maxWidth): card \(shown)"
                for control in [Self.linesButton, Self.linePick, Self.lineCreate, Self.sidePanel] {
                    XCTAssertFalse(shown.intersects(control), "\(context) covers \(control)")
                }
                XCTAssertTrue(placement.leavesStepFree(shown), context)
            }
        }
    }

    /// The line's stations step on that phone, with the lines panel open
    /// (run 38307741519, the whole tutorial walked on the Simulator): the
    /// player's two stations, where the walk built them, as the touch they
    /// take (``NetworkBuilding/touchRadius`` round each), and the card the
    /// map steps take there, 164 points tall.
    private static let lineStations = [
        Frame(x: 140, y: 197, width: 48, height: 48),
        Frame(x: 255, y: 197, width: 48, height: 48),
    ]

    private static func mapStepCard(_ proposal: Size) -> Size {
        Size(width: proposal.width, height: min(164, proposal.height))
    }

    private static func lineStationsStep(stationsKnown: Bool) -> TutorialCardPlacement {
        TutorialCardPlacement(
            target: mapBesidePanel,
            controls: hud + [zoomBesidePanel, linePick],
            panels: [sidePanel],
            required: [],
            sites: stationsKnown ? lineStations : [],
            map: mapBesidePanel,
            maxWidth: 320
        )
    }

    /// Before the stations were known to it, the card went to the bottom of
    /// the strip of map beside the lines panel, over both stations, and
    /// stayed open: the player could not pick them.
    func testTheLineStationsStepCoveredTheStationsBeforeTheyWereKnown() {
        let placement = Self.lineStationsStep(stationsKnown: false)
        let open = placement.frame(in: Self.screen, measure: Self.mapStepCard)
        XCTAssertTrue(placement.leavesStepFree(open), "open \(open)")
        XCTAssertTrue(Self.lineStations.contains { open.intersects($0) }, "open \(open)")
    }

    /// Decision 188, later fix: the stations the step has the player tap are
    /// the step's own (``GameSession/tutorialPlacesToTap``). The card keeps
    /// clear of them or, where it cannot, folds, and folded it covers
    /// neither them nor the lines panel.
    func testTheLineStationsStepKeepsThePlayersStationsFree() {
        let placement = Self.lineStationsStep(stationsKnown: true)
        let open = placement.frame(in: Self.screen, measure: Self.mapStepCard)
        let shown = placement.leavesStepFree(open) ? open : placement.frame(in: Self.screen, measure: Self.foldedCard)
        for covered in Self.lineStations + [Self.sidePanel, Self.linePick] {
            XCTAssertFalse(shown.intersects(covered), "card \(shown) (open \(open)) covers \(covered)")
        }
        XCTAssertTrue(placement.leavesStepFree(shown), "card \(shown)")
    }

    /// The line's stations step with the map dragged `dx` points (the
    /// review of #457): the stations move with it, and only what of them
    /// shows on the map is kept free, as the app reports them.
    private static func draggedLineStationsStep(_ dx: Double) -> TutorialCardPlacement {
        let stations = [Frame(x: 300 + dx, y: 130, width: 48, height: 48), Frame(x: 330 + dx, y: 250, width: 48, height: 48)]
        let shown = stations.compactMap { station -> Frame? in
            let map = mapBesidePanel
            let x = max(station.minX, map.minX), y = max(station.minY, map.minY)
            let width = min(station.maxX, map.maxX) - x, height = min(station.maxY, map.maxY) - y
            return width > 0 && height > 0 ? Frame(x: x, y: y, width: width, height: height) : nil
        }
        return TutorialCardPlacement(
            target: mapBesidePanel,
            controls: hud + [zoomBesidePanel, linePick],
            panels: [sidePanel],
            required: [],
            sites: shown,
            map: mapBesidePanel,
            maxWidth: 320
        )
    }

    /// The map dragged at the line's stations step: a station slides under
    /// the card while the cheapest place for it stays where it is, so the
    /// card's own frame does not change, which was all that made it check
    /// whether it covered anything (the review of #457, dx −40 to −140).
    func testDraggingTheMapSlidesAStationUnderACardThatDoesNotMove() {
        var found = false
        var previous: (frame: Frame, free: Bool)?
        for dx in stride(from: 0.0, through: -140, by: -2) {
            let placement = Self.draggedLineStationsStep(dx)
            let frame = placement.frame(in: Self.screen, measure: Self.mapStepCard)
            let free = placement.leavesStepFree(frame)
            if let previous, previous.frame == frame, previous.free, !free { found = true }
            previous = (frame, free)
        }
        XCTAssertTrue(found, "no drag left the card in place over a station")
    }

    /// Decision 188, later fix: the card folds itself as the app drives it
    /// (``TutorialCardFold``), told of the screen on every frame of the drag
    /// and of the open card's place when it changes. Wherever the drag goes,
    /// right until a station leaves the map and back left past the card, the
    /// card shown, open or folded, covers no station; and once folded it does
    /// not open again while the screen stays the same, though stations go in
    /// and out of view (a folded card opened and folded again as they did).
    func testACardFoldsWhenTheMapIsDraggedUnderItAndStaysFolded() {
        // Straight left from where the open card is clear of the stations
        // (dx −10; at 0 it covers one and folds at once), the review's drag,
        // and right until a station leaves the map, then back left.
        let drags = [
            Array(stride(from: -10.0, through: -140, by: -2)),
            Array(stride(from: 0.0, through: 100, by: 2)) + Array(stride(from: 100.0, through: -140, by: -2))
                + Array(stride(from: -140.0, through: 0, by: 2)),
        ]
        for drag in drags {
            var fold = TutorialCardFold()
            var openFrame: Frame?
            var wasFolded = false
            var reopened = 0
            var everFolded = false
            for dx in drag {
                let placement = Self.draggedLineStationsStep(dx)
                fold.screenChanged(to: placement, in: Self.screen, mayFold: true)
                if fold.isFolded {
                    // The open card is gone.
                    openFrame = nil
                } else {
                    // `onGeometryChange`: the open card reports its place when
                    // it appears or moves.
                    let frame = placement.frame(in: Self.screen, measure: Self.mapStepCard)
                    if frame != openFrame {
                        fold.cardPlaced(at: frame, by: placement, mayFold: true)
                        openFrame = frame
                    }
                }
                if wasFolded, !fold.isFolded { reopened += 1 }
                wasFolded = fold.isFolded
                everFolded = everFolded || fold.isFolded
                let shown = fold.isFolded ? placement.frame(in: Self.screen, measure: Self.foldedCard) : openFrame!
                for station in placement.sites {
                    XCTAssertFalse(shown.intersects(station), "dx \(dx): \(fold.isFolded ? "folded" : "open") card \(shown) covers \(station)")
                }
            }
            XCTAssertTrue(everFolded, "the drag never needed the card folded")
            XCTAssertEqual(reopened, 0, "the folded card opened again while the screen stayed the same")
        }
    }

    /// A new screen (here the lines panel closing: the map widens) opens a
    /// card that folded itself, to see whether it fits now.
    func testANewScreenOpensAFoldedCardAgain() {
        var fold = TutorialCardFold()
        let narrow = Self.draggedLineStationsStep(-60)
        fold.screenChanged(to: narrow, in: Self.screen, mayFold: true)
        let covering = Frame(x: Self.lineStations[0].minX, y: Self.lineStations[0].minY, width: 200, height: 100)
        fold.cardPlaced(at: covering, by: Self.lineStationsStep(stationsKnown: true), mayFold: true)
        XCTAssertTrue(fold.isFolded)
        let wide = TutorialCardPlacement(target: Self.mapAlone, controls: Self.hud, required: [], map: Self.mapAlone, maxWidth: 320)
        fold.screenChanged(to: wide, in: Self.screen, mayFold: true)
        XCTAssertFalse(fold.isFolded)
        // A player's choice, or a done step, never folds it.
        fold.cardPlaced(at: covering, by: Self.lineStationsStep(stationsKnown: true), mayFold: false)
        XCTAssertFalse(fold.isFolded)
    }

    /// Decision 188, later fix (the author, on a phone on its side, found
    /// the open card over the step's controls): the first step's card is
    /// open, so a player who does not want the tutorial finds Skip; from the
    /// second step it is folded to the step and its title, and an action
    /// step, done, stays folded until it moves on; the player opens it to
    /// read the rest.
    func testTheFirstStepIsOpenAndTheRestStartFolded() {
        let first = Tutorial.standardSteps[0]
        XCTAssertEqual(first.id, "build.network")
        XCTAssertNotEqual(first.goal, .read)
        var fold = TutorialCardFold()
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: false, isFirstStep: true))
        XCTAssertTrue(fold.showsFolded(stepChoice: true, chapterChoice: nil, waitsForNext: false, isDone: false, isFirstStep: true))
        // Open over the tool it asks for, it folds itself, as every open card.
        fold.cardPlaced(at: Self.networkTool, by: TutorialCardPlacement(
            target: Self.networkTool, controls: Self.hud, required: [Self.networkTool], map: nil
        ), mayFold: true)
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: false, isFirstStep: true))
        fold = TutorialCardFold()
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: false))
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: true))
        // A chapter the player folded in stays folded.
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: true, waitsForNext: false, isDone: false))
        // Opened on the step, it is open.
        XCTAssertFalse(fold.showsFolded(stepChoice: false, chapterChoice: nil, waitsForNext: false, isDone: false))
    }

    /// The steps to read (the line's card, the ridership and the end) wait for Next, which is
    /// on the open card: they open by themselves, so the tutorial can be
    /// walked to its end without opening the card; and so does a step
    /// reached by Back. Folded on the step, they stay folded.
    func testAStepToReadOpensSoNextShows() {
        let fold = TutorialCardFold()
        let toRead = Tutorial.standardSteps.filter { $0.goal == .read }.map(\.id)
        XCTAssertEqual(toRead, ["line.card.read", "station.ridership", "end"])
        // A step to read is always done.
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: true, isDone: true))
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: true, waitsForNext: true, isDone: true))
        // Reached by Back and undone again, it stays open to be read.
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: true, isDone: false))
        XCTAssertTrue(fold.showsFolded(stepChoice: true, chapterChoice: nil, waitsForNext: true, isDone: true))
    }

    /// Opened earlier in its chapter, the card stays open on the chapter's
    /// next steps, but folds itself where it would cover what one asks for;
    /// opened on the step itself, it stays open.
    func testACardOpenedInTheChapterFoldsItselfOverTheStep() {
        var fold = TutorialCardFold()
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: false, waitsForNext: false, isDone: false))
        let placement = Self.lineStationsStep(stationsKnown: true)
        let covering = Frame(x: Self.lineStations[0].minX, y: Self.lineStations[0].minY, width: 200, height: 100)
        fold.cardPlaced(at: covering, by: placement, mayFold: TutorialCardFold.mayFold(stepChoice: nil, isDone: false))
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: false, waitsForNext: false, isDone: false))
        XCTAssertFalse(TutorialCardFold.mayFold(stepChoice: false, isDone: false), "the player's choice on the step holds")
        XCTAssertFalse(TutorialCardFold.mayFold(stepChoice: nil, isDone: true), "a done step does not fold")
        XCTAssertFalse(fold.showsFolded(stepChoice: false, chapterChoice: false, waitsForNext: false, isDone: false))
    }

    /// The steps before it, with the details card open: nothing the step
    /// asks for is covered and the card stays open (it is not folded), as
    /// the UI tests check on the Simulator.
    func testTheBuildingStepsKeepTheirControlsFreeWithTheCardOpen() {
        let steps: [(name: String, target: Frame, required: [Frame], map: Bool)] = [
            ("build.network", Self.networkTool, [Self.networkTool], false),
            ("track.draw", Self.mapBesideCard, [Self.actionButton], true),
            ("map.move", Self.mapBesideCard, [Self.zoomBesideCard], true),
            ("station.mode", Self.networkModes, [Self.networkModes], true),
        ]
        for step in steps {
            let placement = TutorialCardPlacement(
                target: step.target,
                controls: Self.hud + [Self.zoomBesideCard, Self.networkModes, Self.actionButton],
                backdrops: [Self.detailsCard],
                required: step.required,
                map: Self.mapBesideCard
            )
            let card = placement.frame(in: Self.screen, measure: Self.lineStepCard)
            XCTAssertTrue(placement.leavesStepFree(card), "\(step.name): card \(card)")
            for control in step.required {
                XCTAssertFalse(card.intersects(control), "\(step.name): card \(card) covers \(control)")
            }
        }
    }

    /// A read step beside a panel (decision 188: the ridership step, the
    /// station's panel open beside the map), placed with no map to leave
    /// free: the card stays open and leaves the panel in sight.
    func testAReadStepBesideAPanelLeavesThePanelInSight() {
        for maxWidth in [320.0, 340] {
            let placement = TutorialCardPlacement(
                target: Self.sidePanel,
                controls: Self.hud + [Self.zoomBesidePanel],
                panels: [Self.sidePanel],
                required: [Self.sidePanel],
                map: nil,
                maxWidth: maxWidth
            )
            let card = placement.frame(in: Self.screen, measure: Self.lineStepCard)
            XCTAssertFalse(card.intersects(Self.sidePanel), "width \(maxWidth): card \(card)")
            XCTAssertTrue(placement.leavesStepFree(card), "width \(maxWidth): card \(card)")
        }
    }

    /// The first step with the largest text (`testLargeTextTutorialNavigation`
    /// in the full lane after #429, run 38249605095): the details card, its
    /// controls marked, is a backdrop, so the tall card covers it rather
    /// than the tool rail, whose Done the player taps. As a panel it pushed
    /// the card over Done. At every text size here, no tool is covered.
    func testWithLargeTextTheCardCoversTheDetailsCardRatherThanTheTools() {
        for scale in [1.0, 1.3, 1.6] {
            let card = { (proposal: Size) -> Size in
                let lines = (600 * scale / (proposal.width - 32)).rounded(.up)
                return Size(width: proposal.width, height: max(200, min(150 * scale + lines * 20 * scale, proposal.height)))
            }
            let placement = TutorialCardPlacement(
                target: Self.networkTool,
                controls: Self.hud + [Self.zoomBesideCard, Self.networkModes, Self.actionButton],
                backdrops: [Self.detailsCard],
                required: [Self.networkTool],
                map: Self.mapBesideCard,
                maxWidth: 320
            )
            let shown = placement.frame(in: Self.screen, measure: card)
            for tool in Self.tools {
                XCTAssertFalse(shown.intersects(tool), "text \(scale)×: card \(shown) covers \(tool)")
            }
            XCTAssertTrue(placement.leavesStepFree(shown), "text \(scale)×: card \(shown)")
        }
    }

    /// A step that has the player tap the map, on a phone with the details
    /// card folded (TestFlight 54.1: the card covered the middle of the
    /// map, where the town is): the card goes to the map's top trailing
    /// corner, clear of the middle of the screen, the HUD, the dock and the
    /// zoom buttons, at the heights the map steps' cards take (a title, a
    /// line or two, the buttons, and a hint or "Skip this step").
    func testAMapStepLeavesTheMiddleOfAPhonesMapFree() {
        for height in [150.0, 190, 218] {
            let card = { (proposal: Size) in Size(width: proposal.width, height: min(height, proposal.height)) }
            let controls = Self.hud + Self.dock + [Self.zoomAlone, Self.layers]
            let placement = TutorialCardPlacement(
                target: Self.mapAlone, controls: controls, required: [], map: Self.mapAlone, maxWidth: 320
            )
            let shown = placement.frame(in: Self.screen, measure: card)
            let context = "height \(height): card \(shown)"
            XCTAssertFalse(shown.intersects(Self.screenCentre), "\(context) covers the middle of the screen")
            for control in controls {
                XCTAssertFalse(shown.intersects(control), "\(context) covers \(control)")
            }
            XCTAssertTrue(placement.leavesStepFree(shown), context)
            XCTAssertGreaterThan(shown.midX, Self.mapAlone.midX, "\(context) is at the trailing side")
        }
    }

    /// On a phone on its side the open card is measured no taller than
    /// ``TutorialCardPlacement/compactMaxHeight``, its explanation
    /// scrolling, so most of the map shows beside it (a player's report on
    /// 59.1: the card left too little of the map to see what happened).
    func testOnAPhoneOnItsSideTheCardIsShortSoTheMapShows() {
        var proposals: [Size] = []
        let card = { (proposal: Size) -> Size in
            proposals.append(proposal)
            return Self.lineStepCard(proposal)
        }
        let controls = Self.hud + Self.dock + [Self.zoomAlone, Self.layers]
        let placement = TutorialCardPlacement(
            target: Self.mapAlone, controls: controls, required: [], map: Self.mapAlone, maxWidth: 320,
            maxHeight: TutorialCardPlacement.compactMaxHeight
        )
        let shown = placement.frame(in: Self.screen, measure: card)
        XCTAssertFalse(proposals.isEmpty)
        for proposal in proposals {
            XCTAssertLessThanOrEqual(proposal.height, TutorialCardPlacement.compactMaxHeight)
        }
        XCTAssertLessThanOrEqual(shown.height, TutorialCardPlacement.compactMaxHeight)
        XCTAssertTrue(placement.leavesStepFree(shown), "card \(shown)")
        // Not on a phone held upright or an iPad: measured as tall as it needs.
        let tall = TutorialCardPlacement(target: Self.mapAlone, controls: controls, required: [], map: Self.mapAlone, maxWidth: 320)
        XCTAssertGreaterThan(tall.frame(in: Self.screen, measure: Self.lineStepCard).height, TutorialCardPlacement.compactMaxHeight)
    }

    /// Folded, the card finds a free place on every screen of the tutorial.
    func testTheFoldedCardAlwaysFindsAFreePlace() {
        let screens: [TutorialCardPlacement] = [
            TutorialCardPlacement(
                target: Self.linesButton,
                controls: Self.hud + [Self.zoomBesidePanel],
                panels: [Self.sidePanel],
                required: [Self.linesButton],
                map: Self.mapBesidePanel
            ),
            TutorialCardPlacement(
                target: Self.mapBesideCard,
                controls: Self.hud + [Self.zoomBesideCard, Self.networkModes, Self.actionButton],
                backdrops: [Self.detailsCard],
                required: [Self.networkModes, Self.actionButton],
                map: Self.mapBesideCard
            ),
        ]
        for placement in screens {
            let folded = placement.frame(in: Self.screen, measure: Self.foldedCard)
            XCTAssertTrue(placement.leavesStepFree(folded), "folded \(folded)")
            for control in placement.controls + placement.panels + placement.backdrops {
                XCTAssertFalse(folded.intersects(control), "folded \(folded) covers \(control)")
            }
        }
    }

    /// The map step on that phone, folded: the pill beside the zoom
    /// buttons, which the step asks for.
    private static var mapMoveStep: TutorialCardPlacement {
        TutorialCardPlacement(
            target: zoomAlone, controls: hud + dock + [zoomAlone, layers], required: [zoomAlone], map: mapAlone
        ).folded
    }

    /// The folded pill narrows when "Skip this step" goes, the step done
    /// (main 947c23a's full lane, run 40093122899: 334 points wide with it,
    /// the touch at its leading end fell on the map). Placed afresh it is
    /// centred again and its leading end moves; placed where it stood
    /// (``TutorialCardPlacement/previous``), its leading end, the station
    /// master, stays, and a touch there still lands on it.
    func testAFoldedCardThatNarrowsKeepsItsLeadingEnd() {
        let withSkip = { (proposal: Size) in Size(width: min(334, proposal.width), height: 44) }
        let withoutSkip = { (proposal: Size) in Size(width: min(230, proposal.width), height: 44) }
        let placement = Self.mapMoveStep
        let before = placement.frame(in: Self.screen, measure: withSkip)
        XCTAssertTrue(placement.leavesStepFree(before), "pill \(before)")
        let touch = (x: before.minX + before.width * 0.1, y: before.midY)

        let afresh = placement.frame(in: Self.screen, measure: withoutSkip)
        XCTAssertNotEqual(afresh.minX, before.minX, "placed afresh, the narrower pill is centred again")

        var staying = placement
        staying.previous = before
        let after = staying.frame(in: Self.screen, measure: withoutSkip)
        XCTAssertEqual(after.minX, before.minX, "pill \(before) then \(after)")
        XCTAssertEqual(after.minY, before.minY, "pill \(before) then \(after)")
        XCTAssertTrue((after.minX ... after.maxX).contains(touch.x) && (after.minY ... after.maxY).contains(touch.y), "pill \(after), touch \(touch)")
        XCTAssertTrue(staying.leavesStepFree(after), "pill \(after)")
    }

    /// Lesson 5's stretch to make double (decision 378) moves from station
    /// to station as trains pass, and with it the place to tap. Placed
    /// afresh, the card went wherever the newest place left free, every few
    /// seconds; placed where it stood, it stays while it covers none of
    /// them, and moves only off a place that comes under it.
    func testTheCardStaysPutAsThePlaceToTapMovesElsewhere() {
        let controls = Self.hud + Self.dock + [Self.zoomAlone, Self.layers]
        func step(_ site: Frame) -> TutorialCardPlacement {
            TutorialCardPlacement(
                target: Self.mapAlone, controls: controls, required: [], sites: [site], map: Self.mapAlone, maxWidth: 320
            )
        }
        // The stretch by the first station: at the map's top trailing
        // corner, where the card goes first, so it goes elsewhere.
        let first = Frame(x: 560, y: 90, width: 48, height: 48)
        let placed = step(first).frame(in: Self.screen, measure: Self.mapStepCard)
        XCTAssertFalse(placed.intersects(first), "card \(placed)")
        // The stretch by another station, clear of the card.
        let second = Frame(x: 100, y: 240, width: 48, height: 48)
        XCTAssertFalse(placed.intersects(second), "card \(placed)")
        let afresh = step(second).frame(in: Self.screen, measure: Self.mapStepCard)
        XCTAssertNotEqual(afresh, placed, "placed afresh, the card moves to the corner the first stretch had")

        var staying = step(second)
        staying.previous = placed
        XCTAssertEqual(staying.frame(in: Self.screen, measure: Self.mapStepCard), placed)

        // A stretch under the card: it moves off it.
        let under = Frame(x: placed.midX - 24, y: placed.midY - 24, width: 48, height: 48)
        var covering = step(under)
        covering.previous = placed
        let moved = covering.frame(in: Self.screen, measure: Self.mapStepCard)
        XCTAssertFalse(moved.intersects(under), "card \(moved) covers the stretch \(under)")
        XCTAssertTrue(covering.leavesStepFree(moved), "card \(moved)")
    }

    /// The frames are the screen's, and a layout's bounds may start
    /// elsewhere: the card is placed in the bounds' coordinates.
    func testTheCardIsPlacedInTheBoundsCoordinates() {
        let placement = TutorialCardPlacement(target: Self.networkTool, controls: Self.hud, required: [Self.networkTool], map: nil)
        let atOrigin = placement.frame(in: Self.screen, measure: Self.foldedCard)
        let moved = placement.frame(in: Frame(x: 40, y: 30, width: Self.screen.width, height: Self.screen.height), measure: Self.foldedCard)
        XCTAssertEqual(moved, Frame(x: atOrigin.x + 40, y: atOrigin.y + 30, width: atOrigin.width, height: atOrigin.height))
    }

    /// The folded card with a long title and large text, wider than
    /// a phone held upright. Laid out at its own width it ran past the
    /// screen; it is cut to the screen less the margins.
    func testAFoldedCardIsNeverWiderThanTheScreen() {
        let upright = Frame(x: 0, y: 0, width: 375, height: 667)
        let placement = TutorialCardPlacement(target: nil, controls: [], required: [], map: nil)
        // A card that keeps its own width, whatever it is offered (the
        // folded card did: `fixedSize`).
        let stubborn = placement.frame(in: upright) { _ in Size(width: 520, height: 52) }
        XCTAssertLessThanOrEqual(stubborn.width, upright.width - 2 * HUDMargins.edge)
        XCTAssertGreaterThanOrEqual(stubborn.minX, upright.minX)
        XCTAssertLessThanOrEqual(stubborn.maxX, upright.maxX)

        // The folded card offered the screen's width, its title cut short.
        let longTitle = { (proposal: Size) in Size(width: min(520, proposal.width), height: 52) }
        let folded = placement.folded.frame(in: upright, measure: longTitle)
        XCTAssertEqual(folded.width, upright.width - 2 * HUDMargins.edge)
        XCTAssertGreaterThanOrEqual(folded.minX, upright.minX)
        XCTAssertLessThanOrEqual(folded.maxX, upright.maxX)
        // On a wide screen it keeps its whole title, wider than the open
        // card's 340.
        let tablet = Frame(x: 0, y: 0, width: 1_024, height: 768)
        XCTAssertEqual(placement.folded.frame(in: tablet, measure: longTitle).width, 520)
        XCTAssertEqual(placement.frame(in: tablet, measure: longTitle).width, 340)
    }

    /// The folded card is one line: it is never measured narrower to
    /// leave the map free, as the open card is.
    func testTheFoldedCardIsNotNarrowedForTheMap() {
        // A card over the whole of a map it leaves no band of.
        let placement = TutorialCardPlacement(target: Self.screen, controls: [], required: [], map: Self.screen, maxWidth: 2_000)
        let wide = { (proposal: Size) in Size(width: min(700, proposal.width), height: min(330, proposal.height)) }
        var openOffered: [Size] = []
        _ = placement.frame(in: Self.screen) { proposal in
            openOffered.append(proposal)
            return wide(proposal)
        }
        XCTAssertGreaterThan(openOffered.count, 1, "the open card is measured again, shorter or narrower")
        var foldedOffered: [Size] = []
        _ = placement.folded.frame(in: Self.screen) { proposal in
            foldedOffered.append(proposal)
            return wide(proposal)
        }
        XCTAssertEqual(foldedOffered, [Size(width: Self.screen.width - 2 * HUDMargins.edge, height: Self.screen.height - 2 * HUDMargins.edge)])
    }

    /// No target on screen: the middle.
    func testWithoutATargetTheCardIsInTheMiddle() {
        let placement = TutorialCardPlacement(target: nil, controls: Self.hud, required: [], map: nil)
        let card = placement.frame(in: Self.screen, measure: Self.foldedCard)
        XCTAssertEqual(card.midX, Self.screen.midX, accuracy: 0.5)
        XCTAssertEqual(card.midY, Self.screen.midY, accuracy: 0.5)
    }

    /// What the app shows: the card where it goes, or, where it covers what
    /// the step asks for, folded to its title (``TutorialCardPlacement/leavesStepFree(_:)``).
    private static func shownCard(_ placement: TutorialCardPlacement) -> Frame {
        let open = placement.frame(in: screen, measure: lineStepCard)
        return placement.leavesStepFree(open) ? open : placement.frame(in: screen, measure: foldedCard)
    }
}
