import XCTest
@testable import GamePresentation

/// PERF_3D_COCKPIT (2026-10-30): the 2D map under the 3D map's cover
/// (``CoveredMap``).
final class CoveredMapTests: XCTestCase {
    /// What one tick of the 2D map runs: whether its camera follows the
    /// train frame by frame, whether the tick moves it, whether its glides
    /// run, whether the tick's traffic reaches it.
    private struct Work: Equatable {
        var followsGlide, followsTick, glides, takesTraffic: Bool

        init(covered: Bool, following: Bool = true, running: Bool = true, moving: Bool = true) {
            followsGlide = CoveredMap.followsGlide(following: following, running: running, trainsMoving: moving, covered: covered)
            followsTick = CoveredMap.followsTick(gliding: followsGlide, covered: covered)
            glides = CoveredMap.glides(running && moving, covered: covered)
            takesTraffic = CoveredMap.takesTraffic(covered: covered)
        }

        /// The same tick with nothing run.
        var nothing: Self {
            var none = self
            none.followsGlide = false
            none.followsTick = false
            none.glides = false
            none.takesTraffic = false
            return none
        }
    }

    /// The owner's cockpit: a train followed, the game running, trains
    /// gliding. While the 3D map is shown, no tick and no frame does any of
    /// the 2D map's work.
    func testWhileThe3DMapIsShownTheHidden2DMapDoesNothingPerTick() {
        for following in [false, true] {
            for running in [false, true] {
                for moving in [false, true] {
                    let work = Work(covered: true, following: following, running: running, moving: moving)
                    XCTAssertEqual(work, work.nothing, "following \(following), running \(running), moving \(moving)")
                }
            }
        }
    }

    /// The moment the 3D map closes, the 2D map reads the traffic again and
    /// snaps to its train once, and its frames run again from that tick.
    func testWhenThe3DMapClosesItRefreshesAtOnce() {
        let shown = [true, true, true, false, false]
        var refreshes: [Int] = []
        var was = false
        for (tick, covered) in shown.enumerated() {
            if CoveredMap.refreshesOnUncover(wasCovered: was, covered: covered) { refreshes.append(tick) }
            was = covered
        }
        XCTAssertEqual(refreshes, [3])
        let after = Work(covered: false)
        XCTAssertTrue(after.followsGlide)
        XCTAssertTrue(after.glides)
        XCTAssertTrue(after.takesTraffic)
        // Opening it refreshes nothing.
        XCTAssertFalse(CoveredMap.refreshesOnUncover(wasCovered: false, covered: true))
        XCTAssertFalse(CoveredMap.refreshesOnUncover(wasCovered: false, covered: false))
    }

    /// With no 3D map over it, the 2D map does what it did before: the
    /// camera glides with a followed, gliding train in a running game, and
    /// a tick moves it otherwise (decision 182, later).
    func testUncoveredTheMapIsAsBefore() {
        for following in [false, true] {
            for running in [false, true] {
                for moving in [false, true] {
                    let work = Work(covered: false, following: following, running: running, moving: moving)
                    let gliding = following && running && moving
                    XCTAssertEqual(work.followsGlide, gliding)
                    XCTAssertEqual(work.followsTick, !gliding)
                    XCTAssertEqual(work.glides, running && moving)
                    XCTAssertTrue(work.takesTraffic)
                }
            }
        }
    }
}
