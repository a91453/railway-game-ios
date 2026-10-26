import GameCore

// Journey navigation, first step (decision 423; NEXT_PRIORITIES §22.2 rank
// 27): how to ride from one station to another, how long it takes and what
// it costs, as up to three options a screen can list.
//
// The routes are GameCore's own (``GameWorld/passengerRoutes(from:to:limit:)``,
// the ones the passengers take), so what the player is told is what the
// passengers do; the fare is ``GameWorld/tripFare(from:to:highSpeed:)``, what
// they pay. Nothing here plans or prices anything itself. The reference has
// no journey planner to port (decision 423).
//
// Read from the world, never stored; each query derives the service graph, so
// a screen asks off the main thread. The screen is the next step.

/// The ways to ride from one station to another (decision 423).
public struct JourneyPlan: Equatable, Sendable {
    /// Why a plan has no option.
    public enum Absence: String, CaseIterable, Sendable {
        /// The two stations are the same.
        case sameStation
        /// One of the two is not on the map.
        case unknownStation
        /// The network has no line at all.
        case noLines
        /// Lines exist, but none with trains in service takes one to the other.
        case noRoute

        /// One sentence for the player.
        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .sameStation:
                language.text("Pick two different stations.", "請選兩個不同的車站。")
            case .unknownStation:
                language.text("That station is not on the map.", "地圖上沒有這個車站。")
            case .noLines:
                language.text("There are no lines yet. Create a line, then pick two of its stations.", "還沒有任何路線。先建一條路線，再選它上面的兩個車站。")
            case .noRoute:
                language.text(
                    "No train runs between these stations right now. Check that lines join them and have trains in service.",
                    "目前沒有列車連到這兩站。請確認有路線連起兩站，而且有列車上線。")
            }
        }
    }

    /// One ride on one line, from where the passenger gets on to where they
    /// get off.
    public struct Leg: Equatable, Sendable, Identifiable {
        public let line: LineID
        public let lineName: String
        public let from: StationID
        public let fromName: String
        public let to: StationID
        public let toName: String
        /// The ride itself, rounded up to whole minutes.
        public let rideMinutes: Int64
        /// Whether the passenger walks from the station the last leg ended at
        /// to this leg's first. `false` for the first leg and for a change at
        /// the same station.
        public let walksFromPrevious: Bool

        public var id: String { "\(line.rawValue)-\(from.rawValue)-\(to.rawValue)" }

        /// "Line 1: Alpha → Beta".
        public var text: String { "\(lineName): \(fromName) → \(toName)" }
    }

    /// One way to make the journey.
    public struct Option: Equatable, Sendable, Identifiable {
        public let legs: [Leg]
        /// Changes between lines (a walk to another station counts).
        public let transfers: Int
        public let rideMinutes: Int64
        public let waitMinutes: Int64
        public let transferMinutes: Int64
        public let walkMinutes: Int64
        public let totalMinutes: Int64
        /// What the trip costs, or `nil` while the company keeps no accounts
        /// (free play), when nobody pays.
        public let fare: Money?

        public var id: String { legs.map(\.id).joined(separator: ">") }

        /// "Direct", "1 transfer" or "2 transfers".
        public func transfersText(in language: DisplayLanguage) -> String {
            switch transfers {
            case 0: language.text("Direct", "直達")
            case 1: language.text("1 transfer", "轉乘 1 次")
            default: language.text("\(transfers) transfers", "轉乘 \(transfers) 次")
            }
        }

        /// "35 min".
        public func totalText(in language: DisplayLanguage) -> String {
            language.text("\(totalMinutes) min", "\(totalMinutes) 分鐘")
        }

        /// Where the minutes go: "20 min riding · 8 min waiting · 5 min
        /// changing"; waiting, changing and walking only when there are any.
        public func breakdownText(in language: DisplayLanguage) -> String {
            var parts = [language.text("\(rideMinutes) min riding", "乘車 \(rideMinutes) 分")]
            if waitMinutes > 0 { parts.append(language.text("\(waitMinutes) min waiting", "等車 \(waitMinutes) 分")) }
            if transferMinutes > 0 { parts.append(language.text("\(transferMinutes) min changing", "轉乘 \(transferMinutes) 分")) }
            if walkMinutes > 0 { parts.append(language.text("\(walkMinutes) min walking", "步行 \(walkMinutes) 分")) }
            return parts.joined(separator: " · ")
        }

        /// The fare in dollars and cents, such as "$ 5.00"; `nil` in free play.
        public var fareText: String? { fare?.centsText }

        /// The lines in order, such as "Line 1 → Line 2".
        public var linesText: String { legs.map(\.lineName).joined(separator: " → ") }
    }

    public let origin: StationID
    public let destination: StationID
    /// At most three, quickest first (GameCore's order).
    public let options: [Option]
    /// Why there are no options; `nil` when there are some.
    public let absence: Absence?

    public var isEmpty: Bool { options.isEmpty }

    /// The sentence to show instead of a list.
    public func message(in language: DisplayLanguage) -> String? {
        absence?.text(in: language)
    }

    /// The options for riding from `origin` to `destination` in `world`.
    public init(world: GameWorld, from origin: StationID, to destination: StationID) {
        self.origin = origin
        self.destination = destination
        guard origin != destination else {
            options = []
            absence = .sameStation
            return
        }
        guard world.station(id: origin) != nil, world.station(id: destination) != nil else {
            options = []
            absence = .unknownStation
            return
        }
        guard !world.lines.isEmpty else {
            options = []
            absence = .noLines
            return
        }
        func name(_ station: StationID) -> String { world.station(id: station)?.name ?? "" }
        let charged = world.accounts.mode == .management
        options = world.passengerRoutes(from: origin, to: destination, limit: 3).map { route in
            let legs = route.legs.enumerated().map { index, leg in
                Leg(line: leg.line, lineName: world.line(id: leg.line)?.name ?? "",
                    from: leg.from, fromName: name(leg.from), to: leg.to, toName: name(leg.to),
                    rideMinutes: (leg.rideSeconds + GameTime.secondsPerMinute - 1) / GameTime.secondsPerMinute,
                    walksFromPrevious: index > 0 && route.legs[index - 1].to != leg.from)
            }
            let highSpeed = route.legs.contains { world.line(id: $0.line)?.isHighSpeed ?? false }
            return Option(legs: legs, transfers: route.transfers, rideMinutes: route.rideMinutes,
                          waitMinutes: route.waitMinutes, transferMinutes: route.transferMinutes,
                          walkMinutes: route.walkMinutes, totalMinutes: route.totalMinutes,
                          fare: charged ? world.tripFare(from: origin, to: destination, highSpeed: highSpeed) : nil)
        }
        absence = options.isEmpty ? .noRoute : nil
    }
}
