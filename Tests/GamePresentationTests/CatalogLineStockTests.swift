@testable import GameCore
@testable import GamePresentation
import XCTest

/// TAP-FREEZE-151 (0.6.0 (151) on the author's iPhone): on the
/// Nishi-Kyushu Shinkansen, the line panel's type menu took some three
/// seconds to open, its type menus driving the line twice for every type;
/// and the line's catalog showed the high-speed type as the 700T, where
/// the map draws the line's own N700S.
@MainActor
final class CatalogLineStockTests: XCTestCase {
    func testTheBoughtLineShowsItsOwnN700SAndWalksItsTrackOnce() throws {
        let session = try FukuokaRailwaysTests.fukuoka(start: 3)
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == NishiKyushuShinkansenTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: real)), session.message?.text ?? "")
        let world = session.world
        let line = try XCTUnwrap(world.acquisition(of: NishiKyushuShinkansenTests.id)?.line)

        // The catalog for the line: the high-speed type as the N700S, by
        // that name; the others as their own.
        let catalog = RollingStockCatalog(world: world, line: line)
        let highSpeed = try XCTUnwrap(catalog.entries.first { $0.type == .highSpeed })
        XCTAssertEqual(highSpeed.stock, Map3DN700S.key)
        XCTAssertEqual(highSpeed.portraitKey, Map3DN700S.key)
        XCTAssertEqual(highSpeed.title(in: .traditionalChinese), "\(TrainType.highSpeed.title(in: .traditionalChinese))（N700S）")
        XCTAssertEqual(highSpeed.title(in: .english), "\(TrainType.highSpeed.title(in: .english)) (N700S)")
        XCTAssertNotNil(TrainPortrait.make(key: highSpeed.portraitKey, cars: 3), "the N700S has a picture")
        for entry in catalog.entries where entry.type != .highSpeed {
            XCTAssertNil(entry.stock, entry.type.rawValue)
            XCTAssertEqual(entry.portraitKey, TrainPortrait.key(of: entry.type))
        }
        // With no line, every type as its own.
        XCTAssertTrue(RollingStockCatalog(world: world).entries.allSatisfy { $0.stock == nil })

        // The line's track, walked once, says what each type did before:
        // its kinds of track and its gauges, one type at a time.
        let track = world.lineTrack(ofLine: line)
        XCTAssertEqual(track.gauges, [.shinkansen])
        let types: [TrainType?] = [nil] + TrainType.allCases.map { $0 }
        for type in types {
            let before = world.trackKinds(ofLine: line).allSatisfy { TrackCompatibility.runs(type, on: $0) }
                && world.fitsGauge(type, ofLine: line)
            XCTAssertEqual(track.carries(type), before, type?.rawValue ?? "standard car")
            XCTAssertEqual(world.runsOnTrack(type, ofLine: line), before, type?.rawValue ?? "standard car")
        }
        XCTAssertEqual(session.trainTypeCardChoices(forLine: line).map(\.id), world.openTrainTypes.filter { track.carries($0) })
        XCTAssertTrue(session.trainTypeCardChoices(forLine: line).contains { $0.id == .highSpeed })
        // Kept until the next command.
        let revision = session.commandRevision
        XCTAssertEqual(session.lineTrack(ofLine: line), track)
        XCTAssertEqual(session.lineTrackMemo[line]?.revision, revision)
    }

    /// The Kyushu and Nishi-Kyushu Shinkansen's sets have names.
    func testTheShinkansenSetsHaveNames() {
        XCTAssertEqual(RealLineStock.lineName(ofSet: Map3DN700S.key, in: .traditionalChinese), "N700S")
        XCTAssertEqual(RealLineStock.lineName(ofSet: Map3DKyushuN700.key, in: .traditionalChinese), "N700／800 系")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DKyushu800.key, in: .english), "Series 800")
    }
}
