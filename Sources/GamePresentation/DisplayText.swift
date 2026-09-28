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
        default: return "Crossing"
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
