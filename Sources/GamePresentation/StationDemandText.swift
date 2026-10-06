import GameCore

// Station demand (Stage C2): the screen for G1a's `setStationDemand`, after
// the `Ci/` reference's custom ridership panel (`#panel-station-flow-adjust`
// in `game-dom__q_f4c03f23b8518a04.html`; `applyStationFlowPreset`,
// `copyStationFlowAdjustProfile`, `pasteStationFlowAdjustProfile`,
// `applyStationFlowAdjustToAllServingLines` and `drawStationFlowAdjustCanvas`
// in `app__q_c234188b7c397f91.js`): the four presets, the trips a station
// starts each day, its trips by hour as they enter and leave it, copying one
// station's demand to another or to every station of its lines, and,
// read-only, the trips to and from each other station and the passenger
// ledger. GameCore decides every change; an action made of several commands
// runs them on a copy of the world that replaces the session's only when all
// succeed (as in Stage C1).

extension StationDemandKind {
    /// The reference's preset names (`metro.station.flow.preset_*`: 居民区、
    /// 办公区、购物中心、景区), in Taiwan's usage.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .residential: language.text("Residential", "住宅區")
        case .office: language.text("Office", "辦公區")
        case .shopping: language.text("Shopping", "購物中心")
        case .scenic: language.text("Scenic", "景點")
        }
    }
}

extension StationDemand {
    /// The trips a day a station gets when the player first gives it a
    /// kind. The reference keeps each station's own total (its server's
    /// ridership, which the snapshot does not have), so the number is the
    /// app's own: a peak hour of about 870 trips, a few trains' worth.
    public static let defaultDailyTrips: Int64 = 10_000

    /// The ridership a managed company's city gives every station
    /// (ARCHITECTURE decision 46): the reference's management mode reads
    /// each station's from the real city (`stationFlowCustomEditingAllowed`
    /// lets only free play change it). Until the game has a city (Phase 5),
    /// every station is a residential one of ``defaultDailyTrips``.
    public static let cityDefault = StationDemand(kind: .residential, dailyTrips: defaultDailyTrips)

    /// The daily trips the app steps through: 1, 2 and 5 times each power
    /// of ten from 100 to ``maximumDailyTrips``.
    public static let dailyTripSteps: [Int64] = [
        100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000, maximumDailyTrips,
    ]

    /// The first step above `trips`, or `nil` at the top.
    public static func dailyTrips(above trips: Int64) -> Int64? {
        dailyTripSteps.first { $0 > trips }
    }

    /// The last step below `trips`, or `nil` at the bottom.
    public static func dailyTrips(below trips: Int64) -> Int64? {
        dailyTripSteps.last { $0 < trips }
    }

    /// "Residential · 10,000 trips a day"; "住宅區 · 每日 10,000 人次".
    public func displayText(in language: DisplayLanguage) -> String {
        "\(kind.title(in: language)) · \(Self.tripsText(dailyTrips, in: language))"
    }

    /// "10,000 trips a day"; "每日 10,000 人次".
    public static func tripsText(_ trips: Int64, in language: DisplayLanguage) -> String {
        let count = Money(trips).displayText
        return language.text("\(count) \(trips == 1 ? "trip" : "trips") a day", "每日 \(count) 人次")
    }
}

/// A station's trips by hour of the day, hour 0 first: those that start
/// there, which enter it (the reference's 进站, drawn from its `out` curve),
/// and those that end there, which leave it (出站, its `in` curve).
public struct StationFlow: Hashable, Sendable {
    public let entries: [Int64]
    public let exits: [Int64]
    /// Whether no line takes the station's trips to another station with
    /// demand yet, so the hours only share its own daily trips by its
    /// preset's curve and ``StationDemand/dayShape``, the way the reference
    /// draws a station it has no ridership for from a default shape.
    public let isShape: Bool

    public init(entries: [Int64], exits: [Int64], isShape: Bool) {
        self.entries = entries
        self.exits = exits
        self.isShape = isShape
    }

    /// The hour with the most trips in `hours`, the earliest of equal ones.
    public static func peakHour(of hours: [Int64]) -> Int {
        hours.indices.max { hours[$0] < hours[$1] } ?? 0
    }

    /// The day's total and the busiest hour of `hours`: "1,000 a day ·
    /// busiest 08:00, 171"; "每日 1,000 · 最多 08:00，171".
    public static func summaryText(of hours: [Int64], in language: DisplayLanguage) -> String {
        let total = Money(hours.reduce(0, +)).displayText
        let peak = peakHour(of: hours)
        let time = clockText(minuteOfDay: 60 * peak)
        let count = Money(hours[peak]).displayText
        return language.text("\(total) a day · busiest \(time), \(count)", "每日 \(total) · 最多 \(time)，\(count)")
    }

