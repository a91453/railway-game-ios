import GameCore

// Decision 224, option 3B: while a new line's stations are picked on the
// map, the last two picked side by side, their figures as bars growing
// out from the middle, and between them how far apart they are along the
// track and how long a train takes. All of it is what the world already
// knows: the land within 800 m of each station (Phase 6a), the trips that
// start there each day (the station's demand), and the path and running
// time a line between the two would have (``GameWorld/lineJourney(_:pattern:)``,
// the same trial line ``GameWorld/stationsAlongTrack(from:to:)`` drives).

/// Two stations a new line would join, compared (decision 224, 3B).
public struct StationPairComparison: Equatable, Sendable {
    /// What the comparison measures of a station.
    public enum Measure: CaseIterable, Hashable, Sendable {
        case residents
        case jobs
        case dailyTrips

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .residents: language.text("Residents", "居民")
            case .jobs: language.text("Jobs", "就業")
            case .dailyTrips: language.text("Trips a day", "每天出發")
            }
        }
    }

    /// One of the two stations.
    public struct Side: Equatable, Sendable {
        public let station: StationID
        public let name: String
        /// Within 800 m; `nil` on a map without land.
        public let residents: Int64?
        public let jobs: Int64?
        /// The trips that start at the station each day; `nil` without
        /// demand.
        public let dailyTrips: Int64?
        /// The lines that already call at it.
        public let lines: [LineID]

        public func value(_ measure: Measure) -> Int64? {
            switch measure {
            case .residents: residents
            case .jobs: jobs
            case .dailyTrips: dailyTrips
            }
        }
    }

    public let from: Side
    public let to: Side
    /// How far apart the two stand, in metres.
    public let straightMetres: Int64
    /// How far a train runs between them and in how many seconds, with a
    /// new line's own performance; `nil` when no track joins them yet.
    public let trackMetres: Int64?
    public let runSeconds: Int64?

    /// The measures either station has a figure for, in order.
    public var measures: [Measure] {
        Measure.allCases.filter { from.value($0) != nil || to.value($0) != nil }
    }

    /// How long the bar of `measure` is on `side`, 0 to 1: its share of the
    /// larger of the two, so the larger reaches the end.
    public func fraction(_ measure: Measure, of side: Side) -> Double {
        let largest = max(from.value(measure) ?? 0, to.value(measure) ?? 0)
        guard largest > 0 else { return 0 }
        return Double(side.value(measure) ?? 0) / Double(largest)
    }

    /// The comparison of `from` and `to` in `world`, or `nil` when either
    /// station does not exist or they are the same.
    public init?(world: GameWorld, from: StationID, to: StationID) {
        guard from != to, let a = world.station(id: from), let b = world.station(id: to) else { return nil }
        func side(_ station: Station) -> Side {
            let land = world.land.isEmpty ? nil : world.landCatchment(of: station.id)
            return Side(
                station: station.id,
                name: station.name,
                residents: land?.residents,
                jobs: land?.jobs,
                dailyTrips: world.stationDemand(of: station.id)?.dailyTrips,
                lines: world.lines(callingAt: station.id).map(\.id)
            )
        }
        self.from = side(a)
        self.to = side(b)
        let dx = Double(a.point.x - b.point.x), dy = Double(a.point.y - b.point.y)
        self.straightMetres = Int64(((dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)).rounded())
        var trial = world
        if let line = try? trial.createLine(named: "Route", stops: [from, to]),
           let leg = trial.lineJourney(line.id)?.legs.first, leg.path.distance > 0 {
            self.trackMetres = leg.path.distance / WorldCoordinate.unitsPerMetre
            self.runSeconds = leg.seconds
        } else {
            self.trackMetres = nil
            self.runSeconds = nil
        }
    }

    init(from: Side, to: Side, straightMetres: Int64, trackMetres: Int64?, runSeconds: Int64?) {
        self.from = from
        self.to = to
        self.straightMetres = straightMetres
        self.trackMetres = trackMetres
        self.runSeconds = runSeconds
    }

    /// "13.6 km" along the track, or "13.6 km apart" when no track joins
    /// them yet.
    public func distanceText(in language: DisplayLanguage) -> String {
        if let trackMetres { return Self.kilometres(trackMetres) }
        let text = Self.kilometres(straightMetres)
        return language.text("\(text) apart", "相距 \(text)")
    }

    /// "About 14 min", or what to do when no track joins them.
    public func timeText(in language: DisplayLanguage) -> String {
        guard let runSeconds else { return language.text("No track yet", "還沒有軌道") }
        let minutes = max(1, (runSeconds + 30) / GameTime.secondsPerMinute)
        return language.text("About \(minutes) min", "約 \(minutes) 分")
    }

    /// A figure as the bar shows it: "4,280", or "—".
    public static func valueText(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let digits = String(value.magnitude)
        var text = value < 0 ? "-" : ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text.append(",") }
            text.append(digit)
        }
        return text
    }

    static func kilometres(_ metres: Int64) -> String {
        if metres < 1_000 { return "\(metres) m" }
        let tenths = (metres + 50) / 100
        return "\(tenths / 10).\(tenths % 10) km"
    }
}
