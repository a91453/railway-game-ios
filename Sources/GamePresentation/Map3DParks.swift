import Foundation
import GameCore

// Decision 331: the park kit's four scenes (#946's `Map3DParkKit`, used as
// they are) in a real-world map's parks, the base map's own park areas: a
// pond, gazebo and footbridge or a sports ground in a big park, a
// playground in a middling one, a pocket garden in a small one. Close up
// only; the park's green ground is there from every distance.

extension Map3DScene.Builder {
    /// Close up, the most triangles a scene's parks may have, and a 512 m
    /// chunk's: past them, only the parks nearest the scene's middle.
    static let parkTriangles = 80_000
    static let parkChunkTriangles = 16_000

    /// No two park scenes nearer than this: one to a park, for most parks,
    /// though a park's area comes once for each base map tile it spans.
    static let parkSpacing: Float = 150

    /// A park's area over which it gets a big scene, and over which a
    /// middling one, in square metres.
    static let bigPark = 20_000.0
    static let middlingPark = 5_000.0

    /// A park scene drawn: the model, the middle of its ground at the
    /// origin, its front +x; how long and wide that ground is.
    struct ParkModel: Sendable {
        let mesh: Map3DMesh
        let length: Float
        let width: Float

        var triangles: Int { mesh.indices.count / 3 }
    }

    /// Each of the kit's scenes, with its ground's size
    /// (`Map3DParkKit.model(for:)`'s first box).
    static let parkModels: [Map3DParkKit.Example: ParkModel] = {
        func model(_ example: Map3DParkKit.Example, _ length: Float, _ width: Float) -> ParkModel {
            var builder = StationKitBuilder()
            builder.add(Map3DParkKit.model(for: example), at: .zero)
            return ParkModel(mesh: builder.mesh, length: length, width: width)
        }
        return [
            .gardenWalk: model(.gardenWalk, 24, 24),
            .sportsGround: model(.sportsGround, 38, 34),
            .playground: model(.playground, 22, 22),
            .pocketPark: model(.pocketPark, 18, 20),
        ]
    }()

    /// The scenes a park of `area` square metres may get, the first that
    /// fits: a big park its pond or its sports ground (one or the other
    /// first, by `pick`), then the smaller ones.
    static func parkScenes(area: Double, pick: Float) -> [Map3DParkKit.Example] {
        if area >= bigPark { return pick < 0.5 ? [.gardenWalk, .sportsGround, .playground, .pocketPark] : [.sportsGround, .gardenWalk, .playground, .pocketPark] }
        if area >= middlingPark { return [.playground, .pocketPark] }
        return [.pocketPark]
    }

