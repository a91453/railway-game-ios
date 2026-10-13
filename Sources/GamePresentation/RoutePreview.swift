import Foundation
import GameCore

// ARCHITECTURE decision 201: which track a leg of a line takes, shown on the
// map. A TestFlight player could not tell which track a route choice in the
// line panel meant ("the route choices are numbers, but the map shows no
// numbers"): the panel listed track numbers the map never drew. The
// preview draws one leg's path as the line's trains would drive it, with
// arrows the way they go and each track's number along it, and only that
// leg's. The path is the line's own journey (``GameWorld/lineJourney``),
// worked out on a copy of the world with the leg's choice in place, so it is
// what the trains would do, not what the choice hoped for. Presentation
// only: nothing here is stored or changes the world.

/// One leg of a line's service on the map (decision 201): the pieces of
/// track its trains drive from one call to the next, in order.
public struct RoutePreview: Equatable, Sendable {
    /// Which physical path the leg is shown with.
    public enum Choice: Hashable, Sendable {
        /// As the line runs it now: its preference for the leg, if any.
        case current
        /// With no preference: the path the trains find themselves.
        case automatic
        /// With `preference` in place of the leg's own.
        case preference(LineRoutePreference)
    }

    /// What to show: the leg of line `line`'s service (its own, or its
    /// pattern at index `pattern`) from call `from` to call `to` (indices
    /// in the line's stops), with `choice`.
    public struct Request: Hashable, Sendable {
        public let line: LineID
        public let pattern: Int?
        public let from: Int
        public let to: Int
        public let choice: Choice

        public init(line: LineID, pattern: Int?, from: Int, to: Int, choice: Choice = .current) {
            self.line = line
            self.pattern = pattern
            self.from = from
            self.to = to
            self.choice = choice
        }

        /// Whether `self` shows the same leg as `other`, whatever its choice.
        public func isLeg(of other: Request) -> Bool {
            line == other.line && pattern == other.pattern && from == other.from && to == other.to
        }
    }

    /// A piece of one edge the leg drives: the way it drives it, and where
    /// the piece starts and ends measured from the edge's `from` node
    /// (`start < end`), whichever way it is driven.
    public struct Piece: Equatable, Sendable {
        public let traversal: TrackTraversal
        public let start: Int64
        public let end: Int64

        public init(traversal: TrackTraversal, start: Int64, end: Int64) {
            self.traversal = traversal
            self.start = start
            self.end = end
        }

        public var edge: TrackEdgeID { traversal.edge }
        /// Whether the trains drive it from the edge's `from` node towards
        /// its `to` node.
        public var isForward: Bool { traversal.direction == .forward }
    }

    public let request: Request
    /// The line's colour, or `nil` for its default one.
    public let color: LineColor?
    /// The pieces in the order the trains drive them; never empty.
    public let pieces: [Piece]
    /// Whether the trains would take the path `request`'s choice asks for:
    /// a walk of tracks the leg cannot start from is dropped by the world,
    /// which then finds a path of its own. Always `true` for
    /// ``Choice/current`` and ``Choice/automatic``.
    public let followsChoice: Bool
    /// A point on the path near its middle, for the camera.
    public let focus: WorldCoordinate?

    /// The leg `request` asks for in `world`, or `nil` when the line, its
    /// pattern or the leg does not exist, the choice does not fit the leg,
    /// or the line's journey cannot be driven. A ring is shown the way its
    /// journey goes (inner); a leg only its other way takes has no preview.
    ///
    /// Costs one ``GameWorld/lineJourney(_:pattern:)``.
    public init?(_ request: Request, in world: GameWorld) {
        guard let line = world.line(id: request.line) else { return nil }
        if let pattern = request.pattern, !line.patterns.indices.contains(pattern) { return nil }
        var world = world
        var routes = request.pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
        switch request.choice {
        case .current:
            break
        case .automatic, .preference:
            routes.removeAll { $0.from == request.from && $0.to == request.to }
            if case .preference(let preference) = request.choice {
                guard preference.from == request.from, preference.to == request.to else { return nil }
                routes.append(preference)
            }
            do throws(GameError) {
                try world.setLineRoutePreferences(line.id, to: routes, pattern: request.pattern)
            } catch {
                return nil
            }
        }
        guard let journey = world.lineJourney(line.id, pattern: request.pattern),
              let index = journey.legs.firstIndex(where: { $0.from == request.from && $0.to == request.to }) else { return nil }
        let legs = LineMap.legPieces(of: journey, in: world.network)
        guard legs.indices.contains(index) else { return nil }
        let pieces = legs[index].map { traversal, a, b in
            let length = world.network.edge(traversal.edge)?.length ?? 0
            return traversal.direction == .forward
                ? Piece(traversal: traversal, start: a, end: b)
                : Piece(traversal: traversal, start: length - b, end: length - a)
        }
        guard !pieces.isEmpty else { return nil }
        self.request = request
        self.color = line.color
        self.pieces = pieces
        if case .preference(let preference) = request.choice {
            let driven = pieces.map(\.traversal)
            self.followsChoice = pieces.last?.edge == preference.platform.edge
                && Self.contains(driven, inOrder: preference.tracks)
        } else {
            self.followsChoice = true
        }
        let middle = pieces[pieces.count / 2]
        self.focus = world.trackGeometry(of: middle.edge).flatMap { geometry in
            let half = (middle.start + middle.end) / 2
            return half < geometry.length ? geometry.points(from: half, to: half + 1).first : nil
        }
    }

