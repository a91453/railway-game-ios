import Foundation

/// Isolated exterior study. No station catalog or live-map lookup calls this type.
public enum Map3DStationExteriorBatch1 {
    public enum LevelOfDetail: Sendable { case near, far }
    public enum Station: String, CaseIterable, Sendable { case taichungTRA = "tra-taichung", hsinchuTRA = "tra-hsinchu", hualienTRA = "tra-hualien" }

    public static func model(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        switch station {
        case .taichungTRA: builder.taichungExteriorStudy(detail: detail)
        case .hsinchuTRA: builder.hsinchuExteriorStudy(detail: detail)
        case .hualienTRA: builder.hualienExteriorStudy(detail: detail)
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
    // OSM way 293504390: 16 vertices, height=9, levels=2; no roof or tower part tags.
    // Metres east/north from (120.97165154, 24.80160443); © OpenStreetMap contributors, ODbL 1.0.
    static let hsinchuFootprint: [(Float, Float)] = [
        (-57.772, -45.737),
        (-59.185, -43.625),
        (-66.059, -33.417),
        (-45.387, -20.285),
        (-27.409, -8.620),
        (-13.449, 0.386),
        (4.366, 11.873),
        (15.470, 19.401),
        (50.485, 42.085),
        (57.087, 34.179),
        (59.994, 36.047),
        (61.720, 33.044),
        (63.335, 30.242),
        (4.669, -6.563),
        (-10.401, -16.015),
        (-37.463, -32.994)
    ]

    // Hualien complex: OSM ways from osmtoday Taiwan PBF, downloaded 2026-11-06.
    // Metres east/north from (121.60093265, 23.992764); © OpenStreetMap contributors, ODbL 1.0.
    static let frontHallFootprint: [(Float, Float)] = [ // OSM way 132937553
        (47.091, -13.610),
        (54.842, 3.681),
        (42.692, 9.129),
        (22.974, -34.804),
        (8.792, -66.395),
        (12.856, -68.218),
        (10.733, -72.944),
        (21.135, -77.603),
        (23.258, -72.877),
        (24.640, -73.500),
        (27.556, -67.017),
        (28.561, -67.473),
        (31.192, -61.624),
        (30.177, -61.168),
        (33.316, -54.185),
        (34.321, -54.630),
        (36.800, -49.126),
        (35.794, -48.670),
        (40.366, -38.473),
        (41.371, -38.929),
        (43.708, -33.737),
        (42.702, -33.281),
        (47.741, -22.039),
        (48.757, -22.495),
        (51.520, -16.323),
        (50.514, -15.879),
        (50.789, -15.267),
        (49.976, -14.900)
    ]
    static let rearHallFootprint: [(Float, Float)] = [ // OSM way 132937567
        (-73.829, 122.059),
        (-79.355, 109.727),
        (-88.732, 88.845),
        (-92.277, 90.435),
        (-93.222, 88.311),
        (-97.011, 90.012),
        (-109.862, 95.783),
        (-103.705, 109.494),
        (-104.752, 109.961),
        (-97.742, 125.595),
        (-94.512, 132.778),
        (-90.743, 141.173),
        (-89.686, 140.706),
        (-84.312, 152.693),
        (-70.578, 146.522),
        (-67.672, 145.221),
        (-68.465, 143.475),
        (-65.956, 142.352),
        (-64.919, 141.885),
        (-67.358, 136.459),
        (-70.852, 128.686)
    ]
    static let ticketHallFootprint: [(Float, Float)] = [ // OSM way 554768913
        (92.094, 93.204),
        (95.721, 91.569),
        (95.071, 90.112),
        (98.423, 88.611),
        (90.591, 71.165),
        (109.862, 62.514),
        (104.884, 51.417),
        (101.968, 44.923),
        (101.176, 45.279),
        (99.205, 46.168),
        (98.291, 44.144),
        (77.252, 53.585),
        (74.692, 47.881),
        (72.081, 42.076),
        (68.709, 43.588),
        (59.931, 47.536),
        (62.542, 53.340),
        (58.580, 55.119),
        (62.918, 64.793),
        (64.188, 67.607),
        (58.519, 70.153),
        (63.243, 80.683),
        (68.912, 78.137),
        (69.217, 78.804),
        (73.178, 77.025),
        (81.915, 96.495),
        (82.392, 97.562)
    ]
    static let crossHallFootprint: [(Float, Float)] = [ // OSM way 554768918
        (-66.819, 104.101),
        (-70.151, 105.591),
        (-79.355, 109.727),
        (-73.829, 122.059),
        (-54.862, 113.541),
        (-53.460, 114.553),
        (-3.794, 92.258),
        (18.433, 85.587),
        (21.044, 84.808),
        (28.053, 82.707),
        (34.626, 80.728),
        (35.591, 80.438),
        (44.043, 76.647),
        (57.646, 70.542),
        (58.519, 70.153),
        (64.188, 67.607),
        (62.918, 64.793),
        (58.580, 55.119),
        (62.542, 53.340),
        (59.931, 47.536),
        (59.495, 46.546),
        (49.722, 24.774),
        (39.218, 29.489),
        (25.615, 35.594),
        (16.249, 39.797),
        (10.042, 42.588),
        (1.976, 45.545),
        (10.022, 68.752),
        (-54.425, 97.685),
        (-61.943, 101.577)
    ]
    static let welcomeUmbrellaFootprint: [(Float, Float)] = [ // OSM way 718223887
        (98.291, 44.144),
        (103.167, 41.954),
        (94.725, 23.140),
        (96.513, 22.339),
        (74.794, -26.042),
        (73.006, -25.241),
        (54.009, -16.713),
        (50.789, -15.267),
        (49.976, -14.900),
        (47.091, -13.610),
        (54.842, 3.681),
        (72.081, 42.076),
        (74.692, 47.881),
        (77.252, 53.585)
    ]
    static let platformNorthFootprint: [(Float, Float)] = [ // OSM way 1342634750
        (-54.050, -141.874),
        (-62.095, -137.737),
        (11.576, 29.378),
        (16.249, 39.797),
        (25.615, 35.594)
    ]
    static let platformMiddleFootprint: [(Float, Float)] = [ // OSM way 1342634751
        (-69.623, -134.880),
        (-77.008, -130.954),
        (-23.177, -5.260),
        (1.976, 45.545),
        (10.042, 42.588)
    ]
    static let platformSouthFootprint: [(Float, Float)] = [ // OSM way 1352337182
        (-29.953, -152.693),
        (-40.447, -147.978),
        (39.218, 29.489),
        (49.722, 24.774),
        (42.692, 9.129),
        (22.974, -34.804),
        (8.792, -66.395),
        (2.839, -79.660),
        (-14.380, -118.011)
    ]

}

private extension StationKitBuilder {
    mutating func footprint(_ points: [(Float, Float)], color: UInt32, baseY: Float = 0, height: Float = 0.32) {
        guard points.count >= 3 else { return }
        // A shallow closed plinth carries the surveyed ground outline.
        let p = points.map { Map3DPoint($0.0, baseY + height, $0.1) }
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
                if baseY > 0 {
                    let underside = [a, b, c].map { Map3DPoint(points[$0].0, baseY, points[$0].1) }
                    mesh.addFacet(sign > 0 ? underside : underside.reversed(), color: color)
                }
                remaining.remove(at: k)
                clipped = true
                break
            }
            if !clipped { break }
        }
        for i in points.indices {
            let j = (i + 1) % points.count
            let a = p[i], b = p[j]
            face([a, b, Map3DPoint(b.x, baseY, b.z), Map3DPoint(a.x, baseY, a.z)], inside: .zero, color: color)
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
        add(.flat(named: "hall", from: hall.mesh), at: Map3DPoint(18, 0, -24), angle: 20.9529 * .pi / 180)

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
        add(.flat(named: "old-station", from: old.mesh), at: Map3DPoint(-147.5, 0, -45.7), angle: 23.4326 * .pi / 180)
    }

    mutating func hsinchuExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        footprint(Map3DStationExteriorBatch1.hsinchuFootprint, color: Map3DPalette.stone)
        let wall = Map3DColor.rgb(0xE5D8C3)
        let trim = Map3DColor.rgb(0xF1EADD)
        let brick = Map3DColor.rgb(0xC79C89)
        let roof = Map3DColor.rgb(0x899780)
        let glass = Map3DColor.rgb(0xAFC7CD)
        var station = StationKitBuilder()
        // OSM's 9 m is used for the two-level wing. Roof ridge and clock tower
        // are estimates from photos because the way has no building:part tags.
        station.box(0, 0.32, 0, 139, 15.2, 8.68, wall)
        station.hip(0, 9, 0, 142, 16.2, 2.0, roof)
        // The broad raised central roof and its pale Baroque entrance.
        station.box(0, 0.32, -8.0, 22, 3.2, 11.2, wall)
        station.gable(0, 11.52, -8.0, 23.0, 4.3, 2.0, trim)
        station.hip(0, 9.72, 0, 54, 19.5, 3.2, roof)
        station.box(0, 1.2, -9.68, 8, 0.2, 7.2, glass)
        station.box(0, 8.4, -9.78, 14, 0.35, 0.8, trim)
        station.box(0, 0.32, -9.62, 22, 0.5, 1.0, brick)
        // Clock tower is separate from the measured OSM height.
        station.box(0, 11.4, 0, 7.2, 7.2, 6.3, wall)
        station.hip(0, 17.7, 0, 8, 8, 2.0, roof)
        station.box(0, 19.7, 0, 0.35, 0.35, 1.2, StationKitBuilder.steel)
        station.clockFace(0, 14.0, -3.73, size: 2.2)
        if detail == .near {
            for x in stride(from: Float(-63), through: 63, by: 8) {
                if abs(x) < 19 { continue }
                station.box(x, 1.6, -7.74, 3.6, 0.16, 4.4, trim)
                station.box(x, 2.0, -7.84, 2.9, 0.18, 3.7, glass)
                station.box(x, 6.1, -7.82, 4.8, 0.35, 0.55, trim)
            }
            for x in stride(from: Float(-66), through: 66, by: 11) {
                station.box(x, 0.32, -10.2, 0.35, 0.35, 4.5, trim)
            }
            station.box(0, 4.7, -10.2, 137, 2.8, 0.25, roof)
            for x: Float in [-17, 17] {
                station.box(x, 0.32, -7.8, 0.8, 0.8, 9.4, trim)
                station.box(x, 8.8, -8.0, 1.3, 1.3, 0.5, brick)
            }
        } else {
            for x in stride(from: Float(-56), through: 56, by: 16) {
                if abs(x) < 19 { continue }
                station.box(x, 2.1, -7.75, 5, 0.2, 3.7, glass)
            }
            station.box(0, 4.7, -9.5, 136, 1.5, 0.22, roof)
        }
        // OSM's minimum-area rectangle long axis bears 32.2° north of east.
        add(.flat(named: "hsinchu-station", from: station.mesh), at: .zero, angle: 32.2 * .pi / 180)
    }

