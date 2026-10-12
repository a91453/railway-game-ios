import GameCore

// Trains for a new line in one step (ARCHITECTURE decision 101, UI/UX step
// UX-4): the player chooses how often a train should come, and the line
// gets as many trains as its round trip needs for that, bought, placed
// where its trips start, assigned and set to that headway. Until now that
// took a purchase, a placement and an assignment for each train, and a
// target per service level. The reference has nothing to port: `Ci/`'s
// lines come with their trains (`spawnTrains`), and its train count is a
// stepper.

/// What running a line every `headway` minutes takes (decision 101).
public struct LineStaffingPlan: Equatable, Sendable {
    /// The minutes between trains the player asked for.
    public let headway: Int64
    /// The minutes a round trip takes (``LineJourney/roundTripMinutes``).
    public let roundTripMinutes: Int64
    /// The trains it needs: one for each `headway` of the round trip,
    /// rounded up, at least one and at most what the line can run
    /// (``GameWorld/lineMaximumTrains(_:pattern:)``).
    public let trains: Int
    /// What buying them costs.
    public let cost: Money
    /// The type and the cars of each train (decision 180), and what each
    /// costs to buy and to keep a day on the line.
    public let type: TrainType?
    public let cars: Int
    public let pricePerTrain: Money
    public let dailyCostPerTrain: Money
    /// The minutes between trains it actually gets: the round trip shared
    /// between them, rounded up (more than `headway` when the line cannot
    /// run as many trains as the headway needs).
    public var actualHeadway: Int64 {
        let count = Int64(max(1, trains))
        return (roundTripMinutes + count - 1) / count
    }
}

extension GameWorld {
    /// The headways a player picks from, in minutes.
    public static let staffingHeadways: [Int64] = [3, 5, 10, 15, 20, 30]

    /// What running line `id`'s own service every `headway` minutes takes:
    /// the trains its round trip needs and their price. `nil` for a line
    /// that does not exist, a ring (each way needs its own trains facing
    /// its own way), a headway under 2 minutes, or a line whose journey
    /// cannot be driven (no track joins its stops).
    ///
    /// The trains are of `type` (`nil`: the standard car) with `cars` cars
    /// each, bought at ``purchaseCost(of:cars:)`` (decision 180).
    public func lineStaffingPlan(_ id: LineID, headway: Int64, type: TrainType? = nil, cars: Int = 1) -> LineStaffingPlan? {
        guard headway >= ServiceLine.minimumHeadwayMinutes, let line = line(id: id), !line.isRing,
              let journey = lineJourney(id)
        else { return nil }
        let roundTrip = journey.roundTripMinutes
        var trains = Int(clamping: max(1, (roundTrip + headway - 1) / headway))
        if let most = lineMaximumTrains(id) { trains = min(trains, max(1, most)) }
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        // Decision 168: a high-speed line gets high-speed sets where the
        // game offers them, unless the player chose a type.
        let type = type ?? (line.isHighSpeed && offeredTrainTypes.contains(.highSpeed) ? .highSpeed : nil)
        let price = purchaseCost(of: type, cars: cars)
        let (cost, overflow) = price.amount.multipliedReportingOverflow(by: Int64(trains))
        return LineStaffingPlan(
            headway: headway, roundTripMinutes: roundTrip, trains: trains,
            cost: Money(overflow ? .max : cost), type: type, cars: cars,
            pricePerTrain: price, dailyCostPerTrain: dailyRunningCost(of: type, cars: cars)
        )
    }
}

