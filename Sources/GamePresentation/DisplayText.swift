import GameCore

// Player-facing text for GameCore values. GameCore stays free of UI copy;
// the app shows these strings as they are (English only for the prototype).

extension TrackDirection {
    public var name: String {
        switch self {
        case .north: "North"
        case .east: "East"
        case .south: "South"
        case .west: "West"
        }
    }

    public var abbreviation: String {
        switch self {
        case .north: "N"
        case .east: "E"
        case .south: "S"
        case .west: "W"
        }
    }
}

extension TrackConnections {
    /// The kind of track piece these connections form, such as "Straight".
    public var shapeName: String {
        let directions = directions
        switch directions.count {
        case 0: return "No connections"
        case 1: return "Dead end"
        case 2:
            let isStraight = self == [.north, .south] || self == [.east, .west]
            return isStraight ? "Straight" : "Curve"
        case 3: return "T-junction"
        default: return "Four-way"
        }
    }

    /// The connected directions, such as "N–E".
    public var abbreviation: String {
        directions.map(\.abbreviation).joined(separator: "–")
    }

    /// Shape and directions, such as "Curve N–E".
    public var summary: String {
        isEmpty ? shapeName : "\(shapeName) \(abbreviation)"
    }
}

extension GameWorld {
    /// What is on the tile at `position`, such as "Empty", "Track · Straight N–S",
    /// "Turnout · E–S–W, stem W", "Level crossing · N–S over E–W",
    /// "Station · Central" or, for a station grown onto more tiles,
    /// "Station · Central · 3 tiles".
    public func tileSummary(at position: GridPosition) -> String {
        // The railway first (Stage S3A: it is not on the map), then the land.
        if let track = track(at: position) {
            switch track.layout {
            case .open: return "Track · \(track.connections.summary)"
            case .turnout(let stem): return "Turnout · \(track.connections.abbreviation), stem \(stem.abbreviation)"
            case .crossing: return "Level crossing · N–S over E–W"
            }
        }
        switch map.tile(at: position)?.type {
        case nil: return "Outside the map"
        case .empty?: return "Empty"
        case .station(let id)?: return stationSummary(id)
        }
    }
}

extension GameWorld {
    private func stationSummary(_ id: StationID) -> String {
        guard let station = station(id: id) else { return "Station · #\(id.rawValue)" }
        let tiles = station.tiles.count
        return tiles == 1 ? "Station · \(station.name)" : "Station · \(station.name) · \(tiles) tiles"
    }
}

extension GameWorld {
    /// How much has been built, such as "3 stations · 17 track tiles".
    public var networkSummary: String {
        let stationCount = stations.count
        let trackCount = tracks.count
        let stationText = stationCount == 1 ? "1 station" : "\(stationCount) stations"
        let trackText = trackCount == 1 ? "1 track tile" : "\(trackCount) track tiles"
        return "\(stationText) · \(trackText)"
    }
}

extension GameWorld {
    /// The stations the train `id` is stopped at, such as "Stopped at
    /// Central" (several in ascending ID order: "Stopped at Central,
    /// Market"), or `nil` when it is not stopped at a station. Read from
    /// `stationsStoppedAt(by:)`. A train of several cars not wholly beside
    /// one of them (see `stationsBesideWholeTrain(_:)`) is told so:
    /// "Stopped at Central · the platform is too short for all its cars".
    public func stationStopText(of id: TrainID) -> String? {
        let stopped = stationsStoppedAt(by: id)
        let names = stopped.map { station(id: $0)?.name ?? "#\($0.rawValue)" }
        guard !names.isEmpty else { return nil }
        let text = "Stopped at \(names.joined(separator: ", "))"
        return stationsBesideWholeTrain(id).count < stopped.count ? "\(text) · the platform is too short for all its cars" : text
    }
}

extension TrainPosition {
    /// Where a train is, exactly as GameCore records it: "At (3, 2), facing
    /// East" at a node, or "(3, 2) → (4, 2), 256 / 1024" on a link (the
    /// offset from the first tile, out of ``TrainPosition/linkLength``); on
    /// the track network, "Edge #3 forward, 256 units along".
    public var displayText: String {
        switch self {
        case .atNode(let tile, let heading):
            "At \(tile), facing \(heading.name)"
        case .onLink(let from, let to, let offset):
            "\(from) → \(to), \(offset) / \(TrainPosition.linkLength)"
        case .onEdge(let traversal, let offset):
            "\(traversal.edge.displayText) \(traversal.direction == .forward ? "forward" : "backward"), \(offset) units along"
        }
    }
}

extension TrackNodeID {
    /// "Node #3" on the track network, or "Tile (3, 2)" on the grid.
    public var displayText: String {
        switch self {
        case .tile(let tile): "Tile \(tile)"
        case .node(let number): "Node #\(number)"
        }
    }
}

