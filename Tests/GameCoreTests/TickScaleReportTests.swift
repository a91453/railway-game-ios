import Foundation
@testable import GameCore
import XCTest

/// What a tick costs as the trains grow from a hundred to ten thousand
/// (docs/research/TICK_SCALE_CLOUD_2026-11-12.md). A report, run only on
/// request; it asserts nothing about speed and changes no rule:
///
///     TICK_SCALE_REPORT=100,500,1000,5000,10000 swift test --skip-build \
///       --filter TickScaleReportTests
///
/// - `TICK_SCALE_REPORT`: the train counts, in order.
/// - `TICK_SCALE_LAYOUT`: `meet` (the default: two trains a module, on two
///   lines that run against each other over a single track with a passing
///   loop, under traffic control) or `solo` (one train a module, nothing to
///   meet), or `ring` (one line with every train: a ring of a few more
///   stations than trains on two tracks, half the trains each way round,
///   each following the train ahead; docs/research/TICK_L1_2026-11-13.md).
/// - `TICK_SCALE_BLOCKS=1`: block sections on.
/// - `TICK_SCALE_CONTROL=0`: traffic control off (trains run through each
///   other, as they do in a game without it): what the step costs without
///   routes to take and give up.
/// - `TICK_SCALE_SPLIT=<trains>`: the same modules as so many worlds of at
///   most that many trains each, stepped one after another: what the step
///   would cost if it took each part of the map that shares no track on
///   its own. The times are the sums over the worlds.
/// - `TICK_SCALE_TICKS`: the ticks timed at each speed (default 60).
/// - `TICK_SCALE_WARM`: the ticks of 600× played before any is timed
///   (default 60, a game hour; a ring sends its trains out a headway
///   apart, so a long one wants more).
/// - `TICK_SCALE_BUDGET`: the seconds a size may spend building and
///   warming before it is given up as "did not finish" (default 900).
/// - `TICK_SCALE_HOLD=<seconds>`: keeps stepping so long after the warm-up
///   of each size and prints the process ID, for a sampler to attach.
///
/// The world is `SingleTrackMeet`'s W–M–E (512 m of single track, a loop
/// at M) laid out again and again on a grid, each module its own track,
/// stations and lines: the modules share nothing but the world, so what
/// grows with their number is what the step does over the whole world.
final class TickScaleReportTests: XCTestCase {
    enum Layout: String { case meet, solo, ring }

    struct GaveUp: Error { let reason: String }

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The process's resident memory in megabytes (Linux's
    /// `/proc/self/statm`, pages of 4 KiB); 0 elsewhere.
    static func residentMegabytes() -> Int {
        guard let text = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else { return 0 }
        let fields = text.split(separator: " ")
        guard fields.count > 1, let pages = Int(fields[1]) else { return 0 }
        return pages * 4_096 / 1_048_576
    }

