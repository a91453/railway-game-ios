import GameCore

// Decision 605 (third part): a line bought before its real layout came,
// rebuilt as real. The Taoyuan Airport MRT has been bought with a passing
// loop outside each track at Chang Gung Memorial Hospital (A8), where its
// expresses overtake the stopping trains, and with the timetable whose
// expresses pass the stations between since decision 605; a game saved
// with the line bought before then has two tracks there and every train
// stopping everywhere. A save is never changed when it is read (decision
// 315); the line's panel offers the rebuild, priced, and the player
// decides, as it offers a missing depot (decision 557).
//
// Laid before decision 605, A8's track is level only along its platforms
// (112 m) and climbs at 25 to 38‰ beyond them, steeper than a turnout may
// stand on (decision 233), up to the turn-back crossovers some 60 m on: no
// loop fits beside it. So the rebuild lays the station's stretch again as
// the purchase lays it now (``RealLineAcquisition``): both tracks between
// two of their nodes beyond the crossovers taken up and laid anew, level
// 150 m either way of the station's middle, a loop 6 m outside each
// track's platform with the purchase's 50 m ramps, and the crossovers
// where the purchase puts them, joined to the track kept at those nodes.

/// A line rebuilt as real (decision 605): its overtaking station's
/// stretch taken up and laid again with a loop outside each platform,
/// and the timetable whose expresses overtake there, built with
/// ``GameWorld``'s commands. It holds every node, edge and platform, so
/// the command log replays it without the real data (decision 193).
public struct RealLineRebuild: Hashable, Sendable, Codable {
    /// The line rebuilt.
    public let line: LineID
    /// The real line's name in the app's data (`tymc:A`).
    public let realLine: String
    /// The station the loops are added at.
    let station: StationID
    /// Its platforms taken up, the first track's first.
    let platforms: [TrackPlatform]
    /// The track taken up, then the nodes left with none, by number.
    let edges: [Int]
    let nodes: [Int]
    /// The nodes kept that the new track joins: the first track's two,
    /// then the second's. ``RealLineAcquisition/NodeAt`` piece 0 is these,
    /// piece `n` the `n`th of ``pieces``. By number.
    let anchors: [Int]
    /// The first track, the second, the loops, the crossovers.
    let pieces: [RealLineAcquisition.Piece]
    /// Where each new platform starts, the first track's, the second's
    /// and each loop's (pieces counted as ``anchors`` says), and how long
    /// they are.
    let berths: [RealLineAcquisition.PieceAt]
    let platformLength: Int64
    /// The line's runs from then on, in its stops' order.
    let runs: [LineRun]
}

/// What the line panel's "rebuild as real" card shows (decision 605).
public struct RealLineRebuildOffer: Sendable {
    public let line: LineID
    /// The station the loops are added at.
    public let station: String
    /// What the rebuild takes, or `nil` with ``problem`` saying why it
    /// cannot be done.
    public let rebuild: RealLineRebuild?
    /// The whole price.
    public let price: Money?
    /// How long a stretch of the line is laid again, in metres.
    public let relaid: Int?
    /// The company's buildings in its way, which come down with it.
    public let demolished: [String]
    public let problem: String?
    /// Whether a run of the line is due or under way: its timetable
    /// changes, so it is rebuilt only once the day's last train is in.
    public let waitsForTheLastTrain: Bool

    /// Whether the card's button rebuilds it now, with `balance` in hand.
    public func canRebuild(balance: Money) -> Bool {
        rebuild != nil && !waitsForTheLastTrain && shortfallText(balance: balance, in: .english) == nil
    }