extension TrackEdgeID {
    /// "Edge #3" on the track network, or "Link (3, 2)–(4, 2)" on the grid.
    public var displayText: String {
        switch self {
        case .link(let a, let b): "Link \(a)–\(b)"
        case .edge(let number): "Edge #\(number)"
        }
    }
}

extension Train {
    /// The train's position, or "Not on the track" while it is unplaced.
    public var positionText: String {
        position?.displayText ?? "Not on the track"
    }

    /// How many cars it has, one to a tile: "1 car", "3 cars".
    public var carsText: String {
        cars == 1 ? "1 car" : "\(cars) cars"
    }

    /// The path the train has left. On the grid, ``TrainMovement/pathText``.
    /// On the track network: "No path ahead", "Path: 1 more edge, Edge #4",
    /// "Path: 3 more edges, ending on Edge #9", with ", stopping 3000 units
    /// along it" when it stops part of the way along the last (Stage S5),
    /// or "Path: stops 1024 units ahead" on the edge it is on.
    public var pathText: String {
        guard case .onEdge(_, let offset)? = position else { return movement.pathText }
        let edges = movement.remainingEdges
        guard let last = edges.last else {
            guard let end = movement.end, end > offset else { return "No path ahead" }
            return "Path: stops \(end - offset) units ahead"
        }
        let stop = movement.end.map { ", stopping \($0) units along it" } ?? ""
        return edges.count == 1
            ? "Path: 1 more edge, \(last.displayText)\(stop)"
            : "Path: \(edges.count) more edges, ending on \(last.displayText)\(stop)"
    }
}

extension TrainMovement {
    /// The rate, such as "Rate 128 / min": logical units per game minute,
    /// where ``TrainPosition/linkLength`` units are one tile.
    public var rateText: String {
        "Rate \(rate) / min"
    }

    /// The continuation entries the train has not entered yet, such as
    /// "No path ahead", "Path: 1 more node, (4, 2)" or "Path: 5 more nodes,
    /// ending at (8, 3)": the grid's path (see ``Train/pathText`` for the
    /// track network's).
    public var pathText: String {
        let remaining = remainingContinuation
        guard let last = remaining.last else { return "No path ahead" }
        return remaining.count == 1
            ? "Path: 1 more node, \(last)"
            : "Path: \(remaining.count) more nodes, ending at \(last)"
    }
}

