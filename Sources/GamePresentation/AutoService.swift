import GameCore

// Simple rules' service (ARCHITECTURE decision 264, CORE_LOOP §3.1, after
// decision 258): a new line gets its first train at once, "Add a Train"
// puts one more on a line in one tap, and when a line's single track is
// to carry more trains than it has places to pass, a passing loop
// (decision 204) goes in its longest single-track leg and becomes a stop
// of every line through it, so two trains meet there instead of standing
// nose to nose. Each is one command (``PlayerCommand/autoService(_:)``),
// so one Undo takes all of it back, and none is a new GameCore command.
// Realistic rules ask the player, as before.
//
// The reference has nothing to port: `Ci/`'s lines come with their trains
// (`spawnTrains`) and its track is never single. Mini Metro hands out a
// train with each new line; A-Train runs a line nobody set up with a
// train stopping 5 minutes at each station (CORE_LOOP §6.1). Native.

/// What one tap of simple rules' service does, worked out in the session
/// before it runs: a new line, or one already there; the passing loops
/// it needs; and the trains to put on it.
public struct AutoService: Hashable, Sendable, Codable {
    /// A line made first, as ``PlayerCommand/Edit/createLine(name:stops:targets:)``.
    public struct NewLine: Hashable, Sendable, Codable {
        public let name: String
        public let stops: [StationID]
        public let targets: TargetHeadways?
    }

    /// The new line, or `nil` for ``line``.
    public let newLine: NewLine?
    /// The line the trains go on when ``newLine`` is `nil`.
    public let line: LineID?
    /// The passing loops built first, each becoming a stop of the lines
    /// through it.
    public let loops: [PassingLoopPlan]
    /// The trains bought, placed and assigned, and their cars.
    public let trains: Int
    public let cars: Int
    /// The language the trains are named in.
    public let language: DisplayLanguage

    /// The most cars a train it buys has: four, the first line's in the
    /// balance tests (decision 137), when the platforms are long enough.
    public static let maximumCars = 4

    /// The shortest single-track leg a new line gets a passing loop on
    /// before its first train: 2 km. A shorter leg's trains are seldom
    /// between the stations, so the loop would be money spent for little;
    /// "Add a Train" builds one there when it is asked for.
    public static let shortestLoopLeg: Int64 = 2_000 * WorldCoordinate.unitsPerMetre
}

/// A line's single track carrying more trains than it has places for them
/// to pass (decision 264): where a passing loop would go, best first, and
/// the other lines over the same single track.
public struct PassingPlaceShortfall: Hashable, Sendable {
    /// A single-track leg of the line, from stop `from` to stop `to`
    /// (indices of its stops), over `edges`, `distance` long.
    public struct Leg: Hashable, Sendable {
        public let from: Int
        public let to: Int
        public let edges: [TrackEdgeID]
        public let distance: Int64
    }

    public let line: LineID
    /// The legs a loop would go on, best first: those another line shares,
    /// then the longest.
    public let legs: [Leg]
    /// The other lines with trains over the line's single track, ascending.
    public let others: [LineID]
}

extension GameWorld {
    /// Line `id`'s shortfall of places to pass when it runs `trains` of its
    /// own with room for `readyFor` in all (decision 264), or `nil` when it
    /// has places enough, is a ring or cannot be driven.
    ///
    /// A line's single-track legs carry its own trains and those of every
    /// line that runs over the same track. Trains on single track pass
    /// only at a stop with a track each way: `n` trains need `n − 1` such
    /// stops between the line's ends.
    public func passingPlaceShortfall(of id: LineID, trains wanted: Int, readyFor: Int = 0) -> PassingPlaceShortfall? {
        var edges: [LineID: Set<TrackEdgeID>] = [:]
        return passingPlaceShortfall(of: id, trains: wanted, readyFor: readyFor, edges: &edges)
    }