    mutating func hualienExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let paleRoof = Map3DColor.rgb(0xE8E6DE)
        let warmWall = Map3DColor.rgb(0xDDD8CB)
        let rib = Map3DColor.rgb(0xC1B19A)
        let concrete = Map3DColor.rgb(0xB9B9B3)
        let darkRoof = Map3DColor.rgb(0x858B89)
        let glass = Map3DColor.rgb(0x9BB7B9)
        let wayOutlines: [[(Float, Float)]] = [
            Map3DStationExteriorBatch1.crossHallFootprint,
            Map3DStationExteriorBatch1.ticketHallFootprint,
            Map3DStationExteriorBatch1.welcomeUmbrellaFootprint,
            Map3DStationExteriorBatch1.frontHallFootprint,
            Map3DStationExteriorBatch1.rearHallFootprint
        ]
        for outline in wayOutlines { footprint(outline, color: concrete) }
        for outline in [Map3DStationExteriorBatch1.platformNorthFootprint,
                        Map3DStationExteriorBatch1.platformMiddleFootprint,
                        Map3DStationExteriorBatch1.platformSouthFootprint] {
            footprint(outline, color: paleRoof, baseY: 5.6, height: 0.36)
        }

        // The cross-station gallery sits above the tracks. OSM has three levels,
        // but no height; 6 m underside and 17 m roof are reference-display estimates.
        var bridge = StationKitBuilder()
        bridge.box(0, 6, 0, 147, 38, 9.8, glass)
        bridge.box(0, 15.8, 0, 153, 45, 1.2, paleRoof)
        bridge.box(0, 6, 0, 147, 38, 0.5, warmWall)
        for z: Float in [-18.8, 18.8] {
            bridge.box(0, 7.1, z, 147, 0.35, 0.7, warmWall)
            bridge.box(0, 11.7, z, 147, 0.35, 0.55, warmWall)
        }
        if detail == .near {
            for x in stride(from: Float(-68), through: 68, by: 9) {
                for z: Float in [-18.9, 18.9] { bridge.box(x, 6.4, z, 0.4, 0.45, 9.0, warmWall) }
            }
        } else {
            for x in stride(from: Float(-60), through: 60, by: 20) {
                for z: Float in [-18.9, 18.9] { bridge.box(x, 6.4, z, 0.55, 0.55, 9.0, warmWall) }
            }
        }
        add(.flat(named: "hualien-cross-gallery", from: bridge.mesh),
            at: Map3DPoint(-10.83, 0, 76.06), angle: -23.8166 * .pi / 180)

