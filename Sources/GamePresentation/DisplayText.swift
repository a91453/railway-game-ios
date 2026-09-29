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
    /// What is on the tile at `position`, such as "Empty", "Track · Straight N–S"
    /// or "Station · Central".
    public func tileSummary(at position: GridPosition) -> String {
        switch map.tile(at: position)?.type {
        case nil: "Outside the map"
        case .empty?: "Empty"
        case .track(let connections)?: "Track · \(connections.summary)"
        case .station(let id)?: "Station · \(station(id: id)?.name ?? "#\(id.rawValue)")"
        }
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
    /// `stationsStoppedAt(by:)`.
    public func stationStopText(of id: TrainID) -> String? {
        let names = stationsStoppedAt(by: id).map { station(id: $0)?.name ?? "#\($0.rawValue)" }
        guard !names.isEmpty else { return nil }
        return "Stopped at \(names.joined(separator: ", "))"
    }
}

extension TrainPosition {
    /// Where a train is, exactly as GameCore records it: "At (3, 2), facing
    /// East" at a node, or "(3, 2) → (4, 2), 256 / 1024" on a link (the
    /// offset from the first tile, out of ``TrainPosition/linkLength``).
    public var displayText: String {
        switch self {
        case .atNode(let tile, let heading):
            "At \(tile), facing \(heading.name)"
        case .onLink(let from, let to, let offset):
            "\(from) → \(to), \(offset) / \(TrainPosition.linkLength)"
        }
    }
}

extension Train {
    /// The train's position, or "Not on the track" while it is unplaced.
    public var positionText: String {
        position?.displayText ?? "Not on the track"
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
    /// ending at (8, 3)".
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
            "Not enough cash: this costs \(required.displayText) and you have \(available.displayText)."
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
            "A train can only be placed on a track tile or between two joined track tiles."
        case .invalidMovementRate:
            "A train's rate cannot be negative."
        case .invalidContinuation:
            "The train cannot follow that path: each step must lead to joined track, without turning back."
        case .clockOverflow:
            "Game time cannot advance any further."
        case .idsExhausted:
            "This game has no IDs left for anything more of this kind."
        case .invalidTimetable:
            "A timetable's times cannot be negative or go back: each stop leaves no earlier than it arrives, and no later than the next stop arrives."
        case .unknownStation(let id):
            "There is no station #\(id.rawValue)."
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