    /// One hour of `hours`: "08:00–09:00 · 171 trips"; "08:00–09:00 · 171
    /// 人次".
    public static func hourText(_ hour: Int, of hours: [Int64], in language: DisplayLanguage) -> String {
        let span = "\(clockText(minuteOfDay: 60 * hour))–\(hour == 23 ? "24:00" : clockText(minuteOfDay: 60 * hour + 60))"
        let count = hours[hour]
        let text = Money(count).displayText
        return language.text("\(span) · \(text) \(count == 1 ? "trip" : "trips")", "\(span) · \(text) 人次")
    }
}

/// The trips each day between a station and one other station.
public struct StationDemandPair: Hashable, Sendable {
    /// The other station.
    public let station: StationID
    /// Trips from the station to the other one.
    public let outbound: Int64
    /// Trips from the other station to this one.
    public let inbound: Int64

    public init(station: StationID, outbound: Int64, inbound: Int64) {
        self.station = station
        self.outbound = outbound
        self.inbound = inbound
    }
}

/// One row of a station's passenger ledger: what it counts and how many.
public struct LedgerCount: Hashable, Sendable {
    public let title: String
    public let count: Int64

    public init(title: String, count: Int64) {
        self.title = title
        self.count = count
    }

    /// The count with thousands separators.
    public var countText: String {
        Money(count).displayText
    }
}

extension GameWorld {
    /// The trips that start and end at station `id` in each hour (see
    /// ``StationFlow``): the sums of ``hourlyDemand(from:to:)`` to and from
    /// every other station. `nil` when it has no demand.
    public func stationFlow(of id: StationID) -> StationFlow? {
        guard let demand = stationDemand(of: id) else { return nil }
        var entries = Array(repeating: Int64(0), count: 24)
        var exits = entries
        for other in stations where other.id != id && stationDemand(of: other.id) != nil {
            let leaving = hourlyDemand(from: id, to: other.id)
            let coming = hourlyDemand(from: other.id, to: id)
            for hour in 0..<24 {
                entries[hour] += leaving[hour]
                exits[hour] += coming[hour]
            }
        }
        guard entries.allSatisfy({ $0 == 0 }), exits.allSatisfy({ $0 == 0 }) else {
            return StationFlow(entries: entries, exits: exits, isShape: false)
        }
        return StationFlow(
            entries: Self.shared(demand.dailyTrips, by: demand.kind.departureShape),
            exits: Self.shared(demand.dailyTrips, by: demand.kind.arrivalShape),
            isShape: true
        )
    }

    /// `trips` shared among the hours in proportion to
    /// ``StationDemand/dayShape`` × `shape`, by largest remainder (ties to
    /// the earlier hour), as GameCore shares a pair's trips.
    static func shared(_ trips: Int64, by shape: [Int64]) -> [Int64] {
        let weights = (0..<24).map { StationDemand.dayShape[$0] * shape[$0] }
        let sum = weights.reduce(0, +)
        var shares = weights.map { trips * $0 / sum }
        let remainders = weights.map { trips * $0 % sum }
        let left = Int(trips - shares.reduce(0, +))
        let order = weights.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for hour in order.prefix(left) {
            shares[hour] += 1
        }
        return shares
    }

    /// The trips each day between station `id` and every other station it
    /// exchanges any with (``dailyDemand(from:to:)`` both ways), by
    /// ascending station ID.
    public func stationDemandPairs(of id: StationID) -> [StationDemandPair] {
        guard stationDemand(of: id) != nil else { return [] }
        return stations.compactMap { other in
            guard other.id != id, stationDemand(of: other.id) != nil else { return nil }
            let pair = StationDemandPair(
                station: other.id,
                outbound: dailyDemand(from: id, to: other.id),
                inbound: dailyDemand(from: other.id, to: id)
            )
            return pair.outbound > 0 || pair.inbound > 0 ? pair : nil
        }
    }

    /// One pair as the station panel lists it: "Beta · 6,000 there · 4,000
    /// back"; "Beta · 去 6,000 · 回 4,000".
    public func demandPairText(_ pair: StationDemandPair, in language: DisplayLanguage) -> String {
        let name = station(id: pair.station)?.name ?? "#\(pair.station.rawValue)"
        let there = Money(pair.outbound).displayText
        let back = Money(pair.inbound).displayText
        return language.text("\(name) · \(there) there · \(back) back", "\(name) · 去 \(there) · 回 \(back)")
    }

