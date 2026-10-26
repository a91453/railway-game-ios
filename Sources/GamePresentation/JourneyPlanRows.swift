import Foundation
import GameCore

// Journey navigation, second step (decision 423): what the station panel's
// "How to Get There" section shows of a ``JourneyPlan``. The wording of every
// row, the destinations to pick from and what decides that a plan is worked
// out again are here, so the app only lays them out and a Linux test can pin
// them.

extension JourneyPlan {
    /// The text of one option's row (and of its legs, once opened).
    public struct Rows: Equatable, Sendable {
        /// One ride, with the walk that comes before it when there is one.
        public struct Leg: Equatable, Sendable, Identifiable {
            public let id: String
            /// "Walk to Beta", or `nil` when the passenger stays at the station.
            public let walkText: String?
            /// "Line 1: Alpha → Beta".
            public let text: String
        }

        /// "35 min · 1 transfer · $ 5.00"; no fare in free play.
        public let headline: String
        /// "Line 1 → Line 2".
        public let lines: String
        /// "20 min riding · 8 min waiting · 5 min changing".
        public let breakdown: String
        public let legs: [Leg]

        /// What VoiceOver reads for the row: the three lines in one breath.
        public var spoken: String { [headline, lines, breakdown].joined(separator: ", ") }
    }

    /// The sentence shown while the options are being worked out.
    public static func findingText(in language: DisplayLanguage) -> String {
        language.text("Finding routes…", "正在找路線…")
    }

    /// The stations to pick as a destination from `origin`, out of
    /// `stations` (``GameSession/stationMenuChoices``): every other one whose
    /// name matches `search`, by name (numbers in names by their value, so
    /// "Stop 2" comes before "Stop 10"). Worked out from the names alone, so
    /// the panel can keep the list while the game ticks.
    public static func destinations(among stations: [MenuChoice<StationID>], from origin: StationID?, matching search: ListSearch = ListSearch()) -> [MenuChoice<StationID>] {
        stations
            .filter { $0.id != origin && search.matches([$0.title]) }
            .sorted { a, b in
                let order = a.title.compare(b.title, options: [.caseInsensitive, .numeric, .widthInsensitive])
                return order == .orderedSame ? a.id.rawValue < b.id.rawValue : order == .orderedAscending
            }
    }

    /// Everything that decides the options for riding from `origin` to
    /// `destination`: the stations, the lines (with their trains, calls,
    /// names and speed class), the fares and the day (``RidershipInputs``).
    /// The panel works the plan out again when this changes and not on every
    /// tick.
    public struct Inputs: Equatable, Sendable {
        struct LineLook: Equatable, Sendable {
            let id: LineID
            let name: String
            let isHighSpeed: Bool
        }

        let origin: StationID
        let destination: StationID
        let world: RidershipInputs
        let lines: [LineLook]

        public init(world: GameWorld, from origin: StationID, to destination: StationID) {
            self.origin = origin
            self.destination = destination
            self.world = RidershipInputs(world: world)
            lines = world.lines.map { LineLook(id: $0.id, name: $0.name, isHighSpeed: $0.isHighSpeed) }
        }
    }
}

extension JourneyPlan.Option {
    /// The texts of this option's row in `language`.
    public func rows(in language: DisplayLanguage) -> JourneyPlan.Rows {
        var headline = [totalText(in: language), transfersText(in: language)]
        if let fareText { headline.append(fareText) }
        return JourneyPlan.Rows(
            headline: headline.joined(separator: " · "),
            lines: linesText,
            breakdown: breakdownText(in: language),
            legs: legs.map { leg in
                JourneyPlan.Rows.Leg(id: leg.id, walkText: leg.walksFromPrevious ? Self.walkText(to: leg.fromName, in: language) : nil, text: leg.text)
            })
    }

    /// "Walk to Beta" or "步行到 北車站" (Chinese names already ending in 站
    /// are not given a second one).
    public static func walkText(to name: String, in language: DisplayLanguage) -> String {
        language.text("Walk to \(name)", "步行到 \(name.hasSuffix("站") ? name : name + "站")")
    }
}
