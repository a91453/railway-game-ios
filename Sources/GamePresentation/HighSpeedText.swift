import GameCore

// High-speed rail in the session and its text (ARCHITECTURE decision 168):
// the line's switch goes through GameCore's `setLineHighSpeed`, and the text
// is derived from the world.

extension GameWorld {
    /// What the switch of a high-speed line says it does, before and after
    /// it is on: the fare, where the trips come from and where they go.
    public func highSpeedLineHelp(in language: DisplayLanguage) -> String {
        let fare = Money(HighSpeed.minimumFareDollars * 100).moneyText
        let perKilometre = Money(HighSpeed.centsPerKilometre).centsText
        let radius = HighSpeed.hinterlandRadius / WorldCoordinate.unitsPerMetre / 1_000
        let near = HighSpeed.nearDistance / WorldCoordinate.unitsPerMetre / 1_000
        let full = HighSpeed.fullDistance / WorldCoordinate.unitsPerMetre / 1_000
        return language.text(
            "Riders pay \(fare) or \(perKilometre) a kilometre, whichever is more. Its stations draw intercity trips from the people within \(radius) km of them, "
                + "to the other high-speed stations: none under \(near) km, all from \(full) km. Give its trains the high-speed type.",
            "乘客付 \(fare) 或每公里 \(perKilometre)，取較高的。它的車站從 \(radius) 公里內的居民與就業取得城際旅次，"
                + "去其他高鐵站：\(near) 公里內沒有，\(full) 公里起全部。列車請選高鐵車種。"
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
}

extension GameSession {
    /// Makes the selected line a high-speed line, or an ordinary one again
    /// (decision 168). A line made one that still plans its journeys at the
    /// standard performance plans them at ``TrainPerformance/highSpeed``,
    /// in the same edit, so Undo takes both back.
    public func setSelectedLineHighSpeed(_ isHighSpeed: Bool) {
        guard let line = requireSelectedLine(), line.isHighSpeed != isHighSpeed else { return }
        perform { world throws(GameError) in
            try world.setLineHighSpeed(line.id, to: isHighSpeed)
            if isHighSpeed, line.performance == .standard {
                try world.setLinePerformance(line.id, to: .highSpeed)
            }
            return isHighSpeed
                ? language.text("\(line.name) is a high-speed line.", "\(line.name) 改為高鐵路線。")
                : language.text("\(line.name) is an ordinary line again.", "\(line.name) 改回一般路線。")
        }
    }
}
