import Foundation
@testable import GamePresentation
import XCTest

/// The public repository carries only the neutral brand (GameBrand): the
/// released game's is put into a working copy before a release build
/// (tools/brand/apply_brand.py) and must never be committed.
final class GameBrandTests: XCTestCase {
    private static let app = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp")

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.app.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheCommittedBrandIsTheNeutralOne() throws {
        let data = try Data(contentsOf: Self.app.appendingPathComponent("Resources/GameBrand.json"))
        XCTAssertEqual(try JSONDecoder().decode(GameBrand.self, from: data), .neutral,
                       "GameBrand.json holds an applied brand: restore it (tools/brand/README.md)")
    }

    func testTheCommittedInfoPlistIsNeutral() throws {
        let info = try text("Info.plist")
        XCTAssertEqual(info.components(separatedBy: "<string>Railway Game Save</string>").count - 1, 2)
        XCTAssertEqual(info.components(separatedBy: "<string>\(GameBrand.neutral.saveExtension)</string>").count - 1, 1)
        XCTAssertTrue(try text("Resources/en.lproj/InfoPlist.strings").contains(#""CFBundleDisplayName" = "Railway Game";"#))
        XCTAssertTrue(try text("Resources/zh-Hant.lproj/InfoPlist.strings").contains(#""CFBundleDisplayName" = "鐵道遊戲";"#))
        XCTAssertTrue(try text("Resources/zh-Hant.lproj/InfoPlist.strings").contains(#""Railway Game Save" = "鐵道遊戲存檔";"#))
    }

    func testATestBuildIsNeutral() {
        XCTAssertEqual(GameBrand.current, .neutral)
        XCTAssertEqual(SharedNetwork.fileExtension, GameBrand.neutral.saveExtension)
        XCTAssertNil(GameWebsite.home)
    }

    func testABrandReadsBackAndChecksItsFields() throws {
        let brand = GameBrand(english: "Test", chinese: "測試", saveExtension: "test1", website: "www.railway.example", contactEmail: "hi@railway.example")
        let decoded = try JSONDecoder().decode(GameBrand.self, from: JSONEncoder().encode(brand))
        XCTAssertEqual(decoded, brand)
        XCTAssertTrue(brand.isValid)
        XCTAssertTrue(GameBrand.neutral.isValid)
        XCTAssertEqual(brand.websiteName, "railway.example")
        XCTAssertEqual(brand.name(in: .traditionalChinese), "測試")
        XCTAssertFalse(GameBrand(english: "A", chinese: "B", saveExtension: "a.b").isValid)
        XCTAssertFalse(GameBrand(english: "A", chinese: "B", saveExtension: "ab", website: "https://x").isValid)
        XCTAssertFalse(GameBrand(english: "", chinese: "B", saveExtension: "ab").isValid)
    }
}
