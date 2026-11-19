import Foundation
@testable import GamePresentation
import XCTest

/// MAP-PACK-MANAGE: the player removes a city's map pack in the settings
/// or downloads it again; what was removed is kept in the preferences, and
/// a save on its map says how to get it back.
final class MapPackChoicesTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "MapPackChoicesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testTheRemovedCitiesAreKept() throws {
        let defaults = try defaults()
        XCTAssertEqual(MapPackChoices.removed(in: defaults), [])
        MapPackChoices.set(.hongKong, removed: true, in: defaults)
        MapPackChoices.set(.rovaniemi, removed: true, in: defaults)
        XCTAssertEqual(MapPackChoices.removed(in: defaults), [.hongKong, .rovaniemi])
        MapPackChoices.set(.hongKong, removed: false, in: defaults)
        XCTAssertEqual(MapPackChoices.removed(in: defaults), [.rovaniemi])
        XCTAssertEqual(defaults.stringArray(forKey: MapPackChoices.key), ["rovaniemi"])
    }

    /// A downloaded pack can be removed, but not under an open game on its
    /// map; a removed or failed one downloaded again; a carried one (the
    /// Debug app) or one still coming offers nothing.
    func testWhatEachRowOffers() {
        let offer = { (status: MapPackStatus, carried: Bool, playing: Bool) in
            MapPackChoices.offer(.hongKong, status: status, carried: carried, playing: playing)
        }
        XCTAssertEqual(offer(.downloaded, false, false), .remove)
        XCTAssertEqual(offer(.earlier, false, false), .remove)
        XCTAssertEqual(offer(.downloaded, false, true), .inUse)
        XCTAssertEqual(offer(.removed, false, false), .download)
        XCTAssertEqual(offer(.failed("offline"), false, false), .download)
        XCTAssertEqual(offer(.refused(.noManifest), false, false), .download)
        XCTAssertEqual(offer(.downloading, false, false), .none)
        XCTAssertEqual(offer(.bundled, false, false), .none)
        XCTAssertEqual(offer(.downloaded, true, false), .none)
        XCTAssertEqual(offer(.removed, true, false), .none)
    }

    /// What the player reads: the row, the button, the question, and what
    /// a save on a removed map says.
    func testTheWords() {
        let zh = DisplayLanguage.traditionalChinese
        XCTAssertEqual(MapPackStatus.removed.text(in: zh, carried: false), "已刪除")
        XCTAssertEqual(MapPackStatus.removed.text(in: .english, carried: false), "Removed")
        XCTAssertEqual(MapPackChoices.buttonTitle(.remove, in: zh), "刪除地圖資料")
        XCTAssertEqual(MapPackChoices.buttonTitle(.download, in: zh), "重新下載")
        XCTAssertNil(MapPackChoices.buttonTitle(.none, in: zh))
        XCTAssertNotNil(MapPackChoices.note(.inUse, .hongKong, in: zh))
        XCTAssertNil(MapPackChoices.note(.remove, .hongKong, in: zh))
        XCTAssertTrue(MapPackChoices.confirmation(.hongKong, in: zh).contains("存檔會留著"))
        XCTAssertTrue(OverseasMap.rovaniemi.notDownloadedText(.removed, in: zh).contains("重新下載"))
        XCTAssertEqual(MapPackStatus.removed.reportText, "removed by the player")
    }

    /// A removed pack is not waited for: the real-world data does not
    /// stand still for it.
    func testARemovedPackIsNotWaitedFor() {
        XCTAssertFalse(MapPackStatus.removed.isWaiting)
    }
}
