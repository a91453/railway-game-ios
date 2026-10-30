import GameCore
import GamePresentation
import XCTest

/// The build card names the one thing that stops a stretch, not the list of
/// everything GameCore checks (PLAYER_FEEDBACK 97.1: "0 m" and four reasons).
/// Nodes stay within 64 m of the ground, so a height gap and a spot twice
/// cannot be reached through taps; they are asked of the function directly.
final class NetworkGeometryProblemTests: XCTestCase {
    func testEachReasonHasItsOwnSentenceInBothLanguages() {
        var seen: Set<String> = []
        for reason in NetworkBuilding.GeometryProblem.allCases {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let text = reason.text(in: language)
                XCTAssertFalse(text.contains("64"), text)
                XCTAssertTrue(seen.insert(text).inserted, text)
            }
        }
    }

    func testTheReasonIsTheOneThatApplies() throws {
        let bounds = try WorldBounds(width: 16_384, height: 8_192)
        let a = WorldCoordinate(x: 2_048, y: 2_048, z: 0)
        XCTAssertEqual(NetworkBuilding.geometryProblem(from: a, to: WorldCoordinate(x: 2_048, y: 2_048, z: 64), curve: .straight, bounds: bounds), .sameSpot)
        XCTAssertEqual(NetworkBuilding.geometryProblem(from: a, to: WorldCoordinate(x: 20_000, y: 2_048, z: 0), curve: .straight, bounds: bounds), .outsideMap)
        XCTAssertEqual(NetworkBuilding.geometryProblem(from: a, to: WorldCoordinate(x: 6_144, y: 2_048, z: 20_000), curve: .straight, bounds: bounds), .heightGap)
        // A handle that folds the curve back on itself.
        let fold = TrackCurve.cubic(PlanPoint(x: 6_000, y: 2_048), PlanPoint(x: 1_000, y: 2_048))
        XCTAssertEqual(NetworkBuilding.geometryProblem(from: a, to: WorldCoordinate(x: 4_096, y: 2_048, z: 0), curve: fold, bounds: bounds), .tooBent)
    }
}
