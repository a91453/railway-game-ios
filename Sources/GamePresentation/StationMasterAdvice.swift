import GameCore

// The station master (ARCHITECTURE decision 118): one character who says,
// in a sentence, the one thing most worth doing now. SimCity BuildIt has
// an advisor's face say what happened, TheoTown a little man in its
// tutorial; the reference's `Railway/city_world_reference/` keeps one
// objective line on screen (`.hud-obj`). Worked out from the world each
// time it is asked, so it changes as soon as its cause does, and nothing is
// stored.

/// What the station master advises, most pressing first.
public enum StationMasterAdvice: Hashable, Sendable {
    /// A managed company's cash is below zero.
    case inDebt
    /// A station's room for waiting passengers is full.
    case stationFull(station: StationID, name: String)
    /// A line has no train, so no one rides it.
    case lineWithoutTrains(line: LineID, name: String)
    /// Half a station's room is taken.
    case stationCrowded(station: StationID, name: String)
    /// No track yet.
    case buildTrack
    /// Track, but no station on it.
    case buildStation
    /// One station: a line needs two.
    case buildSecondStation
    /// Stations, but no line.
    case createLine
    /// Decision 128: a station whose town grows served too few of its
    /// passengers yesterday (`percent`, under ``LandDemand/upgradeService``)
    /// for its buildings to rise.
    case underserved(station: StationID, name: String, percent: Int64)
    /// Decision 128: the town round a station grew yesterday, by `tenths`
    /// of a percent: the most of any.
    case townGrew(station: StationID, name: String, tenths: Int64)
    /// Decision 154: a public holiday starts in `days` days (1 to 3),
    /// raising demand on every line by `percent`.
    case holidayComing(kind: HolidayKind, days: Int64, percent: Int64)
    /// Decision 154: the holiday that ended yesterday carried `riders` a
    /// day, `percent` more than the days before it.
    case holidayOver(kind: HolidayKind, riders: Int64, percent: Int64)
    /// The town round the station was short of building materials at the
    /// last midnight (decision 158).
    case materialsShort(station: StationID, name: String)
    /// Decision 162: a typhoon comes in `days` days (0 while it blows),
    /// over `stations` of the network's stations, taking `percent` off their
    /// demand.
    case typhoonComing(days: Int64, stations: Int, percent: Int64)
    /// Decision 162: a fuel spell started today, the day's energy `percent`
    /// dearer (or cheaper when negative) for `days` days.
    case fuelSpell(percent: Int64, days: Int64)

    /// The advice for `world`, or `nil` when all runs well. The worries
    /// first (debt, a typhoon on its way over a station a line serves
    /// (decision 162), a full station, a line no one rides, a crowded
    /// station; the lowest ID of each), then the next step of building a
    /// first line, then a public holiday about to start or just over
    /// (decision 154), then how the towns grow (decision 128): a station
    /// that served too few to grow taller (the lowest ID), else the town
    /// that grew most.
    public init?(world: GameWorld) {
        if world.accounts.mode == .management, world.economy.balance < .zero {
            self = .inDebt
            return
        }
        if let typhoon = Self.typhoon(in: world) {
            self = typhoon
            return
        }
        let alerts = world.mapAlerts()
        let name = { (id: StationID) in world.station(id: id)?.name ?? "" }
        if let full = alerts.first(where: { if case .full = $0.kind { true } else { false } }) {
            self = .stationFull(station: full.station, name: name(full.station))
            return
        }
        for alert in alerts {
            if case .lineWithoutTrains(let line) = alert.kind {
                self = .lineWithoutTrains(line: line, name: world.line(id: line)?.name ?? "")
                return
            }
        }
        if let crowded = alerts.first(where: { if case .crowded = $0.kind { true } else { false } }) {
            self = .stationCrowded(station: crowded.station, name: name(crowded.station))
            return
        }
        if world.network.edges.isEmpty, world.stations.isEmpty {
            self = .buildTrack
        } else if world.stations.isEmpty {
            self = .buildStation
        } else if world.stations.count == 1 {
            self = .buildSecondStation
        } else if world.lines.isEmpty {
            self = .createLine
        } else if let holiday = Self.holiday(in: world) {
            self = holiday
        } else if let growth = Self.growth(in: world) {
            self = growth
        } else {
            return nil
        }
    }

