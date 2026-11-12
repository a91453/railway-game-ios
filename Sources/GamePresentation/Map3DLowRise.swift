import Foundation
import GameCore

// Decision 707: on a real-world map the game lays houses of its own along
// the roads where the footprints have none (decision 385): a 透天厝 of two
// to four floors, now and then a block of flats of three to six. On Qimei,
// Wang'an, Lanyu, Green Island and Xiaoliuqiu nothing real is over two or
// three storeys, and those stood over every village. So the game's houses
// are no taller than the tallest real building round them, by the
// footprints' own storeys, with no list of islands.

/// The tallest real building round each place of a real-world map, from
/// the footprint tiles, whatever part of the map a scene is built for: a
/// chunk built alone finds what the whole scene does.
struct Map3DLowRise {
    let tiles: FootprintTiles
    let frame: RealWorldFrame
    /// Each tile read so far: how many buildings, and the tallest's storeys.
    private var known: [SIMD2<Int32>: (buildings: Int, tallest: Int)] = [:]

    init(tiles: FootprintTiles, frame: RealWorldFrame) {
        self.tiles = tiles
        self.frame = frame
    }

    /// Fewer real buildings than this round a place say nothing of it.
    static let fewest = 8
    /// The tallest house the game lays along a road (a block of flats'
    /// six floors, `addTownHouse`): a cap of this or more changes nothing.
    static let tallestHouse = 6
    /// No cap under this: a 透天厝 has two floors.
    static let lowest = 2

    /// The most floors a house of the game's may have at (`worldX`,
    /// `worldY`), world units: the storeys of the tallest footprint in its
    /// tile of zoom 16 and the eight round it (some 0.6 to 1.1 km away),
    /// at least ``lowest``; `nil` where that is ``tallestHouse`` or more,
    /// or there are fewer than ``fewest`` footprints to tell by.
    mutating func cap(worldX: Double, worldY: Double) -> Int? {
        let zoom = FootprintTiles.zoom
        let anchorLatitude = frame.anchor.latitudeDegrees
        let pointsPerMetre = RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(anchorLatitude * .pi / 180))
        let tilePoints = RealWorldFrame.worldPoints / Double(1 << zoom), metre = Double(WorldCoordinate.unitsPerMetre)
        let column = Int((((worldX - frame.middleX) / metre * pointsPerMetre + RealWorldFrame.mercatorX(frame.anchor.longitudeDegrees)) / tilePoints)
            .rounded(.down))
        let row = Int((((worldY - frame.middleY) / metre * pointsPerMetre + RealWorldFrame.mercatorY(anchorLatitude)) / tilePoints).rounded(.down))
        var buildings = 0, tallest = 0
        for y in row - 1...row + 1 {
            for x in column - 1...column + 1 {
                let key = SIMD2(Int32(truncatingIfNeeded: x), Int32(truncatingIfNeeded: y))
                let tile: (buildings: Int, tallest: Int)
                if let read = known[key] {
                    tile = read
                } else {
                    let decoded = (try? tiles.archive.tile(zoom: zoom, x: x, y: y)).flatMap { $0 }.flatMap { try? Map3DFootprints.decode($0) } ?? []
                    tile = (decoded.count, decoded.map(\.storeys).max() ?? 0)
                    known[key] = tile
                }
                buildings += tile.buildings
                tallest = max(tallest, tile.tallest)
            }
        }
        guard buildings >= Self.fewest, tallest < Self.tallestHouse else { return nil }
        return max(Self.lowest, tallest)
    }
}

extension Map3DScene.Builder {
    /// Decision 707: the land round the airfields no house of the game's
    /// stands on: each runway's strip, the taxiways and the aprons.
    struct AirfieldClear {
        struct Field {
            var low = (x: Float.infinity, z: Float.infinity)
            var high = (x: -Float.infinity, z: -Float.infinity)
            /// A line's piece and how far from it is kept clear, metres.
            var strips: [(a: (x: Float, z: Float), b: (x: Float, z: Float), half: Float)] = []
            var aprons: [[(x: Float, z: Float)]] = []

            mutating func add(_ line: [Map3DBaseMap.Point], half: Float) {
                let points = line.map { (x: Float($0.x), z: Float($0.z)) }
                for (a, b) in zip(points, points.dropFirst()) {
                    strips.append((a, b, half))
                    low = (min(low.x, min(a.x, b.x) - half), min(low.z, min(a.z, b.z) - half))
                    high = (max(high.x, max(a.x, b.x) + half), max(high.z, max(a.z, b.z) + half))
                }
            }

            mutating func add(apron: [Map3DBaseMap.Point]) {
                let ring = apron.map { (x: Float($0.x), z: Float($0.z)) }
                aprons.append(ring)
                for point in ring {
                    low = (min(low.x, point.x), min(low.z, point.z))
                    high = (max(high.x, point.x), max(high.z, point.z))
                }
            }

            func contains(x: Float, z: Float) -> Bool {
                guard x >= low.x, x <= high.x, z >= low.z, z <= high.z else { return false }
                for strip in strips {
                    let dx = strip.b.x - strip.a.x, dz = strip.b.z - strip.a.z, px = x - strip.a.x, pz = z - strip.a.z
                    let length2 = dx * dx + dz * dz
                    let t = length2 > 0 ? min(max((px * dx + pz * dz) / length2, 0), 1) : 0
                    let ox = px - dx * t, oz = pz - dz * t
                    if ox * ox + oz * oz < strip.half * strip.half { return true }
                }
                return aprons.contains { NoBuild.inside(x, z, $0) }
            }
        }

        var fields: [Field] = []

        func contains(_ point: Map3DPoint) -> Bool {
            fields.contains { $0.contains(x: point.x, z: point.z) }
        }

        /// How far from a runway's centre line no house stands, metres, by
        /// its length: ICAO Annex 14's runway strip, 140 m each side of an
        /// instrument runway of code 3 or 4 (1,200 m and longer) and 75 m
        /// (now 70) of a shorter one.
        static func runwayStrip(length: Double) -> Float {
            length >= 1_200 ? 140 : 75
        }

        /// Beyond a taxiway's edge, metres: a small aircraft's wing.
        static let taxiwayMargin: Float = 15
    }
}
