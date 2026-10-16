import GameCore

// Choosing how trains and lines run (Stage C3). Stage W2c gave every train
// and every line a TrainPerformance, standard until a command changes it, and
// left choosing one to a later screen. The choices are the owner's
// references: the Railway reference's presets (`PERF_*`, already in
// GameCore), named after the trains it picks them for, and the metro game's
// design speeds (`Ci/`: the line modal's 設计时速, `LINE_SPEED_ALL_NON_SG`).
// Nothing here is a rule: GameCore checks every performance.

/// The performances the app offers by name: the rows of GameCore's
/// ``TrainPerformanceCatalog`` (decision 236), each named after the train
/// the Railway reference picks it for (`PERF_RULES`, `PERF_BY_TYPE`), and
/// the metro game's.
public struct PerformancePreset: CaseIterable, Hashable, Sendable {
    /// Its row in ``TrainPerformanceCatalog/builtIn``.
    let row: Int

    private init(row: Int) {
        self.row = row
    }

    /// A row the catalog lists; traps on a code it does not.
    private init(listed code: String) {
        guard let row = TrainPerformanceCatalog.builtIn.firstIndex(where: { $0.code == code }) else {
            preconditionFailure("No performance has the code \(code).")
        }
        self.row = row
    }

    /// Every preset, in the catalog's order.
    public static let allCases: [PerformancePreset] = TrainPerformanceCatalog.builtIn.indices.map(PerformancePreset.init(row:))

    public static let standard = PerformancePreset(listed: "standard")
    public static let metro = PerformancePreset(listed: "metro")
    public static let local = PerformancePreset(listed: "local")
    public static let ordinary = PerformancePreset(listed: "ordinary")
    public static let semiExpress = PerformancePreset(listed: "semiExpress")
    public static let express = PerformancePreset(listed: "express")
    public static let emu3000 = PerformancePreset(listed: "emu3000")
    public static let pushPull = PerformancePreset(listed: "pushPull")
    public static let taroko = PerformancePreset(listed: "taroko")
    public static let puyuma = PerformancePreset(listed: "puyuma")
    public static let dieselExpress = PerformancePreset(listed: "dieselExpress")
    public static let dieselRailcar = PerformancePreset(listed: "dieselRailcar")
    public static let forestRailway = PerformancePreset(listed: "forestRailway")
    public static let highSpeed = PerformancePreset(listed: "highSpeed")
    /// The steam train of decision 153: this project's, not the
    /// reference's.
    public static let steam = PerformancePreset(listed: "steam")
    /// Taipei Metro's C371 and C381 (decision 237).
    public static let metroC381 = PerformancePreset(listed: "metroC381")
    /// The Taiwan Railway's EMU800 and EMU900 (decision 237).
    public static let emu800 = PerformancePreset(listed: "emu800")
    /// The Taiwan Railway's models of decision 252.
    public static let emu100 = PerformancePreset(listed: "emu100")
    public static let e200ChuKuang = PerformancePreset(listed: "e200ChuKuang")
    public static let e500ChuKuang = PerformancePreset(listed: "e500ChuKuang")
    public static let r100ChuKuang = PerformancePreset(listed: "r100ChuKuang")
    public static let r200ChuKuang = PerformancePreset(listed: "r200ChuKuang")
    public static let haiFeng = PerformancePreset(listed: "haiFeng")

    /// Its row's code.
    public var code: String { TrainPerformanceCatalog.builtIn[row].code }

    public var performance: TrainPerformance { TrainPerformanceCatalog.builtIn[row].performance }

    /// The train's name, as the reference's rules match it (`/區間/`,
    /// `/自強/`, `/\(太/` and so on); the metro game's for ``metro``. Each
    /// row has one in ``names``, by its code; a row without one is a
    /// mistake `PerformanceSessionTests` catches.
    public func title(in language: DisplayLanguage) -> String {
        guard let name = Self.names[code] else { preconditionFailure("The performance \(code) has no name.") }
        return language.text(name.english, name.chinese)
    }