    /// Decision 162: the first typhoon announced or blowing over a station
    /// some line calls at.
    private static func typhoon(in world: GameWorld) -> StationMasterAdvice? {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let served = Set(world.lines.flatMap(\.stops))
        for typhoon in world.typhoons(onDay: today) {
            let hit = world.stations.filter { served.contains($0.id) && typhoon.covers($0.point) }.count
            if hit > 0 {
                return .typhoonComing(days: max(0, typhoon.start - today), stations: hit, percent: typhoon.drop / 10)
            }
        }
        return nil
    }

    /// Decision 154: a holiday starting in one to three days, else the
    /// review of one that ended yesterday; decision 162: else a fuel spell
    /// that started today.
    private static func holiday(in world: GameWorld) -> StationMasterAdvice? {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        if let coming = world.holidays(from: today + 1, through: today + 3).first(where: { $0.start > today }) {
            return .holidayComing(kind: coming.holiday.kind, days: coming.start - today, percent: (coming.boost + 5) / 10)
        }
        if let review = world.holidayReview() {
            return .holidayOver(kind: review.kind, riders: review.riders, percent: review.percent)
        }
        if world.accounts.mode == .management, let spell = world.fuelSpell(onDay: today), spell.start == today {
            return .fuelSpell(percent: (spell.index - 1_000) / 10, days: spell.end - spell.start)
        }
        return nil
    }

    /// Decision 128: what the last midnight's growth says, where the land
    /// grows (``GameWorld/landDemand``). A station's service is measured
    /// from the first midnight it was seen (0 until then, so 0 is left out).
    private static func growth(in world: GameWorld) -> StationMasterAdvice? {
        guard world.landDemand, let places = world.townGrowth?.places else { return nil }
        let open = places.filter { world.station(id: $0.station).map { $0.operationMode != .closed } ?? false }
        let name = { (id: StationID) in world.station(id: id)?.name ?? "" }
        if let short = open.first(where: { $0.lastService > 0 && $0.lastService < LandDemand.upgradeService }) {
            return .underserved(station: short.station, name: name(short.station), percent: short.lastService / 10)
        }
        // Decision 158: then the first station short of building materials.
        if let short = world.freight?.lastShort.first(where: { id in open.contains { $0.station == id } }) {
            return .materialsShort(station: short, name: name(short))
        }
        // The first of the most grown, as `places` is by station.
        if let grown = open.filter({ $0.lastGrowth > 0 }).max(by: { $0.lastGrowth < $1.lastGrowth || ($0.lastGrowth == $1.lastGrowth && $0.station > $1.station) }) {
            // Thousandths of the town are tenths of a percent.
            return .townGrew(station: grown.station, name: name(grown.station), tenths: grown.lastGrowth)
        }
        return nil
    }

    /// What the station master says when tapped with no advice to give
    /// (decision 123): before, a tap then did nothing, as if it were broken.
    public static func allWellText(in language: DisplayLanguage) -> String {
        language.text("All running well. Keep it up!", "一切順利，繼續保持！")
    }

