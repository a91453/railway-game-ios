import GamePresentation
import XCTest

/// Decision 382 (TestFlight 85.1): the controls floating over the map keep
/// one inset inside the safe area, on every side.
final class HUDMarginsTests: XCTestCase {
    /// An iPhone 17 Pro on its side: the camera housing's side and the
    /// other alike in the safe area, the home indicator below.
    private let phone = (screen: ScreenSize(width: 874, height: 402), safe: ScreenInsets(top: 0, leading: 62, bottom: 21, trailing: 62))
    /// An iPad Pro 11-inch on its side and upright.
    private let iPad = (screen: ScreenSize(width: 1194, height: 834), safe: ScreenInsets(top: 24, leading: 0, bottom: 20, trailing: 0))
    private let iPadUpright = (screen: ScreenSize(width: 834, height: 1194), safe: ScreenInsets(top: 24, leading: 0, bottom: 20, trailing: 0))
    /// A phone with the camera housing's side only (a Split View or an
    /// older safe area): the lines follow each side's own inset.
    private let housingOneSide = (screen: ScreenSize(width: 874, height: 402), safe: ScreenInsets(top: 0, leading: 62, bottom: 21, trailing: 0))

    private var screens: [(screen: ScreenSize, safe: ScreenInsets)] { [phone, iPad, iPadUpright, housingOneSide] }

    func testTheStatusBarAndItsMarginsFillTheScreensWidth() {
        for (screen, safe) in screens {
            for band in [0.0, 30] {
                let lines = HUDMargins.lines(screen: screen, safeArea: safe, creditsBand: band)
                XCTAssertEqual(
                    safe.leading + HUDMargins.edge + lines.statusBarMaxWidth + HUDMargins.edge + safe.trailing,
                    screen.width
                )
                // The largest text: a bar that measures wider is held to
                // the lines, not past the trailing one.
                let bar = lines.statusBar(ScreenSize(width: screen.width, height: 80))
                XCTAssertEqual(bar.x, lines.leading)
                XCTAssertEqual(bar.x + bar.width, lines.trailing)
            }
        }
        // The screenshot's phone: 874 wide, 750 between the safe area's
        // sides, 730 for the bar.
        XCTAssertEqual(HUDMargins.lines(screen: phone.screen, safeArea: phone.safe).statusBarMaxWidth, 750 - 20)
    }

    func testTheCardTheOverviewMapAndTheMapsButtonsEndOnTheStatusBarsLine() {
        for (screen, safe) in screens {
            let lines = HUDMargins.lines(screen: screen, safeArea: safe, creditsBand: 30)
            let bar = lines.statusBar(ScreenSize(width: 2000, height: 44))
            // Coverage, 3D and the zoom buttons: 44 + 44 + 12 + 88.
            let buttons = lines.bottomTrailing(ScreenSize(width: 188, height: 44))
            let overview = lines.trailing(ScreenSize(width: 160, height: 110), above: buttons)
            let legend = lines.trailing(ScreenSize(width: 240, height: 180), above: buttons)
            for frame in [buttons, overview, legend] {
                XCTAssertEqual(frame.x + frame.width, bar.x + bar.width)
                XCTAssertEqual(frame.x + frame.width, screen.width - safe.trailing - HUDMargins.edge)
            }
            XCTAssertEqual(overview.y + overview.height + HUDMargins.cornerStackGap, buttons.y)
        }
    }

    func testTheBottomRowStandsOnOneLine() {
        for (screen, safe) in screens {
            for band in [0.0, 30] {
                let lines = HUDMargins.lines(screen: screen, safeArea: safe, creditsBand: band)
                // The tools column's foot (decision 226: 48 + 2 × 4 wide),
                // the expansion button and the station master beside it,
                // and the map's buttons at the trailing end.
                let column = lines.bottomLeading(ScreenSize(width: ToolColumn.width, height: 262))
                let expansion = lines.bottomLeading(ScreenSize(width: 120, height: 44), after: ToolColumn.width + 12)
                let stationMaster = lines.bottomLeading(ScreenSize(width: 52, height: 52), after: 200)
                let buttons = lines.bottomTrailing(ScreenSize(width: 188, height: 44))
                let feet = [column, expansion, stationMaster, buttons].map { $0.y + $0.height }
                XCTAssertEqual(Set(feet), [screen.height - safe.bottom - band - HUDMargins.edge])
                // Clear of the credits' band, which nothing covers.
                XCTAssertLessThanOrEqual(feet[0], screen.height - safe.bottom - band)
            }
        }
    }

    func testTheLeadingLineIsTheColumnsTheStripsAndTheBars() {
        let lines = HUDMargins.lines(screen: phone.screen, safeArea: phone.safe)
        let bar = lines.statusBar(ScreenSize(width: 600, height: 44))
        let column = lines.bottomLeading(ScreenSize(width: ToolColumn.width, height: 262))
        XCTAssertEqual(bar.x, column.x)
        XCTAssertEqual(bar.x, 62 + HUDMargins.edge)
        // The status bar's top, inside the safe area's top.
        XCTAssertEqual(bar.y, HUDMargins.edge)
        // Decision 226's column keeps its width.
        XCTAssertEqual(ToolColumn.width, 56)
    }

    /// TestFlight 83.1 (iPhone 17 on its side, 874 by 402): the opened
    /// legend reached up behind the status bar and the next step. It now
    /// ends an inset under what runs down the top of the map, with the
    /// zoom buttons under it and the corner's foot above the safe area.
    func testTheLegendStaysUnderTheTopOfTheMap() {
        // The status bar and the layer strip, each 44 under a gap of 10;
        // the home indicator's 21 at the foot.
        let top = 10 + 44 + 10 + 44.0, bottom = 21.0
        let height = HUDMargins.legendMaximumHeight(mapHeight: 402, top: top, bottom: bottom, buttons: true)
        XCTAssertEqual(height, 402 - 108 - 10 - (21 + 10 + 44 + 10))
        // Stacked from the foot: the legend's top is an inset under the strip.
        XCTAssertEqual(402 - bottom - HUDMargins.edge - 44 - HUDMargins.cornerStackGap - height, top + HUDMargins.edge)
        // Without the zoom buttons under it (a phone's panel holds them),
        // the legend has their room too.
        XCTAssertEqual(HUDMargins.legendMaximumHeight(mapHeight: 402, top: top, bottom: bottom, buttons: false), height + 44 + HUDMargins.cornerStackGap)
        // Never less than a title and its colour bar.
        XCTAssertEqual(HUDMargins.legendMaximumHeight(mapHeight: 150, top: top, bottom: bottom, buttons: true), 64)
    }
}