        // Ticket hall at the east end, with the vertical screen seen in east photos.
        var ticket = StationKitBuilder()
        ticket.box(0, 0.32, 0, 51, 46, 9.7, warmWall)
        ticket.box(0, 10.02, 0, 54, 50, 1.1, paleRoof)
        ticket.box(0, 1.4, -23.13, 43, 0.25, 7.8, glass)
        let screenStep: Float = detail == .near ? 3.3 : 8.2
        for x in stride(from: Float(-23), through: 23, by: screenStep) {
            ticket.box(x, 0.32, -23.45, 0.8, 0.85, 10.4, paleRoof)
        }
        add(.flat(named: "hualien-ticket-hall", from: ticket.mesh),
            at: Map3DPoint(84.52, 0, 66.63), angle: 65.8392 * .pi / 180)

        // The huge welcome canopy is a shallow waved shell. Its roof polygon is
        // surveyed; scallops, timber ribs, support heights and curvature are estimates.
        footprint(Map3DStationExteriorBatch1.welcomeUmbrellaFootprint,
                  color: rib, baseY: 10.0, height: 0.35)
        var umbrella = StationKitBuilder()
        for (index, x) in stride(from: Float(-29), through: 29, by: 14.5).enumerated() {
            let edgeHeight: Float = index.isMultiple(of: 2) ? 11.0 : 12.0
            umbrella.canopy(x, edgeHeight, 0, length: 15.5, width: 28.5, rise: 1.8, color: paleRoof)
            umbrella.box(x, 0.32, 0, 0.7, 0.7, 10.98, rib)
            umbrella.box(x, 9.2, 0, 0.8, 27.2, 0.28, rib)
        }
        if detail == .near {
            for x in stride(from: Float(-32), through: 32, by: 3.6) {
                umbrella.box(x, 11.42, 0, 0.24, 27.5, 0.2, rib)
            }
            for z in stride(from: Float(-12), through: 12, by: 4) {
                umbrella.box(0, 11.4, z, 70, 0.25, 0.2, rib)
            }
        }
        add(.flat(named: "hualien-welcome-canopy", from: umbrella.mesh),
            at: Map3DPoint(76.09, 0, 13.77), angle: 65.8235 * .pi / 180)