    /// Station `id`'s passenger ledger (``passengerLedger(of:)``) as rows:
    /// released, and where they are now (waiting, riding, arrived, left a
    /// full station, gave up), then the times trains left them behind.
    public func passengerLedgerRows(of id: StationID, in language: DisplayLanguage) -> [LedgerCount] {
        let ledger = passengerLedger(of: id)
        return [
            LedgerCount(title: language.text("Released", "釋出"), count: ledger.released),
            LedgerCount(title: language.text("Waiting", "候車"), count: ledger.waiting),
            LedgerCount(title: language.text("Riding", "車上"), count: ledger.riding),
            LedgerCount(title: language.text("Arrived", "已抵達"), count: ledger.arrived),
            LedgerCount(title: language.text("Left a full station", "車站客滿離開"), count: ledger.overflowed),
            LedgerCount(title: language.text("Gave up", "放棄搭乘"), count: ledger.abandoned),
            LedgerCount(title: language.text("Left behind (times)", "未能上車（次）"), count: ledger.refused),
        ]
    }

    /// The lines calling at station `id`, by ID.
    public func lines(callingAt id: StationID) -> [ServiceLine] {
        lines.filter { $0.stops.contains(id) }
    }
}

extension GameSession {
    /// The selected station, read from the world: the one picked
    /// (``selectedStationID``).
    public var selectedStation: Station? {
        selectedStationID.flatMap { world.station(id: $0) }
    }

    /// Whether the player may change stations' ridership: only in free
    /// play, as the reference's `stationFlowCustomEditingAllowed`. A managed
    /// company's city sets it (``StationDemand/cityDefault``).
    public var canEditStationDemand: Bool {
        world.accounts.mode == .free
    }

    /// Gives the selected station the `Ci/` preset `kind`
    /// (`applyStationFlowPreset`) through `GameWorld.setStationDemand(_:to:)`,
    /// keeping its daily trips as the reference keeps a station's total; a
    /// station without demand gets ``StationDemand/defaultDailyTrips``.
    /// Free play only (see ``canEditStationDemand``).
    public func setSelectedStationDemandKind(_ kind: StationDemandKind) {
        guard requireDemandEditing(), let station = requireSelectedStation() else { return }
        let trips = world.stationDemand(of: station.id)?.dailyTrips ?? StationDemand.defaultDailyTrips
        setDemand(StationDemand(kind: kind, dailyTrips: trips), of: station)
    }

