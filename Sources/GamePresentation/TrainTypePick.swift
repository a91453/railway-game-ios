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
