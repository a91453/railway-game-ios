@testable import GameCore
@testable import GamePresentation
import XCTest

/// The author's report on 104.1 (CURVE3D): at Zhuzhong, on the real-world
/// map in 3D, the Liujia Line bought with the Neiwan Line, a Liujia train
/// rounding the curved platform on the viaduct (decision 462) had its last
/// car swung off the curve, its far end hanging out over the ground
/// platform below. Every car's two ends (where its bogies stand) must be on
/// the track the map draws (decision 538). In this class, whose shard
/// already builds the Zhuzhong map (`swift-shards.sh`, campaigns-13).
extension LiujiaLineTrainsTests {
    /// The farthest a car's end may stand from the track's centre line, in
    /// metres: a car's ends are laid on the track, so only rounding.
    static let curveTolerance = 0.5

    /// The drawn track of `world` (its edges' sampled centre lines, with
    /// their heights) within `radius` world units of `centre`, segment by
    /// segment.
    static func track(of world: GameWorld, near centre: TrainMotion.Point, radius: Double) -> [(WorldCoordinate, WorldCoordinate)] {
        var segments: [(WorldCoordinate, WorldCoordinate)] = []
        for edge in world.network.edges {
            guard let geometry = world.trackGeometry(of: edge.id) else { continue }
            for (a, b) in zip(geometry.points, geometry.points.dropFirst())
            where TrainMotion.Trail.distance(TrainMotion.Point(a), centre) < radius || TrainMotion.Trail.distance(TrainMotion.Point(b), centre) < radius {
                segments.append((a, b))
            }
        }
        return segments
    }

    /// How far world point `point` is from the nearest of `track`'s
    /// segments, in metres, and how far `height` (world units) is from the
    /// height of the track it stands on, in metres.
    static func offTrack(_ point: TrainMotion.Point, height: Double, on track: [(WorldCoordinate, WorldCoordinate)]) -> (plan: Double, height: Double) {
        var best = (plan: Double.infinity, height: Double.infinity)
        for (a, b) in track {
            let ax = Double(a.x), ay = Double(a.y), dx = Double(b.x) - ax, dy = Double(b.y) - ay
            let q = dx * dx + dy * dy
            let t = q > 0 ? min(max(((point.x - ax) * dx + (point.y - ay) * dy) / q, 0), 1) : 0
            let px = ax + t * dx - point.x, py = ay + t * dy - point.y
            let plan = (px * px + py * py).squareRoot()
            best.plan = min(best.plan, plan)
            // Where tracks cross (the Liujia viaduct over the Neiwan
            // Line), the height of the one it stands on.
            if plan <= curveTolerance * Double(WorldCoordinate.unitsPerMetre) {
                best.height = min(best.height, abs(Double(a.z) + t * Double(b.z - a.z) - height))
            }
        }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        return (best.plan / metre, best.height / metre)
    }

    /// Every train of `world` within `radius` metres of `centre` (world
    /// units), at each of `progresses`: its cars' ends that stand more than
    /// ``curveTolerance`` off the track (or, at progress 1, off its height),
    /// described; `checked` counts the cars looked at.
    static func strays(in world: GameWorld, near centre: TrainMotion.Point, radius: Double, motion: TrainMotion,
                       models: Map3DModelPack, progresses: [Double] = [0, 0.5, 1], checked: inout Int) -> [String] {
        let heights = Map3DTrains.Heights(world: world)
        let reach = radius * Double(WorldCoordinate.unitsPerMetre)
        // A car whose head is within reach lies within a train's length
        // and a half of it.
        let track = track(of: world, near: centre, radius: reach + 400 * Double(WorldCoordinate.unitsPerMetre))
        var strays: [String] = []
        for run in motion.runs {
            for progress in progresses {
                guard let head = run.head(at: progress)?.point,
                      TrainMotion.Trail.distance(head, centre) < reach else { continue }
                let laid = Map3DTrains.cars(of: run, progress: progress, heights: heights, models: models)
                checked += laid.cars.count
                for (index, car) in laid.cars.enumerated() {
                    for (end, point) in [("front", car.first), ("back", car.last)] {
                        guard let point else { continue }
                        let off = offTrack(point, height: heights.height(of: run.train, x: point.x, y: point.y), on: track)
                        // Its height where the world's trains stand now
                        // (progress 1): gliding a game minute behind, as
                        // here, a car is past the heights the tick gives.
                        if off.plan > curveTolerance || (progress == 1 && off.height > curveTolerance) {
                            strays.append("train \(run.train.rawValue) (\(laid.type)) car \(index + 1)/\(laid.cars.count) \(end) "
                                + "\(String(format: "%.1f", off.plan)) m off the track, \(String(format: "%.1f", off.height)) m off its height, "
                                + "at progress \(progress)")
                        }
                    }
                }
            }
        }
        return strays
    }

    /// The Liujia and Neiwan lines bought at Zhuzhong; through the
    /// morning, every Liujia train near Zhuzhong has each car's two ends
    /// on the track, stopped at the curved viaduct platform or rounding it.
    func testTheLiujiaTrainsAtZhuzhongKeepEveryCarOnTheCurve() throws {
        let session = try LiujiaLineTrainsTests.zhuzhong()
        for network in ["NEIWAN", "LIUJIA"] {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network }, network)
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(network): \(session.message?.text ?? "")")
        }
        var world = session.world
        let at = try XCTUnwrap(world.stations.first { $0.name.contains("竹中") }, "Zhuzhong").location
        let centre = TrainMotion.Point(x: Double(at.x), y: Double(at.y))
        let models = Map3DModelPack.standard
        var motion = TrainMotion(world: world, time: 0)
        var strays: [String] = []
        var seen = 0
        // 06:00 to 09:00, a game minute at a time.
        while world.clock.now.seconds < 6 * 3600 { try world.advance(ticks: 1) }
        while world.clock.now.seconds < 9 * 3600, strays.count < 20 {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(world.clock.now.seconds))
            strays += Self.strays(in: world, near: centre, radius: 600, motion: motion, models: models, checked: &seen)
        }
        XCTAssertGreaterThan(seen, 200, "too few cars near Zhuzhong")
        XCTAssertEqual(strays, [], "cars off the curve:\n" + strays.prefix(20).joined(separator: "\n"))
    }
}
