import GameCore

/// Decision 314: a thin band in a line's colour along the track it runs on,
/// beside the rails, so the 3D map shows which line takes which track as
/// the 2D map does. Where lines share a stretch, only the one the 2D map
/// draws on top: the last of ``LineMap``'s stretches over it, the line
/// with the largest ID.
public struct Map3DLineBands: Hashable, Sendable {
    /// One stretch of one edge and the colour its band is drawn in.
    public struct Band: Hashable, Sendable {
        public let edge: TrackEdgeID
        /// Along the edge from its `from` node, world units.
        public let start: Int64
        public let end: Int64
        /// 0xRRGGBB, after the player's line palette.
        public let rgb: Int
    }

    /// By edge, then along it.
    public let bands: [Band]

    public init(bands: [Band]) {
        self.bands = bands
    }

    /// The bands of `lines` (``LineMap``): for each stretch of an edge the
    /// top line's colour, its own or the automatic one (decision 216),
    /// through `palette`. Freight lines too: they are lines on the map.
    /// A line's stretch can reach over the shorter one of another, where
    /// the other joining moves neither its place nor its width (a line one
    /// way beside one ridden both ways): the edge is cut where any stretch
    /// starts or ends, so no two bands cover the same track.
    public init(lines: LineMap, palette: LinePalette) {
        var bands: [Band] = []
        for (edge, stretches) in Dictionary(grouping: lines.stretches, by: \.edge) {
            let cuts = Set(stretches.flatMap { [$0.start, $0.end] }).sorted()
            for (start, end) in zip(cuts, cuts.dropFirst()) {
                guard let top = stretches.filter({ $0.start <= start && end <= $0.end }).max(by: { $0.line < $1.line }) else { continue }
                bands.append(Band(edge: edge, start: start, end: end, rgb: palette.color(for: top.color?.rgb ?? LineBadge.automaticColor(of: top.line))))
            }
        }
        self.bands = bands.sorted { ($0.edge, $0.start) < ($1.edge, $1.start) }
    }

    /// The bands of `world`'s lines through `palette`.
    public init(world: GameWorld, palette: LinePalette) {
        self.init(lines: LineMap(world: world), palette: palette)
    }

    /// The bands on `edge`, along it.
    func on(_ edge: TrackEdgeID) -> ArraySlice<Band> {
        let first = bands.partitioningIndex { $0.edge >= edge }
        let end = bands[first...].firstIndex { $0.edge != edge } ?? bands.endIndex
        return bands[first..<end]
    }

    /// What of `world`'s lines moves their bands: the track each takes
    /// (its stops, paths, further services, ring) and its colour; not its
    /// trains or dispatches, which change all game long. For a cache of
    /// the scene to tell when to build it again.
    public struct Signature: Hashable, Sendable {
        private let lines: [Line]

        private struct Line: Hashable, Sendable {
            let id: LineID
            let stops: [StationID]
            let routePreferences: [LineRoutePreference]
            let patterns: [Pattern]
            let isRing: Bool
            let color: LineColor?
        }

        private struct Pattern: Hashable, Sendable {
            let calls: [Int]
            let routePreferences: [LineRoutePreference]
        }

        public init(world: GameWorld) {
            lines = world.lines.map { line in
                Line(id: line.id, stops: line.stops, routePreferences: line.routePreferences,
                     patterns: line.patterns.map { Pattern(calls: $0.calls, routePreferences: $0.routePreferences) },
                     isRing: line.isRing, color: line.color)
            }
        }
    }

    /// The band's width and how far it stands above the ballast or the
    /// deck, in metres: a hand's breadth, proud enough not to flicker.
    static let width: Float = 0.3
    static let lift: Float = 0.04
    /// Its middle from the track's centre line, on the same side of every
    /// edge along its way: on the ballast's shoulder outside the rails, or
    /// at the deck's edge.
    static func offset(on kind: TrackSectionKind) -> Float {
        switch kind {
        case .viaduct, .bridge: Map3DScene.Builder.deckWidth / 2 - 0.35
        case .surface, .embankment, .cutting, .tunnel: Map3DScene.Builder.bedTop / 2 - 0.3
        }
    }
}

extension Array {
    /// The first index whose element is `true` for `belongs`, which is
    /// `false` for a prefix and `true` after it.
    fileprivate func partitioningIndex(where belongs: (Element) -> Bool) -> Int {
        var low = startIndex, high = endIndex
        while low < high {
            let middle = (low + high) / 2
            if belongs(self[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}

extension Map3DScene.Builder {
    /// Decision 314: `bands` along the track of `snapshot`, in the near
    /// meshes only (a hand's breadth is lost to the pixels afar), none in a
    /// tunnel.
    mutating func addLineBands(_ bands: Map3DLineBands, snapshot: RailwaySnapshot) {
        guard !bands.bands.isEmpty else { return }
        let saved = target
        target = .near
        defer { target = saved }
        for alignment in snapshot.edges {
            for band in bands.on(alignment.edge.id) {
                let color = Map3DColor.rgb(UInt32(band.rgb))
                for span in alignment.edge.sectionSpans where span.kind != .tunnel {
                    let start = max(span.start, band.start), end = min(span.end, band.end)
                    guard end > start else { continue }
                    let line = sample(alignment.geometry, from: start, to: end)
                    guard line.count > 1, line.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) else { continue }
                    let points = line.map { point($0) + Self.lifted }
                    let lift = (span.kind == .viaduct || span.kind == .bridge ? 0 : -Self.bedDrop) + Map3DLineBands.lift
                    for piece in Self.pieces(of: points) {
                        mesh(at: piece[piece.count / 2]) { mesh in
                            mesh.addRibbon(along: piece, width: Map3DLineBands.width, offset: Map3DLineBands.offset(on: span.kind), lift: lift,
                                           top: color)
                        }
                    }
                }
            }
        }
    }
}