    /// The edges each line with trains runs over, worked out once for every
    /// line asked about.
    private func journeyEdges(of id: LineID, in edges: inout [LineID: Set<TrackEdgeID>]) -> Set<TrackEdgeID> {
        if let known = edges[id] { return known }
        let found = lineJourney(id).map { Set(Self.legEdges(of: $0).flatMap(\.edges)) } ?? []
        edges[id] = found
        return found
    }

    private func passingPlaceShortfall(
        of id: LineID, trains wanted: Int, readyFor: Int, edges cache: inout [LineID: Set<TrackEdgeID>]
    ) -> PassingPlaceShortfall? {
        guard let line = line(id: id), !line.isRing, let journey = lineJourney(id), let tracks = lineTrackCounts(id) else { return nil }
        // The single-track legs out, each with its edges.
        let single = Self.legEdges(of: journey).filter { $0.leg.to > $0.leg.from && $0.leg.from < tracks.count && tracks[$0.leg.from] == 1 }
        guard !single.isEmpty else { return nil }
        let singleEdges = Set(single.flatMap(\.edges))
        // The other lines over the same single track, and their trains.
        var shared = Set<TrackEdgeID>()
        var others: [LineID] = []
        var trains = wanted
        for other in lines where other.id != id && !other.assignedTrains.isEmpty {
            let edges = journeyEdges(of: other.id, in: &cache).intersection(singleEdges)
            guard !edges.isEmpty else { continue }
            shared.formUnion(edges)
            others.append(other.id)
            trains += other.assignedTrains.count
        }
        // The stops between the ends with a track each way.
        let passing = line.stops.dropFirst().dropLast().filter { trackPlatforms(of: $0).count >= 2 }.count
        guard max(trains, readyFor) - 1 > passing else { return nil }
        let ordered = single.sorted { a, b in
            let aShared = a.edges.contains { shared.contains($0) }
            let bShared = b.edges.contains { shared.contains($0) }
            if aShared != bShared { return aShared }
            return a.leg.path.distance > b.leg.path.distance
        }
        return PassingPlaceShortfall(
            line: id,
            legs: ordered.map { .init(from: $0.leg.from, to: $0.leg.to, edges: $0.edges, distance: $0.leg.path.distance) },
            others: others.sorted()
        )
    }

    /// Line `id`'s shortfall with the trains it has, when another line's
    /// trains share its single track (decision 264): the trains of the two
    /// cannot pass, so one turns back short (decision 255) or they stand.
    /// `nil` when it has places enough or shares no single track.
    public func sharedSingleTrackShortfall(of id: LineID) -> PassingPlaceShortfall? {
        var edges: [LineID: Set<TrackEdgeID>] = [:]
        return sharedSingleTrackShortfall(of: id, edges: &edges)
    }

    private func sharedSingleTrackShortfall(of id: LineID, edges: inout [LineID: Set<TrackEdgeID>]) -> PassingPlaceShortfall? {
        guard let line = line(id: id), !line.assignedTrains.isEmpty,
              let shortfall = passingPlaceShortfall(of: id, trains: line.assignedTrains.count, readyFor: 0, edges: &edges),
              !shortfall.others.isEmpty
        else { return nil }
        return shortfall
    }

    /// The first line, by ID, with a ``sharedSingleTrackShortfall(of:)``:
    /// what the station master warns of. Each line's journey is driven once.
    public func firstLineWithoutPlaceToPass() -> ServiceLine? {
        var edges: [LineID: Set<TrackEdgeID>] = [:]
        // Only lines that share a single-track edge with another line's
        // trains can fall short this way: most networks have none.
        let running = lines.filter { !$0.assignedTrains.isEmpty }
        guard running.count >= 2 else { return nil }
        return running.sorted { $0.id < $1.id }.first { sharedSingleTrackShortfall(of: $0.id, edges: &edges) != nil }
    }

    /// Each leg of `journey` with the edges it runs over, the one it
    /// leaves from first: a path lists only the edges it moves on to.
    static func legEdges(of journey: LineJourney) -> [(leg: LineLeg, edges: [TrackEdgeID])] {
        guard case .onEdge(let start, _) = journey.start else { return [] }
        var current = start.edge
        return journey.legs.map { leg in
            var seen: Set<TrackEdgeID> = [current]
            let edges = [current] + leg.path.traversals.map(\.edge).filter { seen.insert($0).inserted }
            current = leg.path.traversals.last?.edge ?? current
            return (leg, edges)
        }
    }
}

