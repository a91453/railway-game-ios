import Foundation
import XCTest
@testable import GameCore

/// Decision 910: each save version says what it added in a file of its own,
/// `SaveFixtures/versions/<N>.md`, rather than in one list at the top of
/// `SavedGame.swift` that every raise of the version changed.
final class SaveVersionNotesTests: XCTestCase {
    /// Versions the list never described, before it was split.
    private let undescribed: Set<Int> = [81, 88, 96]

    func testEachSaveVersionHasItsNote() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/versions", isDirectory: true)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        for version in 1...SavedGame.currentVersion where !undescribed.contains(version) {
            XCTAssertTrue(names.contains("\(version).md"), "SaveFixtures/versions/\(version).md: say what save version \(version) adds")
        }
        let extra = names.compactMap { Int($0.dropLast(3)) }.filter { $0 > SavedGame.currentVersion }
        XCTAssertEqual(extra, [], "a note for a version this build does not write yet")
    }
}
