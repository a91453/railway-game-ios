import GameCore

// Decision 869: a real suspension bridge's towers, main cables and hangers.
//
// The base map's bridges are decks on piers (decision 391) and the track's
// viaducts likewise (decision 407), so 青馬大橋 was two rows of piers
// across the strait. Where its towers stand and what they measure is the
// Lands Department's survey (3D Visualisation Map, sheets 10-NE-2D and
// 10-NE-3B, each leg a model of its own; the decks are 10-NE-2D's and
// 10-NE-3A's). The decks stay the game's own, at the game's heights (the
// road on the upper, the track under it, decision 391's 後來): the towers
// keep their surveyed heights over the road, their legs under it only as
// long as the game's deck is high, and the cables and hangers are hung
// from the towers down to the deck as it is drawn. The spans the cables
// carry stand on no pier.

/// Decision 869: a suspension bridge of the real world.
struct Map3DSuspensionBridge: Sendable {
    /// The middle of each tower, between its legs.
    let towers: [(latitude: Double, longitude: Double)]
    /// How far past each tower its cables are anchored, metres.
    let sideSpans: [Float]
    /// Whether each side span hangs from the cables (else it stands on its
    /// own piers under the backstays).
    let hungSides: [Bool]

    /// 青馬大橋: 馬灣's tower and 青衣's, 1,377 m apart; 馬灣's side span
    /// (355 m) hangs, 青衣's (300 m) stands on piers.
    static let tsingMa = Map3DSuspensionBridge(towers: [(22.349_340, 114.067_644), (22.352_902, 114.080_452)],
                                               sideSpans: [355, 300], hungSides: [true, false])

    static let all = [tsingMa]

    // The towers as surveyed, metres; heights over the road at the tower
    // (73.5 m over Principal Datum).

    /// Each leg's middle from the bridge's, across it: surveyed 18.2 m,
    /// a metre more here, since the base map's two carriageways are drawn
    /// 32 m across and the legs stand clear of them.
    static let legOffset: Float = 19.2
    /// A leg's half width across the bridge and half length along it, at
    /// the road, at its upper two portal beams and under its cap.
    static let legSections: [(height: Float, across: Float, along: Float)] = [(0, 2.8, 4.75), (81.9, 2.6, 4.35), (122.4, 2.4, 3.85)]
    /// A leg's foot, as much wider than at the road as it stands
    /// ``footDrop`` under it (less in proportion on a lower deck).
    static let foot: (across: Float, along: Float) = (4.0, 7.15)
    static let footDrop: Float = 66.7
    /// The cap on each leg, and the saddle's housing over it: its outline
    /// along the bridge.
    static let cap: (bottom: Float, top: Float, across: Float, along: Float) = (125.5, 128.1, 2.95, 5.5)
    static let housing: [(along: Float, height: Float)] = [(-5.5, 128.1), (-8.5, 133.0), (-7.0, 134.0), (-5.6, 134.8), (-2.4, 135.9),
                                                         (2.4, 135.9), (5.6, 134.8), (7.0, 134.0), (8.5, 133.0), (5.5, 128.1)]
    /// The portal beams over the road, and half their length along it.
    static let beams: [(bottom: Float, top: Float)] = [(29.7, 38.6), (76.1, 83.1), (116.4, 122.3)]
    static let beamHalf: Float = 1.9
    /// The beam under the deck: how deep, and half its length along.
    static let lowBeam: (depth: Float, half: Float) = (6, 2.5)
    /// The cables' middle over the road at a tower (their saddles), and
    /// at the middle of the main span.
    static let saddle: Float = 129.5
    static let cableLow: Float = 2.5
    /// How thick a main cable is drawn (1.1 m; a little more, to be seen
    /// from the map's height), and a hanger.
    static let cable: Float = 1.4
    static let hanger: Float = 0.35
    /// A hanger every 18 m.
    static let hangerSpacing: Float = 18
    /// The deck's edge from its middle (41 m wide; a metre more each side
    /// here, as the legs), how far over the road
    /// its fairing stands, and how far from a tower's middle it stops.
    static let deckHalf: Float = 21.5
    static let fairingRise: Float = 0.9
    static let fairingGap: Float = 7
    /// How far across the bridge's middle its decks may lie.
    static let corridor: Float = 30