/// What opening the drafted line does under simple rules (decision 264):
/// its price, and whether a train and a passing loop come with it.
public struct LineOpeningPreview: Equatable, Sendable {
    public let cost: Money
    public let train: Bool
    public let loop: Bool

    /// "With a train and a passing loop · $ 1,234,000", for the line panel
    /// and the map's ✓.
    public func text(in language: DisplayLanguage) -> String {
        let what = switch (train, loop) {
        case (true, true): language.text("With a train and a passing loop", "含一列車與一處待避線")
        case (true, false): language.text("With a train", "含一列車")
        case (false, true): language.text("With a passing loop", "含一處待避線")
        case (false, false): language.text("No train yet", "還沒有列車")
        }
        return what + " · " + cost.moneyText
    }
}

struct PassingShortfallMemo {
    struct Key: Equatable {
        let line: LineID
        let revision: Int
    }

    let key: Key
    let shortfall: PassingPlaceShortfall?
}

struct LineOpeningMemo {
    struct Key: Equatable {
        let stops: [StationID]
        let worldRevision: Int
    }

    let key: Key
    let preview: LineOpeningPreview?
}

extension GameSession {
    /// Whether new lines and "Add a Train" run themselves (decision 264):
    /// in a managed game (a company's, as every new game is) of simple rules
    /// (``NewGameRules``), outside the tutorial, which teaches buying a
    /// line's trains by hand.
    public var runsLinesForThePlayer: Bool {
        tutorial == nil && !staffsLinesByHand && world.accounts.mode == .management && NewGameRules(of: world) == .simple
    }

    /// The new line of ``createLineFromDraft()`` under simple rules, with
    /// its first train (decision 264), or `nil` when nothing would run yet:
    /// no track joins its stops.
    ///
    /// The line is made ready for a second train before its first runs:
    /// the passing loops already on its way become its stops, and when its
    /// single track still leaves no place for two trains to pass, a loop
    /// goes in now. Later it could not: GameCore never cuts track a train
    /// stands on or has reserved, and a line's train is always on its track.
    func autoServicePlan(creating name: String, stops: [StationID], targets: TargetHeadways?) -> AutoService? {
        var scratch = world
        guard let line = try? scratch.createLine(named: name, stops: stops), scratch.lineJourney(line.id) != nil else { return nil }
        var stops = stops
        for station in scratch.stations where Self.isPassingPlace(station, in: scratch) && !stops.contains(station.id) {
            guard let stop = scratch.passingLoopOffer(for: station.id).stops.first(where: { $0.line == line.id }) else { continue }
            let longer = LineStopEditing.inserting(station.id, at: stop.index, into: stops)
            if (try? scratch.setLineStops(line.id, to: longer)) != nil { stops = longer }
        }
        return AutoService(
            newLine: AutoService.NewLine(name: name, stops: stops, targets: targets), line: nil,
            loops: passingLoopsNeeded(for: line.id, trains: 1, readyFor: 2, shortestLeg: AutoService.shortestLoopLeg, in: scratch), trains: 1,
            cars: Self.autoServiceCars(for: line.id, in: scratch), language: language
        )
    }

    /// What opening the drafted line (``lineDraftStops``) would cost and
    /// bring under simple rules, as ``createLineFromDraft()`` would open it;
    /// `nil` unless the game runs its lines for the player and the draft
    /// has two stops. Worked out once for each draft and command (not at
    /// every tick).
    public var lineOpeningPreview: LineOpeningPreview? {
        guard runsLinesForThePlayer else { return nil }
        let stops = lineDraftStops
        guard stops.count >= 2 else { return nil }
        _ = world
        let key = LineOpeningMemo.Key(stops: stops, worldRevision: commandRevision)
        if let memo = lineOpeningMemo, memo.key == key { return memo.preview }
        var preview: LineOpeningPreview?
        if let plan = autoServicePlan(creating: Self.suggestedLineName(for: world, in: language), stops: stops, targets: nil).flatMap(feasible)?.plan,
           let priced = try? priced({ world throws(GameError) in try apply(plan, to: &world) }) {
            let trains = priced.result.line.map(\.trains.count) ?? 0
            preview = LineOpeningPreview(cost: priced.cost, train: trains > 0, loop: priced.result.number > 0)
        }
        lineOpeningMemo = LineOpeningMemo(key: key, preview: preview)
        return preview
    }

