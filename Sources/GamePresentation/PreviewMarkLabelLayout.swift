// Decision 826, later (the owner's report, 2026-11-18): the network tool's
// preview labels its tightest curve ("Radius 150 · 65 km/h") in a capsule
// over the dot. The tightest point of a curve leaving a node is often the
// node itself, where the start flag stands over its point, and the flag
// covered the middle of the capsule. Each capsule now goes where it covers
// neither flag, nor the anchors' dots, nor a capsule placed before it, and
// crosses as little of the track previewed as it can: over the dot as
// before when that is clear, else beside the flag at the same height, else
// under the dot, else beside it. The dot stays where the curve is tightest,
// so the mark still says where. The owner's references draw no such
// labels (MapBuilder's and `Simulator/`'s previews checked for decision
// 826): the project's own, a map labeller's usual candidate positions.

/// Where the capsules naming the preview's tightest curve and steepest
/// grade go, in the screen's points, kept off the flags at the stretch's
/// ends and off each other.
public enum PreviewMarkLabelLayout {
    /// The gap between a mark's dot and its capsule, as before.
    public static let gap = 10.0
    /// The gap kept between a capsule and a flag beside it.
    public static let flagGap = 4.0
    /// A flag's badge: 28 points across, standing 8 points over its point
    /// (``MapBuildConfirm``'s flag).
    public static let flagSize = 28.0
    public static let flagLift = 8.0
    /// An anchor's dot, as far as a capsule keeps from its centre.
    public static let anchorReach = 7.0
    /// How close the track may come to a capsule's edge, in points: about
    /// half the preview's line.
    public static let trackReach = 3.0

    /// The places a capsule is tried in, in order: the first that covers
    /// nothing wins, and among those that cover something, the one that
    /// covers least.
    public enum Side: CaseIterable, Sendable {
        /// Centred over the dot: where it always was.
        case above
        /// Over the dot's height, past a flag standing there.
        case aboveTrailing, aboveLeading
        case below
        case belowTrailing, belowLeading
        case trailing, leading
    }

    /// The frame of a capsule `size` across and high on `side` of a dot at
    /// `point`.
    public static func frame(_ side: Side, at point: ScreenPoint, size: (width: Double, height: Double)) -> ScreenFrame {
        let (width, height) = size
        let besideFlag = flagSize / 2 + flagGap
        let x: Double, y: Double
        switch side {
        case .above: (x, y) = (point.x - width / 2, point.y - gap - height)
        case .aboveTrailing: (x, y) = (point.x + besideFlag, point.y - gap - height)
        case .aboveLeading: (x, y) = (point.x - besideFlag - width, point.y - gap - height)
        case .below: (x, y) = (point.x - width / 2, point.y + gap)
        case .belowTrailing: (x, y) = (point.x + besideFlag, point.y + gap)
        case .belowLeading: (x, y) = (point.x - besideFlag - width, point.y + gap)
        case .trailing: (x, y) = (point.x + gap, point.y - height / 2)
        case .leading: (x, y) = (point.x - gap - width, point.y - height / 2)
        }
        return ScreenFrame(x: x, y: y, width: width, height: height)
    }

    /// A flag's badge over its `point`.
    public static func flagFrame(at point: ScreenPoint) -> ScreenFrame {
        ScreenFrame(x: point.x - flagSize / 2, y: point.y - flagLift - flagSize, width: flagSize, height: flagSize)
    }

    /// The frames of capsules `sizes` over the dots at `points`, in that
    /// order, each kept off the flags at `flags`, their anchors' dots, the
    /// capsules before it and, as far as it can, the line `track`.
    public static func place(
        _ labels: [(point: ScreenPoint, size: (width: Double, height: Double))],
        flags: [ScreenPoint], track: [ScreenPoint]
    ) -> [ScreenFrame] {
        var solid = flags.flatMap { flag in
            [flagFrame(at: flag), ScreenFrame(x: flag.x - anchorReach, y: flag.y - anchorReach, width: 2 * anchorReach, height: 2 * anchorReach)]
        }
        let samples = sampled(track)
        var placed: [ScreenFrame] = []
        for label in labels {
            var best: (frame: ScreenFrame, score: Double)?
            for (order, side) in Side.allCases.enumerated() {
                let frame = frame(side, at: label.point, size: label.size)
                let covered = solid.reduce(0.0) { $0 + overlap(frame, $1) }
                let crossed = samples.filter { inside($0, frame, by: trackReach) }.count
                // Covering a flag or a capsule is worse than any crossing
                // of the track; the order breaks ties.
                let score = (covered > 0 ? 1_000_000 + covered : 0) + Double(crossed) * 100 + Double(order)
                if best.map({ score < $0.score }) ?? true { best = (frame, score) }
                if score < 100 { break }
            }
            guard let frame = best?.frame else { continue }
            placed.append(frame)
            solid.append(frame)
        }
        return placed
    }

    /// The points of `line` at most 3 points apart, so a capsule cannot
    /// sit between two far points of it unseen.
    static func sampled(_ line: [ScreenPoint]) -> [ScreenPoint] {
        guard var last = line.first else { return [] }
        var points = [last]
        for point in line.dropFirst() {
            let dx = point.x - last.x, dy = point.y - last.y
            let steps = min(2_000, max(1, Int(((dx * dx + dy * dy).squareRoot() / 3).rounded(.up))))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                points.append(ScreenPoint(x: last.x + dx * t, y: last.y + dy * t))
            }
            last = point
        }
        return points
    }

    static func overlap(_ a: ScreenFrame, _ b: ScreenFrame) -> Double {
        let across = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let down = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        return across > 0 && down > 0 ? across * down : 0
    }

    static func inside(_ point: ScreenPoint, _ frame: ScreenFrame, by reach: Double) -> Bool {
        point.x > frame.x - reach && point.x < frame.x + frame.width + reach
            && point.y > frame.y - reach && point.y < frame.y + frame.height + reach
    }
}
