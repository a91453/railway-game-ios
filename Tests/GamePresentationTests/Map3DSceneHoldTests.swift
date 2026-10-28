@testable import GamePresentation
import XCTest

/// Review L-1: the 3D map's scene let go while it still builds is held
/// until the build ends, so a 3D map opened again meanwhile takes it
/// instead of building a second scene beside it.
final class Map3DSceneHoldTests: XCTestCase {
    func testABuildEndedIsLetGoAtOnce() {
        var hold = Map3DSceneHold()
        let build = hold.start()
        XCTAssertFalse(hold.finished(build), "built and not let go: kept")
        XCTAssertTrue(hold.isBuilt)
        XCTAssertTrue(hold.clear(), "built: let go at once")
        XCTAssertNil(hold.building)
    }

    func testABuildStillRunningIsLetGoOnceItEnds() {
        var hold = Map3DSceneHold()
        let build = hold.start()
        XCTAssertFalse(hold.clear(), "still building: held")
        XCTAssertEqual(hold.building, build, "a 3D map opened now takes it")
        XCTAssertTrue(hold.dropsWhenBuilt)
        XCTAssertTrue(hold.finished(build), "ended: let go then")
        XCTAssertNil(hold.building)
    }

    func testAskedForAgainWhileHeldItStays() {
        var hold = Map3DSceneHold()
        let build = hold.start()
        XCTAssertFalse(hold.clear())
        hold.reuse()
        XCTAssertFalse(hold.finished(build), "opened again before it ended: kept")
        XCTAssertEqual(hold.building, build)
    }

    func testAnOlderBuildEndingChangesNothing() {
        var hold = Map3DSceneHold()
        let old = hold.start()
        XCTAssertFalse(hold.clear())
        let new = hold.start()
        XCTAssertNotEqual(old, new)
        XCTAssertFalse(hold.finished(old), "another build is held now")
        XCTAssertEqual(hold.building, new)
        XCTAssertFalse(hold.dropsWhenBuilt)
        XCTAssertFalse(hold.isBuilt)
    }

    func testNothingHeldClearsAtOnce() {
        var hold = Map3DSceneHold()
        XCTAssertTrue(hold.clear())
        let first = hold.start()
        XCTAssertFalse(hold.clear())
        XCTAssertTrue(hold.finished(first))
        XCTAssertGreaterThan(hold.start(), first, "numbers go on after a let go")
    }
}
