import GameCore

// High-speed rail in the session and its text (ARCHITECTURE decision 168).
// A high-speed line is not declared: it is a line planned at high speed
// (``ServiceLine/isHighSpeed``), which the line menu's "High-speed rail"
// makes, and so does a high-speed set put on a line that runs nothing else.
// What the session adds here is the second of those, and the words.

extension GameWorld {
    /// What a high-speed line is paid and filled by, as the line's panel
    /// says it: the fare, where the trips come from and where they go.
    public func highSpeedLineHelp(in language: DisplayLanguage) -> String {
        let perKilometre = Money(HighSpeed.centsPerKilometre).centsText
        let radius = HighSpeed.hinterlandRadius / WorldCoordinate.unitsPerMetre / 1_000
        let near = HighSpeed.nearDistance / WorldCoordinate.unitsPerMetre / 1_000
        let full = HighSpeed.fullDistance / WorldCoordinate.unitsPerMetre / 1_000
        return language.text(
            "High-speed line: riders pay \(perKilometre) a kilometre, or the network's fare if that is more. Its stations draw intercity trips from the people within \(radius) km of them, "
                + "to the other high-speed stations: none under \(near) km, all from \(full) km. Run it with high-speed sets.",
            "高鐵路線：乘客付每公里 \(perKilometre)，路網的票價比較高就付路網的。它的車站從 \(radius) 公里內的居民與就業取得城際旅次，"
                + "去其他高鐵站：\(near) 公里內沒有，\(full) 公里起全部。列車請用高鐵車種。"
        )
    }

    /// Where a high-speed line's trips come from: each of its stations with
    /// the people within reach of it, or `nil` for a line that is not a
    /// high-speed line.
    public func highSpeedLineText(_ id: LineID, in language: DisplayLanguage) -> String? {
        guard let line = line(id: id), line.isHighSpeed else { return nil }
        var seen = Set<StationID>()
        var parts: [String] = []
        for stop in line.stops where seen.insert(stop).inserted {
            guard let station = station(id: stop) else { continue }
            parts.append("\(station.name) \(Money(stationDemand(of: stop)?.hinterland ?? 0).displayText)")
        }
        let radius = HighSpeed.hinterlandRadius / WorldCoordinate.unitsPerMetre / 1_000
        let list = parts.joined(separator: " · ")
        return language.text("People within \(radius) km: \(list)", "\(radius) 公里內的人口：\(list)")
    }

    /// Whether line `id` is a passenger line that runs high-speed sets and
    /// nothing else: every train assigned to it is one, and there is one.
    func runsHighSpeedSetsOnly(_ id: LineID) -> Bool {
        guard let line = line(id: id), !line.isFreight else { return false }
        let assigned = line.assignedTrains
        return !assigned.isEmpty && assigned.allSatisfy { train(id: $0)?.type == .highSpeed }
    }

    /// Plans line `id` at high speed when it runs high-speed sets and
    /// nothing else and is still planned at the standard performance: the
    /// player who puts a high-speed set on a new line has built a high-speed
    /// line, without a second step (decision 168). A line the player has
    /// already given a performance keeps it. Whether it changed the line.
    mutating func planAtHighSpeedWhenRunByHighSpeedSets(_ id: LineID) throws(GameError) -> Bool {
        guard let line = line(id: id), line.performance == .standard, runsHighSpeedSetsOnly(id) else { return false }
        try setLinePerformance(id, to: .highSpeed)
        return true
    }

    /// Lets train `id`, just given another type, run as that type does
    /// (``TrainType/performance``, or the standard performance) where it ran
    /// as its old type `old` did: an EMU3000 made a high-speed set runs at
    /// the set's 300 km/h, a set made a type A at 110 (decisions 168, 169).
    /// A performance the player set otherwise is kept.
    mutating func runAsItsType(_ id: TrainID, ranAs old: TrainType?) throws(GameError) {
        guard let train = train(id: id) else { throw .unknownTrain(id) }
        let next = train.type?.performance ?? .standard
        guard train.performance == (old?.performance ?? .standard), train.performance != next else { return }
        try setTrainPerformance(id, to: next)
    }
}

extension DisplayLanguage {
    /// What is said after a line has been planned at high speed because of
    /// the set put on it (see ``GameWorld/planAtHighSpeedWhenRunByHighSpeedSets(_:)``).
    func nowHighSpeedText(_ line: String) -> String {
        text(" \(line) is planned at high speed now: a high-speed line.", "\(line) 現在以高鐵規劃，是高鐵路線。")
    }
}
