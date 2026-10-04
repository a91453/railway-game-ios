// The vertical dimension of the track network (Phase 4.5 Stage S4,
// ARCHITECTURE decision 30). A node's height is its z; along an edge the
// height follows the edge's vertical profile, worked out from the heights of
// its end nodes and two integers by the exact rules in TrackGeometry. An
// edge's structure (surface, elevated, bridge, tunnel) says what carries the
// track, which heights it may take and what it costs. Heights and grades
// never move a train: its length along the track is the horizontal chainage
// of Stage S3, and grades matter to running only from Stage W.

/// A gradient: the rise over a horizontal run, in lowest terms with a
/// positive run. Positive climbs in the direction it is measured.
///
/// Exact integers: a grade is compared by cross-multiplying, never by
/// converting it to a floating-point value.
public struct TrackGrade: Hashable, Sendable {
    public let rise: Int64
    public let run: Int64

    /// The grade `rise` over `run`, reduced to lowest terms.
    ///
    /// - Precondition: `run > 0` and `rise != Int64.min`.
    public init(rise: Int64, run: Int64) {
        precondition(run > 0 && rise != .min, "a grade needs a positive run")
        let divisor = rise == 0 ? run : FixedPoint.greatestCommonDivisor(rise, run)
        self.rise = rise / divisor
        self.run = run / divisor
    }

    /// No rise at all.
    public static let level = TrackGrade(rise: 0, run: 1)

    /// The same slope measured the other way.
    public var reversed: TrackGrade {
        TrackGrade(rise: -rise, run: run)
    }

    /// Whether this grade, up or down, is no steeper than `other`, up or
    /// down: `|rise| × other.run <= |other.rise| × run`, multiplied in 128
    /// bits so it never overflows.
    public func isNoSteeper(than other: TrackGrade) -> Bool {
        let left = rise.magnitude.multipliedFullWidth(by: other.run.magnitude)
        let right = other.rise.magnitude.multipliedFullWidth(by: run.magnitude)
        return left.high < right.high || (left.high == right.high && left.low <= right.low)
    }
}

/// The vertical profile of an edge: how its height changes from its `from`
/// node to its `to` node along the chainage (see
/// ``TrackGeometry/height(at:)``).
///
/// With no transitions the edge climbs or falls at one grade from end to
/// end (level when its ends are at one height). A transition at an end is a
/// vertical curve that length long: the edge leaves or reaches that end
/// level, and the grade changes evenly to the edge's steady grade.
public struct TrackProfile: Hashable, Sendable {
    /// The length of the vertical curve at the `from` end, in world units
    /// of chainage; 0 for none.
    public let startTransition: Int64
    /// The length of the vertical curve at the `to` end; 0 for none.
    public let endTransition: Int64

    public init(startTransition: Int64 = 0, endTransition: Int64 = 0) {
        self.startTransition = startTransition
        self.endTransition = endTransition
    }

    /// One grade from end to end.
    public static let uniform = TrackProfile()

    /// The steepest grade track may have, up or down: 40 in 1000. A
    /// gameplay parameter of this game, not a claim about real railways.
    public static let maximumGrade = TrackGrade(rise: 40, run: 1_000)
}

/// A stretch of an edge's vertical profile, for renderers: level, climbing,
/// falling or a vertical curve, from the `from` node toward the `to` node.
public struct TrackProfileSegment: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case level
        case up
        case down
        /// A vertical curve between level and the steady grade.
        case transition
    }

    public let kind: Kind
    /// Where the stretch starts and ends, in chainage from the `from` node.
    public let start: Int64
    public let end: Int64

    public init(kind: Kind, start: Int64, end: Int64) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// What carries an edge's track. The whole edge has one structure: where
/// the structure changes there is a node.
public enum TrackStructure: String, Hashable, CaseIterable, Sendable {
    /// On the ground, on a low embankment or in a shallow cutting.
    case surface
    /// On a viaduct.
    case elevated
    /// On a bridge. For now it differs from ``elevated`` only in cost and in
    /// what a renderer draws; crossing water comes with terrain.
    case bridge
    /// Underground. A node where a tunnel edge and another edge end is a
    /// portal (see ``RailwayNetwork/isTunnelPortal(_:)``).
    case tunnel

    /// The least height difference, rail to rail, between two tracks that
    /// cross in plan without a shared node: 512 units (8 m).
    public static let clearance: Int64 = 512

    /// How far above or below the ground surface track may run: 128 units
    /// (2 m) of embankment or cutting. Less than half the clearance, so two
    /// surface tracks can never pass over each other.
    public static let embankment: Int64 = 128

    /// Whether this structure can carry track at `height`: surface track
    /// within ``embankment`` of the ground (0), elevated track and bridges
    /// at or above it, tunnels at or below it.
    public func allows(height: Int64) -> Bool {
        switch self {
        case .surface: -Self.embankment <= height && height <= Self.embankment
        case .elevated, .bridge: height >= 0
        case .tunnel: height <= 0
        }
    }

    /// What track on this structure costs, as a multiple of
    /// ``ConstructionCosts/track``: the cost hook for structures. Placeholder
    /// values until balancing work starts; surface track is 1, as in Stage
    /// S3.
    public var costFactor: Int64 {
        switch self {
        case .surface: 1
        case .elevated: 3
        case .bridge: 4
        case .tunnel: 5
        }
    }
}

// MARK: - Codable

extension TrackProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case startTransition, endTransition
    }

    /// Decodes `{"startTransition", "endTransition"}`, both required.
    /// Whether the transitions fit the edge is checked with its end nodes
    /// (see ``TrackGeometry/init(from:to:curve:profile:)``).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startTransition: try container.decode(Int64.self, forKey: .startTransition),
            endTransition: try container.decode(Int64.self, forKey: .endTransition)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startTransition, forKey: .startTransition)
        try container.encode(endTransition, forKey: .endTransition)
    }
}

/// Encoded as its name: `"surface"`, `"elevated"`, `"bridge"` or
/// `"tunnel"`; any other name is rejected.
extension TrackStructure: Codable {}
