import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 711 (MAP3D-CAP): the still scene's triangles and buffers have
/// a limit, and the track is not drawn point by point.
final class Map3DSceneBudgetTests: XCTestCase {
    private typealias Key = Map3DStreaming.Key
    private typealias Builder = Map3DScene.Builder
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    private func coordinate(_ x: Double, _ y: Double, _ z: Double = 0) -> WorldCoordinate {
        WorldCoordinate(x: Int64((x * metre).rounded()), y: Int64((y * metre).rounded()), z: Int64((z * metre).rounded()))
    }

    // MARK: - The track's points

    /// A straight line with a point every 0.65 m (a bought real line's
    /// geometry) is drawn a piece every 16 m, as a line with no points
    /// between is.
    func testAStraightDenseLineIsDrawnAPieceAStep() {
        let line = stride(from: 0.0, through: 1_600, by: 0.65).map { coordinate($0, 0) } + [coordinate(1_600, 0)]
        let thinned = Builder.thinned(line)
        XCTAssertEqual(thinned.first, line.first)
        XCTAssertEqual(thinned.last, line.last)
        XCTAssertLessThanOrEqual(thinned.count, 110, "from \(line.count) points")
        XCTAssertGreaterThanOrEqual(thinned.count, 101)
        for (a, b) in zip(thinned, thinned.dropFirst()) {
            XCTAssertLessThanOrEqual(Double(b.x - a.x) / metre, Builder.trackStep + 0.001)
        }
    }

    /// Round a curve of 300 m, the drawn pieces stay within the tolerance
    /// of every point left out, and are far fewer than the points.
    func testACurveKeepsWithinTheTolerance() {
        let radius = 300.0
        let line = stride(from: 0.0, through: Double.pi / 2, by: 0.65 / radius).map { coordinate(radius * sin($0), radius * (1 - cos($0)), $0 * 10) }
        let thinned = Builder.thinned(line)
        XCTAssertLessThan(thinned.count * 5, line.count, "\(thinned.count) of \(line.count)")
        XCTAssertGreaterThan(thinned.count, 30, "a curve is not cut to a few chords")
        var piece = 0
        for point in line {
            while piece + 2 < thinned.count, thinned[piece + 1] != point, !isBetween(point, thinned[piece], thinned[piece + 1], in: line) { piece += 1 }
            let a = thinned[piece], b = thinned[piece + 1]
            let chord = (Double(b.x - a.x), Double(b.y - a.y), Double(b.z - a.z)), to = (Double(point.x - a.x), Double(point.y - a.y), Double(point.z - a.z))
            let length = (chord.0 * chord.0 + chord.1 * chord.1 + chord.2 * chord.2).squareRoot()
            let along = (to.0 * chord.0 + to.1 * chord.1 + to.2 * chord.2) / length
            let off = max(0, to.0 * to.0 + to.1 * to.1 + to.2 * to.2 - along * along).squareRoot()
            // A unit of rounding more than the tolerance.
            XCTAssertLessThanOrEqual(off / metre, Builder.trackTolerance + 0.02)
        }
    }

    private func isBetween(_ point: WorldCoordinate, _ a: WorldCoordinate, _ b: WorldCoordinate, in line: [WorldCoordinate]) -> Bool {
        guard let at = line.firstIndex(of: point), let from = line.firstIndex(of: a), let to = line.firstIndex(of: b) else { return false }
        return from <= at && at <= to
    }

    /// A line as the game's own track gives it (a point a step, and its
    /// corners) is drawn as before.
    func testALineWithNoPointsCloserThanAStepIsUnchanged() {
        let straight = [0.0, 16, 32, 48, 53].map { coordinate($0, 0) }
        XCTAssertEqual(Builder.thinned(straight), straight)
        let withACorner = [coordinate(0, 0), coordinate(16, 0), coordinate(21, 0), coordinate(37, 0), coordinate(37, 16)]
        XCTAssertEqual(Builder.thinned(withACorner), withACorner)
        XCTAssertEqual(Builder.thinned([coordinate(0, 0), coordinate(1, 0)]), [coordinate(0, 0), coordinate(1, 0)])
        // A kink is kept however close its points.
        let kink = [coordinate(0, 0), coordinate(1, 0), coordinate(1, 1), coordinate(2, 1)]
        XCTAssertEqual(Builder.thinned(kink), kink)
    }

