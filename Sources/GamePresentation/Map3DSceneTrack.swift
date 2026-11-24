import GameCore

/// The player's track on the native 3D map (decision 229): the cells it
/// clears, its bed, viaducts, tunnels and their shadows. Moved as it was
/// out of `Map3DScene.swift` (TRACK-SPLIT), whose builder these belong to.
extension Map3DScene.Builder {
    // MARK: Track

    /// Decision 720: the 64 m cells the player's track runs through
    /// (``addTrack(_:)``'s, known before the ground is laid), whose
    /// ground stays plain so the track stands off it as before.
    func trackCells(_ snapshot: RailwaySnapshot) -> Set<Map3DScene.ChunkKey> {
        var cells = Set<Map3DScene.ChunkKey>()
        let cell = Double(Land.cellLength), region = region
        for spans in shared.samples(of: snapshot).edges {
            // Decision 876: only the stretches whose box reaches.
            for span in spans where span.end > span.start && span.reaches(region, by: cell) {
                for coordinate in span.line {
                    let x = Double(coordinate.x), y = Double(coordinate.y)
                    guard x >= region.minX - cell, x <= region.maxX + cell, y >= region.minY - cell, y <= region.maxY + cell else { continue }
                    cells.insert(Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((y / cell).rounded(.down))))
                }
            }
        }
        return cells
    }

    /// The track: its bed or viaduct, piers and rails, edge by edge and
    /// stretch by stretch of what carries it. Returns the 64 m cells
    /// it runs through, which keep no building.
    mutating func addTrack(_ snapshot: RailwaySnapshot) -> Set<Map3DScene.ChunkKey> {
        var cleared = Set<Map3DScene.ChunkKey>()
        let cell = Double(Land.cellLength)
        let fast = highSpeedTrack()
        // Decision 679: ``contains(x:y:)`` asked of the region alone.
        // Asked of the builder, an unoptimized build (the Linux tests')
        // copied the whole builder for every point of every line.
        let region = region
        func inside(_ coordinate: WorldCoordinate) -> Bool {
            let x = Double(coordinate.x), y = Double(coordinate.y)
            return x >= region.minX && x <= region.maxX && y >= region.minY && y <= region.maxY
        }
        // Decision 876: the scene's samples, and only the stretches
        // whose box reaches the region (the rest lay nothing here).
        let samples = shared.samples(of: snapshot)
        // Decision 888: the diamonds, their rails cut and their wing
        // rails laid.
        diamonds = Map3DDiamondCrossings.find(snapshot) { point($0) + Self.lifted }
        // Decision 947: the guideway trains' lines' track, their beams.
        let guided = guideways(of: snapshot).edges
        // Decision 964: the kinds of the rest, from the trains run on it.
        let kinds = trackKinds(of: snapshot)
        for (number, alignment) in snapshot.edges.enumerated() {
            // Decision 407: a high-speed line's on its box girder.
            let guideway = guided[alignment.edge.id]
            let track = guideway == nil ? kinds[alignment.edge.id] ?? .ballast : .ballast
            // Decision 964: a metro's or a light rail's on a metro's viaduct.
            let viaduct: Map3DViaduct = fast.contains(alignment.edge.id) ? .highSpeed : track.ridesMetroViaduct ? .metro : .railway
            for span in samples.edges[number] where span.end > span.start && span.reaches(region) {
                let line = span.line
                guard line.count > 1 else { continue }
                for coordinate in line where inside(coordinate) {
                    cleared.insert(Map3DScene.ChunkKey(column: Int((Double(coordinate.x) / cell).rounded(.down)), row: Int((Double(coordinate.y) / cell).rounded(.down))))
                }
                guard line.contains(where: inside) else { continue }
                let points = line.map { point($0) + Self.lifted }
                // Decision 964: nor over a third rail or a rubber-tyred track.
                if guideway != nil || !track.hasOverheadLine { guidedTrackLines.insert(trackLines.count) }
                trackLines.append((points, span.kind))
                for piece in Self.pieces(of: points) {
                    addTrackPiece(piece, kind: span.kind, viaduct: viaduct, guideway: guideway, track: track)
                }
            }
        }
        addDiamondWings()
        return cleared
    }

    /// The centre line between `start` and `end` along `geometry`, at
    /// least every ``trackStep`` metres, with its heights.
    func sample(_ geometry: TrackGeometry, from start: Int64, to end: Int64) -> [WorldCoordinate] {
        Self.sample(geometry, from: start, to: end)
    }

    static func sample(_ geometry: TrackGeometry, from start: Int64, to end: Int64) -> [WorldCoordinate] {
        let step = Int64(trackStep * metre)
        var distances: [Int64] = [start]
        var next = start + step
        for distance in geometry.distances where distance > start && distance < end {
            while next < distance {
                distances.append(next)
                next += step
            }
            distances.append(distance)
            next = distance + step
        }
        while next < end {
            distances.append(next)
            next += step
        }
        distances.append(end)
        return thinned(distances.map { geometry.location(at: $0).position })
    }

    /// MAP3D-CAP: how far, in metres, the drawn track may stand from
    /// the track's own line where its points are thinned
    /// (``thinned(_:)``): under half a rail's width.
    static let trackTolerance: Double = 0.03

    /// MAP3D-CAP: `line` without the points a straight piece no longer
    /// than ``trackStep`` passes within ``trackTolerance`` of. A bought
    /// real line's geometry has a point every 0.65 m or so; drawn at
    /// each (a bore, a bed and two rails a point), the 212 km of
    /// tunnel in a 150-train game's 12 km scene were 11.5 million
    /// triangles. A line with no points closer than ``trackStep`` is
    /// unchanged.
    static func thinned(_ line: [WorldCoordinate]) -> [WorldCoordinate] {
        guard line.count > 2 else { return line }
        let longest = trackStep * metre, tolerance = trackTolerance * metre
        func vector(_ a: WorldCoordinate, _ b: WorldCoordinate) -> (x: Double, y: Double, z: Double) {
            (Double(b.x - a.x), Double(b.y - a.y), Double(b.z - a.z))
        }
        var kept = [line[0]]
        var anchor = 0
        for index in 1..<(line.count - 1) {
            // Whether the piece from the last point kept to the next
            // point passes this one and those left out since.
            let chord = vector(line[anchor], line[index + 1])
            let length = (chord.x * chord.x + chord.y * chord.y + chord.z * chord.z).squareRoot()
            var passes = length > 0 && length <= longest
            var between = anchor + 1
            while passes, between <= index {
                let to = vector(line[anchor], line[between])
                let along = (to.x * chord.x + to.y * chord.y + to.z * chord.z) / length
                let off = to.x * to.x + to.y * to.y + to.z * to.z - along * along
                if along < 0 || along > length || off > tolerance * tolerance { passes = false }
                between += 1
            }
            if !passes {
                kept.append(line[index])
                anchor = index
            }
        }
        kept.append(line[line.count - 1])
        return kept
    }

    /// `line` in pieces of at most 256 m, each sharing its first point
    /// with the last's end, so a long line falls into the chunks it
    /// crosses.
    static func pieces(of line: [Map3DPoint]) -> [[Map3DPoint]] {
        var pieces: [[Map3DPoint]] = []
        var current: [Map3DPoint] = []
        var length: Float = 0
        for point in line {
            if let last = current.last { length += (point - last).length }
            current.append(point)
            if length >= 256, current.count > 1 {
                pieces.append(current)
                current = [point]
                length = 0
            }
        }
        if current.count > 1 { pieces.append(current) }
        return pieces
    }

    /// Decision 600: with `railsNear`, its rails only in the near
    /// detail (``Target/near``), its bed, banks and viaducts at every
    /// distance: the real lines' tracks, which far out are most of what
    /// a scene draws.
    ///
    /// Decision 964: `track`, what lies under the trains in place of
    /// ballast and two rails (``Map3DTrackKind``).
    ///
    /// `from`: how far along its whole track `line` starts, metres
    /// (a real track's, review L11-1), so a viaduct's piers stand where
    /// the whole track puts them, wherever the piece starts.
    mutating func addTrackPiece(_ line: [Map3DPoint], kind: TrackSectionKind, viaduct: Map3DViaduct = .railway, railsNear: Bool = false,
                                from along: Float? = nil, guideway: Map3DGuideway.Kind? = nil, track: Map3DTrackKind = .ballast) {
        let middle = line[line.count / 2]
        // Decision 947: a guideway in place of the rails, the bed and
        // the viaduct.
        if let guideway {
            addGuideway(line, kind: kind, guideway: guideway)
            return
        }
        switch kind {
        case .tunnel:
            // Decision 359 (續): its bore round its bed.
            var bore = Map3DMesh()
            // Decision 860: none along an underground station, its
            // box there instead.
            for piece in undergroundStations.outside(line) { addBore(piece, into: &bore) }
            mesh(at: middle) { mesh in
                mesh.append(bore)
                guard track == .ballast else {
                    Map3DTrackKind.addBed(track, along: line, depth: 0.6, green: false, into: &mesh)
                    return
                }
                mesh.addRibbon(along: line, width: Self.bedTop, lift: -Self.bedDrop, depth: 0.6, top: Map3DPalette.ballast, side: Map3DPalette.ballast,
                               topPaint: Self.ballast, sidePaint: Self.concrete)
            }
        case .viaduct, .bridge:
            // Decision 407: drawn with the rest (addViaducts()).
            let grounds = line.map { ground(at: $0) }
            addDeckShadow(line, grounds: grounds, width: viaduct.look(over: kind).deckWidth)
            viaducts.add(line, grounds: grounds, kind: kind, viaduct: viaduct, from: along)
            // Decision 964: an embedded track's paving on the deck.
            if track == .embedded { mesh(at: middle) { Map3DTrackKind.addEmbeddedSurface(along: line, green: false, into: &$0) } }
        case .surface, .embankment, .cutting:
            let lifts = line.map { $0.y - ground(at: $0) }
            let depth = max(0.45, (lifts.reduce(0, +) / Float(lifts.count)) - Self.bedDrop)
            let bank = kind == .embankment ? Map3DPalette.embankment : Map3DPalette.ballast
            // Decision 391 (續篇二): open over a road passing under it.
            let (banks, spans) = kind == .embankment ? openings(of: line) : ([line], [])
            mesh(at: middle) { mesh in
                let width = Self.bedBottom + min(depth, 4.7) * 2
                for part in banks where kind == .embankment {
                    mesh.addRibbon(along: part, width: width, lift: -Self.bedDrop - 0.05, depth: depth, top: bank, side: bank,
                                   topPaint: Self.bank, sidePaint: Self.bank)
                }
                for span in spans {
                    mesh.addRibbon(along: span, width: Self.bedBottom, lift: -Self.bedDrop - 0.05, depth: Self.girderDepth, top: Map3DPalette.concrete,
                                   side: Map3DPalette.concrete, topPaint: Self.concrete, sidePaint: Self.concrete)
                    // The bank's ends each side: its abutments.
                    for (end, inward) in [(span[0], span[1] - span[0]), (span[span.count - 1], span[span.count - 2] - span[span.count - 1])] {
                        guard let forward = Map3DPoint(inward.x, 0, inward.z).normalized else { continue }
                        let across = Map3DPoint(-forward.z, 0, forward.x) * (width / 2)
                        let top = end + Map3DPoint(0, -Self.bedDrop - 0.05, 0), foot = top + Map3DPoint(0, -depth, 0)
                        mesh.addQuad(foot - across, foot + across, top + across, top - across, color: bank, paint: Self.bank)
                        mesh.addQuad(foot + across, foot - across, top - across, top + across, color: bank, paint: Self.bank)
                    }
                }
                guard track == .ballast else {
                    Map3DTrackKind.addBed(track, along: line, depth: min(depth, 0.6), green: true, into: &mesh)
                    return
                }
                mesh.addRibbon(along: line, width: Self.bedTop, lift: -Self.bedDrop, depth: min(depth, 0.6), top: Map3DPalette.ballast, side: Map3DPalette.ballast,
                               topPaint: Self.ballast, sidePaint: Self.concrete)
            }
        }
        // The rails, their middles half a rail outside the gauge.
        // Decision 799: at the map's gauge (Finland's 1,524 mm).
        let offset = (look.gauge + Self.railWidth) / 2
        let target = self.target
        defer { self.target = target }
        // Decision 964: the kind's small parts, close up only.
        defer {
            if track != .ballast {
                self.target = .near
                mesh(at: middle) { Map3DTrackKind.addDetails(track, along: line, railOffset: offset, into: &$0) }
            }
        }
        // Decision 964: a rubber-tyred track's pads in place of rails.
        guard track.hasRails else {
            mesh(at: middle) { Map3DTrackKind.addPads(along: line, into: &$0) }
            return
        }
        if railsNear { self.target = .near }
        // Decision 888: at a diamond, short of the rail it crosses.
        let gaps = [Float(-1), 1].map { diamondGaps(line, offset: $0 * offset) }
        mesh(at: middle) { mesh in
            for (number, side) in [Float(-1), 1].enumerated() {
                for piece in gaps[number].isEmpty ? [line] : Map3DDiamondCrossings.cut(line, without: gaps[number]) {
                    guard track != .embedded else {
                        Map3DTrackKind.addEmbeddedRail(along: piece, offset: side * offset, into: &mesh)
                        continue
                    }
                    mesh.addRibbon(along: piece, width: Self.railWidth, offset: side * offset, lift: 0, depth: Self.railHeight,
                                   top: Map3DPalette.railTop, side: Map3DPalette.rail)
                }
            }
        }
    }

    /// Decision 391 (續篇二): `line` (an embankment's rails) in the
    /// stretches of bank and the spans open over a road passing under
    /// (``Map3DRoadBridges/openings``), each split where they meet.
    func openings(of line: [Map3DPoint]) -> (banks: [[Map3DPoint]], spans: [[Map3DPoint]]) {
        var travelled: [Float] = [0]
        for index in 1..<line.count { travelled.append(travelled[index - 1] + Map3DPoint(line[index].x - line[index - 1].x, 0, line[index].z - line[index - 1].z).length) }
        // The open stretches, by the way along the line.
        var open: [ClosedRange<Float>] = []
        for opening in roadBridges.openings {
            for index in 1..<line.count {
                let a = Map3DBaseMap.Point(x: Double(line[index - 1].x), z: Double(line[index - 1].z)), b = Map3DBaseMap.Point(x: Double(line[index].x), z: Double(line[index].z))
                let on = Map3DRoadBridges.nearest(opening.point, a, b)
                guard on.distance < 1 else { continue }
                let at = travelled[index - 1] + Float(((on.point.x - a.x) * (on.point.x - a.x) + (on.point.z - a.z) * (on.point.z - a.z)).squareRoot())
                open.append(max(0, at - opening.half)...min(travelled[travelled.count - 1], at + opening.half))
                break
            }
        }
        guard !open.isEmpty else { return ([line], []) }
        open.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Float>] = []
        for range in open {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        func point(at distance: Float) -> Map3DPoint {
            let index = max(1, min(line.count - 1, travelled.firstIndex { $0 >= distance } ?? line.count - 1))
            let length = travelled[index] - travelled[index - 1]
            let share = length > 0 ? (distance - travelled[index - 1]) / length : 0
            return line[index - 1] + (line[index] - line[index - 1]) * min(max(share, 0), 1)
        }
        func part(_ from: Float, _ to: Float) -> [Map3DPoint] {
            [point(at: from)] + line.indices.filter { travelled[$0] > from && travelled[$0] < to }.map { line[$0] } + [point(at: to)]
        }
        var banks: [[Map3DPoint]] = [], spans: [[Map3DPoint]] = []
        var from: Float = 0
        for range in merged {
            if range.lowerBound > from { banks.append(part(from, range.lowerBound)) }
            if range.upperBound > range.lowerBound { spans.append(part(range.lowerBound, range.upperBound)) }
            from = range.upperBound
        }
        if travelled[travelled.count - 1] > from { banks.append(part(from, travelled[travelled.count - 1])) }
        return (banks, spans)
    }

    /// Decision 232: the deck's shadow on the ground under a viaduct
    /// or bridge, wider the higher it stands.
    mutating func addDeckShadow(_ line: [Map3DPoint], grounds: [Float], width: Float = deckWidth) {
        let heights = zip(line, grounds).map { $0.y - $1 }
        let height = heights.reduce(0, +) / Float(max(heights.count, 1))
        guard height > 2 else { return }
        let half = width / 2, spread = min(5, 1.5 + height * 0.15)
        let across = Map3DMesh.acrossDirections(line)
        var rows: [[Map3DPoint]] = []
        for (point, side) in zip(line, across) {
            rows.append(onGround([-(half + spread), -half, half, half + spread].map { point + side * $0 }))
        }
        shadows[key(of: line[line.count / 2]), default: Map3DMesh()].addShadowStrip(rows, darkness: 0.26)
    }
}