    /// What the station master says.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .inDebt:
            language.text(
                "We're in the red. Raise fares, cut a train, or borrow from the bank.",
                "現金是負的。調高票價、減少列車，或向銀行借款吧。"
            )
        case .stationFull(_, let name):
            language.text(
                "\(name) is full: passengers are giving up. Send more trains.",
                "「\(name)」站滿了，旅客開始放棄。加開列車吧。"
            )
        case .lineWithoutTrains(_, let name):
            language.text(
                "\(name) has no trains yet. Open Lines and give it one.",
                "「\(name)」還沒有列車。打開路線幫它配車。"
            )
        case .stationCrowded(_, let name):
            language.text(
                "\(name) is getting crowded. A train more would help.",
                "「\(name)」站越來越擠了，多一列車會好一些。"
            )
        case .buildTrack:
            language.text(
                "Welcome! Tap Build, then Network, and lay some track to begin.",
                "歡迎！點「建設」，再選「路網」，鋪一段軌道吧。"
            )
        case .buildStation:
            language.text(
                "Good track. Now add a platform on it for a station.",
                "軌道不錯。接著在軌道上加月台，蓋一座車站。"
            )
        case .buildSecondStation:
            language.text(
                "One station. A line needs a second one along the track.",
                "有一座車站了。路線要兩座，沿著軌道再蓋一座。"
            )
        case .createLine:
            language.text(
                "Stations ready. Open Lines and join them into a line.",
                "車站都好了。打開路線，把它們連成一條路線。"
            )
        case .underserved(_, let name, let percent):
            language.text(
                "Only \(percent)% of \(name)'s passengers got a train yesterday. At 80% the town round it grows taller: run more trains.",
                "昨天「\(name)」只有 \(percent)% 的旅客搭上車。到 80% 附近的城市才會長高，加開列車吧。"
            )
        case .townGrew(_, let name, let tenths):
            language.text(
                "The town round \(name) grew \(tenths / 10).\(tenths % 10)% yesterday. Good service keeps it growing, fastest within 250 m of the station.",
                "「\(name)」附近的城市昨天成長了 \(tenths / 10).\(tenths % 10)%。服務好，城市就會繼續長大，車站 250 公尺內長得最快。"
            )
        case .holidayComing(let kind, let days, let percent):
            language.text(
                "\(kind.title(in: language)) starts in \(days) day\(days == 1 ? "" : "s"): about \(percent)% more passengers on every line. Add trains or cars before it.",
                "\(days) 天後是\(kind.title(in: language))，各線旅客約多 \(percent)%。先加開列車或加掛車廂吧。"
            )
        case .materialsShort(_, let name):
            language.text(
                "The town round \(name) ran short of building materials last night and grew slowly. Have a freight yard send materials, and run a freight line to \(name)'s yard.",
                "「\(name)」附近昨晚缺建材，城市長得慢。讓一座貨運場出建材，開一條貨運路線運到「\(name)」的貨運場。"
            )
        case .holidayOver(let kind, let riders, let percent):
            percent >= 0
                ? language.text(
                    "\(kind.title(in: language)) is over: \(Money(riders).displayText) riders a day, \(percent)% more than before it.",
                    "\(kind.title(in: language))結束了：每天 \(Money(riders).displayText) 人次，比連假前多 \(percent)%。"
                )
                : language.text(
                    "\(kind.title(in: language)) is over: \(Money(riders).displayText) riders a day, \(-percent)% fewer than before it. Were the trains full?",
                    "\(kind.title(in: language))結束了：每天 \(Money(riders).displayText) 人次，比連假前少 \(-percent)%。是不是車太擠了？"
                )
        case .typhoonComing(let days, let stations, let percent):
            days > 0
                ? language.text(
                    "A typhoon comes in \(days) day\(days == 1 ? "" : "s"), over \(stations) of our station\(stations == 1 ? "" : "s"): about \(percent)% fewer passengers there. Run fewer trains, or close those stations for it.",
                    "颱風 \(days) 天後來襲，影響 \(stations) 個車站，那裡的旅客會少約 \(percent)%。可以減少班次，或先把車站封站。"
                )
                : language.text(
                    "A typhoon is blowing over \(stations) of our station\(stations == 1 ? "" : "s"): about \(percent)% fewer passengers there today.",
                    "颱風正在影響 \(stations) 個車站，今天那裡的旅客少約 \(percent)%。"
                )
        case .fuelSpell(let percent, let days):
            percent >= 0
                ? language.text(
                    "Fuel and power cost \(percent)% more for \(days) days. A train or two fewer saves on energy.",
                    "油電價格上漲 \(percent)%，持續 \(days) 天。少開一兩列車可以省能源費。"
                )
                : language.text(
                    "Fuel and power cost \(-percent)% less for \(days) days.",
                    "油電價格下跌 \(-percent)%，持續 \(days) 天。"
                )
        }
    }

    /// Whether it is a worry (shown with a warning look) rather than a
    /// next step.
    public var isWorry: Bool {
        switch self {
        case .inDebt, .stationFull, .lineWithoutTrains, .stationCrowded, .underserved, .materialsShort, .typhoonComing: true
        case .buildTrack, .buildStation, .buildSecondStation, .createLine, .townGrew, .holidayComing, .holidayOver, .fuelSpell: false
        }
    }
}
