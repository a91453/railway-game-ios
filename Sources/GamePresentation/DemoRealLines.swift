import Foundation
import GameCore

// The demo mode's real lines (decision 351, its sequel): on a real-world
// map, one tap lays the real TRA, High Speed Rail, metro and light rail
// lines whose stations are in view, along their real alignment, with a
// platform at each real station, a line calling at them and trains
// running it every few minutes. Every step is one of the player's own
// commands (the trace of decision 213, ``PlayerCommand/addPlatform(_:)``,
// ``PlayerCommand/Edit/createLine(name:stops:targets:)``,
// ``PlayerCommand/Edit/staffLine(_:headway:type:cars:language:)``), so
// GameCore checks each as ever and one Undo takes all of it back.
//
// The reference has no one-tap network: `Ci/`'s lines are drawn by the
// player. What it gives is the bundled lines and stations
// (`track_lines.geojson`, `track_stations.geojson`, each line's stations in
// order) and the real headways (decision 298's operations).

/// The real lines to lay in a part of a real-world map (decision 351):
/// worked out from the real railways alone, off the main actor.
public struct DemoRealLines: Sendable {
    /// A station of a line, where it stands along the line and the span of
    /// its platform.
    struct Stop: Sendable {
        let chinese: String
        let along: Double
        let platform: ClosedRange<Double>
        let inView: Bool
    }

    /// Some stations of one real line that are in view one after another,
    /// to be laid as one line of the game.
    struct Route: Sendable {
        /// The line's key (`mrt|BL`), its system and its site name.
        let lineKey: String
        let system: RealRailways.System
        let name: String
        let color: RealRailways.RGB
        /// The line's centre line, end to end.
        let path: WorldPath
        let stops: [Stop]
        /// Cars of its trains; its platforms take a car more.
        let cars: Int
    }

    let routes: [Route]

    static let metre = RealRailwayTraces.metre
    /// How far a station may stand from its line's centre line.
    static let stationReach = 150 * metre
    /// The least track between two platforms of a line: a node either side
    /// of each platform needs room (``RealWorldDemo/platformMargin``,
    /// ``RealWorldDemo/shortestEdge``).
    static let platformGap = 2 * RealWorldDemo.platformMargin + RealWorldDemo.shortestEdge
    /// How far the track runs on past each end platform: room for the
    /// crossover there, beyond the platform.
    static let runOn = 150 * metre
    /// The widest view laid at once: 40 km across. Wider, the player is
    /// asked to zoom in.
    public static let widestView = 40_000 * metre

    /// Cars of each system's trains, about as many as its real trains
    /// have: the TRA's EMU sets 8, the High Speed Rail's 12, Taipei's metro
    /// 6, Kaohsiung's and Taoyuan's 3 and 4, the light rails and Taichung's
    /// 2, the Alishan Forest Railway's 4.
    static func cars(ofSystem system: String) -> Int {
        switch system {
        case "tra_sched": 8
        case "thsr_sched": 12
        case "mrt": 6
        case "tymc", "afr_sched": 4
        case "krtc", "sanying": 3
        default: 2
        }
    }

    /// Whether a system's track is double: all but the Alishan Forest
    /// Railway's; the TRA's as the real line is where the data says
    /// (``GameSession/realDoubleTrack(along:)``).
    static func isDouble(system: String) -> Bool {
        system != "afr_sched"
    }

    /// How far apart the lines' levels are: more than the 8 m GameCore
    /// keeps between two tracks that cross (``GameError``'s crossing).
    static let levelStep = Int64(12) * WorldCoordinate.unitsPerMetre
    /// The levels there are room for: 48 m below the ground to 48 m above.
    static let levels: Int64 = 4

    /// The level of the `number`th line laid: the ground, then 12 m below
    /// it, 12 m above, 24 m below, and so on, round again after 48 m.
    static func level(_ number: Int) -> Int64 {
        let step = Int64(number) % (2 * levels + 1)
        guard step > 0 else { return 0 }
        let depth = (step + 1) / 2 * levelStep
        return step % 2 == 1 ? -depth : depth
    }

