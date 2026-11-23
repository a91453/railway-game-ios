@testable import GamePresentation
import GameCore
import XCTest

/// Decision 941: a level crossing's yellow hatching and rubber panels
/// (the reference's `level-crossing.js`), and its booms coming down and
/// going up as the trains pass (the reference's `crossing-cycle.js`).
final class Map3DLevelCrossingDeckTests: XCTestCase {
    private let square = Map3DLevelCrossing(point: Map3DPoint(0, Map3DScene.railLift, 0), along: Map3DPoint(1, 0, 0), kind: .tertiary)

    /// The reference's numbers, as taken: the deck level 3.2 m past the
    /// track (`FLAT`); its ramp, raise and lift kept for the record.
    func testTheReferencesNumbers() {
        XCTAssertEqual(Map3DLevelCrossing.deckHalf, 3.2)
        XCTAssertEqual(Map3DLevelCrossingDeck.referenceRamp, 5)
        XCTAssertEqual(Map3DLevelCrossingDeck.referenceRaise, 0.15)
        XCTAssertEqual(Map3DLevelCrossingDeck.referenceLift, Map3DScene.Builder.lift(of: .tertiary))
        XCTAssertEqual(Map3DPalette.crossingHatch, Map3DColor.rgb(0xCDA019))
        XCTAssertTrue(Map3DLook.functional.contains(Map3DPalette.crossingHatch), "the look keeps the hatching's yellow")
    }

    /// The hatching: two sets of lines at 45° to the street, within the
    /// carriageway and short of the ramps' foot, none on the rails.
    func testTheHatchingKeepsOffTheRailsAndWithinTheBarriers() throws {
        let slanting = Map3DLevelCrossing(point: .zero, along: Map3DPoint(1, 0, 0), kind: .tertiary,
                                          trackWay: Map3DPoint(0.5, 0, Float(0.75).squareRoot()), spread: 4)
        for crossing in [square, Map3DLevelCrossing(point: .zero, along: Map3DPoint(0, 0, 1), kind: .primary, spread: 4), slanting] {
            let pieces = Map3DLevelCrossingDeck.hatch(crossing)
            XCTAssertGreaterThan(pieces.count, 20)
            let reach = Map3DLevelCrossingDeck.hatchReach(of: crossing), hw = crossing.kind.width(ramp: false) / 2
            let wt = Map3DLevelCrossingDeck.slant(of: crossing).wt
            var slopes = Set<Int>()
            for piece in pieces {
                XCTAssertEqual(piece.count, 4)
                let s = piece.map { ($0 - crossing.point).dot(crossing.along) }, t = piece.map { ($0 - crossing.point).dot(crossing.across) }
                let n = zip(s, t).map { Map3DLevelCrossingDeck.fromTracks(crossing, s: $0, t: $1) }
                XCTAssertLessThanOrEqual(n.map(abs).max()!, reach - Map3DLevelCrossingDeck.hatchEnd + 0.1)
                XCTAssertLessThanOrEqual(t.map(abs).max()!, hw - Map3DLevelCrossingDeck.hatchEdge + 0.01)
                let middle = n.reduce(0, +) / 4
                for track in Map3DLevelCrossingDeck.tracks(of: crossing) {
                    XCTAssertGreaterThanOrEqual(abs(middle - track * wt), Map3DLevelCrossingDeck.railClear - 0.01, "on the rails")
                }
                // Its run along the street is its run across it, one way or the other.
                let ds = (s[1] - s[0]), dt = (t[1] - t[0])
                XCTAssertEqual(abs(ds), abs(dt), accuracy: 1e-4)
                slopes.insert(ds * dt > 0 ? 1 : -1)
            }
            XCTAssertEqual(slopes, [1, -1], "two sets of diagonals")
        }
    }

