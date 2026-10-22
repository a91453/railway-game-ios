import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 336: the ways in the author could not find. The lines panel
/// lists the real lines for sale, or says why there are none; a refusal
/// of land not bought yet offers to go and expand the map.
@MainActor
final class DiscoverableEntriesTests: XCTestCase {
    /// A real-world game of `side` units square round (`latitude`,
    /// `longitude`), with the bundled railways unless `railways` is false.
    private func game(latitude: Double, longitude: Double, side: Int64, railways: Bool = true, language: DisplayLanguage = .english) throws -> GameSession {
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: Money(100_000_000_000))
        let session = GameSession(world: world, language: language)
        if railways { session.railways = try BundledRealData.railways() }
        return session
    }

    /// The middle of `network`'s stations.
    private func middle(of network: String) throws -> (latitude: Double, longitude: Double) {
        let runs = try XCTUnwrap(try BundledRealData.railways().branchRuns[network])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "tra_sched") }
        return (
            stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count),
            stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        )
    }

    func testABlankMapSaysRealLinesAreOnRealWorldMaps() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9), language: .english)
        XCTAssertTrue(session.buyableRealLines.isEmpty)
        XCTAssertEqual(session.realLinesForSaleNote, "Real branch lines are for sale on real-world maps.")
        XCTAssertEqual(GameSession(world: session.world, language: .traditionalChinese).realLinesForSaleNote, "真實支線只在實景地圖上可以收購。")
        session.startTutorial()
        XCTAssertNil(session.realLinesForSaleNote, "not in the tutorial")
        let lesson = GameSession(world: GameWorld.newGame(lesson: Lesson.all[0]), language: .english)
        XCTAssertNil(lesson.realLinesForSaleNote, "not in a lesson")
    }

    func testARealWorldMapSaysWhileTheRailwaysLoad() throws {
        let pingxi = try middle(of: "PINGXI")
        let session = try game(latitude: pingxi.latitude, longitude: pingxi.longitude, side: 1 << 20, railways: false)
        XCTAssertEqual(session.realLinesForSaleNote, "The real railways are still loading.")
        session.railways = try BundledRealData.railways()
        XCTAssertTrue(session.buyableRealLines.contains { $0.network == "PINGXI" })
        XCTAssertNil(session.realLinesForSaleNote, "the lines are listed")
    }

    func testAMapHoldingPartOfALineNamesIt() throws {
        // 2 km round Shifen: a station or two of the Pingxi Line.
        let shifen = try BundledRealData.station("十分", in: "tra_sched")
        let session = try game(latitude: shifen.coordinate.latitude, longitude: shifen.coordinate.longitude, side: 2_000 * WorldCoordinate.unitsPerMetre)
        XCTAssertTrue(session.buyableRealLines.isEmpty)
        XCTAssertEqual(
            session.realLinesForSaleNote,
            "This map holds only part of the Pingxi Line. A line is for sale when all its stations are on the map."
        )
        let chinese = try game(latitude: shifen.coordinate.latitude, longitude: shifen.coordinate.longitude, side: 2_000 * WorldCoordinate.unitsPerMetre, language: .traditionalChinese)
        XCTAssertEqual(chinese.realLinesForSaleNote, "這張地圖只框到平溪線的一部分。整條線的車站都在地圖上，才可以收購。")
    }

    func testAMapWithNoBranchLineSaysSo() throws {
        // Kaohsiung's harbour, far from every branch line.
        let session = try game(latitude: 22.62, longitude: 120.28, side: 1 << 17)
        XCTAssertEqual(session.realLinesForSaleNote, "No real branch line runs through this map.")
    }

    func testAMapWhoseLinesAreBoughtSaysSo() throws {
        let pingxi = try middle(of: "PINGXI")
        // 12 km: the Pingxi Line, short of the Shenao Line's far end.
        let session = try game(latitude: pingxi.latitude, longitude: pingxi.longitude, side: 12_000 * WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(session.buyableRealLines.map(\.network), ["PINGXI"])
        for line in session.buyableRealLines {
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        }
        XCTAssertTrue(session.buyableRealLines.isEmpty)
        XCTAssertEqual(session.realLinesForSaleNote, "You own every real branch line on this map.")
    }

    // MARK: - Expanding the map

    /// TestFlight 56.1 hid the map's button while building; the refusal
    /// of land not bought yet carries one instead, which ends building.
    func testLandNotBoughtOffersToExpandTheMap() {
        let session = GameSession(world: GameWorld.newGame(balance: 1_000_000_000, eventSeed: 9, buysMap: true), language: .traditionalChinese)
        let refusal = GameError.mapTileNotOwned(MapTile(row: 0, column: 4)).playerMessage(in: .traditionalChinese)
        session.selectTool(.network)
        XCTAssertFalse(session.showsMapExpansionButton)
        XCTAssertTrue(session.offersMapExpansion(for: refusal))
        XCTAssertFalse(session.offersMapExpansion(for: GameError.mapTileNotAdjacent.playerMessage(in: .traditionalChinese)))
        XCTAssertFalse(session.offersMapExpansion(for: nil))

        session.startChoosingMapTile()
        XCTAssertEqual(session.tool, .select, "building ends")
        XCTAssertTrue(session.isChoosingMapTile)
        XCTAssertFalse(session.offersMapExpansion(for: refusal), "already choosing")

        let fixed = GameSession(world: GameWorld.newGame(eventSeed: 9), language: .traditionalChinese)
        XCTAssertFalse(fixed.offersMapExpansion(for: refusal), "a map that is not bought")
    }
}
