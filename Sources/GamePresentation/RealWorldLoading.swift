import GameCore

// The loading screen of a real-world map (ARCHITECTURE decision 307):
// while a real-world game's map is built, the company's name, the name of
// the place nearest where it starts, and three lines in the game's own
// line colours with a train running back and forth on each. With Reduce
// Motion the trains stand still (motion skill §3: nothing loops on its
// own).

/// What the loading screen shows while a real-world map is built.
public struct RealWorldLoading: Hashable, Sendable {
    /// The place the map starts at, in the player's language, or `nil`
    /// where the app has no name for it (abroad, at sea).
    public let place: String?

    public init(place: String?) {
        self.place = place
    }

    /// The name of the place nearest `anchor` in `names`: the nearest
    /// settlement, village or ward (``PlaceNames/nearby(_:)``), or else
    /// the township or district it is in; `nil` with neither.
    public static func placeName(near anchor: GeoAnchor, in names: PlaceNames?, language: DisplayLanguage) -> String? {
        guard let names else { return nil }
        let point = RealRailways.Coordinate(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees)
        return (names.nearby(point).first ?? names.township(containing: point))?.name(in: language)
    }
}

/// The lines drawn on the loading screen, in a square from (0, 0) at the
/// top left to (1, 1), and their trains.
public enum LoadingRoutes {
    /// A line: its stations, in order; the track runs straight between
    /// them.
    public struct Route: Hashable, Sendable {
        public let stations: [ScreenPoint]
        /// Where its train is at the start, as a share of the way along.
        public let start: Double

        /// The track's length.
        public var length: Double {
            zip(stations, stations.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        }

        /// The point `share` (0 to 1) of the way along the track.
        public func point(at share: Double) -> ScreenPoint {
            guard share < 1 else { return stations[stations.count - 1] }
            var left = max(share, 0) * length
            for (a, b) in zip(stations, stations.dropFirst()) {
                let step = distance(a, b)
                if left <= step, step > 0 {
                    let t = left / step
                    return ScreenPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                left -= step
            }
            return stations[stations.count - 1]
        }
    }

    /// Three lines, as a small network: one across, one down and one
    /// corner to corner, crossing at shared stations.
    public static let routes: [Route] = [
        Route(stations: [ScreenPoint(x: 0.08, y: 0.42), ScreenPoint(x: 0.34, y: 0.42), ScreenPoint(x: 0.62, y: 0.58), ScreenPoint(x: 0.92, y: 0.58)], start: 0.1),
        Route(stations: [ScreenPoint(x: 0.34, y: 0.1), ScreenPoint(x: 0.34, y: 0.42), ScreenPoint(x: 0.34, y: 0.9)], start: 0.55),
        Route(stations: [ScreenPoint(x: 0.12, y: 0.86), ScreenPoint(x: 0.62, y: 0.58), ScreenPoint(x: 0.88, y: 0.16)], start: 0.8),
    ]

    /// The seconds a train takes from one end of its line to the other: as
    /// a train that follows time it runs at an even speed (motion skill
    /// §2), slow enough to read as a train, not a spinner.
    public static let crossingSeconds = 3.2

    /// Where `route`'s train is, as a share of the way along, `elapsed`
    /// seconds after the screen showed: there and back, again and again.
    /// With `reduceMotion` it stays where it started.
    public static func share(of route: Route, elapsed: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return route.start }
        let travelled = (route.start + max(elapsed, 0) / crossingSeconds).truncatingRemainder(dividingBy: 2)
        return travelled <= 1 ? travelled : 2 - travelled
    }

    /// Where `route`'s train is, `elapsed` seconds after the screen showed.
    public static func train(of route: Route, elapsed: Double, reduceMotion: Bool) -> ScreenPoint {
        route.point(at: share(of: route, elapsed: elapsed, reduceMotion: reduceMotion))
    }
}

private func distance(_ a: ScreenPoint, _ b: ScreenPoint) -> Double {
    ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
}
