import GameCore

/// ARCHITECTURE decision 327: removing a line sells its trains with it, and
/// a train on no line is sold where it stands, so no train is left on the
/// track holding a platform or track that is to be taken down.
extension GameWorld {
    /// Whether train `id` can be sold from the fleet list or the map
    /// (decision 327): it is on no line. One on the track, or running a
    /// timetable of its own, is stopped and taken off first.
    public func canSellTrainWhereItStands(_ id: TrainID) -> Bool {
        train(id: id) != nil && assignedLine(of: id) == nil
    }

    /// What removing line `id` sells (decision 327): its trains, and what
    /// they bring in all (``trainSaleQuote(_:)``).
    public func lineRemovalSale(_ id: LineID) -> (trains: Int, proceeds: Money) {
        let trains = line(id: id)?.assignedTrains ?? []
        return (trains.count, trains.reduce(Money.zero) { $0 + trainSaleQuote($1) })
    }

    /// The train standing on no line and running no service that refused
    /// `error` (decision 327): one that never moves on by itself, so the
    /// track it holds stays held until it is sold or taken off. `nil` for
    /// any other refusal.
    public func idleTrainInTheWay(of error: GameError) -> Train? {
        let candidate: Train?
        switch error {
        case .trackReserved(let id):
            candidate = train(id: id)
        case .trackEdgeInUse(let edge):
            candidate = trains.first { train in
                if case .onEdge(let traversal, _)? = train.position, traversal.edge == edge { return true }
                return train.trailEdges.contains(edge)
            }
        default:
            candidate = nil
        }
        guard let train = candidate, train.execution == nil, assignedLine(of: train.id) == nil else { return nil }
        return train
    }
}

extension GameSession {
    /// Sells train `id` in `world` where it stands (decision 327): its own
    /// service stopped, then off the track, then sold
    /// (``GameWorld/sellTrain(_:)``). A line's train is taken off its line
    /// only when `offLine`; otherwise it is refused, as selling refuses it.
    static func sellWhereItStands(_ id: TrainID, offLine: Bool, in world: inout GameWorld) throws(GameError) {
        guard let train = world.train(id: id) else { throw .unknownTrain(id) }
        if world.assignedLine(of: id) != nil {
            guard offLine else { throw .trainInService(id) }
            try world.unassignTrain(id)
        }
        if train.execution != nil { try world.stopTrainService(id) }
        if train.position != nil { try world.unplaceTrain(id) }
        try world.sellTrain(id)
    }

    /// Removes line `id` from `world` and sells its trains (decision 327).
    /// Returns how many were sold.
    static func removeLineSellingTrains(_ id: LineID, in world: inout GameWorld) throws(GameError) -> Int {
        guard let line = world.line(id: id) else { throw .unknownLine(id) }
        let trains = line.assignedTrains
        try world.removeLine(id)
        for train in trains {
            try sellWhereItStands(train, offLine: true, in: &world)
        }
        return trains.count
    }

    /// How many trains removing the selected line sells, and what they
    /// bring (decision 327): what its confirmation says.
    public var selectedLineRemovalSale: (trains: Int, proceeds: Money)? {
        selectedLineID.map { world.lineRemovalSale($0) }
    }
}
