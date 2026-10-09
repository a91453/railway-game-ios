import GameCore

// The station master (ARCHITECTURE decision 118): one character who says,
// in a sentence, the one thing most worth doing now. SimCity BuildIt has
// an advisor's face say what happened, TheoTown a little man in its
// tutorial; the reference's `Railway/taipei_gta_reference/` keeps one
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

    /// The advice for `world`, or `nil` when all runs well. The worries
    /// first (debt, a full station, a line no one rides, a crowded
    /// station; the lowest ID of each), then the next step of building a
    /// first line, then how the towns grow (decision 128): a station that
    /// served too few to grow taller (the lowest ID), else the town that
    /// grew most.
    public init?(world: GameWorld) {
        if world.accounts.mode == .management, world.economy.balance < .zero {
            self = .inDebt
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
        } else if let growth = Self.growth(in: world) {
            self = growth
        } else {
            return nil
        }
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
                "The town round \(name) grew \(tenths / 10).\(tenths % 10)% yesterday. Good service keeps it growing.",
                "「\(name)」附近的城市昨天成長了 \(tenths / 10).\(tenths % 10)%。服務好，城市就會繼續長大。"
            )
        }
    }

    /// Whether it is a worry (shown with a warning look) rather than a
    /// next step.
    public var isWorry: Bool {
        switch self {
        case .inDebt, .stationFull, .lineWithoutTrains, .stationCrowded, .underserved: true
        case .buildTrack, .buildStation, .buildSecondStation, .createLine, .townGrew: false
        }
    }
}
