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

    /// The frames are the screen's, and a layout's bounds may start
    /// elsewhere: the card is placed in the bounds' coordinates.
    func testTheCardIsPlacedInTheBoundsCoordinates() {
        let placement = TutorialCardPlacement(target: Self.networkTool, controls: Self.hud, required: [Self.networkTool], map: nil)
        let atOrigin = placement.frame(in: Self.screen, measure: Self.foldedCard)
        let moved = placement.frame(in: Frame(x: 40, y: 30, width: Self.screen.width, height: Self.screen.height), measure: Self.foldedCard)
        XCTAssertEqual(moved, Frame(x: atOrigin.x + 40, y: atOrigin.y + 30, width: atOrigin.width, height: atOrigin.height))
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