    // MARK: - A frame's triangles

    private func cost(_ whole: Int, _ simplified: Int, _ ground: Int) -> Map3DSceneBudget.Cost {
        Map3DSceneBudget.Cost(whole: whole, simplified: simplified, ground: ground)
    }

    func testChunksWithinTheBudgetAreDrawnWhole() {
        let costs = Array(repeating: cost(100, 40, 10), count: 10)
        XCTAssertEqual(Map3DSceneBudget.shares(of: costs, within: 1_000), Array(repeating: .whole, count: 10))
        XCTAssertEqual(Map3DSceneBudget.shares(of: [], within: 1_000), [])
    }

    /// Past the budget the farther chunks are simplified, then their
    /// ground alone, then nothing; what is drawn never passes twice the
    /// budget.
    func testTheFartherChunksGiveWayFirst() {
        let costs = Array(repeating: cost(100, 40, 10), count: 200)
        let shares = Map3DSceneBudget.shares(of: costs, within: 1_000)
        XCTAssertEqual(shares.prefix(10), ArraySlice(repeating: .whole, count: 10))
        XCTAssertEqual(shares, shares.sorted(), "nearest first: no chunk fares better than one nearer")
        XCTAssertTrue(shares.contains(.ground))
        XCTAssertEqual(shares.last, .nothing)
        var drawn = 0, city = 0
        for (share, cost) in zip(shares, costs) {
            switch share {
            case .whole: drawn += cost.whole; city += cost.whole
            case .simplified: drawn += cost.simplified; city += cost.simplified
            case .ground: drawn += cost.ground
            case .nothing: break
            }
        }
        XCTAssertLessThanOrEqual(city, 1_000)
        XCTAssertLessThanOrEqual(drawn, 1_000 * Map3DSceneBudget.ceiling)
    }

    /// A chunk too heavy in full is drawn simplified, and a lighter one
    /// farther out still in full.
    func testAHeavyChunkIsSimplifiedOnItsOwn() {
        let shares = Map3DSceneBudget.shares(of: [cost(600, 100, 10), cost(900, 100, 10), cost(200, 100, 10)], within: 1_000)
        XCTAssertEqual(shares, [.whole, .simplified, .whole])
    }

    /// The budget follows the load ladder's tier down, and the buffers'
    /// the device's memory.
    func testTheBudgetsStepDownWithTheTier() {
        XCTAssertGreaterThan(Map3DSceneBudget.triangles(tier: .higher), Map3DSceneBudget.triangles(tier: .standard))
        XCTAssertGreaterThan(Map3DSceneBudget.triangles(tier: .standard), Map3DSceneBudget.triangles(tier: .lower))
        XCTAssertEqual(Map3DSceneBudget.triangles(tier: nil), Map3DSceneBudget.triangles(tier: .lower))
        XCTAssertGreaterThan(Map3DSceneBudget.bytes(memory: .ample), Map3DSceneBudget.bytes(memory: .roomy))
        XCTAssertGreaterThan(Map3DSceneBudget.bytes(memory: .roomy), Map3DSceneBudget.bytes(memory: .tight))
    }

    // MARK: - Letting go

    private func window() -> Map3DStreaming.Window {
        let half = 50_000 * metre, reach = Map3DScene.reach * metre
        let grid = Map3DStreaming(originX: half, originY: half, map: WorldRegion(minX: 0, minY: 0, maxX: 2 * half, maxY: 2 * half))
        return Map3DStreaming.Window(grid: grid, region: WorldRegion(minX: half - reach, minY: half - reach, maxX: half + reach, maxY: half + reach))
    }