    /// The minutes between trains where the data has no headway: the
    /// metros' 6, the others' 15.
    static func headway(ofSystem system: String) -> Int64 {
        switch system {
        case "tra_sched", "thsr_sched", "afr_sched": 15
        default: 6
        }
    }

    /// The real lines with stations in `view` (and in `bounds`), as
    /// `frame` projects them: for each line its pieces joined end to end,
    /// its stations along them in order, each with a platform of its
    /// trains' cars and one more, `carLength` long each.
    static func plan(railways: RealRailways, frame: RealWorldFrame, bounds: WorldBounds, view: WorldRegion, carLength: Int64) -> DemoRealLines {
        let map = WorldRegion(bounds: bounds)
        func world(_ coordinate: RealRailways.Coordinate) -> WorldVector {
            WorldVector(frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func inside(_ point: WorldVector, _ region: WorldRegion) -> Bool {
            point.x >= region.minX && point.x <= region.maxX && point.y >= region.minY && point.y <= region.maxY
        }
        var pieces: [String: [RealRailways.Line]] = [:]
        for line in railways.lines {
            pieces[line.lineKey, default: []].append(line)
        }
        var routes: [Route] = []
        for key in railways.stops.keys.sorted() {
            guard let lines = pieces[key], let first = lines.first, let stops = railways.stops[key] else { continue }
            let points = stops.map { (chinese: $0.chinese, point: world($0.coordinate)) }
            guard points.contains(where: { inside($0.point, view) && inside($0.point, map) }) else { continue }
            let cars = cars(ofSystem: first.system.id)
            let length = Double(Int64(cars + 1) * carLength)
            for chain in Self.chains(lines.map { $0.points.map(world) }) {
                let path = WorldPath(chain)
                guard path.points.count > 1 else { continue }
                // Its stations on this piece, in order along it, each with
                // room for its platform and the track between.
                var found: [(chinese: String, along: Double, point: WorldVector)] = []
                for station in points {
                    let near = path.nearest(station.point)
                    if near.away <= stationReach { found.append((station.chinese, near.along, station.point)) }
                }
                found.sort { $0.along < $1.along }
                var placed: [Stop] = []
                for station in found {
                    let low = min(max(0, station.along - length / 2), path.length - length)
                    guard low >= 0 else { continue }
                    if let last = placed.last, low < last.platform.upperBound + platformGap { continue }
                    let ends = [path.point(at: low), path.point(at: low + length)]
                    let inView = ends.allSatisfy { inside($0, view) && inside($0, map) }
                    placed.append(Stop(chinese: station.chinese, along: station.along, platform: low...(low + length), inView: inView))
                }
                // Each run of stations in view one after another.
                var run: [Stop] = []
                for stop in placed + [Stop(chinese: "", along: 0, platform: 0...0, inView: false)] {
                    if stop.inView {
                        run.append(stop)
                        continue
                    }
                    if run.count >= 2 {
                        routes.append(Route(
                            lineKey: key, system: first.system, name: first.name, color: first.palette.color,
                            path: path, stops: run, cars: cars
                        ))
                    }
                    run = []
                }
            }
        }
        return DemoRealLines(routes: routes)
    }

    /// The pieces of a line joined end to end where one ends within
    /// ``RealRailwayTraces/joinReach`` of where another begins or ends,
    /// in the site's order: a line in several pieces (the TRA's Western
    /// Trunk Line north, the Bannan Line, the High Speed Rail) as one.
    static func chains(_ pieces: [[WorldVector]]) -> [[WorldVector]] {
        var chains: [[WorldVector]] = []
        let reach = RealRailwayTraces.joinReach
        for piece in pieces where piece.count > 1 {
            guard var chain = chains.popLast() else {
                chains.append(piece)
                continue
            }
            let head = chain[0], tail = chain[chain.count - 1]
            if (piece[0] - tail).length <= reach {
                chain += piece.dropFirst()
            } else if (piece[piece.count - 1] - tail).length <= reach {
                chain += piece.reversed().dropFirst()
            } else if (piece[piece.count - 1] - head).length <= reach {
                chain = piece.dropLast() + chain
            } else if (piece[0] - head).length <= reach {
                chain = piece.reversed().dropLast() + chain
            } else {
                chains.append(chain)
                chain = piece
            }
            chains.append(chain)
        }
        return chains
    }

    /// How far the laying has got: stations done of all those in view.
    public struct Progress: Hashable, Sendable {
        public let done: Int
        public let total: Int
    }

    /// What one tap laid.
    public struct Outcome: Hashable, Sendable {
        public let lines: Int
        public let stations: Int
        /// The stations in view that could not be reached: GameCore refused
        /// the track or the platform there.
        public let missed: Int
        /// Whether traffic control was turned off for the trains.
        public let trafficControlOff: Bool
    }
}

extension GameSession {
    /// Whether the map can lay the real lines in view (decision 351): a
    /// demo game on a real-world map with the real railways.
    public var canLayDemoRealLines: Bool {
        news.isDemo && railways != nil && RealWorldFrame(world: world) != nil
    }

    /// Lays the real lines with stations in `view` (decision 351): the
    /// plan worked out off the main actor, then each line's track, its
    /// platforms, a line calling at them and its trains, as the player's
    /// own commands, one Undo for all of it. ``demoRealLinesProgress`` says
    /// how far it has got. `nil` when nothing is laid (not a demo, not a
    /// real-world map, a view too wide, or no real station in view); the
    /// message says why.
    @discardableResult
    public func layDemoRealLines(in view: WorldRegion) async -> DemoRealLines.Outcome? {
        guard canLayDemoRealLines, demoRealLinesProgress == nil, let railways, let frame = RealWorldFrame(world: world) else { return nil }
        guard view.maxX - view.minX <= DemoRealLines.widestView, view.maxY - view.minY <= DemoRealLines.widestView else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Zoom in closer: the real lines are laid for a view up to 40 km across.",
                "請再放大一點：一次只鋪畫面 40 公里以內的真實路線。"
            ))
            return nil
        }
        let bounds = world.bounds, carLength = world.platformCarLength
        demoRealLinesProgress = DemoRealLines.Progress(done: 0, total: 0)
        defer { demoRealLinesProgress = nil }
        let planned = await Task.detached(priority: .userInitiated) {
            DemoRealLines.plan(railways: railways, frame: frame, bounds: bounds, view: view, carLength: carLength)
        }.value
        let total = planned.routes.reduce(0) { $0 + $1.stops.count }
        guard total > 0 else {
            message = StatusMessage(kind: .failure, text: language.text(
                "No two stations of a real line are in view here.",
                "畫面裡沒有同一條真實路線的兩個車站。"
            ))
            return nil
        }
        demoRealLinesProgress = DemoRealLines.Progress(done: 0, total: total)

