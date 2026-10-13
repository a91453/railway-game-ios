import GameCore

// TestFlight 54.1: a player could not find how to put a train on a line or
// what a train standing still needed. What the train card and the line
// panel say about it, and the menus that do it.

extension GameWorld {
    /// What the player does next with train `id`, or `nil` when it needs
    /// nothing: an unplaced train is placed at a station, and a placed one
    /// standing with no line, no service and no path is given a line or
    /// sent somewhere.
    public func trainNextStepText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let train = train(id: id) else { return nil }
        guard train.position != nil else {
            return language.text(
                "Next: select a station with a free platform, then tap Place \(train.name) Here.",
                "下一步：選一個月台空著的車站，按「把 \(train.name) 放在這裡」。"
            )
        }
        guard train.execution == nil, !train.hasPathAhead, assignedLine(of: id) == nil else { return nil }
        return language.text(
            "Next: give it a line with Assign to a Line below or in the Lines panel, or select a station and tap Send \(train.name) Here.",
            "下一步：用下方的「配屬路線」或在路線面板配屬路線，或選一個車站按「派 \(train.name) 到這裡」。"
        )
    }

    /// A warning when traffic control holds line `id`'s own service to
    /// fewer trains than it could run without it (``lineMaximumTrains(_:pattern:)``,
    /// decision 62): single track with nowhere to pass. `nil` otherwise.
    public func lineCapacityWarning(_ id: LineID, in language: DisplayLanguage) -> String? {
        guard isTrafficControlEnabled, let journey = lineJourney(id), let most = lineMaximumTrains(id) else { return nil }
        let eachWay = Int(clamping: max(1, journey.roundTripMinutes / ServiceLine.minimumHeadwayMinutes))
        guard most < (journey.isRing ? eachWay * 2 : eachWay) else { return nil }
        return language.text(
            "Single track with no passing station: under traffic control the line runs at most \(most) \(most == 1 ? "train" : "trains"). Add a second platform track at a station on the way, or double the track.",
            "單線又沒有會車站，交通管制下只能跑 \(most) 列：在中間站加第二股月台，或改成雙線。"
        )
    }
}

extension GameSession {
    /// The lines, in the world's order, to give a train one.
    public var lineMenuChoices: [MenuChoice<LineID>] {
        world.lines.map { MenuChoice(id: $0.id, title: $0.name) }
    }

    /// The trains a line can be given from its panel: those on the track
    /// with no line and no service of their own. An unplaced train is left
    /// out: GameCore lets a line take it, but it would never leave.
    public var unassignedTrainMenuChoices: [MenuChoice<TrainID>] {
        world.trains.filter { train in
            train.position != nil && train.execution == nil && world.assignedLine(of: train.id) == nil
        }
        .map { MenuChoice(id: $0.id, title: $0.name) }
    }
}
