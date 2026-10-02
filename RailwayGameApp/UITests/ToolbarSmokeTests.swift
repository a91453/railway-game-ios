import XCTest

@MainActor
final class ToolbarSmokeTests: XCTestCase {
    func testEnglishToolbar() {
        captureToolbar(language: "en", locale: "en_US", queries: [
            "Select tool", "Track network tool", "Train tool",
        ])
    }

    func testTraditionalChineseScreenshots() {
        // Use identifiers, not translated text: these are visual evidence,
        // not assertions about the wording of the Traditional Chinese UI.
        captureToolbar(language: "zh-Hant", locale: "zh_TW", queries: [
            "tool.select", "tool.network", "tool.train",
        ])
    }

    private func captureToolbar(language: String, locale: String, queries: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The app creates a new game on each launch without -demo-layout.
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        let tools = ["select", "network", "train"]
        for (index, query) in queries.enumerated() {
            let button = app.buttons[query]
            guard button.waitForExistence(timeout: 10) else {
                XCTFail("Missing toolbar button: \(query)")
                return
            }
            XCTAssertTrue(button.isHittable, "Toolbar button cannot be tapped: \(query)")
            button.tap()

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(language)-0\(index + 1)-\(tools[index])"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
