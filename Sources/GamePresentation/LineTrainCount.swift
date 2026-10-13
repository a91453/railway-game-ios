import GameCore

// A line's headway and trains after it has started (TestFlight 54.1 and
// 56.1: "make arranging several trains simpler"). Decision 101's one step
// (choose how often a train comes, tap once) used to be offered only to a
// line without trains; afterwards the player had a count per time of day
// that buys nothing, a list of trains already on the track to assign, and
// a target headway behind Advanced. Here the same choice serves a line
// that runs: the trains its headway lacks are bought and placed where its
// trips start, as decision 194's "run more trains" does
// (`PlayerCommand.Edit.addLineTrains`), and the trains it no longer needs
// go back to no line once their trip is over; the line's targets keep them
// evenly apart. Also: the warning when a line is set to run more trains
// than it has, with the one tap that buys them, and the trains and headway
// the lines list shows on each row. The reference has nothing to port:
// `Ci/`'s lines come with their trains and its count is a stepper.

/// Running a line that has trains every `headway` minutes: the trains it
/// gains or gives up for it.
public struct LineHeadwayChange: Hashable, Sendable {
    /// The minutes between trains the player asked for.
    public let headway: Int64
    /// The minutes between them it gets: more than `headway` when the line
    /// cannot run as many trains as that needs
    /// (``LineStaffingPlan/actualHeadway``).
    public let actualHeadway: Int64
    /// The trains its own service has now, and those it will have.
    public let current: Int
    public let trains: Int
    /// The most trains the line can run, when that holds it back.
    public let maximum: Int?
    /// What each bought train costs, its type and its cars (the line's
    /// first train's, as decision 194's fix buys).
    public let pricePerTrain: Money
    public let type: TrainType?
    public let cars: Int
    /// Whether the line already runs every `headway` minutes with these
    /// trains: nothing to do.
    public let isUnchanged: Bool

    /// The target headway at every level.
    public var targets: TargetHeadways {
        TargetHeadways(peak: headway, offPeak: headway, low: headway)
    }

    /// The trains bought for it, and those taken off.
    public var buying: Int { max(0, trains - current) }
    public var removing: Int { max(0, current - trains) }

    /// What the trains bought cost.
    public var cost: Money {
        let (cost, overflow) = pricePerTrain.amount.multipliedReportingOverflow(by: Int64(buying))
        return Money(overflow ? .max : cost)
    }

    /// The button: "Every 5 min (add 2 trains · $ 9,000,000)", "Run 2
    /// trains, every 20 min (the others go to no line)", "Every 10 min",
    /// or "Already every 10 min".
    public func title(in language: DisplayLanguage) -> String {
        if isUnchanged {
            return language.text("Already every \(headway) min", "已經是每 \(headway) 分")
        }
        if buying > 0 {
            return language.text(
                "Every \(headway) min (add \(buying) \(buying == 1 ? "train" : "trains") · \(cost.moneyText))",
                "調整為每 \(headway) 分（加開 \(buying) 列 · \(cost.moneyText)）"
            )
        }
        if removing > 0 {
            return language.text(
                "Run \(trains) \(trains == 1 ? "train" : "trains"), every \(headway) min (the others go to no line)",
                "改為 \(trains) 列，每 \(headway) 分（多的車回到未配屬）"
            )
        }
        return language.text("Every \(headway) min", "調整為每 \(headway) 分")
    }

    /// Why it gets less than asked, or `nil` when it does not: single
    /// track holds the line to `maximum` trains.
    public func limitText(in language: DisplayLanguage) -> String? {
        guard actualHeadway > headway, let maximum else { return nil }
        return language.text(
            "This line can run at most \(maximum) \(maximum == 1 ? "train" : "trains"): one every \(actualHeadway) min. Double track or passing loops let it run more.",
            "這條路線最多只能跑 \(maximum) 列：每 \(actualHeadway) 分一班。蓋雙線或待避線才能再多跑。"
        )
    }
}

/// A line set to run more trains than it has (TestFlight 56.1): what it
/// wants at its busiest level, what it has, and buying the rest.
public struct LineTrainShortfall: Hashable, Sendable {
    public let level: ServiceLevel
    public let wanted: Int
    public let assigned: Int
    public let pricePerTrain: Money
    public let type: TrainType?
    public let cars: Int

