import Foundation
import GameCore

// Decision 723: decision 389 kept the game's own houses off every 64 m
// cell a real building's box reaches (a footprint's, or one of decision
// 239's city tiles'). Where the real buildings are thin (round Kaohsiung
// Station, a building or two a cell where rows of 透天厝 stand) that left
// the blocks mostly bare ground. So a cell the real buildings cover less
// than ``Map3DScene/Builder/RealCover/thinShare`` of is no longer kept
// whole: the houses along its roads (decision 385) are laid on it, each
// clear of every real building's own outline. A cell covered more than
// that stays as decision 389 left it.

extension Map3DScene.Builder {
    /// Decision 723: the real buildings of one source drawn (the city
    /// tiles', ``addRealBuildings``; the footprints', ``addFootprints``):
    /// each one's outline, which a house of the game's keeps off, and how
    /// much of each 64 m cell they cover.
    struct RealCover {
        struct Outline {
            /// Scene metres.
            let ring: [(x: Float, z: Float)]
            let low: (x: Float, z: Float)
            let high: (x: Float, z: Float)
        }

        var outlines: [Outline] = []
        /// The outlines whose boxes, ``margin`` wider, reach each cell.
        var byCell: [Map3DScene.ChunkKey: [Int]] = [:]
        /// The share of each cell with a building under the buildings.
        var share: [Map3DScene.ChunkKey: Double] = [:]
        /// The cells of a building not drawn (cleared for one of the
        /// player's), which keep no house either.
        var kept = Set<Map3DScene.ChunkKey>()

        /// The share of a 64 m cell under real buildings below which the
        /// game's houses are laid along its roads.
        static let thinShare = 0.25
        /// How far a house of the game's keeps from a real building, metres.
        static let margin: Float = 1

        /// Whether `house` reaches within ``margin`` of a building.
        func reaches(_ house: StreetHouse, cells: Set<Map3DScene.ChunkKey>) -> Bool {
            let radius = (house.width * house.width + house.depth * house.depth).squareRoot() / 2 + Self.margin
            var seen = Set<Int>()
            for cell in cells {
                for index in byCell[cell] ?? [] where seen.insert(index).inserted {
                    let outline = outlines[index]
                    guard house.middle.x + radius >= outline.low.x, house.middle.x - radius <= outline.high.x,
                          house.middle.z + radius >= outline.low.z, house.middle.z - radius <= outline.high.z else { continue }
                    if NoBuild.inside(house.middle.x, house.middle.z, outline.ring) { return true }
                    var previous = outline.ring[outline.ring.count - 1]
                    for point in outline.ring {
                        if house.distance(from: Map3DPoint(previous.x, 0, previous.z), to: Map3DPoint(point.x, 0, point.z)) < Self.margin { return true }
                        previous = point
                    }
                }
            }
            return false
        }
    }

