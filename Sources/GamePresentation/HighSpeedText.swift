import GameCore

// High-speed rail in the session and its text (ARCHITECTURE decision 168).
// A high-speed line is not declared: it is a line planned at high speed
// (``ServiceLine/isHighSpeed``), which the line menu's "High-speed rail"
// makes, and so does a high-speed set put on a line that runs nothing else.
// What the session adds here is the second of those, and the words.

extension GameWorld {
    /// What the fares page says of high-speed trips (decision 663, the Mac
    /// playtest's D9: the High Speed Rail demo's page showed only the
    /// distance steps, "32 km and more NT$24", though a trip from Nangang
    /// to Zuoying pays the real NT$1,530): with a table of real fares
    /// (decision 325), its cheapest and dearest fare and the pair that pays
    /// the dearest; without one, a world with a high-speed line, the
    /// kilometre fare; otherwise `nil`.
    public func highSpeedFareText(in language: DisplayLanguage) -> String? {
        let table = accounts.highSpeedFares
        if let cheapest = table.min(by: { $0.fare < $1.fare }), let dearest = table.max(by: { $0.fare < $1.fare }) {
            let from = station(id: dearest.from)?.name ?? "", to = station(id: dearest.to)?.name ?? ""
            return language.text(
                "High-speed riders pay the fare between their two stations, not the fares above: \(cheapest.fare.wholeText) to \(dearest.fare.wholeText) (\(from)–\(to)).",
                "搭高鐵的旅客照兩站之間的高鐵票價付，不用上面的票價：\(cheapest.fare.wholeText) 到 \(dearest.fare.wholeText)（\(from)－\(to)）。"
            )
        }
        guard lines.contains(where: \.isHighSpeed) else { return nil }
        let perKilometre = Money(HighSpeed.centsPerKilometre).centsText
        return language.text(
            "High-speed riders pay \(perKilometre) a kilometre, or the fare above when it is more.",
            "搭高鐵路線的旅客每公里付 \(perKilometre)；上面的票價比較高時付上面的。"
        )
    }
}

extension GameWorld {
    /// What a high-speed line is paid and filled by, as the line's panel
    /// says it: the fare, where the trips come from and where they go.
    public func highSpeedLineHelp(in language: DisplayLanguage) -> String {
        let perKilometre = Money(HighSpeed.centsPerKilometre).centsText
        let radius = HighSpeed.hinterlandRadius / WorldCoordinate.unitsPerMetre / 1_000
        let near = HighSpeed.nearDistance / WorldCoordinate.unitsPerMetre / 1_000
        let full = HighSpeed.fullDistance / WorldCoordinate.unitsPerMetre / 1_000
        return language.text(
            "High-speed line: riders pay \(perKilometre) a kilometre, never less than the network's fare. Its stations draw travellers from within \(radius) km "
                + "to the other high-speed stations: none for trips under \(near) km, the most from \(full) km. Run high-speed trains on it.",
            "高鐵路線：每公里 \(perKilometre)，不低於一般路網的票價。車站吸引 \(radius) 公里內的旅客前往其他高鐵站："
                + "\(near) 公里內沒人搭，\(full) 公里以上搭的人最多。請用高鐵列車。"
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
            parts.append("\(station.name) \((stationDemand(of: stop)?.hinterland ?? 0).groupedText)")
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
        return !assigned.isEmpty && assigned.allSatisfy { train(id: $0)?.type?.isHighSpeed == true }
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
        text(" \(line) is now a high-speed line.", "\(line) 現在是高鐵路線。")
    }
}
