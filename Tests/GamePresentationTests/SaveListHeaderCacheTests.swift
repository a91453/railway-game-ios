import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 497 (P2-2, the owner's 97.1 report): listing the saves reads
/// whole only the files that changed since they were last read, by this
/// library or, through the small files it keeps in a folder of its own,
/// by an earlier launch; what the list shows is what reading every file shows.
final class SaveListHeaderCacheTests: XCTestCase {
    private var directory: URL!
    private var headers: URL!
    private let date = Date(timeIntervalSince1970: 1_790_942_400)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveListHeaderCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        headers = directory.appendingPathExtension("headers")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: headers)
    }

    private func library() -> SaveLibrary {
        SaveLibrary(directory: directory, headers: headers)
    }

    /// Writes a save file as another device or build would: not through
    /// the library.
    private func write(_ name: String, at date: Date) throws {
        try SaveLibrary.encode(DemoWorld.make(in: .english), at: date).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    func testAListReadAgainReadsOnlyWhatChanged() throws {
        try write("autosave.json", at: date)
        try write("save-a.json", at: date.addingTimeInterval(60))
        try write("save-b.json", at: date.addingTimeInterval(120))
        let library = self.library()

        let listed = library.entries()
        XCTAssertEqual(listed.map(\.id), ["autosave.json", "save-b.json", "save-a.json"])
        XCTAssertEqual(library.headersRead, 3)
        XCTAssertEqual(library.entries(), listed)
        XCTAssertEqual(library.headersRead, 3, "nothing changed, nothing read")

        // A copy of the library (the launcher's save queue lists with one)
        // and a library of the next launch read no file whole either.
        let copy = library
        XCTAssertEqual(copy.entries(), listed)
        let nextLaunch = self.library()
        XCTAssertEqual(nextLaunch.entries(), listed)
        XCTAssertEqual(library.headersRead, 3)
        XCTAssertEqual(nextLaunch.headersRead, 0)

        // A name lies beside the save and is read every time.
        let first = try XCTUnwrap(listed.first { $0.id == "save-a.json" })
        try library.rename(first, to: "Morning")
        XCTAssertEqual(library.entries().first { $0.id == first.id }?.name, "Morning")
        XCTAssertEqual(library.headersRead, 3)

        // A save written over is read again, and the list shows it.
        try write("save-b.json", at: date.addingTimeInterval(3_600))
        XCTAssertEqual(library.entries().first { $0.id == "save-b.json" }?.savedAt, date.addingTimeInterval(3_600))
        XCTAssertEqual(library.headersRead, 4)
        XCTAssertEqual(self.library().entries(), library.entries(), "the file kept for the next launch is out of date, and read again")

        // A deleted save leaves the list, and its kept header goes.
        try library.delete(first)
        XCTAssertFalse(library.entries().contains { $0.id == first.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: headers.appendingPathComponent("save-a.json").path))
    }

    /// The library's own save is not read back for the list.
    func testASaveIsListedWithoutReadingItBack() throws {
        let library = self.library()
        let saved = try library.save(DemoWorld.make(in: .english), as: .autosave, at: date.addingTimeInterval(0.25))
        let listed = try XCTUnwrap(library.entries().first)
        XCTAssertEqual(library.headersRead, 0)
        XCTAssertEqual(listed.savedAt, date, "to the second, as reading the file gives it")
        XCTAssertEqual(listed.summary, saved.summary)

        let read = self.library()
        try FileManager.default.removeItem(at: headers)
        XCTAssertEqual(read.entries(), library.entries(), "the same as reading the file")
        XCTAssertEqual(read.headersRead, 1)
    }

    /// A file that is no save, made one later under the same name, is
    /// listed as the save it became.
    func testAFileThatChangesIsReadAgain() throws {
        let library = self.library()
        let file = directory.appendingPathComponent("save-other.json")
        try Data("{}".utf8).write(to: file)
        XCTAssertEqual(library.entries().map(\.problem), [.notASave])

        try write("save-other.json", at: date)
        let entry = try XCTUnwrap(library.entries().first)
        XCTAssertNil(entry.problem)
        XCTAssertEqual(entry.savedAt, date)
    }

    /// The saves' folder holds the saves alone, and a library given no
    /// folder for the headers keeps them in memory only.
    func testTheSavesFolderHoldsOnlyTheSaves() throws {
        try write("save-a.json", at: date)
        _ = library().entries()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["save-a.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: headers.path), ["save-a.json"])

        let inMemory = SaveLibrary(directory: directory)
        _ = inMemory.entries()
        _ = inMemory.entries()
        XCTAssertEqual(inMemory.headersRead, 1)
    }
}