        // Lower front and rear station halls use the OSM ground outlines. Both
        // heights and roof forms are visual estimates because tags omit them.
        var front = StationKitBuilder()
        front.box(0, 0.32, 0, 84, 17.5, 8.2, concrete)
        front.box(0, 8.52, 0, 88, 19, 0.5, darkRoof)
        front.box(0, 1.1, -8.9, 80, 0.2, 5.7, glass)
        for x in stride(from: Float(-37), through: 37, by: detail == .near ? 7.5 : 15) {
            front.box(x, 1.1, -9.05, 0.5, 0.35, 6.0, paleRoof)
        }
        front.box(0, 5.0, -10.5, 84, 3.2, 0.5, darkRoof)
        add(.flat(named: "hualien-front-hall", from: front.mesh),
            at: Map3DPoint(33.13, 0, -34.78), angle: 65.8284 * .pi / 180)

        var rear = StationKitBuilder()
        rear.box(0, 0.32, 0, 59, 21, 7.8, concrete)
        rear.box(0, 8.12, 0, 62, 23, 0.8, darkRoof)
        rear.box(0, 1.0, -10.6, 56, 0.2, 5.2, glass)
        for x in stride(from: Float(-26), through: 26, by: detail == .near ? 6.5 : 13) {
            rear.box(x, 1.0, -10.76, 0.5, 0.3, 5.4, paleRoof)
        }
        add(.flat(named: "hualien-rear-hall", from: rear.mesh),
            at: Map3DPoint(-87.68, 0, 119.95), angle: 65.8233 * .pi / 180)

        let platforms: [(Float, Float, Float)] = [(-18.91, -51.04, 65.8318),
                                                   (-34.70, -43.95, 65.8247),
                                                   (4.65, -61.65, 65.8247)]
        for (east, north, rotation) in platforms {
            var columns = StationKitBuilder()
            for x in stride(from: Float(-87), through: 87, by: detail == .near ? 15 : 35) {
                columns.box(x, 0.32, 0, 0.55, 0.55, 5.28, rib)
                if detail == .near { columns.box(x, 5.15, 0, 0.28, 9.0, 0.3, rib) }
            }
            add(.flat(named: "hualien-platform-columns", from: columns.mesh),
                at: Map3DPoint(east, 0, north), angle: rotation * .pi / 180)
        }
    }
}
