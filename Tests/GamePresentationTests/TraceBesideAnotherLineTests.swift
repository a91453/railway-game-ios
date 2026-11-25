import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 972: a trace that starts where two real lines are drawn side
/// by side takes the one that leads to its other end, and a step from one
/// line to the one beside it is laid slanting. The owner's trace from
/// beside Su'aoxin's junction to Su'ao (3,154 m) was refused, "the real
/// line bends too tightly here": the way ran up the North-Link Line to its
/// end in the station, stepped 12.7 m across to the Yilan Line and came
/// back, a curve of 2 m.
@MainActor
final class TraceBesideAnotherLineTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    private func session() throws -> GameSession {
        let start = try BundledRealData.station("蘇澳新", in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(start.anchor)), language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        return session
    }

    private func point(_ station: String, in session: GameSession) throws -> WorldVector {
        WorldVector(try BundledRealData.point(try BundledRealData.station(station, in: "tra_sched").coordinate, in: session.world))
    }

    /// The North-Link Line, which ends in Su'aoxin, and the Yilan Line,
    /// which runs through it to Su'ao.
    private func lines(in session: GameSession) throws -> (northLink: RealRailwayTraces.Line, yilan: RealRailwayTraces.Line) {
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let suao = try XCTUnwrap(traces.snap(try point("蘇澳", in: session), within: 100 * metre))
        let xin = try point("蘇澳新", in: session)
        let northLink = try XCTUnwrap(traces.lines.first { line in
            line.system == "tra_sched" && line.id != suao.place.line && (line.path.point(at: line.path.length) - xin).length < 100 * metre
        })
        return (northLink, traces.lines[suao.place.line])
    }

    /// From the North-Link Line beside the junction, 150 to 500 m short of
    /// its end, where the Yilan Line is 9 to 21 m beside it: the whole way
    /// to Su'ao is laid, about as long as the Yilan Line from there, with
    /// no curve tighter than the tool lays.
    func testATraceFromBesideTheJunctionReachesSuao() throws {
        let session = try session()
        let lines = try lines(in: session)
        let suao = try point("蘇澳", in: session)
        for back in [150.0, 300.0, 450.0, 500.0] {
            let from = lines.northLink.path.point(at: lines.northLink.path.length - back * metre)
            let plan = try XCTUnwrap(session.tracePlan(from: .point(from.plan), to: .point(suao.plan)), "\(back)")
            XCTAssertNil(plan.problem, "\(back) m back")
            XCTAssertEqual(plan.buildable, plan.stretches.count, "\(back) m back")
            let tightest = plan.stretches.compactMap(GameSession.tightestRadius(of:)).min() ?? .infinity
            XCTAssertGreaterThan(tightest, 100 * metre, "\(back) m back")
            let length = plan.stretches.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve)?.length }.reduce(0, +)
            let direct = lines.yilan.path.project(from)
            XCTAssertEqual(Double(length), direct, accuracy: 60 * metre, "\(back) m back: no way up to the station and back")
        }
    }

    /// A trace along the North-Link Line itself keeps to it, though the
    /// Yilan Line is within reach at one end.
    func testATraceAlongOneLineKeepsToIt() throws {
        let session = try session()
        let line = try lines(in: session).northLink.path
        let a = line.point(at: line.length - 300 * metre).plan, b = line.point(at: line.length - 1_500 * metre).plan
        let from = WorldCoordinate(x: a.x, y: a.y, z: 0), to = WorldCoordinate(x: b.x, y: b.y, z: 0)
        let way = try XCTUnwrap(session.tracedWay(from: from, to: to, reach: 44 * metre))
        XCTAssertLessThan(way.map { line.nearest($0).away }.max() ?? .infinity, 1 * metre)
    }

    /// From track laid on the North-Link Line, where the two lines part at
    /// some 20°: the trace leaves the track along it, as a turnout does.
    func testATraceLeavesTrackLaidBesideTheLineAlongIt() throws {
        let session = try session()
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        let line = try lines(in: session).northLink.path
        session.tapNetwork(at: line.point(at: line.length).plan, reach: reach)
        session.tapNetwork(at: line.point(at: line.length - 1_500 * metre).plan, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.clearNetworkDraft()
        for back in [150.0, 450.0] {
            session.tapNetwork(at: line.point(at: line.length - back * metre).plan, reach: reach)
            session.tapNetwork(at: try point("蘇澳", in: session).plan, reach: reach)
            let preview = try XCTUnwrap(session.networkPreview(now: true))
            XCTAssertNil(preview.problem, "\(back) m back")
            XCTAssertTrue(preview.joinsStart, "\(back) m back")
            session.clearNetworkDraft()
        }
    }

    /// Farther down the North-Link Line, out of reach of the Yilan Line,
    /// the only way to Su'ao turns back in Su'aoxin, as the trains do: the
    /// refusal says that, not a curve's radius.
    func testAWayThatTurnsBackSaysSo() throws {
        let session = try session()
        let line = try lines(in: session).northLink.path
        let from = line.point(at: line.length - 900 * metre)
        let plan = try XCTUnwrap(session.tracePlan(from: .point(from.plan), to: .point(try point("蘇澳", in: session).plan)))
        XCTAssertLessThan(plan.buildable, plan.stretches.count)
        XCTAssertEqual(plan.brief, "真實鐵路在這裡要折返")
    }

    /// A step to the side becomes a slant with no corner: 12 m across
    /// between two lines 400 m long, eased over √(4 × 300 × 12) = 120 m.
    func testAStepToTheSideIsLaidSlanting() {
        let first = stride(from: 0.0, through: 400, by: 20).map { WorldVector(x: $0 * metre, y: 0) }
        let second = stride(from: 400.0, through: 800, by: 20).map { WorldVector(x: $0 * metre, y: 12 * metre) }
        let eased = RealRailwayTraces.eased(first + second, hops: [first.count - 1])
        XCTAssertEqual(eased.first, first.first)
        XCTAssertEqual(eased.last, second.last)
        var sharpest = 0.0
        for index in 1..<(eased.count - 1) {
            sharpest = max(sharpest, (eased[index] - eased[index - 1]).angle(to: eased[index + 1] - eased[index]))
        }
        XCTAssertLessThan(sharpest, 6 * Double.pi / 180, "no corner")
        XCTAssertEqual(eased.filter { $0.y > 1 && $0.y < 12 * metre - 1 }.map(\.x).min() ?? 0, 340 * metre, accuracy: 15 * metre)
        XCTAssertEqual(eased.filter { $0.y > 1 && $0.y < 12 * metre - 1 }.map(\.x).max() ?? 0, 460 * metre, accuracy: 15 * metre)

        // A step shorter than 2 m, and a way with none, stay as they are.
        let near = second.map { WorldVector(x: $0.x, y: 1 * metre) }
        XCTAssertEqual(RealRailwayTraces.eased(first + near, hops: [first.count - 1]), first + near)
        XCTAssertEqual(RealRailwayTraces.eased(first, hops: []), first)

        // From a point on track, along the track there.
        let track = WorldVector(x: 0, y: 12 * metre)
        let left = RealRailwayTraces.eased([track] + first, hops: [0], leaving: WorldVector(x: 1, y: 0))
        XCTAssertEqual(left.first, track)
        XCTAssertLessThan((left[1] - left[0]).angle(to: WorldVector(x: 1, y: 0)), 6 * Double.pi / 180)
    }
}
