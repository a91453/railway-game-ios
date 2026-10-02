import Foundation
import GameCore
import XCTest

/// Stage S5 (ARCHITECTURE decision 31): generated lines of track network at
/// several levels (straight edges, gentle S-curves, ramps, viaducts,
/// tunnels and a siding), stations with platforms of different lengths on
/// them, and trains of one to four cars running timetables (once or
/// repeating, turning round at stops), lines with patterns sending them
/// out, and paths set by hand, on GameCore and on ``ReferenceWorld`` side by
/// side. After every operation the outcome and the whole state must agree:
/// every train's position, body, path and end, service and timetable, the
/// stations it is stopped at (and with its whole length), its way to every
/// station with the distance, every service's journey with its legs,
/// trains and headway at each level, and each line's last dispatches; the
/// world must keep every invariant and survive a save exactly.
final class NetworkServicePropertyTests: XCTestCase {
    enum Operation {
        case place(TrainID, TrainPosition)
        case stand(TrainID, [TrackTraversal], Int64?)
        case unplace(TrainID)
        case reverse(TrainID)
        case rate(TrainID, Int64)
        case timetable(TrainID, [ScheduledStop], Int64?)
        case start(TrainID)
        case stop(TrainID)
        case createLine([StationID])
        /// A timetable, then its service started.
        case run(TrainID, [ScheduledStop], Int64?)
        /// A line created, open all day with a train at each level, and
        /// given a train.
        case line([StationID], TrainID?)
        /// A train placed, then stopped where it stands.
        case settle(TrainID, TrainPosition)
        /// A pattern added, with a train at each level.
        case patternRun(LineID, [Int])
        case lineRate(LineID, Int64)
        case allDay(LineID)
        case trains(LineID, TrainsInService, Int?)
        case targets(LineID, TargetHeadways, Int?)
        case assign(TrainID, LineID, Int?)
        case unassign(TrainID)
        case pattern(LineID, [Int])
        case addPlatform(StationID, TrackEdgeID, Int64, Int64)
        case removePlatform(StationID, TrackEdgeID, Int64)
        case advance(Int)

        /// Whether the operation is several commands, which keep what the
        /// first did when a later one is refused.
        var isCompound: Bool {
            switch self {
            case .run, .line, .settle, .patternRun: true
            default: false
            }
        }
    }

    /// A generated layout: nodes, and edges between them by index.
    private struct Layout {
        var nodes: [WorldCoordinate]
        var edges: [(Int, Int, TrackCurve, TrackStructure)]
        /// The edges on one level, which can take platforms, by index.
        var level: [Int]
    }

    private static let y: Int64 = 8_192

    private static func structure(at z: Int64) -> TrackStructure {
        z > 0 ? .elevated : z < 0 ? .tunnel : .surface
    }

    /// A line east along y = 8192 from x = 2048: four to six edges, each
    /// straight, a gentle S-curve (leaving and arriving within 1 in 16 of
    /// east) or a ramp of 16384 to a level 512 up or down (1 in 32), on the
    /// surface, a viaduct or in a tunnel; and now and then a siding from a
    /// node, 400 north over 8192, with a straight edge on after the node.
    private static func layout(using random: inout SplitMix64) -> Layout {
        var nodes = [WorldCoordinate(x: 2_048, y: y, z: 0)]
        var edges: [(Int, Int, TrackCurve, TrackStructure)] = []
        var level: [Int] = []
        let siding = random.chance(1, in: 2) ? 1 + random.below(2) : nil
        for index in 0..<(4 + random.below(3)) {
            let here = nodes[nodes.count - 1]
            var z = here.z
            var curve = TrackCurve.straight
            let run: Int64
            if index != siding, random.chance(1, in: 5) {
                // A ramp to a neighbouring level.
                z = random.element(of: [here.z - 512, here.z + 512].filter { (-512...512).contains($0) })
                run = 16_384
            } else {
                run = Int64(256 * (16 + random.below(32)))
                if index != siding, random.chance(1, in: 3) {
                    let bend = random.element(of: [64, 128] as [Int64])
                    curve = .cubic(PlanPoint(x: here.x + 2_048, y: y + bend), PlanPoint(x: here.x + run - 2_048, y: y - bend))
                }
            }
            nodes.append(WorldCoordinate(x: here.x + run, y: y, z: z))
            let carried = here.z == z ? Self.structure(at: z) : (z > 0 || here.z > 0 ? .elevated : .tunnel)
            edges.append((nodes.count - 2, nodes.count - 1, curve, carried))
            if here.z == z { level.append(edges.count - 1) }
            if index == siding {
                let branch = nodes.count - 2
                let start = nodes[branch]
                nodes.append(WorldCoordinate(x: start.x + 8_192, y: y - 400, z: start.z))
                edges.append((branch, nodes.count - 1, .straight, Self.structure(at: start.z)))
                level.append(edges.count - 1)
            }
        }
        return Layout(nodes: nodes, edges: edges, level: level)
    }

