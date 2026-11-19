import GameCore

// Decision 888 (GRADE-CROSSING-LOOK): a diamond crossing in the 3D map.
//
// GameCore has had diamonds since decisions 26 and 29, and decision 887
// lets a player lay one by drawing across track at one level; until now
// the scene drew the two tracks' rails straight through each other. Here
// the crossing is drawn as the owner's old version (SwiftRailMac) drew its
// three diamond pieces (`assets/models/item_2508203f…` 12 m at 90°,
// `item_541b351d…` 23 × 20 m at 67.5°, `item_310cb806…` 32 × 31 m at 45°),
// their white models kept and their texture dropped (decision 767's B):
//
// - Each running rail stops short of the other track's rail where it
//   enters the diamond, leaving a flangeway; outside the diamond the two
//   tracks' rails run on into the corner and meet there, an L.
// - Where a rail inside the diamond stops, a short wing rail turns off
//   beside the other track's rail, on its gauge side, outwards: one each
//   side of each of the four corners, eight in all.
//
// The old pieces come at three angles only; the same layout is worked out
// here for any angle a diamond is laid at (decision 887: 1 in 4, 14.5°,
// to 90°), the flangeway and wing rails lengthening as the angle flattens,
// as they do in the old 45° piece against its 90° one. The old pieces'
// rails stand 3 m apart for a 3 m gauge model; across, the parts keep
// their place relative to the rails at the map's gauge (decision 799),
// along, the wing rails keep the old length. Rails, flangeway and wing
// rails in the rails' own colours: no new colour.

/// Decision 888: a diamond crossing of the track network, in a scene.
struct Map3DDiamondCrossing: Equatable, Sendable {
    /// Where the node is, at the rails' height (``Map3DScene/Builder/lifted``).
    let point: Map3DPoint
    /// Where it is in the world, to tell which scene builds it.
    let world: WorldCoordinate
    /// The two tracks' ways through it, level and of unit length.
    let first: Map3DPoint
    let second: Map3DPoint

    /// The sine of the angle the tracks cross at.
    var sine: Float { abs(first.x * second.z - first.z * second.x) }
}

enum Map3DDiamondCrossings {
    /// The flangeway left between a rail's end and the rail it crosses,
    /// across that rail (the old pieces' 0.07 m on a 3 m gauge, at least a
    /// real flangeway's 45 mm and a little to be seen).
    static let flangeway: Float = 0.05
    /// How far a wing rail runs out beyond the corner at 90°, metres; at a
    /// flatter angle, this over its sine (the old pieces' 1.0 m at 90° and
    /// 1.4 m at 45°).
    static let wingLength: Float = 1.0
    /// Two edge ends leave a node the opposite way to within 1 in 16
    /// (``TrackNodeEnd/exits``).
    static let opposite: Float = -(1 - 1 / 512)
    /// Flatter than this, two pairs of ends are not taken for a diamond:
    /// decision 887's tool lays none flatter than 1 in 4.
    static let flattest: Float = 0.2

    /// The diamonds of `snapshot`: each node where four edges end in two
    /// pairs leaving it opposite ways, crossing at 1 in 5 or more. In the
    /// order of the nodes' IDs.
    static func find(_ snapshot: RailwaySnapshot, scene: (WorldCoordinate) -> Map3DPoint) -> [Map3DDiamondCrossing] {
        func level(_ v: PlanVector) -> Map3DPoint? { Map3DPoint(Float(v.dx), 0, Float(v.dy)).normalized }
        var ends: [TrackNodeID: [Map3DPoint]] = [:]
        for alignment in snapshot.edges where alignment.edge.from != alignment.edge.to {
            if let start = level(alignment.geometry.startDirection) { ends[alignment.edge.from, default: []].append(start) }
            if let end = level(alignment.geometry.endDirection) { ends[alignment.edge.to, default: []].append(end) }
        }
        var crossings: [Map3DDiamondCrossing] = []
        for node in snapshot.nodes {
            guard let ways = ends[node.id], ways.count == 4,
                  let partner = (1..<4).first(where: { ways[0].dot(ways[$0]) < opposite })
            else { continue }
            let others = (1..<4).filter { $0 != partner }
            guard ways[others[0]].dot(ways[others[1]]) < opposite else { continue }
            let crossing = Map3DDiamondCrossing(point: scene(node.position), world: node.position, first: ways[0], second: ways[others[0]])
            if crossing.sine >= flattest { crossings.append(crossing) }
        }
        return crossings
    }

    /// `line` without the stretches `gaps` (metres along it in plan), in
    /// the pieces left.
    static func cut(_ line: [Map3DPoint], without gaps: [ClosedRange<Float>]) -> [[Map3DPoint]] {
        var travelled: [Float] = [0]
        for index in 1..<line.count {
            let step = line[index] - line[index - 1]
            travelled.append(travelled[index - 1] + Map3DPoint(step.x, 0, step.z).length)
        }
        let total = travelled[travelled.count - 1]
        func point(at distance: Float) -> Map3DPoint {
            let index = max(1, min(line.count - 1, travelled.firstIndex { $0 >= distance } ?? line.count - 1))
            let length = travelled[index] - travelled[index - 1]
            let share = length > 0 ? (distance - travelled[index - 1]) / length : 0
            return line[index - 1] + (line[index] - line[index - 1]) * min(max(share, 0), 1)
        }
        var pieces: [[Map3DPoint]] = []
        var from: Float = 0
        for gap in gaps.sorted(by: { $0.lowerBound < $1.lowerBound }) + [total...total] {
            let to = min(gap.lowerBound, total)
            if to - from > 0.01 {
                pieces.append([point(at: from)] + line.indices.filter { travelled[$0] > from && travelled[$0] < to }.map { line[$0] } + [point(at: to)])
            }
            from = max(from, gap.upperBound)
        }
        return pieces
    }
}

