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

    /// Why a train waits (decision 210): the cases of
    /// ``GameCore/GameWorld/routeWaitText(of:in:)``, short enough for a tag
    /// on the map beside its ring.
    public enum WaitReason: Hashable, Sendable {
        /// By plan, to meet a train coming the other way (decision 59).
        case meet
        /// By plan for a faster train behind (decision 59), or at a
        /// passing place the dispatcher sent it to (Stage V2).
        case standAside
        /// On its way, behind a train ahead (Stage U2).
        case following
        /// Due to leave, on a route another train holds.
        case route
        /// It and the trains it waits for wait for each other (Stage V2).
        case deadlock

        /// "Meet", "等交會": the tag's first word.
        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .meet: language.text("Meet", "等交會")
            case .standAside: language.text("Stand aside", "待避")
            case .following: language.text("Following", "跟車")
            case .route: language.text("Route", "等進路")
            case .deadlock: language.text("Deadlock", "死結")
            }
        }

        /// The tag: the reason, then the train it waits for, its name cut
        /// to ``nameLimit`` characters: "等交會 · 莒光 3".
        public func tag(holder name: String, in language: DisplayLanguage) -> String {
            let short = name.count > Self.nameLimit ? String(name.prefix(Self.nameLimit - 1)) + "…" : name
            return short.isEmpty ? text(in: language) : "\(text(in: language)) · \(short)"
        }

        /// The most characters of a train's name a tag shows.
        public static let nameLimit = 10
    }

    /// A train waiting for its route (see
    /// ``GameCore/GameWorld/trainHoldingRoute(of:)``).
    public struct Wait: Hashable, Sendable {
        public let train: TrainID
        /// The train holding its route.
        public let holder: TrainID
        /// Its name, for the tag (decision 210).
        public let holderName: String
        /// Why it waits (decision 210).
        public let reason: WaitReason
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

        public init(
            train: TrainID, holder: TrainID, holderName: String = "", reason: WaitReason, isDeadlocked: Bool,
            contested: Track, from: WorldCoordinate, to: WorldCoordinate, heading: PlanVector
        ) {
            self.train = train
            self.holder = holder
            self.holderName = holderName
            self.reason = reason
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
        var kinds = ScheduledWaitKinds()
        return trafficOverlay(routeWaits(), kinds: &kinds)
    }

    /// The overlay of `routeWaits`, this world's ``GameCore/GameWorld/routeWaits()``,
    /// with the kind of each scheduled wait taken from `kinds` or worked
    /// out and kept there.
    func trafficOverlay(_ routeWaits: [RouteWait], kinds: inout ScheduledWaitKinds) -> TrafficOverlay {
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
                train: train.id, holder: wait.holder, holderName: self.train(id: wait.holder)?.name ?? "#\(wait.holder.rawValue)",
                reason: waitReason(of: train, wait, kinds: &kinds), isDeadlocked: wait.isDeadlocked,
                contested: contested, from: head, to: target, heading: headLocation.direction
            ))
        }
        return overlay
    }

    /// Why `train` waits (decision 210), in the order
    /// ``GameCore/GameWorld/routeWaitText(of:in:)`` tells it: a deadlock,
    /// a scheduled wait (nothing contested: it waits by plan, not for
    /// track), a passing place, following, or a route.
    func waitReason(of train: Train, _ wait: RouteWait, kinds: inout ScheduledWaitKinds) -> TrafficOverlay.WaitReason {
        if wait.isDeadlocked { return .deadlock }
        if wait.contested.isEmpty, let execution = train.execution {
            return kinds.kind(of: train.id, holder: wait.holder, at: execution, in: self) == .overtake ? .standAside : .meet
        }
        if passingPlace(of: train.id) != nil { return .standAside }
        if case .travellingToStop? = train.execution { return .following }
        return .route
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

/// Whether each scheduled wait (decision 59) is a meet or an overtake,
/// kept from one tick's reading to the next (decision 210): the plan that
/// says so costs as much as the rest of the reading, and a wait keeps its
/// kind while it lasts, so the plan is asked again only when a train
/// starts a wait not seen before.
struct ScheduledWaitKinds: Sendable {
    struct Key: Hashable, Sendable {
        let train: TrainID
        let holder: TrainID
        let execution: TimetableExecution
    }

    private(set) var kinds: [Key: ScheduledTrafficWait.Kind] = [:]
    /// The plan's waits, asked at most once for this reading.
    private var plan: [ScheduledTrafficWait]?

    /// The kind of `train`'s wait for `holder` at `execution`'s stop: the
    /// plan's wait for that stop and cycle (as
    /// ``GameCore/GameWorld/scheduledTrafficWait(of:)`` finds it), a meet
    /// when the plan has none.
    mutating func kind(of train: TrainID, holder: TrainID, at execution: TimetableExecution, in world: GameWorld) -> ScheduledTrafficWait.Kind {
        let key = Key(train: train, holder: holder, execution: execution)
        if let kept = kinds[key] { return kept }
        if plan == nil { plan = world.scheduledTrafficWaits() }
        let kind = plan?.first {
            $0.train == train && $0.other == holder && $0.stop == execution.stop && $0.cycle == execution.cycle
        }?.kind ?? .meet
        kinds[key] = kind
        return kind
    }

    /// Only the kinds of the waits still going on, for the next reading:
    /// without the plan, which is of this world.
    func kept(for waits: [TrafficOverlay.Wait], in world: GameWorld) -> ScheduledWaitKinds {
        var next = ScheduledWaitKinds()
        for wait in waits {
            guard let execution = world.train(id: wait.train)?.execution else { continue }
            let key = Key(train: wait.train, holder: wait.holder, execution: execution)
            if let kind = kinds[key] { next.kinds[key] = kind }
        }
        return next
    }
}

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
    /// The kinds of the scheduled waits still going on (decision 210),
    /// for the next reading.
    let kinds: ScheduledWaitKinds

    /// The reading of `world`, with the words of `train`'s wait if it has
    /// one, and the kinds of scheduled waits `previous` (the last
    /// reading) already knew.
    public init(world: GameWorld, train: TrainID? = nil, in language: DisplayLanguage, previous: TrafficReading? = nil) {
        let waits = world.isTrafficControlEnabled ? world.routeWaits() : []
        var kinds = previous?.kinds ?? ScheduledWaitKinds()
        overlay = world.trafficOverlay(waits, kinds: &kinds)
        self.kinds = kinds.kept(for: overlay.waits, in: world)
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
