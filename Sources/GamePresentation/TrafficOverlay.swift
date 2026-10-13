import Foundation
import GameCore

// Stage V4e (ARCHITECTURE decision 64): what the map shows of traffic
// control, read from the world and never saved: with each tick, off the
// main actor (``TrafficReading``, decision 64's later fix).
// Each train's movement authority (the track it has reserved), and for
// each train waiting for its route the train it waits for and the track
// where the two meet, red where they wait for each other in a deadlock.
// The words for the same waits stay those of `routeWaitText(of:in:)`.

/// What the map draws for traffic control, in world coordinates.
public struct TrafficOverlay: Hashable, Sendable {
    /// Track drawn along its centre line: each stretch of one edge (the
    /// adjacent spans of a resource list joined), and each junction node.
    public struct Track: Hashable, Sendable {
        public var lines: [[WorldCoordinate]]
        public var nodes: [WorldCoordinate]

        public init(lines: [[WorldCoordinate]] = [], nodes: [WorldCoordinate] = []) {
            self.lines = lines
            self.nodes = nodes
        }

        public var isEmpty: Bool { lines.isEmpty && nodes.isEmpty }
    }

    /// The track a train has reserved ahead of it (see
    /// ``GameCore/GameWorld/reservedResources(of:)``).
    public struct Authority: Hashable, Sendable {
        public let train: TrainID
        public let track: Track

        public init(train: TrainID, track: Track) {
            self.train = train
            self.track = track
        }
    }

    /// A train waiting for its route (see
    /// ``GameCore/GameWorld/trainHoldingRoute(of:)``).
    public struct Wait: Hashable, Sendable {
        public let train: TrainID
        /// The train holding its route.
        public let holder: TrainID
        /// Whether the two are in a deadlock (see
        /// ``GameCore/GameWorld/deadlockedTrains()``).
        public let isDeadlocked: Bool
        /// The track of its route the holder keeps it from (see
        /// ``GameCore/GameWorld/contestedResources(of:)``); empty for a
        /// scheduled wait.
        public let contested: Track
        /// The waiting train's head.
        public let from: WorldCoordinate
        /// Where the wait is for: the point of the contested track nearest
        /// its head, or without one the holder's head.
        public let to: WorldCoordinate
        /// The way the waiting train faces at its head, not normalised:
        /// its mark moves aside across it (``WaitMarkSides``).
        public let heading: PlanVector

        public init(train: TrainID, holder: TrainID, isDeadlocked: Bool, contested: Track, from: WorldCoordinate, to: WorldCoordinate, heading: PlanVector) {
            self.train = train
            self.holder = holder
            self.isDeadlocked = isDeadlocked
            self.contested = contested
            self.from = from
            self.to = to
            self.heading = heading
        }
    }

    /// In train ID order.
    public var authorities: [Authority] = []
    /// In train ID order.
    public var waits: [Wait] = []

    public init() {}

    public var isEmpty: Bool { authorities.isEmpty && waits.isEmpty }

    /// For VoiceOver and the map's description: "Movement authority for 2
    /// trains · 1 waiting · 2 deadlocked"; "2 列車有行車授權 · 1 列等候
    /// · 2 列死結". `nil` when there is nothing to show.
    public func summary(in language: DisplayLanguage) -> String? {
        guard !isEmpty else { return nil }
        let deadlocked = waits.filter(\.isDeadlocked).count
        let waiting = waits.count - deadlocked
        var parts: [String] = []
        if !authorities.isEmpty {
            parts.append(language.text(
                "Movement authority for \(authorities.count) \(authorities.count == 1 ? "train" : "trains")",
                "\(authorities.count) 列車有行車授權"
            ))
        }
        if waiting > 0 { parts.append(language.text("\(waiting) waiting", "\(waiting) 列等候")) }
        if deadlocked > 0 { parts.append(language.text("\(deadlocked) deadlocked", "\(deadlocked) 列死結")) }
        return parts.joined(separator: " · ")
    }
}

extension GameWorld {
    /// What the map draws for traffic control (Stage V4e); empty with
    /// traffic control off. Derived on every call, never saved.
    public func trafficOverlay() -> TrafficOverlay {
        guard isTrafficControlEnabled else { return TrafficOverlay() }
        return trafficOverlay(routeWaits())
    }