    /// The button on the line's panel.
    public static func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Rebuild as real", "照真實改建")
    }

    /// The card's text: what changes, what it costs and what comes down;
    /// or why it cannot be done.
    public func summaryText(in language: DisplayLanguage) -> String {
        if let problem { return problem }
        let cost = price?.moneyText ?? ""
        let length = relaid.map { "\($0)" } ?? ""
        var text = language.text(
            "\(station)'s \(length) m of track are laid again level, with a passing track beside each platform, and the express trains run again, passing the stations they pass in real life and overtaking at \(station). For \(cost).",
            "\(station)前後 \(length) 公尺的軌道重鋪成平的，兩側各加一股待避線；直達車照真實只停幾站、在\(station)越過普通車。\(cost)。"
        )
        if waitsForTheLastTrain {
            text += language.text(
                " The line's timetable changes with it: rebuild after the day's last train is in.",
                "班次會跟著換成有直達車的時刻表：請在今天末班車收班後改建。"
            )
        }
        if !demolished.isEmpty {
            let names = demolished.joined(separator: language.text(", ", "、"))
            text += language.text(" Comes down: \(names).", "要拆：\(names)。")
        }
        return text
    }

    /// Why the company cannot pay for it now, or `nil`.
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let price, balance < price else { return nil }
        return language.text(
            "Not enough money: it costs \(price.moneyText).",
            "資金不足：需要 \(price.moneyText)。"
        )
    }
}

extension GameSession {
    /// The selected line's rebuild as real (decision 605), laid out and
    /// priced; `nil` when it has nothing to rebuild: a line not bought,
    /// bought as real already, or off a real-world map.
    public var selectedLineRealRebuildOffer: RealLineRebuildOffer? {
        guard let line = selectedLine else { return nil }
        return realRebuildOffer(for: line.id)
    }

    /// Whether line `id` has a rebuild as real to offer: the panel's
    /// button shows for it. Cheap: nothing is laid or priced.
    public func rebuildsAsReal(_ id: LineID) -> Bool {
        realRebuildTarget(for: id) != nil
    }

    /// What a rebuild of line `id` starts from: the line, the real line's
    /// name, its overtaking station, the real timetable's runs and which
    /// of them carry no riders; `nil` for nothing to rebuild.
    private func realRebuildTarget(for id: LineID)
        -> (line: ServiceLine, realLine: String, station: Station, runs: [LineRun], positioning: Set<RealLineRunKey>)?
    {
        guard let railways, RealWorldFrame(world: world) != nil, let line = world.line(id: id),
              let bought = world.acquisitions.first(where: { $0.line == id }),
              let urban = RealBranchLine.urbanLines.first(where: { "\(RealBranchLine.dataSystem(of: $0.system)):\($0.network)" == bought.realLine }),
              let name = RealBranchLine.overtakeStations(system: urban.system, network: urban.network).first,
              let station = realOvertakeStation(name, of: line, system: urban.system, railways: railways),
              world.trackPlatforms(of: station.id).count == 2
        else { return nil }
        // The real timetable, as a line bought now runs it.
        let candidates = [urban.shares.flatMap { RealBranchLine.metroRuns(of: bought.realLine, after: $0, in: railways) }, railways.metroRuns[bought.realLine]]
        guard let real = candidates.compactMap(\.self).first(where: { $0.stops.count == line.stops.count }),
              real.runs.contains(where: { !$0.passes.isEmpty }) else { return nil }
        let all = real.runs.map { $0.lineRun(stops: real.stops, reversed: true) }
        let positioning = Set(zip(real.runs, all).filter { $0.0.positioning || $0.0.train == "回送" }.map { RealLineRunKey($0.1) })
        // As the purchase: with its depot laid, the line's own empty runs
        // take the trains in and out, not the timetable's positioning runs
        // (decision 479), so a line that runs none of them gets none.
        let keeps = line.runs.contains { positioning.contains(RealLineRunKey($0)) }
        let runs = keeps ? all : all.filter { !positioning.contains(RealLineRunKey($0)) }
        return (line, bought.realLine, station, runs, positioning)
    }

