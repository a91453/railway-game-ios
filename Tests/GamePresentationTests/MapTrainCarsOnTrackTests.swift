import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 538 (continued): the 2D map lays a train's cars along the
/// track past its body's two ends (``TrainCars/mapCars(of:progress:)``), as
/// the 3D map does, so a car round a curve, through a switch or across a
/// ring's seam stays on the track rather than swinging straight off it.
final class MapTrainCarsOnTrackTests: XCTestCase {
    typealias Point = TrainMotion.Point

    /// The farthest a car's end may stand from the track's centre line on
    /// the map, in metres: only rounding.
    static let tolerance = 0.5

    /// Every edge of `world` as its sampled centre line, segment by
    /// segment, in buckets of `cell` world units for a quick nearest look.
    struct Track {
        let cell: Double
        var buckets: [Int64: [(Point, Point)]] = [:]

        init(_ world: GameWorld, cell: Double = 64 * Double(WorldCoordinate.unitsPerMetre)) {
            self.cell = cell
            for edge in world.network.edges {
                guard let geometry = world.trackGeometry(of: edge.id) else { continue }
                for (a, b) in zip(geometry.points, geometry.points.dropFirst()) {
                    let p = Point(a), q = Point(b)
                    for key in keys(from: p, to: q) { buckets[key, default: []].append((p, q)) }
                }
            }
        }

        private func key(_ x: Int64, _ y: Int64) -> Int64 { x &* 1_000_003 &+ y }

        private func keys(from p: Point, to q: Point) -> [Int64] {
            let x0 = Int64((min(p.x, q.x) / cell).rounded(.down)), x1 = Int64((max(p.x, q.x) / cell).rounded(.down))
            let y0 = Int64((min(p.y, q.y) / cell).rounded(.down)), y1 = Int64((max(p.y, q.y) / cell).rounded(.down))
            var keys: [Int64] = []
            for x in (x0 - 1)...(x1 + 1) { for y in (y0 - 1)...(y1 + 1) { keys.append(key(x, y)) } }
            return keys
        }