    /// `trains` trains on modules of `layout`, or the reason the world
    /// could not be built within `budget` seconds.
    static func world(trains: Int, layout: Layout, blocks: Bool, control: Bool = true, budget: Double) throws -> GameWorld {
        if layout == .ring { return try ring(trains: trains, blocks: blocks, control: control, budget: budget) }
        let perModule = layout == .meet ? 2 : 1
        let modules = (trains + perModule - 1) / perModule
        let columns = max(1, Int(Double(modules).squareRoot() / 1.7))
        let rows = (modules + columns - 1) / columns
        let width: Int64 = 36_864, height: Int64 = 12_288
        var world = try GameWorld(
            bounds: WorldBounds(width: width * Int64(columns), height: height * Int64(rows)),
            economy: GameEconomy(balance: 1_000_000_000_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal)
        )
        let clock = ContinuousClock()
        let started = clock.now
        var placed = 0
        for module in 0..<modules {
            if module % 16 == 0, ms(clock.now - started) > budget * 1_000 {
                throw GaveUp(reason: "building stopped at \(placed) of \(trains) trains after \(Int(budget)) s")
            }
            let dx = width * Int64(module % columns), dy = height * Int64(module / columns)
            let node = module * 6, edge = module * 6, station = module * 3
            for point in SingleTrackMeet.points() { _ = try world.buildTrackNode(at: WorldCoordinate(x: point.x + dx, y: point.y + dy)) }
            let entrance = TrackCurve.cubic(.init(x: 11_264 + dx, y: 4_096 + dy), .init(x: 11_264 + dx, y: 6_144 + dy))
            let exit = TrackCurve.cubic(.init(x: 23_552 + dx, y: 6_144 + dy), .init(x: 23_552 + dx, y: 4_096 + dy))
            for index in 1...3 { _ = try world.buildTrackEdge(from: .node(node + index), to: .node(node + index + 1)) }
            _ = try world.buildTrackEdge(from: .node(node + 2), to: .node(node + 5), curve: entrance)
            _ = try world.buildTrackEdge(from: .node(node + 5), to: .node(node + 6))
            _ = try world.buildTrackEdge(from: .node(node + 6), to: .node(node + 3), curve: exit)
            var ids: [StationID] = []
            for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
                ids.append(try world.buildStation(named: "\(name)\(module)", at: PlanPoint(x: x + dx, y: 8_192 + dy)).id)
            }
            XCTAssertEqual(ids.first, StationID(rawValue: station + 1))
            for (index, platform) in SingleTrackMeet.platforms().enumerated() {
                try world.addTrackPlatform(ids[[0, 1, 1, 2][index]], on: .edge(edge + platform.1), from: platform.2, to: platform.3)
            }
            let starts: [(stops: [StationID], traversal: TrackTraversal, offset: Int64)] = [
                (ids, SingleTrackMeet.forward(edge + 1), 3_072),
                (ids.reversed(), SingleTrackMeet.backward(edge + 3), 3_072),
            ]
            for start in starts.prefix(perModule) where placed < trains {
                let line = try world.createLine(named: "L\(placed)", stops: start.stops).id
                let train = try SingleTrackMeet.stand(&world, edge: start.traversal, offset: start.offset)
                try world.assignTrain(train, to: line)
                try world.setLineServiceWindow(line, to: .allDay)
                try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
                placed += 1
            }
        }
        if control { try world.setTrafficControl(true) }
        if blocks { world.setBlockSections(true) }
        return world
    }

    /// One line with every train: a ring of six stations more than trains
    /// (made even) on two tracks that never meet, an outer one the
    /// trains run clockwise and an inner one they run the other way, each
    /// a rectangle with half the stations along the top and half along the
    /// bottom, a platform of every station on each. Half the trains start
    /// on each track, at every other station, so each has one train ahead
    /// of it a station or two away: what the step costs when the trains
    /// follow each other along one line, as on a real main line.
    static func ring(trains: Int, blocks: Bool, control: Bool, budget: Double) throws -> GameWorld {
        // Six stations more than trains: a ring runs fewer trains than it
        // has stations, and one left standing at a platform stops the rest.
        let side = (trains + 1) / 2 + 3
        let pitch: Int64 = 12_288, gap: Int64 = 2_048, depth: Int64 = 16_384
        var world = try GameWorld(
            bounds: WorldBounds(width: pitch * Int64(side + 2) + 2 * depth, height: depth + 4 * 4_096),
            economy: GameEconomy(balance: 1_000_000_000_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal)
        )
        let clock = ContinuousClock()
        let started = clock.now
        func check(_ what: String) throws {
            if ms(clock.now - started) > budget * 1_000 { throw GaveUp(reason: "building stopped at \(what) after \(Int(budget)) s") }
        }
        // A track: its ends `inset` in from the outer one's, the edges
        // built clockwise, each end a curve that leaves the top and comes
        // to the bottom along them. The edges along the top and the
        // bottom, the first and the last of each without a platform.
        func track(inset: Int64) throws -> (top: [TrackEdgeID], bottom: [TrackEdgeID]) {
            let left = depth + inset, right = depth + pitch * Int64(side + 2) - inset
            let top = 4_096 + inset, bottom = 4_096 + depth - inset
            var points: [WorldCoordinate] = []
            for column in 0...(side + 2) {
                points.append(WorldCoordinate(x: column == 0 ? left : column == side + 2 ? right : depth + pitch * Int64(column), y: top))
            }
            points += points.reversed().map { WorldCoordinate(x: $0.x, y: bottom) }
            var nodes: [TrackNodeID] = []
            for (index, point) in points.enumerated() {
                if index % 64 == 0 { try check("the track") }
                nodes.append(try world.buildTrackNode(at: point))
            }
            var edges: [TrackEdgeID] = []
            for index in nodes.indices {
                if index % 64 == 0 { try check("the track") }
                let bulge = (bottom - top) * 2 / 3
                let curve: TrackCurve = index == side + 2 ? .cubic(.init(x: right + bulge, y: top), .init(x: right + bulge, y: bottom))
                    : index == nodes.count - 1 ? .cubic(.init(x: left - bulge, y: bottom), .init(x: left - bulge, y: top)) : .straight
                edges.append(try world.buildTrackEdge(from: nodes[index], to: nodes[(index + 1) % nodes.count], curve: curve))
            }
            return (Array(edges[0..<(side + 2)]), Array(edges[(side + 3)..<(2 * side + 5)]))
        }
        let outer = try track(inset: 0), inner = try track(inset: gap)
        var stops: [StationID] = []
        // Clockwise: along the top from the left, then along the bottom
        // from the right.
        for index in 0..<(2 * side) {
            if index % 64 == 0 { try check("the stations") }
            let onTop = index < side, column = onTop ? index + 1 : index - side + 1
            let x = onTop ? depth + pitch * Int64(column) + pitch / 2 : depth + pitch * Int64(side + 2 - column) - pitch / 2
            let station = try world.buildStation(named: "R\(index)", at: PlanPoint(x: x, y: onTop ? 4_096 + 2 * gap : 4_096 + depth - 2 * gap)).id
            try world.addTrackPlatform(station, on: (onTop ? outer.top : outer.bottom)[column], from: 4_096, to: 6_144)
            try world.addTrackPlatform(station, on: (onTop ? inner.top : inner.bottom)[column], from: 4_096, to: 6_144)
            stops.append(station)
        }
        let line = try world.createLine(named: "Ring", stops: stops).id
        try world.setLineRing(line, to: true)
        // A ring's trains run in pairs (decision 49): the first, the third
        // and so on the way the stops are listed, on the outer track.
        let pairs = max(1, trains / 2)
        for index in 0..<(2 * pairs) {
            if index % 64 == 0 { try check("the trains") }
            let clockwise = index % 2 == 0
            let stop = (index / 2) * (2 * side) / pairs
            let onTop = stop < side, column = onTop ? stop + 1 : stop - side + 1
            let edge = clockwise ? (onTop ? outer.top : outer.bottom)[column] : (onTop ? inner.top : inner.bottom)[column]
            let train = try SingleTrackMeet.stand(
                &world, edge: TrackTraversal(edge: edge, direction: clockwise ? .forward : .backward), offset: clockwise ? 6_144 : pitch - 4_096
            )
            try world.assignTrain(train, to: line)
        }
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2 * pairs, offPeak: 2 * pairs, low: 2 * pairs))
        // Decision 172: a ring's train goes out from the stop it stands at.
        world.setFlexDispatch(true)
        if control { try world.setTrafficControl(true) }
        if blocks { world.setBlockSections(true) }
        return world
    }

    func testWhatATickCostsAsTheTrainsGrow() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["TICK_SCALE_REPORT"] else {
            throw XCTSkip("set TICK_SCALE_REPORT=<trains>,… to time the ticks as the trains grow")
        }
        let layout = try XCTUnwrap(Layout(rawValue: environment["TICK_SCALE_LAYOUT"] ?? "meet"))
        let blocks = environment["TICK_SCALE_BLOCKS"] != nil
        let control = environment["TICK_SCALE_CONTROL"] != "0"
        let split = Int(environment["TICK_SCALE_SPLIT"] ?? "")
        let ticks = Int(environment["TICK_SCALE_TICKS"] ?? "") ?? 60
        let budget = Double(environment["TICK_SCALE_BUDGET"] ?? "") ?? 900
        let warm = Int(environment["TICK_SCALE_WARM"] ?? "") ?? 60
        let hold = Int(environment["TICK_SCALE_HOLD"] ?? "") ?? 0
        let clock = ContinuousClock()
        var rows = [
            "| Trains | Worlds | Lines | Stations | Edges | Build s | 600× tick ms: median | p95 | slowest | 6000× tick ms: median | slowest | Trains that moved | Deadlocked | Waiting riders | Copy and change ms | JSON MB | Encode ms | Decode ms | Resident MB |",
            "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        func note(_ text: String) { FileHandle.standardError.write(Data("TICKSCALE \(text)\n".utf8)) }
        for count in value.split(separator: ",").compactMap({ Int($0) }) where count > 0 {
            do {
                var worlds: [GameWorld] = []
                let building = try clock.measure {
                    var left = count
                    while left > 0 {
                        let part = min(left, split ?? left)
                        worlds.append(try Self.world(trains: part, layout: layout, blocks: blocks, control: control, budget: budget))
                        left -= part
                    }
                }
                note("\(count): built in \(Int(Self.ms(building))) ms")
                // One tick of every world.
                func step() throws -> Double {
                    Self.ms(try clock.measure { for index in worlds.indices { try worlds[index].advance(ticks: 1) } })
                }
                // A game hour at 600× warms what a running game keeps; the
                // first ticks are the dearest, so each is watched.
                let warming = clock.now
                for tick in 0..<warm {
                    let spent = try step()
                    if tick < 3 || spent > 5_000 { note("\(count): warm-up tick \(tick) took \(Int(spent)) ms") }
                    if Self.ms(clock.now - warming) > budget * 1_000 {
                        throw GaveUp(reason: "warm-up stopped at tick \(tick + 1) of \(warm) after \(Int(budget)) s (that tick \(Int(spent)) ms)")
                    }
                }
                if hold > 0 {
                    note("\(count): pid \(ProcessInfo.processInfo.processIdentifier), running for \(hold) s")
                    let until = clock.now + .seconds(hold)
                    while clock.now < until { _ = try step() }
                }
                let before = worlds.flatMap(\.trains)
                func timed(_ speed: GameSpeed, _ ticks: Int) throws -> [Double] {
                    for index in worlds.indices { worlds[index].setSpeed(speed) }
                    var times: [Double] = []
                    let started = clock.now
                    for _ in 0..<ticks {
                        times.append(try step())
                        if Self.ms(clock.now - started) > budget * 1_000 { break }
                    }
                    return times.sorted()
                }
                let normal = try timed(.normal, ticks)
                let moved = zip(before, worlds.flatMap(\.trains)).filter { $0.0.position != $0.1.position }.count
                let fast = try timed(.fast, max(1, ticks / 6))
                for index in worlds.indices { worlds[index].setSpeed(.normal) }
                let deadlocked = worlds.reduce(0) { $0 + $1.deadlockedTrains().count }
                let waiting = worlds.reduce(Int64(0)) { $1.passengers.reduce($0) { $0 + $1.waitingCount } }
                // What handing the world to another thread and stepping it
                // there costs beyond the step: a copy whose arrays are then
                // written to (a tick of a paused clock moves nothing).
                let copying = try clock.measure {
                    for world in worlds {
                        var copy = world
                        copy.setSpeed(.double)
                        try copy.advance(ticks: 1)
                        XCTAssertNotEqual(copy.clock.now, world.clock.now)
                    }
                }
                let encoder = JSONEncoder()
                var saves: [Data] = []
                let encoding = try clock.measure { saves = try worlds.map { try encoder.encode(SavedGame(world: $0)) } }
                var decoded = 0
                let decoding = try clock.measure {
                    for save in saves { decoded += try JSONDecoder().decode(SavedGame.self, from: save).world.trains.count }
                }
                XCTAssertEqual(decoded, count)
                func at(_ times: [Double], _ share: Double) -> Double { times[min(times.count - 1, Int(Double(times.count) * share))] }
                rows.append(String(
                    format: "| %d | %d | %d | %d | %d | %.1f | %.2f | %.2f | %.2f | %.1f | %.1f | %d | %d | %d | %.2f | %.2f | %.0f | %.0f | %d |",
                    count, worlds.count, worlds.reduce(0) { $0 + $1.lines.count }, worlds.reduce(0) { $0 + $1.stations.count },
                    worlds.reduce(0) { $0 + $1.network.edges.count }, Self.ms(building) / 1_000,
                    at(normal, 0.5), at(normal, 0.95), normal.last ?? 0, at(fast, 0.5), fast.last ?? 0, moved, deadlocked, waiting,
                    Self.ms(copying), Double(saves.reduce(0) { $0 + $1.count }) / 1_048_576, Self.ms(encoding), Self.ms(decoding), Self.residentMegabytes()
                ))
                note(rows.last ?? "")
            } catch let gaveUp as GaveUp {
                rows.append("| \(count) | did not finish: \(gaveUp.reason) |")
                note(rows.last ?? "")
            }
        }
        print("layout \(layout.rawValue), traffic control \(control ? "on" : "off"), block sections \(blocks ? "on" : "off"), \(split.map { "worlds of \($0) trains" } ?? "one world"), \(ticks) ticks timed at 600×")
        print(rows.joined(separator: "\n"))
    }
}