    /// Whether `walk` holds `tracks` in their order, one after the other.
    private static func contains(_ walk: [TrackTraversal], inOrder tracks: [TrackTraversal]) -> Bool {
        guard !tracks.isEmpty else { return true }
        guard walk.count >= tracks.count else { return false }
        return (0...(walk.count - tracks.count)).contains { Array(walk[$0..<($0 + tracks.count)]) == tracks }
    }

    /// The numbers of the tracks driven, in order, each once where the
    /// path stays on it.
    public var trackNumbers: [Int] {
        Self.distinctInOrder(pieces.map { Self.number(of: $0.edge) })
    }

    /// "Tracks #3 → #4 → #5, stopping on #5", or in Chinese "經由軌段 #3 →
    /// #4 → #5，停在 #5"; with a choice the trains cannot take, what they
    /// take instead.
    public func text(in language: DisplayLanguage) -> String {
        let numbers = trackNumbers
        let walk = numbers.map { "#\($0)" }.joined(separator: " → ")
        let last = numbers.last.map { "#\($0)" } ?? ""
        let path = numbers.count == 1
            ? language.text("Stays on track \(walk)", "停在軌段 \(walk)")
            : language.text("Tracks \(walk), stopping on \(last)", "經由軌段 \(walk)，停在 \(last)")
        guard !followsChoice else { return path }
        return language.text(
            "This choice does not join the track the train comes from; it would take: \(path)",
            "這個選擇接不上列車來的軌道，列車會改走：\(path)"
        )
    }

    // MARK: - Texts of the choices

    /// A track's number on the map and in the panel: "#7".
    public static func label(of edge: TrackEdgeID) -> String {
        "#\(number(of: edge))"
    }

    static func number(of edge: TrackEdgeID) -> Int {
        switch edge { case .edge(let number): number }
    }

    /// What the line panel's route menu says of `preference`, in the
    /// words the map and the select tool use (decision 201): "Platform on
    /// track #7 · route chosen automatically", "Tracks #16 → #15 → #7
    /// (platform)"; in Chinese "月台在軌段 #7・自動選路", "軌段 #16 → #15 →
    /// #7（月台）". The way each track is driven is left to the map's
    /// arrows.
    public static func choiceText(_ preference: LineRoutePreference, in language: DisplayLanguage) -> String {
        let platform = label(of: preference.platform.edge)
        guard !preference.tracks.isEmpty else {
            return language.text("Platform on track \(platform) · route chosen automatically", "月台在軌段 \(platform)・自動選路")
        }
        let walk = distinctInOrder(preference.tracks.map { number(of: $0.edge) }).map { "#\($0)" }.joined(separator: " → ")
        return language.text("Tracks \(walk) (platform)", "軌段 \(walk)（月台）")
    }

    /// ``choiceText(_:in:)`` of each of `choices`, a repeated text
    /// numbered ("(2)", "(3)", …) so that no two entries of the menu read
    /// the same: two walks over the same tracks driven different ways.
    public static func choiceTexts(_ choices: [LineRoutePreference], in language: DisplayLanguage) -> [String] {
        var seen: [String: Int] = [:]
        return choices.map { choice in
            let text = choiceText(choice, in: language)
            let count = seen[text, default: 0] + 1
            seen[text] = count
            return count == 1 ? text : "\(text) (\(count))"
        }
    }

    private static func distinctInOrder(_ numbers: [Int]) -> [Int] {
        var kept: [Int] = []
        for number in numbers where kept.last != number { kept.append(number) }
        return kept
    }
}

// MARK: - Marks along a drawn path