    /// How far over rails on the ground under the road a tower's lowest
    /// beam keeps (a train and its wires).
    static let overRails: Float = 6.5
    /// The most the towers and cables follow the road's middle off the
    /// surveyed one (the base map's road lies a few metres off it).
    static let mostOff: Float = 4

    /// Decision 869: the decks across a bridge at a station
    /// (``Map3DScene/Builder/suspendedDeck(_:at:)``).
    struct Deck: Sendable {
        let road: Float
        let left: Float
        let right: Float
        let soffit: Float
        let rails: Float?

        /// The road's middle from the surveyed one, across the bridge: the
        /// towers stand astride the road as it is drawn, the cables over
        /// its edges.
        var middle: Float { min(max((left + right) / 2, -Map3DSuspensionBridge.mostOff), Map3DSuspensionBridge.mostOff) }
    }

    /// Decision 869: a bridge in a scene.
    struct Placed: Sendable {
        let bridge: Map3DSuspensionBridge
        /// The first tower's middle, at height 0.
        let first: Map3DPoint
        /// Level units: from the first tower to the second, and to the
        /// right of that.
        let along: Map3DPoint
        let across: Map3DPoint
        /// The towers apart, metres.
        let span: Float

        /// The point `along` metres from the first tower towards the
        /// second and `across` metres to the right, at `height`.
        func point(along s: Float, across a: Float, height: Float = 0) -> Map3DPoint {
            Map3DPoint(first.x + along.x * s + across.x * a, height, first.z + along.z * s + across.z * a)
        }

        func station(x: Float, z: Float) -> (along: Float, across: Float) {
            let dx = x - first.x, dz = z - first.z
            return (dx * along.x + dz * along.z, dx * across.x + dz * across.z)
        }

        /// The stations the cables run between: their anchorages.
        var ends: ClosedRange<Float> { -bridge.sideSpans[0]...span + bridge.sideSpans[1] }

        /// The stations the cables are drawn between: the anchorages and
        /// every hanger's (a multiple of the spacing from the first
        /// tower).
        var marks: [Float] {
            let spacing = Map3DSuspensionBridge.hangerSpacing
            var marks: [Float] = []
            var mark = (ends.lowerBound / spacing).rounded(.up) * spacing
            if mark > ends.lowerBound + 0.5 { marks.append(ends.lowerBound) }
            while mark < ends.upperBound - 0.5 {
                marks.append(mark)
                mark += spacing
            }
            marks.append(ends.upperBound)
            return marks
        }

        /// The stations of the deck the cables carry.
        var hung: ClosedRange<Float> {
            (bridge.hungSides[0] ? -bridge.sideSpans[0] : 0)...(span + (bridge.hungSides[1] ? bridge.sideSpans[1] : 0))
        }

        /// Whether a deck's pier at scene point (`x`, `z`) would stand
        /// under the deck the cables carry: none does. A tower's own beam
        /// carries the deck at it.
        func carries(x: Float, z: Float) -> Bool {
            let at = station(x: x, z: z)
            return abs(at.across) <= Map3DSuspensionBridge.corridor && hung.contains(at.along)
        }

