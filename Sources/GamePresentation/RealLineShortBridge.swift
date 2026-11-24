import GameCore

// BRANCH-SHORT-BRIDGE (decision 950, TERRAIN-CHECK-A's first item): a real
// line's bridges shorter than ``TrackRise/shortestCarried`` (160 m) bound
// nothing in ``TrackRise`` (decision 279): what the game's ground and
// water make of the track there stands. A river narrower than the 58 m
// water cells has no water cell, so nothing made the track a bridge unless
// the ground left it more than 8 m up (a viaduct). On the four branch
// lines on sale (Pingxi, Jiji, Neiwan, Shenao) 11 of the 33 samples on a
// real bridge were laid as one; the Yilan Line's 82 m over the Keelung
// River south of Sandiaoling went from a viaduct on the old ground to an
// embankment across the river on the new (decision 943).
//
// Now each such bridge (one shorter than ``shortestBridge``, 16 m, laid
// that long about its middle), clear of the
// stations and the other nodes the line forces, has a node at each end,
// and the edges between them are laid as bridges (``TrackStructure/bridge``)
// where the track ``TrackRise`` already gives is at or above the ground
// there, as a bridge must stand (``TrackStructure/allows(height:)``) and
// clear of any water by 4 m; elsewhere, in a cutting under a hill the
// coarse ground made, they stay automatic, as before. The track's heights
// do not change, so neither does anything else along the line.
//
// The rule is the reference's: `Railway/rail-reference/regions/taiwan/
// source/rail-3d/integration/rail-structures.js` draws every segment OSM
// tags a bridge as one, however short (`if(bridge||railLift>=VIADUCT_
// LIFT_M)`). The site draws lines; the game builds edges GameCore must
// accept, hence the height check and the 16 m floor, which are this
// project's own.

extension RealLineAcquisition {
    /// The shortest bridge laid: one pricing length
    /// (``ConstructionCosts/trackPricingLength``, 16 m), what the game
    /// judges and prices track by. A shorter real bridge (a stream's span
    /// of 5 to 15 m, most of the Jiji Line's) is laid this long, about
    /// its middle.
    static let shortestBridge = Double(ConstructionCosts.trackPricingLength)

    /// How far over the ground, at least, a short bridge's track must be
    /// at each pricing length's middle and at its ends: a little over the
    /// 0 a bridge must keep (``TrackStructure/allows(height:)``), so that a
    /// later read of the same ground rounded otherwise still allows it.
    static let shortBridgeLift: Int64 = 8

    /// The stretches of the path, by distance along it, of the real line's
    /// bridges shorter than ``TrackRise/shortestCarried`` in `carried`, at
    /// least ``shortestBridge`` long (a shorter one lengthened about its
    /// middle) and wholly on the path, whose ends are
    /// at least ``RealWorldDemo/shortestEdge`` from every distance in
    /// `forced` and outside `keepOut` and its margin
    /// (``RealWorldDemo/platformMargin``), and where `rise` allows a node.
    static func shortBridges(
        _ carried: [TrackRise.Carried], length: Double, forced: [Double], keepOut: [ClosedRange<Double>], rise: TrackRise
    ) -> [ClosedRange<Double>] {
        let margin = RealWorldDemo.platformMargin
        let zones = keepOut.map { ($0.lowerBound - margin)...($0.upperBound + margin) }
        var taken = forced
        var found: [ClosedRange<Double>] = []
        for stretch in carried where stretch.kind == .bridge && !stretch.isLong {
            let middle = (stretch.range.lowerBound + stretch.range.upperBound) / 2
            let half = max(stretch.range.upperBound - stretch.range.lowerBound, shortestBridge) / 2
            let range = (middle - half)...(middle + half)
            guard range.lowerBound > 0, range.upperBound < length,
                  !zones.contains(where: { $0.overlaps(range) }) else { continue }
            let ends = [range.lowerBound, range.upperBound]
            guard ends.allSatisfy({ end in
                rise.allowsNode(at: end) && !taken.contains { abs($0 - end) < RealWorldDemo.shortestEdge }
            }) else { continue }
            taken += ends
            found.append(range)
        }
        return found
    }

    /// What carries each edge of a piece laid along the path, `distances`
    /// along it (its nodes `nodes`, its curves `curves`): a bridge where
    /// the edge lies within one of `bridges` (``shortBridges(_:length:forced:keepOut:rise:)``)
    /// and its track is at least ``shortBridgeLift`` over the ground of
    /// `world` at its ends and at every pricing length's middle, and 4 m
    /// over any water there (as ``GameWorld`` judges a bridge); otherwise
    /// `structure`. `nil` where every edge is `structure`.
    static func shortBridgeStructures(
        nodes: [WorldCoordinate], curves: [TrackCurve], distances: [Double], bridges: [ClosedRange<Double>], structure: TrackStructure, in world: GameWorld
    ) -> [TrackStructure]? {
        guard !bridges.isEmpty, structure == .automatic, nodes.count == curves.count + 1, distances.count == nodes.count else { return nil }
        let mapped = world.ground.isMapped
        let structures = curves.indices.map { index -> TrackStructure in
            let a = distances[index], b = distances[index + 1]
            guard bridges.contains(where: { $0.lowerBound - 1 <= a && b <= $0.upperBound + 1 }),
                  let geometry = TrackGeometry(from: nodes[index], to: nodes[index + 1], curve: curves[index]) else { return structure }
            let priced = ConstructionCosts.trackPricingLength
            let count = max(1, (geometry.length + priced - 1) / priced)
            let middles = (0..<count).map { (($0 * priced) + min(geometry.length, ($0 + 1) * priced)) / 2 }
            let holds = ([0, geometry.length] + middles).allSatisfy { distance in
                let point = geometry.location(at: distance).position
                guard let ground = world.groundHeight(at: point.plan) else { return false }
                let over = point.z - ground
                let wet = mapped && world.terrain.isWater(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
                return over >= (wet ? TrackSectionRules.waterClearance : 0) + shortBridgeLift && over <= TrackSectionRules.highestDeck
            }
            return holds ? .bridge : structure
        }
        return structures.contains(where: { $0 != structure }) ? structures : nil
    }
}

extension RealLineAcquisition.Piece {
    /// What carries its edge `index`: its own of ``structures`` where it
    /// has them (decision 950), else ``structure``.
    func structure(ofEdge index: Int) -> TrackStructure {
        guard let structures, structures.indices.contains(index) else { return structure }
        return structures[index]
    }
}
