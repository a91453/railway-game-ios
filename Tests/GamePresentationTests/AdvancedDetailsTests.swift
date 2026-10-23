import GameCore
import GamePresentation
import XCTest

/// Decision 196, later: the lines panel's "Advanced" switch, folded on a
/// phone, and the one line that keeps a game's folded settings in sight.
final class AdvancedDetailsTests: XCTestCase {
    private let track = TestLine(tiles: 7, row: 1)

    private func makeLineWorld() throws -> (world: GameWorld, main: LineID) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        return (world, main)
    }

    func testFoldedOnAPhoneAndShownOnAnIPadUntilThePlayerChooses() {
        XCTAssertFalse(AdvancedDetails.isShown(stored: nil, roomy: false))
        XCTAssertTrue(AdvancedDetails.isShown(stored: nil, roomy: true))
        XCTAssertTrue(AdvancedDetails.isShown(stored: true, roomy: false))
        XCTAssertFalse(AdvancedDetails.isShown(stored: false, roomy: true))
    }

    func testANewLineHasNothingFolded() throws {
        let (world, main) = try makeLineWorld()
        let line = try XCTUnwrap(world.line(id: main))
        XCTAssertNil(AdvancedDetails.lineSummary(line, in: .english))
        XCTAssertNil(AdvancedDetails.lineSummary(line, in: .traditionalChinese))
    }

    func testALinesFoldedSettingsAreSaidInOneLine() throws {
        var (world, main) = try makeLineWorld()
        let pattern = try world.addLinePattern(main, calling: [0, 2])
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 10, offPeak: nil, low: nil), pattern: pattern)
        let choice = try XCTUnwrap(world.lineRouteChoices(main, from: 0, to: 1, pattern: nil).first)
        try world.setLineRoutePreferences(main, to: [choice])
        let line = try XCTUnwrap(world.line(id: main))
        XCTAssertEqual(
            AdvancedDetails.lineSummary(line, in: .english),
            "Advanced: 1 leg on set tracks, target headways"
        )
        XCTAssertEqual(AdvancedDetails.lineSummary(line, in: .traditionalChinese), "進階：1 段指定進路、目標班距")
    }

    /// Decision 383: a stopping pattern shows with Advanced folded, so the
    /// folded line does not say it.
    func testAStoppingPatternIsNotFolded() throws {
        var (world, main) = try makeLineWorld()
        _ = try world.addLinePattern(main, calling: [0, 2])
        let line = try XCTUnwrap(world.line(id: main))
        XCTAssertNil(AdvancedDetails.lineSummary(line, in: .english))
    }

    /// Decision 383: the network's switches have their own block, never
    /// folded; the folded line says only the service day.
    func testTheNetworksFoldedSettingIsSaidAsItIs() throws {
        var (world, _) = try makeLineWorld()
        XCTAssertEqual(AdvancedDetails.networkSummary(of: world, in: .english), "Standard service day")
        try world.setTrafficControl(true)
        world.setPassengerRoutingMode(.network)
        XCTAssertEqual(AdvancedDetails.networkSummary(of: world, in: .traditionalChinese), "標準時段")
    }
}
