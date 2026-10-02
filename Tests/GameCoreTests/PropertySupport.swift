import Foundation
import GameCore
import XCTest

// Deterministic property testing: seeded generators, independent reference
// models and world invariants, shared by the property suites.
//
// Every campaign runs a fixed number of cases for each canonical seed. Each
// case draws from its own generator, derived only from (seed, case index),
// so a failure report ("[suite] seed 0x… case n") replays that one case
// without running the others. Nothing reads the clock, the locale or global
// randomness, and no expectation depends on Set or Dictionary order.

// MARK: - Randomness

/// A small deterministic generator (SplitMix64), so generated cases are the
/// same on every run and platform.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound`. The modulo bias is irrelevant for generating
    /// test cases.
    mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "below(_:) needs a positive bound")
        return Int(next() % UInt64(bound))
    }

    /// `true` with probability `numerator / denominator`.
    mutating func chance(_ numerator: Int, in denominator: Int) -> Bool {
        below(denominator) < numerator
    }

    mutating func element<T>(of array: [T]) -> T {
        array[below(array.count)]
    }

    mutating func int64(in range: ClosedRange<Int64>) -> Int64 {
        let span = UInt64(bitPattern: range.upperBound &- range.lowerBound) &+ 1
        guard span != 0 else { return Int64(bitPattern: next()) }
        return range.lowerBound &+ Int64(bitPattern: next() % span)
    }

    /// The elements of `array` in a generated order (Fisher–Yates).
    mutating func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        var index = result.count - 1
        while index > 0 {
            result.swapAt(index, below(index + 1))
            index -= 1
        }
        return result
    }
}

// MARK: - Campaigns

enum PropertySeeds {
    /// The seeds every campaign runs in CI. Fixed: CI never picks new ones.
    static let canonical: [UInt64] = [0x5EED_A001, 0x5EED_A002, 0x5EED_A003, 0x5EED_A004]

    /// The canonical seeds, plus `PROPERTY_STRESS=<n>` more for a longer
    /// local run. The extra seeds are derived from the canonical ones, so a
    /// stress run is as reproducible as CI.
    static var active: [UInt64] {
        let extra = ProcessInfo.processInfo.environment["PROPERTY_STRESS"].flatMap { Int($0) } ?? 0
        var derive = SplitMix64(seed: 0x5EED_5EED)
        return canonical + (0..<max(0, extra)).map { _ in derive.next() }
    }
}

/// What a campaign has seen so far. Owned by one campaign run, touched only
/// by the test thread; there is no global state.
final class CampaignLog {
    var failingCases = 0
    var failures = 0
}

/// Checks how many cases a campaign ran. Skipped while
/// `PROPERTY_REPLAY` runs a single case.
func assertVolume(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard ProcessInfo.processInfo.environment["PROPERTY_REPLAY"] == nil else { return }
    XCTAssertTrue(condition(), message, file: file, line: line)
}

/// One generated case of a campaign.
struct PropertyCase {
    let suite: String
    let seed: UInt64
    let index: Int
    /// This case's own generator.
    var random: SplitMix64
    /// Parameters written down while generating, for the failure report.
    private(set) var notes: [String] = []
    private let log: CampaignLog

    init(suite: String, seed: UInt64, index: Int, log: CampaignLog = CampaignLog()) {
        self.suite = suite
        self.seed = seed
        self.index = index
        self.log = log
        var mixer = SplitMix64(seed: seed ^ (UInt64(index) &* 0xD1B5_4A32_D192_ED03))
        self.random = SplitMix64(seed: mixer.next())
    }

    var label: String {
        "[\(suite)] seed 0x\(String(seed, radix: 16, uppercase: true)) case \(index)"
    }

    mutating func note(_ text: @autoclosure () -> String) {
        notes.append(text())
    }

    /// The failure text: which case, and how it was generated.
    func report(_ message: String) -> String {
        ([label + ": " + message] + notes.map { "  " + $0 }).joined(separator: "\n")
    }

    /// Fails this case with its full report.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        log.failures += 1
        XCTFail(report(message), file: file, line: line)
    }

    /// Fails this case unless `condition` holds.
    func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !condition() {
            fail(message(), file: file, line: line)
        }
    }
}

/// Runs `body` for `cases` cases of every active seed and returns how many
/// ran. Stops a campaign after three failing cases, so one bug does not
/// flood the log; `PROPERTY_REPLAY=<suite>@<seed hex>@<case>` runs one case.
@discardableResult
func runCampaign(
    _ suite: String,
    cases: Int,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: (inout PropertyCase) throws -> Void
) rethrows -> Int {
    let replay = ProcessInfo.processInfo.environment["PROPERTY_REPLAY"]?.split(separator: "@").map(String.init)
    if let replay, replay.first != suite { return 0 }
    let log = CampaignLog()
    var ran = 0
    for seed in PropertySeeds.active {
        if let replay, replay.count == 3, UInt64(replay[1], radix: 16) != seed { continue }
        for index in 0..<cases {
            if let replay, replay.count == 3, Int(replay[2]) != index { continue }
            var testCase = PropertyCase(suite: suite, seed: seed, index: index, log: log)
            let failuresBefore = log.failures
            try body(&testCase)
            ran += 1
            if log.failures > failuresBefore {
                log.failingCases += 1
                if log.failingCases >= 3 {
                    XCTFail("[\(suite)] stopped after \(log.failingCases) failing cases", file: file, line: line)
                    return ran
                }
            }
        }
    }
    return ran
}

/// A running FNV-1a digest of everything a campaign observed. Two runs of
/// the same campaign (in one process, or in two processes with different
/// hash seeds) must give the same digest.
struct Digest {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01B3
        }
        value ^= 0xFF
        value &*= 0x0000_0100_0000_01B3
    }

    var hex: String { String(value, radix: 16, uppercase: true) }
}

// MARK: - Geometry

