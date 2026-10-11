import Foundation
import GameCore
import XCTest

/// Stage T (ARCHITECTURE decision 32): route reservation under traffic
/// control, on GameCore and on ``ReferenceWorld`` side by side.
///
/// Every case builds a network layout (a line of straight, curved and
/// sloping edges on the surface, a viaduct or in a tunnel, a siding off a
/// turnout, sometimes a diamond crossing and a flyover, stations with
/// platforms; Stage F3c-3b dropped the grid layout every other case built),
/// puts trains of one to four cars on it
/// and runs generated operations: traffic control on and off, placing,
/// paths by hand and to stations, turning round, taking off, timetables,
/// lines and patterns, time, and removing and adding track and platforms.
/// After every operation the outcome and the whole state must agree, and
/// for every train what it holds, what it has reserved, and who holds the
/// route it waits for; the world must keep every invariant (under traffic
/// control no two trains hold the same track) and survive a save exactly.
final class TrafficControlPropertyTests: XCTestCase {
    enum Operation {
        case trafficControl(Bool)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case rate(TrainID, Int64)
        case path(TrainID, [TrackTraversal], Int64?)
        /// A timetable, then its service started.
        case run(TrainID, [ScheduledStop], Int64?)
        case stop(TrainID)
        /// A line created, open all day with a train at each level, and
        /// given a train.
        case line([StationID], TrainID?)
        /// A pattern added, with a train at each level.
        case patternRun(LineID, [Int])
        case assign(TrainID, LineID, Int?)
        case unassign(TrainID)
        case removeEdge(TrackEdgeID)
        case addPlatform(StationID, TrackEdgeID, Int64, Int64)
        case removePlatform(StationID, TrackEdgeID, Int64)
        /// A new node 2048 off `node`, square to the track, and an edge to
        /// it: a new junction.
        case spur(TrackNodeID)
        case advance(Int)

        var isCompound: Bool {
            switch self {
            case .run, .line, .patternRun, .spur: true
            default: false
            }
        }
    }

    // MARK: - Layouts

    private static let costs = ConstructionCosts(track: 100, station: 1_000, train: 500)

    /// Builds the same thing on both, which must agree.
    private static func both(_ world: inout GameWorld, _ model: inout ReferenceWorld, _ operation: Operation) {
        XCTAssertEqual(apply(operation, to: &world), apply(operation, to: &model), "\(operation)")
    }

    /// A network: a line east along y = 8192 of four to six edges
    /// (straight, gentle S-curves, ramps 512 up or down onto a viaduct or
    /// into a tunnel), a siding off a turnout; now and then a diamond
    /// crossing at a surface node and a flyover 1024 up across the line;
    /// three stations with one or two platforms each on level edges.
    private static func beginNetwork(_ testCase: inout PropertyCase, world: inout GameWorld, model: inout ReferenceWorld) throws {
        let y: Int64 = 8_192
        var nodes = [WorldCoordinate(x: 2_048, y: y, z: 0)]
        var edges: [(Int, Int, TrackCurve, TrackStructure)] = []
        var level: [Int] = []
        let siding = testCase.random.chance(2, in: 3) ? 1 + testCase.random.below(2) : nil
        func structure(_ z: Int64) -> TrackStructure { z > 0 ? .elevated : z < 0 ? .tunnel : .surface }
        for index in 0..<(4 + testCase.random.below(3)) {
            let here = nodes[nodes.count - 1]
            var z = here.z
            var curve = TrackCurve.straight
            let run: Int64
            if index != siding, testCase.random.chance(1, in: 5) {
                z = testCase.random.element(of: [here.z - 512, here.z + 512].filter { (-512...512).contains($0) })
                run = 16_384
            } else {
                run = Int64(256 * (12 + testCase.random.below(28)))
                if index != siding, testCase.random.chance(1, in: 3) {
                    let bend = testCase.random.element(of: [64, 128] as [Int64])
                    curve = .cubic(PlanPoint(x: here.x + 2_048, y: y + bend), PlanPoint(x: here.x + run - 2_048, y: y - bend))
                }
            }
            nodes.append(WorldCoordinate(x: here.x + run, y: y, z: z))
            let carried = here.z == z ? structure(z) : (z > 0 || here.z > 0 ? .elevated : .tunnel)
            edges.append((nodes.count - 2, nodes.count - 1, curve, carried))
            if here.z == z { level.append(edges.count - 1) }
            if index == siding {
                let branch = nodes.count - 2
                let start = nodes[branch]
                nodes.append(WorldCoordinate(x: start.x + 8_192, y: y - 400, z: start.z))
                edges.append((branch, nodes.count - 1, .straight, structure(start.z)))
                level.append(edges.count - 1)
            }
        }
        for node in nodes {
            _ = try world.buildTrackNode(at: node)
            XCTAssertNil(model.buildNetworkNode(at: node))
        }
        for edge in edges {
            let from = TrackNodeID.node(edge.0 + 1)
            let to = TrackNodeID.node(edge.1 + 1)
            _ = try world.buildTrackEdge(from: from, to: to, curve: edge.2, structure: edge.3)
            XCTAssertNil(model.buildNetworkEdge(from: from, to: to, curve: edge.2, profile: .uniform, structure: edge.3))
        }
        testCase.note("\(nodes.count) nodes, \(edges.count) edges, siding \(String(describing: siding)), level \(level)")
        // A diamond at a surface node of the main line, far from the siding.
        let lineNodes = nodes.indices.filter { nodes[$0].y == y && $0 > 0 && $0 < nodes.count - 1 && nodes[$0].z == 0 }
        if testCase.random.chance(1, in: 2), let crossing = lineNodes.last {
            let c = nodes[crossing]
            let north = WorldCoordinate(x: c.x, y: y - 4_096, z: 0)
            let south = WorldCoordinate(x: c.x, y: y + 4_096, z: 0)
            let n = world.network.nodes.count + 1
            if (try? world.buildTrackNode(at: north)) != nil {
                XCTAssertNil(model.buildNetworkNode(at: north))
                _ = try world.buildTrackNode(at: south)
                XCTAssertNil(model.buildNetworkNode(at: south))
                for (a, b) in [(TrackNodeID.node(n), TrackNodeID.node(crossing + 1)), (.node(crossing + 1), .node(n + 1))] {
                    let built: GameError?
                    do { _ = try world.buildTrackEdge(from: a, to: b); built = nil } catch { built = error }
                    XCTAssertEqual(built, model.buildNetworkEdge(from: a, to: b, curve: .straight))
                }
                testCase.note("diamond at node \(crossing + 1)")
            }
        }
        // A flyover 1024 up across the line.
        if testCase.random.chance(1, in: 2) {
            let x = nodes[0].x + 1_024 + Int64(testCase.random.below(8)) * 512
            let a = WorldCoordinate(x: x, y: y - 3_072, z: 1_024)
            let b = WorldCoordinate(x: x, y: y + 3_072, z: 1_024)
            if (try? world.buildTrackNode(at: a)) != nil {
                XCTAssertNil(model.buildNetworkNode(at: a))
                _ = try world.buildTrackNode(at: b)
                XCTAssertNil(model.buildNetworkNode(at: b))
                let count = world.network.nodes.count
                let built: GameError?
                do { _ = try world.buildTrackEdge(from: .node(count - 1), to: .node(count), structure: .elevated); built = nil } catch { built = error }
                XCTAssertEqual(built, model.buildNetworkEdge(from: .node(count - 1), to: .node(count), curve: .straight, structure: .elevated))
                testCase.note("flyover at x \(x): \(String(describing: built))")
            }
        }
        for (index, name) in ["A", "B", "C"].enumerated() {
            _ = try world.buildStation(named: name, at: TestLine.centre(index + 1, 1))
            XCTAssertNil(model.buildStation(named: name, at: TestLine.centre(index + 1, 1)))
            for _ in 0..<(2 + testCase.random.below(2)) {
                let edge = world.network.edges[testCase.random.element(of: level)]
                let start = testCase.random.int64(in: 0...max(0, edge.length - 1_024))
                let end = min(edge.length, start + Int64(1_024 * (2 + testCase.random.below(3))))
                both(&world, &model, .addPlatform(StationID(rawValue: index + 1), edge.id, start, end))
            }
        }
    }