    /// Line `id`'s rebuild as real, laid out on a copy of the world and
    /// priced, or `nil` for nothing to rebuild.
    public func realRebuildOffer(for id: LineID) -> RealLineRebuildOffer? {
        guard let (line, realLine, station, runs, positioning) = realRebuildTarget(for: id) else { return nil }
        let waits = !RealLineDepotAddition.isAtRest(line, runs: runs, positioning: positioning, in: world)
        func refused(_ problem: String) -> RealLineRebuildOffer {
            RealLineRebuildOffer(
                line: id, station: station.name, rebuild: nil, price: nil, relaid: nil, demolished: [],
                problem: language.text("\(station.name) cannot be rebuilt: ", "\(station.name)改建不了：") + problem, waitsForTheLastTrain: waits
            )
        }
        // Where a run starts or ends at the station, the purchase's
        // turn-back crossovers either side (decision 556).
        let stop = line.stops.firstIndex(of: station.id)
        let turns = zip(runs, runs.indices).contains { run, _ in
            !positioning.contains(RealLineRunKey(run)) && (run.from == stop || run.to == stop)
        }
        let laid: (rebuild: RealLineRebuild, relaid: Double)
        switch realRebuildLayout(line: line, realLine: realLine, station: station, runs: runs, crossovers: turns) {
        case .success(let layout): laid = layout
        case .failure(let problem): return refused(problem.text)
        }
        let rebuild = laid.rebuild

        // GameCore's answer and the price, on a funded copy, with the
        // line's trains at rest: the runs are set only while none is out.
        var probe = world.pricingCopy()
        if waits { probe = RealLineDepotAddition.atRest(probe, line: id) }
        let opening = probe.economy.balance
        let standing = probe.placedBuildings
        var step = RealLineRebuildStep.lifting
        do throws(GameError) {
            try build(rebuild, in: &probe, step: &step)
            let gone = standing.filter { building in !probe.placedBuildings.contains { $0.id == building.id } }
            return RealLineRebuildOffer(
                line: id, station: station.name, rebuild: rebuild, price: opening - probe.economy.balance,
                relaid: Int((laid.relaid / RealLineAcquisition.metre).rounded()),
                demolished: gone.map { $0.kind.title(in: language) }, problem: nil, waitsForTheLastTrain: waits
            )
        } catch {
            return refused(step.text(in: language) + error.playerMessage(in: language))
        }
    }

    /// The line's stop nearest the real station `name`, within reach of it.
    private func realOvertakeStation(_ name: String, of line: ServiceLine, system: String, railways: RealRailways) -> Station? {
        guard let frame = RealWorldFrame(world: world),
              let real = RealLineLaying.realPoint(of: name, system: system, railways: railways, frame: frame) else { return nil }
        let stops = line.stops.compactMap(world.station(id:))
        guard let nearest = stops.min(by: { (WorldVector($0.location) - real).length < (WorldVector($1.location) - real).length }),
              (WorldVector(nearest.location) - real).length < RealLineAcquisition.stationReach else { return nil }
        return nearest
    }

    /// Rebuilds the line of `offer` as real (decision 605), paying for it.
    /// `false`, with the message saying why, where it cannot be.
    ///
    /// The offer is taken again from the world as it is now, as a depot's
    /// is (``addRealDepot(_:)``): once the first train is due it waits for
    /// the last one, and where the rebuild no longer lays or prices as the
    /// card said, the player is asked to look again.
    @discardableResult
    public func rebuildRealLine(_ offer: RealLineRebuildOffer) -> Bool {
        let current = realRebuildOffer(for: offer.line)
        guard let current, let rebuild = current.rebuild, !current.waitsForTheLastTrain, rebuild == offer.rebuild else {
            let changed = current?.problem == nil && current?.waitsForTheLastTrain == false && offer.rebuild != nil
            message = StatusMessage(
                kind: .failure,
                text: changed
                    ? language.text(
                        "The line has changed since the card opened: open it again for its price now.",
                        "這條線在打開後變了，請重新打開看現在的價格。"
                    )
                    : current.map { $0.problem ?? $0.summaryText(in: language) }
                    ?? language.text("This line has nothing to rebuild.", "這條線沒有要改建的。")
            )
            return false
        }
        let station = offer.station
        return perform(.rebuildRealLine(rebuild)) { _, _, _ in
            language.text(
                "Rebuilt: \(station) has its passing tracks and the express trains run.",
                "已改建：\(station)有待避線，直達車開始行駛。"
            )
        } != nil
    }

    /// Builds `rebuild` in `world`: the station's stretch taken up and laid
    /// again, its platforms, the line's route through it, then its new runs,
    /// its trains still out taken off their runs and put back; all of it
    /// or, throwing, none.
    func build(_ rebuild: RealLineRebuild, in world: inout GameWorld) throws(GameError) {
        var step = RealLineRebuildStep.lifting
        try build(rebuild, in: &world, step: &step)
    }