    /// `plan` as it can run now: whole, or without its loops when they
    /// cannot go in (a train stands on or has reserved that track, or one
    /// in the way cannot go back on its line), or `nil` when even that is
    /// refused, for the line to be made as before. `trainInTheWay`: its
    /// loops were left out because a train is on their track.
    func feasible(_ plan: AutoService) -> (plan: AutoService, trainInTheWay: Bool)? {
        var trial = world
        do throws(GameError) {
            _ = try apply(plan, to: &trial)
            return (plan, false)
        } catch {
            guard !plan.loops.isEmpty else { return nil }
            let without = AutoService(
                newLine: plan.newLine, line: plan.line, loops: [], trains: plan.trains, cars: plan.cars, language: plan.language
            )
            trial = world
            guard (try? apply(without, to: &trial)) != nil else { return nil }
            if case .trackReserved = error { return (without, true) }
            return (without, false)
        }
    }

    /// Whether `station` is a passing loop's signal station: closed to
    /// passengers, with a track each way.
    static func isPassingPlace(_ station: Station, in world: GameWorld) -> Bool {
        station.operationMode == .closed && world.trackPlatforms(of: station.id).count >= 2
    }

    /// One more train on line `id` (decision 264), with the passing loop it
    /// needs, or `nil` for a ring or a line whose journey cannot be driven.
    public func autoServicePlan(addingTrainTo id: LineID) -> AutoService? {
        guard let line = world.line(id: id), !line.isRing, world.lineJourney(id) != nil else { return nil }
        let cars = line.trains.first.flatMap { world.train(id: $0)?.cars } ?? Self.autoServiceCars(for: id, in: world)
        return AutoService(
            newLine: nil, line: id, loops: passingLoopsNeeded(for: id, trains: line.assignedTrains.count + 1, in: world), trains: 1, cars: cars,
            language: language
        )
    }