    /// A place for a train of `length` beside one of `station`'s platforms
    /// on the network: its berth one way or the other, or a point along it.
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

    private static func begin(_ testCase: inout PropertyCase) throws -> (world: GameWorld, model: ReferenceWorld) {
        let minute = Int64(testCase.random.below(1_440))
        let (width, height) = (128, 16)
        var world = try GameWorld(bounds: WorldBounds(width: Int64(width) * 1_024, height: Int64(height) * 1_024), economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(now: GameTime(minutes: minute), speed: .normal))
        var model = ReferenceWorld(width: Int64(width) * 1_024, height: Int64(height) * 1_024, balance: 1_000_000_000, costs: costs, minutes: minute, speed: .normal)
        try beginNetwork(&testCase, world: &world, model: &model)
        // Traffic control on from the start, mostly.
        if testCase.random.chance(3, in: 4) { both(&world, &model, .trafficControl(true)) }
        for id in 1...(3 + testCase.random.below(2)) {
            let train = TrainID(rawValue: id)
            _ = try world.purchaseTrain(named: "T")
            _ = model.purchaseTrain(named: "T")
            let cars = 1 + testCase.random.below(4)
            try world.setTrainCars(train, to: cars)
            _ = model.setCars(train, cars)
            // Beside a platform where its body fits (a few tries), stopped
            // there, and given a rate.
            for _ in 0..<6 where world.train(id: train)?.position == nil {
                let station = StationID(rawValue: 1 + testCase.random.below(world.stations.count))
                guard let position = berth(for: Int64(cars - 1) * 1_024, of: station, in: world, using: &testCase.random) else { continue }
                both(&world, &model, .place(train, position))
                if case .onEdge(let traversal, let offset) = position, world.train(id: train)?.position != nil,
                   let length = world.trackEdge(traversal.edge)?.length {
                    both(&world, &model, .path(train, [], offset < length ? offset : nil))
                }
            }
            both(&world, &model, .rate(train, testCase.random.element(of: [1_024, 2_048, 3_072] as [Int64])))
        }
        return (world, model)
    }

    // MARK: - Operations

