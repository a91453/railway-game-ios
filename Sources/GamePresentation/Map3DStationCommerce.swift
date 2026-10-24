import Foundation
import GameCore

// Decision 331: the commercial kit's four scenes (#946's
// `Map3DCommercialKit`, used as they are) in front of the big city
// stations: Taipei, Taichung, Kaohsiung and the other city and high-speed
// rail stations, which keep no decision 322 shop street. A transit hub
// across the forecourt, a commercial avenue and a retail corner beside
// it, a night market alley behind them, each where it is clear of track,
// platforms, roads, station buildings and what already stands. Close up
// only: from farther, the station square it stands on.

extension Map3DScene.Builder {
    /// Close up, the most triangles a scene's commercial scenes may have:
    /// past them, the stations later in the scene's list get none.
    static let commerceTriangles = 40_000

    /// Whether `station` is a big city station: one of the station kit's
    /// city or high-speed rail buildings.
    static func isBig(_ station: Map3DStationKit.Station) -> Bool {
        switch station.profile {
        case .taipei, .taichung, .kaohsiung, .hsinchu, .tainan, .chiayi, .keelung, .nangang, .banqiao, .hualien, .taitung, .zuoying,
             .hsrTaichung, .hsrTaoyuan, .hsrHsinchu, .hsrTainan:
            true
        default:
            false
        }
    }


    /// The kit's scenes, in the order a station takes them, each with the
    /// ground it takes: the middle of its mesh's bounds at the origin,
    /// signs and awnings included.
    static let commerceModels: [(example: Map3DCommercialKit.Example, model: ParkModel)] = {
        ([.stationTransitHub, .commercialAvenue, .neighborhoodRetailCorner, .nightMarketAlley] as [Map3DCommercialKit.Example]).map { example in
            var builder = StationKitBuilder()
            builder.add(Map3DCommercialKit.model(for: example), at: .zero)
            let mesh = builder.mesh, bounds = mesh.bounds
            let length = 2 * max(-(bounds?.min.x ?? 0), bounds?.max.x ?? 0), width = 2 * max(-(bounds?.min.z ?? 0), bounds?.max.z ?? 0)
            return (example, ParkModel(mesh: mesh, length: length, width: width))
        }
    }()

    /// The gap between a station's front and its scenes, and between two
    /// scenes, metres.
    static let commerceGap: Float = 8

    /// Where a station's scenes may stand, in turn: the middle of each,
    /// facing the station. Across its forecourt; beside that, right and
    /// left; then a row farther out.
    static func commerceSlots(centre: Map3DPoint, forward: Map3DPoint, depth: Float) -> [Map3DPoint] {
        let right = forward.cross(.up), pitch: Float = 44 + commerceGap
        let first = centre + forward * (depth / 2 + commerceGap + 22)
        var slots: [Map3DPoint] = []
        for row in 0..<2 {
            let middle = first + forward * (pitch * Float(row))
            slots += [middle, middle + right * pitch, middle - right * pitch]
        }
        return slots
    }

    /// Decision 331: each big station's commercial scenes, each kind once,
    /// on no cell in `cleared`, over no station building or other scene,
    /// clear of track, platforms and roads; within ``commerceTriangles``.
    /// Returns the 64 m cells they stand on, which keep no city lot.
    mutating func addStationCommerce(clearOf cleared: Set<Map3DScene.ChunkKey>) -> Set<Map3DScene.ChunkKey> {
        var taken = Set<Map3DScene.ChunkKey>(), placed: [[Map3DPoint]] = [], triangles = 0
        for station in bigStations {
            let facing = station.forward * -1
            var free = Self.commerceSlots(centre: station.centre, forward: station.forward, depth: station.depth)
            for (_, model) in Self.commerceModels where triangles + model.triangles <= Self.commerceTriangles {
                for (index, slot) in free.enumerated() {
                    let footprint = Self.parkFootprint(model, centre: slot, facing: facing)
                    let cells = cells(under: footprint)
                    guard cleared.isDisjoint(with: cells), !Self.overlaps(footprint, houseFootprints + placed), !onPlacedGround(footprint),
                          isClear(footprint, facing: facing) else { continue }
                    let foot = Map3DPoint(slot.x, footprint.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, slot.z)
                    target = .close
                    mesh(at: slot) { $0.append(model.mesh, at: foot, forward: facing) }
                    target = .base
                    taken.formUnion(cells)
                    placed.append(footprint)
                    triangles += model.triangles
                    free.remove(at: index)
                    break
                }
            }
        }
        return taken
    }

    /// Whether `footprint` and any of `others` overlap: a corner of either
    /// inside the other.
    static func overlaps(_ footprint: [Map3DPoint], _ others: [[Map3DPoint]]) -> Bool {
        others.contains { other in
            footprint.contains { inside($0, [other]) } || other.contains { inside($0, [footprint]) }
        }
    }
}
