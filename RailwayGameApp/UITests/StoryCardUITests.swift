import XCTest

/// Decision 387: a challenge's story card stands in the station master's
/// place, clear of the building tools, Undo and Redo, the dock's entries
/// and the map's buttons, which a finger still reaches, and gives way
/// while the building tools are out, where the map's ✓ shows. Full lane
/// only (decision 199). Run by hand with
/// only_testing=RailwayGameUITests/StoryCardUITests.
@MainActor
final class StoryCardUITests: XCTestCase {
    func testTheCardKeepsClearHeldUpright() {
        checkTheCard(orientation: .portrait)
    }

    func testTheCardKeepsClearOnItsSide() {
        checkTheCard(orientation: .landscapeLeft)
    }

    private func checkTheCard(orientation: UIDeviceOrientation) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-world", "story", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The game opens")

        // The first beat, at the challenge's next midnight.
        let card = app.descendants(matching: .any)["storyCard"].firstMatch
        XCTAssertTrue(card.appears(within: 40), "The story card shows")
        card.waitUntilSettled()
        // One snapshot of the whole screen: asking each button in turn takes
        // longer than the card stays up (14 s), and it would go mid-check.
        var frames: [String: CGRect] = [:]
        func collect(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty, frames[element.identifier] == nil { frames[element.identifier] = element.frame }
            // The zoom buttons go by their labels.
            if element.elementType == .button, !element.label.isEmpty, frames[element.label] == nil { frames[element.label] = element.frame }
            element.children.forEach(collect)
        }
        guard let screen = try? app.snapshot() else { return XCTFail("No snapshot of the screen") }
        collect(screen)
        let cardFrame = frames["storyCard"]
        XCTAssertNotNil(cardFrame, "The card is in the snapshot")
        let ids = [
            "dock.build", "entry.lines", "entry.economy", "controls.toggle", "controls.undo", "controls.redo",
            "map.layers", "map.coverageShortcut", "map.open3D", "Zoom out", "Zoom in",
        ]
        XCTAssertNotNil(frames["dock.build"], "Build is in the snapshot")
        for id in ids {
            guard let cardFrame, let frame = frames[id], !frame.isEmpty else { continue }
            XCTAssertFalse(cardFrame.intersects(frame), "\(id) \(frame) under the card \(cardFrame)")
        }
        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.becomesHittable(within: 5), "Build is reached beside the card")

        // The building tools out: the card goes, so the ✓ is never near it.
        build.tap()
        XCTAssertTrue(card.disappears(within: 5), "The card gives way to the building tools")
    }
}
