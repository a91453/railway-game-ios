import GameCore

// TestFlight 60.1: "when I assign trains, they don't leave". A train a line
// does not send out said only "Waiting for service dispatch"; it now says
// why (``GameWorld/lineDispatchHold(of:)``) and, when the line is set to run
// fewer trains than it has, offers to run them all.

/// A service that has more trains assigned than it is set to run even at
/// its busiest level: assigning a train to a line that already runs some
/// leaves its counts as they were, so the new train never leaves. A level
/// set below the busiest one is the player's choice and is not counted.
public struct LineUnusedTrains: Hashable, Sendable {
    public let line: LineID
    /// The line's pattern, or `nil` for its own service.
    public let pattern: Int?
    /// How many trains the busiest level is to run so that all of them run: the
    /// trains assigned, on a ring made even, up (decision 49).
    public let target: Int
    /// The service's counts now.
    public let counts: TrainsInService

    /// The most the service is set to run at any level.
    public var busiest: Int { ServiceLevel.allCases.map { counts[$0] }.max() ?? 0 }

    /// The counts with each level set to the busiest count raised to
    /// ``target``; a level set lower stays as it is.
    public var raised: TrainsInService {
        let busiest = busiest
        func raise(_ count: Int) -> Int { count == busiest ? max(count, target) : count }
        return TrainsInService(peak: raise(counts.peak), offPeak: raise(counts.offPeak), low: raise(counts.low))
    }
}

extension GameWorld {
    /// The unused trains of the service train `id` runs for (see
    /// ``LineUnusedTrains``), or `nil` when its busiest level runs at least as
    /// many trains as it has.
    public func lineUnusedTrains(ofTrain id: TrainID) -> LineUnusedTrains? {
        guard let lineID = assignedLine(of: id), let line = line(id: lineID) else { return nil }
        let pattern = assignedPattern(of: id)
        // A level run to a target headway takes its trains from the
        // headway, not the counts: raising the counts would change nothing.
        let targets = pattern.map { line.patterns[$0].targetHeadways } ?? line.targetHeadways
        guard targets == .none else { return nil }
        let counts = pattern.map { line.patterns[$0].trainsInService } ?? line.trainsInService
        let assigned = (pattern.map { line.patterns[$0].trains } ?? line.trains).count
        let target = min(TrainsInService.maximum, line.isRing ? assigned + assigned % 2 : assigned)
        let unused = LineUnusedTrains(line: lineID, pattern: pattern, target: target, counts: counts)
        return unused.busiest < target ? unused : nil
    }

    /// Whether the service train `id` runs for is set by the player to run
    /// `planned` trains at this time of day, fewer than at its busiest
    /// level (the PR #526–#626 review, U3): the counts, not a target
    /// headway or the track, keep it to `planned`.
    private func isSetLowNow(ofTrain id: TrainID, planned: Int) -> Bool {
        guard let lineID = assignedLine(of: id), let line = line(id: lineID),
              let level = serviceLevel(of: lineID, at: clock.now) else { return false }
        let pattern = assignedPattern(of: id)
        let targets = pattern.map { line.patterns[$0].targetHeadways } ?? line.targetHeadways
        guard targets[level] == nil else { return false }
        let counts = pattern.map { line.patterns[$0].trainsInService } ?? line.trainsInService
        let busiest = ServiceLevel.allCases.map { counts[$0] }.max() ?? 0
        return counts[level] == planned && planned < busiest
    }

    /// Why line train `id` is not sent out (``lineDispatchHold(of:)``), in
    /// words that say what to do, or `nil` when nothing holds it.
    public func lineDispatchHoldText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let hold = lineDispatchHold(of: id) else { return nil }
        switch hold {
        case .notPlaced(let first):
            let name = stationName(first)
            return language.text("Not on the track: place it at \(name) first", "未放上軌道：先放到 \(name)")
        case .stopped:
            return language.text("Stopped: tap Resume train", "列車已暫停：按「恢復列車」")
        case .awayFromFirstStop(let first):
            let name = stationName(first)
            return language.text(
                "Not at the first stop \(name): send it there",
                "不在首站 \(name)：派它到首站"
            )
        case .noRoundTrip(let first):
            // Decision 284 (TestFlight 73.1): a train longer than every
            // platform of a call can stop there on no platform.
            if let short = shortPlatformCall(ofTrain: id) {
                return shortPlatformText(short, in: language)
            }
            let name = stationName(first)
            return language.text(
                "Cannot run the line from here: check the track to \(name)",
                "從這裡跑不完路線：檢查到 \(name) 的軌道"
            )
        case .serviceFull(_, let planned):
            if let unused = lineUnusedTrains(ofTrain: id) {
                return language.text(
                    "The line runs only \(planned) \(planned == 1 ? "train" : "trains") now: run \(unused.target)",
                    "路線只開 \(planned) 列：加開到 \(unused.target) 列"
                )
            }
            if isSetLowNow(ofTrain: id, planned: planned) {
                return language.text(
                    "The line is set to run \(planned) \(planned == 1 ? "train" : "trains") at this time of day",
                    "路線這個時段設定只開 \(planned) 列"
                )
            }
            return language.text(
                "The line runs only \(planned) \(planned == 1 ? "train" : "trains") now (headway or track limits it)",
                "路線現在只開 \(planned) 列（受班距或軌道限制）"
            )
        case .routeHeld:
            if let line = assignedLine(of: id), lineCapacityWarning(line, in: language) != nil {
                return language.text(
                    "Single track ahead is taken: add a passing platform or double the track",
                    "前方單線被占用：加會車月台或改雙線"
                )
            }
            return language.text("The way ahead is taken: waits for it to clear", "前方區間被占用：等候空出")
        }
    }
}

