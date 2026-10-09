import GameCore

// Tap to look, hold to change (ARCHITECTURE decision 119). SimCity BuildIt
// answers a tap on a building with a small tag over it (its name and what
// it gives) and a long press with picking it up to change; TheoTown opens a
// dialog in the middle of the screen, which hides the map. Here a tap on a
// station shows a tag over it; the tag opens the details, and holding the
// station (or the tag's pencil) opens the station's panel. Read from the
// world each time it is drawn; nothing is stored.

/// What the tag over a selected station shows.
public struct StationTag: Hashable, Sendable {
    /// One line calling at the station, for its colour.
    public struct LineMark: Hashable, Sendable {
        public let id: LineID
        /// The player's colour, `nil` for the line's own (``LineColor``).
        public let color: LineColor?

        public init(id: LineID, color: LineColor?) {
            self.id = id
            self.color = color
        }
    }

    public let station: StationID
    public let name: String
    /// Where the station stands: the tag stands over it.
    public let location: PlanPoint
    /// Everyone waiting there, on every line and both ways.
    public let waiting: Int64
    /// The lines calling there, by ID.
    public let lines: [LineMark]

    public init(station: StationID, name: String, location: PlanPoint, waiting: Int64, lines: [LineMark]) {
        self.station = station
        self.name = name
        self.location = location
        self.waiting = waiting
        self.lines = lines
    }

    /// The tag for station `id` of `world`; `nil` for an ID it does not
    /// have.
    public init?(world: GameWorld, station id: StationID) {
        guard let station = world.station(id: id) else { return nil }
        self.init(
            station: id,
            name: station.name,
            location: station.location,
            waiting: world.waitingPassengers(at: id).reduce(Int64(0)) { $0 + $1.count },
            lines: world.lines(callingAt: id).map { LineMark(id: $0.id, color: $0.color) }
        )
    }

    /// "123 waiting", or `nil` with no one waiting.
    public func waitingText(in language: DisplayLanguage) -> String? {
        guard waiting > 0 else { return nil }
        return language.text("\(Money(waiting).displayText) waiting", "候車 \(Money(waiting).displayText) 人")
    }
}

extension GameSession {
    /// A long press on the map at `point` (decision 119): selects the
    /// station there, found as a tap finds one (``tapMap(at:reach:)``),
    /// and returns it, for the app to open its panel; `nil`, selecting
    /// nothing, where there is none. Never changes the world.
    public func holdMap(at point: PlanPoint, reach: Int64) -> StationID? {
        guard world.bounds.contains(point),
              let station = world.station(near: point, within: reach / 2) ?? world.station(near: point, within: reach)
        else { return nil }
        selectStation(station.id)
        return station.id
    }
}
