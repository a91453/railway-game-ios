import GameCore

// Decision 873: a real cable-stayed bridge's mast and stays.
//
// 淡江大橋 crosses the mouth of 淡水河 on one mast: a 450 m main span to
// 八里's side, a 175 m back span to 淡水's, the stays in two planes down
// to the deck's middle. On the base map it was two carriageways on piers
// (decision 391). The mast stands where the two carriageways run widest
// apart (OpenStreetMap, the same lines the base map's tiles are cut
// from), its height and spans as the Directorate General of Highways
// publishes them. As 青馬大橋's towers (decision 869), its heights are
// kept over the road as the game draws it, each piece is measured from
// the deck under it (so a chunk built apart draws what the whole scene
// does), and the spans the stays carry stand on no pier.

/// Decision 873: the mast and stays of a cable-stayed bridge: its mast at
/// the bridge's first tower, its main span towards the second.
struct Map3DCableStays: Sendable {
    /// One stay: where it is anchored on the deck, metres from the mast
    /// (towards the main span's end, or behind the mast when negative),
    /// and where it is held on the mast, metres over the road.
    struct Stay: Sendable, Equatable {
        let anchor: Float
        let hold: Float
    }

    /// The road's top over the sea where the stays carry it.
    let road: Float
    /// The mast's top over the road.
    let top: Float
    /// The mast's half width across the bridge and half length along it,
    /// at heights over the road, from the road up to its top.
    let sections: [(height: Float, across: Float, along: Float)]
    /// The same at the mast's foot.
    let foot: (across: Float, along: Float)
    /// The stays to a side in each plane.
    let count: Int
    /// The lowest and the highest stay's hold on the mast, over the road.
    let holds: ClosedRange<Float>
    /// The nearest and the farthest stay's anchorage from the mast: the
    /// main span's and the back span's.
    let mainAnchors: ClosedRange<Float>
    let backAnchors: ClosedRange<Float>
    /// Each plane of stays from the bridge's middle: at the deck, and at
    /// the mast.
    let plane: (deck: Float, mast: Float)
    /// How thick a stay is drawn (some 0.25 m; three times that here, to
    /// be seen from the map's height).
    let cable: Float

    /// 淡江大橋: a 200 m mast, the road some 20 m over the river at it;
    /// 450 m and 175 m its spans.
    static let danjiang = Map3DCableStays(
        road: 20, top: 180, sections: [(0, 3.0, 6.0), (60, 2.6, 4.8), (120, 2.1, 3.6), (180, 1.6, 2.6)], foot: (3.8, 7.2),
        count: 20, holds: 78...174, mainAnchors: 45...432, backAnchors: 30...168, plane: (4, 1.2), cable: 0.8)

    /// A stay is drawn in pieces this long, each from the deck under it.
    static let piece: Float = 25
    /// A stay's anchorage over the road.
    static let anchorRise: Float = 1
    /// How far round the mast's middle no surveyed building is drawn.
    static let plot: Float = 25
    /// The deck between the carriageways, this far under the road's top.
    static let medianDrop: Float = 0.15

    /// The stays of one plane: the main span's, the nearest first, then
    /// the back span's. The farther a stay is anchored, the higher it is
    /// held.
    var stays: [Stay] {
        [(mainAnchors, Float(1)), (backAnchors, -1)].flatMap { anchors, way in
            (0..<count).map { index in
                let share = count > 1 ? Float(index) / Float(count - 1) : 1
                return Stay(anchor: way * (anchors.lowerBound + (anchors.upperBound - anchors.lowerBound) * share),
                            hold: holds.lowerBound + (holds.upperBound - holds.lowerBound) * share)
            }
        }
    }

    /// `stay`'s middle over the road, `distance` metres from the mast: a
    /// straight line from its hold down to its anchorage.
    func height(of stay: Stay, at distance: Float) -> Float {
        stay.hold + (Self.anchorRise - stay.hold) * min(max(distance / abs(stay.anchor), 0), 1)
    }

    /// How far from the bridge's middle `stay` runs, `distance` metres
    /// from the mast.
    func across(of stay: Stay, at distance: Float) -> Float {
        plane.mast + (plane.deck - plane.mast) * min(max(distance / abs(stay.anchor), 0), 1)
    }

    /// The lengths `stay` is drawn in, metres from the mast: the same
    /// whichever chunk draws them.
    func pieces(of stay: Stay) -> [(from: Float, to: Float)] {
        let reach = abs(stay.anchor)
        var pieces: [(from: Float, to: Float)] = [], from: Float = 0
        while from < reach - 0.5 {
            // The last piece takes what is left of a short one.
            let to = reach - (from + Self.piece) < Self.piece / 3 ? reach : from + Self.piece
            pieces.append((from, to))
            from = to
        }
        return pieces
    }
}

extension Map3DSuspensionBridge {
    /// Decision 873: 淡江大橋, its mast where its carriageways run widest
    /// apart, its main span 450 m towards 八里, its back span 175 m
    /// towards 淡水; both hang from the stays.
    static let danjiang = Map3DSuspensionBridge(towers: [(25.175_40, 121.417_81), (25.171_452, 121.416_752)],
                                                sideSpans: [175, 0], hungSides: [true, false], stays: .danjiang)
}

