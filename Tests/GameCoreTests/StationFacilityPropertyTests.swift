import Foundation
import GameCore
import XCTest

/// Station facilities and train length (Stage S2, decision 27) under
/// generated command sequences: stations grown along the track, trains
/// given cars and placed with their bodies behind them, sent to stations
/// (pulled along the platforms) and to tiles, turned round, moved, taken
/// off and given other cars, track removed under their bodies, and lines
/// dispatching trains of several cars; some commands invalid on purpose (tiles
/// not beside a station, cars out of range, cars for a placed
/// train, placements with no track behind).
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, whose body is a list of points with distances cut
///   by walking them, and which finds the tail by walking those points to
///   turn a train round; all state (stations' annexes, trains' cars and
///   bodies included) must match after every step, and so must platforms,
///   platform tracks, stops, whole-train stops and occupied track.
/// - **Invariants.** Every world reached keeps them, the body rules among
///   them (``WorldInvariants/bodyViolations(of:in:)``); the world each case
///   ends in loads back equal and saves to the same bytes.
///
/// `PROPERTY_REPLAY=station.facilities@<seed>@<case>` runs one case.
final class StationFacilityPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static let carChoices = [1, 1, 2, 2, 3, 3, 4, 5, 8, 16]

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        // Small networks: the reference drives lines from scratch.
        var setup = KernelDifferentialTests.makeSetup(shapes: [.line, .line, .loopWithTails, .loopWithTails, .ladder, .grid, .random], using: &c.random)
        setup.seconds = 60 * (c.random.int64(in: 0...3_000))
        setup.extraBalance = 10_000_000
        setup.speed = .normal
        // Some junctions become turnouts, so bodies lie through them.
        setup.specs = setup.specs.map { spec in
            guard case .track(let connections) = spec.kind, connections.directions.count >= 3, c.random.chance(1, in: 3) else { return spec }
            return TileSpec(position: spec.position, kind: .turnout(connections, stem: c.random.element(of: connections.directions)))
        }
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        // Stations grow along the track.
        for station in world.stations where c.random.chance(2, in: 3) {
            for _ in 0..<(1 + c.random.below(3)) {
                run(extendOperation(in: world, station: station.id, using: &c.random))
            }
        }
        // Trains of several cars, placed with room behind them.
        for index in 0..<(2 + c.random.below(3)) {
            run(.purchase("C\(index + 1)"))
            guard let id = world.trains.last?.id else { continue }
            run(.setCars(id, c.random.element(of: carChoices)))
            for _ in 0..<4 where world.train(id: id)?.position == nil {
                guard let position = bodyPosition(in: world, using: &c.random) else { break }
                run(.place(id, position))
            }
            run(.setRate(id, c.random.element(of: [512, 700, 1024, 1500, 2048])))
        }
        // A line or two whose trains have cars.
        for _ in 0..<(1 + c.random.below(2)) {
            operations += lineWithCars(in: &world, using: &c.random)
        }
        while operations.count < count {
            let trains = world.trains
            let train = trains.isEmpty ? nil : c.random.element(of: trains)
            switch c.random.below(24) {
            case 0, 1:
                let stations = world.stations.map(\.id)
                let station = stations.isEmpty || c.random.chance(1, in: 10)
                    ? StationID(rawValue: c.random.element(of: [0, stations.count + 1]))
                    : c.random.element(of: stations)
                run(extendOperation(in: world, station: station, using: &c.random))
            case 2, 3, 4:
                let stations = world.stations.map(\.id)
                guard let train, !stations.isEmpty else { run(.advance(3)); continue }
                run(.sendWholeTrainToStation(train.id, c.random.element(of: stations)))
            case 5:
                let stations = world.stations.map(\.id)
                guard let train, !stations.isEmpty else { run(.advance(3)); continue }
                run(.sendToStation(train.id, c.random.element(of: stations)))
            case 6, 7:
                guard let train else { run(.advance(3)); continue }
                run(.reverse(train.id))
            case 8:
                // Under a body, mostly.
                let bodies = trains.flatMap(\.trail)
                if !bodies.isEmpty, c.random.chance(3, in: 4) {
                    run(.removeTrack(c.random.element(of: bodies)))
                } else {
                    run(KernelDifferentialTests.nextGridOperation(in: world, using: &c.random))
                }
            case 9:
                guard let train else { run(.advance(3)); continue }
                let cars = c.random.chance(1, in: 8) ? c.random.element(of: [0, -1, 17, .max]) : c.random.element(of: carChoices)
                run(.setCars(c.random.chance(1, in: 12) ? TrainID(rawValue: trains.count + 1) : train.id, cars))
            case 10:
                // Off the track, other cars, and back on.
                guard let train else { run(.advance(3)); continue }
                run(.unplace(train.id))
                run(.setCars(train.id, c.random.element(of: carChoices)))
                if let position = bodyPosition(in: world, using: &c.random) { run(.place(train.id, position)) }
            case 11..<16:
                run(.advance(1 + c.random.below(10)))
            case 16, 17:
                run(Self.gridDispatchOperation(in: world, using: &c.random))
            default:
                run(KernelDifferentialTests.nextGridOperation(in: world, using: &c.random))
            }
        }
        return (setup, operations)
    }

    /// Growing `station`: mostly onto a tile beside one of its tiles
    /// (empty or not), sometimes anywhere on or off the map.
    static func extendOperation(in world: GameWorld, station: StationID, using random: inout SplitMix64) -> Operation {
        if let tiles = world.station(id: station)?.tiles, random.chance(4, in: 5) {
            return .extendStation(station, step(random.element(of: tiles), random.element(of: TrackDirection.allCases)))
        }
        return .extendStation(station, GridPosition(x: random.below(world.map.width + 2) - 1, y: random.below(world.map.height + 2) - 1))
    }

    /// A position with joined track behind it: at a node facing away from
    /// a joined neighbour, or on a link; `nil` without track.
    static func bodyPosition(in world: GameWorld, using random: inout SplitMix64) -> TrainPosition? {
        let tracks = world.tracks.map(\.position)
        guard !tracks.isEmpty else { return nil }
        let tile = random.element(of: tracks)
        let neighbors = world.connectedNeighbors(of: tile)
        guard let behind = neighbors.isEmpty ? nil : random.element(of: neighbors) else {
            return .atNode(tile, heading: random.element(of: TrackDirection.allCases))
        }
        if random.chance(1, in: 3) {
            return .onLink(from: behind, to: tile, offset: random.element(of: [1, 256, 512, 700, 1023]))
        }
        return .atNode(tile, heading: stepDirection(from: behind, to: tile)!)
    }

    // MARK: - Dispatch on the grid

    // The line dispatch campaign's generators as they were on the grid
    // (before Stage F3b moved that campaign to the track network), kept
    // for this campaign, whose subject is the grid: it goes with the grid
    // in Stage F3c.

    /// A working line: two or three stations with platforms, mostly ones a
    /// train can reach from the first, a count or a target at each level,
    /// usually open all day, and one to three trains bought, standing at
    /// the first stop facing any way, given a rate and assigned; applied to
    /// `world` as they are drawn, and they may still fail.
    static func gridScriptedLine(in world: inout GameWorld, using random: inout SplitMix64) -> [Operation] {
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        let served = world.stations.filter { !world.platforms(of: $0.id).isEmpty }.map(\.id)
        guard served.count >= 2, world.lines.count < 3 else {
            run(.advance(random.below(20)))
            return operations
        }
        let first = random.element(of: served)
        let platform = random.element(of: world.platforms(of: first))
        let reachable = served.filter { station in
            station != first && TrackDirection.allCases.contains { world.route(from: .atNode(platform, heading: $0), toStation: station) != nil }
        }
        var stops = [first]
        for _ in 0..<(1 + random.below(2)) {
            let pool = !reachable.isEmpty && random.chance(5, in: 6) ? reachable : served
            let next = random.element(of: pool)
            if next != stops.last { stops.append(next) }
        }
        if stops.count < 2 { stops.append(served.first { $0 != first }!) }
        run(.createLine("D\(world.lines.count + 1)", stops))
        guard let line = world.lines.last?.id else { return operations }
        // Decision 49: a third stop round, sometimes, to make a ring.
        if random.chance(1, in: 3), let third = served.first(where: { !stops.contains($0) }) {
            if stops.count == 2 { run(.setLineStops(line, stops + [third])) }
            run(.setLineRing(line, true))
        }
        if random.chance(4, in: 5) { run(.setLineWindow(line, .allDay)) }
        run(.setLineTrains(line, TrainsInService(peak: random.below(4), offPeak: 1 + random.below(3), low: random.below(3))))
        if random.chance(1, in: 3) { run(.setLineTargets(line, LineDispatchPropertyTests.targets(using: &random))) }
        // Stage W2c: mostly a crawl, so that trips last minutes as before
        // (a train keeps to the time its line plans, whatever its own
        // performance).
        if random.chance(3, in: 4) {
            run(.setLinePerformance(line, PerformanceSamples.crawl))
        } else if random.chance(1, in: 2) {
            run(.setLinePerformance(line, random.element(of: PerformanceSamples.valid)))
        }
        for _ in 0..<(1 + random.below(3)) {
            run(.purchase("L\(world.trains.count + 1)"))
            guard let id = world.trains.last?.id, world.train(id: id)?.position == nil else { break }
            run(.place(id, .atNode(platform, heading: random.element(of: TrackDirection.allCases))))
            run(.setRate(id, random.element(of: [700, 1024, 1024, 1500, 2048, 4096])))
            if random.chance(1, in: 4) { run(.setPerformance(id, random.element(of: PerformanceSamples.valid))) }
            run(.assign(id, line))
        }
        return operations
    }

    /// A dispatch operation, drawn with the world in view.
    static func gridDispatchOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let lines = world.lines
        let trains = world.trains
        let unknownLine = LineID(rawValue: random.element(of: [0, -1, (lines.last?.id.rawValue ?? 0) + 1]))
        let unknownTrain = TrainID(rawValue: random.element(of: [0, -1, trains.count + 1]))
        func anyLine() -> LineID {
            lines.isEmpty || random.chance(1, in: 12) ? unknownLine : random.element(of: lines).id
        }
        func anyTrain() -> TrainID {
            trains.isEmpty || random.chance(1, in: 12) ? unknownTrain : random.element(of: trains).id
        }
        let assigned = lines.flatMap(\.trains)
        switch random.below(42) {
        case 0..<3:
            // Mostly a free train onto a first stop, then assigned there.
            let free = trains.filter { !assigned.contains($0.id) }
            if let line = lines.isEmpty ? nil : random.element(of: lines), let train = free.isEmpty ? nil : random.element(of: free),
               train.position == nil, let platform = world.platforms(of: line.stops[0]).first, random.chance(1, in: 2) {
                return .place(train.id, .atNode(platform, heading: random.element(of: TrackDirection.allCases)))
            }
            return .assign(anyTrain(), anyLine())
        case 3, 4:
            return .unassign(random.chance(3, in: 4) && !assigned.isEmpty ? random.element(of: assigned) : anyTrain())
        case 5..<8:
            return .setLineTargets(anyLine(), random.chance(1, in: 4) ? .none : LineDispatchPropertyTests.targets(using: &random))
        case 8..<11:
            let counts = (0..<3).map { _ in random.chance(1, in: 20) ? -1 : random.below(5) }
            return .setLineTrains(anyLine(), TrainsInService(peak: counts[0], offPeak: counts[1], low: counts[2]))
        case 11, 12:
            let window: ServiceWindow = switch random.below(4) {
            case 0: .allDay
            case 1: .hours(open: random.below(1440), close: 1441 + random.below(359))
            default: .hours(open: random.below(1200), close: 1200 + random.below(240))
            }
            return .setLineWindow(anyLine(), window)
        case 13:
            var start = 0
            var bands: [ServiceDay.Band] = []
            while start < 1440, bands.count < 5 {
                bands.append(ServiceDay.Band(start: start, level: random.element(of: ServiceLevel.allCases)))
                start += 1 + random.below(400)
            }
            return .setServiceDay(ServiceDay(bands: bands))
        case 14:
            return random.chance(1, in: 2)
                ? .setLinePerformance(anyLine(), random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
                : .setPerformance(anyTrain(), random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
        case 15:
            guard let line = lines.isEmpty ? nil : random.element(of: lines) else { return .advance(5) }
            let stations = world.stations.map(\.id)
            var stops = line.stops
            if random.chance(1, in: 2), stops.count > 2 {
                stops.removeLast()
            } else if let extra = stations.first(where: { $0 != stops.last }) {
                stops.append(extra)
            }
            return .setLineStops(line.id, stops)
        case 16:
            return random.chance(1, in: 4) ? .removeLine(anyLine()) : .advance(random.below(30))
        case 17..<20:
            // A line's train by hand: its timetable or service (refused), or
            // held, released, turned or taken off.
            let id = !assigned.isEmpty && random.chance(4, in: 5) ? random.element(of: assigned) : anyTrain()
            switch random.below(8) {
            case 0: return .setTimetable(id, [])
            case 1: return .startService(id)
            case 2: return .stopService(id)
            case 3: return .setRate(id, 0)
            case 4: return .setRate(id, random.element(of: [700, 1024, 2048]))
            case 5: return .reverse(id)
            case 6: return .unplace(id)
            default:
                let platforms = lines.flatMap { world.platforms(of: $0.stops[0]) }
                guard let platform = platforms.isEmpty ? nil : random.element(of: platforms) else { return .advance(5) }
                return .place(id, .atNode(platform, heading: random.element(of: TrackDirection.allCases)))
            }
        case 20, 21:
            // A line's train sent back to its first stop by hand.
            guard let line = lines.isEmpty ? nil : random.element(of: lines), let id = line.trains.isEmpty ? nil : random.element(of: line.trains) else {
                return .advance(10)
            }
            return .sendToStation(id, line.stops[0])
        case 22:
            // A line's train waiting at its first stop, turned round by hand:
            // it may then have to turn again as it leaves.
            let waiting = lines.flatMap { line in
                line.trains.filter { world.train(id: $0)?.execution == nil && world.stationsStoppedAt(by: $0).contains(line.stops[0]) }
            }
            return waiting.isEmpty ? .advance(10) : .reverse(random.element(of: waiting))
        case 23:
            if world.clock.isPaused { return .setSpeed(random.element(of: [.normal, .double])) }
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 24..<34:
            return .advance(random.below(40))
        case 40, 41:
            return .setLineRing(anyLine(), random.chance(2, in: 3))
        default:
            return .advance(60 + random.below(600))
        }
    }

    /// A line as ``LineDispatchPropertyTests/scriptedLine(in:using:)``
    /// makes one, its trains then taken off, given cars and put back at the
    /// first stop's platform with room behind them if there is any, moving.
    static func lineWithCars(in world: inout GameWorld, using random: inout SplitMix64) -> [Operation] {
        var operations = Self.gridScriptedLine(in: &world, using: &random)
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        guard let line = world.lines.last else { return operations }
        let platforms = world.platforms(of: line.stops[0])
        for id in line.trains {
            run(.unplace(id))
            run(.setCars(id, random.element(of: [2, 2, 3, 4, 5])))
            let starts = platforms.flatMap { platform in
                world.connectedNeighbors(of: platform).map { TrainPosition.atNode(platform, heading: stepDirection(from: $0, to: platform)!) }
            }
            if !starts.isEmpty { run(.place(id, random.element(of: starts))) }
            run(.setRate(id, random.element(of: [700, 1024, 1500, 2048])))
        }
        return operations
    }

    func testStationFacilitiesMatchTheReference() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("station.facilities", cases: 12) { c in
            let (setup, operations) = try Self.generate(&c, operations: 60)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles")

            if let failure = KernelDifferentialTests.firstProblem(setup, operations, lineAnswers: false) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations, lineAnswers: false)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var (world, model) = try setup.build()
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                _ = KernelDifferentialTests.apply(operation, to: &model)
                let at = "step \(index) \(operation)"
                let long = { (id: TrainID) in (before.train(id: id)?.cars ?? 0) >= 2 }
                switch (operation, error) {
                case (.extendStation, nil):
                    counts["grown", default: 0] += 1
                case (.extendStation, .invalidStationTile?):
                    counts["not beside", default: 0] += 1
                case (.setCars, .invalidTrainLength?):
                    counts["bad cars", default: 0] += 1
                case (.setCars, .trainAlreadyPlaced?):
                    counts["cars while placed", default: 0] += 1
                case (.place(let id, _), nil) where long(id):
                    counts["long placed", default: 0] += 1
                case (.place(let id, _), .invalidTrainPosition?) where long(id):
                    counts["no room behind", default: 0] += 1
                case (.reverse(let id), nil) where long(id):
                    counts["turned with body", default: 0] += 1
                case (.removeTrack(let p), .trackInUse?) where before.trains.contains(where: { $0.trail.contains(p) }):
                    counts["under a body", default: 0] += 1
                case (.sendWholeTrainToStation(let id, let station), nil):
                    if let train = before.train(id: id), let position = train.position,
                       let whole = before.route(from: position, toStation: station, length: train.length),
                       let short = before.route(from: position, toStation: station), whole.count > short.count {
                        counts["pulled along", default: 0] += 1
                    }
                case (.advance, nil):
                    for train in world.trains where train.cars >= 2 && train.position != before.train(id: train.id)?.position {
                        counts["long moved", default: 0] += 1
                    }
                    for train in world.trains where train.cars >= 2 && train.execution != nil && before.train(id: train.id)?.execution == nil
                        && world.lines.contains(where: { $0.trains.contains(train.id) || $0.patterns.contains { $0.trains.contains(train.id) } }) {
                        counts["long dispatched", default: 0] += 1
                    }
                default:
                    break
                }
                let problems = TrackResourcePropertyTests.resourceDifferences(world, model) + WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems.prefix(5))")
                if !problems.isEmpty { return }
                for train in world.trains where train.cars >= 2 && !world.stationsBesideWholeTrain(train.id).isEmpty {
                    counts["whole train beside", default: 0] += 1
                }
                for train in world.trains where train.cars >= 2 && world.stationsStoppedAt(by: train.id) != world.stationsBesideWholeTrain(train.id) {
                    counts["partly beside", default: 0] += 1
                }
            }
            counts["annexes", default: 0] += world.stations.reduce(0) { $0 + $1.annexes.count }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with grown stations and long trains did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] station.facilities \(digest.hex) (\(summary))")
        assertVolume(ran == 12 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("grown", 10), ("not beside", 3), ("bad cars", 2), ("cars while placed", 3), ("long placed", 10), ("no room behind", 2),
            ("turned with body", 10), ("under a body", 3), ("pulled along", 3), ("long moved", 20), ("whole train beside", 10),
            ("partly beside", 3), ("annexes", 10), ("long dispatched", 6),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
