import XCTest

/// Decision 388 (86.1): everything that floats over the map keeps the four
/// lines of ``HUDMargins`` (decision 382), on every screen: the map, while
/// building, with a train's card, a station's or a line's panel, following
/// a train in 2D and in 3D and from its cab, a lesson's card, the station
/// master's bubble, the news, settings, help and achievements, on a phone
/// (on its side: it turns no other way) and on an iPad on its side and
/// upright. Each edge that stands near a line stands on it, within a
/// point. Where the lines are is `HUDMarginsTests` on Linux; this reads
/// where the screen put them.
///
/// The lines are read from the screen itself: the leading and top lines
/// from the status bar's corner, the trailing line from the map's corner
/// column, the bottom line from the tools' foot (decision 382). A group's
/// edges are its glass's, read from the element `hudFrameMark` puts behind
/// it under `-ui-testing` (a container's own element is as big as its
/// buttons' touch areas). Every frame read is printed as
/// `ALIGN|screen|element|minX minY maxX maxY`.
///
/// Full lane only (decision 199): a dozen launches. Run by hand with
/// only_testing=RailwayGameUITests/HUDAlignmentUITests and
/// only_testing_ipad for the iPad's.
@MainActor
final class HUDAlignmentUITests: XCTestCase {
    /// How far an edge may stand from its line.
    private let tolerance: CGFloat = 1
    /// An edge nearer its line than this is meant to stand on it: the
    /// margin is 10 points, so a control 6 points off (16, a plain
    /// padding) is caught, and one beside another control (10 more) is not.
    private let near: CGFloat = 8

    private var app: XCUIApplication!

    nonisolated override func setUp() {
        super.setUp()
        // Every edge of a screen is worth reporting, not only the first.
        continueAfterFailure = true
        // Two launches a test, each way the device is held.
        executionTimeAllowance = 600
    }

    /// Closes the app and stands the device upright again, as the other
    /// tests expect it.
    private func finish() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - The screens