        /// How far `point` is from the nearest segment, in metres
        /// (infinity past a cell's reach).
        func distance(_ point: Point) -> Double {
            let k = key(Int64((point.x / cell).rounded(.down)), Int64((point.y / cell).rounded(.down)))
            var best = Double.infinity
            for (a, b) in buckets[k] ?? [] {
                let dx = b.x - a.x, dy = b.y - a.y, q = dx * dx + dy * dy
                let t = q > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / q, 0), 1) : 0
                let px = a.x + t * dx - point.x, py = a.y + t * dy - point.y
                best = min(best, (px * px + py * py).squareRoot())
            }
            return best / Double(WorldCoordinate.unitsPerMetre)
        }
    }

    /// The worst of every car end of every train in `motion` at each of
    /// `progresses`, in metres off `track`: laid by `cars`. A train whose
    /// track behind runs out before its drawn cars do (standing at a buffer
    /// stop: four cars drawn 20 m each, 80 m, on 64 m of track) is left
    /// out: past the track's end there is none to follow, and its tail goes
    /// on straight, as in 3D.
    static func worst(_ motion: TrainMotion, on track: Track, progresses: [Double] = [0, 0.5, 1],
                      cars: (TrainMotion.Run, Double) -> [[Point]] = TrainCars.mapCars(of:progress:)) -> (off: Double, ends: Int) {
        var off = 0.0, ends = 0
        for run in motion.runs {
            for progress in progresses {
                let along = run.lag * (1 - progress)
                let drawn = TrainCars.drawnCarLength * Double(TrainCars.count(length: run.length, carPitch: run.carPitch))
                guard along + drawn - TrainCars.drawnCarLength / 2 <= run.trail.length else { continue }
                for car in cars(run, progress) {
                    for point in [car.first, car.last].compactMap({ $0 }) {
                        off = max(off, track.distance(point))
                        ends += 1
                    }
                }
            }
        }
        return (off, ends)
    }

    /// The cars as the 2D map laid them before: straight on past the
    /// body's two ends.
    static func straight(_ run: TrainMotion.Run, _ progress: Double) -> [[Point]] {
        guard let head = run.head(at: progress) else { return [] }
        return TrainCars.cars(body: run.body(at: progress), heading: head.heading, count: TrainCars.count(length: run.length, carPitch: run.carPitch))
    }

    /// The general way (``TrainCars/cars(body:heading:count:gap:track:)``
    /// given the run's track), which ``TrainCars/mapCars(of:progress:)``
    /// reads more quickly off the trail.
    static func general(_ run: TrainMotion.Run, _ progress: Double) -> [[Point]] {
        guard let head = run.head(at: progress) else { return [] }
        return TrainCars.cars(body: run.body(at: progress), heading: head.heading, count: TrainCars.count(length: run.length, carPitch: run.carPitch),
                              track: run.track(at: progress))
    }

    /// The demo map through a morning, a game minute at a time: its ring
    /// line round its seam and every line through the switches at its
    /// stations, each car's two ends on the track (laid straight on, as
    /// before, a ring train's last car stood a metre off it); and the cars
    /// read off the trail are the ones laid along the track.
    func testTheDemoTrainsKeepEveryCarOnTheTrack() throws {
        var world = DemoWorld.make(in: .english)
        let track = Track(world)
        var motion = TrainMotion(world: world, time: 0)
        var worst = (off: 0.0, ends: 0), before = 0.0
        for minute in 1...240 {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(minute))
            let now = Self.worst(motion, on: track)
            worst = (max(worst.off, now.off), worst.ends + now.ends)
            before = max(before, Self.worst(motion, on: track, cars: Self.straight).off)
            for run in motion.runs {
                for progress in [0, 0.5, 1.0] {
                    let quick = TrainCars.mapCars(of: run, progress: progress), general = Self.general(run, progress)
                    XCTAssertEqual(quick.count, general.count)
                    for (a, b) in zip(quick, general) {
                        for (p, q) in [(a.first, b.first), (a.last, b.last)] {
                            XCTAssertLessThan(TrainMotion.Trail.distance(p!, q!), 0.01, "train \(run.train.rawValue) at \(progress): read off the trail as laid along the track")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(worst.ends, 1_000)
        XCTAssertLessThanOrEqual(worst.off, Self.tolerance)
        // Laid straight on, as before, the ring's cars came off it.
        XCTAssertGreaterThan(before, Self.tolerance, "the demo has a car the old way laid off the track")
    }

    /// What laying the cars costs a frame, each train at once, along the
    /// track and straight on (the 2D map draws every frame). Only with
    /// `MAP_CARS_TIMING` set (a number of rounds); prints, asserts nothing.
    func testTimingOfTheCarsAlongTheTrack() throws {
        guard let rounds = ProcessInfo.processInfo.environment["MAP_CARS_TIMING"].flatMap(Int.init) else {
            throw XCTSkip("set MAP_CARS_TIMING to a number of rounds")
        }
        var world = DemoWorld.make(in: .english)
        var motion = TrainMotion(world: world, time: 0)
        for minute in 1...90 {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(minute))
        }
        let runs = motion.runs.count
        for (name, lay) in [("straight", Self.straight), ("along the track, general", Self.general), ("along the track", TrainCars.mapCars(of:progress:))] {
            var points = 0
            let start = DispatchTime.now().uptimeNanoseconds
            for round in 0..<rounds {
                for run in motion.runs { points += lay(run, Double(round % 10) / 10).reduce(0) { $0 + $1.count } }
            }
            let nanoseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds * runs)
            print("map cars \(name): \(String(format: "%.2f", nanoseconds / 1_000)) µs a train a frame (\(runs) trains, \(points / rounds) points a frame)")
        }
    }
}
