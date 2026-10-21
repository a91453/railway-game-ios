import GameCore
@testable import GamePresentation
import XCTest

/// Decision 309 (TestFlight 77.1 #1): the line panel's choice of how a
/// line's trains leave, and the command it gives.
@MainActor
final class LineDispatchPatternChoiceTests: XCTestCase {
    private static let line = TestLine(tiles: 7, row: 1)
    private static let main = LineID(rawValue: 1)

    private func session(flex: Bool, language: DisplayLanguage = .english) throws -> GameSession {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        world.setFlexDispatch(flex)
        try Self.line.build(in: &world)
        let alpha = try Self.line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try Self.line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        let session = GameSession(world: world, language: language)
        session.selectLine(Self.main)
        return session
    }

    func testTheMenuOffersBothEndsOnlyWithFlexibleDispatch() throws {
        let flexible = try session(flex: true)
        XCTAssertEqual(flexible.selectedLineDispatchChoices.map(\.pattern).prefix(3), [.even, .fromBothEnds, .staggered(minutes: 2)])
        XCTAssertEqual(flexible.selectedLineDispatchChoices.count, 2 + LineDispatchPatternChoice.staggers.count)
        XCTAssertTrue(LineDispatchPatternChoice.staggers.allSatisfy(DispatchPattern.staggerRange.contains))
        let plain = try session(flex: false)
        XCTAssertFalse(plain.selectedLineDispatchChoices.contains { $0.pattern == .fromBothEnds })
    }

    func testChoosingSetsTheLinesPatternAndSaysSo() throws {
        let session = try session(flex: true, language: .traditionalChinese)
        session.setSelectedLineDispatchPattern(.staggered(minutes: 10))
        XCTAssertEqual(session.world.line(id: Self.main)?.dispatchPattern, .staggered(minutes: 10))
        XCTAssertEqual(session.message?.text, "Main：第二列晚 10 分。")
        XCTAssertEqual(session.dispatchPatternFooter(.fromBothEnds), "一半的車在終點站等，兩端同時發車。")
        session.setSelectedLineDispatchPattern(.fromBothEnds)
        XCTAssertEqual(session.world.line(id: Self.main)?.dispatchPattern, .fromBothEnds)
    }

    func testTheTitles() {
        XCTAssertEqual(LineDispatchPatternChoice(pattern: .even).title(in: .traditionalChinese), "平均錯開")
        XCTAssertEqual(LineDispatchPatternChoice(pattern: .fromBothEnds).title(in: .traditionalChinese), "兩端對開")
        XCTAssertEqual(LineDispatchPatternChoice(pattern: .staggered(minutes: 5)).title(in: .english), "Second train 5 min later")
    }
}
