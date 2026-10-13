import UIKit
import XCTest

/// The whole tutorial (decision 188), walked from its first step to its
/// last as a player would: started from the start screen, never from
/// `-tutorial-step`, every step done with the control it points at
/// (NEXT_PRIORITIES_2026-10-12 §2, item 1). On every step the control is
/// in reach and the tutorial's card, open or folded, leaves it free; a
/// step that cannot be done fails with its number, its title and what
/// stood in the way.
///
/// One test for a phone on its side and one for an iPad, each skipped on
/// the other device. Not in the pull request gate: the full lane runs the
/// phone's on its iPhone and the iPad's in its iPad job (ios-build.yml).
@MainActor
final class TutorialJourneyUITests: XCTestCase {
    func testTheWholeTutorialOnAPhoneOnItsSide() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The phone's journey; the iPad walks its own (testTheWholeTutorialOnAnIPad)")
        }
        TutorialJourney(test: self).walk()
    }

    func testTheWholeTutorialOnAnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The iPad's journey; the phone walks its own (testTheWholeTutorialOnAPhoneOnItsSide)")
        }
        TutorialJourney(test: self).walk()
    }
}

/// One walk through the tutorial's 21 steps, in English.
@MainActor
private final class TutorialJourney {
    /// The steps' titles in English, in order (`Tutorial.standardSteps`):
    /// step `n` is `titles[n - 1]`.
    static let titles = [
        "Tap Network",
        "Zoom out to see the town",
        "Tap the start, then the end",
        "Tap ✓ to build the track",
        "Tap Platform",
        "Tap your track near one end",
        "Tap ✓ to build the station",
        "Tap the track near the other end",
        "Tap ✓ for the second station",
        "Tap Lines",
        "Tap one station, then the other",
        "Tap ✓ to create the line",
        "Tap Buy … and Start Service",
        "Tap Done to stop building",
        "Tap \u{25B6}\u{FE0E} to run time",
        "Wait for your first fares",
        "Tap Lines to check your line",
        "Read your line's card",
        "Tap one of your stations",
        "Tap Ridership to see who rides",
        "That's the tour",
    ]

    let test: XCTestCase
    let app = XCUIApplication()
    /// The step the walk is on, from 1.
    private var step = 0
    /// The two ends of the track the walk lays, and the two stations' places
    /// on it, on the screen. The camera stays where the walk left it: only
    /// the zoom buttons move it, and a station already in view is not
    /// centred.
    private var trackStart = CGPoint.zero
    private var trackEnd = CGPoint.zero
    private var firstStation = CGPoint.zero
    private var secondStation = CGPoint.zero