/// The direction from `position` to `neighbor` when they are orthogonal
/// neighbours, worked out here rather than taken from GameCore. Comparing
/// instead of subtracting cannot overflow.
func stepDirection(from position: GridPosition, to neighbor: GridPosition) -> TrackDirection? {
    if position.x == neighbor.x {
        if position.y != .min, neighbor.y == position.y - 1 { return .north }
        if position.y != .max, neighbor.y == position.y + 1 { return .south }
    } else if position.y == neighbor.y {
        if position.x != .max, neighbor.x == position.x + 1 { return .east }
        if position.x != .min, neighbor.x == position.x - 1 { return .west }
    }
    return nil
}

func step(_ position: GridPosition, _ direction: TrackDirection) -> GridPosition {
    switch direction {
    case .north: GridPosition(x: position.x, y: position.y - 1)
    case .east: GridPosition(x: position.x + 1, y: position.y)
    case .south: GridPosition(x: position.x, y: position.y + 1)
    case .west: GridPosition(x: position.x - 1, y: position.y)
    }
}

/// The node a train stands on or is heading for, and the way it faces there.
func ahead(of position: TrainPosition) -> (node: GridPosition, heading: TrackDirection) {
    switch position {
    case .atNode(let tile, let heading):
        return (tile, heading)
    case .onLink(let from, let to, _):
        guard let heading = stepDirection(from: from, to: to) else {
            preconditionFailure("\(position) is not a link between neighbours")
        }
        return (to, heading)
    case .onEdge:
        preconditionFailure("ahead(of:) is for positions on the grid")
    }
}

// MARK: - Generated networks

/// A tile of a generated network, built through the public commands.
struct TileSpec {
    enum Kind {
        case track(TrackConnections)
        case station
        /// Only the track-resource campaign (`TrackResourcePropertyTests`) draws these.
        case turnout(TrackConnections, stem: TrackDirection)
        case crossing
    }

    let position: GridPosition
    let kind: Kind
}

/// The shapes of network the campaigns generate.
enum NetworkShape: CaseIterable {
    /// Random track, a few stations, joined neighbours, dangling exits.
    case random
    /// One straight line, dead ends at both ends.
    case line
    /// A rectangle loop with tails leaving it through junctions.
    case loopWithTails
    /// Every tile a four-way junction: many cycles and equal routes.
    case grid
    /// Two parallel lines joined by rungs: equal-length alternatives.
    case ladder
    /// Two random networks with an empty column between them.
    case twoComponents
}

enum NetworkGenerator {
    static let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

    /// A world of the given size with the generated tiles built in order.
    static func build(_ specs: [TileSpec], width: Int, height: Int) throws -> GameWorld {
        var world = try GameWorld(
            width: width,
            height: height,
            economy: GameEconomy(balance: 1_000_000_000, costs: costs),
            clock: GameClock(speed: .normal)
        )
        for spec in specs {
            switch spec.kind {
            case .track(let connections):
                try world.buildTrack(at: spec.position, connections: connections)
            case .station:
                try world.buildStation(named: "S\(spec.position.x)-\(spec.position.y)", at: spec.position)
            case .turnout(let connections, let stem):
                try world.buildTurnout(at: spec.position, connections: connections, stem: stem)
            case .crossing:
                try world.buildCrossing(at: spec.position)
            }
        }
        return world
    }