    /// The overlay of `routeWaits`, this world's ``GameCore/GameWorld/routeWaits()``.
    func trafficOverlay(_ routeWaits: [RouteWait]) -> TrafficOverlay {
        var overlay = TrafficOverlay()
        guard isTrafficControlEnabled else { return overlay }
        // One pass for every wait (see routeWaits()), not three queries a train.
        let waits = Dictionary(uniqueKeysWithValues: routeWaits.map { ($0.train, $0) })
        for train in trains.sorted(by: { $0.id < $1.id }) {
            guard let position = train.position, let headLocation = location(of: position) else { continue }
            let head = headLocation.position
            let reserved = trafficTrack(reservedResources(of: train.id))
            if !reserved.isEmpty {
                overlay.authorities.append(.init(train: train.id, track: reserved))
            }
            guard let wait = waits[train.id] else { continue }
            let contested = trafficTrack(wait.contested)
            let points = contested.lines.flatMap { $0 } + contested.nodes
            let target = points.min { Self.squaredDistance($0, head) < Self.squaredDistance($1, head) }
                ?? self.train(id: wait.holder)?.position.flatMap { location(of: $0)?.position }
                ?? head
            overlay.waits.append(.init(
                train: train.id, holder: wait.holder, isDeadlocked: wait.isDeadlocked,
                contested: contested, from: head, to: target, heading: headLocation.direction
            ))
        }
        return overlay
    }

    /// `resources` on the map: the spans of each edge joined where one ends
    /// where the next starts, in edge and chainage order, then the nodes.
    func trafficTrack(_ resources: [TrackResource]) -> TrafficOverlay.Track {
        var track = TrafficOverlay.Track()
        var spans: [TrackSpan] = []
        for resource in resources {
            switch resource {
            case .node(let id):
                if let node = trackNode(id) { track.nodes.append(node.position) }
            case .span(let span):
                spans.append(span)
            }
        }
        var runs: [(edge: TrackEdgeID, start: Int64, end: Int64)] = []
        for span in spans.sorted() {
            if let last = runs.last, last.edge == span.edge, last.end == span.start {
                runs[runs.count - 1].end = span.end
            } else {
                runs.append((span.edge, span.start, span.end))
            }
        }
        for run in runs {
            guard let geometry = trackGeometry(of: run.edge), 0 <= run.start, run.start < run.end, run.end <= geometry.length else { continue }
            track.lines.append(geometry.points(from: run.start, to: run.end))
        }
        return track
    }

    private static func squaredDistance(_ a: WorldCoordinate, _ b: WorldCoordinate) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return dx * dx + dy * dy
    }
}

// MARK: - Read once a tick (decision 64, later fix)

/// What the map and the train tool show of traffic control for one world:
/// the overlay, and the selected train's wait in words, worked out with one
/// search for every wait (``GameCore/GameWorld/routeWaits()``). The game
/// loop works it out off the main actor with each tick (``GameSession``),
/// so the map no longer searches for deadlocks on the main actor at every
/// tick. Equal to asking the world each time: ``overlay`` is
/// ``GameCore/GameWorld/trafficOverlay()`` and ``waitText(of:in:language:)``
/// ``GameCore/GameWorld/routeWaitText(of:in:)``.
public struct TrafficReading: Sendable {
    public let overlay: TrafficOverlay
    /// The trains ``GameCore/GameWorld/routeWaits()`` names. A train on the
    /// track that is not one of them has no wait to put in words.
    let waiting: Set<TrainID>
    /// The words of the waits worked out so far, by train.
    private(set) var texts: [TrainID: String?] = [:]

    /// The reading of `world`, with the words of `train`'s wait if it has one.
    public init(world: GameWorld, train: TrainID? = nil, in language: DisplayLanguage) {
        let waits = world.isTrafficControlEnabled ? world.routeWaits() : []
        overlay = world.trafficOverlay(waits)
        waiting = Set(waits.map(\.train))
        if let train { _ = waitText(of: train, in: world, language: language) }
    }