    /// Decision 723: counts a real building of `rings` (its outline then
    /// its holes, world units) into `cover`: the cells its box reaches
    /// (which it returns), how much of each it covers, and, when `drawn`,
    /// its outline for the game's houses to keep off.
    @discardableResult
    func count(_ rings: [[(x: Double, y: Double)]], drawn: Bool, into cover: inout RealCover) -> [Map3DScene.ChunkKey] {
        guard let outline = rings.first, outline.count >= 3 else { return [] }
        let cell = Double(Land.cellLength)
        func key(_ x: Double, _ y: Double) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((y / cell).rounded(.down)))
        }
        let low = (x: outline.map(\.x).min() ?? 0, y: outline.map(\.y).min() ?? 0)
        let high = (x: outline.map(\.x).max() ?? 0, y: outline.map(\.y).max() ?? 0)
        var under: [Map3DScene.ChunkKey] = []
        for row in key(low.x, low.y).row...key(high.x, high.y).row {
            for column in key(low.x, low.y).column...key(high.x, high.y).column {
                let here = Map3DScene.ChunkKey(column: column, row: row)
                under.append(here)
                guard drawn else {
                    cover.kept.insert(here)
                    continue
                }
                let west = Double(column) * cell, north = Double(row) * cell
                var area = 0.0
                for (index, ring) in rings.enumerated() {
                    let part = Map3DFootprints.area(of: ring, minX: west, minY: north, maxX: west + cell, maxY: north + cell)
                    area += index == 0 ? part : -part
                }
                cover.share[here, default: 0] += max(0, area) / (cell * cell)
            }
        }
        guard drawn else { return under }
        let margin = Double(RealCover.margin) * Self.metre
        for row in key(low.x - margin, low.y - margin).row...key(high.x + margin, high.y + margin).row {
            for column in key(low.x - margin, low.y - margin).column...key(high.x + margin, high.y + margin).column {
                cover.byCell[Map3DScene.ChunkKey(column: column, row: row), default: []].append(cover.outlines.count)
            }
        }
        let ring = outline.map { world -> (x: Float, z: Float) in
            let scene = point(x: world.x, y: world.y, height: 0)
            return (scene.x, scene.z)
        }
        cover.outlines.append(.init(ring: ring, low: (ring.map(\.x).min() ?? 0, ring.map(\.z).min() ?? 0),
                                    high: (ring.map(\.x).max() ?? 0, ring.map(\.z).max() ?? 0)))
        return under
    }

    /// Decision 723: the cells with a real building that the real
    /// buildings cover less than ``RealCover/thinShare`` of, but those of
    /// `others` (a landmark's, a temple's, a kit's scene's, water).
    func thinlyBuilt(but others: Set<Map3DScene.ChunkKey>) -> Set<Map3DScene.ChunkKey> {
        var thin = Set<Map3DScene.ChunkKey>()
        for cell in Set(tileCover.share.keys).union(footprintCover.share.keys) {
            guard (tileCover.share[cell] ?? 0) + (footprintCover.share[cell] ?? 0) < RealCover.thinShare,
                  !tileCover.kept.contains(cell), !footprintCover.kept.contains(cell), !others.contains(cell) else { continue }
            thin.insert(cell)
        }
        return thin
    }
}

extension Map3DFootprints {
    /// Decision 723: the area of `ring` (any units) on the square from
    /// (`minX`, `minY`) to (`maxX`, `maxY`), in those units squared: the
    /// ring cut to each of the square's sides in turn.
    static func area(of ring: [(x: Double, y: Double)], minX: Double, minY: Double, maxX: Double, maxY: Double) -> Double {
        var points = ring
        func cut(_ inside: ((x: Double, y: Double)) -> Bool, _ crossing: ((x: Double, y: Double), (x: Double, y: Double)) -> (x: Double, y: Double)) {
            guard var previous = points.last else { return }
            var kept: [(x: Double, y: Double)] = []
            for point in points {
                if inside(point) {
                    if !inside(previous) { kept.append(crossing(previous, point)) }
                    kept.append(point)
                } else if inside(previous) {
                    kept.append(crossing(previous, point))
                }
                previous = point
            }
            points = kept
        }
        cut({ $0.x >= minX }) { a, b in (minX, a.y + (b.y - a.y) * (minX - a.x) / (b.x - a.x)) }
        cut({ $0.x <= maxX }) { a, b in (maxX, a.y + (b.y - a.y) * (maxX - a.x) / (b.x - a.x)) }
        cut({ $0.y >= minY }) { a, b in (a.x + (b.x - a.x) * (minY - a.y) / (b.y - a.y), minY) }
        cut({ $0.y <= maxY }) { a, b in (a.x + (b.x - a.x) * (maxY - a.y) / (b.y - a.y), maxY) }
        guard var previous = points.last else { return 0 }
        var doubled = 0.0
        for point in points {
            doubled += previous.x * point.y - point.x * previous.y
            previous = point
        }
        return abs(doubled) / 2
    }
}