extension GameError {
    /// What went wrong, in words a player can act on. GameError itself
    /// carries only structured data.
    public var playerMessage: String {
        switch self {
        case .invalidMapSize(let width, let height):
            "A \(width) × \(height) map is not supported."
        case .outOfBounds(let position):
            "\(position) is outside the map."
        case .tileOccupied(let position):
            "Tile \(position) is already occupied."
        case .invalidTrackConnections:
            // The app builds pieces only from the four named directions, so
            // an empty piece is the only way a player can get this error.
            "Choose at least one direction for the track."
        case .invalidName:
            "Enter a name."
        case .insufficientFunds(let required, let available):
            "Not enough cash: this costs \(required.moneyText) and you have \(available.moneyText)."
        case .noTrackToRemove(let position):
            "There is no track to remove at \(position)."
        case .trackInUse(let position):
            "A train is on the track at \(position). Take the train off the track first."
        case .unknownTrain(let id):
            "There is no train #\(id.rawValue)."
        case .trainAlreadyPlaced(let id):
            "Train #\(id.rawValue) is already on the track."
        case .trainNotPlaced(let id):
            "Train #\(id.rawValue) is not on the track."
        case .invalidTrainPosition:
            "A train can only be placed on a track tile or between two joined track tiles, with track behind it for all its cars."
        case .invalidMovementRate:
            "A train's rate cannot be negative."
        case .invalidContinuation:
            "The train cannot follow that path: each step must lead to joined track, without turning back."
        case .clockOverflow:
            "Game time cannot advance any further."
        case .idsExhausted:
            "This game has no IDs left for anything more of this kind."
        case .invalidTimetable:
            "A timetable's times cannot be negative or go back: each stop leaves no earlier than it arrives, and no later than the next stop arrives. A repeating timetable needs a stop, and a period long enough to start again without going back."
        case .unknownStation(let id):
            "There is no station #\(id.rawValue)."
        case .trainServiceActive(let id):
            "Train #\(id.rawValue) is running its timetable. Stop its service first."
        case .trainServiceNotActive(let id):
            "Train #\(id.rawValue) is not running a timetable."
        case .noTimetable(let id):
            "Train #\(id.rawValue) has no timetable to run."
        case .trainNotAtFirstStop(let id):
            "Train #\(id.rawValue) must be stopped at its timetable's first station to start its service."
        case .unknownLine(let id):
            "There is no line #\(id.rawValue)."
        case .invalidLineStops:
            "A line calls at two stations or more, and not at the same station twice in a row."
        case .invalidLineRate:
            "A line's speed must be at least 1."
        case .invalidServiceWindow:
            "A line opens between 00:00 and 23:59 and closes after it opens, by 06:00 the next morning."
        case .invalidTrainsInService:
            "A line cannot run a negative number of trains."
        case .invalidServiceDay:
            "The day's service levels must start at 00:00 and change at later times within the day."
        case .invalidHeadway:
            "A target headway must be between 2 minutes and 24 hours."
        case .trainOnLine(let id):
            "Train #\(id.rawValue) runs for a line. Take it off the line first."
        case .trainNotOnLine(let id):
            "Train #\(id.rawValue) is not on a line."
        case .invalidLinePattern:
            "A pattern calls at two of its line's stops or more, in the line's order."
        case .unknownLinePattern(let index):
            "The line has no pattern #\(index + 1)."
        case .invalidStationTile(let position):
            "A station can only grow onto an empty tile beside one of its tiles, not \(position)."
        case .invalidTrainLength:
            "A train has \(Train.minimumCars) to \(Train.maximumCars) cars."
        case .unknownTrackNode(let node):
            "\(node.displayText) is not a node of the track network."
        case .unknownTrackEdge(let edge):
            "\(edge.displayText) is not an edge of the track network."
        case .invalidTrackGeometry:
            "Track can't be built there: it must stay on the map within 64 m of the ground, start and end at different nodes, and run smoothly."
        case .trackNodeInUse(let node):
            "Track still ends at \(node.displayText.lowercased()). Remove that track first."
        case .trackEdgeInUse(let edge):
            "A train is on \(edge.displayText.lowercased()). Take the train off the track first."
        case .trackTooSteep:
            "That track would be too steep. Track may climb or fall at most 40 in 1000; make it longer or the height difference smaller."
        case .invalidTrackStructure:
            "That structure can't carry track at those heights: surface track stays within 2 m of the ground, viaducts and bridges above it, tunnels below it."
        case .trackConflict(let edge):
            "That track would cross \(edge.displayText.lowercased()) without 8 m between them. Pass over or under it, or cross at a shared node."
        case .trackEdgeHasPlatform(let edge):
            "A station has a platform on \(edge.displayText.lowercased()). Remove the platform first."
        case .invalidPlatform:
            "A platform must lie on a level stretch of one edge and not overlap another platform."
        case .trackReserved(let id):
            "Train #\(id.rawValue) holds that track under traffic control. Wait for it to clear the route."
        case .trainsShareTrack(let first, let second):
            "Trains #\(first.rawValue) and #\(second.rawValue) need the same track, so traffic control can't be turned on. Move one of them first."
        case .invalidStationDemand:
            // Money's text is only the digits, grouped by thousands.
            "A station starts 0 to \(Money(StationDemand.maximumDailyTrips).displayText) trips a day."
        case .invalidFareRules:
            "Fares must be 0 or more, and distance steps must start at 0 km, follow on without gaps, and end with one that has no end."
        }
    }
}

extension Money {
    /// The amount with thousands separators, such as "1,000,000".
    ///
    /// Deterministic rather than locale-dependent, so it reads the same in
    /// every message and test.
    public var displayText: String {
        let digits = String(amount.magnitude)
        var text = amount < 0 ? "-" : ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                text.append(",")
            }
            text.append(digit)
        }
        return text
    }
}

extension GameTime {
    public static let minutesPerDay: Int64 = 24 * 60

    /// Day and time of day, such as "Day 1 · 08:30". Minute 0 is the start of
    /// day 1. Display only: GameCore has no calendar.
    public var displayText: String {
        var day = minutes / Self.minutesPerDay
        var minuteOfDay = minutes % Self.minutesPerDay
        if minuteOfDay < 0 {
            minuteOfDay += Self.minutesPerDay
            day -= 1
        }
        return "Day \(day + 1) · \(Self.twoDigits(minuteOfDay / 60)):\(Self.twoDigits(minuteOfDay % 60))"
    }

    private static func twoDigits(_ value: Int64) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

extension GameSpeed {
    /// Compact label for the speed controls.
    public var label: String {
        switch self {
        case .paused: "Pause"
        case .normal: "1×"
        case .double: "2×"
        }
    }

    /// Spoken name, since "1×" reads poorly aloud.
    public var accessibilityName: String {
        switch self {
        case .paused: "Paused"
        case .normal: "Normal speed"
        case .double: "Double speed"
        }
    }
}