extension GameSession {
    /// Runs the selected line every `headway` minutes (decision 101), in
    /// one edit: buys the trains ``GameWorld/lineStaffingPlan(_:headway:)``
    /// says it needs, places each where the line's trips start (the berth
    /// its journey starts from, so each is ready to be sent out), assigns
    /// them to the line's own service and sets its target headway at every
    /// level to `headway`. The line sends them out one `headway` apart.
    ///
    /// Without traffic control the trains wait one behind another on that
    /// berth (placement does not mind other trains). Under traffic control
    /// a train that cannot take the berth now stays off the track,
    /// assigned, and the message says so. Refused as a whole when the
    /// money does not reach.
    ///
    /// The trains are of `type` with `cars` cars each when the player chose
    /// them (decision 180); without a choice a high-speed line gets
    /// high-speed sets where the game offers them, and every other the
    /// standard car of one car.
    public func staffSelectedLine(headway: Int64, type chosen: TrainType? = nil, cars: Int = 1) {
        guard let line = requireSelectedLine() else { return }
        guard let plan = world.lineStaffingPlan(line.id, headway: headway, type: chosen, cars: cars), let journey = world.lineJourney(line.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot run yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能行駛：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        perform { world throws(GameError) in
            var draft = world
            var waiting = 0
            // Decision 168: a high-speed line is run with high-speed sets,
            // where the game offers them (not in an era with types of its own).
            for _ in 0..<plan.trains {
                let name = Self.suggestedTrainName(for: draft, in: language)
                let train: Train
                if let type = plan.type {
                    train = try draft.purchaseTrain(named: name, as: type)
                } else {
                    train = try draft.purchaseTrain(named: name)
                }
                if plan.cars > Train.minimumCars { try draft.setTrainCars(train.id, to: plan.cars) }
                var placed = draft
                do throws(GameError) {
                    try Self.placeAtStart(train.id, of: journey, in: &placed)
                    draft = placed
                } catch {
                    waiting += 1
                }
                try draft.assignTrain(train.id, to: line.id, pattern: nil)
            }
            try draft.setLineTargetHeadways(
                line.id, to: TargetHeadways(peak: headway, offPeak: headway, low: headway), pattern: nil
            )
            world = draft
            let first = world.station(id: line.stops[0])?.name ?? line.name
            var text = language.text(
                "\(line.name) now runs \(plan.trains) \(plan.trains == 1 ? "train" : "trains"), "
                    + "\(headwayText(minutes: plan.actualHeadway, in: language).lowercased()), from \(first), for \(plan.cost.moneyText).",
                "\(line.name) 現在有 \(plan.trains) 列車，\(headwayText(minutes: plan.actualHeadway, in: language))，從\(first)出發，花費 \(plan.cost.moneyText)。"
            )
            if waiting > 0 {
                text += language.text(
                    " \(waiting) wait off the track: traffic control holds the platform. Place them there once it is free.",
                    "有 \(waiting) 列因交通控制佔用月台而尚未放上軌道，月台空出後請把它們放到起點站。"
                )
            }
            if let assigned = world.line(id: line.id), world.serviceLevel(of: line.id, at: world.clock.now) == nil,
               case .hours(let open, _) = assigned.window {
                let time = clockText(minuteOfDay: open % 1_440)
                text += language.text(" It opens at \(time).", "\(time) 開始營運。")
            }
            return text
        }
    }
}

// Re-forming a whole line's trains (decision 180): the trains of a line that
// stand waiting for their next trip are taken off, given another type and
// number of cars, put back at the line's start and assigned again, in one
// step. A train that cannot be re-formed is left as it was, with the reason.

extension GameSession {
    /// Where a line's trips start, as ``staffSelectedLine(headway:type:cars:)``
    /// puts a new train: placed on the berth of its journey's start, held
    /// there to be sent out. Throws what placing it throws.
    static func placeAtStart(_ id: TrainID, of journey: LineJourney, in world: inout GameWorld) throws(GameError) {
        try world.placeTrain(id, at: journey.start)
        if case .onEdge(let traversal, let offset) = journey.start,
           let edge = world.network.edge(traversal.edge), offset < edge.length {
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        }
        try world.useTrainPerformanceForMovement(id)
    }

    /// Re-forms the selected line's trains into `cars` cars of `type`
    /// (`nil`: the standard car): each train that stands waiting for its
    /// next trip is unassigned, taken off the track, given the type and the
    /// cars (a refit and the cars added are paid for, decision 180), put
    /// back at the start of the line and assigned to the service it was on.
    /// A train on a trip, or one that cannot be put back, or whose purchase
    /// the balance does not reach, stays as it was; the message names it and
    /// the reason.
    public func reformSelectedLine(type: TrainType?, cars: Int) {
        guard let line = requireSelectedLine() else { return }
        guard let journey = world.lineJourney(line.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot be re-formed yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能改編組：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        var changed = 0
        var left: [String] = []
        var paid = Money.zero
        do throws(GameError) {
            let summary = try performEdit { world throws(GameError) in
                let balance = world.economy.balance
                for id in line.assignedTrains {
                    guard let train = world.train(id: id) else { continue }
                    if train.execution != nil {
                        left.append(language.text("\(train.name) (on a trip)", "\(train.name)（正在行駛）"))
                        continue
                    }
                    if train.type == type && train.cars == cars { continue }
                    var attempt = world
                    do throws(GameError) {
                        let pattern = attempt.assignedPattern(of: id)
                        try attempt.unassignTrain(id)
                        if train.position != nil { try attempt.unplaceTrain(id) }
                        if train.type != type {
                            try attempt.setTrainType(id, to: type)
                            if let performance = type?.performance { try attempt.setTrainPerformance(id, to: performance) }
                        }
                        if train.cars != cars { try attempt.setTrainCars(id, to: cars) }
                        try Self.placeAtStart(id, of: journey, in: &attempt)
                        try attempt.assignTrain(id, to: line.id, pattern: pattern)
                        world = attempt
                        changed += 1
                    } catch {
                        left.append("\(train.name) (\(error.playerMessage(in: language)))")
                    }
                }
                paid = balance - world.economy.balance
                let name = Train.typeText(type, in: language)
                return language.text(
                    "\(line.name): \(changed) \(changed == 1 ? "train" : "trains") re-formed into \(Train.carsText(cars, in: language)) of \(name), for \(paid.moneyText).",
                    "\(line.name)：\(changed) 列車改編為 \(Train.carsText(cars, in: language))的\(name)，花費 \(paid.moneyText)。"
                )
            }
            var text = changed == 0 && left.isEmpty
                ? language.text("\(line.name)'s trains are already so.", "\(line.name) 的列車已經是這個編組。")
                : summary
            if !left.isEmpty {
                text += language.text(" Left as they were: ", " 沒有改的：") + left.joined(separator: language.text(", ", "、")) + "."
            }
            message = StatusMessage(kind: changed > 0 || left.isEmpty ? .success : .failure, text: text)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }
}