    /// Puts one more train on the selected line in one tap (decision 264):
    /// the passing loop its single track needs first, then the train,
    /// bought, placed where its trips start (or at its far end when a
    /// train waits there) and assigned, its targets set to share the round
    /// trip between its trains. One command, so one Undo.
    public func addTrainToSelectedLine() {
        guard let line = requireSelectedLine() else { return }
        guard let plan = autoServicePlan(addingTrainTo: line.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot run yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能行駛：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        // A loop cannot go in under a train (see
        // ``autoServicePlan(creating:stops:targets:)``): say so plainly.
        var trial = world
        do throws(GameError) {
            _ = try apply(plan, to: &trial)
        } catch {
            if case .trackReserved = error, !plan.loops.isEmpty {
                message = StatusMessage(kind: .failure, text: language.text(
                    "\(line.name) needs a passing loop for another train, and a train is on that track now. Tap again once it has passed.",
                    "\(line.name) 要再加一列車得先加待避線，但那段單線上現在有列車。等它開過去再按一次。"
                ))
                return
            }
        }
        let balance = world.economy.balance
        let built = perform(.autoService(plan)) { outcome, _, world in
            Self.autoServiceText(plan, outcome: outcome, line: line.id, cost: Money(balance.amount - world.economy.balance.amount), in: world, language: language)
        }
        if built != nil { playSound?(.track) }
    }

    /// The selected line's shortfall of places to pass on single track it
    /// shares with another line's trains (decision 264), for its card.
    /// Worked out once for each line and command, not at every tick.
    public var selectedLinePassingShortfall: PassingPlaceShortfall? {
        guard let id = selectedLine?.id else { return nil }
        let key = PassingShortfallMemo.Key(line: id, revision: commandRevision)
        if let memo = passingShortfallMemo, memo.key == key { return memo.shortfall }
        let shortfall = world.sharedSingleTrackShortfall(of: id)
        passingShortfallMemo = PassingShortfallMemo(key: key, shortfall: shortfall)
        return shortfall
    }

    /// What the line card says of `shortfall`: the two lines share single
    /// track with no place to pass, so a train turns back early.
    public func passingShortfallText(_ shortfall: PassingPlaceShortfall) -> String {
        guard let line = world.line(id: shortfall.line), let leg = shortfall.legs.first,
              leg.from < line.stops.count, leg.to < line.stops.count else { return "" }
        let from = world.station(id: line.stops[leg.from])?.name ?? ""
        let to = world.station(id: line.stops[leg.to])?.name ?? ""
        let others = shortfall.others.compactMap { world.line(id: $0)?.name }.joined(separator: language.text(", ", "、"))
        return language.text(
            "\(line.name) shares the single track between \(from) and \(to) with \(others), with no place to pass: a train may turn back early at \(from). A passing loop lets them pass.",
            "\(line.name) 和 \(others) 共用 \(from)—\(to) 的單線，中間沒有地方交會，列車可能會在\(from)提早折返。加一處待避線就能交會。"
        )
    }

    /// Builds a passing loop where the selected line's shared single track
    /// needs one (decision 264), made a stop of every line through it: the
    /// line card's button and the station master's advice, under simple
    /// and realistic rules alike. One command, so one Undo. A loop cannot go
    /// in under a train; the message says to wait for it to pass.
    public func addPassingLoopToSelectedLine() {
        guard let line = requireSelectedLine() else { return }
        let plans = passingLoopsNeeded(for: line.id, trains: line.assignedTrains.count, in: world)
        guard !plans.isEmpty else {
            message = StatusMessage(kind: .failure, text: language.text(
                "There is no room for a passing loop on \(line.name)'s single track: build a second track beside it instead.",
                "\(line.name) 的單線上沒有地方放待避線，請改在旁邊加一條軌道。"
            ))
            return
        }
        let plan = AutoService(newLine: nil, line: line.id, loops: plans, trains: 0, cars: Train.minimumCars, language: language)
        var trial = world
        do throws(GameError) {
            _ = try apply(plan, to: &trial)
        } catch {
            if case .trackReserved = error {
                message = StatusMessage(kind: .failure, text: language.text(
                    "A train is on that track now. Tap again once it has passed.",
                    "那段軌道上現在有列車，等它開過去再按一次。"
                ))
                return
            }
        }
        let balance = world.economy.balance
        let built = perform(.autoService(plan)) { outcome, _, world in
            let cost = Money(balance.amount - world.economy.balance.amount)
            return language.text(
                "Added a passing loop for \(cost.moneyText): \(line.name)'s trains and the others on that track pass each other there.",
                "加了一處待避線，花費 \(cost.moneyText)：\(line.name) 和同一段單線上的列車會在那裡交會。"
            ) + Self.liftedText(outcome, in: language)
        }
        if built != nil { playSound?(.track) }
    }

    /// What the message says after `plan`: the trains, the loops, and what
    /// it cost; `loopWaits`, that the loop the new line needed was left
    /// out because a train is on its track.
    static func autoServiceText(
        _ plan: AutoService, outcome: PlayerCommand.Outcome, line id: LineID, cost: Money, in world: GameWorld, language: DisplayLanguage,
        loopWaits: Bool = false
    ) -> String {
        guard let line = world.line(id: id) else { return "" }
        let count = line.trains.count
        var text: String
        if plan.newLine != nil {
            text = count > 0
                ? language.text(
                    "Created \(line.name) with \(line.stops.count) stops and a train, for \(cost.moneyText).",
                    "已建立 \(line.name)，共 \(line.stops.count) 站，配了一列車，花費 \(cost.moneyText)。"
                )
                : language.text("Created \(line.name) with \(line.stops.count) stops.", "已建立 \(line.name)，共 \(line.stops.count) 站。")
        } else {
            text = language.text(
                "\(line.name) now runs \(count) \(count == 1 ? "train" : "trains"), for \(cost.moneyText).",
                "\(line.name) 現在有 \(count) 列車，花費 \(cost.moneyText)。"
            )
        }
        if outcome.number > 0 {
            text += language.text(
                " A passing loop went in on its single track, so its trains pass each other there.",
                "單線上加了待避線，列車會在那裡交會。"
            )
        } else if loopWaits {
            text += language.text(
                " Its passing loop is not in yet: a train is on that track now. Once it has passed, tap Add a Train and the loop goes in with the next train.",
                "待避線還沒蓋：那段單線上現在有列車。等它開過去再按「加開一列車」，待避線會和下一列車一起蓋。"
            )
        }
        text += liftedText(outcome, in: language)
        if outcome.held + outcome.unfit > 0 {
            text += language.text(
                " The new train waits off the track: there is no room at the line's ends. Try again when a train has left.",
                "新的列車還沒放上軌道：路線兩端都沒有空位。等列車開出後再試一次。"
            )
        }
        return text
    }

    /// What it says of the trains taken off the track for a loop and put
    /// back where their lines' trips start.
    static func liftedText(_ outcome: PlayerCommand.Outcome, in language: DisplayLanguage) -> String {
        let count = outcome.left.count
        guard count > 0 else { return "" }
        return language.text(
            " \(count) \(count == 1 ? "train was" : "trains were") in the way and went back to the start of \(count == 1 ? "its" : "their") line.",
            "有 \(count) 列車擋在那段軌道上，已經回到路線起點。"
        )
    }

    /// The cars a train bought for line `id` has: as many as its shortest
    /// stop's longest platform holds, from one to ``AutoService/maximumCars``.
    static func autoServiceCars(for id: LineID, in world: GameWorld) -> Int {
        guard let line = world.line(id: id), world.platformCarLength > 0 else { return Train.minimumCars }
        let shortest = line.stops.map { stop in world.trackPlatforms(of: stop).map(\.length).max() ?? 0 }.min() ?? 0
        return min(max(Int(shortest / world.platformCarLength), Train.minimumCars), AutoService.maximumCars)
    }

    /// The passing loop line `id` needs in `world` to run `trains` of its
    /// own (decision 264), with room for `readyFor` trains in all on its
    /// single track, as a plan on this session's track (which `world`
    /// shares), or none. Only legs at least `shortestLeg` long take one.
    ///
    /// A line's single-track legs carry its own trains and those of every
    /// line that runs over the same track. Trains on single track pass
    /// only at a stop with a track each way: `n` trains need `n − 1` such
    /// stops between the line's ends. When the line has fewer, one loop
    /// goes in the middle of its longest single-track leg that another
    /// line shares, or else its longest: one a tap, so a line grows a loop
    /// with each train it needs one for. Rings are left to the player.
    func passingLoopsNeeded(
        for id: LineID, trains wanted: Int, readyFor: Int = 0, shortestLeg: Int64 = 0, in world: GameWorld
    ) -> [PassingLoopPlan] {
        guard let shortfall = world.passingPlaceShortfall(of: id, trains: wanted, readyFor: readyFor) else { return [] }
        for leg in shortfall.legs where leg.distance >= shortestLeg {
            if let plan = passingLoopPlan(along: leg.edges) { return [plan] }
        }
        return []
    }

    /// A passing loop in the middle of a leg over `edges`: on its longest
    /// edge, centred on the edge's middle, on either side; `nil` where none
    /// fits.
    private func passingLoopPlan(along edges: [TrackEdgeID]) -> PassingLoopPlan? {
        let edges = edges
            .compactMap { id in world.network.edge(id).map { (id: id, length: $0.length) } }
            .sorted { $0.length > $1.length }
        for edge in edges {
            for side in [PlatformTrackSide.left, .right] {
                if case .success(let plan) = passingLoopPlan(at: NetworkEdgePoint(edge: edge.id, distance: edge.length / 2), side: side) {
                    return plan
                }
            }
        }
        return nil
    }

    /// Runs `plan` in `world` (``apply(_:to:)``): the line made, the loops
    /// built and made stops of the lines through them, then the trains.
    /// The outcome has the line, the loops built in its count, and the
    /// trains left off the track. Throws ``GameError/trackReserved(_:)``
    /// naming a train in a loop's way that cannot go back on its line.
    func apply(_ plan: AutoService, to world: inout GameWorld) throws(GameError) -> PlayerCommand.Outcome {
        var outcome = PlayerCommand.Outcome()
        let id: LineID
        if let new = plan.newLine {
            let line = try world.createLine(named: new.name, stops: new.stops)
            if let targets = new.targets { try world.setLineTargetHeadways(line.id, to: targets, pattern: nil) }
            id = line.id
        } else {
            guard let line = plan.line, world.line(id: line) != nil else { throw .unknownLine(plan.line ?? LineID(rawValue: 0)) }
            id = line
        }
        // GameCore never cuts track a train stands on or has reserved: a
        // line's train in the way is taken off its line and the track, as
        // re-forming a line takes its trains off (decision 180), and put
        // back where its line's trips start once the loop is in. When both
        // its line's ends are taken, the whole command is refused: the
        // loop waits until the train has passed, rather than the train
        // leaving its line unseen.
        var lifted: [(train: TrainID, line: LineID, pattern: Int?)] = []
        for loop in plan.loops {
            var built: Station?
            while built == nil {
                var attempt = world
                do throws(GameError) {
                    built = try build(loop, in: &attempt)
                    world = attempt
                } catch {
                    guard case .trackReserved(let id) = error, lifted.count < world.trains.count,
                          let train = world.train(id: id), let line = world.assignedLine(of: id) else { throw error }
                    let pattern = world.assignedPattern(of: id)
                    try world.unassignTrain(id)
                    if train.execution != nil { try world.stopTrainService(id) }
                    if world.train(id: id)?.position != nil { try world.unplaceTrain(id) }
                    lifted.append((id, line, pattern))
                }
            }
            guard let station = built else { continue }
            for stop in world.passingLoopOffer(for: station.id).stops {
                guard let line = world.line(id: stop.line), stop.index <= line.stops.count else { continue }
                try world.setLineStops(line.id, to: LineStopEditing.inserting(station.id, at: stop.index, into: line.stops))
            }
            outcome.number += 1
        }
        for (train, line, pattern) in lifted {
            guard let journey = world.lineJourney(line) else { throw .trackReserved(train) }
            var placed = world
            if (try? Self.placeAtStart(train, of: journey, in: &placed)) == nil {
                placed = world
                guard let back = Self.farEndJourney(of: line, in: world), (try? Self.placeAtStart(train, of: back, in: &placed)) != nil else {
                    throw .trackReserved(train)
                }
            }
            world = placed
            try world.assignTrain(train, to: line, pattern: pattern)
            outcome.left.append(world.train(id: train)?.name ?? "")
        }
        if plan.trains > 0, world.lineJourney(id) != nil {
            (outcome.held, outcome.unfit) = try Self.addTrains(
                plan.trains, of: world.lineStaffingPlan(id, headway: ServiceLine.minimumHeadwayMinutes)?.type, cars: plan.cars,
                to: id, in: &world, language: plan.language, orAtTheFarEnd: true
            )
            // The round trip shared between its trains.
            if let journey = world.lineJourney(id), let count = world.line(id: id)?.trains.count, count > 0 {
                let headway = max(ServiceLine.minimumHeadwayMinutes, (journey.roundTripMinutes + Int64(count) - 1) / Int64(count))
                try world.setLineTargetHeadways(id, to: TargetHeadways(peak: headway, offPeak: headway, low: headway), pattern: nil)
            }
        }
        outcome.line = world.line(id: id)
        return outcome
    }
}