    private static let cars = [1, 2, 3, 4]

    /// A place for a train of `length` beside one of `station`'s platforms:
    /// its berth one way or the other, or a point along it.
    private static func berth(for length: Int64, of station: StationID, in world: GameWorld, using random: inout SplitMix64) -> TrainPosition? {
        let platforms = world.trackPlatforms(of: station)
        guard !platforms.isEmpty else { return nil }
        let platform = random.element(of: platforms)
        guard let edge = world.trackEdge(platform.edge) else { return nil }
        switch random.below(3) {
        case 0: return .onEdge(TrackTraversal(edge: edge.id, direction: .forward), offset: platform.end)
        case 1: return .onEdge(TrackTraversal(edge: edge.id, direction: .backward), offset: edge.length - platform.start)
        default:
            let chainage = random.int64(in: platform.start...platform.end)
            return .onEdge(TrackTraversal(edge: edge.id, direction: .forward), offset: max(chainage, min(length, edge.length)))
        }
    }

    /// A timetable back and forth between the station `train` is stopped
    /// at (or any) and another: two or three calls, or three repeating
    /// (there and back, ending where it began). It turns round at the far
    /// call, at the first when it has no way on as it faces, and at the
    /// last of a repeating one when that keeps it facing the way it began;
    /// now and then a turn is left out or added, so a service may find no
    /// way.
    private static func timetable(for train: Train, in world: GameWorld, using random: inout SplitMix64) -> ([ScheduledStop], Int64?) {
        let stations = world.stations.map(\.id)
        let here = world.stationsStoppedAt(by: train.id).first ?? random.element(of: stations)
        let there = random.element(of: stations.filter { $0 != here })
        let repeating = random.chance(1, in: 3)
        let calls = repeating || random.chance(1, in: 2) ? [here, there, here] : [here, there]
        let turnFirst = train.position.map { world.path(from: $0, toStation: there, length: train.length) == nil } ?? false
        var turns = [turnFirst, true] + (calls.count == 3 ? [repeating ? !turnFirst : random.chance(1, in: 2)] : [])
        if random.chance(1, in: 10) {
            let index = random.below(turns.count)
            turns[index].toggle()
        }
        var time = max(0, world.clock.now.minute) + Int64(random.below(4))
        var stops: [ScheduledStop] = []
        for (index, station) in calls.enumerated() {
            if index > 0 { time += Int64(5 + random.below(35)) }
            let arrival = time
            time += Int64(random.below(4))
            stops.append(ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: time), reverses: turns[index]))
        }
        let span = time - stops[0].arrival.minutes
        let period: Int64? = repeating ? span + Int64(random.below(20)) + (random.chance(1, in: 12) ? -3 : 0) : nil
        return (stops, period)
    }

    static func operation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let stations = world.stations.map(\.id)
        func anyTrain() -> TrainID {
            random.chance(1, in: 20) ? TrainID(rawValue: 9) : random.element(of: trains).id
        }
        func anyLine() -> LineID {
            world.lines.isEmpty || random.chance(1, in: 20) ? LineID(rawValue: 9) : random.element(of: world.lines).id
        }
        func anyPattern(of line: LineID) -> Int? {
            guard let patterns = world.line(id: line)?.patterns, !patterns.isEmpty, random.chance(1, in: 2) else { return nil }
            return random.below(patterns.count)
        }
        func level() -> TrainsInService {
            TrainsInService(peak: random.below(3), offPeak: random.below(3), low: random.below(3))
        }
        // Trains free to be given a timetable or a line.
        let free = trains.filter { $0.execution == nil && world.assignedLine(of: $0.id) == nil }
        switch random.below(100) {
        case 0..<30:
            return .advance(1 + random.below(12))
        case 30..<44:
            // A timetable started at once, mostly for a free train stopped at
            // a station; a free train elsewhere is first sent to one.
            if let unplaced = trains.first(where: { $0.position == nil }),
               let position = Self.berth(for: unplaced.length, of: random.element(of: stations), in: world, using: &random) {
                return .settle(unplaced.id, position)
            }
            // Odd trains mostly run timetables, even ones lines.
            let runners = free.filter { $0.id.rawValue % 2 == 1 }
            let ready = (runners.isEmpty ? free : runners).filter { !world.stationsStoppedAt(by: $0.id).isEmpty }
            if free.isEmpty, random.chance(1, in: 3), let busy = trains.first(where: { $0.execution != nil && world.assignedLine(of: $0.id) == nil }) {
                return .stop(busy.id)
            }
            if ready.isEmpty, let train = (runners.isEmpty ? free : runners).first, let position = train.position, random.chance(3, in: 4),
               let path = world.path(from: position, toStation: random.element(of: stations), length: train.length) {
                return .stand(train.id, path.traversals, path.end)
            }
            let train = ready.isEmpty || random.chance(1, in: 10) ? random.element(of: trains) : random.element(of: ready)
            let (stops, period) = timetable(for: train, in: world, using: &random)
            return .run(train.id, stops, period)
        case 44..<47:
            let train = random.element(of: trains)
            let (stops, period) = timetable(for: train, in: world, using: &random)
            return .timetable(train.id, stops, period)
        case 47..<50:
            return .start(anyTrain())
        case 50..<52:
            return random.chance(1, in: 2) ? .stop(anyTrain()) : .advance(1 + random.below(6))
        case 52..<60:
            // By hand to a station, the way GameCore finds: mostly a line's
            // idle train to its service's first call.
            let waiting = trains.compactMap { train -> (Train, StationID)? in
                guard train.execution == nil, let id = world.assignedLine(of: train.id), let line = world.line(id: id) else { return nil }
                let first = line.stops[world.assignedPattern(of: train.id).map { line.patterns[$0].calls[0] } ?? 0]
                return world.stationsStoppedAt(by: train.id).contains(first) ? nil : (train, first)
            }
            let (train, station) = !waiting.isEmpty && random.chance(3, in: 4)
                ? random.element(of: waiting) : (random.element(of: trains), random.element(of: stations))
            guard let position = train.position, let path = world.path(from: position, toStation: station, length: train.length) else {
                return .advance(1)
            }
            return .stand(train.id, path.traversals, path.end)
        case 60..<63:
            // A walk by hand, stopping somewhere (sometimes somewhere it cannot).
            let train = random.element(of: trains)
            guard case .onEdge(let traversal, let offset)? = train.position else { return .stand(train.id, [], 0) }
            var walk: [TrackTraversal] = []
            var last = traversal
            for _ in 0..<random.below(3) {
                let options = world.transitions(after: last)
                guard !options.isEmpty else { break }
                last = random.element(of: options)
                walk.append(last)
            }
            let length = world.trackEdge(last.edge)?.length ?? 1
            let end: Int64? = random.chance(1, in: 4) ? nil : random.int64(in: (walk.isEmpty ? offset - 10 : 0)...length)
            return .stand(train.id, walk, end)
        case 63..<66:
            return .reverse(anyTrain())
        case 66..<68:
            return .rate(anyTrain(), random.element(of: [0, 512, 1_024, 2_048, 3_072] as [Int64]))
        case 68..<72:
            guard world.lines.count < 2 else { return .lineRate(anyLine(), random.element(of: [512, 1_024, 2_048, 3_072] as [Int64])) }
            // From where a free train (an even one) stands, now and then
            // anywhere.
            let waiting = free.filter { $0.id.rawValue % 2 == 0 && !world.stationsStoppedAt(by: $0.id).isEmpty }
            let train = waiting.isEmpty || random.chance(1, in: 5) ? nil : random.element(of: waiting)
            var stops = [train.flatMap { world.stationsStoppedAt(by: $0.id).first } ?? random.element(of: stations)]
            for _ in 1..<(2 + random.below(2)) { stops.append(random.element(of: stations.filter { $0 != stops[stops.count - 1] })) }
            return .line(stops, train?.id)
        case 72..<75:
            let line = anyLine()
            return .trains(line, level(), anyPattern(of: line))
        case 75..<77:
            let line = anyLine()
            return .targets(line, TargetHeadways(peak: random.chance(1, in: 2) ? Int64(2 + random.below(60)) : nil, low: random.chance(1, in: 2) ? Int64(2 + random.below(90)) : nil), anyPattern(of: line))
        case 77..<84:
            // Mostly a free train (an even one first) stopped at a service's
            // first call, to that service.
            for train in random.shuffled(free).sorted(by: { ($0.id.rawValue % 2) < ($1.id.rawValue % 2) }) {
                let stopped = world.stationsStoppedAt(by: train.id)
                for line in random.shuffled(world.lines) {
                    let services = [nil] + line.patterns.indices.map(Optional.some)
                    for service in services {
                        let first = line.stops[service.map { line.patterns[$0].calls[0] } ?? 0]
                        if stopped.contains(first), random.chance(3, in: 4) { return .assign(train.id, line.id, service) }
                    }
                }
            }
            let line = anyLine()
            return .assign(anyTrain(), line, anyPattern(of: line))
        case 84..<86:
            return .unassign(anyTrain())
        case 86..<89:
            let line = anyLine()
            let stops = world.line(id: line)?.stops.count ?? 3
            let calls = random.chance(1, in: 2) ? [0, stops - 1] : [random.below(max(1, stops - 1)), stops - 1]
            return random.chance(3, in: 4) ? .patternRun(line, calls) : .pattern(line, calls)
        case 89..<94:
            let platforms = world.network.platforms
            guard !platforms.isEmpty else { return .advance(1) }
            let platform = random.element(of: platforms)
            return .removePlatform(platform.station, platform.edge, platform.start)
        case 94..<97:
            let edge = random.element(of: world.network.edges)
            let start = random.int64(in: 0...max(0, edge.length - 512))
            return .addPlatform(random.element(of: stations), edge.id, start, min(edge.length, start + Int64(1_024 * (1 + random.below(4)))))
        default:
            return .allDay(anyLine())
        }
    }

    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .stand(let id, let path, let end): try world.setTrainContinuation(id, along: path, stoppingAt: end)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .rate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .timetable(let id, let stops, let period): try world.setTrainTimetable(id, to: stops, repeatingEvery: periodSeconds(period))
            case .start(let id): try world.startTrainService(id)
            case .stop(let id): try world.stopTrainService(id)
            case .createLine(let stops): _ = try world.createLine(named: "L", stops: stops)
            case .run(let id, let stops, let period):
                try world.setTrainTimetable(id, to: stops, repeatingEvery: periodSeconds(period))
                try world.startTrainService(id)
            case .line(let stops, let train):
                let id = try world.createLine(named: "L", stops: stops).id
                try world.setLineServiceWindow(id, to: .allDay)
                try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
                if let train { try world.assignTrain(train, to: id) }
            case .settle(let id, let position):
                try world.placeTrain(id, at: position)
                guard case .onEdge(let traversal, let offset) = position, let length = world.trackEdge(traversal.edge)?.length else { break }
                try world.setTrainContinuation(id, along: [], stoppingAt: offset < length ? offset : nil)
            case .patternRun(let id, let calls):
                let pattern = try world.addLinePattern(id, calling: calls)
                try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: pattern)
            case .lineRate(let id, let rate): try world.setLineRate(id, to: rate)
            case .allDay(let id): try world.setLineServiceWindow(id, to: .allDay)
            case .trains(let id, let trains, let pattern): try world.setLineTrainsInService(id, to: trains, pattern: pattern)
            case .targets(let id, let targets, let pattern): try world.setLineTargetHeadways(id, to: targets, pattern: pattern)
            case .assign(let id, let line, let pattern): try world.assignTrain(id, to: line, pattern: pattern)
            case .unassign(let id): try world.unassignTrain(id)
            case .pattern(let id, let calls): _ = try world.addLinePattern(id, calling: calls)
            case .addPlatform(let station, let edge, let start, let end): try world.addTrackPlatform(station, on: edge, from: start, to: end)
            case .removePlatform(let station, let edge, let start): try world.removeTrackPlatform(station, on: edge, from: start)
            case .advance(let ticks): try world.advance(ticks: ticks)
            }
            return nil
        } catch {
            return error
        }
    }

    private static func apply(_ operation: Operation, to model: inout ReferenceWorld) -> GameError? {
        switch operation {
        case .place(let id, let position): model.placeTrain(id, at: position)
        case .stand(let id, let path, let end): model.setContinuation(id, along: path, stoppingAt: end)
        case .unplace(let id): model.unplaceTrain(id)
        case .reverse(let id): model.reverseTrain(id)
        case .rate(let id, let rate): model.setRate(id, rate)
        case .timetable(let id, let stops, let period): model.setTimetable(id, stops, period: periodSeconds(period))
        case .start(let id): model.startService(id)
        case .stop(let id): model.stopService(id)
        case .createLine(let stops): model.createLine(named: "L", stops: stops)
        case .run(let id, let stops, let period): model.setTimetable(id, stops, period: periodSeconds(period)) ?? model.startService(id)
        case .line(let stops, let train):
            model.createLine(named: "L", stops: stops) ?? model.setLineWindow(LineID(rawValue: model.nextLineID - 1), .allDay)
                ?? model.setLineTrains(LineID(rawValue: model.nextLineID - 1), TrainsInService(peak: 1, offPeak: 1, low: 1))
                ?? train.flatMap { model.assign($0, to: LineID(rawValue: model.nextLineID - 1)) }
        case .settle(let id, let position):
            model.placeTrain(id, at: position) ?? Self.standStill(id, at: position, in: &model)
        case .patternRun(let id, let calls):
            model.addPattern(id, calls) ?? model.setLineTrains(
                id, TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: (model.lines.first { $0.id == id.rawValue }?.patterns.count ?? 1) - 1
            )
        case .lineRate(let id, let rate): model.setLineRate(id, rate)
        case .allDay(let id): model.setLineWindow(id, .allDay)
        case .trains(let id, let trains, let pattern): model.setLineTrains(id, trains, pattern: pattern)
        case .targets(let id, let targets, let pattern): model.setLineTargets(id, targets, pattern: pattern)
        case .assign(let id, let line, let pattern): model.assign(id, to: line, pattern: pattern)
        case .unassign(let id): model.unassign(id)
        case .pattern(let id, let calls): model.addPattern(id, calls)
        case .addPlatform(let station, let edge, let start, let end): model.addTrackPlatform(station, on: edge, from: start, to: end)
        case .removePlatform(let station, let edge, let start): model.removeTrackPlatform(station, on: edge, from: start)
        case .advance(let ticks): model.advance(ticks: ticks)
        }
    }

    /// The model's train `id` at `position` given a path that ends there.
    private static func standStill(_ id: TrainID, at position: TrainPosition, in model: inout ReferenceWorld) -> GameError? {
        guard case .onEdge(let traversal, let offset) = position, case .edge(let number) = traversal.edge, let edge = model.networkEdges[number] else {
            return nil
        }
        return model.setContinuation(id, along: [], stoppingAt: offset < edge.length ? offset : nil)
    }

    /// Every difference between the world and the model.
    private static func differences(_ world: GameWorld, _ model: ReferenceWorld, tally: inout [String: Int]) -> [String] {
        var problems: [String] = []
        if world.clock.now.seconds != model.clockSeconds || world.clock.pendingTenths != model.pendingTenths {
            problems.append("second \(world.clock.now.seconds) vs \(model.clockSeconds)")
        }
        if world.network.platforms != model.allTrackPlatforms { problems.append("platforms \(world.network.platforms) vs \(model.allTrackPlatforms)") }
        if world.trains.map(\.id.rawValue) != model.trains.map(\.id) { problems.append("train IDs") }
        for (train, expected) in zip(world.trains, model.trains) {
            let id = train.id.rawValue
            if train.position != expected.position { problems.append("train \(id) at \(String(describing: train.position)) vs \(String(describing: expected.position))") }
            if train.trailEdges.map(\.number) != expected.trailEdges { problems.append("train \(id) body \(train.trailEdges) vs \(expected.trailEdges)") }
            let movement = train.movement
            if movement.rate != expected.rate || movement.edges.map(\.number) != expected.edges || movement.cursor != expected.cursor || movement.end != expected.end {
                problems.append("train \(id) movement \(movement) vs rate \(expected.rate) edges \(expected.edges) cursor \(expected.cursor) end \(String(describing: expected.end))")
            }
            if train.execution != expected.service?.execution {
                problems.append("train \(id) service \(String(describing: train.execution)) vs \(String(describing: expected.service?.execution))")
            }
            if train.times != expected.service?.times {
                problems.append("train \(id) times \(String(describing: train.times)) vs \(String(describing: expected.service?.times))")
            }
            if train.timetable != expected.timetable || train.timetablePeriod != expected.period { problems.append("train \(id) timetable") }
            let stopped = world.stationsStoppedAt(by: train.id)
            let whole = world.stationsBesideWholeTrain(train.id)
            if stopped != model.stationsStoppedAt(by: train.id) { problems.append("train \(id) stopped at \(stopped) vs \(model.stationsStoppedAt(by: train.id))") }
            if whole != model.stationsBesideWholeTrain(train.id) { problems.append("train \(id) whole at \(whole) vs \(model.stationsBesideWholeTrain(train.id))") }
            if !whole.isEmpty { tally["whole-train stops", default: 0] += 1 }
            if !stopped.isEmpty, whole.isEmpty, train.length > 0 { tally["head on a platform, tail off it", default: 0] += 1 }
            guard let position = train.position else { continue }
            for station in world.stations {
                let path = world.path(from: position, toStation: station.id, length: train.length)
                let reference = model.pathToStation(from: position, station: station.id, length: train.length)
                if path != reference {
                    problems.append("train \(id) path to \(station.id.rawValue): \(String(describing: path)) vs \(String(describing: reference))")
                }
                if let path, path.traversals.count >= 2 { tally["paths over several edges", default: 0] += 1 }
            }
        }
        for line in world.lines {
            guard let expected = model.lines.first(where: { $0.id == line.id.rawValue }) else {
                problems.append("line \(line.id.rawValue) missing")
                continue
            }
            if line.lastDispatch?.minutes != expected.lastDispatch || line.patterns.map(\.lastDispatch?.minutes) != expected.patterns.map(\.lastDispatch) {
                problems.append("line \(line.id.rawValue) last dispatches")
            }
            if line.trains.map(\.rawValue) != expected.roster { problems.append("line \(line.id.rawValue) trains") }
            for pattern in [nil] + line.patterns.indices.map(Optional.some) {
                let journey = world.lineJourney(line.id, pattern: pattern)
                let reference = model.lineJourney(line.id, pattern: pattern)
                if journey != reference {
                    problems.append("line \(line.id.rawValue) pattern \(String(describing: pattern)) journey \(String(describing: journey)) vs \(String(describing: reference))")
                }
                if journey != nil { tally["journeys driven", default: 0] += 1 }
                for level in ServiceLevel.allCases {
                    if world.lineTrainsInService(line.id, at: level, pattern: pattern) != model.lineTrainsInService(line.id, at: level, pattern: pattern)
                        || world.lineHeadway(line.id, at: level, pattern: pattern) != model.lineHeadway(line.id, at: level, pattern: pattern) {
                        problems.append("line \(line.id.rawValue) pattern \(String(describing: pattern)) at \(level)")
                    }
                }
            }
        }
        return problems
    }

    /// A generated layout built on GameCore and on the reference side by
    /// side: the network, three stations with one or two platforms each,
    /// and three or four trains of one to four cars stopped beside them
    /// where they fit, each given a rate.
    private static func begin(_ testCase: inout PropertyCase) throws -> (world: GameWorld, model: ReferenceWorld) {
        let layout = Self.layout(using: &testCase.random)
        testCase.note("\(layout.nodes.count) nodes, \(layout.edges.count) edges, level edges \(layout.level)")
        let costs = ConstructionCosts(track: 100, station: 1_000, train: 500)
        let minute = Int64(testCase.random.below(1_440))
        var world = try GameWorld(width: 128, height: 16, economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(now: GameTime(minutes: minute), speed: .normal))
        var model = ReferenceWorld(width: 128, height: 16, balance: 1_000_000_000, costs: costs, minutes: minute, speed: .normal)
        for node in layout.nodes {
            _ = try world.buildTrackNode(at: node)
            XCTAssertNil(model.buildNetworkNode(at: node))
        }
        for edge in layout.edges {
            let from = TrackNodeID.node(edge.0 + 1)
            let to = TrackNodeID.node(edge.1 + 1)
            _ = try world.buildTrackEdge(from: from, to: to, curve: edge.2, structure: edge.3)
            XCTAssertNil(model.buildNetworkEdge(from: from, to: to, curve: edge.2, profile: .uniform, structure: edge.3))
        }
        for (index, name) in ["A", "B", "C"].enumerated() {
            _ = try world.buildStation(named: name, at: GridPosition(x: index + 1, y: 1))
            _ = model.buildStation(named: name, at: GridPosition(x: index + 1, y: 1))
            for _ in 0..<(1 + testCase.random.below(2)) {
                let edge = world.network.edges[testCase.random.element(of: layout.level)]
                let start = testCase.random.int64(in: 0...max(0, edge.length - 1_024))
                let end = min(edge.length, start + Int64(1_024 * (1 + testCase.random.below(4))))
                let operation = Operation.addPlatform(StationID(rawValue: index + 1), edge.id, start, end)
                XCTAssertEqual(Self.apply(operation, to: &world), Self.apply(operation, to: &model))
            }
        }
        for id in 1...(3 + testCase.random.below(2)) {
            let train = TrainID(rawValue: id)
            _ = try world.purchaseTrain(named: "T")
            _ = model.purchaseTrain(named: "T")
            let cars = testCase.random.element(of: Self.cars)
            try world.setTrainCars(train, to: cars)
            _ = model.setCars(train, cars)
            // Placed beside a platform where its body fits behind it (a
            // few tries), stopped there, and given a rate.
            for _ in 0..<6 where world.train(id: train)?.position == nil {
                let station = StationID(rawValue: 1 + testCase.random.below(3))
                guard let position = Self.berth(for: Int64(cars - 1) * 1_024, of: station, in: world, using: &testCase.random) else { continue }
                let operation = Operation.settle(train, position)
                XCTAssertEqual(Self.apply(operation, to: &world), Self.apply(operation, to: &model))
            }
            let operation = Operation.rate(train, testCase.random.element(of: [1_024, 2_048, 3_072] as [Int64]))
            XCTAssertEqual(Self.apply(operation, to: &world), Self.apply(operation, to: &model))
        }
        return (world, model)
    }

    /// A generated world (see ``begin(_:)``) after `operations` generated
    /// operations on GameCore alone: services, lines and paths under way.
    static func generateWorld(_ testCase: inout PropertyCase, operations: Int) throws -> GameWorld {
        var world = try Self.begin(&testCase).world
        for _ in 0..<operations {
            _ = Self.apply(Self.operation(in: world, using: &testCase.random), to: &world)
        }
        return world
    }

    func testNetworkServicesMatchTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        var operations = 0
        let ran = try runCampaign("service.network", cases: 40) { testCase in
            var (world, model) = try Self.begin(&testCase)
            for step in 0..<80 {
                let operation = Self.operation(in: world, using: &testCase.random)
                testCase.note("\(step): \(operation)")
                let before = world
                let outcome = Self.apply(operation, to: &world)
                let expected = Self.apply(operation, to: &model)
                operations += 1
                guard outcome == expected else {
                    return testCase.fail("\(operation): \(String(describing: outcome)) vs reference \(String(describing: expected))")
                }
                if outcome != nil, !operation.isCompound, world != before { return testCase.fail("refused \(operation) but changed the world") }
                let name = "\(operation)".components(separatedBy: "(")[0]
                tally["\(outcome.map { "\($0)".components(separatedBy: "(")[0] } ?? "ok") \(name)", default: 0] += 1
                if case .advance = operation {
                    for (old, new) in zip(before.trains, world.trains) {
                        switch (old.execution, new.execution) {
                        case (.waitingAtStop(let stop, _)?, let now) where now != old.execution:
                            tally["departures", default: 0] += 1
                            if old.timetable[stop].reverses { tally["turned round at a stop", default: 0] += 1 }
                        case (.travellingToStop?, .waitingAtStop?): tally["arrivals", default: 0] += 1
                        default: break
                        }
                        if old.execution != nil, new.execution == nil { tally["services completed", default: 0] += 1 }
                        if let cycle = new.execution?.cycle, cycle > 0 { tally["in a later cycle", default: 0] += 1 }
                        if new.execution != nil, new.cars >= 3, old.position != new.position { tally["long trains moving in service", default: 0] += 1 }
                        if old.position != new.position, let position = new.position, let z = world.location(of: position)?.position.z, z != 0 {
                            tally["moved off the ground", default: 0] += 1
                        }
                    }
                    for (old, new) in zip(before.lines, world.lines) {
                        if old.lastDispatch != new.lastDispatch { tally["dispatched", default: 0] += 1 }
                        for (oldPattern, newPattern) in zip(old.patterns, new.patterns) where oldPattern.lastDispatch != newPattern.lastDispatch {
                            tally["patterns dispatched", default: 0] += 1
                        }
                    }
                }
                let problems = Self.differences(world, model, tally: &tally) + WorldInvariants.violations(in: world)
                guard problems.isEmpty else { return testCase.fail(problems.joined(separator: "\n")) }
                if let problem = WorldInvariants.roundTripProblem(of: world) { return testCase.fail(problem) }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        let summary = tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")
        print("[digest] service.network \(digest.hex) (\(summary))")
        print("[volume] service.network \(ran) cases, \(operations) operations")
        assertVolume(ran == 40 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["departures", default: 0] > 300, "services leave stops")
        assertVolume(tally["arrivals", default: 0] > 200, "services arrive")
        assertVolume(tally["turned round at a stop", default: 0] > 80, "services turn round")
        assertVolume(tally["services completed", default: 0] > 50, "services end")
        assertVolume(tally["in a later cycle", default: 0] > 30, "timetables repeat")
        assertVolume(tally["dispatched", default: 0] > 30, "lines send trains out")
        assertVolume(tally["patterns dispatched", default: 0] > 5, "patterns send trains out")
        assertVolume(tally["long trains moving in service", default: 0] > 100, "long trains run services")
        assertVolume(tally["moved off the ground", default: 0] > 50, "trains run on viaducts and in tunnels")
        assertVolume(tally["whole-train stops", default: 0] > 500, "trains stand beside platforms")
        assertVolume(tally["paths over several edges", default: 0] > 500, "paths run over several edges")
        assertVolume(tally["trainServiceActive removePlatform", default: 0] > 5, "platforms a service needs stay")
        assertVolume(tally["ok removePlatform", default: 0] > 20, "other platforms go")
    }
}