    /// Decision 331: in each of `map`'s parks, nearest the scene's middle
    /// first, one of the park kit's scenes: on the park's ground, on no
    /// cell in `cleared`, clear of track, platforms and roads, and
    /// ``parkSpacing`` from another; within ``parkTriangles``, and
    /// ``parkChunkTriangles`` a chunk. Returns the cells the scenes stand
    /// on, so no city lot goes there however little of a cell the park
    /// covers (review D, #990).
    @discardableResult
    mutating func addParks(_ map: Map3DBaseMap, clearOf cleared: Set<Map3DScene.ChunkKey>) -> Set<Map3DScene.ChunkKey> {
        let middle = point(x: (region.minX + region.maxX) / 2, y: (region.minY + region.maxY) / 2, height: 0)
        var parks: [(distance: Float, area: Double, centre: Map3DPoint, rings: [[Map3DPoint]], bounds: Map3DBaseMap.Bounds)] = []
        for area in map.areas where area.cover == .park {
            guard let outer = area.rings.first, outer.count >= 3 else { continue }
            let size = abs(Self.area(outer)) - area.rings.dropFirst().reduce(0) { $0 + abs(Self.area($1)) }
            guard size >= Double(Self.parkModels[.pocketPark]!.length * Self.parkModels[.pocketPark]!.width) else { continue }
            let rings = area.rings.map { $0.map { Map3DPoint(Float($0.x), 0, Float($0.z)) } }
            let centre = rings[0].reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(rings[0].count))
            parks.append(((centre - middle).length, size, centre, rings, area.bounds))
        }
        parks.sort { ($0.distance, $0.centre.x, $0.centre.z) < ($1.distance, $1.centre.x, $1.centre.z) }
        var placed: [Map3DPoint] = [], triangles = 0, chunkTriangles: [Map3DScene.ChunkKey: Int] = [:]
        var standing = Set<Map3DScene.ChunkKey>()
        for park in parks {
            guard !placed.contains(where: { ($0 - park.centre).length < Self.parkSpacing }) else { continue }
            // Seeded from where the park is on the map, not in the scene:
            // the scene's origin moves with the camera, and the park's
            // scene must not (review D, #990).
            let east = originX / Self.metre + Double(park.centre.x), south = originY / Self.metre + Double(park.centre.z)
            let pick = map3DRandom(Int32(truncatingIfNeeded: Int(east.rounded())), Int32(truncatingIfNeeded: Int(south.rounded())), salt: 31)
            spots: for spot in Self.parkSpots(park.rings[0], bounds: park.bounds, centre: park.centre) {
                guard !placed.contains(where: { ($0 - spot).length < Self.parkSpacing }) else { continue }
                for example in Self.parkScenes(area: park.area, pick: pick) {
                    guard let model = Self.parkModels[example], triangles + model.triangles <= Self.parkTriangles else { continue }
                    let centre = spot
                    let chunk = key(of: centre)
                    guard chunkTriangles[chunk, default: 0] + model.triangles <= Self.parkChunkTriangles else { continue }
                    for facing in Self.templeFacings {
                        let footprint = Self.parkFootprint(model, centre: centre, facing: facing)
                        guard footprint.allSatisfy({ Self.within($0, park.bounds) && Self.inside($0, park.rings) }),
                              Self.inside(centre, park.rings), cleared.isDisjoint(with: cells(under: footprint)), !onPlacedGround(footprint),
                              isClear(footprint, facing: facing) else { continue }
                        let ground = footprint.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
                        let foot = Map3DPoint(centre.x, ground + Self.lift(of: .park), centre.z)
                        target = .close
                        mesh(at: centre) { $0.append(model.mesh, at: foot, forward: facing) }
                        target = .base
                        placed.append(centre)
                        standing.formUnion(cells(under: footprint))
                        triangles += model.triangles
                        chunkTriangles[chunk, default: 0] += model.triangles
                        break spots
                    }
                }
            }
        }
        return standing
    }

    /// Where in a park to try a scene, in turn: the middle of its outline,
    /// then a 24 m grid over the part of it in `bounds`, nearest that
    /// middle first; at most 40.
    static func parkSpots(_ outer: [Map3DPoint], bounds: Map3DBaseMap.Bounds, centre: Map3DPoint) -> [Map3DPoint] {
        let step: Float = 24
        let low = (x: max(Float(bounds.minX), outer.map(\.x).min()!), z: max(Float(bounds.minZ), outer.map(\.z).min()!))
        let high = (x: min(Float(bounds.maxX), outer.map(\.x).max()!), z: min(Float(bounds.maxZ), outer.map(\.z).max()!))
        guard low.x < high.x, low.z < high.z else { return [] }
        var spots: [Map3DPoint] = []
        var z = low.z + step / 2
        while z < high.z {
            var x = low.x + step / 2
            while x < high.x {
                spots.append(Map3DPoint(x, 0, z))
                x += step
            }
            z += step
        }
        spots.sort { (($0 - centre).length, $0.x, $0.z) < (($1 - centre).length, $1.x, $1.z) }
        return Array(([centre] + spots).prefix(40))
    }

    /// Whether `point` lies in `bounds` (in x and z).
    static func within(_ point: Map3DPoint, _ bounds: Map3DBaseMap.Bounds) -> Bool {
        Double(point.x) >= bounds.minX && Double(point.x) <= bounds.maxX && Double(point.z) >= bounds.minZ && Double(point.z) <= bounds.maxZ
    }

    /// The corners of the ground a park scene `model` on `centre` facing
    /// `facing` takes, in ``isClear(_:facing:)``'s order.
    static func parkFootprint(_ model: ParkModel, centre: Map3DPoint, facing: Map3DPoint) -> [Map3DPoint] {
        let side = facing.cross(.up), back = centre - facing * (model.length / 2), out = centre + facing * (model.length / 2)
        let half = model.width / 2
        return [back - side * half, back + side * half, out + side * half, out - side * half]
    }
}