        /// The stretches of the deck's fairing between stations `from` and
        /// `to`: where the cables carry the deck, clear of the towers.
        func fairing(from: Float, to: Float) -> [ClosedRange<Float>] {
            let gap = Map3DSuspensionBridge.fairingGap
            var runs = [max(from, hung.lowerBound)...max(min(to, hung.upperBound), max(from, hung.lowerBound))]
            for tower in [Float(0), span] {
                runs = runs.flatMap { run -> [ClosedRange<Float>] in
                    guard run.upperBound > tower - gap, run.lowerBound < tower + gap else { return [run] }
                    var parts: [ClosedRange<Float>] = []
                    if run.lowerBound < tower - gap { parts.append(run.lowerBound...(tower - gap)) }
                    if run.upperBound > tower + gap { parts.append((tower + gap)...run.upperBound) }
                    return parts
                }
            }
            return runs.filter { $0.upperBound - $0.lowerBound > 0.5 }
        }

        /// The middle of a main cable over the road, `s` metres from the
        /// first tower: a parabola between the saddles down to
        /// ``Map3DSuspensionBridge/cableLow`` at the middle of the main
        /// span; on a side span the same curve under the chord from the
        /// saddle to the anchorage at the road (a quarter of it on one
        /// that carries no deck).
        func cableHeight(at s: Float) -> Float {
            let top = Map3DSuspensionBridge.saddle, low = Map3DSuspensionBridge.cableLow
            let curve = (top - low) / (span / 2 * span / 2)
            if s >= 0, s <= span {
                let x = s - span / 2
                return low + curve * x * x
            }
            let side = s < 0 ? 0 : 1
            let length = bridge.sideSpans[side], x = s < 0 ? -s : s - span
            let chord = top + (1 - top) * x / length
            return chord - curve * (bridge.hungSides[side] ? 1 : 0.25) * x * (length - x)
        }
    }

    /// Decision 869: the bridge in `frame`'s world, the scene's origin at
    /// world (`originX`, `originY`).
    func placed(frame: RealWorldFrame, origin: (x: Double, y: Double)) -> Placed? {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let points = towers.map { tower -> Map3DPoint in
            let place = frame.worldPosition(latitude: tower.latitude, longitude: tower.longitude)
            return Map3DPoint(Float((place.x - origin.x) / metre), 0, Float((place.y - origin.y) / metre))
        }
        guard points.count == 2, let along = (points[1] - points[0]).normalized else { return nil }
        return Placed(bridge: self, first: points[0], along: along, across: Map3DPoint(-along.z, 0, along.x), span: (points[1] - points[0]).length)
    }
}

extension Map3DMesh {
    /// A flat face through `corners`, turned to look away from `inside`.
    mutating func addFace(_ corners: [Map3DPoint], awayFrom inside: Map3DPoint, color: UInt32) {
        guard corners.count >= 3, let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { return }
        addFacet(normal.dot(corners[0] - inside) >= 0 ? corners : corners.reversed(), color: color)
    }

    /// Decision 869: a four-sided shaft from the rectangle round `low`
    /// (`lowHalf` each way along `along` and `across`) up to the one round
    /// `high`; its top closed when `capped`.
    mutating func addShaft(low: Map3DPoint, lowHalf: (along: Float, across: Float), high: Map3DPoint, highHalf: (along: Float, across: Float),
                           along: Map3DPoint, across: Map3DPoint, color: UInt32, capped: Bool = false) {
        func ring(_ centre: Map3DPoint, _ half: (along: Float, across: Float)) -> [Map3DPoint] {
            [centre + along * half.along - across * half.across, centre + along * half.along + across * half.across,
             centre - along * half.along + across * half.across, centre - along * half.along - across * half.across]
        }
        let bottom = ring(low, lowHalf), top = ring(high, highHalf), inside = (low + high) * 0.5
        // The faces along the bridge shaded as a box's flanks are.
        let shades: [Float] = [0.92, 0.80, 0.70, 0.86]
        for index in 0..<4 {
            let next = (index + 1) % 4
            addFace([bottom[index], bottom[next], top[next], top[index]], awayFrom: inside, color: Map3DColor.shaded(color, shades[index]))
        }
        if capped { addFace(top, awayFrom: inside, color: color) }
    }

