import GameCore

// Decision 619: the depot tool's yards as real yards are laid, from
// docs/research/YARD_TYPES_2026-11-07.md. The tool used to step each siding
// off the one inside it, one turnout and a 50 m S-curve after another, so
// every siding added 72 m of throat (six sidings, 360 m); OSM's Muzha yard
// fans 12 sidings out in about 112 m and Neihu's 16 in about 148 m, each
// turnout splitting the tracks it carries in two. ``DepotYardFan`` lays
// that tree: from the lead's end each group of sidings is split in two at
// a turnout, each half bending out to its own middle (or, held to one
// side, the inner half running straight on), until every siding has a
// track of its own. Turnouts stand at least 22 m apart
// (``NetworkBuilding/minimumSpacing``, the real yards' 20-26 m), the
// S-curves are no tighter than ``DepotYardFan/curveRadius``, sidings stand
// a double track's 5 m apart, and GameCore's rules (4 m track spacing,
// the 16 m junction zone) are not changed: the yard is laid by the same
// track, turnout and platform commands as before. The reference has no
// yard layout to port (the decision's table); nor have OpenTTD or
// Simutrans, whose depots are single tiles.

/// A kind of yard (decision 619): how many sidings it usually has, how
/// long each is, from the real yards it is taken from.
public enum DepotYardTemplate: String, CaseIterable, Hashable, Sendable, Codable {
    /// A light rail's: Danhai 11 × 108 m, Ankeng 12 × 102 m, Kaohsiung's
    /// about 16 × 138 m.
    case lightRail
    /// A metro's: Muzha 12 × 195 m, Neihu 16 × 148 m.
    case metro

    /// How many sidings yards of the kind have.
    public var sidings: ClosedRange<Int> {
        switch self {
        case .lightRail: 4...12
        case .metro: 8...24
        }
    }

    /// The sidings a new yard of the kind starts with: about the real
    /// ones' middle.
    public var defaultSidings: Int {
        switch self {
        case .lightRail: 6
        case .metro: 12
        }
    }

    /// Siding to siding, centre to centre: a double track's 5 m (the real
    /// yards' 4.1-6.7 m; the 3D map's masts and platforms take 5 m).
    public var spacing: Int64 { DepotYard.spacing }

    /// The shortest a siding is, from the throat's last turnout to its
    /// buffer: Danhai's and Ankeng's shortest stabling tracks (75 m),
    /// Neihu's (148 m, rounded to 150 m).
    public var shortestSiding: Int64 {
        switch self {
        case .lightRail: 75 * WorldCoordinate.unitsPerMetre
        case .metro: 150 * WorldCoordinate.unitsPerMetre
        }
    }

    /// How much longer than the train it keeps a siding is: 20 m on a
    /// light rail's, 30 m on a metro's, the first 16 m of it (GameCore's
    /// junction zone) keeping the train clear of the turnout before it.
    public var sidingMargin: Int64 {
        switch self {
        case .lightRail: 20 * WorldCoordinate.unitsPerMetre
        case .metro: 30 * WorldCoordinate.unitsPerMetre
        }
    }

    /// How long a siding for a train `length` long is.
    public func sidingLength(for length: Int64) -> Int64 {
        max(shortestSiding, length + sidingMargin)
    }
}

/// A yard's throat (decision 619): the tracks from the lead's end out to
/// each siding, along and across the yard's way from the lead's end.
struct DepotYardFan: Hashable, Sendable {
    /// Where the throat puts its sidings: about the lead, as the real yards
    /// stand (`nil`), or all to one side of it, the first straight on.
    typealias Anchor = PlatformTrackSide?

    /// One track of the throat: from a turnout, `from` along and `fromAcross`
    /// across, to where it comes out, `to` along and `toAcross` across.
    /// `siding` is the siding it becomes, or `nil` when it splits again.
    struct Leg: Hashable, Sendable {
        let from: Int64
        let fromAcross: Int64
        let to: Int64
        let toAcross: Int64
        let siding: Int?

        var bends: Bool { fromAcross != toAcross }
    }

    /// The tracks, each after the one it leaves.
    let legs: [Leg]
    /// Each siding's place across the yard, from one side to the other.
    let across: [Int64]

    /// The least radius of a throat's S-curves: 25 m, about decision 602's
    /// real yards' 30 m arcs (a cubic S-curve's sharpest point is half
    /// again as sharp as an arc S-curve's of the same length).
    static let curveRadius: Int64 = 25 * WorldCoordinate.unitsPerMetre
    /// The least a turnout stands from the next one, and the lead's length
    /// before the first: 22 m.
    static let turnoutSpacing = NetworkBuilding.minimumSpacing

    /// How far along an S-curve `across` to the side runs: long enough to
    /// keep to ``curveRadius`` (a cubic's tightest radius is length² ÷
    /// (6 × across)), and never shorter than ``turnoutSpacing``.
    static func reach(across: Int64) -> Int64 {
        guard across != 0 else { return turnoutSpacing }
        let needed = (6 * Double(abs(across)) * Double(curveRadius)).squareRoot().rounded(.up)
        return max(turnoutSpacing, Int64(needed))
    }

    /// Where the throat's last track comes out, along from the lead's end:
    /// the throat's length.
    var length: Int64 { legs.map(\.to).max() ?? 0 }

    /// The throat of `sidings` sidings `spacing` apart, about the lead or
    /// to one side of it.
    init(sidings: Int, spacing: Int64, anchor: Anchor) {
        let count = max(sidings, 1)
        let across: [Int64] = (0..<count).map { index in
            switch anchor {
            case nil: (2 * Int64(index) - Int64(count - 1)) * spacing / 2
            case .left?: Int64(index) * spacing
            case .right?: -Int64(index) * spacing
            }
        }
        // Where a group of sidings arrives: at its middle about the lead,
        // at its innermost to one side.
        func arrival(_ group: Range<Int>) -> Int64 {
            anchor == nil ? (across[group.lowerBound] + across[group.upperBound - 1]) / 2 : across[group.lowerBound]
        }
        var legs: [Leg] = []
        // The group `group` arriving `along` the yard: split in two, the
        // first half the larger, each half bending to its own arrival.
        func split(_ group: Range<Int>, along: Int64) {
            guard group.count > 1 else { return }
            let from = arrival(group), middle = group.lowerBound + (group.count + 1) / 2
            for half in [group.lowerBound..<middle, middle..<group.upperBound] {
                let to = arrival(half)
                let end = along + Self.reach(across: to - from)
                legs.append(Leg(from: along, fromAcross: from, to: end, toAcross: to, siding: half.count == 1 ? half.lowerBound : nil))
                split(half, along: end)
            }
        }
        split(0..<count, along: 0)
        self.legs = legs
        self.across = across
    }
}
