import Foundation
import GameCore

// Decision 873: a real cable-stayed bridge's mast and stays.
//
// 淡江大橋 crosses the mouth of 淡水河 on one mast: a 450 m main span to
// 八里's side, a 175 m back span to 淡水's, the stays in two planes down
// to the deck's middle. On the base map it was two carriageways on piers
// (decision 391). The mast stands where the two carriageways run widest
// apart (OpenStreetMap, the same lines the base map's tiles are cut
// from), its height and spans as the Directorate General of Highways
// publishes them, its mast and fan of stays as the owner's earlier
// version drew them. As 青馬大橋's towers (decision 869), its heights are
// kept over the road as the game draws it, each piece is measured from
// the deck under it (so a chunk built apart draws what the whole scene
// does), and the spans the stays carry stand on no pier.

/// Decision 873: the mast and stays of a cable-stayed bridge: its mast at
/// the bridge's first tower, its main span towards the second.
///
/// The mast's shape and the stays' fan are the owner's earlier 淡江大橋
/// (`OpenWorld/reference_snapshot/play/src/world/tamkang-bridge.js` and
/// `play/assets/bridge/manifest.json`'s `towerProfile` in the reference
/// repository): two legs standing apart along the bridge that lean
/// together and meet at the top, 27 pairs of stays to the main span and
/// 20 to the back span.
struct Map3DCableStays: Sendable {
    /// One stay: where it is anchored on the deck, metres from the mast
    /// (towards the main span's end, or behind the mast when negative),
    /// where it is held on the mast, metres over the road, and how far
    /// from the mast's middle the leg's face is there.
    struct Stay: Sendable, Equatable {
        let anchor: Float
        let hold: Float
        let start: Float
    }

    /// The road's top over the water where the stays carry it.
    let road: Float
    /// The mast's top over the road.
    let top: Float
    /// Each leg's middle from the mast's at the water (`tower-
    /// Profile.legHalfOffset`), and how fast the legs close
    /// (`offsetExponent`).
    let legApart: Float
    let legCurve: Float
    /// A leg's length along the bridge and width across it, at the water
    /// and at the top (`widthBase`/`widthTaper`, `depthBase`/`depthTaper`).
    let legAlong: (foot: Float, top: Float)
    let legAcross: (foot: Float, top: Float)
    /// The legs no wider than this across the bridge up to this height
    /// over the road, their own width from the second height on
    /// (`roadClearance`: the carriageways pass either side).
    let waist: (across: Float, to: Float, free: Float)
    /// Where the legs are one: its height down from the top, its width
    /// across the bridge.
    let crown: (height: Float, across: Float)
    /// The pairs of stays to the main span and to the back span.
    let count: (main: Int, back: Int)
    /// The lowest and the highest stay's hold on the mast, over the road.
    let holds: ClosedRange<Float>
    /// The farthest stay's anchorage from the mast, each way.
    let reach: (main: Float, back: Float)
    /// Each plane of stays from the bridge's middle: at the deck, and at
    /// the mast.
    let plane: (deck: Float, mast: Float)
    /// How thick a stay is drawn (the earlier version's 0.68 m, a little
    /// more here to be seen from the map's height).
    let cable: Float

    /// 淡江大橋: a 200 m mast, the road 20 m over the river at it; 450 m
    /// and 175 m its spans.
    static let danjiang = Map3DCableStays(
        road: 20, top: 180, legApart: 13, legCurve: 1.55, legAlong: (7.5, 4.1), legAcross: (11, 5.8),
        waist: (4.8, 7, 60), crown: (16, 6.2), count: (27, 20), holds: 75...162, reach: (432, 168), plane: (4, 1.2), cable: 0.8)

    /// The deck between the carriageways is drawn in pieces this long.
    static let piece: Float = 25
    /// A stay is drawn in pieces this long, each from the deck under it.
    static let stayPiece: Float = 50
    /// A stay's anchorage over the road.
    static let anchorRise: Float = 1
    /// How far round the mast's middle no surveyed building is drawn.
    static let plot: Float = 25
    /// The deck between the carriageways, this far under the road's top.
    static let medianDrop: Float = 0.15
    /// The nearest stay's anchorage, as a share of the farthest's, and
    /// how the rest are spread (the earlier version's fan).
    static let fan: (first: Float, curve: Float) = (0.10, 0.94)

    /// How far up the mast `height` over the road is: 0 at the water, 1
    /// at the top.
    func share(at height: Float) -> Float { min(max((height + road) / (top + road), 0), 1) }