    /// A timetable between the station `train` is stopped at (or any) and
    /// another, turning round at the far call and, if it has no way on as
    /// it faces, the first; now and then repeating back and forth.
    private static func timetable(for train: Train, in world: GameWorld, using random: inout SplitMix64) -> ([ScheduledStop], Int64?) {
        let stations = world.stations.map(\.id)
        let here = world.stationsStoppedAt(by: train.id).first ?? random.element(of: stations)
        let others = stations.filter { $0 != here }
        // A mutated save (Stage F3b) may load with one station: no
        // timetable then, which GameCore refuses.
        guard !others.isEmpty else { return ([], nil) }
        // Mostly a station the train can reach, as it faces or turned round.
        let reachable = others.filter { station in
            guard let position = train.position else { return false }
            return world.path(from: position, toStation: station, length: train.length) != nil
                || world.path(from: world.turnedPosition(of: train) ?? position, toStation: station, length: train.length) != nil
        }
        let there = random.element(of: reachable.isEmpty || random.chance(1, in: 10) ? others : reachable)
        let repeating = random.chance(1, in: 3)
        let calls = repeating || random.chance(1, in: 2) ? [here, there, here] : [here, there]
        let turnFirst = train.position.map { world.path(from: $0, toStation: there, length: train.length) == nil } ?? false
        let turns = [turnFirst, true] + (calls.count == 3 ? [repeating ? !turnFirst : random.chance(1, in: 2)] : [])
        // A mutated save may load with the clock near the end of time (the
        // save mutation campaign): keep every call's minute within seconds
        // that fit, so GameCore refuses the timetable rather than the
        // generator trapping. Ordinary worlds are far below the cap.
        let latest = Int64.max / GameTime.secondsPerMinute - 1_000
        var time = min(max(0, world.clock.now.minute), latest) + Int64(random.below(3))
        var stops: [ScheduledStop] = []
        for (index, station) in calls.enumerated() {
            if index > 0 { time += Int64(4 + random.below(25)) }
            let arrival = time
            time += Int64(random.below(3))
            stops.append(ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: time), reverses: turns[index]))
        }
        let period: Int64? = repeating ? time - stops[0].arrival.minutes + Int64(random.below(10)) : nil
        return (stops, period)
    }

    static func operation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let stations = world.stations.map(\.id)
        // A mutated save (SaveMutationTests) of point stations may load
        // without stations or trains (Stage F3b): nothing to drive then.
        guard !stations.isEmpty, !trains.isEmpty else { return .advance(1 + random.below(12)) }
        func anyTrain() -> TrainID {
            random.chance(1, in: 25) ? TrainID(rawValue: 9) : random.element(of: trains).id
        }
        let free = trains.filter { $0.execution == nil && world.assignedLine(of: $0.id) == nil }
        // Trains a player could drive by hand: placed, without a service.
        let manual = trains.filter { $0.position != nil && $0.execution == nil }
        func driven() -> Train {
            manual.isEmpty || random.chance(1, in: 20) ? random.element(of: trains) : random.element(of: manual)
        }
        switch random.below(100) {
        case 0..<22:
            return .advance(1 + random.below(10))
        case 22..<27:
            // Mostly on: on when off, now and then off again.
            guard world.isTrafficControlEnabled else { return .trafficControl(true) }
            return random.chance(1, in: 4) ? .trafficControl(false) : .advance(1 + random.below(4))
        case 27..<42:
            // To a station, the way GameCore finds; mostly a line's idle
            // train to its service's first call.
            let waiting = trains.compactMap { train -> (Train, StationID)? in
                guard train.execution == nil, let id = world.assignedLine(of: train.id), let line = world.line(id: id) else { return nil }
                let first = line.stops[world.assignedPattern(of: train.id).map { line.patterns[$0].calls[0] } ?? 0]
                return world.stationsStoppedAt(by: train.id).contains(first) ? nil : (train, first)
            }
            let (train, station) = !waiting.isEmpty && random.chance(1, in: 2)
                ? random.element(of: waiting) : (driven(), random.element(of: stations))
            guard let position = train.position, let path = world.path(from: position, toStation: station, length: train.length) else {
                return .advance(1)
            }
            return .path(train.id, path.traversals, path.end)
        case 42..<48:
            // A walk by hand.
            let train = driven()
            // An unplaced train is placed on an edge that does not exist
            // (refused); until Stage F3c-3b, at a grid node off the track,
            // refused the same way.
            guard case .onEdge(let traversal, let offset)? = train.position else {
                return .place(train.id, .onEdge(TrackTraversal(edge: .edge(999_999), direction: .forward), offset: 0))
            }
            var walk: [TrackTraversal] = []
            var last = traversal
            for _ in 0..<random.below(3) {
                let options = world.transitions(after: last)
                guard !options.isEmpty else { break }
                last = random.element(of: options)
                walk.append(last)
            }
            let length = world.trackEdge(last.edge)?.length ?? 1
            let end: Int64? = random.chance(1, in: 4) ? nil : random.int64(in: (walk.isEmpty ? offset : 1)...max(walk.isEmpty ? offset : 1, length - 1))
            return .path(train.id, walk, end)
        case 48..<58:
            // A timetable started at once, mostly for a free train stopped at
            // a station.
            let ready = free.filter { !world.stationsStoppedAt(by: $0.id).isEmpty }
            if free.isEmpty, random.chance(1, in: 2), let busy = trains.first(where: { $0.execution != nil && world.assignedLine(of: $0.id) == nil }) {
                return .stop(busy.id)
            }
            if ready.isEmpty, let train = free.first(where: { $0.position != nil }), random.chance(3, in: 4),
               let path = world.path(from: train.position!, toStation: random.element(of: stations), length: train.length) {
                // First to a station, to start from there later.
                return .path(train.id, path.traversals, path.end)
            }
            let train = ready.isEmpty || random.chance(1, in: 12) ? random.element(of: trains) : random.element(of: ready)
            let (stops, period) = timetable(for: train, in: world, using: &random)
            return .run(train.id, stops, period)
        case 58..<62:
            guard world.lines.count < 2 else {
                let line = random.element(of: world.lines)
                let stops = line.stops.count
                return .patternRun(line.id, random.chance(1, in: 2) ? [0, stops - 1] : [random.below(max(1, stops - 1)), stops - 1])
            }
            let waiting = free.filter { $0.id.rawValue % 2 == 0 && !world.stationsStoppedAt(by: $0.id).isEmpty }
            let train = waiting.isEmpty || random.chance(1, in: 5) ? nil : random.element(of: waiting)
            var stops = [train.flatMap { world.stationsStoppedAt(by: $0.id).first } ?? random.element(of: stations)]
            stops.append(random.element(of: stations.filter { $0 != stops[0] }))
            return .line(stops, train?.id)
        case 62..<67:
            for train in random.shuffled(free) {
                let stopped = world.stationsStoppedAt(by: train.id)
                for line in random.shuffled(world.lines) {
                    for service in [nil] + line.patterns.indices.map(Optional.some) {
                        let first = line.stops[service.map { line.patterns[$0].calls[0] } ?? 0]
                        if stopped.contains(first), random.chance(3, in: 4) { return .assign(train.id, line.id, service) }
                    }
                }
            }
            let assigned = trains.filter { world.assignedLine(of: $0.id) != nil }
            return !assigned.isEmpty && random.chance(1, in: 2) ? .unassign(random.element(of: assigned).id) : .advance(1)
        case 67..<72:
            return .reverse(random.chance(1, in: 25) ? TrainID(rawValue: 9) : driven().id)
        case 72..<80:
            // Clear the way, as a player would: take off or send away a
            // train that holds a route another waits for.
            // Services waiting for each other on single track are Stage V's to
            // resolve; here the player stops or takes the blocker off its
            // line first.
            let blockers = trains.compactMap { world.trainHoldingRoute(of: $0.id) }.compactMap { world.train(id: $0) }
            if !blockers.isEmpty, random.chance(3, in: 4) {
                let blocker = random.element(of: blockers)
                if world.assignedLine(of: blocker.id) != nil { return .unassign(blocker.id) }
                if blocker.execution != nil { return .stop(blocker.id) }
                if random.chance(1, in: 2), let position = blocker.position,
                   let path = world.path(from: position, toStation: random.element(of: stations), length: blocker.length) {
                    return .path(blocker.id, path.traversals, path.end)
                }
                return .unplace(blocker.id)
            }
            let unplaced = trains.filter { $0.position == nil }
            guard !unplaced.isEmpty, random.chance(4, in: 5) else { return .unplace(driven().id) }
            // A place the train fits (tried on a copy), now and then one
            // it does not.
            let train = random.element(of: unplaced)
            var fallback: TrainPosition?
            for _ in 0..<8 {
                guard let position = berth(for: train.length, of: random.element(of: stations), in: world, using: &random) else { continue }
                fallback = fallback ?? position
                var trial = world
                if (try? trial.placeTrain(train.id, at: position)) != nil { return .place(train.id, position) }
            }
            return fallback.map { .place(train.id, $0) } ?? .advance(1)
        case 80..<81:
            return .rate(anyTrain(), random.element(of: [0, 512, 1_024, 2_048] as [Int64]))
        case 81..<89:
            // Infrastructure, mostly where trains are going.
            let edges = world.network.edges
            switch random.below(4) {
            case 0:
                let reserved = trains.flatMap(\.reservation).compactMap { resource -> TrackEdgeID? in
                    if case .span(let span) = resource { span.edge } else { nil }
                }
                return .removeEdge(random.chance(2, in: 3) && !reserved.isEmpty ? random.element(of: reserved) : random.element(of: edges).id)
            case 1:
                let platforms = world.network.platforms
                guard !platforms.isEmpty else { return .advance(1) }
                let platform = random.element(of: platforms)
                return .removePlatform(platform.station, platform.edge, platform.start)
            case 2:
                let edge = random.element(of: edges)
                let start = random.int64(in: 0...max(0, edge.length - 512))
                return .addPlatform(random.element(of: stations), edge.id, start, min(edge.length, start + Int64(1_024 * (1 + random.below(4)))))
            default:
                return .spur(random.element(of: world.network.nodes).id)
            }
        default:
            return .advance(1 + random.below(4))
        }
    }

    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .trafficControl(let on): try world.setTrafficControl(on)
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .rate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .path(let id, let path, let end): try world.setTrainContinuation(id, along: path, stoppingAt: end)
            case .run(let id, let stops, let period):
                try world.setTrainTimetable(id, to: stops, repeatingEvery: periodSeconds(period))
                try world.startTrainService(id)
            case .stop(let id): try world.stopTrainService(id)
            case .line(let stops, let train):
                let id = try world.createLine(named: "L", stops: stops).id
                try world.setLineServiceWindow(id, to: .allDay)
                try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
                if let train { try world.assignTrain(train, to: id) }
            case .patternRun(let id, let calls):
                let pattern = try world.addLinePattern(id, calling: calls)
                try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: pattern)
            case .assign(let id, let line, let pattern): try world.assignTrain(id, to: line, pattern: pattern)
            case .unassign(let id): try world.unassignTrain(id)
            case .removeEdge(let id): try world.removeTrackEdge(id)
            case .addPlatform(let station, let edge, let start, let end): try world.addTrackPlatform(station, on: edge, from: start, to: end)
            case .removePlatform(let station, let edge, let start): try world.removeTrackPlatform(station, on: edge, from: start)
            case .spur(let node):
                guard let at = world.trackNode(node)?.position else { throw .unknownTrackNode(node) }
                let to = try world.buildTrackNode(at: WorldCoordinate(x: at.x, y: at.y + 2_048, z: at.z))
                try world.buildTrackEdge(from: node, to: to, structure: at.z > 0 ? .elevated : at.z < 0 ? .tunnel : .surface)
            case .advance(let ticks): try world.advance(ticks: ticks)
            }
            return nil
        } catch {
            return error
        }
    }

    static func apply(_ operation: Operation, to model: inout ReferenceWorld) -> GameError? {
        switch operation {
        case .trafficControl(let on): return model.setTrafficControl(on)
        case .place(let id, let position): return model.placeTrain(id, at: position)
        case .unplace(let id): return model.unplaceTrain(id)
        case .reverse(let id): return model.reverseTrain(id)
        case .rate(let id, let rate): return model.setRate(id, rate)
        case .path(let id, let path, let end): return model.setContinuation(id, along: path, stoppingAt: end)
        case .run(let id, let stops, let period): return model.setTimetable(id, stops, period: periodSeconds(period)) ?? model.startService(id)
        case .stop(let id): return model.stopService(id)
        case .line(let stops, let train):
            return model.createLine(named: "L", stops: stops) ?? model.setLineWindow(LineID(rawValue: model.nextLineID - 1), .allDay)
                ?? model.setLineTrains(LineID(rawValue: model.nextLineID - 1), TrainsInService(peak: 1, offPeak: 1, low: 1))
                ?? train.flatMap { model.assign($0, to: LineID(rawValue: model.nextLineID - 1)) }
        case .patternRun(let id, let calls):
            return model.addPattern(id, calls) ?? model.setLineTrains(
                id, TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: (model.lines.first { $0.id == id.rawValue }?.patterns.count ?? 1) - 1
            )
        case .assign(let id, let line, let pattern): return model.assign(id, to: line, pattern: pattern)
        case .unassign(let id): return model.unassign(id)
        case .removeEdge(let id): return model.removeNetworkEdge(id)
        case .addPlatform(let station, let edge, let start, let end): return model.addTrackPlatform(station, on: edge, from: start, to: end)
        case .removePlatform(let station, let edge, let start): return model.removeTrackPlatform(station, on: edge, from: start)
        case .spur(let node):
            guard case .node(let number) = node, let at = model.networkNodes[number] else { return .unknownTrackNode(node) }
            let position = WorldCoordinate(x: at.x, y: at.y + 2_048, z: at.z)
            if let error = model.buildNetworkNode(at: position) { return error }
            return model.buildNetworkEdge(
                from: node, to: .node(model.nextNetworkNode - 1), curve: .straight, structure: at.z > 0 ? .elevated : at.z < 0 ? .tunnel : .surface
            )
        case .advance(let ticks): return model.advance(ticks: ticks)
        }
    }

    // MARK: - Comparison

    /// Every difference between the world and the model.
    fileprivate static func differences(_ world: GameWorld, _ model: ReferenceWorld, tally: inout [String: Int]) -> [String] {
        var problems: [String] = []
        if world.clock.now.seconds != model.clockSeconds || world.clock.pendingTenths != model.pendingTenths {
            problems.append("second \(world.clock.now.seconds) vs \(model.clockSeconds)")
        }
        if world.isTrafficControlEnabled != model.trafficControl { problems.append("traffic control \(world.isTrafficControlEnabled) vs \(model.trafficControl)") }
        if world.network.platforms != model.allTrackPlatforms { problems.append("platforms") }
        if world.network.edges.map(\.id.number) != model.networkEdges.keys.sorted() { problems.append("edges") }
        if world.trains.map(\.id.rawValue) != model.trains.map(\.id) { problems.append("train IDs") }
        for (train, expected) in zip(world.trains, model.trains) {
            let id = train.id.rawValue
            if train.position != expected.position { problems.append("train \(id) at \(String(describing: train.position)) vs \(String(describing: expected.position))") }
            if train.trailEdges.map(\.number) != expected.trailEdges { problems.append("train \(id) body") }
            let movement = train.movement
            if movement.rate != expected.rate || movement.edges.map(\.number) != expected.edges || movement.cursor != expected.cursor || movement.end != expected.end {
                problems.append("train \(id) movement \(movement) vs \(expected.edges) \(expected.cursor) \(String(describing: expected.end))")
            }
            if train.execution != expected.service?.execution { problems.append("train \(id) service \(String(describing: train.execution)) vs \(String(describing: expected.service?.execution))") }
            if train.times != expected.service?.times { problems.append("train \(id) times \(String(describing: train.times)) vs \(String(describing: expected.service?.times))") }
            if train.performance != expected.performance { problems.append("train \(id) performance") }
            if train.timetable != expected.timetable || train.timetablePeriod != expected.period { problems.append("train \(id) timetable") }
            if train.reservation != expected.reservation { problems.append("train \(id) reservation \(train.reservation) vs \(expected.reservation)") }
            let held = world.heldResources(of: train.id)
            if held != model.heldResources(of: train.id) { problems.append("train \(id) holds \(held) vs \(model.heldResources(of: train.id))") }
            if world.occupiedResources(of: train.id) != model.occupiedResources(of: train.id) { problems.append("train \(id) occupancy") }
            let holder = world.trainHoldingRoute(of: train.id)
            if holder != model.trainHoldingRoute(of: train.id) {
                problems.append("train \(id) held up by \(String(describing: holder)) vs \(String(describing: model.trainHoldingRoute(of: train.id)))")
            }
            if let holder {
                tally[train.execution == nil ? "line dispatch waits" : "service waits", default: 0] += 1
                let blocker = world.train(id: holder)!
                tally[blocker.reservation.isEmpty ? (blocker.execution == nil ? "held up by an idle standing train" : "held up by a standing service") : "held up by a moving train", default: 0] += 1
            }
            if world.stationsStoppedAt(by: train.id) != model.stationsStoppedAt(by: train.id) { problems.append("train \(id) stops") }
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
        }
        return problems
    }

    // MARK: - Following (Stage U2)

    /// A long line to follow on (Stage U2): six straight edges of 32768
    /// (512 m) east along y = 8192, each with a station whose platform of
    /// 4096 lies somewhere along it, traffic control on, and three to five
    /// trains of one to three cars, each at the forward berth of a
    /// different station, mostly in the western half.
    fileprivate static func beginFollowing(_ testCase: inout PropertyCase) throws -> (world: GameWorld, model: ReferenceWorld) {
        let minute = Int64(testCase.random.below(1_440))
        var world = try GameWorld(bounds: WorldBounds(width: 204_800, height: 16_384), economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(now: GameTime(minutes: minute), speed: .normal))
        var model = ReferenceWorld(width: 204_800, height: 16_384, balance: 1_000_000_000, costs: costs, minutes: minute, speed: .normal)
        for index in 0...6 {
            let node = WorldCoordinate(x: 2_048 + Int64(index) * 32_768, y: 8_192, z: 0)
            _ = try world.buildTrackNode(at: node)
            XCTAssertNil(model.buildNetworkNode(at: node))
        }
        for index in 1...6 {
            _ = try world.buildTrackEdge(from: .node(index), to: .node(index + 1))
            XCTAssertNil(model.buildNetworkEdge(from: .node(index), to: .node(index + 1), curve: .straight))
        }
        var berths: [TrainPosition] = []
        for index in 1...6 {
            let point = PlanPoint(x: 2_048 + Int64(index - 1) * 32_768 + 16_384, y: 9_216)
            _ = try world.buildStation(named: "S\(index)", at: point)
            XCTAssertNil(model.buildStation(named: "S\(index)", at: point))
            let start = Int64(1_024 * (2 + testCase.random.below(24)))
            both(&world, &model, .addPlatform(StationID(rawValue: index), .edge(index), start, start + 4_096))
            berths.append(.onEdge(TrackTraversal(edge: .edge(index), direction: .forward), offset: start + 4_096))
        }
        both(&world, &model, .trafficControl(true))
        let count = 3 + testCase.random.below(3)
        let stations = Array(testCase.random.shuffled([0, 0, 1, 1, 2, 2, 3, 4, 5]).reduce(into: [Int]()) { found, index in
            if !found.contains(index) { found.append(index) }
        }.prefix(count))
        for (number, station) in stations.enumerated() {
            let train = TrainID(rawValue: number + 1)
            _ = try world.purchaseTrain(named: "T")
            _ = model.purchaseTrain(named: "T")
            let cars = 1 + testCase.random.below(3)
            try world.setTrainCars(train, to: cars)
            _ = model.setCars(train, cars)
            both(&world, &model, .place(train, berths[station]))
            if case .onEdge(_, let offset) = berths[station] { both(&world, &model, .path(train, [], offset)) }
            both(&world, &model, .rate(train, testCase.random.element(of: [1_024, 2_048] as [Int64])))
        }
        // Each train not at the last station runs east from its station at
        // once, calling everywhere, all in the same minute or the next, legs
        // of 3 to 12 minutes, so that the ones behind set off while the ones
        // ahead are still on their way and catch them up; mostly ending
        // short of where the one ahead ends, so that they may follow it.
        let now = max(0, world.clock.now.minute)
        let order = stations.enumerated().filter { $0.element < 5 }.sorted { $0.element > $1.element }
        var limit = 5
        for (number, station) in order {
            let last = max(station + 1, min(limit, station + 1 + testCase.random.below(3)))
            limit = last - 1
            var time = now + Int64(testCase.random.below(2))
            var stops = [ScheduledStop(station: StationID(rawValue: station + 1), arrival: GameTime(minutes: time), departure: GameTime(minutes: time))]
            for next in (station + 1)...last {
                time += Int64(3 + testCase.random.below(10))
                let arrival = time
                time += Int64(testCase.random.below(2))
                stops.append(ScheduledStop(station: StationID(rawValue: next + 1), arrival: GameTime(minutes: arrival), departure: GameTime(minutes: time)))
            }
            both(&world, &model, .run(TrainID(rawValue: number + 1), stops, nil))
        }
        testCase.note("trains at stations \(stations.map { $0 + 1 })")
        return (world, model)
    }

    /// A timetable from the station `train` stands at on to one to three
    /// stations further east (or, now and then, back west), legs of 2 to 20
    /// minutes so that trains catch each other up, the last call turning
    /// round now and then, repeating now and then.
    private static func followingTimetable(for train: Train, in world: GameWorld, using random: inout SplitMix64) -> ([ScheduledStop], Int64?) {
        let stations = world.stations.map(\.id)
        guard let here = world.stationsStoppedAt(by: train.id).first ?? stations.first,
              let index = stations.firstIndex(of: here)
        else { return ([], nil) }
        let east = random.chance(5, in: 6)
        let ahead = east ? Array(stations[(index + 1)...]) : Array(stations[..<index].reversed())
        guard !ahead.isEmpty else { return ([], nil) }
        let calls = [here] + ahead.prefix(1 + random.below(3))
        var time = max(0, world.clock.now.minute) + Int64(random.below(3))
        var stops: [ScheduledStop] = []
        for (number, station) in calls.enumerated() {
            if number > 0 { time += Int64(2 + random.below(19)) }
            let arrival = time
            time += Int64(random.below(2))
            let turns = (number == 0 && !east) || (number == calls.count - 1 && random.chance(1, in: 3))
            stops.append(ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: time), reverses: turns))
        }
        let period: Int64? = random.chance(1, in: 6) ? time - stops[0].arrival.minutes + Int64(random.below(10)) : nil
        return (stops, period)
    }

    static func followingOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let stations = world.stations.map(\.id)
        let idle = trains.filter { $0.execution == nil && $0.position != nil }
        switch random.below(100) {
        case 0..<45:
            return .advance(1 + random.below(3))
        case 45..<77:
            let ready = idle.filter { !world.stationsStoppedAt(by: $0.id).isEmpty }
            let train = ready.isEmpty || random.chance(1, in: 15) ? random.element(of: trains) : random.element(of: ready)
            let (stops, period) = followingTimetable(for: train, in: world, using: &random)
            return stops.isEmpty ? .advance(1) : .run(train.id, stops, period)
        case 77..<80:
            let running = trains.filter { $0.execution != nil }
            return running.isEmpty ? .advance(1) : .stop(random.element(of: running).id)
        case 80..<85:
            return .rate(random.element(of: trains).id, random.element(of: [0, 1_024, 2_048, 3_072] as [Int64]))
        case 85..<88:
            return .trafficControl(!world.isTrafficControlEnabled || random.chance(1, in: 3) ? true : false)
        case 88..<95:
            // An idle train sent on by hand to a station.
            guard let train = idle.isEmpty ? nil : random.element(of: idle),
                  let path = world.path(from: train.position!, toStation: random.element(of: stations), length: train.length)
            else { return .advance(1) }
            return .path(train.id, path.traversals, path.end)
        default:
            return .advance(1)
        }
    }

    /// A world of this campaign's layouts after `operations` generated
    /// operations; for the save mutation campaign.
    static func generateWorld(_ testCase: inout PropertyCase, operations: Int) throws -> GameWorld {
        var (world, _) = try Self.begin(&testCase)
        for _ in 0..<operations {
            _ = Self.apply(Self.operation(in: world, using: &testCase.random), to: &world)
        }
        return world
    }

    func testRouteReservationMatchesTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        var operations = 0
        let ran = try runCampaign("traffic.reservation", cases: 40) { testCase in
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
                if case .trackReserved? = outcome {
                    tally["network span conflicts", default: 0] += 1
                    switch operation {
                    case .removeEdge, .addPlatform, .removePlatform, .spur: tally["infrastructure refusals", default: 0] += 1
                    default: tally["refused acquisitions", default: 0] += 1
                    }
                }
                if case .trainsShareTrack? = outcome { tally["enable failures", default: 0] += 1 }
                for (old, new) in zip(before.trains, world.trains) where !new.reservation.isEmpty && new.reservation != old.reservation {
                    // Stage U: a reservation that only lost track was
                    // released behind its train, not taken.
                    if case .advance = operation, Set(new.reservation).isSubset(of: old.reservation) {
                        tally["released behind a moving train", default: 0] += 1
                        continue
                    }
                    tally["reservations taken", default: 0] += 1
                    if new.cars >= 2 { tally["long-train reservations", default: 0] += 1 }
                    if new.movement.end != nil { tally["mid-edge berth reservations", default: 0] += 1 }
                    if case .advance = operation { tally["taken by departures and dispatch", default: 0] += 1 }
                }
                if case .advance = operation {
                    for (old, new) in zip(before.trains, world.trains) where !old.reservation.isEmpty && new.reservation.isEmpty && new.position != nil {
                        tally["released at the end of a route", default: 0] += 1
                    }
                    for (old, new) in zip(before.lines, world.lines) where old.lastDispatch != new.lastDispatch {
                        tally["dispatched", default: 0] += 1
                    }
                    for (old, new) in zip(before.trains, world.trains) {
                        if case .waitingAtStop? = old.execution, new.execution != old.execution { tally["service departures", default: 0] += 1 }
                        if case .travellingToStop? = new.execution, case .waitingAtStop? = old.execution,
                           let ahead = before.trainHoldingRoute(of: old.id), world.train(id: ahead)?.reservation.isEmpty == false {
                            tally["left while the train it waited for still moved", default: 0] += 1
                        }
                        // Stage U2: a service on its way that holds its route
                        // only part of the way follows the trains ahead.
                        if case .travellingToStop? = new.execution, world.trainHoldingRoute(of: new.id) != nil {
                            tally["following a train ahead", default: 0] += 1
                            if case .waitingAtStop? = old.execution { tally["set off following", default: 0] += 1 }
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
        print("[digest] traffic.reservation \(digest.hex) (\(summary))")
        print("[volume] traffic.reservation \(ran) cases, \(operations) operations")
        // Reservations are counted between operations, so one taken and
        // released inside a single advance goes uncounted; and services that
        // wait for each other on single track stay waiting (decision 32,
        // point 15), which keeps these counts well below the departures.
        assertVolume(ran == 40 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["reservations taken", default: 0] > 600, "trains take routes")
        assertVolume(tally["refused acquisitions", default: 0] > 100, "held routes are refused")
        assertVolume(tally["taken by departures and dispatch", default: 0] > 120, "services and lines take routes")
        assertVolume(tally["service waits", default: 0] > 50, "services wait for their routes")
        assertVolume(tally["line dispatch waits", default: 0] > 10, "lines wait to send trains out")
        assertVolume(tally["network span conflicts", default: 0] > 50, "trains meet on the network")
        assertVolume(tally["long-train reservations", default: 0] > 300, "long trains reserve")
        assertVolume(tally["mid-edge berth reservations", default: 0] > 100, "paths end at berths along edges")
        assertVolume(tally["enable failures", default: 0] > 10, "traffic control is refused over shared track")
        assertVolume(tally["infrastructure refusals", default: 0] > 30, "held track stays")
        assertVolume(tally["released at the end of a route", default: 0] > 200, "routes end")
        assertVolume(tally["released behind a moving train", default: 0] > 200, "track behind moving trains is released")
    }
}

/// Stage U2's `traffic.following`, a class of its own so that it runs on a
/// shard of its own (campaigns-13): beside `traffic.reservation` the two
/// no longer fitted one job.
final class TrafficFollowingPropertyTests: XCTestCase {
    /// Stage U2: services following the trains ahead of them on a long
    /// line, on GameCore and on the reference side by side; every
    /// operation's outcome and the whole state agree, invariants hold and
    /// the world survives a save exactly.
    func testFollowingMatchesTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        let ran = try runCampaign("traffic.following", cases: 12) { testCase in
            var (world, model) = try TrafficControlPropertyTests.beginFollowing(&testCase)
            for step in 0..<60 {
                let operation = TrafficControlPropertyTests.followingOperation(in: world, using: &testCase.random)
                testCase.note("\(step): \(operation)")
                let before = world
                let outcome = TrafficControlPropertyTests.apply(operation, to: &world)
                let expected = TrafficControlPropertyTests.apply(operation, to: &model)
                guard outcome == expected else {
                    return testCase.fail("\(operation): \(String(describing: outcome)) vs reference \(String(describing: expected))")
                }
                if outcome != nil, !operation.isCompound, world != before { return testCase.fail("refused \(operation) but changed the world") }
                let name = "\(operation)".components(separatedBy: "(")[0]
                tally["\(outcome.map { "\($0)".components(separatedBy: "(")[0] } ?? "ok") \(name)", default: 0] += 1
                if case .advance = operation {
                    for (old, new) in zip(before.trains, world.trains) {
                        guard case .travellingToStop? = new.execution else { continue }
                        let follows = world.trainHoldingRoute(of: new.id) != nil
                        let followed = before.trainHoldingRoute(of: old.id) != nil
                        if follows { tally["following a train ahead", default: 0] += 1 }
                        if follows, case .waitingAtStop? = old.execution { tally["set off following", default: 0] += 1 }
                        if follows, followed, Set(new.reservation).subtracting(old.reservation).isEmpty == false {
                            tally["took more of its route", default: 0] += 1
                        }
                        if followed, !follows, case .travellingToStop? = old.execution { tally["took the rest of its route", default: 0] += 1 }
                    }
                }
                var ignored: [String: Int] = [:]
                let problems = TrafficControlPropertyTests.differences(world, model, tally: &ignored) + WorldInvariants.violations(in: world)
                guard problems.isEmpty else { return testCase.fail(problems.joined(separator: "\n")) }
                if let problem = WorldInvariants.roundTripProblem(of: world) { return testCase.fail(problem) }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        let summary = tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")
        print("[digest] traffic.following \(digest.hex) (\(summary))")
        assertVolume(ran == 12 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["set off following", default: 0] > 15, "services set off following others")
        assertVolume(tally["took more of its route", default: 0] > 10, "following trains take more of their routes")
        assertVolume(tally["took the rest of its route", default: 0] > 10, "following trains take the rest of their routes")
    }
}

extension TrafficFollowingPropertyTests {
    /// A fixed case (seed 9E03B1A53EA6991E, case 1 under PROPERTY_STRESS=8,
    /// cut to two trains): the follower stands at S2 with its head at 7168
    /// on e2, exactly 25600 short of node 3, while the train ahead's tail
    /// crosses node 3 onto e3's first span. The span lies past the node, so
    /// the follower may set off only once the tail has left it (decision
    /// 56, point 3): the reference model agrees with GameCore every minute.
    func testAFollowerWaitsForTheFirstSpanPastANode() throws {
        let minute: Int64 = 1_378
        let costs = ConstructionCosts(track: 100, station: 1_000, train: 500)
        var world = try GameWorld(bounds: WorldBounds(width: 204_800, height: 16_384), economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(now: GameTime(minutes: minute), speed: .normal))
        var model = ReferenceWorld(width: 204_800, height: 16_384, balance: 1_000_000_000, costs: costs, minutes: minute, speed: .normal)
        func both(_ operation: TrafficControlPropertyTests.Operation) {
            XCTAssertEqual(TrafficControlPropertyTests.apply(operation, to: &world), TrafficControlPropertyTests.apply(operation, to: &model), "\(operation)")
        }
        for index in 0...6 {
            let node = WorldCoordinate(x: 2_048 + Int64(index) * 32_768, y: 8_192, z: 0)
            _ = try world.buildTrackNode(at: node)
            XCTAssertNil(model.buildNetworkNode(at: node))
        }
        for index in 1...6 {
            _ = try world.buildTrackEdge(from: .node(index), to: .node(index + 1))
            XCTAssertNil(model.buildNetworkEdge(from: .node(index), to: .node(index + 1), curve: .straight))
        }
        for (index, start) in [11_264, 3_072, 22_528, 23_552, 6_144, 24_576].enumerated() as EnumeratedSequence<[Int64]> {
            let point = PlanPoint(x: 2_048 + Int64(index) * 32_768 + 16_384, y: 9_216)
            _ = try world.buildStation(named: "S\(index + 1)", at: point)
            XCTAssertNil(model.buildStation(named: "S\(index + 1)", at: point))
            both(.addPlatform(StationID(rawValue: index + 1), .edge(index + 1), start, start + 4_096))
        }
        both(.trafficControl(true))
        // The leader (1 car) at S2's berth, the follower (3 cars) at S1's.
        for (cars, edge, offset) in [(1, 2, Int64(7_168)), (3, 1, 15_360)] {
            let train = try world.purchaseTrain(named: "T").id
            _ = model.purchaseTrain(named: "T")
            try world.setTrainCars(train, to: cars)
            _ = model.setCars(train, cars)
            both(.place(train, .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: offset)))
            both(.path(train, [], offset))
            both(.rate(train, 2_048))
        }
        func stop(_ station: Int, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
            ScheduledStop(station: StationID(rawValue: station), arrival: GameTime(seconds: arrival), departure: GameTime(seconds: departure))
        }
        let (leader, follower) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        both(.run(leader, [stop(2, 82_740, 82_740), stop(3, 83_400, 83_400), stop(4, 84_120, 84_180)], nil))
        both(.run(follower, [stop(1, 82_740, 82_740), stop(2, 82_980, 83_040), stop(3, 83_400, 83_460)], nil))
        var followed = false
        for _ in 0..<9 {
            both(.advance(1))
            var tally: [String: Int] = [:]
            let problems = TrafficControlPropertyTests.differences(world, model, tally: &tally)
            XCTAssertEqual(problems, [], "at \(world.clock.now.seconds)")
            guard problems.isEmpty else { return }
            if case .travellingToStop(2, cycle: 0)? = world.train(id: follower)?.execution, world.trainHoldingRoute(of: follower) == leader {
                followed = true
            }
        }
        XCTAssertTrue(followed, "the follower set off from S2 following the leader")
    }
}

extension GameWorld {
    /// Where train `train` would stand turned round, for generating
    /// timetables that turn it first: its head at its tail, read through a
    /// copy of the world (reverseTrain) so nothing here decides it.
    func turnedPosition(of train: Train) -> TrainPosition? {
        var copy = self
        guard (try? copy.setTrafficControl(false)) != nil, (try? copy.reverseTrain(train.id)) != nil else { return nil }
        return copy.train(id: train.id)?.position
    }
}
