import GameCore

// A new line from its two ends (ARCHITECTURE decision 100, UI/UX step
// UX-1a): the player picks where the line starts and ends, and the
// stations the track between them passes are found for them, from the
// path GameCore's own line journey takes (Stage S5), never from where the
// stations stand. The reference has nothing to port: `Ci/` adds a line's
// stations one at a time (`tutorial.transport.18`), and MapBuilder's
// `handleAddStationToLine` (decision 80) places a station by where it
// stands.

/// Which of the stations along the track a new line calls at.
public enum LineDraftStopping: CaseIterable, Hashable, Sendable {
    /// Every station the track passes between the picked ones.
    case everyStation
    /// Only the stations the player picked: the ends, and any picked on
    /// the way to choose where the line goes.
    case pickedStations
    /// The player's own choice of the stations along the track.
    case custom

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .everyStation: language.text("Every station", "沿途各站停靠")
        case .pickedStations: language.text("Only the stations picked", "只停點選的車站")
        case .custom: language.text("Choose stops", "自訂停靠站")
        }
    }
}

extension GameWorld {
    /// The stations a train passes between station `from` and station
    /// `to`, in the order it passes them, not counting the two: the
    /// stations with a platform on the track the journey of a line from
    /// `from` to `to` takes out (``GameWorld/lineJourney(_:pattern:)``,
    /// the path its trains would drive). `nil` when no such line can be
    /// driven: either station does not exist, they are the same, or no
    /// track joins their platforms.
    ///
    /// A station counts when the track driven runs along any part of one
    /// of its platforms. A station whose platforms are all on another
    /// track (the other track of a double line) is not on the way.
    public func stationsAlongTrack(from: StationID, to: StationID) -> [StationID]? {
        var draft = self
        guard let line = try? draft.createLine(named: "Route", stops: [from, to]),
              let journey = draft.lineJourney(line.id), let out = journey.legs.first
        else { return nil }
        let outbound = LineJourney(start: journey.start, legs: [out], roundTripSeconds: 0)
        var found: [StationID] = []
        for (traversal, a, b) in LineMap.pieces(of: outbound, in: network) {
            let length = network.edge(traversal.edge)?.length ?? 0
            let passed = network.platforms(on: traversal.edge).compactMap { platform -> (Int64, StationID)? in
                let (start, end) = traversal.direction == .forward
                    ? (platform.start, platform.end)
                    : (length - platform.end, length - platform.start)
                guard start < b, a < end else { return nil }
                return (start, platform.station)
            }
            for (_, station) in passed.sorted(by: { ($0.0, $0.1.rawValue) < ($1.0, $1.1.rawValue) })
            where station != from && station != to && !found.contains(station) {
                found.append(station)
            }
        }
        return found
    }

    /// The stations along the track through `picked`, in order: each
    /// picked station, and between each two the stations the track passes
    /// (``stationsAlongTrack(from:to:)``). `nil` for fewer than two, or
    /// when any two in a row have no track a line can drive between them.
    public func stationsAlongTrack(through picked: [StationID]) -> [StationID]? {
        guard picked.count >= 2, let first = picked.first else { return nil }
        var route = [first]
        for (from, to) in zip(picked, picked.dropFirst()) {
            guard let between = stationsAlongTrack(from: from, to: to) else { return nil }
            route += between
            route.append(to)
        }
        return route
    }
}
