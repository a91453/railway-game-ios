import GameCore

// TestFlight 60.1: "when I assign trains, they don't leave". A train a line
// does not send out said only "Waiting for service dispatch"; it now says
// why (``GameWorld/lineDispatchHold(of:)``) and, when the line is set to run
// fewer trains than it has, offers to run them all.

/// A service that has more trains assigned than it is set to run at some
/// level: assigning a train to a line that already runs some leaves its
/// counts as they were, so the new train waits.
public struct LineUnusedTrains: Hashable, Sendable {
    public let line: LineID
    /// The line's pattern, or `nil` for its own service.
    public let pattern: Int?
    /// How many trains every level is to run so that all of them run: the
    /// trains assigned, on a ring made even, up (decision 49).
    public let target: Int
    /// The service's counts now.
    public let counts: TrainsInService

    /// The counts with each level below ``target`` raised to it.
    public var raised: TrainsInService {
        TrainsInService(peak: max(counts.peak, target), offPeak: max(counts.offPeak, target), low: max(counts.low, target))
    }
}

extension GameWorld {
    /// The unused trains of the service train `id` runs for (see
    /// ``LineUnusedTrains``), or `nil` when every level runs at least as
    /// many trains as it has.
    public func lineUnusedTrains(ofTrain id: TrainID) -> LineUnusedTrains? {
        guard let lineID = assignedLine(of: id), let line = line(id: lineID) else { return nil }
        let pattern = assignedPattern(of: id)
        let counts = pattern.map { line.patterns[$0].trainsInService } ?? line.trainsInService
        let assigned = (pattern.map { line.patterns[$0].trains } ?? line.trains).count
        let target = min(TrainsInService.maximum, line.isRing ? assigned + assigned % 2 : assigned)
        guard ServiceLevel.allCases.contains(where: { counts[$0] < target }) else { return nil }
        return LineUnusedTrains(line: lineID, pattern: pattern, target: target, counts: counts)
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
                "Not at the first stop \(name): send it there, or turn on flexible dispatch",
                "不在首站 \(name)：派它到首站，或開啟彈性發車"
            )
        case .noRoundTrip(let first):
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

extension GameSession {
    /// Sets the service of train `id` to run every train it has at every
    /// level (``LineUnusedTrains/raised``), through the same command as
    /// the line panel's counts.
    public func runAllAssignedTrains(ofTrain id: TrainID) {
        guard let unused = world.lineUnusedTrains(ofTrain: id), let line = world.line(id: unused.line) else { return }
        let service = world.assignedServiceName(of: id, in: language) ?? line.name
        perform(.setLineTrains(unused.line, unused.raised, pattern: unused.pattern)) { _, _, _ in
            language.text(
                "\(service) now runs \(unused.target) \(unused.target == 1 ? "train" : "trains") at every level.",
                "\(service) 各時段上線 \(unused.target) 列。"
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
