import GameCore

// What needs the player, on the map where it is (ARCHITECTURE decision
// 109, UI/UX step UX-5c): a crowded station, or a line with no train to
// run it, shows a small bubble over its station, and a tap on the bubble
// goes to it. SimCity BuildIt floats such bubbles over its buildings, and
// Unciv folds its notices to an edge; the reference's `Ci/` posts crowding
// as a notice with a cooldown (`emitCrowdAndFullTrainNotices`). Here the
// bubbles are worked out from the world each time it is drawn, so nothing
// is stored and nothing needs dismissing: a bubble goes when its cause
// does.

/// Something on the map that needs the player.
public struct MapAlert: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Half the station's room for waiting passengers or more is
        /// taken (``StationPassengers/capacity``).
        case crowded(waiting: Int64)
        /// The station's room is full: passengers arriving now leave.
        case full(waiting: Int64)
        /// The line has no train, so no one rides it.
        case lineWithoutTrains(LineID)
    }

    public let kind: Kind
    /// The station the bubble stands over.
    public let station: StationID
    /// Where it stands.
    public let location: PlanPoint

    public var id: Self { self }

    public init(kind: Kind, station: StationID, location: PlanPoint) {
        self.kind = kind
        self.station = station
        self.location = location
    }

    /// What the bubble says, short.
    public func text(in language: DisplayLanguage, lineName: String? = nil) -> String {
        switch kind {
        case .crowded(let waiting):
            language.text("Crowded · \(Money(waiting).displayText)", "擁擠 · \(Money(waiting).displayText) 人")
        case .full:
            language.text("Full", "滿了")
        case .lineWithoutTrains:
            language.text("\(lineName ?? "Line"): no trains", "\(lineName ?? "路線")：沒有列車")
        }
    }
}

extension GameWorld {
    /// The bubbles the map shows (decision 109): each station whose
    /// waiting passengers fill half its room or more, and the first stop
    /// of each line without a train, its own or its patterns'. Stations by
    /// ascending ID, then lines by ascending ID; a station crowded and a
    /// line's first stop at once gets both.
    public func mapAlerts() -> [MapAlert] {
        var alerts: [MapAlert] = []
        for station in stations {
            let waiting = waitingPassengers(at: station.id).reduce(Int64(0)) { $0 + $1.count }
            if waiting >= StationPassengers.capacity {
                alerts.append(MapAlert(kind: .full(waiting: waiting), station: station.id, location: station.location))
            } else if waiting * 2 >= StationPassengers.capacity {
                alerts.append(MapAlert(kind: .crowded(waiting: waiting), station: station.id, location: station.location))
            }
        }
        for line in lines where line.trains.isEmpty && line.patterns.allSatisfy({ $0.trains.isEmpty }) {
            guard let first = line.stops.first, let station = station(id: first) else { continue }
            alerts.append(MapAlert(kind: .lineWithoutTrains(line.id), station: first, location: station.location))
        }
        return alerts
    }
}

extension GameSession {
    /// Goes to what `alert` is about: selects its station, or for a line
    /// without trains, the line, so the line panel shows how to staff it
    /// (decision 101). Returns whether the line panel should open. Never
    /// changes the world.
    @discardableResult
    public func respond(to alert: MapAlert) -> Bool {
        switch alert.kind {
        case .crowded, .full:
            selectStation(alert.station)
            return false
        case .lineWithoutTrains(let line):
            selectLine(line)
            return true
        }
    }
}
