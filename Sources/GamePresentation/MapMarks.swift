import GameCore

/// Decision 377 (§22.2 25a, after decision 367; TestFlight 84.1: the whole
/// High Speed Rail at 6000×, 3 fps, 360 ms of the longest frame "other"):
/// what the map's alert bubbles and sight marks show of the world. Read
/// through ``GameSession/mapBubbles`` and ``GameSession/mapSights``, each
/// changed only when it differs: the two views read the world themselves (every alert, every
/// sight's stars and station, the names the bubbles give), so every tick
/// rebuilt them and every bubble and mark in them.
public struct MapMarks: Equatable, Sendable {
    /// An alert (``GameWorld/mapAlerts()`` and
    /// ``GameSession/situationAlerts``) and what its bubble names.
    public struct Bubble: Equatable, Sendable {
        public let alert: MapAlert
        /// The line's name, for a line without trains or losing money.
        public let lineName: String?
        /// The stuck train's name.
        public let trainName: String?
        /// The sight with no station.
        public let sight: Attraction?
        /// Why a crowded or full station's passengers wait (decision 210).
        public let waitReason: StationWaitReason?
    }

    /// A sight (decision 174) and its rating now.
    public struct Sight: Equatable, Sendable {
        public let attraction: Attraction
        /// ``GameWorld/stars(of:)``.
        public let stars: Int
        /// Whether a station serves it (``GameWorld/attractionStation(of:)``).
        public let isServed: Bool

        /// "3.75★" (``GameWorld/starsText(of:)``).
        public var starsText: String {
            StationMasterAdvice.starsText(stars)
        }
    }

    public var bubbles: [Bubble]
    public var sights: [Sight]

    public init(bubbles: [Bubble] = [], sights: [Sight] = []) {
        self.bubbles = bubbles
        self.sights = sights
    }

    /// What `world` shows, with the session's `situationAlerts`.
    public init(world: GameWorld, situationAlerts: [MapAlert]) {
        bubbles = (world.mapAlerts() + situationAlerts).map { alert in
            var lineName: String?, trainName: String?, sight: Attraction?, waitReason: StationWaitReason?
            switch alert.kind {
            case .lineWithoutTrains(let id), .lineLosingMoney(let id): lineName = world.line(id: id)?.name
            case .trainStuck(let id): trainName = world.train(id: id)?.name
            case .sightWithoutStation(let id): sight = world.attraction(id: id)
            case .crowded, .full: waitReason = alert.station.flatMap { world.stationWaitReason(of: $0) }
            default: break
            }
            return Bubble(alert: alert, lineName: lineName, trainName: trainName, sight: sight, waitReason: waitReason)
        }
        sights = (world.tourism?.attractions ?? []).map { sight in
            Sight(attraction: sight, stars: world.stars(of: sight), isServed: world.attractionStation(of: sight.id) != nil)
        }
    }
}

extension GameSession {
    /// Works ``mapBubbles`` and ``mapSights`` out again after the world
    /// changed, and sets each only when it differs; the same for
    /// ``adviceHour``.
    func refreshMapMarks() {
        let hour = world.clock.now.seconds / GameTime.secondsPerHour
        if hour != adviceHour { adviceHour = hour }
        let marks = MapMarks(world: world, situationAlerts: situationAlerts)
        if marks.bubbles != mapBubbles { mapBubbles = marks.bubbles }
        if marks.sights != mapSights { mapSights = marks.sights }
    }
}
