import GameCore

// Choosing how trains and lines run (Stage C3). Stage W2c gave every train
// and every line a TrainPerformance, standard until a command changes it, and
// left choosing one to a later screen. The choices are the owner's
// references: the Railway reference's presets (`PERF_*`, already in
// GameCore), named after the trains it picks them for, and the metro game's
// design speeds (`Ci/`: the line modal's 設计时速, `LINE_SPEED_ALL_NON_SG`).
// Nothing here is a rule: GameCore checks every performance.

/// The performances the app offers by name: GameCore's presets, each named
/// after the train the Railway reference picks it for (`PERF_RULES`,
/// `PERF_BY_TYPE`), and the metro game's.
public enum PerformancePreset: CaseIterable, Hashable, Sendable {
    case standard
    case metro
    case local
    case ordinary
    case semiExpress
    case express
    case emu3000
    case pushPull
    case taroko
    case puyuma
    case dieselExpress
    case dieselRailcar
    case forestRailway
    case highSpeed

    public var performance: TrainPerformance {
        switch self {
        case .standard: .standard
        case .metro: .metro
        case .local: .local
        case .ordinary: .ordinary
        case .semiExpress: .semiExpress
        case .express: .express
        case .emu3000: .emu3000
        case .pushPull: .pushPull
        case .taroko: .tiltingTaroko
        case .puyuma: .tiltingPuyuma
        case .dieselExpress: .dieselExpress
        case .dieselRailcar: .dieselRailcar
        case .forestRailway: .forestRailway
        case .highSpeed: .highSpeed
        }
    }

    /// The train's name, as the reference's rules match it (`/區間/`,
    /// `/自強/`, `/\(太/` and so on); the metro game's for ``metro``.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .standard: language.text("Standard", "標準")
        case .metro: language.text("Metro", "捷運")
        case .local: language.text("Local EMU", "區間車")
        case .ordinary: language.text("Ordinary", "普通車")
        case .semiExpress: language.text("Chu-Kuang / Fu-Hsing", "莒光／復興")
        case .express: language.text("Tze-Chiang", "自強")
        case .emu3000: "EMU3000"
        case .pushPull: language.text("Push-pull Tze-Chiang", "推拉式自強")
        case .taroko: language.text("Taroko", "太魯閣")
        case .puyuma: language.text("Puyuma", "普悠瑪")
        case .dieselExpress: language.text("Diesel Tze-Chiang", "柴聯自強")
        case .dieselRailcar: language.text("DR1000 railcar", "DR1000")
        case .forestRailway: language.text("Alishan Forest Railway", "阿里山林鐵")
        case .highSpeed: language.text("High-speed rail", "高鐵")
        }
    }

    /// The first preset, in the order above, that accelerates, brakes and
    /// coasts as `performance` does, whatever its top speed (a design speed
    /// changes only that): `nil` for one of the player's own.
    public init?(matching performance: TrainPerformance) {
        let found = Self.allCases.first { preset in
            let other = preset.performance
            return other.acceleration == performance.acceleration && other.braking == performance.braking
                && other.alternativeAcceleration == performance.alternativeAcceleration
                && other.alternativeBraking == performance.alternativeBraking && other.coast == performance.coast
        }
        guard let found else { return nil }
        self = found
    }

    /// The design speeds offered, in km/h: the metro game's line modal
    /// (`LINE_SPEED_ALL_NON_SG`; its first row is 80, 100, 120 and 160).
    public static let designSpeeds: [Int64] = [60, 80, 90, 100, 120, 140, 150, 160, 180, 200]
}

extension TrainPerformance {
    /// The same performance with top speed `speed` km/h.
    public func withTopSpeed(_ speed: Int64) -> TrainPerformance {
        TrainPerformance(
            acceleration: acceleration, braking: braking, topSpeed: speed,
            alternativeAcceleration: alternativeAcceleration, alternativeBraking: alternativeBraking, coast: coast
        )
    }