    /// Sets the trips a day the selected station starts, keeping its kind.
    /// Free play only.
    public func setSelectedStationDailyTrips(_ trips: Int64) {
        guard requireDemandEditing(), let station = requireSelectedStation() else { return }
        guard let demand = world.stationDemand(of: station.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Choose what kind of place \(station.name) serves first.",
                "請先選擇 \(station.name) 的客流類型。"
            ))
            return
        }
        setDemand(StationDemand(kind: demand.kind, dailyTrips: trips), of: station)
    }

    /// Clears the selected station's demand; passengers already waiting
    /// there stay. Free play only.
    public func removeSelectedStationDemand() {
        guard requireDemandEditing(), let station = requireSelectedStation() else { return }
        perform { world throws(GameError) in
            try world.setStationDemand(station.id, to: nil)
            return language.text(
                "\(station.name) has no ridership now. Passengers already waiting stay.",
                "已移除 \(station.name) 的客流。已在候車的乘客會留下。"
            )
        }
    }

    /// Keeps the selected station's demand to paste onto others
    /// (`copyStationFlowAdjustProfile`). Never changes the world.
    public func copySelectedStationDemand() {
        guard let station = requireSelectedStation() else { return }
        guard let demand = world.stationDemand(of: station.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(station.name) has no ridership to copy.",
                "\(station.name) 沒有可複製的客流。"
            ))
            return
        }
        demandClipboard = demand
        message = StatusMessage(kind: .success, text: language.text(
            "Copied \(station.name)'s ridership: \(demand.displayText(in: language)).",
            "已複製 \(station.name) 的客流設定：\(demand.displayText(in: language))。"
        ))
    }

    /// Gives the selected station the copied kind
    /// (`pasteStationFlowAdjustProfile`), keeping its own daily trips as
    /// the reference keeps each station's total; one without demand takes
    /// the copied trips too. Free play only.
    public func pasteDemandToSelectedStation() {
        guard requireDemandEditing(), let station = requireSelectedStation() else { return }
        guard let copied = demandClipboard else {
            message = StatusMessage(kind: .failure, text: language.text("Copy a station's ridership first.", "請先複製一座車站的客流設定。"))
            return
        }
        setDemand(Self.demand(copied, for: station.id, in: world), of: station)
    }

    /// Gives every station of every line calling at the selected station
    /// its kind (`applyStationFlowAdjustToAllServingLines`), each keeping
    /// its own daily trips; stations without demand take the selected
    /// station's. All or nothing. Free play only.
    public func applySelectedStationDemandToItsLines() {
        guard requireDemandEditing(), let station = requireSelectedStation() else { return }
        guard let demand = world.stationDemand(of: station.id) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(station.name) has no ridership to apply.",
                "\(station.name) 沒有可套用的客流。"
            ))
            return
        }
        let lines = world.lines(callingAt: station.id)
        guard !lines.isEmpty else {
            message = StatusMessage(kind: .failure, text: language.text(
                "No line calls at \(station.name).",
                "目前沒有經過 \(station.name) 的路線。"
            ))
            return
        }
        let targets = Set(lines.flatMap(\.stops)).sorted()
        perform { world throws(GameError) in
            var draft = world
            for target in targets {
                try draft.setStationDemand(target, to: Self.demand(demand, for: target, in: draft))
            }
            world = draft
            let kind = demand.kind.title(in: language)
            return language.text(
                "Applied \(kind.lowercased()) to \(lines.count) \(lines.count == 1 ? "line" : "lines"), \(targets.count) stations.",
                "已套用\(kind)到 \(lines.count) 條路線，共 \(targets.count) 座車站。"
            )
        }
    }

    /// `demand`'s kind for station `id`, with the trips `id` already
    /// starts, or `demand`'s if it has none.
    private static func demand(_ demand: StationDemand, for id: StationID, in world: GameWorld) -> StationDemand {
        StationDemand(kind: demand.kind, dailyTrips: world.stationDemand(of: id)?.dailyTrips ?? demand.dailyTrips)
    }

    private func setDemand(_ demand: StationDemand, of station: Station) {
        perform { world throws(GameError) in
            try world.setStationDemand(station.id, to: demand)
            return language.text(
                "\(station.name): \(demand.displayText(in: language)).",
                "\(station.name)：\(demand.displayText(in: language))。"
            )
        }
    }

    /// Whether ridership may be changed, after reporting why not.
    private func requireDemandEditing() -> Bool {
        guard canEditStationDemand else {
            message = StatusMessage(kind: .failure, text: language.text(
                "A managed company's city sets each station's ridership. Only free play can change it.",
                "經營模式下，各站的客流由城市決定；只有自由模式可以修改。"
            ))
            return false
        }
        return true
    }

    /// Every station of a managed company without ridership given the
    /// city's (``StationDemand/cityDefault``); `world` as it is otherwise.
    static func withCityRidership(_ world: GameWorld) -> GameWorld {
        guard world.accounts.mode == .management else { return world }
        var world = world
        for station in world.stations where world.stationDemand(of: station.id) == nil {
            // A known station and a valid demand: this cannot fail.
            try? world.setStationDemand(station.id, to: .cityDefault)
        }
        return world
    }

    /// The selected station, or `nil` after reporting that there is none.
    private func requireSelectedStation() -> Station? {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return nil
        }
        return station
    }
}

extension DemandEventKind {
    /// The reference's event names (`metro.event.exhibition` 大型展览,
    /// `metro.event.crowdSurge` 大客流事件).
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .exhibition: language.text("Exhibition", "大型展覽")
        case .crowdSurge: language.text("Crowd surge", "大客流事件")
        }
    }
}

extension GameWorld {
    /// The demand events announced or running at station `id`, in the
    /// reference's words ("{wait} days until start, lasts {days} days"):
    /// "Exhibition: +35% demand, starts in 2 days, lasts 5 days", or
    /// "Crowd surge: +80% demand, 1 more day".
    public func demandEventTexts(at id: StationID, in language: DisplayLanguage) -> [String] {
        let today = clock.now.seconds / GameTime.secondsPerDay
        return (demandEvents?.events ?? []).filter { $0.station == id && today < $0.end }.map { event in
            let percent = (event.boost + 5) / 10
            let title = event.kind.title(in: language)
            if event.start > today {
                let wait = event.start - today
                let days = event.end - event.start
                return language.text(
                    "\(title): +\(percent)% demand, starts in \(wait) day\(wait == 1 ? "" : "s"), lasts \(days) day\(days == 1 ? "" : "s")",
                    "\(title)：需求 +\(percent)%，\(wait) 天後開始，持續 \(days) 天"
                )
            }
            let left = event.end - today
            return language.text(
                "\(title): +\(percent)% demand, \(left) more day\(left == 1 ? "" : "s")",
                "\(title)：需求 +\(percent)%，還有 \(left) 天"
            )
        }
    }
}
