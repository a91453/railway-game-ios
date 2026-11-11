import GameCore

/// Decision 686: the track a hand-driven run (``ManualDrive``) goes along,
/// read from the world once when the run is taken over: from behind the
/// train's tail, under its body, and on the way it is to go to its next
/// stop and a little past it. The 3D map lays the followed train on it
/// where the player has driven it; the world's train is not touched.
public struct ManualDriveTrack: Sendable {
    /// How much track past the stopping point is read, in metres: more
    /// than a run may overrun (``ManualDrive/overrunMetres``) and the track
    /// the first car's front half is laid on.
    static let pastStopMetres: Int64 = 120

    public let train: TrainID
    /// The track's points with their heights, tail end first.
    let coordinates: [WorldCoordinate]
    /// How far along the track each point is, in world units, on the
    /// plan (as ``TrainMotion/Trail`` measures).
    let distances: [Double]
    let trail: TrainMotion.Trail
    /// How far along the track the head was at the take-over, in world
    /// units.
    let origin: Double
    /// Metres from there to the stopping point.
    public let stopMetres: Double

    private static let units = Double(WorldCoordinate.unitsPerMetre)

    /// The track of `train` in `world`, which has `remaining` world units
    /// of its run left to its stopping point; `nil` for a train not on the
    /// track.
    public init?(train: Train, in world: GameWorld, remaining: Int64) {
        let back = TrainTrackReach.back(of: train, in: world)
        let toStop = TrainTrackReach.front(of: train, in: world, ahead: max(remaining, 1))
        let past = TrainTrackReach.front(of: train, in: world, ahead: max(remaining, 1) + Self.pastStopMetres * WorldCoordinate.unitsPerMetre)
        guard past.count > 1 else { return nil }
        var coordinates: [WorldCoordinate] = []
        var distances: [Double] = []
        for point in back.reversed() + past.dropFirst() {
            if let last = coordinates.last {
                let dx = Double(point.x - last.x), dy = Double(point.y - last.y)
                let step = (dx * dx + dy * dy).squareRoot()
                guard step > 0 else { continue }
                distances.append(distances[distances.count - 1] + step)
            } else {
                distances.append(0)
            }
            coordinates.append(point)
        }
        self.train = train.id
        self.coordinates = coordinates
        self.distances = distances
        trail = TrainMotion.Trail(coordinates.map { TrainMotion.Point(x: Double($0.x), y: Double($0.y)) })
        origin = TrainMotion.Trail(back.map { TrainMotion.Point(x: Double($0.x), y: Double($0.y)) }).length
        stopMetres = TrainMotion.Trail(toStop.map { TrainMotion.Point(x: Double($0.x), y: Double($0.y)) }).length / Self.units
    }

    /// How far along the track the head is `metres` into the run, in world
    /// units, held on the track.
    func along(metres: Double) -> Double {
        min(max(origin + metres * Self.units, 0), trail.length)
    }

    /// `run` (the world's train as it glides) laid `metres` into the hand
    /// driven run instead: standing there, its body back along the track.
    func run(replacing run: TrainMotion.Run, metres: Double) -> TrainMotion.Run {
        let head = along(metres: metres)
        let tail = max(0, head - run.length - Double(TrainTrackReach.behind))
        let behind = TrainMotion.Trail(trail.points(from: tail, to: head).reversed())
        var heading = run.heading
        if let direction = trail.direction(at: head) { heading = direction }
        return TrainMotion.Run(
            train: run.train, look: run.look, isHighSpeed: run.isHighSpeed, livery: run.livery, trail: behind, lag: 0,
            length: run.length, carPitch: run.carPitch, heading: heading,
            aheadTrail: TrainMotion.Trail(trail.points(from: head, to: head + Double(TrainTrackReach.ahead))),
            bodyEnd: behind.length
        )
    }

    /// The track's points, with their heights, under and round a train
    /// `length` world units long whose head is `metres` into the run: its
    /// two ends and its head, and every point of the track between (a
    /// straight has points only at its ends, so these are worked out).
    func body(metres: Double, length: Double) -> [WorldCoordinate] {
        let head = along(metres: metres)
        let from = max(0, head - length - Double(TrainTrackReach.behind)), to = min(trail.length, head + Double(TrainTrackReach.ahead))
        var body = [coordinate(at: from)]
        var index = segment(at: from) + 1
        while index < distances.count, distances[index] < to {
            if distances[index] > from { body.append(coordinates[index]) }
            index += 1
        }
        body.append(coordinate(at: head))
        body.append(coordinate(at: to))
        return body
    }

    /// The last point at or before `distance` along the track, short of
    /// the last one.
    private func segment(at distance: Double) -> Int {
        var low = 0, high = max(distances.count - 2, 0)
        while low < high {
            let middle = (low + high + 1) / 2
            if distances[middle] <= distance { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The track `distance` along it, with its height there.
    private func coordinate(at distance: Double) -> WorldCoordinate {
        guard coordinates.count > 1 else { return coordinates[0] }
        let index = segment(at: distance)
        let a = coordinates[index], b = coordinates[index + 1]
        let span = distances[index + 1] - distances[index]
        let share = span > 0 ? min(max((distance - distances[index]) / span, 0), 1) : 0
        func between(_ a: Int64, _ b: Int64) -> Int64 { a + Int64((Double(b - a) * share).rounded()) }
        return WorldCoordinate(x: between(a.x, b.x), y: between(a.y, b.y), z: between(a.z, b.z))
    }
}

extension TrainMotion {
    /// Decision 686: these trains with `track`'s train drawn `metres` into
    /// its hand-driven run; the same when it is not among them.
    public func driving(on track: ManualDriveTrack, metres: Double) -> TrainMotion {
        guard let index = runs.firstIndex(where: { $0.train == track.train }) else { return self }
        var runs = runs
        runs[index] = track.run(replacing: runs[index], metres: metres)
        return replacing(runs: runs)
    }
}

extension Map3DTrains.Heights {
    /// Decision 686: these heights with `track`'s train's taken from the
    /// track where it is drawn, `metres` into its hand-driven run.
    public func driving(on track: ManualDriveTrack, metres: Double, length: Double) -> Map3DTrains.Heights {
        replacing(body: track.body(metres: metres, length: length), of: track.train)
    }
}