    func testTheMapKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            checkTheMap(lines, way)
        }
    }

    func testBuildingKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            tap("dock.build")
            XCTAssertTrue(app.buttons["tool.network"].appears(within: 10), "\(way): the building tools open")
            app.buttons["tool.network"].waitUntilSettled()
            let screen = "\(way) building"
            leading(["hud.tools", "hud.rail"], on: lines, screen)
            if let rail = read("hud.rail", screen) {
                edgesNearTheLines(rail, "the rail", on: lines, screen)
            }
            trailing(["hud.card", "map.corner"], on: lines, screen)
        }
    }

    func testATrainsCardKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            pickTrainOne()
            let card = element("details.card")
            XCTAssertTrue(card.appears(within: 10), "\(way): the train's card opens")
            card.waitUntilStill()
            let screen = "\(way) train card"
            underTheBar(["hud.card"], on: lines, screen)
            trailing(["hud.card"], on: lines, screen)
        }
    }

    func testAStationsPanelKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            guard let point = stationPoints().first else {
                XCTFail("\(way): no station on the map")
                continue
            }
            // A hold selects the station even with a train over it.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
                .press(forDuration: 1)
            XCTAssertTrue(element("station.operations").appears(within: 10), "\(way): the station's panel opens")
            checkPanel("\(way) station panel", lines)
        }
    }

    func testTheLinesPanelKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            tap("entry.lines")
            XCTAssertTrue(app.navigationBars["Lines"].appears(within: 10), "\(way): the lines panel opens")
            checkPanel("\(way) lines panel", lines)
        }
    }

    func testFollowingATrainKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            followTrainOne()
            let bar = element("follow.bar")
            XCTAssertTrue(bar.appears(within: 10), "\(way): the follow bar shows")
            bar.waitUntilStill()
            let screen = "\(way) following"
            guard let follow = read("follow.bar", screen) else { continue }
            if let strip = read("map.quickLayer.strip", screen) {
                // Beside the layer strip, a margin after it, on its row.
                expect(strip.minX, lines.leading, "the layer strip's leading edge", screen)
                expect(follow.minX, strip.maxX + 10, "the follow bar a margin after the strip", screen)
                expect(follow.midY, strip.midY, "the follow bar on the strip's row", screen)
            } else {
                expect(follow.minX, lines.leading, "the follow bar's leading edge", screen)
            }
            expect(follow.minY, (read("hud.bar", screen)?.maxY ?? lines.top) + 10, "the follow bar a margin under the status bar", screen)
        }
    }

    func testThe3DMapKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            tap("map.open3D")
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 20), "\(way): the 3D map opens")
            app.buttons["map3D.close"].waitUntilSettled()
            check3D("\(way) 3D", lines)
        }
    }

    func testFollowingIn3DAndFromTheCabKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            followTrainOne()
            // The bar beside the layer strip gives way down to the badge
            // and the stop where it is narrow (decision 251), the 3D
            // button with the rest: a trade-off, not an edge.
            guard app.buttons["follow.map3D"].appears(within: 10) else {
                print("ALIGN|\(way) following|follow.map3D|no room")
                continue
            }
            tap("follow.map3D")
            let bar = element("map3D.followBar")
            XCTAssertTrue(bar.appears(within: 20), "\(way): the 3D follow bar shows")
            bar.waitUntilStill()
            check3D("\(way) 3D following", lines)
            followBar3D("\(way) 3D following", lines)
            // Decision 403 (續): beside the train and from the station too;
            // five buttons, in one row or two, all reachable.
            for view in ["cab", "side", "station"] {
                let button = app.buttons["map3D.follow.\(view)"]
                if button.becomesHittable(within: 5) {
                    button.tap()
                    bar.waitUntilStill()
                    check3D("\(way) \(view)", lines)
                    followBar3D("\(way) \(view)", lines)
                } else {
                    XCTFail("\(way): no \(view) view to follow from")
                }
            }
            // Decision 403 (續二): the horn and the photo, whose sheet has
            // the share button.
            let horn = app.buttons["map3D.follow.horn"]
            XCTAssertTrue(horn.becomesHittable(within: 5), "\(way): the horn button is reachable")
            horn.tap()
            let photo = app.buttons["map3D.follow.photo"]
            XCTAssertTrue(photo.becomesHittable(within: 5), "\(way): the photo button is reachable")
            photo.tap()
            XCTAssertTrue(app.buttons["map3D.snapshot.share"].appears(within: 15), "\(way): the photo's sheet offers to share it")
            app.buttons["map3D.snapshot.done"].tap()
            XCTAssertTrue(app.buttons["map3D.snapshot.share"].disappears(within: 10), "\(way): and closes")
        }
    }

    func testTheStationMastersBubbleKeepsTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            tap("stationMaster")
            let bubble = element("stationMaster.bubble")
            XCTAssertTrue(bubble.appears(within: 10), "\(way): the bubble shows")
            bubble.waitUntilStill()
            let screen = "\(way) station master"
            // The bubble first: it speaks for 7 s from the tap, and a slow
            // runner's reads of the avatar and its title took until 8 s
            // after it, when the bubble had gone (main a2f0ef9's full
            // lane, run 40160679685).
            let frame = read("stationMaster.bubble", screen)
            _ = read("stationMaster", screen)
            _ = read("stationMaster.title", screen)
            if let frame {
                // It speaks on the bottom row, beside the avatar.
                expect(frame.maxY, lines.bottom, "the bubble's foot", screen)
                edgesNearTheLines(frame, "the bubble", on: lines, screen)
            }
        }
    }

    func testALessonsCardKeepsTheLines() {
        defer { finish() }
        for way in ways {
            launch(way, ["-tutorial-step", "line.open"])
            let card = element("tutorial.card")
            let folded = app.buttons["tutorial.unfold"]
            XCTAssertTrue(element("map").appears(within: 30), "\(way): the lesson's map opens")
            if !card.appears(within: 15), folded.exists {
                folded.tap()
            }
            XCTAssertTrue(card.appears(within: 15), "\(way): the lesson's card shows")
            card.waitUntilStill()
            let screen = "\(way) lesson card"
            let lines = readLines(screen)
            if let frame = read("tutorial.card", screen) {
                edgesNearTheLines(frame, "the lesson's card", on: lines, screen)
            }
        }
    }

    func testTheNewsSettingsHelpAndAchievementsKeepTheLines() {
        defer { finish() }
        for way in ways {
            let lines = openDemo(way)
            tap("hud.news")
            XCTAssertTrue(app.navigationBars["News"].appears(within: 10), "\(way): the news opens")
            checkPanel("\(way) news", lines)
            close(["news.done", "Done"])

            for (item, done) in [("menu.settings", "settings.done"), ("menu.help", "help.done"), ("menu.achievements", "achievements.done")] {
                tap("hud.menu")
                // Help stands on the menu's first row (decision 383), not
                // under More.
                tapHittable(item)
                XCTAssertTrue(app.buttons[done].appears(within: 15), "\(way): \(item) opens")
                checkPanel("\(way) \(item)", lines)
                close([done])
            }
        }
    }

    // MARK: - What each screen keeps

    /// The map with nothing open: the status bar, the tools, the layer
    /// strip, the map's corner column and its leading row, the station
    /// master.
    private func checkTheMap(_ lines: Lines, _ way: Way) {
        let screen = "\(way) map"
        leading(["hud.tools", "map.quickLayer.strip"], on: lines, screen)
        trailing(["map.corner"], on: lines, screen)
        guard let tools = read("hud.tools", screen) else { return }
        // On the bottom row: what stands beside the tools rather than
        // over them.
        for id in ["map.corner", "stationMaster.title"] {
            guard let frame = read(id, screen) else { continue }
            if frame.minX >= tools.maxX - tolerance || frame.maxY > tools.minY + tolerance {
                expect(frame.maxY, lines.bottom, "\(id)'s foot on the bottom line", screen)
            } else {
                expect(frame.maxY, tools.minY - 10, "\(id)'s foot a margin over the tools", screen)
            }
        }
    }

    /// A panel or sheet: beside the map it stands under the status bar,
    /// on the trailing line; a sheet is the system's.
    private func checkPanel(_ screen: String, _ lines: Lines) {
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.appears(within: 10), "\(screen): no navigation bar")
        bar.waitUntilStill()
        log(screen, "navigationBar", bar.frame)
        // Beside the map, the panel's own glass; a sheet is the system's.
        guard let frame = read("hud.panel", screen) else { return }
        expect(frame.maxX, lines.trailing, "the panel's trailing edge", screen)
        if let status = read("hud.bar", screen) {
            expect(frame.minY, status.maxY + 10, "the panel a margin under the status bar", screen)
        }
    }

    /// The 3D map's own controls, on the 2D map's lines (the 3D map hides
    /// the status bar).
    private func check3D(_ screen: String, _ lines: Lines) {
        if let close = read("map3D.close", screen) {
            expect(close.minX, lines.leading, "the 2D button's leading edge", screen)
            expect(close.minY, lines.top, "the 2D button's top", screen)
        }
        let trailingEdge = [read("map3D.stats", screen), read("map3D.speed", screen)].compactMap { $0?.maxX }.max()
        if let trailingEdge {
            expect(trailingEdge, lines.trailing, "the speed's or the frame rate's trailing edge", screen)
        }
        if let speed = read("map3D.speed", screen) {
            expect(speed.minY, lines.top, "the speed's top", screen)
        }
    }

    private func followBar3D(_ screen: String, _ lines: Lines) {
        guard let bar = read("map3D.followBar", screen) else { return }
        expect(bar.maxY, lines.bottom, "the 3D follow bar's foot", screen)
        edgesNearTheLines(bar, "the 3D follow bar", on: lines, screen)
    }

    // MARK: - Lines

    private struct Lines {
        var leading: CGFloat
        var top: CGFloat
        var trailing: CGFloat
        var bottom: CGFloat
    }

    /// The lines as the map screen stands them: the status bar's corner,
    /// the map's corner column's trailing edge and the tools' foot.
    private func readLines(_ screen: String) -> Lines {
        let status = read("hud.bar", screen) ?? .zero
        let tools = read("hud.tools", screen) ?? .zero
        let window = app.windows.firstMatch.frame
        // The corner column's trailing edge, or (where a card or the
        // tutorial put it away) as far from the screen's trailing edge as
        // the status bar is from its leading one.
        let corner = read("map.corner", screen)
        let trailing = corner?.maxX ?? (window.maxX - status.minX)
        XCTAssertNotEqual(status, .zero, "\(screen): no status bar")
        return Lines(leading: status.minX, top: status.minY, trailing: trailing, bottom: tools.maxY)
    }

    private func leading(_ ids: [String], on lines: Lines, _ screen: String) {
        for id in ids {
            guard let frame = read(id, screen) else { continue }
            expect(frame.minX, lines.leading, "\(id)'s leading edge", screen)
        }
    }

    private func trailing(_ ids: [String], on lines: Lines, _ screen: String) {
        for id in ids {
            guard let frame = read(id, screen) else { continue }
            expect(frame.maxX, lines.trailing, "\(id)'s trailing edge", screen)
        }
    }

    private func underTheBar(_ ids: [String], on lines: Lines, _ screen: String) {
        guard let status = read("hud.bar", screen) else { return }
        for id in ids {
            guard let frame = read(id, screen) else { continue }
            expect(frame.minY, status.maxY + 10, "\(id) a margin under the status bar", screen)
        }
    }

    /// Each edge of `frame` near a line stands on it.
    private func edgesNearTheLines(_ frame: CGRect, _ name: String, on lines: Lines, _ screen: String) {
        for (edge, line, side) in [(frame.minX, lines.leading, "leading"), (frame.maxX, lines.trailing, "trailing"),
                                   (frame.minY, lines.top, "top"), (frame.maxY, lines.bottom, "bottom")] {
            let off = abs(edge - line)
            if off > tolerance, off < near {
                XCTFail("\(screen): \(name)'s \(side) edge \(edge) stands \(off) from the \(side) line \(line)")
            }
        }
    }

    private func expect(_ edge: CGFloat, _ line: CGFloat, _ what: String, _ screen: String) {
        XCTAssertLessThanOrEqual(abs(edge - line), tolerance, "\(screen): \(what) is \(edge), the line \(line)")
    }

    // MARK: - Reading the screen

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The frame of `id` on screen, printed; nil when it does not show.
    private func read(_ id: String, _ screen: String) -> CGRect? {
        let found = element(id)
        guard found.exists else {
            print("ALIGN|\(screen)|\(id)|absent")
            return nil
        }
        let frame = found.frame
        guard !frame.isEmpty else { return nil }
        log(screen, id, frame)
        return frame
    }

    private func log(_ screen: String, _ id: String, _ frame: CGRect) {
        let window = app.windows.firstMatch.frame
        print("ALIGN|\(screen)|\(id)|\(frame.minX) \(frame.minY) \(frame.maxX) \(frame.maxY)|window \(window.width)x\(window.height)")
    }

    /// Where the stations are on the map, once it has settled (as
    /// `LineDraftSummaryUITests` reads them).
    private func stationPoints() -> [CGPoint] {
        let readout = element("map.stations")
        XCTAssertTrue(readout.appears(within: 10))
        let map = element("map")
        let deadline = Date().addingTimeInterval(30)
        var last = readout.value as? String ?? ""
        var since = Date()
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            let value = readout.value as? String ?? ""
            if value != last {
                last = value
                since = Date()
            } else if Date().timeIntervalSince(since) >= 0.5 {
                break
            }
        }
        let points = last.split(separator: ";").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return nil }
            return CGPoint(x: map.frame.minX + xy[0], y: map.frame.minY + xy[1])
        }
        // Not under the tools, where a hold would press them.
        let tools = element("hud.tools").frame.insetBy(dx: -20, dy: -20)
        return points.filter { !tools.contains($0) }
    }

    // MARK: - Getting there

    /// One way the device is held, named for the messages: "phone on its
    /// side", "iPad upright".
    private struct Way: CustomStringConvertible {
        var orientation: UIDeviceOrientation
        var description: String
    }

    private var ways: [Way] {
        // The phone turns no other way (project.yml).
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return [Way(orientation: .landscapeLeft, description: "phone on its side")]
        }
        return [
            Way(orientation: .landscapeLeft, description: "iPad on its side"),
            Way(orientation: .portrait, description: "iPad upright"),
        ]
    }

    private func launch(_ way: Way, _ extra: [String] = []) {
        app?.terminate()
        XCUIDevice.shared.orientation = way.orientation
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
    }

    /// The demo map, paused, its lines read off it.
    private func openDemo(_ way: Way) -> Lines {
        launch(way, ["-demo-layout", "-ui-testing-paused"])
        XCTAssertTrue(element("map").appears(within: 30), "\(way): the demo map opens")
        let tools = element("hud.tools")
        XCTAssertTrue(tools.appears(within: 10), "\(way): the tools show")
        tools.waitUntilStill()
        element("hud.bar").waitUntilStill()
        let lines = readLines("\(way) map")
        print("ALIGN|\(way)|lines|\(lines.leading) \(lines.top) \(lines.trailing) \(lines.bottom)")
        return lines
    }

    /// Follows Train 1 from the fleet list (as `MapInteractionTests`).
    private func followTrainOne() {
        tap("dock.build")
        // The press on Build can be cancelled while the app's main thread
        // stalls (the app's trace: "touch cancelled at (100, 344)" after
        // gaps of 12.8 s and 17.9 s between frames; main 12c1235's full
        // lane, run 40085460126), and the tools never open. Tap once more
        // if they did not, as LessonUITests does for Lessons.
        if !app.buttons["tool.train"].appears(within: 10), app.buttons["dock.build"].exists {
            tap("dock.build")
        }
        tap("tool.train")
        let fleet = app.buttons["train.fleetOverview"]
        XCTAssertTrue(fleet.appears(within: 5))
        if !fleet.becomesHittable(within: 1) { app.swipeUp() }
        fleet.tap()
        let follow = app.buttons["fleet.follow.Train 1"]
        XCTAssertTrue(follow.appears(within: 5))
        for _ in 0..<3 where !follow.becomesHittable(within: 1) { app.swipeUp() }
        follow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 5), "Following shows the follow bar")
        let done = app.buttons["tool.select"]
        if done.exists, done.isHittable { done.tap() }
    }

    /// Follows Train 1, lets go and taps it in the middle of the map,
    /// which opens its card.
    private func pickTrainOne() {
        followTrainOne()
        let unfollow = app.buttons["train.unfollow"]
        unfollow.tap()
        XCTAssertTrue(unfollow.disappears(within: 5))
        element("map").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.appears(within: 15), "Missing \(id)")
        button.waitUntilSettled()
        button.tap()
    }

    /// Taps the copy of `id` that can be touched: a native menu can hold
    /// an unplaced copy of an action (as `SettingsUITests`).
    private func tapHittable(_ id: String) {
        let buttons = app.buttons.matching(identifier: id)
        XCTAssertTrue(buttons.firstMatch.appears(within: 15), "Missing \(id)")
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if let button = buttons.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) {
                button.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("\(id) cannot be tapped")
    }

    private func close(_ ids: [String]) {
        for id in ids {
            let button = app.buttons[id].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                XCTAssertTrue(button.disappears(within: 10), "\(id) closes")
                return
            }
        }
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.exists {
            done.tap()
            _ = done.disappears(within: 10)
        }
    }
}