    /// ``build(_:in:)``, `step` saying what it was building when it threw.
    func build(_ rebuild: RealLineRebuild, in world: inout GameWorld, step: inout RealLineRebuildStep) throws(GameError) {
        let heights = heights
        var reached = RealLineRebuildStep.lifting
        defer { step = reached }
        try world.editTrackAsOne { (world: inout GameWorld) throws(GameError) in
            guard let line = world.line(id: rebuild.line) else { throw .unknownLine(rebuild.line) }
            var lifted: [(TrainID, Int?)] = []
            for id in line.trains where world.train(id: id)?.execution != nil {
                lifted.append((id, world.assignedPattern(of: id)))
                try world.unassignTrain(id)
                try world.stopTrainService(id)
            }
            // A train taken off its run where it was, between the ends,
            // would stand there and take the next run from that station,
            // one a line bought now has no train for: one more train sent
            // to the end, which then had no room for it (decision 605
            // continued). It goes to a free track of a depot instead, as
            // the purchase leaves the trains it has no run for.
            try Self.berthInDepots(lifted.map(\.0), of: line, in: &world)
            reached = .takingUp
            for platform in rebuild.platforms {
                try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
            }
            for edge in rebuild.edges {
                try world.removeTrackEdge(.edge(edge))
            }
            for node in rebuild.nodes {
                try world.removeTrackNode(.node(node))
            }
            var nodes: [[TrackNodeID]] = [rebuild.anchors.map(TrackNodeID.node)]
            var edges: [[TrackEdgeID]] = [[]]
            for (index, piece) in rebuild.pieces.enumerated() {
                reached = RealLineRebuildStep.laying(piece: index)
                try world.readGround(under: piece.ground, from: heights)
                var ids: [TrackNodeID] = []
                for (index, position) in piece.nodes.enumerated() {
                    if index == 0, let start = piece.start {
                        guard nodes.indices.contains(start.piece), nodes[start.piece].indices.contains(start.node) else { throw .invalidTrackGeometry }
                        ids.append(nodes[start.piece][start.node])
                    } else if index == piece.nodes.count - 1, let end = piece.end {
                        guard nodes.indices.contains(end.piece), nodes[end.piece].indices.contains(end.node) else { throw .invalidTrackGeometry }
                        ids.append(nodes[end.piece][end.node])
                    } else {
                        ids.append(try world.buildTrackNode(at: position))
                    }
                }
                edges.append(try world.buildTrackEdges(piece.curves.enumerated().map { index, curve in
                    TrackEdgePlan(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure)
                }))
                nodes.append(ids)
            }
            // A platform on each track and each loop, as the purchase lays
            // them (``RealLineLaying/build(_:in:recording:)``).
            reached = .platforms
            var built: [TrackPlatform] = []
            for at in rebuild.berths {
                guard rebuild.pieces.indices.contains(at.piece - 1), edges.indices.contains(at.piece) else { throw .invalidTrackGeometry }
                let distances = rebuild.pieces[at.piece - 1].distances, laid = edges[at.piece]
                guard !laid.isEmpty, distances.count == laid.count + 1 else { throw .invalidTrackGeometry }
                let index = max(0, min(laid.count - 1, distances.lastIndex { $0 <= at.distance } ?? 0))
                let a = distances[index], b = distances[index + 1]
                let edgeLength = world.network.edge(laid[index])?.length ?? 0
                var offset = Int64(((at.distance - a) / max(b - a, 1) * Double(edgeLength)).rounded())
                if offset + rebuild.platformLength > edgeLength {
                    offset = max(0, edgeLength - rebuild.platformLength - Int64(RealLineAcquisition.metre))
                }
                try world.addTrackPlatform(rebuild.station, on: laid[index], from: offset, to: offset + rebuild.platformLength)
                built.append(TrackPlatform(station: rebuild.station, edge: laid[index], start: offset, end: offset + rebuild.platformLength))
            }
            // The line's route to each of the station's platforms taken up
            // goes to the one laid in its place (decision 323).
            func moved(_ routes: [LineRoutePreference]) -> [LineRoutePreference] {
                routes.map { route in
                    guard let index = rebuild.platforms.firstIndex(of: route.platform), built.indices.contains(index) else { return route }
                    return LineRoutePreference(from: route.from, to: route.to, platform: built[index])
                }
            }
            if let current = world.line(id: rebuild.line) {
                try world.setLineRoutePreferences(rebuild.line, to: moved(current.routePreferences))
                for (pattern, service) in current.patterns.enumerated() {
                    try world.setLineRoutePreferences(rebuild.line, to: moved(service.routePreferences), pattern: pattern)
                }
            }
            reached = .timetable
            try world.setLineRuns(line.id, to: rebuild.runs)
            for (id, pattern) in lifted {
                try world.assignTrain(id, to: line.id, pattern: pattern)
            }
        }
    }
}