    /// ``GameCore/GameWorld/routeWaitText(of:in:)`` of `world`, the world
    /// this was read from, kept once worked out. A placed train under
    /// traffic control that ``waiting`` does not name has none: the text
    /// is of the scheduled wait or the train holding its route, and
    /// `routeWaits()` names every train with either.
    public mutating func waitText(of id: TrainID, in world: GameWorld, language: DisplayLanguage) -> String? {
        if let kept = texts[id] { return kept }
        let text: String?
        if world.isTrafficControlEnabled, world.train(id: id)?.position != nil, !waiting.contains(id) {
            text = nil
        } else {
            text = world.routeWaitText(of: id, in: language)
        }
        texts[id] = text
        return text
    }
}

// MARK: - Marks side by side (decision 64, later fix)

/// The `Railway/` site's `blockSideShift` (index.html), for the rings round
/// waiting trains: where two waiting trains' marks would overlap on the
/// screen (trains side by side on double track, or one behind the other),
/// each is moved across its track, alternately to one side and the other,
/// by half the marks' size and half the gap between them, so both read.
public enum WaitMarkSides {
    /// A waiting train's mark on the screen.
    public struct Mark: Hashable, Sendable {
        public let train: TrainID
        public let center: ScreenPoint
        /// The way along the track on the screen, not normalised.
        public let along: ScreenPoint

        public init(train: TrainID, center: ScreenPoint, along: ScreenPoint) {
            self.train = train
            self.center = center
            self.along = along
        }
    }

    /// The site's `BLOCK_SIDE_GAP`: the space left between two marks, in points.
    public static let gap = 2.0

    /// How far to move each of `marks`, each `size` points across, on the
    /// screen; a mark that stays is left out. Marks closer than `size` to
    /// another are a group (the site's run of trains in one block); in
    /// train order, the first moves to the left of its track, the next to
    /// the right, and so on (the site's alternating `nat`). Each moves along
    /// its track's normal by half of `size` measured across that normal
    /// (the site's `(|nx|·near + |ny|·BLOCK_TAG_H) / 2`, a round mark being
    /// as tall as it is wide) and half the gap.
    public static func offsets(_ marks: [Mark], size: Double) -> [TrainID: ScreenPoint] {
        let marks = marks.sorted { $0.train < $1.train }
        // Groups of marks each within `size` of another of its group.
        var group = Array(marks.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while group[index] != index { index = group[index] }
            return index
        }
        for a in marks.indices {
            for b in marks.indices where b > a {
                let dx = marks[a].center.x - marks[b].center.x, dy = marks[a].center.y - marks[b].center.y
                if dx * dx + dy * dy < size * size {
                    let (ra, rb) = (root(a), root(b))
                    if ra != rb { group[max(ra, rb)] = min(ra, rb) }
                }
            }
        }
        var counts: [Int: Int] = [:]
        for index in marks.indices { counts[root(index), default: 0] += 1 }
        var placed: [Int: Int] = [:]
        var offsets: [TrainID: ScreenPoint] = [:]
        for (index, mark) in marks.enumerated() {
            let key = root(index)
            guard counts[key, default: 0] >= 2 else { continue }
            let order = placed[key, default: 0]
            placed[key] = order + 1
            let length = (mark.along.x * mark.along.x + mark.along.y * mark.along.y).squareRoot()
            guard length > 1e-9 else { continue }
            let nx = -mark.along.y / length, ny = mark.along.x / length
            let side: Double = order % 2 == 0 ? 1 : -1
            let amount = side * ((abs(nx) * size + abs(ny) * size) / 2 + gap / 2)
            offsets[mark.train] = ScreenPoint(x: nx * amount, y: ny * amount)
        }
        return offsets
    }
}

extension TrafficOverlay {
    /// How strongly a deadlocked train's mark shows at `time` seconds:
    /// it beats once every ``deadlockBeat`` seconds between full and 0.35,
    /// so a deadlock catches the eye (the flashing deadlock mark the UI
    /// port plan left for traffic control; the reference has none to
    /// port); steady at full when the player reduces motion.
    public static func deadlockStrength(at time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return 0.35 + 0.65 * (0.5 + 0.5 * cos(2 * Double.pi * time / deadlockBeat))
    }

    /// Seconds between two beats of a deadlocked train's mark.
    public static let deadlockBeat = 1.2
}