    public var buying: Int { max(0, wanted - assigned) }

    public var cost: Money {
        let (cost, overflow) = pricePerTrain.amount.multipliedReportingOverflow(by: Int64(buying))
        return Money(overflow ? .max : cost)
    }

    /// "Peak is set to 5 trains but the line has 3: trains come less often
    /// than shown."
    public func warning(in language: DisplayLanguage) -> String {
        let name = level.title(in: language)
        return language.text(
            "\(name) is set to \(wanted) trains but the line has \(assigned): trains come less often than shown.",
            "\(name)設定上線 \(wanted) 列，但路線只有 \(assigned) 列：實際班距會比顯示的長。"
        )
    }

    /// The button: "Add 2 trains · $ 9,000,000".
    public func title(in language: DisplayLanguage) -> String {
        language.text(
            "Add \(buying) \(buying == 1 ? "train" : "trains") · \(cost.moneyText)",
            "補齊 \(buying) 列 · \(cost.moneyText)"
        )
    }
}

extension GameWorld {
    /// What running line `id`'s own service every `headway` minutes takes
    /// once it has trains: the trains it gains or gives up. `nil` for a
    /// line without trains of its own (decision 101's staffing serves it),
    /// a ring, or a line whose journey cannot be driven.
    public func lineHeadwayChange(_ id: LineID, headway: Int64) -> LineHeadwayChange? {
        guard let line = line(id: id), !line.isRing, !line.trains.isEmpty else { return nil }
        let first = line.trains.first.flatMap { train(id: $0) }
        guard let plan = lineStaffingPlan(id, headway: headway, type: first?.type, cars: first?.cars ?? 1) else { return nil }
        let maximum = lineMaximumTrains(id)
        let targets = TargetHeadways(peak: headway, offPeak: headway, low: headway)
        return LineHeadwayChange(
            headway: headway, actualHeadway: plan.actualHeadway, current: line.trains.count, trains: plan.trains,
            maximum: maximum.flatMap { plan.trains >= $0 ? $0 : nil },
            pricePerTrain: plan.pricePerTrain, type: plan.type, cars: plan.cars,
            isUnchanged: plan.trains == line.trains.count && line.targetHeadways == targets
        )
    }

    /// Line `id`'s own service set to run more trains at some level than
    /// it has (the busiest such level), or `nil` when it has them all, has
    /// none (decision 101's staffing serves it), or is a ring (each way
    /// runs its own trains).
    public func lineTrainShortfall(_ id: LineID) -> LineTrainShortfall? {
        guard let line = line(id: id), !line.isRing, let first = line.trains.first.flatMap({ train(id: $0) }) else { return nil }
        var most: (level: ServiceLevel, trains: Int)?
        for level in ServiceLevel.allCases {
            guard let trains = lineTrainsInService(id, at: level) else { continue }
            if trains > (most?.trains ?? 0) { most = (level, trains) }
        }
        guard let most, most.trains > line.trains.count else { return nil }
        return LineTrainShortfall(
            level: most.level, wanted: most.trains, assigned: line.trains.count,
            pricePerTrain: purchaseCost(of: first.type, cars: first.cars), type: first.type, cars: first.cars
        )
    }

    /// The minutes between line `id`'s own trains at its busiest level, as
    /// they run: the headway it plans, or longer when its trains are too
    /// few to keep to it (each way, on a ring). `nil` without trains of its
    /// own or a journey.
    public func lineRunningHeadway(_ id: LineID) -> Int64? {
        guard let line = line(id: id), let roundTrip = lineJourney(id)?.roundTripMinutes else { return nil }
        let eachWay = Int64(line.isRing ? line.trains.count / 2 : line.trains.count)
        guard eachWay > 0 else { return nil }
        let byTrains = (roundTrip + eachWay - 1) / eachWay
        return ServiceLevel.allCases.compactMap { lineHeadway(id, at: $0).map { max($0, byTrains) } }.min()
    }