    /// Tiles for a generated network of `shape`, and the map size.
    static func specs(_ shape: NetworkShape, using random: inout SplitMix64) -> (specs: [TileSpec], width: Int, height: Int) {
        switch shape {
        case .random:
            let width = 3 + random.below(5)
            let height = 3 + random.below(5)
            return (randomSpecs(width: width, height: height, originX: 0, using: &random), width, height)
        case .line:
            let length = 2 + random.below(7)
            let vertical = random.chance(1, in: 2)
            var exits: [GridPosition: TrackConnections] = [:]
            let tiles = (0..<length).map { vertical ? GridPosition(x: 1, y: $0) : GridPosition(x: $0, y: 1) }
            for (a, b) in zip(tiles, tiles.dropFirst()) {
                join(a, b, in: &exits)
            }
            let size = length + 1
            return (tiles.map { TileSpec(position: $0, kind: .track(exits[$0] ?? .north)) }, size, size)
        case .loopWithTails:
            let width = 2 + random.below(4)
            let height = 2 + random.below(4)
            var exits: [GridPosition: TrackConnections] = [:]
            var ring: [GridPosition] = []
            for x in 0..<width { ring.append(GridPosition(x: x + 1, y: 1)) }
            for y in 1..<height { ring.append(GridPosition(x: width, y: y + 1)) }
            for x in stride(from: width - 1, through: 1, by: -1) where height > 1 { ring.append(GridPosition(x: x, y: height)) }
            for y in stride(from: height - 1, through: 2, by: -1) where width > 1 { ring.append(GridPosition(x: 1, y: y)) }
            for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) where a != b && stepDirection(from: a, to: b) != nil {
                join(a, b, in: &exits)
            }
            // Tails: straight spurs leaving the ring outward from some tiles.
            for tile in ring where random.chance(1, in: 4) {
                let outward: [TrackDirection] = [
                    tile.y == 1 ? .north : nil, tile.x == width ? .east : nil,
                    tile.y == height ? .south : nil, tile.x == 1 ? .west : nil,
                ].compactMap { $0 }
                guard let way = outward.first else { continue }
                var previous = tile
                for _ in 0..<(1 + random.below(2)) {
                    let next = step(previous, way)
                    guard next.x >= 0, next.y >= 0, exits[next] == nil else { break }
                    join(previous, next, in: &exits)
                    previous = next
                }
            }
            return (sortedSpecs(exits), width + 4, height + 4)
        case .grid:
            let width = 2 + random.below(4)
            let height = 2 + random.below(4)
            var specs: [TileSpec] = []
            for y in 0..<height {
                for x in 0..<width {
                    var connections: TrackConnections = []
                    if y > 0 { connections.insert(.north) }
                    if x < width - 1 { connections.insert(.east) }
                    if y < height - 1 { connections.insert(.south) }
                    if x > 0 { connections.insert(.west) }
                    specs.append(TileSpec(position: GridPosition(x: x, y: y), kind: .track(connections.isEmpty ? .north : connections)))
                }
            }
            return (specs, width + 1, height + 1)
        case .ladder:
            let length = 3 + random.below(5)
            var exits: [GridPosition: TrackConnections] = [:]
            for x in 0..<(length - 1) {
                join(GridPosition(x: x, y: 0), GridPosition(x: x + 1, y: 0), in: &exits)
                join(GridPosition(x: x, y: 2), GridPosition(x: x + 1, y: 2), in: &exits)
            }
            for x in 0..<length where x == 0 || x == length - 1 || random.chance(1, in: 3) {
                join(GridPosition(x: x, y: 0), GridPosition(x: x, y: 1), in: &exits)
                join(GridPosition(x: x, y: 1), GridPosition(x: x, y: 2), in: &exits)
            }
            return (sortedSpecs(exits), length + 1, 4)
        case .twoComponents:
            let height = 3 + random.below(3)
            let left = 2 + random.below(3)
            let right = 2 + random.below(3)
            let specs = randomSpecs(width: left, height: height, originX: 0, using: &random)
                + randomSpecs(width: right, height: height, originX: left + 1, using: &random)
            return (specs, left + 1 + right, height)
        }
    }

    /// Mostly track, a few stations; neighbouring track joined both ways
    /// with some probability, and some exits left dangling.
    static func randomSpecs(width: Int, height: Int, originX: Int, using random: inout SplitMix64) -> [TileSpec] {
        var kinds: [GridPosition: Int] = [:]
        var exits: [GridPosition: TrackConnections] = [:]
        for y in 0..<height {
            for x in originX..<(originX + width) {
                let roll = random.below(20)
                kinds[GridPosition(x: x, y: y)] = roll < 15 ? 0 : (roll < 16 ? 1 : 2)
            }
        }
        for y in 0..<height {
            for x in originX..<(originX + width) {
                let tile = GridPosition(x: x, y: y)
                guard kinds[tile] == 0 else { continue }
                for way in [TrackDirection.east, .south] {
                    let neighbor = step(tile, way)
                    if kinds[neighbor] == 0, random.chance(6, in: 10) {
                        join(tile, neighbor, in: &exits)
                    }
                }
                if random.chance(1, in: 5) {
                    exits[tile, default: []].insert(TrackConnections(random.element(of: TrackDirection.allCases)))
                }
            }
        }
        var specs: [TileSpec] = []
        for y in 0..<height {
            for x in originX..<(originX + width) {
                let tile = GridPosition(x: x, y: y)
                if kinds[tile] == 0 {
                    let connections = exits[tile] ?? TrackConnections(random.element(of: TrackDirection.allCases))
                    specs.append(TileSpec(position: tile, kind: .track(connections)))
                } else if kinds[tile] == 1 {
                    specs.append(TileSpec(position: tile, kind: .station))
                }
            }
        }
        return specs
    }

    private static func join(_ a: GridPosition, _ b: GridPosition, in exits: inout [GridPosition: TrackConnections]) {
        guard let way = stepDirection(from: a, to: b) else { return }
        exits[a, default: []].insert(TrackConnections(way))
        exits[b, default: []].insert(TrackConnections(way.opposite))
    }

    /// Specs in row-major order, so building never depends on dictionary order.
    private static func sortedSpecs(_ exits: [GridPosition: TrackConnections]) -> [TileSpec] {
        exits.keys
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            .map { TileSpec(position: $0, kind: .track(exits[$0] ?? .north)) }
    }
}

// MARK: - Positions and paths

enum PositionGenerator {
    /// Offsets on both sides of every boundary, and the middle.
    static let edgeOffsets: [Int64] = [1, 2, 3, 255, 256, 511, 512, 513, 767, 768, 1021, 1022, 1023]

    /// A valid position on the world's track, or `nil` without track.
    static func validPosition(in world: GameWorld, using random: inout SplitMix64) -> TrainPosition? {
        let tracks = world.tracks
        guard !tracks.isEmpty else { return nil }
        let tile = random.element(of: tracks).position
        let neighbors = world.connectedNeighbors(of: tile)
        if !neighbors.isEmpty, random.chance(1, in: 2) {
            let offset = random.chance(1, in: 2) ? random.element(of: edgeOffsets) : random.int64(in: 1...1023)
            return .onLink(from: tile, to: random.element(of: neighbors), offset: offset)
        }
        return .atNode(tile, heading: random.element(of: TrackDirection.allCases))
    }

    /// A walk of up to `length` joined links from the node ahead of
    /// `position`, never turning straight back: a valid continuation.
    static func walk(in world: GameWorld, from position: TrainPosition, length: Int, using random: inout SplitMix64) -> [GridPosition] {
        var (node, heading) = ahead(of: position)
        var nodes: [GridPosition] = []
        for _ in 0..<length {
            let options = world.connectedNeighbors(of: node).filter { stepDirection(from: node, to: $0) != heading.opposite }
            guard !options.isEmpty else { break }
            let next = random.element(of: options)
            heading = stepDirection(from: node, to: next)!
            node = next
            nodes.append(next)
        }
        return nodes
    }
}

// MARK: - Reference movement

/// Train movement written a second way, one unit at a time, straight from
/// the rules of ARCHITECTURE decision 15 rather than from the kernel's
/// arithmetic: travel the link; at a node with distance left, enter the next
/// entry only if it is a joined neighbour that is not straight back; else stop
/// and drop the rest.
enum ReferenceMovement {
    struct Result: Equatable {
        var position: TrainPosition
        /// Entries entered, counted from the start of the continuation.
        var cursor: Int
        /// Units actually travelled.
        var travelled: Int64
    }

