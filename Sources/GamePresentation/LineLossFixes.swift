import GameCore

// One-tap fixes for a losing line's reasons, and the line the station
// master names (ARCHITECTURE decision 194, later): each reason on the line
// card gets the change that answers it, made through a `GameWorld` command
// the command log keeps (decision 193). Too many trains takes one off,
// trains too far apart buys what a shorter headway lacks, nearly empty
// trains run less often. Empty running has no command that would stop the
// trains at the line's ends, so it keeps its words alone. The reference has
// nothing to port: its finance summary names no reasons (decision 194).

/// The change that answers a reason a line loses money (decision 194,
/// later).
public enum LineLossFix: Hashable, Sendable {
    /// Too many trains: train `train` taken off the line
    /// (``GameSession/unassignTrain(_:)``).
    case takeOffTrain(TrainID, name: String)
    /// Trains too far apart: a train every `headway` minutes, the line's
    /// targets set to `targets` and `buying` trains of `type` with `cars`
    /// cars bought for `cost`, as many as its own service lacks for it
    /// (none when its trains already reach).
    case runMoreTrains(headway: Int64, targets: TargetHeadways, buying: Int, cost: Money, type: TrainType?, cars: Int)
    /// Trains run nearly empty: a train only every `headway` minutes, the
    /// line's targets set to `targets`.
    case runLessOften(headway: Int64, targets: TargetHeadways)

    /// The headways the fixes step through, in minutes: the line panel's
    /// target headways.
    public static let headways: [Int64] = [5, 10, 15, 20, 30, 60]

    /// The reason it answers.
    public var kind: LineLossReason.Kind {
        switch self {
        case .takeOffTrain: .tooManyTrains
        case .runMoreTrains: .longHeadway
        case .runLessOften: .lowLoad
        }
    }

    /// What it costs, or zero.
    public var cost: Money {
        if case .runMoreTrains(_, _, _, let cost, _, _) = self { return cost }
        return .zero
    }

    /// Whether a balance of `balance` pays for it.
    public func isAffordable(with balance: Money) -> Bool {
        cost <= .zero || balance >= cost
    }

    /// The button: "Take off a train", "Add 2 trains · $ 9,000,000"…
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .takeOffTrain:
            return language.text("Take off a train", "撤下一列")
        case let .runMoreTrains(headway, _, buying, cost, _, _):
            guard buying > 0 else { return language.text("A train every \(headway) min", "班距縮短到 \(headway) 分") }
            return language.text(
                "Add \(buying) \(buying == 1 ? "train" : "trains") · \(cost.moneyText)",
                "加開 \(buying) 列 · \(cost.moneyText)"
            )
        case let .runLessOften(headway, _):
            return language.text("A train every \(headway) min", "班距拉長到 \(headway) 分")
        }
    }

    /// What the confirmation asks before it is done, on line `line`.
    public func question(on line: String, in language: DisplayLanguage) -> String {
        switch self {
        case let .takeOffTrain(_, name):
            return language.text(
                "Take \(name) off \(line)? It finishes the trip it is on; it stays yours, off the line, and no longer costs the line its keep.",
                "要把 \(name) 移出「\(line)」嗎？進行中的這一趟會跑完；列車仍是你的，只是不再跑這條線，也不再算這條線的開銷。"
            )
        case let .runMoreTrains(headway, _, buying, cost, _, _):
            guard buying > 0 else {
                return language.text(
                    "Run \(line) every \(headway) min? Its trains already reach; each departure costs its running cost.",
                    "要把「\(line)」改成每 \(headway) 分一班嗎？現有的列車就夠；每次發車都要付營運費。"
                )
            }
            return language.text(
                "Buy \(buying) \(buying == 1 ? "train" : "trains") for \(cost.moneyText) and run \(line) every \(headway) min? Each costs its keep every day.",
                "要花 \(cost.moneyText) 買 \(buying) 列車，把「\(line)」改成每 \(headway) 分一班嗎？每列每天都有開銷。"
            )
        case let .runLessOften(headway, _):
            return language.text(
                "Run \(line) only every \(headway) min? Fewer departures cost less, but riders wait longer.",
                "要把「\(line)」改成每 \(headway) 分才一班嗎？發車少了比較省，但旅客要等比較久。"
            )
        }
    }

    /// Why the button is off when the money does not reach.
    public func shortOfMoneyText(in language: DisplayLanguage) -> String {
        language.text("Not enough money: \(cost.moneyText) needed.", "錢不夠：需要 \(cost.moneyText)。")
    }
}

extension GameWorld {
    /// The change that answers reason `kind` on line `id` (decision 194,
    /// later), or `nil` when there is none to make: empty running (no
    /// command stops trains at a line's ends), a line of one train, a ring
    /// (each way runs its own trains), a line whose own service runs no
    /// trains, or a headway already at the end of ``LineLossFix/headways``.
    public func lineLossFix(_ kind: LineLossReason.Kind, on id: LineID) -> LineLossFix? {
        guard let line = line(id: id) else { return nil }
        switch kind {
        case .tooManyTrains:
            // The last one assigned: its trip under way is finished.
            guard line.assignedTrains.count >= 2, let last = line.assignedTrains.last, let train = train(id: last) else { return nil }
            return .takeOffTrain(last, name: train.name)
        case .emptyRuns:
            return nil
        case .longHeadway:
            let now = runningHeadways(of: line)
            guard let longest = now.values.max(), let headway = LineLossFix.headways.last(where: { $0 < longest }) else { return nil }
            let targets = Self.targets(now) { min(headway, $0) }
            let shortest = [targets.peak, targets.offPeak, targets.low].compactMap { $0 }.min() ?? headway
            let first = line.trains.first.flatMap { train(id: $0) }
            guard let plan = lineStaffingPlan(id, headway: shortest, type: first?.type, cars: first?.cars ?? 1),
                  plan.actualHeadway < longest
            else { return nil }
            let buying = max(0, plan.trains - line.trains.count)
            let (cost, overflow) = plan.pricePerTrain.amount.multipliedReportingOverflow(by: Int64(buying))
            return .runMoreTrains(
                headway: headway, targets: targets, buying: buying, cost: Money(overflow ? .max : cost), type: plan.type, cars: plan.cars
            )
        case .lowLoad:
            let now = runningHeadways(of: line)
            guard let shortest = now.values.min(), let headway = LineLossFix.headways.first(where: { $0 > shortest }) else { return nil }
            return .runLessOften(headway: headway, targets: Self.targets(now) { max(headway, $0) })
        }
    }