    private var card: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
    }

    private var folded: XCUIElement {
        app.buttons["tutorial.unfold"]
    }

    init(test: XCTestCase) {
        self.test = test
    }

    func walk() {
        test.continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let start = app.buttons["start.tutorial"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "No Tutorial button on the start screen")
        start.tap()

        // Track
        arrive(at: 1)
        tapTool("tool.network")

        arrive(at: 2)
        let zoomOut = app.buttons["Zoom out"]
        check(zoomOut, "the Zoom out button")
        zoomOut.tap()

        arrive(at: 3)
        // Once more, so the stretch the walk lays (it must stay clear of the
        // lines panel, half of a phone's width) is well over 160 m: the
        // track is laid at about 1 m a point once zoomed out, 2 m twice.
        if zoomOut.exists, zoomOut.isHittable, zoomOut.isEnabled {
            zoomOut.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        planTrack()
        check(map: trackStart, "the track's start")
        tap(trackStart)
        // The start is picked: the card asks for the end.
        if card.exists {
            let asksForEnd = card.staticTexts["Now tap where it ends."]
            XCTAssertTrue(asksForEnd.waitForExistence(timeout: 5), failure("the tap at \(trackStart) did not pick the track's start"))
        }
        check(map: trackEnd, "the track's end")
        tap(trackEnd)

        arrive(at: 4)
        tapConfirm("the ✓ that builds the track")

        // Stations
        arrive(at: 5)
        let platform = app.buttons["Platform"]
        check(platform, "the Platform mode")
        platform.tap()

        arrive(at: 6)
        check(map: firstStation, "the first station's place on the track")
        tap(firstStation)

        arrive(at: 7)
        tapConfirm("the ✓ that builds the first station")

        arrive(at: 8)
        check(map: secondStation, "the second station's place on the track")
        tap(secondStation)

        arrive(at: 9)
        tapConfirm("the ✓ that builds the second station")

        // Line
        arrive(at: 10)
        let lines = app.buttons["entry.lines"]
        check(lines, "the Lines button")
        lines.tap()

        arrive(at: 11)
        // The lines panel slides in before the map beside it is tapped.
        XCTAssertTrue(app.buttons["line.draft.pick"].waitForExistence(timeout: 10), failure("the lines panel did not open"))
        Thread.sleep(forTimeInterval: 1)
        check(map: firstStation, "the first station")
        tap(firstStation)
        check(map: secondStation, "the second station")
        tap(secondStation)

        // Decision 100, later: the line is made by the ✓ on the map.
        arrive(at: 12)
        tapConfirm("the ✓ that creates the line")

        // Service
        arrive(at: 13)
        let buy = app.buttons["line.staff.start"]
        check(buy, "Buy … and Start Service")
        buy.tap()

        arrive(at: 14)
        tapTool("tool.select")

        // Done usually sets time running, and the step that asks for it is
        // then passed over (`moveTutorialForward`).
        if arrive(atOneOf: [15, 16]) == 15 {
            let resume = app.buttons["Resume"]
            check(resume, "▶︎ (Resume)")
            resume.tap()
            arrive(at: 16)
        }
        // The step points at the cash and the speed.
        let cash = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Cash")).firstMatch
        check(cash, "the cash")
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed:")).firstMatch
        check(speed, "the speed menu")
        // The first fares come in at an hour's settlement after the trains
        // set off at 06:00; at the speed Done resumes, that is under a
        // minute. If not, the speed menu goes faster, as the hint says.
        if !waitForStep(after: 16, timeout: 60) {
            speed.tap()
            let fastest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "6000 times real time")).firstMatch
            if fastest.waitForExistence(timeout: 5) {
                fastest.tap()
            }
        }

        // The line's card (decision 194): the lines panel, then a step to
        // read over it. Its card comes after the line's first full day, so
        // the panel may show none yet.
        arrive(at: 17, timeout: 180)
        let linesAgain = app.buttons["entry.lines"]
        check(linesAgain, "the Lines button")
        linesAgain.tap()

        arrive(at: 18)
        tapNext(finishing: false)

        // Passengers: the step closes the lines panel.
        arrive(at: 19)
        // Stopped, so the trains stand still while a station is tapped.
        let pause = app.buttons["Pause"]
        if pause.exists, pause.isHittable { pause.tap() }
        check(map: firstStation, "the first station")
        tap(firstStation)

        arrive(at: 20)
        let ridership = app.buttons["inspector.ridership"]
        check(ridership, "the Ridership button")
        ridership.tap()
        // A step to read: Next, once the station's panel is open.
        tapNext(finishing: false)

        arrive(at: 21)
        check(app.buttons["hud.menu"], "the game menu")
        tapNext(finishing: true)
        XCTAssertTrue(card.waitForNonExistence(timeout: 10), failure("Finish did not end the tutorial"))
        XCTAssertFalse(folded.exists, failure("Finish left the folded card"))
    }

    // MARK: - Steps

    /// Waits for step `number`, on the card or its folded pill, and fails
    /// with what is shown instead.
    @discardableResult
    private func arrive(at number: Int, timeout: TimeInterval = 15) -> Int {
        arrive(atOneOf: [number], timeout: timeout)
    }

    private func arrive(atOneOf numbers: [Int], timeout: TimeInterval = 15) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let shown = shownStep(), numbers.contains(shown) {
                step = shown
                // The card settles where it goes for the step.
                Thread.sleep(forTimeInterval: 0.5)
                return shown
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        let wanted = numbers.map { "\($0) “\(Self.titles[$0 - 1])”" }.joined(separator: " or ")
        XCTFail("Stuck after step \(step) “\(step > 0 ? Self.titles[step - 1] : "start")”: step \(wanted) never came. \(onScreen())")
        return 0
    }

    /// Whether the tutorial moved past step `number` within `timeout`.
    private func waitForStep(after number: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let shown = shownStep(), shown > number { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    /// The step on the card or its folded pill, from 1. Each is read from a
    /// snapshot, nil when it is gone: a card that folded between `exists`
    /// and `label` failed the label's lookup.
    private func shownStep() -> Int? {
        if let title = try? app.staticTexts["tutorial.title"].firstMatch.snapshot(),
           let index = Self.titles.firstIndex(of: title.label) {
            return index + 1
        }
        if let pill = try? folded.firstMatch.snapshot(),
           let index = Self.titles.firstIndex(where: { pill.label.hasSuffix(": " + $0) }) {
            return index + 1
        }
        return nil
    }

    /// Checks that `element`, what the step asks the player to tap, is in
    /// reach and that the card, open or folded, leaves it free. A card that
    /// is still moving to its place, or folding itself, has a few seconds.
    private func check(_ element: XCUIElement, _ name: String, onCard: Bool = false) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), failure("\(name) is not on the screen"))
        let deadline = Date().addingTimeInterval(10)
        var covering: String?
        repeat {
            // The card's own buttons are on it: only whether they can be
            // tapped counts.
            covering = element.exists && !onCard ? coveringCard(element.frame) : nil
            if element.exists, element.isHittable, covering == nil { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        let frame = element.exists ? "\(element.frame)" : "gone"
        if let covering {
            XCTFail(failure("\(covering) covers \(name) (\(frame))"))
        } else {
            XCTFail(failure("\(name) cannot be tapped (\(frame))"))
        }
    }

    /// Checks that the card, open or folded, leaves the map free at
    /// `point`, where the step has the player tap.
    private func check(map point: CGPoint, _ name: String) {
        let target = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        XCTAssertTrue(app.frame.contains(target), failure("\(name) at \(point) is off the screen \(app.frame)"))
        let deadline = Date().addingTimeInterval(5)
        var covering: String?
        repeat {
            covering = coveringCard(target)
            if covering == nil { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        XCTFail(failure("\(covering ?? "The card") covers \(name) at \(point)"))
    }

    /// What of the tutorial's card covers `frame`, if anything.
    private func coveringCard(_ frame: CGRect) -> String? {
        if card.exists, card.frame.intersects(frame) { return "The tutorial card \(card.frame)" }
        if folded.exists, folded.frame.intersects(frame) { return "The folded tutorial card \(folded.frame)" }
        return nil
    }

    /// Taps tool `identifier` until it is selected, at most twice (a touch
    /// can be lost while the Simulator settles, as in TutorialUITests).
    private func tapTool(_ identifier: String) {
        let tool = app.buttons[identifier]
        check(tool, identifier)
        for _ in 0..<2 {
            tool.tap()
            let deadline = Date().addingTimeInterval(5)
            repeat {
                if tool.isSelected { return }
                Thread.sleep(forTimeInterval: 0.25)
            } while Date() < deadline
        }
        XCTFail(failure("\(identifier) is not selected after two taps"))
    }

    /// Taps the map's ✓, once more only if a press was dropped and nothing
    /// was built (run 37554617441).
    private func tapConfirm(_ name: String) {
        let confirm = app.buttons["map.build.confirm"]
        check(confirm, name)
        confirm.tap()
        if !confirm.waitForNonExistence(timeout: 10), confirm.isEnabled, shownStep() == step {
            confirm.tap()
        }
    }

    /// Next, or Finish on the last step: in reach, enabled, then tapped.
    private func tapNext(finishing: Bool) {
        if folded.exists, !card.exists { folded.tap() }
        let next = app.buttons["tutorial.next"]
        check(next, finishing ? "Finish" : "Next", onCard: true)
        let deadline = Date().addingTimeInterval(10)
        while !next.isEnabled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(next.isEnabled, failure("\(finishing ? "Finish" : "Next") stays disabled"))
        if finishing {
            XCTAssertEqual(next.label, "Finish", failure("The last step's button is not Finish"))
        }
        next.tap()
    }

    // MARK: - The map

    /// Where the walk lays its track: a row across the map from beside the
    /// tool rail to short of where the lines panel opens (decision 106:
    /// `ContentView.sidePanelWidth`, at most half the width), so that both
    /// stations stay in view while the line's stations are picked. The
    /// lowest row above the dock whose ends and stations are clear of the
    /// buttons floating over the map (Map Layers, the zoom buttons: the
    /// first walk's start landed on Map Layers on an iPad) and of the
    /// tutorial's card, which takes the map's top. The stations stand a
    /// quarter of the way in from each end.
    private func planTrack() {
        let rail = app.buttons["tool.select"]
        let dock = app.buttons["dock.build"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10), failure("No tool rail"))
        XCTAssertTrue(dock.waitForExistence(timeout: 10), failure("No dock"))
        let screen = app.frame
        // The rail stands one margin (10) inside the safe area, which is the
        // same on both sides of a phone on its side.
        let safeSide = max(0, rail.frame.minX - 10)
        let width = screen.width - 2 * safeSide
        let panelWidth = min(420, (width * 0.5).rounded())
        let panelLeading = screen.maxX - safeSide - 10 - panelWidth
        let left = rail.frame.maxX + 28
        let right = panelLeading - 28
        XCTAssertGreaterThan(right - left, 160, failure("No room for the track: from \(left) to \(right)"))
        let length = right - left

        var obstacles: [CGRect] = []
        for identifier in ["map.layers", "Zoom out", "Zoom in", "map.style", "map.expansion", "hud.menu"] {
            let button = app.buttons[identifier]
            if button.exists { obstacles.append(button.frame) }
        }
        let pill = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Game time")).firstMatch
        let top = max(pill.exists ? pill.frame.maxY : 0, app.buttons["hud.menu"].exists ? app.buttons["hud.menu"].frame.maxY : 0) + 24
        if card.exists { obstacles.append(card.frame) }
        if folded.exists { obstacles.append(folded.frame) }
        let blocked = obstacles.map { $0.insetBy(dx: -24, dy: -24) }

        var y = dock.frame.minY - 44
        while y > top {
            let points = [left, left + length / 4, right - length / 4, right].map { CGPoint(x: $0, y: y) }
            if !points.contains(where: { point in blocked.contains { $0.contains(point) } }) {
                trackStart = points[0]
                firstStation = points[1]
                secondStation = points[2]
                trackEnd = points[3]
                return
            }
            y -= 8
        }
        XCTFail(failure("No row clear of the map's buttons and the card from \(left) to \(right): \(obstacles)"))
    }

    private func tap(_ point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Failures

    /// `message`, with the step it happened on.
    private func failure(_ message: String) -> String {
        let title = step > 0 ? Self.titles[step - 1] : "start"
        return "Step \(step) “\(title)”: \(message). \(onScreen())"
    }

    /// What the tutorial shows: the card's texts (its hint says what is
    /// wrong), or its folded pill.
    private func onScreen() -> String {
        if card.exists {
            let texts = card.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            return "Card at \(card.frame): \(texts.joined(separator: " | "))"
        }
        if folded.exists {
            return "Folded card at \(folded.frame): \(folded.label)"
        }
        return "No tutorial card"
    }
}