    /// Only for distances of a few thousand units: it steps unit by unit.
    static func travel(
        in world: GameWorld,
        from start: TrainPosition,
        distance: Int64,
        continuation: [GridPosition],
        cursor startCursor: Int
    ) -> Result {
        enum Place {
            case node(GridPosition, TrackDirection)
            case link(GridPosition, GridPosition, Int64)
        }
        var place: Place
        switch start {
        case .atNode(let tile, let heading): place = .node(tile, heading)
        case .onLink(let from, let to, let offset): place = .link(from, to, offset)
        case .onEdge: preconditionFailure("ReferenceMovement is for positions on the grid")
        }
        var cursor = startCursor
        var remaining = distance
        var travelled: Int64 = 0
        walking: while remaining > 0 {
            switch place {
            case .link(let from, let to, let offset):
                remaining -= 1
                travelled += 1
                if offset + 1 == TrainPosition.linkLength {
                    place = .node(to, stepDirection(from: from, to: to)!)
                } else {
                    place = .link(from, to, offset + 1)
                }
            case .node(let node, let heading):
                guard cursor < continuation.count else { break walking }
                let next = continuation[cursor]
                guard let way = stepDirection(from: node, to: next), way != heading.opposite,
                      world.isConnected(node, to: next)
                else { break walking }
                cursor += 1
                // The next unit moves it off the node.
                place = .link(node, next, 0)
            }
        }
        switch place {
        case .node(let tile, let heading):
            return Result(position: .atNode(tile, heading: heading), cursor: cursor, travelled: travelled)
        case .link(let from, let to, let offset):
            precondition(offset > 0, "a link is only entered with distance to travel")
            return Result(position: .onLink(from: from, to: to, offset: offset), cursor: cursor, travelled: travelled)
        }
    }
}

// MARK: - Reference route

/// Route finding written a second way (moved from TrainRouteTests): the
/// distance in links from every (node, heading) to the destination by
/// relaxing until nothing changes, then from the start the first direction
/// in north, east, south, west order that keeps the distance falling by one.
enum ReferenceRoute {
    private struct State: Hashable {
        var node: GridPosition
        var heading: TrackDirection
    }

    static func route(in world: GameWorld, from start: TrainPosition, to destination: GridPosition) -> [GridPosition]? {
        let startState: State
        switch start {
        case .atNode(let tile, let heading):
            guard world.track(at: tile) != nil else { return nil }
            startState = State(node: tile, heading: heading)
        case .onLink(let from, let to, let offset):
            guard (1...1023).contains(offset), world.isConnected(from, to: to), let heading = stepDirection(from: from, to: to) else { return nil }
            startState = State(node: to, heading: heading)
        case .onEdge:
            return nil
        }
        guard world.track(at: destination) != nil else { return nil }

        func moves(from state: State) -> [State] {
            world.connectedNeighbors(of: state.node).compactMap { neighbor in
                guard let way = stepDirection(from: state.node, to: neighbor), way != state.heading.opposite else { return nil }
                return State(node: neighbor, heading: way)
            }
        }
        let states = world.tracks.flatMap { track in TrackDirection.allCases.map { State(node: track.position, heading: $0) } }
        var distance: [State: Int] = [:]
        for state in states where state.node == destination {
            distance[state] = 0
        }
        var changed = true
        while changed {
            changed = false
            for state in states where state.node != destination {
                let best = moves(from: state).compactMap { distance[$0] }.min().map { $0 + 1 }
                if let best, best < distance[state] ?? Int.max {
                    distance[state] = best
                    changed = true
                }
            }
        }

        guard var remaining = distance[startState] else { return nil }
        var state = startState
        var route: [GridPosition] = []
        while remaining > 0 {
            guard let next = moves(from: state).first(where: { distance[$0] == remaining - 1 }) else { return nil }
            route.append(next.node)
            state = next
            remaining -= 1
        }
        return route
    }
}

// MARK: - World invariants

