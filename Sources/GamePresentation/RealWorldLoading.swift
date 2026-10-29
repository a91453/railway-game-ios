import Foundation
import GameCore

// The loading screen of a real-world map (ARCHITECTURE decision 307):
// while a real-world game's map is built, the company's name, the name of
// the place nearest where it starts, and three lines in the game's own
// line colours with a train running back and forth on each. With Reduce
// Motion the trains stand still (motion skill §3: nothing loops on its
// own).
//
// Decision 473: it also shows how far the build has come, step by step,
// and has a button back to the screen it was opened from.

/// One step of building a game the loading screen waits for. It is shown
/// as done only once its work has finished (decision 473): no step is
/// timed or guessed.
public enum LoadingStep: Hashable, Sendable {
    /// Reading a saved game from its file.
    case readingSave
    /// Working out how many people and jobs a real-world map's riders
    /// stand for (``RealWorldExpansion/ridersStep(population:places:water:)``).
    case countingPeople
    /// Making the world: its map, land and towns.
    case layingOutMap
    /// Laying a demo's line, its stations and its trains.
    case layingLine
    /// Raising the map to the real ground's heights.
    case shapingGround
    /// Reading the roads of the map's land; the one step whose own share
    /// done is counted as well, tile by tile.
    case readingRoads

    /// What the step does, for the player.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .readingSave: language.text("Reading the save", "讀取存檔")
        case .countingPeople: language.text("Counting people and jobs", "計算人口與工作")
        case .layingOutMap: language.text("Laying out the map", "鋪開地圖")
        case .layingLine: language.text("Laying the line and its trains", "鋪設路線與列車")
        case .shapingGround: language.text("Shaping the ground", "整理地形高低")
        case .readingRoads: language.text("Reading the roads", "讀入道路")
        }
    }
}

/// What the loading screen shows while a real-world map is built or a
/// save is read.
public struct RealWorldLoading: Hashable, Sendable {
    /// The screen the loading screen's button goes back to.
    public enum BackTo: Hashable, Sendable {
        case startScreen
        /// The game being played, when a save is read from it.
        case game
    }

    /// The place the map starts at, in the player's language, or `nil`
    /// where the app has no name for it (abroad, at sea).
    public let place: String?
    /// The steps of the build, in the order they run.
    public let steps: [LoadingStep]
    /// How many of ``steps`` have finished.
    public private(set) var done = 0
    /// The share (0 to 1) of the step running that is done, where it is
    /// counted (``LoadingStep/readingRoads``); 0 otherwise.
    public private(set) var stepShare = 0.0
    /// Where cancelling goes back to.
    public let backTo: BackTo

    public init(place: String?, steps: [LoadingStep] = [], backTo: BackTo = .startScreen) {
        self.place = place
        self.steps = steps
        self.backTo = backTo
    }

    /// The step running, or the last once all are done (the game is then
    /// opening); `nil` without steps.
    public var step: LoadingStep? {
        steps.isEmpty ? nil : steps[min(done, steps.count - 1)]
    }

    /// How much of the build is done, 0 to 1: the steps finished, each an
    /// equal share, and the share counted of the one running. It only
    /// grows.
    public var fraction: Double {
        guard !steps.isEmpty else { return 0 }
        return min(1, (Double(done) + min(max(stepShare, 0), 1)) / Double(steps.count))
    }

    /// Whether the screen shows its progress bar: with more than one step,
    /// or a step whose own share is counted.
    public var showsProgress: Bool {
        steps.count > 1 || step == .readingRoads
    }

    /// This loading with the step running finished.
    public func advanced() -> RealWorldLoading {
        var next = self
        next.done = min(done + 1, steps.count)
        next.stepShare = 0
        return next
    }

    /// This loading with `share` of the step running done; never less
    /// than before.
    public func counting(_ share: Double) -> RealWorldLoading {
        var next = self
        next.stepShare = max(stepShare, min(max(share, 0), 1))
        return next
    }

    /// The step line under the place: "Step 2 of 3: Reading the roads",
    /// or the step alone when there is one; `nil` without steps.
    public func stepLine(in language: DisplayLanguage) -> String? {
        guard let step else { return nil }
        let text = step.text(in: language)
        guard steps.count > 1 else { return text }
        let number = min(done + 1, steps.count)
        return language.text("Step \(number) of \(steps.count): \(text)", "第 \(number) 步，共 \(steps.count) 步：\(text)")
    }

    /// The share done as the player reads it: "40%".
    public func percentText() -> String {
        "\(Int((fraction * 100).rounded(.down)))%"
    }

    /// The title of the button that stops the loading.
    public func cancelTitle(in language: DisplayLanguage) -> String {
        switch backTo {
        case .startScreen: language.text("Back to Start Screen", "回開始畫面")
        case .game: language.text("Back to Game", "回到遊戲")
        }
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

/// Decision 473: what a step running off the main actor shares with the
/// launcher: the share of it done, and whether the player stopped the
/// loading, so a long step (reading roads) stops at its next tile rather
/// than running on for nothing.
final class LoadingMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var shareDone = 0.0
    private var stopped = false

    /// The share (0 to 1) of the step running that is done.
    var share: Double {
        get { lock.withLock { shareDone } }
        set { lock.withLock { shareDone = newValue } }
    }

    /// Whether the loading was stopped.
    var isCancelled: Bool { lock.withLock { stopped } }

    func cancel() { lock.withLock { stopped = true } }

    /// Back to none done, for the next step.
    func reset() { share = 0 }
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