    /// The minutes between the trains of `line`'s own service at each level
    /// it runs at: the headway the line plans (``lineHeadway(_:at:pattern:)``),
    /// or longer when its trains are too few to keep to it. Empty for a
    /// ring, or without trains of its own.
    private func runningHeadways(of line: ServiceLine) -> [ServiceLevel: Int64] {
        guard !line.isRing, !line.trains.isEmpty, let roundTrip = lineJourney(line.id)?.roundTripMinutes else { return [:] }
        let trains = Int64(line.trains.count)
        let byTrains = (roundTrip + trains - 1) / trains
        var headways: [ServiceLevel: Int64] = [:]
        for level in ServiceLevel.allCases {
            if let planned = lineHeadway(line.id, at: level) { headways[level] = max(planned, byTrains) }
        }
        return headways
    }

    /// Targets from `now`'s headways, each changed by `change`; a level
    /// the line does not run at stays without one.
    private static func targets(_ now: [ServiceLevel: Int64], _ change: (Int64) -> Int64) -> TargetHeadways {
        TargetHeadways(peak: now[.peak].map(change), offPeak: now[.offPeak].map(change), low: now[.low].map(change))
    }
}

/// The losing line the station master names (decision 194, later): the one
/// that lost most over its report's days among those with a reason, and its
/// first reason.
public struct LineLossLeader: Hashable, Sendable {
    public let line: LineID
    public let name: String
    public let reason: LineLossReason.Kind
    public let loss: Money
}

extension GameWorld {
    /// The passenger line that lost most over its report's settled days
    /// (``lineLossDiagnosis(_:)``) among those it gives a reason for, the
    /// lowest ID on a tie; `nil` when none does, or outside a managed
    /// company, which has no money to lose.
    public func worstLosingLine() -> LineLossLeader? {
        guard accounts.mode == .management else { return nil }
        var worst: LineLossLeader?
        for line in lines.sorted(by: { $0.id < $1.id }) where !line.isFreight {
            guard let diagnosis = lineLossDiagnosis(line.id), diagnosis.isLosing, let reason = diagnosis.reasons.first else { continue }
            let loss = Money(-diagnosis.profit.amount)
            if worst.map({ loss > $0.loss }) ?? true {
                worst = LineLossLeader(line: line.id, name: line.name, reason: reason.kind, loss: loss)
            }
        }
        return worst
    }
}

extension GameSession {
    /// Makes `fix` on line `id` (decision 194, later), through the command
    /// it is, and says what it did.
    public func applyLineLossFix(_ fix: LineLossFix, to id: LineID) {
        let name = world.line(id: id)?.name ?? ""
        switch fix {
        case .takeOffTrain(let train, _):
            unassignTrain(train)
        case let .runMoreTrains(headway, targets, buying, cost, type, cars):
            perform(.addLineTrains(id, count: buying, type: type, cars: cars, targets: targets, language: language)) { outcome, _, _ in
                let running = buying - outcome.held - outcome.unfit
                var text = buying == 0
                    ? language.text("\(name) now runs a train every \(headway) min.", "「\(name)」現在每 \(headway) 分一班。")
                    : language.text(
                        "Bought \(buying) \(buying == 1 ? "train" : "trains") for \(cost.moneyText): \(name) now runs a train every \(headway) min.",
                        "花 \(cost.moneyText) 買了 \(buying) 列車：「\(name)」現在每 \(headway) 分一班。"
                    )
                if running < buying {
                    let left = buying - running
                    text += language.text(
                        " \(left) of them \(left == 1 ? "stays" : "stay") off the track, not assigned: there is no room at the line's first stop.",
                        "其中 \(left) 列沒有放上軌道，也沒有配屬：路線第一站停不下。"
                    )
                }
                return text
            }
        case let .runLessOften(headway, targets):
            perform(.setLineTargets(id, targets, pattern: nil)) { _, _, _ in
                language.text("\(name) now runs a train only every \(headway) min.", "「\(name)」現在每 \(headway) 分才一班。")
            }
        }
    }
}

/// Keeps ``GameWorld/worstLosingLine()`` for the station master (decision
/// 194, later), which asks once an hour of game time: worked out again only
/// for a new ``GameSession/commandRevision`` or settled day
/// (``GameWorld/lineLossSettledDay``), as ``LineLossMemo``. Not game state.
@MainActor
final class LineLossLeaderMemo {
    private struct Key: Equatable {
        let revision: Int
        let day: Int64
    }

    private var key: Key?
    private var kept: LineLossLeader?
    /// How many times it has worked the line out (for the tests).
    private(set) var workedOut = 0

    func leader(of session: GameSession) -> LineLossLeader? {
        let world = session.world
        let now = Key(revision: session.commandRevision, day: world.lineLossSettledDay)
        guard now != key else { return kept }
        key = now
        kept = world.worstLosingLine()
        workedOut += 1
        return kept
    }
}