extension GameSession {
    /// Puts each of `trains` (off their runs, not standing in one of
    /// `line`'s depots) on a free track of the depot nearest it, as the
    /// purchase places a train there (``RealLineLaying``): facing up the
    /// track, standing still at its far end. A train that fits no free
    /// track stays where it is.
    static func berthInDepots(_ trains: [TrainID], of line: ServiceLine, in world: inout GameWorld) throws(GameError) {
        for id in trains {
            guard let train = world.train(id: id), case .onEdge(let traversal, _)? = train.position,
                  Set(world.stationsStoppedAt(by: id)).isDisjoint(with: line.depots),
                  let at = world.network.edge(traversal.edge).flatMap({ world.network.node($0.from) })?.position
            else { continue }
            let standing = world
            func distance(_ depot: StationID) -> Int64 {
                guard let point = standing.station(id: depot)?.location else { return .max }
                let dx = point.x - at.x, dy = point.y - at.y
                return dx * dx + dy * dy
            }
            // The edges a train stands or reaches back along.
            let taken = Set(standing.trains.flatMap { other -> [TrackEdgeID] in
                guard case .onEdge(let traversal, _)? = other.position else { return [] }
                return [traversal.edge] + other.trailEdges
            })
            let length = train.length
            let berth = line.depots.sorted { (distance($0), $0.rawValue) < (distance($1), $1.rawValue) }
                .flatMap { standing.trackPlatforms(of: $0) }
                .first { platform in
                    !taken.contains(platform.edge) && platform.start + length <= min(platform.end, standing.network.edge(platform.edge)?.length ?? 0)
                }
            guard let berth else { continue }
            try world.unplaceTrain(id)
            let offset = berth.start + length
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: berth.edge, direction: .forward), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 512)
        }
    }
}

/// What a rebuild was doing when GameCore refused it, for the card.
enum RealLineRebuildStep: Equatable {
    case lifting
    case takingUp
    /// The `piece`th of ``RealLineRebuild/pieces``: the first track, the
    /// second, the loops, the crossovers.
    case laying(piece: Int)
    case platforms
    case timetable

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .lifting, .timetable: ""
        case .takingUp: language.text("taking up the old track: ", "拆舊軌道時：")
        case .laying(let piece) where piece < 2: language.text("the main track laid again: ", "重鋪的正線：")
        case .laying(let piece) where piece < 4: language.text("the passing track beside the platform: ", "月台外側的待避線：")
        case .laying: language.text("the crossover: ", "折返渡線：")
        case .platforms: language.text("the platforms: ", "月台：")
        }
    }
}

/// A run told apart from the others of its line: where it starts and
/// ends, when, and on which days (decision 605: which runs carry no
/// riders, which the real timetable says and GameCore does not keep).
struct RealLineRunKey: Hashable {
    let from: Int
    let to: Int
    let departure: Int64
    let arrival: Int64
    let days: Int

    init(_ run: LineRun) {
        from = run.from
        to = run.to
        departure = run.times.first?.departure ?? 0
        arrival = run.times.last?.arrival ?? 0
        days = run.days
    }
}

/// Why a rebuild could not be laid out.
struct RealLineRebuildProblem: Error {
    let text: String
}