    /// Memory short: the chunks farther than the camera sees are let go,
    /// the scene's own too, and the plan does not build them again while
    /// the target stays.
    func testSheddingLetsGoOfTheSceneFarFromTheTarget() {
        var window = window()
        let before = window.built.count
        XCTAssertGreaterThan(before, 400)
        let target = Map3DPoint(0, 0, 0)
        let drop = window.shed(farFrom: target, radius: 1_200)
        XCTAssertFalse(drop.isEmpty)
        XCTAssertEqual(window.built.count, before - drop.count)
        XCTAssertTrue(drop.allSatisfy { Map3DStreaming.distance(of: $0, to: target) > Map3DStreaming.around }, "what the plan keeps stays")
        XCTAssertTrue(window.built.allSatisfy { Map3DStreaming.distance(of: $0, to: target) <= Map3DStreaming.around })
        XCTAssertTrue(window.scene.isDisjoint(with: drop))
        XCTAssertGreaterThanOrEqual(Map3DStreaming.distance(of: drop[0], to: target), Map3DStreaming.distance(of: drop[drop.count - 1], to: target),
                                    "the farthest first")
        let step = window.step(target: target, at: 0)
        XCTAssertTrue(step.build.isEmpty && step.drop.isEmpty, "nothing built again, nothing more let go")
        // From its farthest the camera sees the whole scene: nothing goes.
        var far = self.window()
        XCTAssertTrue(far.shed(farFrom: target, radius: Map3DCamera.farthest).isEmpty)
    }

    /// The chunks let go come back when the target moves to them.
    func testChunksLetGoAreBuiltAgainWhenTheTargetComes() {
        var window = window()
        _ = window.shed(farFrom: Map3DPoint(0, 0, 0), radius: 0)
        let there = Map3DPoint(5_000, 0, 0)
        let step = window.step(target: there, at: 0)
        XCTAssertFalse(step.build.isEmpty)
        XCTAssertTrue(step.build.allSatisfy { Map3DStreaming.distance(of: $0, to: there) <= Map3DStreaming.around })
    }

    /// And when the camera draws back to see that far: built again, the
    /// nearest first, and the scene's again, so the plan does not let them
    /// go as chunks built ahead.
    func testChunksLetGoAreBuiltAgainWhenTheCameraSeesThem() {
        var window = window()
        let target = Map3DPoint(0, 0, 0)
        let drop = Set(window.shed(farFrom: target, radius: 0))
        XCTAssertEqual(window.gone, drop)
        XCTAssertTrue(window.step(target: target, at: 0, sight: 1_200).build.isEmpty)
        var seconds = 1.0, built = Set<Key>()
        while true {
            let step = window.step(target: target, at: seconds, sight: 5_000)
            XCTAssertTrue(step.drop.isEmpty, "none of them let go again")
            guard !step.build.isEmpty else { break }
            XCTAssertTrue(step.build.allSatisfy(drop.contains))
            XCTAssertTrue(window.finished(step.build, generation: window.generation))
            built.formUnion(step.build)
            seconds += 1
        }
        XCTAssertEqual(built, drop.filter { Map3DStreaming.distance(of: $0, to: target) <= 5_000 })
        XCTAssertTrue(window.scene.isSuperset(of: built))
        XCTAssertTrue(window.gone.isDisjoint(with: built))
    }

    /// A window made for a scene built again in part forgets the chunks
    /// the view no longer holds.
    func testAWindowForgetsWhatWasLetGo() {
        var first = window()
        let drop = first.shed(farFrom: Map3DPoint(0, 0, 0), radius: 0)
        var second = window()
        second.letGo(drop)
        XCTAssertEqual(second.built, first.built)
        XCTAssertEqual(second.scene, first.scene)
    }
}
