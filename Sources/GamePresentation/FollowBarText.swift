import GameCore

/// What the follow bar says about the followed train: the `Railway/` site's
/// `renderFollowBar`, ported:
///
///     <dot tr.color> <b>trainDisplayNo</b> trainTypeName　first→last　HH:MM–HH:MM　· status
///
/// The name is the train's; the kind is the service it runs for (its line
/// or pattern, ``GameWorld/assignedServiceName(of:in:)``); first and last
/// are the first and last stops of the trip it is on (a timetable that
/// turns round is a trip each way, ``Train/trip(leaving:)``), with the
/// first stop's departure and the last stop's arrival in the run it is on
/// now (a repeating timetable's current cycle). The status is the site's
/// `setFollowStatus`: "Not departed" (`pre`, 尚未發車) before it leaves
/// its first stop, "Arrived" (`done`, 已抵達) at its last stop, and nothing
/// while it runs; a line's train on an empty run to an end of its line
/// (decision 172) says "Running empty" (回送中), or with a depot (decision
/// 209) "Leaving depot" (出庫中) or "Entering depot" (入庫中), and one
/// standing in its depot "In depot" (在庫; decision 214). Read from the world each time it is shown; never stored.
public struct FollowBarInfo: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case notDeparted
        /// TestFlight 60.1: a line's train its line does not send out,
        /// with why (``GameWorld/lineDispatchHoldText(of:in:)``), shown
        /// as the status itself.
        case held(String)
        case running
        case arrived
        /// Decision 172: an empty run to one end of its line, with no
        /// passengers.
        case deadheading
        /// Decision 209: an empty run out of a depot, into one, or a
        /// train standing in one (``TrainDepotState``).
        case depot(TrainDepotState)

        /// The site's status text, or `nil` while it runs.
        public func text(in language: DisplayLanguage) -> String? {
            switch self {
            case .notDeparted: language.text("Not departed", "尚未發車")
            // The reason says what holds it and what to do, once (the
            // PR #526–#626 review, U3: "Not departed: Stopped: …").
            case .held(let reason): reason
            case .running: nil
            case .deadheading: language.text("Running empty", "回送中")
            case .depot(let state): state.text(in: language)
            case .arrived: language.text("Arrived", "已抵達")
            }
        }
    }

    public let name: String
    /// The line the train runs for, for the dot's colour; `nil` for none.
    public let line: LineID?
    /// The service it runs for, the site's `trainTypeName`.
    public let kind: String?
    public let origin: String?
    public let terminus: String?
    /// "HH:MM" of the first departure and the last arrival.
    public let departure: String?
    public let arrival: String?
    public let status: Status

    public init(name: String, line: LineID?, kind: String?, origin: String?, terminus: String?, departure: String?, arrival: String?, status: Status) {
        self.name = name
        self.line = line
        self.kind = kind
        self.origin = origin
        self.terminus = terminus
        self.departure = departure
        self.arrival = arrival
        self.status = status
    }

    /// The follow bar's speeds, one tap each (decision 195): real time and
    /// ten times it, to watch the train run as it would. They set the
    /// game's speed as the speed menu does, and leave it as it is when the
    /// following stops.
    public static let speedShortcuts: [GameSpeed] = [.x1, .x10]

    /// The text after the name: "Main　Alpha→Gamma　08:00–08:24　· Not
    /// departed", or as much of it as the train has.
    /// Without `times`, the departure and arrival are left out, for a bar
    /// that shows them itself (decision 223: the arrival struck through
    /// when the train is late).
    public func detail(in language: DisplayLanguage, times: Bool = true) -> String {
        var parts: [String] = []
        if let kind { parts.append(kind) }
        if let origin, let terminus { parts.append("\(origin)→\(terminus)") }
        if times, let departure, let arrival { parts.append("\(departure)–\(arrival)") }
        var text = parts.joined(separator: "　")
        if let status = status.text(in: language) {
            text += text.isEmpty ? "· \(status)" : "　· \(status)"
        }
        return text
    }
}

extension GameWorld {
    /// The follow bar's content for train `id` (see ``FollowBarInfo``), or
    /// `nil` for an unknown ID. A train without a timetable has only its
    /// name and service.
    public func followBarInfo(of id: TrainID, in language: DisplayLanguage) -> FollowBarInfo? {
        guard let train = train(id: id) else { return nil }
        let line = assignedLine(of: id)
        let kind = assignedServiceName(of: id, in: language)
        let held = line == nil ? nil : lineDispatchHoldText(of: id, in: language).map(FollowBarInfo.Status.held)
        // The trip it is on, as the departure board reads it: a timetable
        // that turns round is a trip each way; one not yet started, its first.
        guard let trip = train.execution == nil && line == nil ? train.trip(leaving: 0) : train.currentTrip else {
            return FollowBarInfo(name: train.name, line: line, kind: kind, origin: nil, terminus: nil, departure: nil, arrival: nil, status: depotState(of: id).map(FollowBarInfo.Status.depot) ?? held ?? (line == nil ? .running : .notDeparted))
        }
        let first = train.timetable[trip.lowerBound], last = train.timetable[trip.upperBound]
        let execution = train.execution
        let offset = (train.timetablePeriod ?? 0) &* (execution?.cycle ?? 0)
        let status: FollowBarInfo.Status
        let depot = depotState(of: id)
        switch execution {
        case _ where depot != nil:
            status = .depot(depot ?? .inDepot)
        case _? where train.isDeadheading:
            status = .deadheading
        case nil where line != nil:
            // A line train gets its timetable only when dispatched, and
            // keeps the finished trip's until the next dispatch: with one
            // and no execution, it has arrived, unless its line holds it
            // (TestFlight 60.1).
            status = held ?? .arrived
        case nil:
            status = .notDeparted
        case .waitingAtStop(let stop, _)? where stop == 0:
            status = .notDeparted
        case .waitingAtStop(let stop, _)? where stop == train.timetable.count - 1 && train.timetablePeriod == nil:
            status = .arrived
        default:
            status = .running
        }
        return FollowBarInfo(
            name: train.name,
            line: line,
            kind: kind,
            origin: stationName(first.station),
            terminus: stationName(last.station),
            departure: GameTime(seconds: first.departure.seconds &+ offset).clockText,
            arrival: GameTime(seconds: last.arrival.seconds &+ offset).clockText,
            status: status
        )
    }
}
