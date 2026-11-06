import Foundation

/// Isolated exterior study. No station catalog or live-map lookup calls this type.
public enum Map3DStationExteriorBatch1 {
    public enum LevelOfDetail: Sendable { case near, far }
    public enum Station: String, CaseIterable, Sendable { case taichungTRA = "tra-taichung" }

    public static func model(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        switch station {
        case .taichungTRA: builder.taichungExteriorStudy(detail: detail)
        }
        return .flat(named: "station-exterior-study-\(station.rawValue)-\(detail == .near ? "near" : "far")", from: builder.mesh)
    }

    // OSM ways 442234244 and 223056023, osmtoday Taiwan extract 2026-11-06.
    // Metres east/north from (120.68671829, 24.13732601); © OpenStreetMap contributors, ODbL 1.0.
    static let mainFootprint: [(Float, Float)] = [
        (137.202, 13.654),
        (126.122, 8.250),
        (110.584, 0.655),
        (93.289, -7.785),
        (54.272, -27.411),
        (55.237, -37.885),
        (-1.532, -63.716),
        (-2.639, -61.047),
        (-3.492, -57.600),
        (-42.977, -74.357),
        (-83.640, -91.604),
        (-128.791, -108.450),
        (-127.562, -78.527),
        (-107.647, -69.098),
        (-26.901, -30.858),
        (-30.963, -20.806),
        (-31.379, -19.905),
        (-33.207, -15.991),
        (-38.082, -5.505),
        (-69.219, -6.317),
        (-68.599, 4.580),
        (-72.540, 13.665),
        (-79.181, 28.987),
        (-57.378, 32.657),
        (-58.677, 34.080),
        (-45.018, 39.306),
        (-44.582, 40.841),
        (-42.683, 44.521),
        (-38.123, 46.979),
        (-32.801, 49.458),
        (-28.902, 51.282),
        (-21.346, 54.963),
        (-20.767, 55.140),
        (-18.919, 55.685),
        (-5.483, 56.475),
        (-1.441, 55.941),
        (7.404, 54.774),
        (21.084, 20.603),
        (25.187, 10.362),
        (26.720, 6.526),
        (27.380, 4.880),
        (147.632, 59.288),
        (150.963, 42.464),
        (151.846, 37.850),
        (149.297, 31.478)
    ]
    static let oldFootprint: [(Float, Float)] = [
        (-176.959, -50.406),
        (-171.089, -63.938),
        (-148.381, -54.109),
        (-142.856, -51.718),
        (-139.607, -50.306),
        (-137.372, -49.305),
        (-117.935, -40.921),
        (-123.805, -27.388),
        (-143.141, -35.761),
        (-149.051, -38.319),
        (-154.586, -40.721)
    ]
}