extension Map3DScene.Builder {
    /// Decision 873: the deck across `bridge` at `station`, read once.
    private mutating func stayedDeck(_ bridge: Map3DSuspensionBridge.Placed, at station: Float,
                                     known: inout [Int: Map3DSuspensionBridge.Deck?]) -> Map3DSuspensionBridge.Deck? {
        let key = Int((station * 100).rounded())
        if let deck = known[key] { return deck }
        let deck = suspendedDeck(bridge, at: station)
        known[key] = deck
        return deck
    }

    /// Decision 873: a cable-stayed bridge's mast, its stays and the deck
    /// between its carriageways, each piece in the chunk its middle is in
    /// and measured from the deck under it. All of it from any distance:
    /// the stays are what the bridge is known by. Where no road bridge
    /// crosses (the base map not read), nothing.
    mutating func addCableStayedBridge(_ bridge: Map3DSuspensionBridge.Placed, stays: Map3DCableStays) {
        let concrete = Map3DPalette.concrete, white = Map3DPalette.sidewalk
        let saved = target
        defer { target = saved }
        target = .base
        var known: [Int: Map3DSuspensionBridge.Deck?] = [:]

        // The mast, from its footing up through the deck's middle.
        let foot = bridge.point(along: 0, across: 0)
        // The base map's own building of the mast (a surveyed outline 200 m
        // high, drawn as a block of flats in the river) is not drawn again.
        if stayedDeck(bridge, at: 0, known: &known) != nil {
            let plot = Map3DCableStays.plot
            landmarkPlots.append(PlacedSquare(minX: foot.x - plot, minZ: foot.z - plot, maxX: foot.x + plot, maxZ: foot.z + plot))
        }
        if covers(foot), let deck = stayedDeck(bridge, at: 0, known: &known) {
            var built = Map3DMesh()
            let ground = drawnGround(x: foot.x, z: foot.z), road = deck.road
            func at(_ height: Float) -> Map3DPoint { Map3DPoint(foot.x, height, foot.z) }
            let cap = min(ground + 3, road - 1)
            built.addShaft(low: at(ground - 1), lowHalf: (stays.foot.along + 5, stays.foot.across + 5), high: at(cap),
                           highHalf: (stays.foot.along + 5, stays.foot.across + 5), along: bridge.along, across: bridge.across, color: concrete, capped: true)
            let first = stays.sections[0]
            built.addShaft(low: at(cap), lowHalf: (stays.foot.along, stays.foot.across), high: at(road), highHalf: (first.along, first.across),
                           along: bridge.along, across: bridge.across, color: concrete)
            for (index, (lower, upper)) in zip(stays.sections, stays.sections.dropFirst()).enumerated() {
                built.addShaft(low: at(road + lower.height), lowHalf: (lower.along, lower.across), high: at(road + upper.height),
                               highHalf: (upper.along, upper.across), along: bridge.along, across: bridge.across, color: concrete,
                               capped: index == stays.sections.count - 2)
            }
            mesh(at: foot) { $0.append(built) }
        }

        // The deck between the carriageways, where the stays carry it:
        // one deck from edge to edge, the stays anchored along its middle.
        let hung = bridge.hung, step = Map3DCableStays.piece
        var from = (hung.lowerBound / step).rounded(.down) * step
        while from < hung.upperBound - 0.5 {
            let a = max(from, hung.lowerBound), b = min(from + step, hung.upperBound)
            from += step
            let middle = bridge.point(along: (a + b) / 2, across: 0)
            guard b - a > 0.5, covers(middle), let deckA = stayedDeck(bridge, at: a, known: &known),
                  let deckB = stayedDeck(bridge, at: b, known: &known) else { continue }
            let drop = Map3DCableStays.medianDrop, depth = Map3DElevatedLook.roadBridge.girderDepth - drop
            // Within the carriageways' outer edges, under their girders.
            let inset: Float = 0.3
            let corners = [(a, deckA.left + inset, deckA.road), (a, deckA.right - inset, deckA.road),
                           (b, deckB.right - inset, deckB.road), (b, deckB.left + inset, deckB.road)]
            let top = corners.map { bridge.point(along: $0.0, across: $0.1, height: $0.2 - drop) }
            let under = top.map { $0 - Map3DPoint(0, depth, 0) }
            let inside = (top[0] + under[2]) * 0.5
            var slab = Map3DMesh()
            slab.addFace(top, awayFrom: inside, color: concrete)
            slab.addFace(under, awayFrom: inside, color: Map3DColor.shaded(concrete, 0.7))
            mesh(at: middle) { $0.append(slab) }
        }

        // The stays, both planes, in pieces.
        for stay in stays.stays {
            let way: Float = stay.anchor < 0 ? -1 : 1
            for piece in stays.pieces(of: stay) {
                let middle = bridge.point(along: way * (piece.from + piece.to) / 2, across: 0)
                guard covers(middle), let deckFrom = stayedDeck(bridge, at: way * piece.from, known: &known),
                      let deckTo = stayedDeck(bridge, at: way * piece.to, known: &known) else { continue }
                var cables = Map3DMesh()
                for side in [Float(-1), 1] {
                    let a = bridge.point(along: way * piece.from, across: side * stays.across(of: stay, at: piece.from),
                                         height: deckFrom.road + stays.height(of: stay, at: piece.from))
                    let b = bridge.point(along: way * piece.to, across: side * stays.across(of: stay, at: piece.to),
                                         height: deckTo.road + stays.height(of: stay, at: piece.to))
                    cables.addBar(from: a, to: b, thick: stays.cable, color: white)
                }
                mesh(at: middle) { $0.append(cables) }
            }
        }
    }
}