extension GameSession {
    /// Lays out the rebuild of `line` at `station` (decision 605): the
    /// stretch of both tracks reaching past where the purchase puts the
    /// station's crossovers, as the purchase lays it now.
    func realRebuildLayout(
        line: ServiceLine, realLine: String, station: Station, runs: [LineRun], crossovers: Bool
    ) -> Result<(rebuild: RealLineRebuild, relaid: Double), RealLineRebuildProblem> {
        let world = world
        func problem(_ english: String, _ chinese: String) -> Result<(rebuild: RealLineRebuild, relaid: Double), RealLineRebuildProblem> {
            .failure(RealLineRebuildProblem(text: language.text(english, chinese)))
        }
        let changed = problem(
            "its track there is no longer as it was bought.",
            "那裡的軌道已經和收購時不一樣了。"
        )
        // The two tracks as the purchase laid them: each a run of its
        // edges in the order laid (decision 528 keeps them, an edge split
        // since in its place).
        guard let track = world.acquisition(of: realLine)?.track else { return changed }
        var chains: [[TrackEdge]] = []
        for id in track {
            guard let edge = world.network.edge(id) else { continue }
            if let last = chains.last?.last, last.to == edge.from {
                chains[chains.count - 1].append(edge)
            } else {
                chains.append([edge])
            }
        }
        let platforms = world.trackPlatforms(of: station.id)
        guard platforms.count == 2,
              let firstChain = chains.firstIndex(where: { $0.contains { $0.id == platforms[0].edge } }),
              let secondChain = chains.firstIndex(where: { $0.contains { $0.id == platforms[1].edge } }),
              firstChain != secondChain
        else { return changed }
        // The first track is the one laid first.
        let (mainIndex, besideIndex) = firstChain < secondChain ? (firstChain, secondChain) : (secondChain, firstChain)
        let ordered = firstChain < secondChain ? platforms : [platforms[1], platforms[0]]
        let main = chains[mainIndex], beside = chains[besideIndex]
        let mainNodes = [main[0].from] + main.map(\.to), besideNodes = [beside[0].from] + beside.map(\.to)
        var along: [Double] = [0]
        for edge in main {
            along.append(along[along.count - 1] + Double(edge.length))
        }
        guard let platformEdge = main.firstIndex(where: { $0.id == ordered[0].edge }) else { return changed }
        let middle = along[platformEdge] + Double(ordered[0].start + ordered[0].end) / 2
        let length = Double(ordered[0].end - ordered[0].start), half = length / 2

        // How far either way the purchase lays the station's stretch: its
        // loops' reach, then the crossovers two short edges and a ramp
        // beyond, and a short edge past them.
        let layout = RealLineLayout.metro
        let reach = layout.loopReach, gap = RealWorldDemo.shortestEdge, ramp = HighSpeedDemo.rampLength
        let need = reach + 2 * gap + ramp + gap
        guard let low = along.lastIndex(where: { $0 <= middle - need }), let high = along.firstIndex(where: { $0 >= middle + need }),
              low > 0, high < mainNodes.count - 1
        else {
            return problem("there is no room along the line for its passing tracks.", "線上放不下待避線。")
        }
        guard let lowNode = world.network.node(mainNodes[low]), let highNode = world.network.node(mainNodes[high]) else { return changed }
        // The second track's nodes beside those two, a double track's
        // spacing out.
        func besideNode(of node: TrackNode) -> Int? {
            besideNodes.indices.min { a, b in
                let pa = world.network.node(besideNodes[a]).map { (WorldVector($0.position.plan) - WorldVector(node.position.plan)).length } ?? .infinity
                let pb = world.network.node(besideNodes[b]).map { (WorldVector($0.position.plan) - WorldVector(node.position.plan)).length } ?? .infinity
                return pa < pb
            }
        }
        guard let lowBeside = besideNode(of: lowNode), let highBeside = besideNode(of: highNode), lowBeside < highBeside,
              let lowBesideNode = world.network.node(besideNodes[lowBeside]), let highBesideNode = world.network.node(besideNodes[highBeside])
        else { return changed }
        let spacing = HighSpeedDemo.trackOffset
        for (a, b) in [(lowNode, lowBesideNode), (highNode, highBesideNode)] {
            let apart = (WorldVector(a.position.plan) - WorldVector(b.position.plan)).length
            guard abs(apart - spacing) < 0.5 * RealLineAcquisition.metre, a.position.z == b.position.z else { return changed }
        }
        // What is taken up: both tracks between those nodes, and any track
        // between them (the old crossovers); nothing else may join there.
        let innerNodes = Array(mainNodes[(low + 1)..<high] + besideNodes[(lowBeside + 1)..<highBeside])
        let inner = Set(innerNodes)
        let chainEdges = Set(main[low..<high].map(\.id) + beside[lowBeside..<highBeside].map(\.id))
        var removed = Array(main[low..<high].map(\.id) + beside[lowBeside..<highBeside].map(\.id))
        for edge in world.network.edges where !chainEdges.contains(edge.id) && (inner.contains(edge.from) || inner.contains(edge.to)) {
            guard inner.contains(edge.from), inner.contains(edge.to) else {
                return problem("other track joins the line there.", "那裡有別的軌道接在線上。")
            }
            removed.append(edge.id)
        }
        guard world.network.platforms.allSatisfy({ !removed.contains($0.edge) || $0.station == station.id }) else {
            return problem("another station's platform stands there.", "那裡有別站的月台。")
        }

        // The first track's way between those nodes, as laid.
        var points: [WorldVector] = []
        for edge in main[low..<high] {
            guard let geometry = world.trackGeometry(of: edge.id) else { return changed }
            let step = Int64(8 * RealLineAcquisition.metre)
            var distance: Int64 = points.isEmpty ? 0 : step
            while distance < geometry.length {
                points.append(WorldVector(geometry.location(at: distance).position.plan))
                distance += step
            }
            points.append(WorldVector(geometry.location(at: geometry.length).position.plan))
        }
        let path = WorldPath(points)
        func way(_ edge: TrackEdge, at end: Bool) -> WorldVector? {
            guard let geometry = world.trackGeometry(of: edge.id) else { return nil }
            let direction = geometry.location(at: end ? geometry.length : 0).direction
            return WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit
        }
        guard let startWay = way(main[low], at: false), let endWay = way(main[high - 1], at: true) else { return changed }
        let at = path.nearest(WorldVector(lowNode.position.plan)).along + (middle - along[low]) * path.length / (along[high] - along[low])
        // The second track's side: the purchase's on the left.
        let side: Double = (WorldVector(lowBesideNode.position.plan) - WorldVector(lowNode.position.plan)).dot(startWay.normal) >= 0 ? 1 : -1
        let besideOffset = side * spacing

        // Level a loop's reach either way, at the platforms' height, and
        // from there to the kept track's height at each end within the
        // line's grade, near the ground.
        guard let height = world.trackGeometry(of: ordered[0].edge)?.height(at: ordered[0].start) else { return changed }
        let planning = world
        func ground(_ point: WorldVector) -> Double { Double(planning.groundHeight(at: point.plan) ?? 0) }
        func water(_ point: WorldVector) -> Bool {
            guard planning.ground.isMapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }
        let levelled = (at - reach)...(at + reach)
        guard let rise = TrackRise(
            path: path, ground: ground, water: water,
            levels: [
                TrackRise.Level(0...0, at: Double(lowNode.position.z)), TrackRise.Level(levelled, at: Double(height)),
                TrackRise.Level(path.length...path.length, at: Double(highNode.position.z)),
            ],
            grade: realLine == "tymc:A" ? 0.038 : RealWorldDemo.rulingGrade, slack: [0]
        ) else {
            return problem("the track cannot be laid level there within the steepest grade.", "那裡的高低差太大，鋪不成平的。")
        }
        let turnbacks: [(low: Double, high: Double)] = crossovers
            ? [(at - reach - 2 * gap - ramp, at - reach - 2 * gap), (at + reach + 2 * gap, at + reach + 2 * gap + ramp)] : []
        let zone = (at - half)...(at + half)
        let mainPlan = RealWorldDemo.TrackPlan(
            path, forced: [0, path.length, at - reach, at + reach] + turnbacks.flatMap { [$0.low, $0.high] }, avoiding: [zone],
            close: [levelled], start: (lowNode.position.plan, startWay), end: (highNode.position.plan, endWay), rise: rise, structure: .automatic
        )
        guard mainPlan.heights.first == lowNode.position.z, mainPlan.heights.last == highNode.position.z else { return changed }
        let besidePlan = RealWorldDemo.TrackPlan(
            beside: mainPlan, at: Array(mainPlan.distances.indices), offsets: mainPlan.distances.map { _ in besideOffset }, following: true
        )
        guard let first = besidePlan.nodes.first, let last = besidePlan.nodes.last,
              (WorldVector(first.point) - WorldVector(lowBesideNode.position.plan)).length < 0.5 * RealLineAcquisition.metre,
              (WorldVector(last.point) - WorldVector(highBesideNode.position.plan)).length < 0.5 * RealLineAcquisition.metre
        else { return changed }

        var plans: [(plan: RealWorldDemo.TrackPlan, start: RealLineAcquisition.NodeAt, end: RealLineAcquisition.NodeAt)] = [
            (mainPlan, .init(piece: 0, node: 0), .init(piece: 0, node: 1)),
            (besidePlan, .init(piece: 0, node: 2), .init(piece: 0, node: 3)),
        ]
        var berths = [
            RealLineAcquisition.PieceAt(piece: 1, distance: zone.lowerBound), RealLineAcquisition.PieceAt(piece: 2, distance: zone.lowerBound),
        ]
        // A loop outside each track (``RealLineLaying``'s): the first
        // track's on the side away from the second, the second's beyond it.
        let node = { (distance: Double) in mainPlan.distances.firstIndex { abs($0 - distance) < 1 } }
        guard let a = node(at - reach), let b = node(at + reach) else { return changed }
        for (piece, base) in [(1, 0.0), (2, besideOffset)] {
            let offset = (piece == 1 ? -side : side) * layout.loopOffset
            let loopPath = path.offset(from: at - reach, to: at + reach, by: offset, ramp: layout.ramp(level: 1), from: base)
            func shifted(_ index: Int) -> (point: PlanPoint, direction: WorldVector) {
                let node = mainPlan.nodes[index]
                return ((WorldVector(node.point) + node.direction.unit.normal * base).plan, node.direction)
            }
            guard let loopRise = TrackRise(path: loopPath, ground: ground, water: water, levels: [TrackRise.Level(0...loopPath.length, at: Double(height))])
            else { return changed }
            let middle = loopPath.length / 2, loopHalf = max(half, Double(RealWorldDemo.platformLength) / 2)
            let loopZone = (middle - loopHalf)...(middle + loopHalf)
            plans.append((
                RealWorldDemo.TrackPlan(
                    loopPath, forced: [0, loopPath.length], avoiding: [loopZone], close: [0...loopPath.length],
                    start: shifted(a), end: shifted(b), rise: loopRise, structure: .automatic
                ),
                .init(piece: piece, node: a), .init(piece: piece, node: b)
            ))
            berths.append(RealLineAcquisition.PieceAt(piece: plans.count, distance: middle - half))
        }
        // The crossovers, from the second track nearer the line's first
        // end to the first further on, as the purchase lays them where the
        // trains keep right (decisions 556 and 564).
        for turnback in turnbacks {
            guard let a = node(turnback.low), let b = node(turnback.high) else { return changed }
            plans.append((
                RealWorldDemo.TrackPlan(beside: mainPlan, at: [a, b], offsets: [besideOffset, 0]),
                .init(piece: 2, node: a), .init(piece: 1, node: b)
            ))
        }
        let pieces = plans.map { entry in
            let plan = entry.plan
            let nodes = plan.nodes.indices.map { WorldCoordinate(x: plan.nodes[$0].point.x, y: plan.nodes[$0].point.y, z: plan.heights[$0]) }
            let ground = plan.curves.indices.flatMap { index -> [PlanPoint] in
                let surveyed = TrackGeometry(from: nodes[index], to: nodes[index + 1], curve: plan.curves[index]).map(NetworkBuilding.surveyedPoints(of:)) ?? []
                return [nodes[index].plan, nodes[index + 1].plan] + surveyed
            }
            return RealLineAcquisition.Piece(
                nodes: nodes, start: entry.start, end: entry.end, curves: plan.curves, distances: plan.distances, structure: plan.structure,
                together: true, ground: ground
            )
        }
        func number(_ id: TrackNodeID) -> Int? { if case .node(let number) = id { number } else { nil } }
        func number(_ id: TrackEdgeID) -> Int? { if case .edge(let number) = id { number } else { nil } }
        let rebuild = RealLineRebuild(
            line: line.id, realLine: realLine, station: station.id, platforms: ordered, edges: removed.compactMap(number), nodes: innerNodes.compactMap(number),
            anchors: [lowNode.id, highNode.id, lowBesideNode.id, highBesideNode.id].compactMap(number), pieces: pieces, berths: berths,
            platformLength: Int64(length), runs: runs
        )
        return .success((rebuild, along[high] - along[low]))
    }
}