    /// Decision 869: a square bar `thick` a side from `a` to `b`.
    mutating func addBar(from a: Map3DPoint, to b: Map3DPoint, thick: Float, color: UInt32) {
        guard let way = (b - a).normalized else { return }
        let side = way.cross(Map3DPoint(0, 1, 0)).normalized ?? Map3DPoint(1, 0, 0)
        guard let over = side.cross(way).normalized else { return }
        let half = thick / 2
        let corners = [side * half + over * half, side * -half + over * half, side * -half + over * -half, side * half + over * -half]
        let inside = (a + b) * 0.5
        for index in 0..<4 {
            let next = (index + 1) % 4
            // Its top in full, its sides and underside a little darker.
            let shade: Float = index == 0 ? 1 : index == 2 ? 0.72 : 0.86
            addFace([a + corners[index], a + corners[next], b + corners[next], b + corners[index]], awayFrom: inside,
                    color: Map3DColor.shaded(color, shade))
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 869: the suspension bridges whose towers or anchorages
    /// stand within 2 km of what the scene covers.
    mutating func suspensionBridges() -> [Map3DSuspensionBridge.Placed] {
        if let placedSuspensionBridges { return placedSuspensionBridges }
        var found: [Map3DSuspensionBridge.Placed] = []
        if let frame = RealWorldFrame(world: world) {
            let reach = 2_000 * Self.metre
            for bridge in Map3DSuspensionBridge.all {
                guard let placed = bridge.placed(frame: frame, origin: (originX, originY)) else { continue }
                let ends = [placed.point(along: placed.ends.lowerBound, across: 0), placed.point(along: placed.ends.upperBound, across: 0)]
                    .map { (x: originX + Double($0.x) * Self.metre, y: originY + Double($0.z) * Self.metre) }
                let (xs, ys) = (ends.map(\.x), ends.map(\.y))
                guard xs.max()! >= region.minX - reach, xs.min()! <= region.maxX + reach,
                      ys.max()! >= region.minY - reach, ys.min()! <= region.maxY + reach else { continue }
                found.append(placed)
            }
        }
        placedSuspensionBridges = found
        return found
    }

    /// Decision 869: whether a deck at scene point (`x`, `z`) hangs from a
    /// suspension bridge's cables, so no pier stands under it.
    mutating func hangsFromCables(x: Float, z: Float) -> Bool {
        suspensionBridges().contains { $0.carries(x: x, z: z) }
    }

    /// Decision 869: the decks across `bridge` at `station` metres from
    /// its first tower: the road's top (the highest bridge of the base
    /// map within ``Map3DSuspensionBridge/corridor`` of its middle), how
    /// far each side of the surveyed middle the road reaches, the
    /// underside of the lowest deck there (the road's girder, or a
    /// viaduct's of the track under it), and the highest rails on the
    /// ground under the road. `nil` where no road bridge crosses. All of
    /// it from what lies at the station, so a chunk built apart finds
    /// what the whole scene does.
    mutating func suspendedDeck(_ bridge: Map3DSuspensionBridge.Placed, at station: Float) -> Map3DSuspensionBridge.Deck? {
        let reach = Map3DSuspensionBridge.corridor
        var road: Float = -.infinity, left: Float = .infinity, right: Float = -.infinity
        var offset = -reach
        while offset <= reach {
            defer { offset += 0.5 }
            let p = bridge.point(along: station, across: offset)
            let raised = roadRise(at: Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)), along: (Double(bridge.along.x), Double(bridge.along.z)), onDeck: true)
            guard raised.onBridge, raised.rise > 0.05 else { continue }
            road = max(road, drawnGround(x: p.x, z: p.z) + Self.lift(of: .motorway) + raised.rise)
            left = min(left, offset)
            right = max(right, offset)
        }
        guard road.isFinite else { return nil }
        var soffit = road - Map3DElevatedLook.roadBridge.girderDepth, rails: Float?
        let middle = bridge.point(along: station, across: 0)
        let low = Map3DTrackCover.key(x: middle.x - reach, z: middle.z - reach), high = Map3DTrackCover.key(x: middle.x + reach, z: middle.z + reach)
        for row in low.row...high.row {
            for column in low.column...high.column {
                for index in trackCover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                    let piece = trackCover.pieces[index]
                    guard !piece.isTunnel else { continue }
                    let a = bridge.station(x: piece.a.x, z: piece.a.z), b = bridge.station(x: piece.b.x, z: piece.b.z)
                    guard min(a.along, b.along) <= station, station <= max(a.along, b.along), abs(b.along - a.along) > 0.01 else { continue }
                    let t = (station - a.along) / (b.along - a.along)
                    guard abs(a.across + (b.across - a.across) * t) <= reach else { continue }
                    let height = piece.a.y + (piece.b.y - piece.a.y) * t
                    guard height < road else { continue }
                    if piece.isViaduct {
                        soffit = min(soffit, height - Self.bedDrop - piece.girderDepth)
                    } else {
                        rails = max(rails ?? height, height)
                    }
                }
            }
        }
        return Map3DSuspensionBridge.Deck(road: road, left: left, right: right, soffit: soffit, rails: rails)
    }

    /// Whether scene point `p` is in what the scene covers.
    func covers(_ p: Map3DPoint) -> Bool {
        contains(x: originX + Double(p.x) * Self.metre, y: originY + Double(p.z) * Self.metre)
    }

    /// Decision 869: each suspension bridge's towers, main cables,
    /// anchorages, hangers and the fairing along its deck's edges, each
    /// piece in the chunk its middle is in and measured from the deck
    /// under it (so a chunk built apart draws what the whole scene does).
    /// The towers, cables and fairing from any distance; the hangers near.
    /// Where no road bridge crosses (the base map not read), nothing.
    mutating func addSuspensionBridges() {
        typealias Bridge = Map3DSuspensionBridge
        let concrete = Map3DPalette.concrete, steel = Map3DPalette.steel, cladding = Map3DPalette.tankSteel
        let saved = target
        defer { target = saved }
        for bridge in suspensionBridges() {
            target = .base
            // The towers.
            for station in [0, bridge.span] {
                guard covers(bridge.point(along: station, across: 0)), let deck = suspendedDeck(bridge, at: station) else { continue }
                let centre = bridge.point(along: station, across: deck.middle)
                var built = Map3DMesh()
                let road = deck.road
                for side in [Float(-1), 1] {
                    let leg = bridge.point(along: station, across: deck.middle + side * Bridge.legOffset)
                    let ground = drawnGround(x: leg.x, z: leg.z)
                    func at(_ height: Float) -> Map3DPoint { Map3DPoint(leg.x, height, leg.z) }
                    // Its footing, then the leg under the road, wider the
                    // farther down it reaches.
                    let share = min(max((road - ground) / Bridge.footDrop, 0), 1)
                    let top = Bridge.legSections[0]
                    let foot = (along: top.along + (Bridge.foot.along - top.along) * share, across: top.across + (Bridge.foot.across - top.across) * share)
                    built.addShaft(low: at(ground - 1), lowHalf: (foot.along + 2.5, foot.across + 2.5), high: at(ground + 2.5),
                                   highHalf: (foot.along + 2.5, foot.across + 2.5), along: bridge.along, across: bridge.across, color: concrete, capped: true)
                    built.addShaft(low: at(ground + 2.5), lowHalf: foot, high: at(road), highHalf: (top.along, top.across),
                                   along: bridge.along, across: bridge.across, color: concrete)
                    for (lower, upper) in zip(Bridge.legSections, Bridge.legSections.dropFirst()) {
                        built.addShaft(low: at(road + lower.height), lowHalf: (lower.along, lower.across), high: at(road + upper.height),
                                       highHalf: (upper.along, upper.across), along: bridge.along, across: bridge.across, color: concrete)
                    }
                    // The neck, the cap and the saddle's housing.
                    let last = Bridge.legSections[Bridge.legSections.count - 1], cap = Bridge.cap
                    built.addShaft(low: at(road + last.height), lowHalf: (last.along, last.across), high: at(road + cap.bottom),
                                   highHalf: (cap.along, cap.across), along: bridge.along, across: bridge.across, color: concrete)
                    built.addShaft(low: at(road + cap.bottom), lowHalf: (cap.along, cap.across), high: at(road + cap.top),
                                   highHalf: (cap.along, cap.across), along: bridge.along, across: bridge.across, color: concrete)
                    let inside = at(road + (cap.top + Bridge.housing.map(\.height).max()!) / 2)
                    let faces = [Float(-1), 1].map { face in
                        Bridge.housing.map { at(road + $0.height) + bridge.along * $0.along + bridge.across * (face * cap.across) }
                    }
                    for face in faces { built.addFace(face, awayFrom: inside, color: Map3DColor.shaded(cladding, 0.86)) }
                    for index in 0..<Bridge.housing.count - 1 {
                        built.addFace([faces[0][index], faces[1][index], faces[1][index + 1], faces[0][index + 1]], awayFrom: inside,
                                      color: Map3DColor.shaded(cladding, abs(Bridge.housing[index].along + Bridge.housing[index + 1].along) < 6 ? 1 : 0.9))
                    }
                }
                // The portal beams between the legs' inner faces, and the
                // one the deck rests on: clear of the ground, and of a
                // train on rails on the ground under the road.
                var beams = Bridge.beams.map { (bottom: road + $0.bottom, top: road + $0.top, half: Bridge.beamHalf) }
                let under = deck.soffit - 0.1
                let floor = max(max(drawnGround(x: centre.x, z: centre.z), 0) + 2, deck.rails.map { $0 + Bridge.overRails } ?? -.infinity)
                let bottom = max(under - Bridge.lowBeam.depth, floor)
                if under - bottom >= 2 { beams.append((bottom, under, Bridge.lowBeam.half)) }
                let half = Bridge.legOffset - 2.3
                for beam in beams {
                    let low = Map3DPoint(centre.x, beam.bottom, centre.z), high = Map3DPoint(centre.x, beam.top, centre.z)
                    built.addShaft(low: low, lowHalf: (beam.half, half), high: high, highHalf: (beam.half, half),
                                   along: bridge.along, across: bridge.across, color: concrete, capped: true)
                    built.addFace([low + bridge.along * beam.half - bridge.across * half, low + bridge.along * beam.half + bridge.across * half,
                                   low - bridge.along * beam.half + bridge.across * half, low - bridge.along * beam.half - bridge.across * half],
                                  awayFrom: high, color: Map3DColor.shaded(concrete, 0.7))
                }
                mesh(at: bridge.point(along: station, across: 0)) { $0.append(built) }
            }

            // The cables, a piece between each two hangers, with its
            // hanger where the deck hangs from it and the fairing along
            // the deck's edge under it.
            let ends = bridge.ends, marks = bridge.marks
            for (from, to) in zip(marks, marks.dropFirst()) {
                let middle = bridge.point(along: (from + to) / 2, across: 0)
                guard covers(middle), let deckFrom = suspendedDeck(bridge, at: from), let deckTo = suspendedDeck(bridge, at: to) else { continue }
                var cables = Map3DMesh(), hangers = Map3DMesh()
                for side in [Float(-1), 1] {
                    let a = bridge.point(along: from, across: deckFrom.middle + side * Bridge.legOffset, height: deckFrom.road + bridge.cableHeight(at: from))
                    let b = bridge.point(along: to, across: deckTo.middle + side * Bridge.legOffset, height: deckTo.road + bridge.cableHeight(at: to))
                    cables.addBar(from: a, to: b, thick: Bridge.cable, color: steel)
                    // A hanger at the piece's far end, clear of the towers.
                    if bridge.hung.contains(to), to < ends.upperBound - 0.5, abs(to) > 6, abs(to - bridge.span) > 6, b.y - deckTo.road > 3 {
                        hangers.addBar(from: Map3DPoint(b.x, deckTo.road + Bridge.fairingRise, b.z), to: b, thick: Bridge.hanger, color: steel)
                    }
                    // An anchorage where the cables end.
                    for (end, way) in [(ends.lowerBound, Float(-1)), (ends.upperBound, 1)] where end == from || end == to {
                        let deck = end == from ? deckFrom : deckTo
                        let foot = bridge.point(along: end + way * 6, across: deck.middle + side * Bridge.legOffset)
                        let ground = drawnGround(x: foot.x, z: foot.z), top = deck.road + bridge.cableHeight(at: end) + 2
                        guard top - ground > 1 else { continue }
                        cables.addBox(base: Map3DPoint(foot.x, ground, foot.z), forward: bridge.along, length: 24, width: 8, height: top - ground,
                                      top: concrete, side: concrete)
                    }
                    // The fairing: the deck's edge out to its real width,
                    // as deep as the decks together, a darker band along
                    // its middle (the open strip between its upper and
                    // lower cladding); it stops short of the towers' legs.
                    for run in bridge.fairing(from: from, to: to) {
                        let shares = [run.lowerBound, run.upperBound].map { ($0 - from) / (to - from) }
                        func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
                        let line = zip([run.lowerBound, run.upperBound], shares).map { s, t in
                            bridge.point(along: s, across: 0, height: mix(deckFrom.road, deckTo.road, t))
                        }
                        // From the road's edge out to the deck's.
                        let inner = shares.map { side < 0 ? mix(deckFrom.left, deckTo.left, $0) + 0.2 : mix(deckFrom.right, deckTo.right, $0) - 0.2 }
                        let outer = shares.map { mix(deckFrom.middle, deckTo.middle, $0) + side * Bridge.deckHalf }
                        guard zip(inner, outer).allSatisfy({ side * ($1 - $0) > 0.5 }) else { continue }
                        let depth = Bridge.fairingRise + max(min(deckFrom.road - deckFrom.soffit, deckTo.road - deckTo.soffit), 2)
                        let bands: [(share: Float, inset: Float, colour: UInt32)] = [(0.4, 0, cladding), (0.25, 0.5, steel), (0.35, 0, cladding)]
                        var lift = Bridge.fairingRise
                        for band in bands {
                            let edge = outer.map { $0 - side * band.inset }
                            cables.addRibbon(along: line, width: 0, lift: lift, depth: depth * band.share, top: band.colour, side: band.colour,
                                             widths: zip(inner, edge).map { abs($1 - $0) }, offsets: zip(inner, edge).map { ($0 + $1) / 2 })
                            lift -= depth * band.share
                        }
                        // Its underside and its ends.
                        let top = Map3DPoint(0, Bridge.fairingRise, 0), low = Map3DPoint(0, lift, 0)
                        let corners = (0..<2).map { index in [line[index] + bridge.across * inner[index], line[index] + bridge.across * outer[index]] }
                        cables.addFace([corners[0][0] + low, corners[1][0] + low, corners[1][1] + low, corners[0][1] + low],
                                       awayFrom: line[0], color: Map3DColor.shaded(cladding, 0.72))
                        for (index, other) in [(0, 1), (1, 0)] {
                            cables.addFace([corners[index][0] + low, corners[index][1] + low, corners[index][1] + top, corners[index][0] + top],
                                           awayFrom: (corners[other][0] + corners[other][1]) * 0.5, color: Map3DColor.shaded(cladding, 0.86))
                        }
                    }
                }
                target = .base
                mesh(at: middle) { $0.append(cables) }
                target = .near
                mesh(at: middle) { $0.append(hangers) }
                target = .base
            }
        }
    }
}
