import GameCore

/// The side slopes of an embankment or a cutting beside the track on the
/// map (ARCHITECTURE decision 124, the design's third step), in world
/// units: for each 16 m pricing length GameCore measured as one, a band on
/// either side as wide as the slope runs, and hachures across it, the
/// map's sign for a bank. The cross-section is the one the earthwork is
/// priced by (``GameCore/TrackSectionRules``): a bed 10 m wide, its sides
/// 1 : 1.5, so a slope reaches 1.5 m out for every metre the rail stands
/// above or below the ground.
///
/// On an embankment the short hachures hang from the bed's edge, the top
/// of the bank; in a cutting from the band's outer edge, the top of the
/// cut. Presentation only, worked out once for each edge with its drawing.
///
/// Reference (`a91453/railway-reference-private` `05d7000`):
/// `Railway/site_archive_clean/rail-3d/integration/rail-structures.js`
/// draws only fills in 3D, a trapezoid widening by its slope with the lift
/// (`FILL_SLOPE`, `BED_BOTTOM_MAX`), in its bank colour `#c6c0b1`; there is
/// no cutting and no flat map drawing of either (gap). The bands and
/// hachures are this project's.
public struct TrackSlope: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// A hachure, from one end to the other.
    public struct Hachure: Hashable, Sendable {
        public let from: Point
        public let to: Point

        public init(from: Point, to: Point) {
            self.from = from
            self.to = to
        }
    }

    public let kind: TrackSectionKind
    /// The band on each side: its edge by the bed from the start, then its
    /// outer edge back.
    public let bands: [[Point]]
    public let hachures: [Hachure]

    /// Half the bed's width: 5 m.
    public static let bedHalfWidth = 5.0 * Double(WorldCoordinate.unitsPerMetre)
    /// How far a slope runs out for each unit of height: 1.5.
    public static let run = 1.5

    /// The slopes of the edge `section` and `geometry` describe: one for
    /// each pricing length on an embankment or in a cutting, from its
    /// middle's height (``GameCore/TrackGroundSample/height``).
    public static func slopes(of section: TrackLongSection, geometry: TrackGeometry) -> [TrackSlope] {
        section.samples.dropFirst().dropLast().enumerated().compactMap { index, sample in
            guard sample.kind == .embankment || sample.kind == .cutting else { return nil }
            let (start, end) = section.pricingLength(index)
            guard start < end else { return nil }
            return TrackSlope(kind: sample.kind, height: Double(abs(sample.height)), from: geometry.location(at: start), to: geometry.location(at: end))
        }
    }

    /// The slope of a piece of track from `a` to `b`, the rail `height`
    /// units above or below the ground.
    init(kind: TrackSectionKind, height: Double, from a: TrackLocation, to b: TrackLocation) {
        self.kind = kind
        let width = height * Self.run
        let ax = Double(a.position.x), ay = Double(a.position.y), bx = Double(b.position.x), by = Double(b.position.y)
        let dx = bx - ax, dy = by - ay
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        // One side of the way along the track, then the other.
        let normals = [(-dy / length, dx / length), (dy / length, -dx / length)]
        func point(_ x: Double, _ y: Double, out: Double, _ normal: (Double, Double)) -> Point {
            Point(x: x + normal.0 * out, y: y + normal.1 * out)
        }
        let inner = Self.bedHalfWidth, outer = Self.bedHalfWidth + width
        bands = normals.map { normal in
            [point(ax, ay, out: inner, normal), point(bx, by, out: inner, normal), point(bx, by, out: outer, normal), point(ax, ay, out: outer, normal)]
        }
        // Every 4 m, long and short in turn; the short ones from the top.
        let shortFrom = kind == .embankment ? inner : inner + width / 2
        let shortTo = kind == .embankment ? inner + width / 2 : outer
        var hachures: [Hachure] = []
        for normal in normals {
            for i in 0..<4 {
                let t = (Double(i) + 0.5) / 4
                let x = ax + dx * t, y = ay + dy * t
                if i % 2 == 0 {
                    hachures.append(Hachure(from: point(x, y, out: inner, normal), to: point(x, y, out: outer, normal)))
                } else {
                    hachures.append(Hachure(from: point(x, y, out: shortFrom, normal), to: point(x, y, out: shortTo, normal)))
                }
            }
        }
        self.hachures = hachures
    }
}
