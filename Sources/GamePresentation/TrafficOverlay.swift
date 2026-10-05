import GameCore

// Stage V4e (ARCHITECTURE decision 64): what the map shows of traffic
// control, read from the world each time the map is drawn and never kept.
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

        public init(train: TrainID, holder: TrainID, isDeadlocked: Bool, contested: Track, from: WorldCoordinate, to: WorldCoordinate) {
            self.train = train
            self.holder = holder
            self.isDeadlocked = isDeadlocked
            self.contested = contested
            self.from = from
            self.to = to
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
        var overlay = TrafficOverlay()
        guard isTrafficControlEnabled else { return overlay }
        // One pass for every wait (see routeWaits()), not three queries a train.
        let waits = Dictionary(uniqueKeysWithValues: routeWaits().map { ($0.train, $0) })
        for train in trains.sorted(by: { $0.id < $1.id }) {
            guard let position = train.position, let head = location(of: position)?.position else { continue }
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
                contested: contested, from: head, to: target
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
