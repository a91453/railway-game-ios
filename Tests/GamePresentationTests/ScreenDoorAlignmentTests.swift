import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 859: a train standing at a platform with screen doors stands
/// with its doors at the doors' openings. GameCore stops a train with its
/// head at the platform's far end the way it travels; the doors, the queue
/// lines and the stop boards had been laid for a train standing in the
/// platform's middle, and a bought line's platform is longer than its
/// train ((cars + 1) × 16 m: the Wenhu Line's 80 m for its 50 m trains,
/// the Tung Chung Line's 48 m for its 39 m ones), so every door stood
/// 4.5 to 15 m from its opening.
@MainActor
final class ScreenDoorAlignmentTests: XCTestCase {
    typealias Point = TrainMotion.Point
    typealias Props = Map3DPlatformProps
    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// A metro car's door, 1.3 m wide (Taipei's 1.3 m, the MTR's 1.4 m
    /// less the frame).
    static let doorLeaf = 1.3

    // MARK: Along the platform

    func testTheDoorsAreAtTheEndTheTrainsComeInTowards() {
        let four = Props.Formation(cars: 4, carLength: 12.5, doors: 2)
        XCTAssertEqual(Props.trainStarts(length: 80, train: 50, stands: []), [15], "not known: in the middle, as before")
        XCTAssertEqual(Props.trainStarts(length: 80, train: 50, stands: .forward), [30])
        XCTAssertEqual(Props.trainStarts(length: 80, train: 50, stands: .backward), [0])
        XCTAssertEqual(Props.trainStarts(length: 80, train: 50, stands: [.forward, .backward]), [0, 30])

        let forward = Props.doorCentres(length: 80, formations: [four], kind: .metro, stands: .forward)
        XCTAssertEqual(forward.count, 8)
        XCTAssertEqual(forward.first ?? 0, 30 + 3.125, accuracy: 0.001)
        XCTAssertEqual(forward.last ?? 0, 80 - 3.125, accuracy: 0.001)
        let backward = Props.doorCentres(length: 80, formations: [four], kind: .metro, stands: .backward)
        XCTAssertEqual(backward.first ?? 0, 3.125, accuracy: 0.001)
        XCTAssertEqual(backward.last ?? 0, 50 - 3.125, accuracy: 0.001)
        // Both ways: each way's doors, those within half a door of each
        // other once.
        let both = Props.doorCentres(length: 80, formations: [four], kind: .metro, stands: [.forward, .backward])
        XCTAssertEqual(Set(both.map { ($0 * 1000).rounded() }), Set((forward + backward).map { ($0 * 1000).rounded() }))
        let flush = Props.doorCentres(length: 50, formations: [four], kind: .metro, stands: [.forward, .backward])
        XCTAssertEqual(flush.count, 8, "a train as long as its platform stands in the same place either way")

        // The screen doors' openings at those doors, the panels the whole
        // platform long.
        let pieces = Map3DScreenDoors.pieces(length: 80, formations: [four], stands: .forward)
        let openings = pieces.filter(\.door).map { ($0.from + $0.to) / 2 }
        XCTAssertEqual(openings.count, forward.count)
        for (opening, door) in zip(openings, forward) { XCTAssertEqual(opening, door, accuracy: 0.001) }
        XCTAssertEqual(pieces.first?.from ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(pieces.last?.to ?? 0, 79.8, accuracy: 0.001)

        // At a line's end, trains standing each way round: two doors
        // nearer than an opening's width share one wider opening, and
        // every door of either way is inside one.
        let shared = Map3DScreenDoors.pieces(length: 80, formations: [four], stands: [.forward, .backward]).filter(\.door)
        XCTAssertLessThan(shared.count, 16)
        for door in forward + backward {
            XCTAssertTrue(shared.contains { $0.from <= door - 0.65 && door + 0.65 <= $0.to }, "door at \(door)")
        }

        // The stop board where the head stops: at the platform's end.
        XCTAssertEqual(Props.stopMarks(length: 80, formations: [four], kind: .metro, stands: .forward),
                       [Props.StopMark(along: 80, heading: 1, cars: 4)])
        XCTAssertEqual(Props.stopMarks(length: 80, formations: [four], kind: .metro, stands: .backward),
                       [Props.StopMark(along: 0, heading: -1, cars: 4)])
        // A railway platform: one board each way, the longest train's,
        // as every length stops there.
        let short = Props.Formation(cars: 3, carLength: 20, doors: 2), long = Props.Formation(cars: 4, carLength: 20, doors: 2)
        XCTAssertEqual(Props.stopMarks(length: 100, formations: [short, long], kind: .railway, stands: [.forward, .backward]),
                       [Props.StopMark(along: 0, heading: -1, cars: 4), Props.StopMark(along: 100, heading: 1, cars: 4)])
    }

    // MARK: In a game

    /// How far along `line` (metres from its first point) `point` lies.
    static func along(_ point: Point, _ line: [Point]) -> Double {
        var best = (Double.infinity, 0.0), walked = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, q = dx * dx + dy * dy
            let t = q > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / q, 0), 1) : 0
            let px = a.x + t * dx - point.x, py = a.y + t * dy - point.y
            let d = (px * px + py * py).squareRoot()
            if d < best.0 { best = (d, walked + t * q.squareRoot()) }
            walked += q.squareRoot()
        }
        return best.1 / metre
    }

    struct Standing: CustomStringConvertible {
        let station: String
        let forward: Bool
        let platform: Double
        let train: ClosedRange<Double>
        /// The farthest any of its doors' leaves reaches past the nearest
        /// opening, metres.
        let worstDoor: Double
        var description: String {
            String(format: "%@ %@ platform %.1f m, train %.1f–%.1f m, doors reach %.2f m past their openings",
                   station, forward ? "forward" : "backward", platform, train.lowerBound, train.upperBound, worstDoor)
        }
    }

    /// Plays `opened` from `from` (clock seconds) for `minutes` and, for
    /// every train standing at a berth of a platform with screen doors (its
    /// run at rest), how far its doors (each car's evenly along it, as the
    /// cars are drawn) are from the openings the scene lays there.
    static func standing(_ opened: GameWorld, from: Int64, minutes: Int) throws -> [Standing] {
        var world = opened
        let plan = Map3DScreenDoors.Plan(world: world)
        if world.clock.now.seconds < from { try world.advance(ticks: Int((from - world.clock.now.seconds) / GameTime.secondsPerMinute)) }
        var motion = TrainMotion(world: world, time: Double(world.clock.now.seconds))
        var found: [String: Standing] = [:]
        for _ in 0..<minutes {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(world.clock.now.seconds))
            let snapshot = world.railwaySnapshot()
            let heights = Map3DTrains.Heights(world: world)
            for run in motion.runs {
                guard let train = world.trains.first(where: { $0.id == run.train }),
                      case .onEdge(let traversal, let offset)? = train.position,
                      let edge = world.network.edge(traversal.edge) else { continue }
                let forward = traversal.direction == .forward
                let at = forward ? offset : edge.length - offset
                guard let platform = snapshot.platforms.first(where: {
                    $0.platform.edge == traversal.edge && (forward ? $0.platform.end == at : $0.platform.start == at)
                }), world.station(id: platform.platform.station)?.isDepot == false,
                    plan.doors(edge: platform.platform.edge, station: platform.platform.station,
                               underground: platform.structure == .tunnel) != nil else { continue }
                let line = platform.points.map(Point.init)
                let length = Double(platform.platform.length) / metre
                let openings = Map3DScreenDoors.pieces(
                    length: Float(length), formations: plan.trains(edge: platform.platform.edge, station: platform.platform.station),
                    stands: plan.stands(edge: platform.platform.edge)
                ).filter(\.door).map { Double($0.from)...Double($0.to) }
                let cars = Map3DTrains.cars(of: run, progress: 1, heights: heights, models: .standard).cars.compactMap { car -> ClosedRange<Double>? in
                    guard let front = car.first, let back = car.last else { return nil }
                    let (a, b) = (along(front, line), along(back, line))
                    return min(a, b)...max(a, b)
                }
                let doors = Int(train.type?.doorsPerCar ?? 0)
                guard doors > 0, let first = cars.map(\.lowerBound).min(), let last = cars.map(\.upperBound).max() else { continue }
                var worst = 0.0
                for car in cars {
                    for door in 0..<doors {
                        let centre = car.lowerBound + (car.upperBound - car.lowerBound) * (Double(door) + 0.5) / Double(doors)
                        // How far its leaf reaches past the nearest opening.
                        let leaf = (centre - doorLeaf / 2)...(centre + doorLeaf / 2)
                        worst = max(worst, openings.map { max(0, $0.lowerBound - leaf.lowerBound, leaf.upperBound - $0.upperBound) }.min() ?? .infinity)
                    }
                }
                let name = world.station(id: platform.platform.station)?.name ?? "?"
                let standing = Standing(station: name, forward: forward, platform: length, train: first...last, worstDoor: worst)
                let key = "\(platform.platform.edge)-\(forward)"
                if let known = found[key], known.worstDoor >= worst { continue }
                found[key] = standing
            }
        }
        return found.values.sorted { ($0.station, $0.forward ? 1 : 0) < ($1.station, $1.forward ? 1 : 0) }
    }

    /// The Wenhu Line bought: its 50 m trains on its 80 m platforms stand
    /// at the end they come in towards, each door at an opening.
    /// origin/main: every door 14.7–15.1 m from its opening (13.4–13.8 m
    /// past it).
    func testTheWenhuLinesTrainsStandWithTheirDoorsAtTheOpenings() throws {
        let world = try DepotReturnReportTests.bought("trtc:BR", rules: .realistic)
        let plan = Map3DScreenDoors.Plan(world: world)
        let platforms = world.railwaySnapshot().platforms.filter { world.station(id: $0.platform.station)?.isDepot == false }
        XCTAssertFalse(platforms.isEmpty)
        for platform in platforms {
            XCTAssertFalse(plan.stands(edge: platform.platform.edge).isEmpty, "every platform of the line is called at: \(platform.platform.edge)")
        }
        let found = try Self.standing(world, from: 6 * 3600, minutes: 40)
        for standing in found { print("SCREEN-DOOR-ALIGNMENT: \(standing)") }
        XCTAssertGreaterThanOrEqual(found.count, 10, "trains stood at the line's platforms")
        XCTAssertTrue(found.contains { $0.forward } && found.contains { !$0.forward }, "both ways")
        XCTAssertTrue(found.contains { $0.platform - ($0.train.upperBound - $0.train.lowerBound) > 20 }, "a platform longer than its train")
        for standing in found {
            XCTAssertLessThanOrEqual(standing.worstDoor, 0.1, "\(standing)")
        }
    }

    /// `SCREEN_DOOR_ALIGNMENT=<line>` (a `hkmtr:` line, or any Taiwan line
    /// on sale) reports the same for that line through a morning.
    func testReportALine() throws {
        guard let which = ProcessInfo.processInfo.environment["SCREEN_DOOR_ALIGNMENT"] else {
            throw XCTSkip("SCREEN_DOOR_ALIGNMENT=<line> reports where its trains stand against its screen doors")
        }
        let world = which.hasPrefix("hkmtr:") ? try DepotReturnReportTests.hongKongBought([String(which.dropFirst(6))])
            : try DepotReturnReportTests.bought(which, rules: .realistic)
        let clock = ContinuousClock(), took = clock.measure { _ = Map3DScreenDoors.Plan(world: world) }
        print("SCREEN-DOOR-ALIGNMENT: \(which) the plan took \(took)")
        let found = try Self.standing(world, from: 6 * 3600, minutes: 90)
        for standing in found { print("SCREEN-DOOR-ALIGNMENT: \(which) \(standing)") }
        XCTAssertFalse(found.isEmpty)
    }
}