        // The track as the trace lays it with the tool's own choices; the
        // clock stopped meanwhile, so no tick splits the one Undo, and
        // running again as it was after.
        let tool = (height: networkHeight, structure: networkStructure)
        let speed = world.clock.isPaused ? nil : world.clock.speed
        if speed != nil { setSpeed(.paused) }
        networkHeight = 0
        networkStructure = .automatic
        beginEditGesture()
        defer {
            endEditGesture()
            networkHeight = tool.height
            networkStructure = tool.structure
            if let speed { setSpeed(speed) }
        }
        // As the real-line demos run (decision 228): a line's trains wait
        // one behind another where its trips start, and set off a headway
        // apart.
        let controlled = world.isTrafficControlEnabled
        if controlled { _ = try? performCommand(.edit(.setTrafficControl(false))) }
        var done = 0, lines = 0, stations = 0
        for (number, route) in planned.routes.enumerated() {
            // Each line on its own level, as the real lines cross over and
            // under each other: at the ground, then below and above it.
            networkHeight = DemoRealLines.level(number)
            // A run from the first station on, then, where the track
            // stops short, another from the first station it missed.
            var index = 0
            while index < route.stops.count - 1 {
                let laid = await layDemoRun(Array(route.stops[index...]), of: route)
                stations += laid.stations.count
                if laid.stations.count >= 2, addDemoLine(route, calling: laid.stations) { lines += 1 }
                index += laid.reached
                demoRealLinesProgress = DemoRealLines.Progress(done: min(done + index, total), total: total)
                await Task.yield()
            }
            done += route.stops.count
        }
        let outcome = DemoRealLines.Outcome(
            lines: lines, stations: stations, missed: max(0, total - stations), trafficControlOff: controlled && !world.isTrafficControlEnabled
        )
        message = StatusMessage(kind: lines > 0 ? .success : .failure, text: Self.demoRealLinesText(outcome, in: language))
        return outcome
    }

    /// What the message says after laying.
    static func demoRealLinesText(_ outcome: DemoRealLines.Outcome, in language: DisplayLanguage) -> String {
        var text = language.text(
            "Laid \(outcome.lines) real \(outcome.lines == 1 ? "line" : "lines") with \(outcome.stations) stations; the trains are running.",
            "鋪好 \(outcome.lines) 條真實路線、\(outcome.stations) 個車站，列車已開始行駛。"
        )
        if outcome.lines == 0 {
            text = language.text("No real line could be laid here.", "這裡鋪不了真實路線。")
        }
        if outcome.missed > 0 {
            text += language.text(
                " \(outcome.missed) \(outcome.missed == 1 ? "station was" : "stations were") left out where the track could not go.",
                "有 \(outcome.missed) 個車站因為軌道鋪不過去而略過。"
            )
        }
        if outcome.trafficControlOff {
            text += language.text(
                " Traffic control is off, so each line's trains set off one after another.",
                "交通控制已關閉，讓每條路線的列車依序發車。"
            )
        }
        return text
    }

    /// Lays `run`'s track along `route` from its first platform to its
    /// last as one traced command, as far as GameCore builds it, and a
    /// platform at each station it reaches. Returns the stations with a
    /// platform, in order, and how many stations of `run` the track
    /// reached.
    private func layDemoRun(_ run: [DemoRealLines.Stop], of route: DemoRealLines.Route) async -> (stations: [StationID], reached: Int) {
        guard let first = run.first, let last = run.last else { return ([], 0) }
        let path = route.path
        // On past the end platforms, for the crossovers there.
        let lower = max(0, first.platform.lowerBound - DemoRealLines.runOn)
        let upper = min(path.length, last.platform.upperBound + DemoRealLines.runOn)
        let way = path.points(from: lower, to: upper)
        let start = NetworkAnchor.point(path.point(at: lower).plan)
        let end = NetworkAnchor.point(path.point(at: upper).plan)
        let spans = run.map { (path.point(at: $0.platform.lowerBound), path.point(at: $0.platform.upperBound)) }
        guard let plan = tracePlan(from: start, to: end, along: way, platforms: spans), plan.buildable > 0 else { return ([], 1) }
        let built = Array(plan.stretches.prefix(plan.buildable))
        // How many stations the track reaches: their platforms all built.
        let reached = plan.platformStretches.prefix { $0.map { $0 < plan.buildable } ?? false }.count

        var command = PlayerCommand.buildTrackChain(built)
        let double = route.system.id == Self.traSystem
            ? realDoubleTrack(along: built) ?? true
            : DemoRealLines.isDouble(system: route.system.id)
        // A crossover at each end, so a train turns back onto the other
        // track (decision 247's, which the tool lays only where it joins
        // track).
        if double, let parallel = parallelChain(beside: built.map(ChainSegment.init), side: networkDoubleSide, in: world),
           let found = try? planDoubleChain(main: built, run: [], parallel: parallel, platforms: [], wantsCrossover: (true, true), in: world) {
            command = found.command
        }
        do throws(GameError) {
            try performCommand(command)
        } catch {
            return ([], max(1, reached))
        }
        await Task.yield()

        var stations: [StationID] = []
        for (stop, index) in zip(run.prefix(reached), plan.platformStretches) {
            guard let index, let edge = demoEdge(from: built[index].from.plan, to: built[index].to.plan) else { continue }
            if let station = addDemoPlatform(on: edge, named: stop.chinese, of: route) {
                stations.append(station)
            }
        }
        return (stations, max(1, reached))
    }

    /// The edge of the network from the node at `a` to the node at `b`
    /// (either way round).
    private func demoEdge(from a: PlanPoint, to b: PlanPoint) -> TrackEdge? {
        let network = world.network
        func near(_ node: TrackNodeID, _ point: PlanPoint) -> Bool {
            guard let position = network.node(node)?.position.plan else { return false }
            return abs(position.x - point.x) <= 1 && abs(position.y - point.y) <= 1
        }
        return network.edges.last { edge in
            (near(edge.from, a) && near(edge.to, b)) || (near(edge.from, b) && near(edge.to, a))
        }
    }

    /// A platform the whole of `edge`, levelled where it climbs, with one
    /// beside it on a second track (decision 285), of the station of the
    /// game named as the real one within 450 m, or a new one. Returns the
    /// station; `nil` where GameCore refuses it.
    private func addDemoPlatform(on edge: TrackEdge, named chinese: String, of route: DemoRealLines.Route) -> StationID? {
        let stretch = (edge: edge.id, start: Int64(0), end: edge.length)
        guard let geometry = world.trackGeometry(of: edge.id) else { return nil }
        var levelling: PlatformLevelling?
        if platformGrade(of: stretch) != nil, case .success(let found) = platformLevelling(of: edge.id, from: 0, to: edge.length, in: world) {
            levelling = found
        }
        var middle = geometry.location(at: edge.length / 2).position.plan
        if let levelling, let level = Self.platformMiddle(levelling) { middle = level }
        let real = railways?.stations.first { $0.id == "\(route.system.id)|\(chinese)" }
        let name = real?.name(in: language) ?? chinese
        let reach = Double(Self.realSectionReach)
        let existing = world.stations.first { station in
            station.name == name
                && (WorldVector(station.location) - WorldVector(middle)).length <= reach
        }
        let station = existing.map { PlayerCommand.PlatformStation.existing($0.id) }
            ?? .new(name: name, at: middle, demand: newStationDemand(at: middle))
        for beside in [besidePlatform(of: stretch), nil] {
            let addition = PlayerCommand.PlatformAddition(
                edge: edge.id, start: 0, end: edge.length, station: station, levelling: levelling, beside: beside
            )
            if let outcome = try? performCommand(.addPlatform(addition)), let id = outcome.station?.id { return id }
            if beside == nil { break }
        }
        return nil
    }

    /// A line of the game calling at `stations`, named after the real line,
    /// in its colour, with trains every few minutes: the real line's peak
    /// headway where the data has it. Whether the line was made.
    private func addDemoLine(_ route: DemoRealLines.Route, calling stations: [StationID]) -> Bool {
        let real = realLine(calling: stations)
        let targets = real.flatMap { realTargetHeadways(of: $0.line, inSystem: $0.system) }
        let headway = targets?.peak ?? DemoRealLines.headway(ofSystem: route.system.id)
        let ends = [stations.first, stations.last].compactMap { $0.flatMap { world.station(id: $0)?.name } }
        let name = language.text(
            "\(route.system.name(in: language)) \(ends.joined(separator: "–"))",
            "\(route.name.split(separator: "（").first.map(String.init) ?? route.name) \(ends.joined(separator: "–"))"
        )
        guard let line = try? performCommand(.edit(.createLine(name: name, stops: stations, targets: targets))).line else { return false }
        let color = route.color
        if let rgb = LineColor(rgb: Int(color.red) << 16 | Int(color.green) << 8 | Int(color.blue)) {
            _ = try? performCommand(.edit(.setLineColor(line.id, rgb)))
        }
        _ = try? performCommand(.edit(.staffLine(line.id, headway: headway, type: nil, cars: route.cars, language: language)))
        return true
    }
}