extension Map3DScene.Builder {
    /// Decision 888: the diamond at `end` of a line of track, if one is.
    func diamond(at end: Map3DPoint) -> Map3DDiamondCrossing? {
        diamonds.first { Map3DPoint($0.point.x - end.x, 0, $0.point.z - end.z).length < 0.05 && abs($0.point.y - end.y) < 0.5 }
    }

    /// Decision 888: where along `line` (metres from its start) the rail
    /// `offset` to its right (negative: left) leaves a flangeway at a
    /// diamond at either end: just short of the other track's rail, on the
    /// diamond's side of it.
    func diamondGaps(_ line: [Map3DPoint], offset: Float) -> [ClosedRange<Float>] {
        guard line.count > 1, !diamonds.isEmpty else { return [] }
        var travelled: Float = 0
        for (a, b) in zip(line, line.dropFirst()) { travelled += Map3DPoint(b.x - a.x, 0, b.z - a.z).length }
        var gaps: [ClosedRange<Float>] = []
        for atStart in [true, false] {
            let end = atStart ? line[0] : line[line.count - 1]
            let next = atStart ? line[1] : line[line.count - 2]
            guard let diamond = diamond(at: end), let chord = Map3DPoint(next.x - end.x, 0, next.z - end.z).normalized else { continue }
            // The way out along this track, and the other track's.
            let ways = [diamond.first, diamond.first * -1, diamond.second, diamond.second * -1]
            guard let way = ways.max(by: { $0.dot(chord) < $1.dot(chord) }) else { continue }
            let other = abs(way.dot(diamond.first)) > abs(way.dot(diamond.second)) ? diamond.second : diamond.first
            // The rail's offset across the way out (the line's own right,
            // ``Map3DMesh/acrossDirections(_:)``, at the start; its left
            // at the end, the line running the other way).
            let across = Map3DPoint(-way.z, 0, way.x) * (atStart ? offset : -offset)
            let normal = Map3DPoint(-other.z, 0, other.x)
            let towards = way.dot(normal)
            guard abs(towards) > 0.01 else { continue }
            let half = abs(offset)
            let corners = [half, -half].map { ($0 - across.dot(normal)) / towards }.filter { $0 > 0 }
            guard let corner = corners.min() else { continue }
            let sine = abs(towards)
            let near = corner - (Self.railWidth / 2 + Map3DDiamondCrossings.flangeway) / sine
            let far = corner - Self.railWidth / 2 / sine
            guard near > 0 else { continue }
            gaps.append(atStart ? near...far : (travelled - far)...(travelled - near))
        }
        return gaps
    }

    /// Decision 888: the wing rails of the diamonds in the region, beside
    /// the rails at each corner.
    mutating func addDiamondWings() {
        let region = region
        for diamond in diamonds {
            let x = Double(diamond.world.x), y = Double(diamond.world.y)
            guard x >= region.minX, x <= region.maxX, y >= region.minY, y <= region.maxY else { continue }
            let wings = Map3DDiamondCrossings.wings(of: diamond, gauge: look.gauge)
            mesh(at: diamond.point) { mesh in
                for wing in wings {
                    mesh.addRibbon(along: wing, width: Self.railWidth, lift: 0, depth: Self.railHeight, top: Map3DPalette.railTop, side: Map3DPalette.rail)
                }
            }
        }
    }
}

extension Map3DDiamondCrossings {
    /// Decision 888: `diamond`'s eight wing rails at `gauge`, each from
    /// its start to its end: at each corner, one beside each track's rail
    /// on its gauge side, from the other track's rail outwards.
    static func wings(of diamond: Map3DDiamondCrossing, gauge: Float) -> [[Map3DPoint]] {
        typealias Builder = Map3DScene.Builder
        let offset = (gauge + Builder.railWidth) / 2
        let spacing = Builder.railWidth + flangeway
        let a = diamond.first, b = diamond.second
        let normalA = Map3DPoint(-a.z, 0, a.x), normalB = Map3DPoint(-b.z, 0, b.x)
        let length = wingLength / diamond.sine
        var wings: [[Map3DPoint]] = []
        for i: Float in [-1, 1] {
            for j: Float in [-1, 1] {
                // The corner where rail i of the first track meets rail j
                // of the second, from the node.
                let along = (j * offset - i * offset * normalA.dot(normalB)) / a.dot(normalB)
                let corner = normalA * (i * offset) + a * along
                let outA = corner.dot(a) >= 0 ? a : a * -1, outB = corner.dot(b) >= 0 ? b : b * -1
                // Beside the second track's rail j, on its gauge side, from
                // the first track's rail outwards; and the same beside the
                // first track's rail i.
                let startB = corner + a * (-j * spacing / a.dot(normalB))
                let startA = corner + b * (-i * spacing / b.dot(normalA))
                wings.append([diamond.point + startB, diamond.point + startB + outB * length])
                wings.append([diamond.point + startA, diamond.point + startA + outA * length])
            }
        }
        return wings
    }
}
