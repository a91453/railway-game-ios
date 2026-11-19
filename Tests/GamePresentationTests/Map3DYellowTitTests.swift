import XCTest
@testable import GamePresentation

/// Decision 889: the station master's yellow tit in 3D, landing now and
/// then on the platform the camera looks at.
final class Map3DYellowTitTests: XCTestCase {
    private typealias Tit = Map3DYellowTit

    /// Each pose decodes, in the palette's five colours only, at about a
    /// pigeon's size (the studio's 13 cm bird, six times).
    func testThePosesDecodeInThePalette() throws {
        let palette = Set(Tit.meshPalette)
        for pose in Tit.Pose.allCases {
            let model = try XCTUnwrap(Tit.model(pose), "\(pose)")
            XCTAssertFalse(model.vertices.isEmpty)
            XCTAssertTrue(model.vertices.allSatisfy { palette.contains($0.color) }, "\(pose)")
            let length = model.maximum.x - model.minimum.x
            XCTAssertGreaterThan(length, 0.6, "\(pose)")
            XCTAssertLessThan(length, 1.0, "\(pose)")
        }
        // Perched, its feet on the ground (models are +z up) and its beak along +x.
        let perch = try XCTUnwrap(Tit.model(.perch))
        XCTAssertEqual(perch.minimum.z, 0, accuracy: 0.01)
        XCTAssertEqual(Tit.drawn.map(\.name), Tit.Pose.allCases.map(\.rawValue))
    }

    private let line = Map3DStreetLife.Path([Map3DPoint(0, 5, 0), Map3DPoint(100, 5, 0)])!

    /// The first visiting window after `from`.
    private func visit(after from: Double = 0) -> Double {
        var start = (from / Tit.every).rounded(.up) * Tit.every
        while !Tit.isVisiting(at: start) { start += Tit.every }
        return start
    }

    private func drawn(_ seconds: Double, daytime: Bool = true, still: Bool = false, target: Map3DPoint = Map3DPoint(40, 5, 8),
                       eye: Map3DPoint = Map3DPoint(40, 60, 60), underground: Bool = false) -> Tit.Drawn? {
        Tit.drawn(at: seconds, platforms: [line], target: target, eye: eye, daytime: daytime, still: still) { _ in underground }
    }

    /// It flies in, lands on the platform nearest what the camera looks
    /// at, stays, and flies on along it; then it is gone.
    func testItLandsOnThePlatformTheCameraLooksAt() throws {
        let start = visit()
        let landed = try XCTUnwrap(drawn(start + Tit.flyIn + 1))
        XCTAssertEqual(landed.pose, .perch)
        XCTAssertEqual(landed.point.x, 40, accuracy: 0.01)
        XCTAssertEqual(landed.point.y, 5, accuracy: 0.01)
        let coming = try XCTUnwrap(drawn(start + 0.2))
        XCTAssertNotEqual(coming.pose, .perch)
        XCTAssertGreaterThan(coming.point.y, 5 + Tit.height / 2)
        XCTAssertEqual(abs(coming.point.x - 40), Tit.approach, accuracy: 3)
        // Flying on the way it came, ahead of where it landed.
        let going = try XCTUnwrap(drawn(start + Tit.visit - 0.1))
        XCTAssertGreaterThan((going.point.x - 40) * landed.forward.x, Tit.approach / 2)
        XCTAssertEqual(coming.forward, going.forward)
        XCTAssertNil(drawn(start + Tit.visit + 0.1))
    }

    /// Never at night, with Reduce Motion, underground, from afar or far
    /// from any platform.
    func testItStaysAwayAtNightUndergroundAndFromAfar() {
        let t = visit() + Tit.flyIn + 1
        XCTAssertNotNil(drawn(t))
        XCTAssertNil(drawn(t, daytime: false))
        XCTAssertNil(drawn(t, still: true))
        XCTAssertNil(drawn(t, underground: true))
        XCTAssertNil(drawn(t, eye: Map3DPoint(40, 400, 400)))
        XCTAssertNil(drawn(t, target: Map3DPoint(40, 5, 200)))
    }

    /// Now and then: two in three windows, so a few minutes hold some
    /// visits but not every window, and at most one bird at a time.
    func testItComesNowAndThen() {
        let windows = (0..<60).map { Tit.visits(Int64($0)) }
        let count = windows.filter { $0 }.count
        XCTAssertGreaterThan(count, 30)
        XCTAssertLessThan(count, 55)
        XCTAssertLessThan(Tit.visit, Tit.every)
    }

    /// Its flight undulates: flaps, then a glide.
    func testItFlapsThenGlides() {
        let poses = stride(from: 0.0, to: Tit.bout, by: Tit.beat / 2).map { Tit.flight(at: $0 + 0.001) }
        XCTAssertTrue(poses.contains(.wingsUp))
        XCTAssertTrue(poses.contains(.wingsDown))
        XCTAssertEqual(poses.last, .glide)
    }

    /// It is in the game's pack, after Finland's street furniture.
    func testItIsInThePack() throws {
        let pack = Map3DModelPack.standard
        for pose in Tit.Pose.allCases { XCTAssertNotNil(pack.index(of: pose.rawValue), "\(pose)") }
        var frame = Map3DTrains.Frame()
        let tit = try XCTUnwrap(drawn(visit() + Tit.flyIn + 1))
        Tit.add(tit, to: &frame, pack: pack)
        XCTAssertEqual(frame.instances.count, 1)
    }
}