enum WorldInvariants {
    /// Every documented invariant a world reachable through commands must
    /// keep; each broken one is described. Checked from the public state only.
    static func violations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let ids = world.trains.map(\.id.rawValue)
        if ids != ids.sorted() || Set(ids).count != ids.count {
            problems.append("train IDs not unique and ascending: \(ids)")
        }
        for station in world.stations where world.map.tile(at: station.position)?.type != .station(id: station.id) {
            problems.append("station \(station.id.rawValue) does not match its tile")
        }
        // Decision 27: every tile of a station is its tile on the map, each
        // annex beside an earlier tile, none twice; no other station tiles.
        for station in world.stations {
            var earlier = [station.position]
            for annex in station.annexes {
                if world.map.tile(at: annex)?.type != .station(id: station.id) {
                    problems.append("station \(station.id.rawValue) annex \(annex) does not match its tile")
                }
                if earlier.contains(annex) || !earlier.contains(where: { stepDirection(from: $0, to: annex) != nil }) {
                    problems.append("station \(station.id.rawValue) annex \(annex) is not beside an earlier tile")
                }
                earlier.append(annex)
            }
        }
        let stationTiles = world.map.tiles.filter { if case .station = $0.type { true } else { false } }.count
        if stationTiles != world.stations.reduce(0, { $0 + 1 + $1.annexes.count }) {
            problems.append("\(stationTiles) station tiles for \(world.stations.count) stations")
        }
        // Decision 29 (S3A): the railway network holds the grid's track, one
        // piece a tile, in row-major order, each on the map's empty land.
        let positions = world.tracks.map(\.position)
        if positions != positions.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) || Set(positions).count != positions.count {
            problems.append("grid track not one piece a tile in row-major order")
        }
        for track in world.tracks where world.map.tile(at: track.position)?.type != .empty || world.track(at: track.position) != track {
            problems.append("grid track at \(track.position) is not on empty land or not found there")
        }
        // Decision 26: a turnout has three exits or more, its stem among them.
        for track in world.tracks {
            if case .turnout(let stem) = track.layout, track.connections.directions.count < 3 || !track.connections.contains(TrackConnections(stem)) {
                problems.append("turnout at \(track.position) with exits \(track.connections) and stem \(stem)")
            }
        }
        // Decision 22: lines in ID order, each with two stops or more (none
        // twice in a row) at known stations, a rate of 1 or more, a window
        // that opens within the day and closes after it by 06:00 the next
        // morning, and no negative count; a day that starts at minute 0 and
        // strictly increases within the day.
        let lineIDs = world.lines.map(\.id.rawValue)
        if lineIDs != lineIDs.sorted() || Set(lineIDs).count != lineIDs.count || lineIDs.contains(where: { $0 < 1 }) {
            problems.append("line IDs not unique, positive and ascending: \(lineIDs)")
        }
        for line in world.lines {
            let id = line.id.rawValue
            if line.stops.count < 2 || zip(line.stops, line.stops.dropFirst()).contains(where: { $0 == $1 }) {
                problems.append("line \(id) stops \(line.stops)")
            }
            for stop in line.stops where world.station(id: stop) == nil {
                problems.append("line \(id) calls at unknown station \(stop.rawValue)")
            }
            if line.rate < 1 { problems.append("line \(id) rate \(line.rate)") }
            if case .hours(let open, let close) = line.window, !(open >= 0 && open < 1440 && close > open && close <= 1800) {
                problems.append("line \(id) window \(open)-\(close)")
            }
            // No negative count. Decision 23: targets of 2 to 1440 minutes;
            // trains in ID order, known, and on this line only; a last
            // dispatch from minute 0 to now; a line's train in service runs
            // a trip that is not repeated. Decision 24: the same for each
            // pattern, whose calls are two or more of the line's stops,
            // rising; no train on two services.
            let services: [(name: String, counts: TrainsInService, targets: TargetHeadways, trains: [TrainID], last: GameTime?)] =
                [("line \(id)", line.trainsInService, line.targetHeadways, line.trains, line.lastDispatch)]
                + line.patterns.enumerated().map { ("line \(id) pattern \($0)", $1.trainsInService, $1.targetHeadways, $1.trains, $1.lastDispatch) }
            for pattern in line.patterns {
                let calls = pattern.calls
                if calls.count < 2 || calls[0] < 0 || calls[calls.count - 1] >= line.stops.count || zip(calls, calls.dropFirst()).contains(where: { $0 >= $1 }) {
                    problems.append("line \(id) pattern calls \(calls) for \(line.stops.count) stops")
                }
            }
            for service in services {
                if min(service.counts.peak, service.counts.offPeak, service.counts.low) < 0 { problems.append("\(service.name) negative trains") }
                for level in ServiceLevel.allCases {
                    if let target = service.targets[level], !(2...1440).contains(target) {
                        problems.append("\(service.name) target \(target) at \(level)")
                    }
                }
                if zip(service.trains, service.trains.dropFirst()).contains(where: { $0 >= $1 }) {
                    problems.append("\(service.name) trains \(service.trains) not ascending")
                }
                for train in service.trains {
                    if world.train(id: train) == nil { problems.append("\(service.name) has unknown train \(train.rawValue)") }
                    let homes = world.lines.reduce(0) { count, other in
                        count + (other.trains.contains(train) ? 1 : 0) + other.patterns.filter { $0.trains.contains(train) }.count
                    }
                    if homes > 1 {
                        problems.append("train \(train.rawValue) is on two lines or services")
                    }
                    if let running = world.train(id: train), running.execution != nil, running.timetablePeriod != nil {
                        problems.append("\(service.name)'s train \(train.rawValue) runs a repeating timetable")
                    }
                }
                if let last = service.last, last.seconds < 0 || last > world.clock.now {
                    problems.append("\(service.name) last dispatch \(last.seconds) at second \(world.clock.now.seconds)")
                }
            }
        }
        // Decision 29: the track network.
        problems += NetworkInvariants.violations(in: world)
        // Decision 32: traffic control.
        problems += trafficViolations(in: world)
        problems += passengerViolations(in: world)
        problems += accountsViolations(in: world)
        let starts = world.serviceDay.bands.map(\.start)
        if starts.first != 0 || starts.contains(where: { $0 >= 1440 }) || zip(starts, starts.dropFirst()).contains(where: { $0 >= $1 }) {
            problems.append("service day starts \(starts)")
        }
        for train in world.trains {
            // Decision 19: times never go back from minute 0, and every stop
            // is at a station the world has, placed or not.
            let times = train.timetable.flatMap { [$0.arrival.seconds, $0.departure.seconds] }
            if times.contains(where: { $0 < 0 }) || zip(times, times.dropFirst()).contains(where: { $0 > $1 }) {
                problems.append("train \(train.id.rawValue) timetable goes back in time: \(times)")
            }
            for stop in train.timetable where world.station(id: stop.station) == nil {
                problems.append("train \(train.id.rawValue) timetable names unknown station \(stop.station.rawValue)")
            }
            // Decision 21: a repeating timetable has a stop and a period of a
            // minute or more, and does not go back when it starts again.
            if let period = train.timetablePeriod {
                if let first = train.timetable.first, let last = train.timetable.last {
                    // Stage W2a: times and periods are seconds.
                    let (again, overflow) = first.arrival.seconds.addingReportingOverflow(period)
                    if period < 1 || (!overflow && last.departure.seconds > again) {
                        problems.append("train \(train.id.rawValue) timetable cannot repeat every \(period) minutes")
                    }
                } else {
                    problems.append("train \(train.id.rawValue) repeats an empty timetable")
                }
            }
            problems += serviceViolations(of: train, in: world)
            problems += bodyViolations(of: train, in: world)
            let movement = train.movement
            guard let position = train.position else {
                if movement != .idle { problems.append("unplaced train \(train.id.rawValue) is not idle") }
                continue
            }
            switch position {
            case .atNode(let tile, _):
                if world.track(at: tile) == nil { problems.append("train \(train.id.rawValue) at \(tile) is not on track") }
            case .onLink(let from, let to, let offset):
                if !(1...1023).contains(offset) { problems.append("train \(train.id.rawValue) offset \(offset)") }
                if !world.isConnected(from, to: to) { problems.append("train \(train.id.rawValue) link \(from)->\(to) not joined") }
            case .onEdge:
                // Decision 29: checked with the network's own invariants.
                problems += NetworkInvariants.trainViolations(of: train, in: world)
                continue
            }
            if movement.rate < 0 { problems.append("train \(train.id.rawValue) negative rate") }
            let count = movement.continuation.count
            if !(count == 0 && movement.cursor == 0) && !(0..<count).contains(movement.cursor) {
                problems.append("train \(train.id.rawValue) cursor \(movement.cursor) of \(count)")
                continue
            }
            let (node, heading) = ahead(of: position)
            if movement.cursor >= 1, movement.continuation[movement.cursor - 1] != node {
                problems.append("train \(train.id.rawValue) last entered entry is not the node ahead")
            }
            if movement.cursor >= 2,
               stepDirection(from: movement.continuation[movement.cursor - 2], to: movement.continuation[movement.cursor - 1]) != heading {
                problems.append("train \(train.id.rawValue) heading disagrees with the last entered link")
            }
            var (current, facing) = (node, heading)
            for next in movement.remainingContinuation {
                guard let way = stepDirection(from: current, to: next), way != facing.opposite else {
                    problems.append("train \(train.id.rawValue) remaining continuation is not a path from \(node)")
                    break
                }
                (current, facing) = (next, way)
            }
            if !movement.continuation.allSatisfy(world.map.contains) {
                problems.append("train \(train.id.rawValue) continuation leaves the map")
            }
        }
        return problems
    }

    /// Decision 34: every passenger released at a station is accounted
    /// for (released = waiting + overflowed + abandoned), no station holds
    /// more than its capacity, groups wait in the order they came, no later
    /// than now, for a trip the world still has; records are by station,
    /// each of an existing station, and none says nothing.
    static func passengerViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let stations = world.passengers.map(\.station)
        if stations != stations.sorted() || Set(stations).count != stations.count {
            problems.append("passenger records not by ascending station")
        }
        for record in world.passengers {
            let id = record.station.rawValue
            if world.station(id: record.station) == nil { problems.append("passengers at station \(id), which does not exist") }
            let waiting = record.waiting.reduce(Int64(0)) { $0 + $1.count }
            let ledger = world.passengerLedger(of: record.station)
            if ledger.waiting != waiting { problems.append("station \(id) counts \(ledger.waiting) waiting in \(waiting)") }
            // Decision 35: and those riding or arrived.
            let riding = world.riders.flatMap(\.groups).filter { $0.origin == record.station }.reduce(Int64(0)) { $0 + $1.count }
            if ledger.riding != riding { problems.append("station \(id) counts \(ledger.riding) riding of \(riding)") }
            if ledger.released != waiting + riding + ledger.arrived + ledger.overflowed + ledger.abandoned
                || ledger.overflowed < 0 || ledger.abandoned < 0 || ledger.arrived < 0 || ledger.refused < 0 {
                problems.append("station \(id) does not account for its passengers: \(ledger)")
            }
            if waiting > StationPassengers.capacity { problems.append("station \(id) holds \(waiting) waiting") }
            if record.demand == nil, record.released == 0, record.remainders.isEmpty { problems.append("station \(id) keeps an empty record") }
            for (earlier, later) in zip(record.waiting, record.waiting.dropFirst())
            where later.since < earlier.since || (later.since == earlier.since && later.destination <= earlier.destination) {
                problems.append("station \(id) queue out of order")
            }
            for group in record.waiting {
                if group.count < 1 || group.since >= world.clock.now { problems.append("station \(id) has a group \(group)") }
                let line = world.lines.first { $0.id == group.line }
                let from = line?.stops.firstIndex(of: record.station)
                let to = line?.stops.firstIndex(of: group.destination)
                if let from, let to, from != to, (to > from ? LineDirection.outbound : .inbound) == group.direction { continue }
                problems.append("station \(id) has a group whose line does not take it that way")
            }
            for remainder in record.remainders where !(1..<3600).contains(remainder.value) || remainder.destination == record.station {
                problems.append("station \(id) keeps remainder \(remainder)")
            }
        }
        problems += riderViolations(in: world)
        return problems
    }

    /// Decision 35: riders are listed once for each train that has any, by
    /// train; the train runs a service and holds no more than its cars ×
    /// 352; each group, listed once by origin and destination, came from a
    /// station with a record and rides to a station the train calls at
    /// from the stop it is at or heading for up to the next stop where it
    /// turns round (or its last).
    static func riderViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let trains = world.riders.map(\.train)
        if trains != trains.sorted() || Set(trains).count != trains.count { problems.append("riders not by ascending train") }
        for entry in world.riders {
            let id = entry.train.rawValue
            guard let train = world.train(id: entry.train), let execution = train.execution else {
                problems.append("riders on train \(id), which runs no service")
                continue
            }
            let pairs = entry.groups.map { [$0.origin.rawValue, $0.destination.rawValue] }
            if entry.groups.isEmpty || pairs != pairs.sorted(by: { $0.lexicographicallyPrecedes($1) }) || Set(pairs).count != pairs.count {
                problems.append("train \(id) riders not listed once each by origin and destination")
            }
            let total = entry.groups.reduce(Int64(0)) { $0 + $1.count }
            if total > Int64(train.cars) * 320 * 11 / 10 { problems.append("train \(id) carries \(total) on \(train.cars) cars") }
            var ahead: Set<StationID> = []
            for stop in execution.stop..<train.timetable.count {
                ahead.insert(train.timetable[stop].station)
                if train.timetable[stop].reverses { break }
            }
            for group in entry.groups {
                if group.count < 1 { problems.append("train \(id) has an empty group") }
                if !world.passengers.contains(where: { $0.station == group.origin }) { problems.append("train \(id) riders from a station without a record") }
                if !ahead.contains(group.destination) { problems.append("train \(id) riders to \(group.destination.rawValue), which it does not call at next") }
            }
        }
        return problems
    }

    /// Decision 36: a managed company's accounts are open, never after
    /// now; the hour's counts are not negative and its fares whole dollars;
    /// at most 50 rows, none dated after now, each of its kind's items with
    /// fares in, costs out and the items adding up to the row; at most 720
    /// days, once each and ascending, no total negative.
    static func accountsViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let accounts = world.accounts
        if accounts.mode == .management, accounts.openedAt == nil { problems.append("managed accounts never opened") }
        if let opened = accounts.openedAt, opened > world.clock.now { problems.append("accounts open at second \(opened.seconds), after now") }
        let pending = accounts.pending
        if [pending.fareTrips, pending.departures, pending.trainDistance, pending.passengers, pending.seats, pending.fareRevenue.amount].contains(where: { $0 < 0 }) {
            problems.append("the hour's counts go negative: \(pending)")
        }
        if pending.fareRevenue.amount % 100 != 0 { problems.append("the hour's fares \(pending.fareRevenue.amount) are not whole dollars") }
        if accounts.entries.count > 50 { problems.append("\(accounts.entries.count) ledger rows kept") }
        for entry in accounts.entries {
            if entry.time > world.clock.now { problems.append("ledger row dated second \(entry.time.seconds), after now") }
            let expected: [LedgerItem] = switch entry.kind {
            case .hourlyNet: [.fareRevenue, .operatingCost, .maintenanceCost]
            case .dailyEnergy: [.routeEnergy, .trainEnergy]
            case .dailyStaff: [.stationStaff, .trainStaff]
            }
            var sum: Int64 = 0
            for line in entry.breakdown {
                sum += line.amount.amount
                if (line.item == .fareRevenue) != (line.amount.amount >= 0) && line.amount.amount != 0 {
                    problems.append("ledger row \(entry.kind) has \(line.item) of \(line.amount.amount)")
                }
            }
            if entry.breakdown.map(\.item) != expected || sum != entry.amount.amount || (entry.crowding != nil) != (entry.kind == .hourlyNet) {
                problems.append("ledger row \(entry) is not shaped as settlements write it")
            }
        }
        if accounts.days.count > 720 { problems.append("\(accounts.days.count) days kept") }
        let days = accounts.days.map(\.day)
        if days != days.sorted() || Set(days).count != days.count { problems.append("days not once each, ascending: \(days)") }
        for day in accounts.days {
            let totals = [day.fareRevenue, day.operatingCost, day.maintenanceCost, day.energyCost, day.staffCost].map(\.amount)
            if totals.contains(where: { $0 < 0 }) { problems.append("day \(day.day) has a negative total") }
        }
        return problems
    }

    /// Decision 32: without traffic control nothing is reserved. With it,
    /// no two trains hold the same track; a reservation is in resource
    /// order without repeats, belongs to a placed train and holds what the
    /// train stands on; a train plainly standing (at a node with nothing
    /// left to enter, or at the end of its path on its own edge) has none,
    /// and one plainly on its way (on a grid link, with grid steps left, or
    /// short of where its path ends on its own edge) has one.
    static func trafficViolations(in world: GameWorld) -> [String] {
        guard world.isTrafficControlEnabled else {
            return world.trains.contains { !$0.reservation.isEmpty } ? ["a reservation while traffic control is off"] : []
        }
        var problems: [String] = []
        let placed = world.trains.filter { $0.position != nil }
        for (index, train) in placed.enumerated() {
            let held = Set(world.heldResources(of: train.id))
            for other in placed[..<index] where !held.isDisjoint(with: world.heldResources(of: other.id)) {
                problems.append("trains \(other.id.rawValue) and \(train.id.rawValue) hold the same track")
            }
        }
        for train in world.trains {
            let id = train.id.rawValue
            let reservation = train.reservation
            if zip(reservation, reservation.dropFirst()).contains(where: { $0 >= $1 }) {
                problems.append("train \(id)'s reservation is not in resource order without repeats")
            }
            if world.reservedResources(of: train.id) != reservation { problems.append("train \(id)'s reservation reads differently") }
            guard let position = train.position else {
                if !reservation.isEmpty { problems.append("unplaced train \(id) has a reservation") }
                continue
            }
            if !reservation.isEmpty, !Set(world.occupiedResources(of: train.id)).isSubset(of: reservation) {
                problems.append("train \(id)'s reservation does not hold what it stands on")
            }
            let movement = train.movement
            var stands: Bool?
            switch position {
            case .atNode:
                stands = movement.remainingContinuation.isEmpty
            case .onLink:
                stands = false
            case .onEdge(let traversal, let offset):
                if movement.cursor == movement.edges.count, let length = world.trackEdge(traversal.edge)?.length {
                    stands = offset == (movement.end ?? length)
                }
            }
            if stands == true, !reservation.isEmpty { problems.append("standing train \(id) has a reservation") }
            if stands == false, reservation.isEmpty { problems.append("train \(id) on its way has no reservation") }
        }
        return problems
    }

    /// Decision 27: 1 to 16 cars; no body off the track; on it, the body
    /// starts right behind the head (the tile behind a train at a node, the
    /// `from` end of a link), runs over joined track by turns a train may
    /// take, and ends at the first node at or beyond the tail.
    static func bodyViolations(of train: Train, in world: GameWorld) -> [String] {
        let id = train.id.rawValue
        var problems: [String] = []
        if !(1...16).contains(train.cars) { problems.append("train \(id) has \(train.cars) cars") }
        guard let position = train.position else {
            if !train.trail.isEmpty { problems.append("unplaced train \(id) has a body") }
            return problems
        }
        // One car to a tile: a link between car centres.
        let length = Int64(train.cars - 1) * 1024
        var spine: [GridPosition]
        var distance: Int64
        switch position {
        case .atNode(let tile, let heading):
            if let first = train.trail.first, stepDirection(from: tile, to: first) != heading.opposite {
                problems.append("train \(id)'s body does not start behind it")
            }
            spine = [tile]
            distance = 1024
        case .onLink(let from, let to, let offset):
            if let first = train.trail.first, first != from {
                problems.append("train \(id)'s body does not start at its link's far end")
            }
            spine = [to]
            distance = offset
        case .onEdge:
            if !train.trail.isEmpty { problems.append("train \(id) on the track network has a grid trail") }
            return problems
        }
        // The distances of the nodes: each must be short of the tail but
        // the last, which must reach it.
        for (index, node) in train.trail.enumerated() {
            let last = index == train.trail.count - 1
            if last ? distance < length : distance >= length {
                problems.append("train \(id)'s body of \(train.trail.count) nodes does not fit \(train.cars) cars")
                break
            }
            distance += 1024
            spine.append(node)
        }
        if length > 0, train.trail.isEmpty { problems.append("train \(id) of \(train.cars) cars has no body") }
        if length == 0, !train.trail.isEmpty { problems.append("train \(id) of one car has a body") }
        for index in spine.indices.dropFirst() where !world.isConnected(spine[index - 1], to: spine[index]) {
            problems.append("train \(id)'s body crosses \(spine[index - 1])-\(spine[index]), which is not joined")
        }
        for index in spine.indices.dropFirst().dropLast() {
            let heading = stepDirection(from: spine[index + 1], to: spine[index])!
            if !world.exits(from: spine[index], facing: heading).contains(spine[index - 1]) {
                problems.append("train \(id)'s body turns at \(spine[index]) where no train may")
            }
        }
        return problems
    }

    /// Decision 20: a service points at an entry of the timetable of a
    /// placed train; a waiting train is stopped at that entry's station; a
    /// travelling one heads for an entry after the service's first, has not
    /// ended its journey, and ends it next to that entry's station.
    /// Decision 21: the cycle is 0 unless the timetable repeats, and then
    /// its latest time still fits in a game minute. Decision 31: on the
    /// track network a travelling train's path is not spent and ends at the
    /// far end, the way it travels, of a platform of that station no shorter
    /// than the train.
    static func serviceViolations(of train: Train, in world: GameWorld) -> [String] {
        guard let execution = train.execution else { return [] }
        let id = train.id.rawValue
        guard train.timetable.indices.contains(execution.stop) else {
            return ["train \(id) service at stop \(execution.stop) of \(train.timetable.count)"]
        }
        if execution.cycle != 0 {
            guard let period = train.timetablePeriod, execution.cycle > 0 else {
                return ["train \(id) service in cycle \(execution.cycle) of a timetable that does not repeat"]
            }
            let (shift, overflow) = execution.cycle.multipliedReportingOverflow(by: period)
            if overflow || train.timetable.last!.departure.seconds.addingReportingOverflow(shift).overflow {
                return ["train \(id) service in cycle \(execution.cycle), whose times do not fit"]
            }
        }
        guard let position = train.position else { return ["unplaced train \(id) runs a service"] }
        let target = train.timetable[execution.stop].station
        switch execution {
        case .waitingAtStop:
            return world.stationsStoppedAt(by: train.id).contains(target) ? [] : ["train \(id) waits at station \(target.rawValue) but is not stopped there"]
        case .travellingToStop(let stop, let cycle):
            var problems: [String] = []
            if stop < 1, cycle < 1 { problems.append("train \(id) travels to the service's first stop") }
            if case .onEdge(let traversal, let offset) = position {
                return problems + networkServiceViolations(of: train, at: traversal, offset: offset, to: target, in: world)
            }
            let remaining = train.movement.remainingContinuation
            if case .atNode = position, remaining.isEmpty { problems.append("train \(id) travels but its journey has ended") }
            let end = remaining.last ?? ahead(of: position).node
            // Decision 27: beside any tile of the station.
            if let station = world.station(id: target), !station.tiles.contains(where: { stepDirection(from: end, to: $0) != nil }) {
                problems.append("train \(id) travels to station \(target.rawValue) but its journey ends at \(end)")
            }
            return problems
        }
    }

    /// Decision 31: a travelling train on the network has path left and
    /// ends it at a berth of `target` it fits: followed along its edges to
    /// the last where it can be, otherwise one way or the other on its last
    /// edge.
    static func networkServiceViolations(of train: Train, at traversal: TrackTraversal, offset: Int64, to target: StationID, in world: GameWorld) -> [String] {
        let id = train.id.rawValue
        let left = train.movement.remainingEdges
        guard let lastEdge = world.trackEdge(left.last ?? traversal.edge) else { return ["train \(id) travels along a path whose last edge is gone"] }
        let end = train.movement.end ?? lastEdge.length
        if left.isEmpty, offset == end { return ["train \(id) travels but its path is spent"] }
        let ahead = world.pathAhead(of: train.id)
        let lastWay: TrackEdgeDirection? = left.isEmpty ? traversal.direction : ahead.count == left.count ? ahead.last?.direction : nil
        let length = Int64(train.cars - 1) * 1024
        let fits = world.trackPlatforms(of: target).filter { $0.edge == lastEdge.id && $0.end - $0.start >= length }
        let berths = fits.flatMap { platform -> [(TrackEdgeDirection, Int64)] in [(.forward, platform.end), (.backward, lastEdge.length - platform.start)] }
        let ends = berths.contains { berth in berth.1 == end && (lastWay == nil || berth.0 == lastWay) }
        return ends ? [] : ["train \(id) travels to station \(target.rawValue) on a path that ends at \(end) on \(lastEdge.id), no berth of it"]
    }

    /// The world survives a save and load unchanged: the decoder accepts
    /// every state the commands can reach, and loses nothing.
    static func roundTripProblem(of world: GameWorld) -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(world)
            let decoded = try JSONDecoder().decode(GameWorld.self, from: data)
            return decoded == world ? nil : "decoded world differs"
        } catch {
            return "round trip failed: \(error)"
        }
    }
}
