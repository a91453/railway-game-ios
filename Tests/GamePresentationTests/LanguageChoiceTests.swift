import GamePresentation
import XCTest

/// ARCHITECTURE decision 257: the start screen's language menu. iOS shows an
/// app's language row in Settings only when the device lists two or more
/// languages, so the game chooses its own: the choice is the app's
/// `AppleLanguages` override, read back from it, and used from the next launch.
final class LanguageChoiceTests: XCTestCase {
    func testEachChoiceWritesTheOverrideIOSReadsAtLaunch() {
        XCTAssertNil(LanguageChoice.system.appleLanguages)
        XCTAssertEqual(LanguageChoice.english.appleLanguages, ["en"])
        XCTAssertEqual(LanguageChoice.traditionalChinese.appleLanguages, ["zh-Hant"])
    }

    func testTheChoiceIsReadBackFromTheAppsOverride() {
        XCTAssertEqual(LanguageChoice(appleLanguages: nil), .system)
        XCTAssertEqual(LanguageChoice(appleLanguages: []), .system)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["en"]), .english)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["en-TW"]), .english)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["zh-Hant"]), .traditionalChinese)
        // What iOS Settings writes when the player picks Chinese there.
        XCTAssertEqual(LanguageChoice(appleLanguages: ["zh-Hant-TW"]), .traditionalChinese)
        for choice in LanguageChoice.allCases {
            XCTAssertEqual(LanguageChoice(appleLanguages: choice.appleLanguages), choice)
        }
    }

    func testTheMenuNamesEachLanguageInItself() {
        for language in DisplayLanguage.allCases {
            XCTAssertEqual(LanguageChoice.english.title(in: language), "English")
            XCTAssertEqual(LanguageChoice.traditionalChinese.title(in: language), "繁體中文")
        }
        XCTAssertEqual(LanguageChoice.system.title(in: .english), "Same as iPhone")
        XCTAssertEqual(LanguageChoice.system.title(in: .traditionalChinese), "跟隨 iPhone")
    }

    func testAChangeAsksForARestartOnlyWhenTheLanguageMayChange() {
        XCTAssertFalse(LanguageChoice.english.needsRestart(from: .english, showing: .english))
        XCTAssertTrue(LanguageChoice.traditionalChinese.needsRestart(from: .english, showing: .english))
        XCTAssertTrue(LanguageChoice.system.needsRestart(from: .english, showing: .english))
        XCTAssertFalse(LanguageChoice.system.needsRestart(from: .system, showing: .english))
        let note = LanguageChoice.traditionalChinese.restartNote(in: .english)
        XCTAssertFalse(note.isEmpty)
        XCTAssertNotEqual(note, LanguageChoice.traditionalChinese.restartNote(in: .traditionalChinese))
    }
}