    /// A leg at `height` over the road: its middle from the mast's along
    /// the bridge, and its half length along and half width across.
    func leg(at height: Float) -> (offset: Float, along: Float, across: Float) {
        let t = share(at: height)
        var across = legAcross.foot + (legAcross.top - legAcross.foot) * t
        if height <= waist.to {
            across = min(across, waist.across)
        } else if height < waist.free {
            across = min(across, waist.across + (across - waist.across) * (height - waist.to) / (waist.free - waist.to))
        }
        return (legApart * (1 - Float(pow(Double(t), Double(legCurve)))), (legAlong.foot + (legAlong.top - legAlong.foot) * t) / 2, across / 2)
    }

    /// The stays of one plane: the main span's, the nearest first, then
    /// the back span's. The farther a stay is anchored, the higher it is
    /// held (the earlier version held the farthest lowest, so its stays
    /// crossed; the bridge's do not).
    var stays: [Stay] {
        [(reach.main, count.main, Float(1)), (reach.back, count.back, -1)].flatMap { reach, count, way in
            (1...max(count, 1)).map { index in
                let share = Float(index) / Float(max(count, 1))
                let hold = holds.lowerBound + (holds.upperBound - holds.lowerBound) * share
                let leg = leg(at: hold)
                return Stay(anchor: way * reach * (Self.fan.first + (1 - Self.fan.first) * Float(pow(Double(share), Double(Self.fan.curve)))),
                            hold: hold, start: leg.offset + leg.along)
            }
        }
    }

    /// How far along `stay` `distance` metres from the mast's middle is.
    private func along(_ stay: Stay, _ distance: Float) -> Float {
        min(max((distance - stay.start) / (abs(stay.anchor) - stay.start), 0), 1)
    }

    /// `stay`'s middle over the road, `distance` metres from the mast: a
    /// straight line from its hold down to its anchorage.
    func height(of stay: Stay, at distance: Float) -> Float {
        stay.hold + (Self.anchorRise - stay.hold) * along(stay, distance)
    }

    /// How far from the bridge's middle `stay` runs, `distance` metres
    /// from the mast.
    func across(of stay: Stay, at distance: Float) -> Float {
        plane.mast + (plane.deck - plane.mast) * along(stay, distance)
    }

    /// The lengths `stay` is drawn in, metres from the mast: the same
    /// whichever chunk draws them.
    func pieces(of stay: Stay) -> [(from: Float, to: Float)] {
        let reach = abs(stay.anchor)
        var pieces: [(from: Float, to: Float)] = [], from = stay.start
        while from < reach - 0.5 {
            // The last piece takes what is left of a short one.
            let to = reach - (from + Self.stayPiece) < Self.stayPiece / 3 ? reach : from + Self.stayPiece
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
            let base = stays.leg(at: cap - road)
            built.addShaft(low: at(ground - 1), lowHalf: (base.offset + base.along + 1.5, stays.legAcross.foot / 2 + 2.5), high: at(cap),
                           highHalf: (base.offset + base.along + 1.5, stays.legAcross.foot / 2 + 2.5), along: bridge.along, across: bridge.across,
                           color: concrete, capped: true)
            // Two legs apart along the bridge, leaning together; one
            // where they meet.
            let crown = stays.top - stays.crown.height
            var heights: [Float] = [cap - road, 0, stays.waist.to]
            var height = stays.waist.to
            while height < crown - 1 {
                height = min(height + 12, crown)
                heights.append(height)
            }
            for (lower, upper) in zip(heights, heights.dropFirst()) where upper > lower {
                let low = stays.leg(at: lower), high = stays.leg(at: upper)
                for side in [Float(-1), 1] {
                    built.addShaft(low: at(road + lower) + bridge.along * (side * low.offset), lowHalf: (low.along, low.across),
                                   high: at(road + upper) + bridge.along * (side * high.offset), highHalf: (high.along, high.across),
                                   along: bridge.along, across: bridge.across, color: concrete)
                }
            }
            let meet = stays.leg(at: crown), peak = stays.leg(at: stays.top)
            built.addShaft(low: at(road + crown), lowHalf: (meet.offset + meet.along, stays.crown.across / 2), high: at(road + stays.top),
                           highHalf: (peak.offset + peak.along, stays.crown.across / 2), along: bridge.along, across: bridge.across,
                           color: concrete, capped: true)
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
