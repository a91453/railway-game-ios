import GameCore

// Decision 354: the station's board a platform at a time, as the platform
// boards of a real station (the idea of sporenkijker's station board,
// https://github.com/Guy-Roh/0066-sporenkijker, which has no licence: only
// the idea is taken). Each platform lists the trains due at it in the next
// ``DepartureBoard/soonSeconds``; a platform with none that soon lists its
// next train, at its time, so a quiet line's platform is never blank. A
// train whose platform is not known yet is listed under the way it goes,
// as the board did before.
//
// Which platform: the one the train stands along or is routed over now
// (``Map3DNextDeparture/routedPlatform(of:at:in:)``), for its next call
// here; else the one the line's route preference sends it to from the call
// before (decision 61); else, at a station of one platform, that one.

extension DepartureBoard {
    /// The trains due at one platform, or going one way when their
    /// platform is not known.
    public struct PlatformGroup: Equatable, Sendable, Identifiable {
        public enum Heading: Hashable, Sendable {
            /// The platform's number, from 1, as the station card numbers them.
            case platform(Int)
            case direction(destination: StationID, endsHere: Bool)
        }

        public let heading: Heading
        /// Soonest first: those due within ``DepartureBoard/soonSeconds``,
        /// or only the next one when none is.
        public let rows: [Row]
        /// Whether no train is due within ``DepartureBoard/soonSeconds``
        /// and `rows` is the next one alone.
        public let isNextOnly: Bool

        public var id: String {
            switch heading {
            case .platform(let number): "p\(number)"
            case .direction(let destination, let endsHere): "d\(destination.rawValue)|\(endsHere)"
            }
        }

        /// "第 2 月台", "往 東站" or "抵達本站".
        public func title(in language: DisplayLanguage, world: GameWorld) -> String {
            switch heading {
            case .platform(let number):
                return language.text("Platform \(number)", "第 \(number) 月台")
            case .direction(_, true):
                return language.text("Ending here", "抵達本站")
            case .direction(let destination, false):
                let name = world.station(id: destination)?.name ?? ""
                return language.text("To \(name)", "往 \(name)")
            }
        }

        /// "15 分鐘內沒有車，下一班 09:47" when the group lists its next
        /// train alone; `nil` otherwise.
        public func noteText(in language: DisplayLanguage) -> String? {
            guard isNextOnly, let next = rows.first else { return nil }
            let minutes = DepartureBoard.soonSeconds / GameTime.secondsPerMinute
            return language.text("No train in the next \(minutes) min. Next at \(next.expected.clockText).",
                                 "\(minutes) 分鐘內沒有車，下一班 \(next.expected.clockText)。")
        }
    }

    /// How far ahead a platform lists its trains: 15 minutes.
    public static let soonSeconds: Int64 = 15 * GameTime.secondsPerMinute

    /// The board a platform at a time (``PlatformGroup``): the platforms in
    /// their order, then the ways trains go whose platform is not known,
    /// the soonest first and those that end here last.
    public func byPlatform(in world: GameWorld) -> [PlatformGroup] {
        let platforms = world.trackPlatforms(of: station)
        var seen = Set<TrainID>()
        let numbered = rows.map { row -> (row: Row, platform: Int?) in
            // Only a train's next call here is routed yet.
            let next = row.train.map { seen.insert($0).inserted } ?? false
            let platform = Self.platform(of: row, isTrainsNext: next, at: station, among: platforms, in: world)
            return (row, platform.flatMap { platforms.firstIndex(of: $0) }.map { $0 + 1 })
        }
        return Self.grouping(numbered)
    }

    /// The platform of `station` row `row` is due at, or `nil` when not known.
    static func platform(of row: Row, isTrainsNext: Bool, at station: StationID, among platforms: [TrackPlatform], in world: GameWorld) -> TrackPlatform? {
        guard !platforms.isEmpty else { return nil }
        if isTrainsNext, let train = row.train, let routed = Map3DNextDeparture.routedPlatform(of: train, at: station, in: world) {
            return routed
        }
        // A train running past may take a track with no platform.
        guard !row.passes else { return nil }
        if let from = row.comesFrom, let line = world.line(id: row.line) {
            let preferences = line.routePreferences + line.patterns.flatMap(\.routePreferences)
            let preferred = preferences.first { preference in
                line.stops.indices.contains(preference.from) && line.stops.indices.contains(preference.to)
                    && line.stops[preference.from] == from && line.stops[preference.to] == station
                    && platforms.contains(preference.platform)
            }
            if let preferred { return preferred.platform }
        }
        return platforms.count == 1 ? platforms[0] : nil
    }

    /// `rows`, soonest first, each with its platform's number or `nil`,
    /// in groups: each lists its trains due within ``soonSeconds`` (at
    /// most ``rowsPerDirection``), or its next train alone.
    static func grouping(_ rows: [(row: Row, platform: Int?)]) -> [PlatformGroup] {
        var order: [PlatformGroup.Heading] = []
        var grouped: [PlatformGroup.Heading: [Row]] = [:]
        for (row, platform) in rows {
            let heading = platform.map(PlatformGroup.Heading.platform) ?? .direction(destination: row.destination, endsHere: row.endsHere)
            if grouped[heading] == nil { order.append(heading) }
            grouped[heading, default: []].append(row)
        }
        let groups = order.map { heading -> PlatformGroup in
            let all = grouped[heading]!
            let soon = all.filter { $0.isBoarding || $0.secondsAway <= soonSeconds }
            return soon.isEmpty
                ? PlatformGroup(heading: heading, rows: [all[0]], isNextOnly: true)
                : PlatformGroup(heading: heading, rows: Array(soon.prefix(rowsPerDirection)), isNextOnly: false)
        }
        func number(_ group: PlatformGroup) -> Int? {
            if case .platform(let number) = group.heading { number } else { nil }
        }
        func endsHere(_ group: PlatformGroup) -> Bool {
            if case .direction(_, true) = group.heading { true } else { false }
        }
        let platforms = groups.filter { number($0) != nil }.sorted { number($0)! < number($1)! }
        let directions = groups.filter { number($0) == nil }
        return platforms + directions.filter { !endsHere($0) } + directions.filter(endsHere)
    }
}
