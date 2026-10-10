import GameCore

/// The build card's long section of a new stretch of track (ARCHITECTURE
/// decision 124, the design's third step): chainage across, height up; the
/// ground's line, the rail's, and between them each stretch in the colour
/// of what carries it (surface, embankment, cutting, viaduct, bridge,
/// tunnel). Worked out from GameCore's ``GameCore/TrackLongSection`` of the
/// edge the preview built on its copy of the world; the view only scales it
/// to its frame.
///
/// Coordinates are fractions of the chart: `x` 0 at the start to 1 at the
/// end, `y` 0 at the bottom to 1 at the top. Between the samples (the ends
/// and every 16 m) the lines run straight, as the rules see them.
///
/// The references have no long section to port (the design's section 10:
/// `Railway/site_archive_clean/rail-3d/physical/level-profiles.json` holds
/// real lines' sections as data, with no chart); the chart is this
/// project's.
public struct LongSectionChart: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// A stretch carried alike: the area between the rail and the ground,
    /// the rail's points from the start, then the ground's back.
    public struct Band: Hashable, Sendable {
        public let kind: TrackSectionKind
        public let outline: [Point]
    }

    public let ground: [Point]
    public let rail: [Point]
    public let bands: [Band]
    /// Where the track crosses water, as ranges of `x`.
    public let water: [ClosedRange<Double>]
    /// The heights at the bottom and the top of the chart, in world units
    /// above the sea.
    public let bottom: Int64
    public let top: Int64
    /// The kinds the chart shows, in ``GameCore/TrackSectionKind``'s order:
    /// its key.
    public let kinds: [TrackSectionKind]

    /// The least height the chart spans, so a level stretch does not
    /// stretch a metre across it: 16 m.
    public static let minimumSpan: Int64 = 16 * WorldCoordinate.unitsPerMetre

    public init(_ section: TrackLongSection) {
        let samples = section.samples
        let length = Double(max(1, section.length))
        let heights = samples.flatMap { [$0.rail, $0.ground] }
        var low = heights.min() ?? 0, high = heights.max() ?? 0
        // A tenth of the span spare above and below, and at least
        // ``minimumSpan`` in all.
        let spare = max((Self.minimumSpan - (high - low) + 1) / 2, (high - low) / 10)
        low -= spare
        high += spare
        bottom = low
        top = high
        let span = Double(high - low)
        func point(_ distance: Int64, _ height: Int64) -> Point {
            Point(x: Double(distance) / length, y: Double(height - low) / span)
        }
        ground = samples.map { point($0.distance, $0.ground) }
        rail = samples.map { point($0.distance, $0.rail) }
        // The rail and the ground at `distance`, straight between samples.
        func levels(at distance: Int64) -> (rail: Int64, ground: Int64) {
            guard let next = samples.firstIndex(where: { $0.distance >= distance }) else {
                return (samples.last?.rail ?? 0, samples.last?.ground ?? 0)
            }
            let b = samples[next]
            guard next > 0, b.distance != distance else { return (b.rail, b.ground) }
            let a = samples[next - 1]
            func blend(_ p: Int64, _ q: Int64) -> Int64 {
                p + (q - p) * (distance - a.distance) / (b.distance - a.distance)
            }
            return (blend(a.rail, b.rail), blend(a.ground, b.ground))
        }
        bands = section.spans.map { span in
            let inside = samples.filter { $0.distance > span.start && $0.distance < span.end }
            let start = levels(at: span.start), end = levels(at: span.end)
            let rails = [point(span.start, start.rail)] + inside.map { point($0.distance, $0.rail) } + [point(span.end, end.rail)]
            let grounds = [point(span.start, start.ground)] + inside.map { point($0.distance, $0.ground) } + [point(span.end, end.ground)]
            return Band(kind: span.kind, outline: rails + grounds.reversed())
        }
        // Water by the pricing lengths it is measured at: each wet middle
        // stands for its length, the last one shorter.
        var water: [ClosedRange<Double>] = []
        for (index, sample) in samples.dropFirst().dropLast().enumerated() where sample.isWater {
            let (start, end) = section.pricingLength(index)
            let from = Double(start) / length, to = Double(end) / length
            if let last = water.last, last.upperBound >= from {
                water[water.count - 1] = last.lowerBound...to
            } else {
                water.append(from...to)
            }
        }
        self.water = water
        let shown = Set(section.spans.map(\.kind))
        kinds = TrackSectionKind.allCases.filter(shown.contains)
    }
}

extension NetworkCostParts {
    /// The build card's cost lines (decision 124, H3), each with what it
    /// costs: the track, then earthwork, viaducts and bridges, tunnels and
    /// demolition where they cost anything, then the total.
    public func lines(in language: DisplayLanguage) -> [(name: String, cost: Money)] {
        var lines = [(language.text("Track", "軌道"), track.track)]
        let parts = [
            (language.text("Earthwork", "土方"), track.earthwork),
            (language.text("Viaducts and bridges", "高架與橋"), track.viaductsAndBridges),
            (language.text("Tunnels", "隧道"), track.tunnels),
            (language.text("Demolition", "拆遷"), demolition),
        ]
        lines += parts.filter { $0.1 != .zero }
        lines.append((language.text("Total", "合計"), total))
        return lines.map { (name: $0.0, cost: $0.1) }
    }
}

extension TrackLongSection {
    /// Where pricing length `index` runs, as GameCore surveys it: 16 m at a
    /// time from the edge's start, the last one shorter. Its sample is the
    /// one after the start's.
    func pricingLength(_ index: Int) -> (start: Int64, end: Int64) {
        let priced = ConstructionCosts.trackPricingLength
        let start = Int64(index) * priced
        return (start, min(length, start + priced))
    }
}