    /// What the lines list says of line `id`'s trains: "3 trains · every 8
    /// min", "1 train", or "No trains".
    public func lineTrainsRowText(_ id: LineID, in language: DisplayLanguage) -> String {
        let count = line(id: id)?.assignedTrains.count ?? 0
        guard count > 0 else { return language.text("No trains", "沒有列車") }
        let trains = language.text("\(count) \(count == 1 ? "train" : "trains")", "\(count) 列")
        guard let headway = lineRunningHeadway(id) else { return trains }
        return trains + " · " + headwayText(minutes: headway, in: language).lowercased()
    }
}

extension GameSession {
    /// Makes `change` on the selected line, in one command the log keeps:
    /// the trains it lacks bought and placed where its trips start
    /// (``PlayerCommand/Edit/addLineTrains(_:count:type:cars:targets:language:)``),
    /// or those it no longer needs taken off it
    /// (``PlayerCommand/Edit/removeLineTrains(_:count:targets:)``), and its
    /// targets set to the headway at every level.
    public func changeSelectedLineHeadway(_ change: LineHeadwayChange) {
        guard let line = requireSelectedLine() else { return }
        let headway = change.headway
        if change.removing > 0 {
            perform(.removeLineTrains(line.id, count: change.removing, targets: change.targets)) { _, _, _ in
                language.text(
                    "\(line.name) now runs \(change.trains) \(change.trains == 1 ? "train" : "trains"), every \(headway) min. "
                        + "\(change.removing) more \(change.removing == 1 ? "goes" : "go") to no line once \(change.removing == 1 ? "its" : "their") trip is over.",
                    "「\(line.name)」現在跑 \(change.trains) 列，每 \(headway) 分一班。另外 \(change.removing) 列跑完這一趟後回到未配屬。"
                )
            }
        } else {
            addTrains(change.buying, to: line, cost: change.cost, type: change.type, cars: change.cars, targets: change.targets) {
                language.text("\(line.name) now runs a train every \(headway) min.", "「\(line.name)」現在每 \(headway) 分一班。")
            }
        }
    }

    /// Buys the trains `shortfall` lacks for the selected line and places
    /// and assigns them, keeping its targets.
    public func fillSelectedLineTrains(_ shortfall: LineTrainShortfall) {
        guard let line = requireSelectedLine() else { return }
        addTrains(shortfall.buying, to: line, cost: shortfall.cost, type: shortfall.type, cars: shortfall.cars, targets: line.targetHeadways) {
            language.text(
                "\(line.name) now has the \(shortfall.wanted) trains it is set to run.",
                "「\(line.name)」現在有設定的 \(shortfall.wanted) 列車。"
            )
        }
    }

    /// `count` trains bought for `cost` and put on `line`, its targets set
    /// to `targets`, saying `done` and how many could not be placed.
    private func addTrains(
        _ count: Int, to line: ServiceLine, cost: Money, type: TrainType?, cars: Int, targets: TargetHeadways, done: () -> String
    ) {
        perform(.addLineTrains(line.id, count: count, type: type, cars: cars, targets: targets, language: language)) { outcome, _, _ in
            var text = done()
            if count > 0 {
                text = language.text(
                    "Bought \(count) \(count == 1 ? "train" : "trains") for \(cost.moneyText): ",
                    "花 \(cost.moneyText) 買了 \(count) 列車："
                ) + text
            }
            let left = outcome.held + outcome.unfit
            if left > 0 {
                text += language.text(
                    " \(left) of them \(left == 1 ? "stays" : "stay") off the track, not assigned: there is no room at the line's first stop.",
                    "其中 \(left) 列沒有放上軌道，也沒有配屬：路線第一站停不下。"
                )
            }
            return text
        }
    }

    /// Takes `count` of line `id`'s own trains off it in `world`, those
    /// waiting for their next trip first, the last assigned first; a train
    /// on a trip finishes it. Its targets are set to `targets`.
    static func removeTrains(_ count: Int, from id: LineID, targets: TargetHeadways, in world: inout GameWorld) throws(GameError) {
        guard let line = world.line(id: id) else { throw .unknownLine(id) }
        let newestFirst = line.trains.reversed()
        let waiting = newestFirst.filter { world.train(id: $0)?.execution == nil }
        let running = newestFirst.filter { world.train(id: $0)?.execution != nil }
        for train in (waiting + running).prefix(max(0, count)) {
            try world.unassignTrain(train)
        }
        try world.setLineTargetHeadways(id, to: targets, pattern: nil)
    }
}
