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
        // game offers them, unless the player chose a type. An era has no
        // standard car (decision 153): its own type, as a train bought there
        // is, so re-forming with the line's default keeps it.
        let type = type ?? (!offersStandardCar ? offeredTrainTypes.first
            : line.isHighSpeed && offeredTrainTypes.contains(.highSpeed) ? .highSpeed : nil)
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
    /// berth (placement does not mind other trains). A train that cannot be
    /// placed there (under traffic control, the berth is taken; or it is too
    /// long to stand there) stays off the track and is not assigned: a trip
    /// starts from the track, so it would never be sent out and still pay
    /// its running costs (decision 101, a later fix). The message says how
    /// many and why. Refused as a whole when the money does not reach.
    ///
    /// The trains are of `type` with `cars` cars each when the player chose
    /// them (decision 180); without a choice a high-speed line gets
    /// high-speed sets where the game offers them, and every other the
    /// standard car of one car.
    public func staffSelectedLine(headway: Int64, type chosen: TrainType? = nil, cars: Int = 1) {
        guard let line = requireSelectedLine() else { return }
        guard let plan = world.lineStaffingPlan(line.id, headway: headway, type: chosen, cars: cars), world.lineJourney(line.id) != nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot run yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能行駛：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        perform(.staffLine(line.id, headway: headway, type: chosen, cars: cars, language: language)) { outcome, _, world in
            let (held, unfit) = (outcome.held, outcome.unfit)
            let first = world.station(id: line.stops[0])?.name ?? line.name
            let running = plan.trains - held - unfit
            var text: String
            if running == plan.trains {
                text = language.text(
                    "\(line.name) now runs \(plan.trains) \(plan.trains == 1 ? "train" : "trains"), "
                        + "\(headwayText(minutes: plan.actualHeadway, in: language).lowercased()), from \(first), for \(plan.cost.moneyText).",
                    "\(line.name) 現在有 \(plan.trains) 列車，\(headwayText(minutes: plan.actualHeadway, in: language))，從\(first)出發，花費 \(plan.cost.moneyText)。"
                )
            } else {
                // Decision 101, a later fix: the trains left off the track
                // are bought but not assigned, so they cost nothing to run.
                text = language.text(
                    "Bought \(plan.trains) \(plan.trains == 1 ? "train" : "trains") for \(plan.cost.moneyText); "
                        + "\(line.name) now runs \(running) \(running == 1 ? "train" : "trains") from \(first).",
                    "買了 \(plan.trains) 列車，花費 \(plan.cost.moneyText)；\(line.name) 現在有 \(running) 列車從\(first)出發。"
                )
                if held > 0 {
                    text += language.text(
                        " \(held) more \(held == 1 ? "stays" : "stay") off the track, not assigned to the line: "
                            + "traffic control lets only one train wait at \(first)'s platform. "
                            + "Once it is free, place \(held == 1 ? "it" : "them") at \(first) and assign \(held == 1 ? "it" : "them") to \(line.name).",
                        "另外 \(held) 列沒有放上軌道，也沒有配屬給路線：交通控制下\(first)的月台一次只能停一列。"
                            + "月台空出後，請把它們放到\(first)，再配屬給\(line.name)。"
                    )
                }
                if unfit > 0 {
                    text += language.text(
                        " \(unfit) more \(unfit == 1 ? "stays" : "stay") off the track, not assigned to the line: "
                            + "\(unfit == 1 ? "it is" : "they are") too long to stand at \(first). Fewer cars would fit.",
                        "另外 \(unfit) 列沒有放上軌道，也沒有配屬給路線：列車太長，\(first)停不下。減少節數就停得下。"
                    )
                }
            }
            if let assigned = world.line(id: line.id), world.serviceLevel(of: line.id, at: world.clock.now) == nil,
               case .hours(let open, _) = assigned.window {
                let time = clockText(minuteOfDay: open % 1_440)
                text += language.text(" It opens at \(time).", "\(time) 開始營運。")
            }
            if outcome.highSpeed { text += language.nowHighSpeedText(line.name) }
            return text
        }
    }

    /// Runs line `id` every `headway` minutes in `world`, as
    /// ``staffSelectedLine(headway:type:cars:)`` does, naming the trains in
    /// `language`: how many trains were left off the track because the
    /// berth was held, and how many because they were too long to stand
    /// there.
    static func staff(
        _ id: LineID, headway: Int64, type chosen: TrainType?, cars: Int, in world: inout GameWorld, language: DisplayLanguage
    ) throws(GameError) -> (held: Int, unfit: Int) {
        // Decision 168 rule 7: high-speed sets on a line that runs nothing
        // else make it a high-speed line in the same edit; planned at high
        // speed first, the plan counts the trains its faster trips need.
        if chosen == .highSpeed, let line = world.line(id: id), line.performance == .standard, !line.isFreight,
           line.assignedTrains.allSatisfy({ world.train(id: $0)?.type == .highSpeed }) {
            try world.setLinePerformance(id, to: .highSpeed)
        }
        guard let plan = world.lineStaffingPlan(id, headway: headway, type: chosen, cars: cars) else {
            throw .unknownLine(id)
        }
        let left = try addTrains(plan.trains, of: plan.type, cars: plan.cars, to: id, in: &world, language: language)
        try world.setLineTargetHeadways(id, to: TargetHeadways(peak: headway, offPeak: headway, low: headway), pattern: nil)
        return left
    }

    /// Buys `count` trains of `type` with `cars` cars, places each where
    /// line `id`'s trips start and assigns it to the line's own service, as
    /// ``staff(_:headway:type:cars:in:language:)`` does: a train that
    /// cannot be placed there stays off the track and is not assigned.
    /// Returns how many were left off because the berth was held and how
    /// many because they were too long (decision 194, later: the line
    /// card's "run more trains" buys only those its headway lacks).
    static func addTrains(
        _ count: Int, of type: TrainType?, cars: Int, to id: LineID, in world: inout GameWorld, language: DisplayLanguage
    ) throws(GameError) -> (held: Int, unfit: Int) {
        guard let journey = world.lineJourney(id) else { throw .unknownLine(id) }
        // Trains left off the track: the berth held under traffic
        // control, or too long to stand there.
        var held = 0, unfit = 0
        // Decision 168: a high-speed line is run with high-speed sets,
        // where the game offers them (not in an era with types of its own).
        for _ in 0..<max(0, count) {
            let name = Self.suggestedTrainName(for: world, in: language)
            let train: Train
            if let type {
                train = try world.purchaseTrain(named: name, as: type)
            } else {
                train = try world.purchaseTrain(named: name)
            }
            if cars > Train.minimumCars { try world.setTrainCars(train.id, to: cars) }
            var placed = world
            do throws(GameError) {
                try Self.placeAtStart(train.id, of: journey, in: &placed)
                world = placed
            } catch {
                if case .trackReserved = error { held += 1 } else { unfit += 1 }
                continue
            }
            try world.assignTrain(train.id, to: id, pattern: nil)
        }
        return (held, unfit)
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
        guard world.lineJourney(line.id) != nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot be re-formed yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能改編組：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        do throws(GameError) {
            let before = world
            let outcome = try performCommand(.edit(.reformLine(line.id, type: type, cars: cars, language: language)))
            let (changed, left) = (outcome.number, outcome.left)
            let summary: String = {
                let paid = before.economy.balance - world.economy.balance
                let name = Train.typeText(type, in: language)
                return language.text(
                    "\(line.name): \(changed) \(changed == 1 ? "train" : "trains") re-formed into \(Train.carsText(cars, in: language)) of \(name), for \(paid.moneyText).",
                    "\(line.name)：\(changed) 列車改編為 \(Train.carsText(cars, in: language))的\(name)，花費 \(paid.moneyText)。"
                )
            }()
            var text = changed == 0 && left.isEmpty
                ? language.text("\(line.name)'s trains are already so.", "\(line.name) 的列車已經是這個編組。")
                : summary
            if !left.isEmpty {
                text += language.text(" Left as they were: ", " 沒有改的：") + left.joined(separator: language.text(", ", "、")) + "."
            }
            if outcome.highSpeed { text += language.nowHighSpeedText(line.name) }
            message = StatusMessage(kind: changed > 0 || left.isEmpty ? .success : .failure, text: text)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// Re-forms line `id`'s waiting trains in `world`, as
    /// ``reformSelectedLine(type:cars:)`` does: how many were, and those
    /// left as they were, with the reason in `language`.
    static func reform(
        _ id: LineID, type: TrainType?, cars: Int, in world: inout GameWorld, language: DisplayLanguage
    ) throws(GameError) -> (changed: Int, left: [String]) {
        guard let line = world.line(id: id) else { throw .unknownLine(id) }
        guard let journey = world.lineJourney(id) else { throw .unknownLine(id) }
        var changed = 0
        var left: [String] = []
        for trainID in line.assignedTrains {
            guard let train = world.train(id: trainID) else { continue }
            if train.execution != nil {
                left.append(language.text("\(train.name) (on a trip)", "\(train.name)（正在行駛）"))
                continue
            }
            if train.type == type && train.cars == cars { continue }
            var attempt = world
            do throws(GameError) {
                let pattern = attempt.assignedPattern(of: trainID)
                try attempt.unassignTrain(trainID)
                if train.position != nil { try attempt.unplaceTrain(trainID) }
                // Cars taken off go first, so the new type is paid
                // for the cars kept only (a later fix); cars added
                // come after, at the new type's car price.
                if cars < train.cars { try attempt.setTrainCars(trainID, to: cars) }
                if train.type != type {
                    try attempt.setTrainType(trainID, to: type)
                    try attempt.runAsItsType(trainID, ranAs: train.type)
                }
                if cars > train.cars { try attempt.setTrainCars(trainID, to: cars) }
                try Self.placeAtStart(trainID, of: journey, in: &attempt)
                try attempt.assignTrain(trainID, to: id, pattern: pattern)
                world = attempt
                changed += 1
            } catch {
                left.append("\(train.name) (\(error.playerMessage(in: language)))")
            }
        }
        return (changed, left)
    }
}
