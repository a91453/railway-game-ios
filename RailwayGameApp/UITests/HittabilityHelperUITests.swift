import XCTest

/// `XCUIElement.isHittableNow` (FLANE7) forgives XCTest's "Failed to
/// determine hittability" inside `XCTExpectFailure`. These check, without
/// launching the app, that the test goes on after that failure even with
/// `continueAfterFailure` false, as the UI tests that use it set it, and
/// that any other failure still fails the test.
@MainActor
final class HittabilityHelperUITests: XCTestCase {
    func testAForgivenHittabilityFailureLetsTheTestGoOn() {
        continueAfterFailure = false
        var wentOn = false
        // Runs even when a failure has stopped the test: a forgiven
        // failure that stopped it would otherwise pass unseen.
        addTeardownBlock { XCTAssertTrue(wentOn, "The test stopped at a forgiven hittability failure") }
        XCUIElement.forgivingHittabilityFailure {
            XCTFail("Failed to determine hittability of \"probe\" StaticText: Activation point invalid and no suggested hit points based on element frame")
        }
        wentOn = true
    }

    func testAnyOtherFailureStillFailsTheTest() {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("The menu probe did not settle") }
        // Strict: the inner failure must reach this outer expectation, so
        // forgivingHittabilityFailure did not take it.
        XCTExpectFailure("forgivingHittabilityFailure must not take other failures", options: options) {
            XCUIElement.forgivingHittabilityFailure {
                XCTFail("The menu probe did not settle")
            }
        }
    }
}