private extension StationKitBuilder {
    mutating func footprint(_ points: [(Float, Float)], color: UInt32) {
        guard points.count >= 3 else { return }
        // A shallow closed plinth carries the surveyed ground outline.
        let p = points.map { Map3DPoint($0.0, 0.32, $0.1) }
        var remaining = Array(p.indices)
        let area = points.indices.reduce(Float(0)) { total, i in
            let j = (i + 1) % points.count
            return total + points[i].0 * points[j].1 - points[j].0 * points[i].1
        }
        let sign: Float = area >= 0 ? 1 : -1
        var guardCount = 0
        while remaining.count > 2 && guardCount < points.count * points.count {
            guardCount += 1
            var clipped = false
            for k in remaining.indices {
                let a = remaining[(k + remaining.count - 1) % remaining.count]
                let b = remaining[k]
                let c = remaining[(k + 1) % remaining.count]
                let ax = points[a].0, az = points[a].1
                let bx = points[b].0, bz = points[b].1
                let cx = points[c].0, cz = points[c].1
                let cross = (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
                if cross * sign <= 0.0001 { continue }
                let contains = remaining.contains { q in
                    if q == a || q == b || q == c { return false }
                    let x = points[q].0, z = points[q].1
                    let u = ((bx - ax) * (z - az) - (bz - az) * (x - ax)) * sign
                    let v = ((cx - bx) * (z - bz) - (cz - bz) * (x - bx)) * sign
                    let w = ((ax - cx) * (z - cz) - (az - cz) * (x - cx)) * sign
                    return u >= -0.0001 && v >= -0.0001 && w >= -0.0001
                }
                if contains { continue }
                mesh.addFacet(sign > 0 ? [p[c], p[b], p[a]] : [p[a], p[b], p[c]], color: color)
                remaining.remove(at: k)
                clipped = true
                break
            }
            if !clipped { break }
        }
        for i in points.indices {
            let j = (i + 1) % points.count
            let a = p[i], b = p[j]
            face([a, b, Map3DPoint(b.x, 0, b.z), Map3DPoint(a.x, 0, a.z)], inside: .zero, color: color)
        }
    }

    mutating func taichungExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        footprint(Map3DStationExteriorBatch1.mainFootprint, color: Map3DPalette.concrete)
        footprint(Map3DStationExteriorBatch1.oldFootprint, color: Map3DPalette.brick)
        let paleRoof: UInt32 = Map3DColor.rgb(0xE5E7E2)
        let warmWall: UInt32 = Map3DColor.rgb(0xEEE7DA)
        let darkRoof: UInt32 = Map3DColor.rgb(0x90979E)
        let brick: UInt32 = Map3DColor.rgb(0xC79C89)
        // New elevated hall: OSM width/depth and height 318.276 × 118.043 × 37 m.
        // Roof curvature, column rhythm and platform elevation are visual estimates.
        var hall = StationKitBuilder()
        hall.box(0, 0.32, 0, 243, 65, 11.7, warmWall)
        hall.box(0, 12.02, 0, 242, 65, 1.1, Map3DPalette.concrete)
        hall.canopy(0, 27.8, 0, length: 250, width: 75, rise: 9.2, color: paleRoof)
        hall.box(0, 12.9, 0, 239, 0.55, 14.5, StationKitBuilder.glass)
        if detail == .near {
            for x in stride(from: Float(-112), through: 112, by: 16) {
                for z: Float in [-31, 31] { hall.box(x, 0.32, z, 0.75, 0.75, 27.0, StationKitBuilder.white) }
                hall.box(x, 13.1, 0, 0.35, 64, 0.25, StationKitBuilder.white)
            }
            for z in stride(from: Float(-27), through: 27, by: 15) {
                hall.box(119.5, 2.0, z, 0.18, 10, 7.5, StationKitBuilder.glass)
            }
        } else {
            for x in stride(from: Float(-105), through: 105, by: 34) {
                for z: Float in [-31, 31] { hall.box(x, 0.32, z, 0.9, 0.9, 27.0, StationKitBuilder.white) }
            }
        }
        // Reference OSM minimum rotated rectangle is 20.9529° east/north.
        add(.flat(named: "hall", from: hall.mesh), at: Map3DPoint(18, 0, -24), angle: -20.9529 * .pi / 180)

        // Former station: brick Baroque body, hipped roof, central clock tower.
        // OSM records two levels and roof:shape=hipped; 13 m total is estimated.
        var old = StationKitBuilder()
        old.box(0, 0.32, 0, 57.2, 14.2, 8.8, brick)
        old.hip(0, 9.12, 0, 57.949, 14.772, 2.1, darkRoof)
        old.box(0, 0.32, -7.3, 12, 2.0, 10.5, brick)
        old.box(0, 8.8, 0, 8, 8, 2.4, brick)
        old.gable(0, 10.9, -7.3, 12.5, 4.0, 2.0, darkRoof)
        old.box(0, 2.0, -8.45, 5.5, 0.15, 7.9, StationKitBuilder.glass)
        old.hip(0, 11.2, 0, 8.5, 8.5, 1.8, darkRoof)
        if detail == .near {
            for x in stride(from: Float(-24), through: 24, by: 8) {
                if abs(x) < 4 { continue }
                old.box(x, 2.2, -7.18, 3.2, 0.15, 3.8, warmWall)
                old.box(x, 2.5, -7.30, 2.5, 0.16, 3.1, StationKitBuilder.glass)
            }
            old.clockFace(0, 9.45, -4.33, size: 2.0)
        } else {
            old.clockFace(0, 9.45, -4.33, size: 1.8)
        }
        add(.flat(named: "old-station", from: old.mesh), at: Map3DPoint(-147.5, 0, -45.7), angle: -23.4326 * .pi / 180)
    }
}
