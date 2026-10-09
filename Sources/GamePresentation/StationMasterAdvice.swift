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

    /// The advice for `world`, or `nil` when all runs well. The worries
    /// first (debt, a full station, a line no one rides, a crowded
    /// station; the lowest ID of each), then the next step of building a
    /// first line.
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
        } else {
            return nil
        }
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
        }
    }

    /// Whether it is a worry (shown with a warning look) rather than a
    /// next step.
    public var isWorry: Bool {
        switch self {
        case .inDebt, .stationFull, .lineWithoutTrains, .stationCrowded: true
        case .buildTrack, .buildStation, .buildSecondStation, .createLine: false
        }
    }
}