    /// The panels: one over each track crossed, across the deck, along
    /// their track.
    func testAPanelOverEachTrack() {
        XCTAssertEqual(Map3DLevelCrossingDeck.panels(square).count, 1)
        let double = Map3DLevelCrossing(point: .zero, along: Map3DPoint(1, 0, 0), kind: .tertiary, spread: 4)
        let panels = Map3DLevelCrossingDeck.panels(double)
        XCTAssertEqual(panels.count, 2)
        XCTAssertEqual(panels[0].map(\.x).min()!, -2 - Map3DLevelCrossingDeck.panelHalf, accuracy: 1e-4)
        XCTAssertEqual(panels[1].map(\.x).max()!, 2 + Map3DLevelCrossingDeck.panelHalf, accuracy: 1e-4)
        let slanting = Map3DLevelCrossing(point: .zero, along: Map3DPoint(1, 0, 0), kind: .tertiary, trackWay: Map3DPoint(0.6, 0, 0.8))
        let panel = try! XCTUnwrap(Map3DLevelCrossingDeck.panels(slanting).first)
        XCTAssertEqual(try! XCTUnwrap((panel[1] - panel[0]).normalized).cross(Map3DPoint(0.6, 0, 0.8)).length, 0, accuracy: 1e-4)
    }

    /// In a town's scene: the hatching is painted on its crossings, every
    /// crossing knows its two posts, and no boom is baked with them.
    func testATownsCrossingsAreHatchedAndTheirBoomsLeftToTheTrains() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        XCTAssertFalse(scene.levelCrossings.isEmpty)
        let hatched = scene.chunks.flatMap(\.mesh.vertices).filter { $0.color == Map3DPalette.crossingHatch }
        XCTAssertGreaterThan(hatched.count, scene.levelCrossings.count * 20 * 4 / 2)
        for vertex in hatched {
            XCTAssertTrue(scene.levelCrossings.contains { abs(($0.point - vertex.position).dot($0.along)) < $0.rampEnd + 0.5 })
        }
        for crossing in scene.levelCrossings { XCTAssertEqual(crossing.gateFeet.map(\.end), [-1, 1]) }
        // The posts' lamps without their booms' stripes over 3 m.
        let posts = scene.chunks.flatMap(\.mesh.vertices).filter { $0.color == Map3DScene.Builder.barrierBlack }
        XCTAssertFalse(posts.isEmpty)
        for crossing in scene.levelCrossings {
            XCTAssertFalse(posts.contains { ($0.position - crossing.point).length < 20 && $0.y > crossing.point.y + 3.5 }, "a boom baked")
        }
    }

    /// The reference's cycle: bells 6 s before, the booms down from 4 s to
    /// 2 s before the front arrives, up 0.8 s after the last car clears,
    /// in 2.2 s.
    func testTheBoomsComeDownBeforeTheTrainAndGoUpAfterIt() {
        let length: Float = 40, speed: Float = 10
        // The middle `seconds` from the front's arrival (3.5 m short).
        func state(_ seconds: Float) -> Map3DCrossingCycle.State {
            Map3DCrossingCycle.state(centre: seconds * speed - length / 2 - 3.5, length: length, speed: speed)
        }
        XCTAssertEqual(state(-7).closed, 0)
        XCTAssertFalse(state(-7).bells)
        XCTAssertTrue(state(-5).bells)
        XCTAssertEqual(state(-5).closed, 0)
        XCTAssertEqual(state(-3).closed, 0.5, accuracy: 1e-4)
        XCTAssertEqual(state(-2).closed, 1, accuracy: 1e-4)
        XCTAssertTrue(state(1).occupied)
        XCTAssertEqual(state(1).closed, 1)
        // The last car 3.5 m past at (length + 7) / speed after the front.
        let cleared = (length + 7) / speed
        XCTAssertEqual(state(cleared + 0.5).closed, 1)
        XCTAssertEqual(state(cleared + 0.8 + 1.1).closed, 0.5, accuracy: 1e-4)
        XCTAssertEqual(state(cleared + 3.1).closed, 0)
        XCTAssertFalse(state(cleared + 3.1).bells)
        // Standing on the crossing holds them down; standing off it, not.
        XCTAssertEqual(Map3DCrossingCycle.state(centre: 0, length: length, speed: 0).closed, 1)
        XCTAssertEqual(Map3DCrossingCycle.state(centre: -80, length: length, speed: 0).closed, 0)
    }

    /// A train on the crossing's track puts its booms down; one beside it
    /// on another line, or across it, does not.
    func testOnlyATrainOnTheCrossingsTrackPutsItsBoomsDown() {
        let crossing = Map3DLevelCrossing(point: .zero, along: Map3DPoint(1, 0, 0), kind: .tertiary, trackWay: Map3DPoint(0, 0, 1))
        func head(_ middle: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, 1)) -> Map3DTrains.Head {
            var head = Map3DTrains.Head(train: TrainID(rawValue: 1), point: middle, forward: forward)
            head.middle = middle + Map3DPoint(0, Map3DScene.railLift, 0)
            head.length = 40
            head.speed = 10
            return head
        }
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(0, 0, -10))]), 1)
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(0, 0, -200))]), 0)
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(30, 0, -10))]), 0, "another line")
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(0, 0, -10), forward: Map3DPoint(1, 0, 0))]), 0, "across")
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(0, 20, -10))]), 0, "on a viaduct over it")
        // Behind it, going away, it is past.
        XCTAssertEqual(Map3DCrossingBooms.closed(crossing, heads: [head(Map3DPoint(0, 0, 200))]), 0)
    }

    /// Raised, the instance's boom stands where the baked one did; lowered,
    /// it reaches level across the street.
    func testTheBoomTurnsAboutItsPivot() throws {
        let arm = try XCTUnwrap(Map3DCrossingGate.arm), raised = try XCTUnwrap(Map3DCrossingGate.raised)
        let foot = Map3DPoint(10, 2, -5), reach = Map3DPoint(0, 0, 1), facing = Map3DPoint(1, 0, 0)
        func placed(_ closed: Float) -> [Map3DPoint] {
            let m = Map3DCrossingGate.boomTransform(at: foot, reach: reach, facing: facing, closed: closed)
            return arm.vertices.map { v in
                Map3DPoint(m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12], m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13],
                           m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14])
            }
        }
        let up = Map3DPoint(0, 1, 0)
        let baked = raised.dropFirst(348 * 3).map { foot + reach * $0.x + facing * $0.y + up * $0.z }
        for (a, b) in zip(placed(0), baked) { XCTAssertEqual((a - b).length, 0, accuracy: 1e-4) }
        let lowered = placed(1)
        XCTAssertEqual(lowered.map(\.y).max()!, 2 + 1 + 0.06, accuracy: 0.01, "level at the pivot's height")
        XCTAssertEqual(lowered.map(\.z).max()!, -5 + 0.14 + arm.maximum.x, accuracy: 0.01, "across the street")
    }

    /// Drawn with the trains, two booms a crossing near the eye, none far.
    func testTheBoomsAreDrawnNearTheEye() throws {
        let pack = Map3DModelPack(models: Map3DCrossingGate.drawn)
        var crossing = square
        crossing.gateFeet = [(-1, Map3DPoint(-5, 1, 4)), (1, Map3DPoint(5, 1, -4))]
        let booms = Map3DCrossingBooms.instances([crossing], heads: [], pack: pack, eye: Map3DPoint(0, 100, 0))
        XCTAssertEqual(booms.count, 2)
        // As long as the street is wide (the reference's `2 * hw`).
        let x = Map3DPoint(booms[0].transform[0], booms[0].transform[1], booms[0].transform[2])
        XCTAssertEqual(x.length * pack.models[0].maximum.x, crossing.kind.width(ramp: false), accuracy: 1e-3)
        XCTAssertTrue(Map3DCrossingBooms.instances([crossing], heads: [], pack: pack, eye: Map3DPoint(0, 2_000, 0)).isEmpty)
        XCTAssertTrue(Map3DCrossingBooms.instances([crossing], heads: [], pack: Map3DModelPack(models: []), eye: .zero).isEmpty)
    }
}