    /// The names, by code: English, then Traditional Chinese.
    static let names: [String: (english: String, chinese: String)] = [
        "standard": ("Standard", "標準"),
        "metro": ("Metro", "捷運"),
        "local": ("Local EMU", "區間車"),
        "ordinary": ("Ordinary", "普快車"),
        "semiExpress": ("Chu-Kuang / Fu-Hsing", "莒光／復興"),
        "express": ("Tze-Chiang", "自強"),
        "emu3000": ("EMU3000", "EMU3000"),
        "pushPull": ("Push-pull Tze-Chiang", "推拉式自強"),
        "taroko": ("Taroko", "太魯閣"),
        "puyuma": ("Puyuma", "普悠瑪"),
        "dieselExpress": ("Diesel Tze-Chiang", "柴聯自強"),
        "dieselRailcar": ("DR1000 railcar", "DR1000"),
        "forestRailway": ("Alishan Forest Railway", "阿里山林鐵"),
        "highSpeed": ("High-speed rail", "高鐵"),
        "steam": ("Steam train", "蒸汽列車"),
        "metroC381": ("Taipei Metro C371 / C381", "北捷 C371／C381"),
        "emu800": ("EMU800 / EMU900 local", "EMU800／900 區間車"),
        "emu100": ("EMU100 Tze-Chiang", "EMU100 自強號"),
        "e200ChuKuang": ("Chu-Kuang, E200 locomotive", "莒光號（E200 電力機車）"),
        "e500ChuKuang": ("Chu-Kuang, E500 locomotive", "莒光號（E500 電力機車）"),
        "r100ChuKuang": ("Chu-Kuang, R100 diesel", "莒光號（R100 柴電機車）"),
        "r200ChuKuang": ("Chu-Kuang, R200 diesel", "莒光號（R200 柴電機車）"),
        "haiFeng": ("Hai-Feng sightseeing train", "海風號"),
    ]

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
    /// Speed derived from the authoritative running curve, sampled over
    /// the surrounding second. A waiting, held or unplaced train is at rest.
    /// Manual movements convert the kernel's integer distance rate to km/h.
    public func trainSpeedKMH(of id: TrainID) -> Double {
        guard let train = train(id: id), train.movement.rate > 0,
              case .onEdge(let traversal, let offset)? = train.position,
              let edge = network.edge(traversal.edge) else { return 0 }
        if train.movement.remainingEdges.isEmpty, offset >= (train.movement.end ?? edge.length) { return 0 }
        if let execution = train.execution {
            guard case .travellingToStop = execution,
                  let run = train.times?.run, clock.now > run.start, clock.now < run.end,
                  let curve = runCurve(of: run, for: train.performance) else { return 0 }
            let elapsed = (clock.now.seconds - run.start.seconds) * 1000
            let first = max(0, elapsed - 500), last = min(curve.duration, elapsed + 500)
            return Double(curve.distance(at: last) - curve.distance(at: first)) * 3600
                / Double(WorldCoordinate.unitsPerMetre * (last - first))
        }
        return Double(train.movement.rate) * 60 / Double(WorldCoordinate.unitsPerMetre * 1000)
    }

