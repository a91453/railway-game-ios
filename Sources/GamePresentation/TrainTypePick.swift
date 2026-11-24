import GameCore

// Decision 960 (TRAIN-TYPE-PICK, second part; the author's report on
// TestFlight 145): a train's type could be changed only while it was off
// the track, and a line's trains only while the line's own service ran
// none, so once a line ran there was nowhere to change its trains. Now a
// train on the track changes type when it is not on a trip, and a line
// that runs changes its trains' type keeping their cars.

extension GameSession {
    /// Changes train `id`'s type wherever it is (decision 960): off the
    /// track as ``setTrainType(_:to:)`` does; on the track, when it is not
    /// on a trip, taken off, changed and put back where it stood (on a
    /// line, back on its service); on a trip, refused with a word on when.
    public func changeTrainType(_ id: TrainID, to type: TrainType?) {
        guard let train = world.train(id: id) else { return }
        guard train.position != nil else {
            setTrainType(id, to: type)
            return
        }
        if train.execution != nil {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(train.name) is on a trip: change its type when it waits for its next one.",
                "\(train.name) 正在行駛，等它在站上等下一趟時再換車型。"
            ))
            return
        }
        perform(.refitTrain(id, type)) { outcome, before, world in
            let text = Train.typeText(type, in: language)
            var said = language.text("\(train.name) now has \(text).", "\(train.name) 現在是 \(text)。")
            let refit = before.economy.balance - world.economy.balance
            if refit > .zero {
                said += language.text(" The refit cost \(refit.moneyText).", "改裝費 \(refit.moneyText)。")
            }
            if outcome.highSpeed, let line = world.assignedLine(of: id).flatMap(world.line(id:)) {
                said += language.nowHighSpeedText(line.name)
            }
            said += world.guidewayFirstHint(for: type, in: language) ?? ""
            return said
        }
    }

    /// Takes train `id`, on the track and on no trip, off it, gives it
    /// `type` and puts it back where it stood (decision 960); on a line,
    /// back on the service it ran, at the start of the line when where it
    /// stood will not take it.
    static func refit(_ id: TrainID, to type: TrainType?, in world: inout GameWorld) throws(GameError) {
        guard let train = world.train(id: id) else { throw .unknownTrain(id) }
        guard let position = train.position else {
            try world.setTrainType(id, to: type)
            try world.runAsItsType(id, ranAs: train.type)
            return
        }
        let line = world.assignedLine(of: id)
        let pattern = world.assignedPattern(of: id)
        if line != nil { try world.unassignTrain(id) }
        if world.train(id: id)?.position != nil { try world.unplaceTrain(id) }
        try world.setTrainType(id, to: type)
        try world.runAsItsType(id, ranAs: train.type)
        // The track it held was let go when it was taken off.
        var back = world
        if (try? back.placeTrain(id, at: position)) != nil {
            world = back
        } else if let line, let journey = world.lineJourney(line) {
            try placeAtStart(id, of: journey, in: &world)
        } else {
            try world.placeTrain(id, at: position)
        }
        if let line { try world.assignTrain(id, to: line, pattern: pattern) }
    }
}

// Decision 960, buy first, assign later (the author, 2026-11-24: 「先選取
// 購買列車 再排到指定路線」): a train bought from the train types stands
// off the track; the fleet gives it a line, which puts it where the line's
// trips start, as a line's own new trains are put (``GameSession/addTrains``),
// and assigns it, in one edit. Where it will not stand, it stays in the
// fleet with no line, and the message says why.

extension GameSession {
    /// Whether the fleet offers train `id` a line: off the track, with no
    /// line, and a line to give it.
    public func offersAssignToLine(for id: TrainID) -> Bool {
        guard let train = world.train(id: id) else { return false }
        return train.position == nil && world.assignedLine(of: id) == nil && !assignToLineChoices(for: id).isEmpty
    }

    /// The lines train `id` may be given from the fleet: each with two
    /// stops or more, not a ring (each way of a ring needs its own trains
    /// facing its own way, as ``GameWorld/lineStaffingPlan(_:headway:type:cars:)``
    /// says).
    public func assignToLineChoices(for id: TrainID) -> [ServiceLine] {
        world.lines.filter { $0.stops.count >= 2 && !$0.isRing }
    }

    /// Puts train `id`, off the track, where line `line`'s trips start and
    /// assigns it to the line's own service, in one edit. Where the berth
    /// is held or the train is too long to stand there, nothing changes
    /// and the message says why (decision 584's words).
    public func assignUnplacedTrain(_ id: TrainID, to line: LineID) {
        guard let train = world.train(id: id), let target = world.line(id: line) else { return }
        let first = target.stops.first.flatMap { world.station(id: $0)?.name } ?? target.name
        var trial = world
        do throws(GameError) {
            try Self.placeForLine(id, of: line, in: &trial)
        } catch {
            let off = language.text(
                "\(train.name) stays in the fleet, not assigned to \(target.name): ",
                "\(train.name) 留在車隊，沒有配屬給\(target.name)："
            )
            switch error {
            case .trackReserved:
                message = StatusMessage(kind: .failure, text: off + (world.lineStartBlockedText(line, in: language)?.text ?? language.text(
                    "\(first)'s platform is taken. Once it is free, assign it again.",
                    "\(first)的月台被佔著。月台空出後再配屬一次。"
                )))
                return
            case .invalidTrainPosition:
                message = StatusMessage(kind: .failure, text: off + language.text(
                    "it is too long to stand at \(first). Fewer cars would fit.",
                    "列車太長，\(first)停不下。減少節數就停得下。"
                ))
                return
            default:
                break // Refused below, in the edit's own words.
            }
        }
        perform(.assignUnplacedTrain(id, line)) { outcome, _, world in
            var said = language.text(
                "\(train.name) now runs for \(target.name), from \(first).",
                "\(train.name) 已配屬給\(target.name)，從\(first)出發。"
            )
            if outcome.highSpeed { said += language.nowHighSpeedText(target.name) }
            return said
        }
    }

    /// Places train `id`, off the track, where line `line`'s trips start,
    /// as ``addTrains(_:of:cars:to:in:language:orAtTheFarEnd:)`` places a
    /// new one with `orAtTheFarEnd`: at its first stop's berth, else at the
    /// far end's, else beside either (decision 572). Throws what placing
    /// it at the first stop threw when none takes it.
    static func placeForLine(_ id: TrainID, of line: LineID, in world: inout GameWorld) throws(GameError) {
        guard let journey = world.lineJourney(line) else { throw .unknownLine(line) }
        var placed = world
        do throws(GameError) {
            try placeAtStart(id, of: journey, in: &placed)
            world = placed
        } catch {
            guard case .trackReserved = error else { throw error }
            let back = farEndJourney(of: line, in: world)
            var far = world
            if let back, (try? placeAtStart(id, of: back, in: &far)) != nil {
                world = far
            } else if let beside = placeBeside(id, of: line, journeys: [journey, back].compactMap { $0 }, in: world) {
                world = beside
            } else {
                throw error
            }
        }
    }
}