/// A call of a line that a train is too long for (decision 284): every
/// platform of the station is shorter than the train, so it can stop there
/// on none (`GameWorld.path(from:toStation:length:)` ends only at a platform
/// the train fits).
public struct ShortPlatformCall: Hashable, Sendable {
    /// The first such call, in the order the service calls.
    public let station: StationID
    /// The length, in world units, its longest platform must have.
    public let needed: Int64
    /// The most cars, at the train's car length, that fit at every call of
    /// the service.
    public let cars: Int
}

extension GameWorld {
    /// The first call of the service train `id` runs for that the train is
    /// longer than every platform of (``ShortPlatformCall``), or `nil` when
    /// it fits at every call, or runs for no line.
    public func shortPlatformCall(ofTrain id: TrainID) -> ShortPlatformCall? {
        guard let train = train(id: id), let lineID = assignedLine(of: id), let line = line(id: lineID) else { return nil }
        let stops = assignedPattern(of: id).map { line.patterns[$0].calls.map { line.stops[$0] } } ?? line.stops
        // A station with no platform at all is another problem: no train
        // stops there, however short.
        let longest = stops.map { stop in network.platforms(of: stop).map(\.length).max() }
        guard let index = longest.firstIndex(where: { $0.map { $0 < train.length } ?? false }),
              let shortest = longest.compactMap(\.self).min()
        else { return nil }
        return ShortPlatformCall(station: stops[index], needed: train.length, cars: Int(shortest / train.carPitch) + 1)
    }

    /// What a train too long for a call of its line is told: the station,
    /// how long its platform must be, and how many cars fit.
    public func shortPlatformText(_ short: ShortPlatformCall, in language: DisplayLanguage) -> String {
        let name = stationName(short.station)
        let unitsPerMetre = WorldCoordinate.unitsPerMetre
        let metres = (short.needed + unitsPerMetre - 1) / unitsPerMetre
        return language.text(
            "Too long for the platforms at \(name): lengthen one to \(metres) m, or take the train off the track and shorten it to \(short.cars) \(short.cars == 1 ? "car" : "cars")",
            "列車比 \(name) 的月台長：把月台加長到 \(metres) 公尺，或把列車移出軌道、減到 \(short.cars) 節"
        )
    }
}

/// Why lines hold their trains (``GameWorld/lineDispatchHoldText(of:in:)``),
/// kept for the ``GameSession/commandRevision`` and game minute they were
/// worked out in.
struct LineDispatchHoldMemo {
    let revision: Int
    let minute: Int64
    var texts: [TrainID: String?] = [:]
}

extension GameSession {
    /// ``GameWorld/trainPathStatusText(of:in:)`` of the world as it is now,
    /// in ``language``, with why a line holds the train worked out once a
    /// command (``commandRevision``) or a game minute, not at every read:
    /// it plans the train's trip (a route search), and the fleet overview
    /// reads every waiting train's at each redraw.
    public func trainPathStatusText(of id: TrainID) -> String {
        world.trainPathStatusText(of: id, in: language) { lineDispatchHoldText(of: $0) }
    }

    /// ``GameWorld/lineDispatchHoldText(of:in:)``, kept as
    /// ``trainPathStatusText(of:)`` says.
    func lineDispatchHoldText(of id: TrainID) -> String? {
        let minute = world.clock.now.seconds / GameTime.secondsPerMinute
        if lineDispatchHoldMemo?.revision != commandRevision || lineDispatchHoldMemo?.minute != minute {
            lineDispatchHoldMemo = LineDispatchHoldMemo(revision: commandRevision, minute: minute)
        }
        if let text = lineDispatchHoldMemo?.texts[id] { return text }
        let text = world.lineDispatchHoldText(of: id, in: language)
        lineDispatchHoldMemo?.texts[id] = text
        lineDispatchHoldsWorkedOut += 1
        return text
    }

    /// Sets the service of train `id` to run every train it has at its
    /// busiest levels (``LineUnusedTrains/raised``), through the same
    /// command as the line panel's counts.
    public func runAllAssignedTrains(ofTrain id: TrainID) {
        guard let unused = world.lineUnusedTrains(ofTrain: id), let line = world.line(id: unused.line) else { return }
        let service = world.assignedServiceName(of: id, in: language) ?? line.name
        perform(.setLineTrains(unused.line, unused.raised, pattern: unused.pattern)) { _, _, _ in
            language.text(
                "\(service) now runs up to \(unused.target) \(unused.target == 1 ? "train" : "trains").",
                "\(service) 最多上線 \(unused.target) 列。"
            )
        }
    }

    /// Whether the train card offers its line menu for train `id`: as the
    /// line panel's ``unassignedTrainMenuChoices``, only for a train on
    /// the track with no line and no service of its own.
    public func offersLineMenu(for id: TrainID) -> Bool {
        guard let train = world.train(id: id) else { return false }
        return train.position != nil && train.execution == nil && world.assignedLine(of: id) == nil && !world.lines.isEmpty
    }
}