    public func trainSpeedText(of id: TrainID) -> String {
        let tenths = Int64((trainSpeedKMH(of: id) * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) km/h"
    }

    /// A service creates its next path when it departs, so an empty
    /// continuation while it waits is not a routing failure.
    public func trainPathStatusText(of id: TrainID, in language: DisplayLanguage) -> String {
        trainPathStatusText(of: id, in: language) { lineDispatchHoldText(of: $0, in: language) }
    }

    /// ``trainPathStatusText(of:in:)``, with why a line holds a train
    /// (``lineDispatchHoldText(of:in:)``) from `holdText`.
    func trainPathStatusText(of id: TrainID, in language: DisplayLanguage, holdText: (TrainID) -> String?) -> String {
        guard let train = train(id: id) else { return language.text("No train", "沒有列車") }
        if case .waitingAtStop? = train.execution {
            return language.text("Waiting for departure", "等候發車")
        }
        // Author's report, 2026-10-14: a train on a trip says where it is
        // going and how far it has left, not its path's track numbers.
        if case .travellingToStop(let stop, _)? = train.execution, train.timetable.indices.contains(stop) {
            let name = stationName(train.timetable[stop].station)
            guard let left = pathDistanceLeft(of: train), left > 0 else {
                return language.text("Heading to \(name)", "開往 \(name)")
            }
            let distance = NetworkBuilding.distanceText(left, in: language)
            return language.text("Heading to \(name), \(distance) to go", "開往 \(name)，還有 \(distance)")
        }
        if train.execution == nil, let lineID = assignedLine(of: id) {
            // A line outside its service window sends nobody out: say
            // when it opens, not only that the train waits.
            if serviceLevel(of: lineID, at: clock.now) == nil, let line = line(id: lineID),
               case .hours(let open, _) = line.window {
                let time = clockText(minuteOfDay: open % 1_440)
                return language.text("Waiting: \(line.name) opens at \(time)", "等候發車：\(line.name) \(time) 開始營運")
            }
            // TestFlight 60.1: say why the line does not send it out.
            if let hold = holdText(id) { return hold }
            return language.text("Waiting for service dispatch", "等候派車")
        }
        // TestFlight 54.1: a placed train standing with no line says so,
        // not only that it has no path (``trainNextStepText(of:in:)``
        // says what to do).
        if train.execution == nil, train.position != nil, !train.hasPathAhead, assignedLine(of: id) == nil {
            return language.text("Not assigned to a line", "未配屬路線")
        }
        // Author's report, 2026-10-14: how far it goes, not its path's
        // track numbers (``Train/pathText(in:)`` keeps them).
        guard let left = pathDistanceLeft(of: train), left > 0 else {
            return language.text("No path ahead", "前方沒有路徑")
        }
        let distance = NetworkBuilding.distanceText(left, in: language)
        return language.text("Path: stops \(distance) ahead", "路徑：前方 \(distance) 處停車")
    }

    /// How far `train` has left along its path, in units: the rest of the
    /// edge it is on and the edges after it, to where it stops on the last;
    /// `nil` when it has no path ahead.
    func pathDistanceLeft(of train: Train) -> Int64? {
        guard train.hasPathAhead, case .onEdge(let traversal, let offset)? = train.position,
              let length = network.edge(traversal.edge)?.length else { return nil }
        let edges = train.movement.remainingEdges
        guard let last = edges.last else { return max(0, (train.movement.end ?? length) - offset) }
        var left = max(0, length - offset)
        for edge in edges.dropLast() {
            left += network.edge(edge)?.length ?? 0
        }
        return left + (train.movement.end ?? network.edge(last)?.length ?? 0)
    }

    /// How long line `id`'s own service takes, worked out with the line's
    /// performance (Stage W2c, `lineJourney(_:pattern:)`): "Round trip 7
    /// min 4 s · legs 16 s, 16 s, 16 s, 16 s", the first eight legs then
    /// "…"; a ring's lap (decision 49) "Lap 7 min 16 s · legs …". `nil`
    /// when the line cannot run.
    public func lineJourneyText(_ id: LineID, in language: DisplayLanguage) -> String? {
        guard let journey = lineJourney(id) else { return nil }
        var legs = journey.legs.prefix(8).map { durationText(seconds: $0.seconds, in: language) }
        if journey.legs.count > 8 {
            legs.append("…")
        }
        let roundTrip = durationText(seconds: journey.roundTripSeconds, in: language)
        if journey.isRing {
            return language.text("Lap \(roundTrip) · legs \(legs.joined(separator: ", "))", "一圈 \(roundTrip) · 各段 \(legs.joined(separator: "、"))")
        }
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
        perform(.setTrainPerformance(train.id, performance)) { _, _, _ in
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
        perform(.setLinePerformance(line.id, performance)) { _, _, _ in
            let text = performance.displayText(in: language)
            return language.text("\(line.name) plans its journeys as \(text).", "\(line.name) 以 \(text) 規劃行程。")
        }
    }
}
