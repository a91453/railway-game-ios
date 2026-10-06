import GameCore

/// What the follow bar says about the followed train: the `Railway/` site's
/// `renderFollowBar`, ported:
///
///     <dot tr.color> <b>trainDisplayNo</b> trainTypeName　first→last　HH:MM–HH:MM　· status
///
/// The name is the train's; the kind is the service it runs for (its line
/// or pattern, ``GameWorld/assignedServiceName(of:in:)``); first and last
/// are its timetable's first and last stops, with the first stop's
/// departure and the last stop's arrival in the run it is on now (a
/// repeating timetable's current cycle). The status is the site's
/// `setFollowStatus`: "Not departed" (`pre`, 尚未發車) before it leaves
/// its first stop, "Arrived" (`done`, 已抵達) at its last stop, and nothing
/// while it runs. Read from the world each time it is shown; never stored.
public struct FollowBarInfo: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case notDeparted
        case running
        case arrived

        /// The site's status text, or `nil` while it runs.
        public func text(in language: DisplayLanguage) -> String? {
            switch self {
            case .notDeparted: language.text("Not departed", "尚未發車")
            case .running: nil
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

    /// The text after the name: "Main　Alpha→Gamma　08:00–08:24　· Not
    /// departed", or as much of it as the train has.
    public func detail(in language: DisplayLanguage) -> String {
        var parts: [String] = []
        if let kind { parts.append(kind) }
        if let origin, let terminus { parts.append("\(origin)→\(terminus)") }
        if let departure, let arrival { parts.append("\(departure)–\(arrival)") }
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
        guard let first = train.timetable.first, let last = train.timetable.last, train.timetable.count > 1 else {
            return FollowBarInfo(name: train.name, line: line, kind: kind, origin: nil, terminus: nil, departure: nil, arrival: nil, status: line == nil ? .running : .notDeparted)
        }
        let execution = train.execution
        let offset = (train.timetablePeriod ?? 0) &* (execution?.cycle ?? 0)
        let status: FollowBarInfo.Status
        switch execution {
        case nil where line != nil:
            // A line train gets its timetable only when dispatched, and
            // keeps the finished trip's until the next dispatch: with one
            // and no execution, it has arrived.
            status = .arrived
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