    /// What the train or line runs as: "Local EMU · 120 km/h · 2.5 / 3
    /// km/h/s" (accelerating, then braking), "Custom" for one that matches
    /// no preset (see ``PerformancePreset/init(matching:)``).
    public func displayText(in language: DisplayLanguage) -> String {
        let name = PerformancePreset(matching: self)?.title(in: language) ?? language.text("Custom", "自訂")
        return "\(name) · \(topSpeed) km/h · \(Self.rateText(acceleration)) / \(Self.rateText(braking)) km/h/s"
    }

    /// Thousandths of a km/h per second as a decimal: 2500 is "2.5", 3960
    /// "3.96", 2000 "2".
    static func rateText(_ thousandths: Int64) -> String {
        let whole = thousandths / 1_000
        var fraction = String(thousandths % 1_000)
        while fraction.count < 3 {
            fraction = "0" + fraction
        }
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        return fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
    }
}

/// A duration in whole seconds: "16 s", "7 min", "7 min 4 s"; "16 秒",
/// "7 分", "7 分 4 秒".
public func durationText(seconds: Int64, in language: DisplayLanguage) -> String {
    let minutes = seconds / GameTime.secondsPerMinute
    let rest = seconds % GameTime.secondsPerMinute
    switch (minutes, rest) {
    case (0, _): return language.text("\(rest) s", "\(rest) 秒")
    case (_, 0): return language.text("\(minutes) min", "\(minutes) 分")
    default: return language.text("\(minutes) min \(rest) s", "\(minutes) 分 \(rest) 秒")
    }
}

extension GameWorld {
    /// How long line `id`'s own service takes, worked out with the line's
    /// performance (Stage W2c, `lineJourney(_:pattern:)`): "Round trip 7
    /// min 4 s · legs 16 s, 16 s, 16 s, 16 s", the first eight legs then
    /// "…". `nil` when the line cannot run.
    public func lineJourneyText(_ id: LineID, in language: DisplayLanguage) -> String? {
        guard let journey = lineJourney(id) else { return nil }
        var legs = journey.legs.prefix(8).map { durationText(seconds: $0.seconds, in: language) }
        if journey.legs.count > 8 {
            legs.append("…")
        }
        let roundTrip = durationText(seconds: journey.roundTripSeconds, in: language)
        return language.text(
            "Round trip \(roundTrip) · legs \(legs.joined(separator: ", "))",
            "來回 \(roundTrip) · 各段 \(legs.joined(separator: "、"))"
        )
    }

    /// The run train `id` is following between two calls (Stage W2c,
    /// `ServiceTimes.run`): "Running 240 s over 64 m, due Day 1 ·
    /// 08:04:12". `nil` when it is not on one.
    public func trainRunText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let run = train(id: id)?.times?.run else { return nil }
        let length = NetworkBuilding.lengthText(run.length, in: language)
        let due = run.end.displayTextWithSeconds(in: language)
        return language.text(
            "Running \(durationText(seconds: run.seconds, in: language)) over \(length), due \(due)",
            "行駛 \(durationText(seconds: run.seconds, in: language))、\(length)，預計 \(due) 到"
        )
    }
}

extension GameSession {
    /// Sets how the selected train runs through
    /// `GameWorld.setTrainPerformance(_:to:)`: not while it runs a service.
    public func setSelectedTrainPerformance(_ performance: TrainPerformance) {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.setTrainPerformance(train.id, to: performance)
            let text = performance.displayText(in: language)
            return language.text("\(train.name) now runs as \(text).", "\(train.name) 的性能改為 \(text)。")
        }
    }

    /// Sets the performance the selected line plans its journeys with
    /// through `GameWorld.setLinePerformance(_:to:)`; trains already sent
    /// out keep their timetables.
    public func setSelectedLinePerformance(_ performance: TrainPerformance) {
        guard let line = selectedLine else {
            message = StatusMessage(kind: .failure, text: language.text("Create or choose a line first.", "請先建立或選擇一條路線。"))
            return
        }
        perform { world throws(GameError) in
            try world.setLinePerformance(line.id, to: performance)
            let text = performance.displayText(in: language)
            return language.text("\(line.name) plans its journeys as \(text).", "\(line.name) 以 \(text) 規劃行程。")
        }
    }
}