/// Where to put marks along a polyline on the screen (decision 201): the
/// arrows along a previewed leg or a line ridden one way, and the number
/// of a track at its middle. Pure geometry, so the map's placement is
/// tested on Linux.
public enum PolylineMarks {
    /// A mark: where it stands and the way the polyline goes there, in
    /// radians from the screen's x axis (y grows down).
    public struct Mark: Equatable, Sendable {
        public let point: ScreenPoint
        public let angle: Double

        public init(point: ScreenPoint, angle: Double) {
            self.point = point
            self.angle = angle
        }
    }

    /// Marks every `spacing` points along `points`, the first half a
    /// spacing in, so a polyline shorter than `spacing` still has one at
    /// its middle; at most `limit`. A polyline of no length has none.
    public static func marks(along points: [ScreenPoint], spacing: Double, limit: Int = 200) -> [Mark] {
        let length = self.length(of: points)
        guard length > 0, spacing > 0 else { return [] }
        let count = min(limit, max(1, Int(length / spacing)))
        let gap = length / Double(count)
        return (0..<count).compactMap { mark(along: points, at: gap / 2 + gap * Double($0)) }
    }

    /// The mark at the middle of `points`, or `nil` for a polyline of no
    /// length.
    public static func middle(of points: [ScreenPoint]) -> Mark? {
        let length = self.length(of: points)
        return length > 0 ? mark(along: points, at: length / 2) : nil
    }

    /// The mark `distance` points along `points`.
    static func mark(along points: [ScreenPoint], at distance: Double) -> Mark? {
        var travelled = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let step = (dx * dx + dy * dy).squareRoot()
            guard step > 0 else { continue }
            if travelled + step >= distance {
                let t = (distance - travelled) / step
                return Mark(point: ScreenPoint(x: a.x + dx * t, y: a.y + dy * t), angle: atan2(dy, dx))
            }
            travelled += step
        }
        return nil
    }

    /// How long `points` run on the screen, in points.
    public static func length(of points: [ScreenPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { sum, pair in
            let dx = pair.1.x - pair.0.x, dy = pair.1.y - pair.0.y
            return sum + (dx * dx + dy * dy).squareRoot()
        }
    }

    /// `mark` moved `distance` points to the left of the way it points (a
    /// negative distance to the right), as the map moves a line beside
    /// the track (``LineMap/Stretch/offset``).
    public static func shifted(_ mark: Mark, by distance: Double) -> Mark {
        // The left of a step on the screen, whose y grows down.
        let left = (x: sin(mark.angle), y: -cos(mark.angle))
        return Mark(point: ScreenPoint(x: mark.point.x + left.x * distance, y: mark.point.y + left.y * distance), angle: mark.angle)
    }
}

// MARK: - The session's preview

extension GameSession {
    /// The leg of the selected line shown on the map (decision 201), or
    /// `nil`: worked out once for each command, as only a command changes
    /// the track and the lines. A preview of another line than the
    /// selected one is not shown.
    public var routePreview: RoutePreview? {
        guard let request = routePreviewRequest, request.line == selectedLineID else { return nil }
        if let kept = routePreviewMemo, kept.revision == commandRevision, kept.request == request { return kept.preview }
        let preview = RoutePreview(request, in: world)
        routePreviewMemo = (commandRevision, request, preview)
        return preview
    }

    /// Shows the leg of the selected line's service (its own, or its
    /// pattern at index `pattern`) from call `from` to call `to` on the
    /// map, with `choice`.
    public func previewRoute(from: Int, to: Int, pattern: Int?, choice: RoutePreview.Choice = .current) {
        guard let line = selectedLineID else { return }
        routePreviewRequest = RoutePreview.Request(line: line, pattern: pattern, from: from, to: to, choice: choice)
    }

    /// Whether the map shows that leg of the selected line, with any choice.
    public func isPreviewingRoute(from: Int, to: Int, pattern: Int?) -> Bool {
        guard let request = routePreviewRequest, let line = selectedLineID else { return false }
        return request.isLeg(of: RoutePreview.Request(line: line, pattern: pattern, from: from, to: to))
    }

    /// Stops showing that leg; another leg's preview stays.
    public func endRoutePreview(from: Int, to: Int, pattern: Int?) {
        if isPreviewingRoute(from: from, to: to, pattern: pattern) { routePreviewRequest = nil }
    }

    /// Stops showing any leg: the line panel closed.
    public func endRoutePreviews() {
        if routePreviewRequest != nil { routePreviewRequest = nil }
    }
}
