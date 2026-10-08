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
    public func lineStaffingPlan(_ id: LineID, headway: Int64) -> LineStaffingPlan? {
        guard headway >= ServiceLine.minimumHeadwayMinutes, let line = line(id: id), !line.isRing,
              let journey = lineJourney(id)
        else { return nil }
        let roundTrip = journey.roundTripMinutes
        var trains = Int(clamping: max(1, (roundTrip + headway - 1) / headway))
        if let most = lineMaximumTrains(id) { trains = min(trains, max(1, most)) }
        let (cost, overflow) = economy.costs.train.amount.multipliedReportingOverflow(by: Int64(trains))
        return LineStaffingPlan(
            headway: headway, roundTripMinutes: roundTrip, trains: trains,
            cost: Money(overflow ? .max : cost)
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
    public func staffSelectedLine(headway: Int64) {
        guard let line = requireSelectedLine() else { return }
        guard let plan = world.lineStaffingPlan(line.id, headway: headway), let journey = world.lineJourney(line.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line.name)'s trains cannot run yet: build track joining its stations, with a platform at each.",
                "\(line.name) 的列車還不能行駛：請先鋪設連接各站的軌道，並在每站設置月台。"
            ))
            return
        }
        perform { world throws(GameError) in
            var draft = world
            var waiting = 0
            for _ in 0..<plan.trains {
                let train = try draft.purchaseTrain(named: Self.suggestedTrainName(for: draft, in: language))
                var placed = draft
                do throws(GameError) {
                    try placed.placeTrain(train.id, at: journey.start)
                    if case .onEdge(let traversal, let offset) = journey.start,
                       let edge = placed.network.edge(traversal.edge), offset < edge.length {
                        try placed.setTrainContinuation(train.id, along: [], stoppingAt: offset)
                    }
                    try placed.useTrainPerformanceForMovement(train.id)
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
