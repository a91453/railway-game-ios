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

// TestFlight 70.1 (decision 284): a double track drawn from open ground has
// no crossover between its two tracks, so stations given platforms on
// different ones are not joined. The draft said only that no track joins
// them; it now says why and what joins them.

/// Why no line can be driven between two stations picked one after the
/// other (``GameWorld/lineDraftGap(through:)``).
public enum LineDraftGap: Hashable, Sendable {
    /// The station has no platform on any track.
    case noPlatform(StationID)
    /// No track at all, through any switch, runs from a platform of the
    /// first to a platform of the second: the two tracks of a double line
    /// with no crossover between them, say.
    case separateTracks(StationID, StationID)
    /// Track joins their platforms, but a train cannot drive it from one to
    /// the other.
    case noWay(StationID, StationID)
}

extension GameWorld {
    /// Why ``stationsAlongTrack(through:)`` finds no route through
    /// `picked`: for the first two in a row with none, the station of the
    /// two without a platform, or else whether any track joins their
    /// platforms. `nil` when a route is found, or for fewer than two.
    public func lineDraftGap(through picked: [StationID]) -> LineDraftGap? {
        for (from, to) in zip(picked, picked.dropFirst()) where stationsAlongTrack(from: from, to: to) == nil {
            for id in [from, to] where network.platforms(of: id).isEmpty {
                return .noPlatform(id)
            }
            return platformTracksMeet(from, to) ? .noWay(from, to) : .separateTracks(from, to)
        }
        return nil
    }

    /// Whether track, through any node, runs from a platform of station
    /// `a` to a platform of station `b`, whichever way a train could
    /// drive it.
    func platformTracksMeet(_ a: StationID, _ b: StationID) -> Bool {
        tracksMeet(Set(network.platforms(of: a).map(\.edge)), Set(network.platforms(of: b).map(\.edge)))
    }

    /// Whether track, through any node, runs from one of the edges `from`
    /// to one of `to`, whichever way a train could drive it.
    func tracksMeet(_ from: Set<TrackEdgeID>, _ to: Set<TrackEdgeID>) -> Bool {
        var seen = from
        var queue = Array(seen)
        while let id = queue.popLast() {
            if to.contains(id) { return true }
            guard let edge = network.edge(id) else { continue }
            for node in [edge.from, edge.to] {
                for end in network.node(node)?.ends ?? [] where seen.insert(end.edge).inserted {
                    queue.append(end.edge)
                }
            }
        }
        return false
    }

    /// What the new line's draft says when no track joins the stations
    /// picked: why, and what to do. The line can still be created; it
    /// calls at the stations picked.
    public func lineDraftGapText(_ gap: LineDraftGap, in language: DisplayLanguage) -> String {
        let still = language.text(
            " The line calls at the stations picked; its trains run once track joins them.",
            "路線只停點選的車站，軌道接通後列車才能行駛。"
        )
        switch gap {
        case .noPlatform(let id):
            let name = stationName(id)
            return language.text(
                "\(name) has no platform yet: add one on the track with the network tool's Platform.",
                "\(name) 還沒有月台：用路網工具的「月台」在軌道上設一座。"
            ) + still
        case .separateTracks(let a, let b):
            let first = stationName(a), second = stationName(b)
            return language.text(
                "The platforms of \(first) and \(second) are on tracks that do not meet, such as the two tracks of a double line with no crossover. Give both a platform on the same track, or select the track and tap Add X crossover.",
                "\(first) 和 \(second) 的月台在兩條不相連的軌道上（例如複線的兩條之間沒有渡線）。在同一條軌道上為兩站都設月台，或選取軌道按「加 X 渡線」。"
            ) + still
        case .noWay:
            return language.text(
                "No track joins these stations yet.",
                "這些車站之間還沒有軌道相連。"
            ) + still
        }
    }
}
