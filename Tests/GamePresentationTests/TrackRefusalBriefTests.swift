import GameCore
import XCTest
@testable import GamePresentation

/// Decision 803, continued (BUILD-MODE-CLEAN-2; the owner: "字不會太多嗎"):
/// the map's ✕ ✓ pill says why a stretch is refused in one short line.
/// Every refusal building track meets has one, in both languages: no
/// figures, no full stop, shorter than the sentence it stands for, and
/// no more than half of one that took two lines.
final class TrackRefusalBriefTests: XCTestCase {
    private let languages: [DisplayLanguage] = [.english, .traditionalChinese]

    private func check(_ brief: String, for whole: String, _ language: DisplayLanguage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(brief.isEmpty, file: file, line: line)
        XCTAssertFalse(brief.contains { $0.isASCII && $0.isNumber }, "no figures: \(brief)", file: file, line: line)
        XCTAssertFalse(brief.contains("\n"), brief, file: file, line: line)
        XCTAssertFalse(brief.hasSuffix(".") || brief.hasSuffix("。"), "a label, not a sentence: \(brief)", file: file, line: line)
        // One line of the caption in the pill: some 45 Latin letters or 16
        // Chinese characters.
        XCTAssertLessThanOrEqual(brief.count, language == .english ? 45 : 16, brief, file: file, line: line)
        XCTAssertLessThan(brief.count, whole.count, "shorter than: \(whole)", file: file, line: line)
        // A sentence of two lines or more in the pill comes down to half.
        if whole.count >= (language == .english ? 80 : 30) {
            XCTAssertLessThanOrEqual(brief.count * 2, whole.count, "half of: \(whole)", file: file, line: line)
        }
    }

    func testEveryErrorBuildingTrackMeetsHasOneShortLine() {
        let tile = MapTile(row: 0, column: 0)
        let edge = TrackEdgeID.edge(1), node = TrackNodeID.node(1)
        let errors: [GameError] = [
            .trackOverWater, .trackTooSteep, .structureTooHigh, .invalidTrackStructure,
            .trackConflict(edge), .trackTooClose(edge), .turnoutTooSteep, .mapTileNotOwned(tile),
            .insufficientFunds(required: Money(200), available: Money(100)), .invalidTrackGeometry, .groundNotLoaded,
            .trackReserved(TrainID(rawValue: 1)), .trackEdgeHasPlatform(edge), .unknownTrackNode(node), .unknownTrackEdge(edge),
        ]
        for error in errors {
            for language in languages {
                let brief = error.trackBrief(in: language)
                XCTAssertNotNil(brief, "\(error)")
                check(brief ?? "", for: error.playerMessage(in: language), language)
            }
        }
        // One building track never meets is said whole.
        XCTAssertNil(GameError.invalidName.trackBrief(in: .english))
    }

    @MainActor
    func testEveryCheckOfTheToolHasOneShortLine() {
        for language in languages {
            for problem in NetworkBuilding.GeometryProblem.allCases {
                check(problem.brief(in: language), for: problem.text(in: language), language)
                check(TrackGeometryProblem.geometry(problem).brief(in: language), for: problem.text(in: language), language)
                check(NetworkProblem.geometry(problem).brief(in: language), for: problem.text(in: language), language)
            }
            for problem in [TrackGeometryProblem.tooHigh(5_000), .tooDeep(70_000), .pointTaken] {
                check(problem.brief(in: language), for: problem.text(in: language), language)
            }
            for problem in [NetworkProblem.missingNode, .tooClose, .tooSharp, .steepTurnout, .turnoutOnVerticalCurve] {
                check(problem.brief(in: language), for: problem.text(in: language), language)
            }
            for problem in [ScissorsProblem.notLevel, .notAcross, .tooShort, .nearANode, .tooSharp, .tooShallow] {
                check(problem.brief(in: language), for: problem.text(in: language), language)
            }
            check(GameSession.noParallelBrief(in: language), for: GameSession.noParallelText(in: language), language)
            for note in [NetworkHeightCard.Note.noneWorks, .endsFixed] {
                check(note.brief(in: language), for: note.text(in: language), language)
            }
            XCTAssertLessThan(NetworkHeightCard.Note.looking.brief(in: language).count, NetworkHeightCard.Note.looking.text(in: language).count)
        }
    }

    /// Too close to the other end, refused before GameCore is asked: the
    /// preview carries the short line beside the whole sentence.
    @MainActor
    func testAPreviewCarriesBoth() throws {
        let world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000)),
            clock: GameClock(speed: .paused)
        )
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkSnapsToTrack = false
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 1_024 + 640, y: 2_048), reach: 16)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.problemBrief, "The ends are too close")
        XCTAssertEqual(preview.problem, NetworkProblem.tooClose.text(in: .english))
        let refusal = try XCTUnwrap(BuildConfirmLayout.refusal(of: preview))
        XCTAssertEqual(refusal.shown, "The ends are too close")
        XCTAssertEqual(refusal.spoken, preview.problem)
    }
}
