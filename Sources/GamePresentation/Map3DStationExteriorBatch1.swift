import Foundation

/// Isolated exterior study. No station catalog or live-map lookup calls this type.
public enum Map3DStationExteriorBatch1 {
    public enum LevelOfDetail: Sendable { case near, far }
    public enum Station: String, CaseIterable, Sendable { case taichungTRA = "tra-taichung", hsinchuTRA = "tra-hsinchu", hualienTRA = "tra-hualien", taitungTRA = "tra-taitung", banqiaoTRA = "tra-banqiao", nangangTRA = "tra-nangang" }

    public static func model(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        switch station {
        case .taichungTRA: builder.taichungExteriorStudy(detail: detail)
        case .hsinchuTRA: builder.hsinchuExteriorStudy(detail: detail)
        case .hualienTRA: builder.hualienExteriorStudy(detail: detail)
        case .taitungTRA: builder.taitungExteriorStudy(detail: detail)
        case .banqiaoTRA: builder.banqiaoExteriorStudy(detail: detail)
        case .nangangTRA: builder.nangangExteriorStudy(detail: detail)
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

    // Taitung complex: OSM ways from osmtoday Taiwan PBF, downloaded 2026-11-06.
    // Metres east/north from (121.12276045, 22.79349185); © OpenStreetMap contributors, ODbL 1.0.
    static let taitungHallFootprint: [(Float, Float)] = [ // OSM way 386900387
        (19.083, 77.075),
        (42.855, 74.262),
        (41.245, 60.496),
        (39.523, 45.818),
        (38.252, 35.088),
        (36.796, 22.912),
        (35.167, 9.035),
        (33.783, -2.730),
        (32.635, -12.559),
        (8.811, -9.735),
        (11.363, 11.848),
        (15.730, 48.653),
    ]
    static let taitungPlatformAFootprint: [(Float, Float)] = [ // OSM way 386900423
        (-9.364, 105.474),
        (0.302, 104.329),
        (-26.484, -119.952),
        (-36.161, -118.795),
    ]
    static let taitungPlatformBFootprint: [(Float, Float)] = [ // OSM way 386900424
        (-52.583, -116.849),
        (-42.988, -117.995),
        (-14.675, 118.806),
        (-24.280, 119.952),
    ]
    static let taitungPlatformCFootprint: [(Float, Float)] = [ // OSM way 386900425
        (-59.851, -115.726),
        (-70.359, -114.470),
        (-43.419, 110.900),
        (-32.901, 109.644),
    ]
    static let taitungPorticoFootprint: [(Float, Float)] = [ // OSM way 724860888
        (41.932, 34.643),
        (40.477, 22.478),
        (37.412, -3.152),
        (35.987, -16.118),
        (39.749, -16.551),
        (59.728, -18.842),
        (70.359, 69.814),
        (53.526, 71.849),
        (46.463, 72.660),
        (44.977, 60.051),
    ]

    // Banqiao complex: OSM ways from osmtoday Taiwan PBF, downloaded 2026-11-06.
    // Metres east/north from (121.4640451, 25.0144511); © OpenStreetMap contributors, ODbL 1.0.
    static let banqiaoMainFootprint: [(Float, Float)] = [ // OSM way 232201616
        (-101.440, -47.035),
        (-76.974, -16.724),
        (-56.892, 8.740),
        (-33.716, 38.940),
        (-11.659, 67.673),
        (-0.947, 82.418),
        (30.189, 58.322),
        (41.697, 50.049),
        (62.787, 34.893),
        (71.442, 22.673),
        (74.737, 18.014),
        (76.178, 15.979),
        (78.889, 12.142),
        (85.892, 11.787),
        (90.799, 6.182),
        (89.469, 1.357),
        (86.497, -3.191),
        (80.894, -4.770),
        (75.110, -3.547),
        (60.580, -17.547),
        (27.146, -28.054),
        (-0.695, -46.969),
        (-3.688, -50.004),
        (-24.677, -71.298),
        (-28.436, -78.315),
        (-42.714, -104.912),
        (-50.765, -109.471),
        (-51.118, -114.019),
        (-53.395, -118.567),
        (-58.293, -120.847),
        (-63.895, -118.567),
        (-67.220, -114.542),
        (-78.466, -106.503),
        (-99.788, -91.258),
        (-92.734, -81.117),
        (-84.058, -68.618),
        (-79.473, -62.025),
    ]
    static let banqiaoCircularLineFootprint: [(Float, Float)] = [ // OSM way 818694787
        (98.558, 67.451),
        (99.425, 66.806),
        (82.940, 44.434),
        (81.841, 42.944),
        (8.515, 96.973),
        (26.108, 120.847),
        (49.355, 103.712),
        (52.257, 107.648),
        (78.073, 88.589),
        (75.191, 84.675),
        (91.132, 72.933),
        (94.004, 76.836),
        (101.440, 71.343),
    ]
    static let banqiaoTowerSouthFootprint: [(Float, Float)] = [ // OSM way 1491394339
        (-74.334, -12.854),
        (-38.805, -39.007),
        (-63.724, -72.866),
        (-99.254, -46.713),
    ]
    static let banqiaoTowerNorthFootprint: [(Float, Float)] = [ // OSM way 1491394340
        (-35.661, 47.369),
        (0.595, 22.228),
        (-23.367, -12.309),
        (-59.613, 12.821),
    ]

    // Nangang complex: OSM ways from osmtoday Taiwan PBF, downloaded 2026-11-06.
    // Metres east/north from (121.60664345, 25.0528905); © OpenStreetMap contributors, ODbL 1.0.
    static let nangangMainFootprint: [(Float, Float)] = [ // OSM way 233331393
        (-6.200, 67.651),
        (35.493, 75.535),
        (37.135, 67.529),
        (41.719, 68.363),
        (46.896, 77.292),
        (87.512, 84.186),
        (91.773, 60.079),
        (64.686, 55.964),
        (65.925, 48.214),
        (66.761, 42.999),
        (69.148, 27.309),
        (89.527, 31.146),
        (97.354, -7.094),
        (98.986, -15.045),
        (94.060, -15.912),
        (86.787, -17.180),
        (57.101, -22.361),
        (27.425, -27.543),
        (12.838, -30.067),
        (8.275, -30.890),
        (-4.185, -33.069),
        (-20.152, -35.849),
        (-14.289, -69.041),
        (-18.500, -69.819),
        (-98.804, -84.052),
        (-100.688, -73.934),
        (-105.946, -43.666),
        (-109.966, -20.193),
        (-113.451, -2.113),
        (-29.077, 12.965),
        (-26.256, -2.769),
        (-10.109, 0.356),
        (1.405, 2.580),
        (-2.020, 15.979),
        (33.831, 21.172),
        (31.535, 36.639),
        (30.507, 42.421),
        (29.601, 48.248),
        (-1.949, 43.533),
    ]
    static let nangangBlockCFootprint: [(Float, Float)] = [ // OSM way 410390808
        (-211.283, -30.290),
        (-207.536, -28.933),
        (-208.191, -24.307),
        (-208.624, -21.361),
        (-155.034, -13.721),
        (-153.281, -27.165),
        (-132.419, -23.796),
        (-123.958, -22.417),
        (-109.966, -20.193),
        (-105.946, -43.666),
        (-120.724, -45.890),
        (-129.165, -47.225),
        (-149.715, -50.483),
        (-148.809, -54.608),
        (-202.701, -62.547),
        (-203.195, -59.178),
        (-208.382, -58.455),
        (-212.875, -56.142),
        (-216.381, -52.495),
        (-218.526, -47.914),
        (-219.080, -42.832),
        (-217.942, -37.851),
        (-215.242, -33.514),
    ]
    static let nangangBlockBFootprint: [(Float, Float)] = [ // OSM way 411044008
        (-104.848, -46.624),
        (-111.598, -7.906),
        (-28.714, 6.716),
        (-21.874, -32.080),
    ]
    static let nangangEastFootprint: [(Float, Float)] = [ // OSM way 556511660
        (139.450, -3.736),
        (154.208, -1.201),
        (154.339, -3.025),
        (173.921, 0.400),
        (174.536, -1.601),
        (184.398, 0.022),
        (184.307, 2.213),
        (194.934, 4.070),
        (194.602, 5.560),
        (217.730, 9.374),
        (210.709, 50.316),
        (192.748, 47.603),
        (194.642, 36.650),
        (186.030, 34.704),
        (176.651, 30.668),
        (169.963, 26.131),
        (170.134, 23.673),
        (149.332, 20.393),
        (145.988, 22.762),
        (142.523, 24.441),
        (139.511, 24.496),
        (136.791, 23.273),
        (134.424, 21.071),
        (133.074, 18.536),
        (132.762, 15.323),
        (133.195, 13.299),
        (134.051, 11.475),
        (135.109, 9.985),
        (136.821, 8.807),
        (137.667, 8.162),
        (139.047, 0.200),
    ]
    static let nangangBlockAFootprint: [(Float, Float)] = [ // OSM way 908843920
        (15.055, 13.455),
        (69.259, 23.195),
        (71.455, 11.008),
        (77.036, 12.009),
        (78.839, 2.046),
        (72.795, 0.956),
        (75.011, -11.364),
        (21.260, -21.027),
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

    mutating func taitungExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let arcRoof = Map3DColor.rgb(0xDCE8E6)
        let tiledWall = Map3DColor.rgb(0xD9D0CC)
        let columns = Map3DColor.rgb(0xC6D2CF)
        let platformRoof = Map3DColor.rgb(0xADBDBD)
        let glass = Map3DColor.rgb(0x8CACB1)
        let darkRoof = Map3DColor.rgb(0x768E90)
        let brick = Map3DColor.rgb(0xBA9F92)
        // OSM has a train-station way, a separate elevated front roof way,
        // and three platform roof ways. None carries height or roof tags.
        footprint(Map3DStationExteriorBatch1.taitungHallFootprint, color: tiledWall)
        footprint(Map3DStationExteriorBatch1.taitungPorticoFootprint,
                  color: platformRoof, baseY: 5.6, height: 0.32)
        for outline in [Map3DStationExteriorBatch1.taitungPlatformAFootprint,
                        Map3DStationExteriorBatch1.taitungPlatformBFootprint,
                        Map3DStationExteriorBatch1.taitungPlatformCFootprint] {
            footprint(outline, color: platformRoof, baseY: 5.3, height: 0.32)
        }

        // The hall's low, tiled rear wall and broad glass entrance are based on
        // photographs. 13.5 m total is the reference's illustrative height.
        var hall = StationKitBuilder()
        hall.box(0, 0.32, 0, 85, 22.8, 12.3, tiledWall)
        hall.box(0, 12.62, 0, 87.5, 24, 0.88, platformRoof)
        hall.box(0, 1.0, -11.56, 76, 0.22, 5.6, glass)
        hall.box(0, 1.0, -11.82, 17, 0.3, 7.0, darkRoof)
        hall.box(0, 8.15, -12.0, 20, 0.3, 0.65, brick)
        for x in stride(from: Float(-37), through: 37, by: detail == .near ? 7.5 : 15) {
            hall.box(x, 1.0, -11.75, 0.55, 0.3, 6.4, columns)
        }
        add(.flat(named: "taitung-hall", from: hall.mesh),
            at: Map3DPoint(25.86, 0, 32.26), angle: 83.2552 * .pi / 180)

        // Two rows of shallow vaults reproduce the station's characteristic
        // front profile. Vault curvature, rhythm and height are estimates.
        var portico = StationKitBuilder()
        let pitch: Float = detail == .near ? 10.5 : 18.0
        let span: Float = detail == .near ? 11.1 : 18.8
        for x in stride(from: Float(-38), through: 38, by: pitch) {
            for (z, edgeHeight) in [(Float(-5.75), Float(6.6)), (Float(5.75), Float(9.5))] {
                var vault = StationKitBuilder()
                vault.canopy(0, 0, 0, length: 12.0, width: span,
                             rise: detail == .near ? 1.8 : 1.65, color: arcRoof)
                portico.add(.flat(named: "taitung-vault", from: vault.mesh),
                            at: Map3DPoint(x, edgeHeight, z), angle: Float.pi / 2)
            }
            for z: Float in [-10.5, 0.0, 10.5] {
                portico.box(x, 0.32, z, 0.65, 0.65, z == -10.5 ? 6.28 : 9.18, columns)
                if detail == .near {
                    portico.box(x, 5.8, z, 0.3, 3.7, 0.28, darkRoof)
                }
            }
        }
        portico.box(0, 0.32, -11.7, 88, 0.55, 0.75, brick)
        add(.flat(named: "taitung-front-vaults", from: portico.mesh),
            at: Map3DPoint(53.11, 0, 26.87), angle: 83.1805 * .pi / 180)

        // Platform sheds retain their three separate surveyed roof polygons.
        // The repeated columns and fascia are visual estimates.
        let platforms: [(Float, Float, Float, Float)] = [
            (-17.93, -7.23, 83.1893, 226.128),
            (-33.63, 0.98, 83.1841, 238.757),
            (-51.64, -2.41, 83.1808, 227.231)
        ]
        for (east, north, rotation, length) in platforms {
            var supports = StationKitBuilder()
            let step: Float = detail == .near ? 14 : 31
            for x in stride(from: -length / 2 + 7, through: length / 2 - 7, by: step) {
                supports.box(x, 0.32, 0, 0.65, 0.65, 4.98, columns)
                if detail == .near {
                    supports.box(x, 4.9, 0, 0.32, 9.0, 0.25, darkRoof)
                }
            }
            supports.box(0, 5.62, -4.3, length - 1, 0.3, 0.3, darkRoof)
            supports.box(0, 5.62, 4.3, length - 1, 0.3, 0.3, darkRoof)
            add(.flat(named: "taitung-platform-supports", from: supports.mesh),
                at: Map3DPoint(east, 0, north), angle: rotation * .pi / 180)
        }
    }

    mutating func banqiaoExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let trim = Map3DColor.rgb(0xEEE5DA)
        let towerWall = Map3DColor.rgb(0xDDCEC2)
        let podiumWall = Map3DColor.rgb(0xCDBEB5)
        let paleRoof = Map3DColor.rgb(0xBEC7C6)
        let windows = Map3DColor.rgb(0x728C94)
        let glass = Map3DColor.rgb(0x688189)
        let darkGlass = Map3DColor.rgb(0x5B6970)

        // The parent OSM building has height=116.8 m and 25 above-ground
        // levels. Its two commercial building:part ways have no own heights.
        footprint(Map3DStationExteriorBatch1.banqiaoMainFootprint, color: podiumWall)
        for outline in [Map3DStationExteriorBatch1.banqiaoTowerSouthFootprint,
                        Map3DStationExteriorBatch1.banqiaoTowerNorthFootprint] {
            footprint(outline, color: towerWall, baseY: 20, height: 0.32)
        }
        // The circular-line station is tagged layer=1, without height tags.
        footprint(Map3DStationExteriorBatch1.banqiaoCircularLineFootprint,
                  color: paleRoof, baseY: 7, height: 0.32)

        // A low, long station podium with two cylindrical end pavilions and
        // a shallow curved roof rhythm. Podium height and all subdivisions
        // are photo/reference estimates, separate from OSM's tower height.
        var podium = StationKitBuilder()
        podium.box(0, 0.32, 0, 181, 91, 17.6, podiumWall)
        podium.box(0, 0.32, -48, 161, 20, 18.3, podiumWall)
        podium.box(0, 18.0, 0, 191, 113, 1.4, trim)
        for x: Float in [-85, 85] {
            podium.cylinder(x, 0.32, -47, radius: 11.0, height: 18.5,
                            color: podiumWall, sides: detail == .near ? 16 : 10)
            podium.cylinder(x, 18.82, -47, radius: 11.8, height: 0.7,
                            color: trim, sides: detail == .near ? 16 : 10)
        }
        for x in stride(from: Float(-68), through: 68, by: detail == .near ? 10 : 20) {
            podium.box(x, 2.8, -58.18, 6.0, 0.18, 10.4, windows)
            if detail == .near { podium.box(x, 13.8, -58.2, 0.55, 0.25, 3.9, trim) }
        }
        for x: Float in [-47, 0, 47] {
            podium.canopy(x, 19.4, -43, length: 27, width: 17,
                          rise: 1.8, color: paleRoof)
        }
        add(.flat(named: "banqiao-podium", from: podium.mesh),
            at: Map3DPoint(-13.09, 0, -32.37), angle: 52.2644 * .pi / 180)

        // The two towers keep their individual OSM part outlines. The parent
        // way supplies only their shared 116.8 m top; 20 m start is estimated.
        let towers: [(Float, Float, Float)] = [(-69.03, -42.86, -36.3563),
                                               (-29.51, 17.53, -34.7394)]
        for (east, north, rotation) in towers {
            var tower = StationKitBuilder()
            tower.box(0, 20.32, 0, 43.4, 41.4, 85.2, towerWall)
            tower.box(0, 105.52, 0, 39.4, 37.4, 8.78, towerWall)
            tower.box(0, 114.3, 0, 47.1, 45.0, 2.5, trim)
            tower.box(0, 112.7, 0, 40.2, 38.2, 1.6, podiumWall)
            let floorStep: Int = detail == .near ? 1 : 3
            let columns: [Float] = detail == .near ? [-15.4, -7.7, 0, 7.7, 15.4]
                                                   : [-14, 0, 14]
            for floor in stride(from: 0, through: 21, by: floorStep) {
                let y = Float(23.0 + Double(floor) * 3.7)
                let height: Float = detail == .near ? 2.45 : 2.9
                for x in columns {
                    for z: Float in [-20.75, 20.75] {
                        let panel = [Map3DPoint(x - 2.6, y, z),
                                     Map3DPoint(x + 2.6, y, z),
                                     Map3DPoint(x + 2.6, y + height, z),
                                     Map3DPoint(x - 2.6, y + height, z)]
                        tower.face(panel, inside: Map3DPoint(0, y, 0), color: windows)
                    }
                }
                let sideColumns: [Float] = detail == .near ? [-13, 0, 13] : [-11, 11]
                for z in sideColumns {
                    for x: Float in [-21.75, 21.75] {
                        let panel = [Map3DPoint(x, y, z - 2.6),
                                     Map3DPoint(x, y, z + 2.6),
                                     Map3DPoint(x, y + height, z + 2.6),
                                     Map3DPoint(x, y + height, z - 2.6)]
                        tower.face(panel, inside: Map3DPoint(0, y, 0), color: windows)
                    }
                }
            }
            for x: Float in [-14, 14] {
                tower.box(x, 106.6, -18.9, 5.6, 0.18, 4.9, glass)
            }
            add(.flat(named: "banqiao-tower", from: tower.mesh),
                at: Map3DPoint(east, 0, north), angle: rotation * .pi / 180)
        }

        // Dark central glazed link between the two station towers.
        var link = StationKitBuilder()
        link.box(0, 20.32, 0, 30.0, 37.0, 66.0, darkGlass)
        for y in stride(from: Float(25), through: 82, by: detail == .near ? 5.5 : 12) {
            for z: Float in [-18.65, 18.65] {
                link.box(0, y, z, 30.5, 0.24, 0.34, paleRoof)
            }
        }
        add(.flat(named: "banqiao-glass-link", from: link.mesh),
            at: Map3DPoint(-49.27, 0, -12.67), angle: 52.2644 * .pi / 180)

        var circular = StationKitBuilder()
        circular.box(0, 7.32, 0, 87, 32, 11.0, glass)
        circular.canopy(0, 18.32, 0, length: 91, width: 34,
                        rise: 3.7, color: paleRoof)
        for x in stride(from: Float(-39), through: 39, by: detail == .near ? 7 : 19) {
            for z: Float in [-15.8, 15.8] {
                circular.box(x, 7.32, z, 0.46, 0.52, 10.7, trim)
                circular.box(x, 0.32, z, 0.75, 0.75, 7.0, podiumWall)
            }
        }
        add(.flat(named: "banqiao-circular-line", from: circular.mesh),
            at: Map3DPoint(55.42, 0, 83.86), angle: -36.3842 * .pi / 180)
    }

    mutating func nangangGlassTower(length: Float, width: Float,
                                   detail: Map3DStationExteriorBatch1.LevelOfDetail,
                                   glass: UInt32, frame: UInt32, roof: UInt32) {
        // A/B both carry OSM height=139 and 30 levels; the 28 m starting
        // plane comes from the reference display and is not an OSM height.
        box(0, 28.32, 0, length - 0.9, width - 0.9, 109.38, glass)
        box(0, 137.7, 0, length, width, 1.3, roof)
        for x: Float in [-length / 2 + 2.5, length / 2 - 2.5] {
            box(x, 28.32, 0, 0.7, width - 1, 109.38, frame)
        }
        let floors = detail == .near ? Array(stride(from: 0, through: 22, by: 1))
                                        : Array(stride(from: 0, through: 22, by: 3))
        let frontColumns = detail == .near ? Int(length / 5.0) : Int(length / 12.0)
        let sideColumns = detail == .near ? Int(width / 5.0) : Int(width / 11.0)
        for floor in floors {
            let y = Float(31.0 + Double(floor) * 4.55)
            let height: Float = detail == .near ? 2.6 : 3.1
            for index in 0..<frontColumns {
                let x = -length / 2 + (Float(index) + 0.5) * length / Float(frontColumns)
                for z: Float in [-(width - 0.9) / 2 - 0.05, (width - 0.9) / 2 + 0.05] {
                    let panel = [Map3DPoint(x - 1.8, y, z), Map3DPoint(x + 1.8, y, z),
                                 Map3DPoint(x + 1.8, y + height, z),
                                 Map3DPoint(x - 1.8, y + height, z)]
                    face(panel, inside: Map3DPoint(0, y, 0), color: roof)
                }
            }
            for index in 0..<sideColumns {
                let z = -width / 2 + (Float(index) + 0.5) * width / Float(sideColumns)
                for x: Float in [-(length - 0.9) / 2 - 0.05, (length - 0.9) / 2 + 0.05] {
                    let panel = [Map3DPoint(x, y, z - 1.7), Map3DPoint(x, y, z + 1.7),
                                 Map3DPoint(x, y + height, z + 1.7),
                                 Map3DPoint(x, y + height, z - 1.7)]
                    face(panel, inside: Map3DPoint(0, y, 0), color: roof)
                }
            }
        }
    }

    mutating func nangangExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let white = Map3DColor.rgb(0xE8E9E2)
        let paleRoof = Map3DColor.rgb(0xD8E1DE)
        let frame = Map3DColor.rgb(0xB7C6C4)
        let glass = Map3DColor.rgb(0x97B8BA)
        let concrete = Map3DColor.rgb(0xAAB3B1)
        let brick = Map3DColor.rgb(0xBE9F91)
        let darkGlass = Map3DColor.rgb(0x607D84)
        let darkRim = Map3DColor.rgb(0x6F7879)

        footprint(Map3DStationExteriorBatch1.nangangMainFootprint, color: brick)
        footprint(Map3DStationExteriorBatch1.nangangBlockCFootprint, color: white)
        footprint(Map3DStationExteriorBatch1.nangangEastFootprint, color: white)
        for outline in [Map3DStationExteriorBatch1.nangangBlockAFootprint,
                        Map3DStationExteriorBatch1.nangangBlockBFootprint] {
            footprint(outline, color: frame, baseY: 28, height: 0.32)
        }

        // Seven OSM levels on the station body; the 28 m roof and front
        // entrance canopy are photo/reference estimates.
        var main = StationKitBuilder()
        main.box(0, 0.32, 0, 207, 126, 24.7, brick)
        main.box(0, 25.02, 0, 212, 133, 2.98, concrete)
        for y in stride(from: Float(5), through: 23, by: detail == .near ? 4 : 9) {
            for z: Float in [-63.2, 63.2] {
                main.box(0, y, z, 204, 0.22, 0.45, white)
            }
        }
        main.box(0, 1.0, -63.18, 59, 0.26, 15.5, darkGlass)
        main.canopy(0, 17.0, -67, length: 75, width: 33,
                    rise: 2.8, color: paleRoof)
        for x in stride(from: Float(-32), through: 32, by: detail == .near ? 8 : 16) {
            main.box(x, 0.32, -76, 0.55, 0.55, 16.6, white)
            if detail == .near {
                main.beam(Map3DPoint(x, 9, -76), Map3DPoint(x, 17.5, -58),
                          0.26, frame)
            }
        }
        add(.flat(named: "nangang-main-station", from: main.mesh),
            at: Map3DPoint(-5.75, 0, 0.31), angle: 10.1304 * .pi / 180)

        var blockA = StationKitBuilder()
        blockA.nangangGlassTower(length: 60.0, width: 34.6, detail: detail,
                                glass: glass, frame: frame, roof: paleRoof)
        add(.flat(named: "nangang-block-a", from: blockA.mesh),
            at: Map3DPoint(48.05, 0, 1.59), angle: 10.1912 * .pi / 180)

        var blockB = StationKitBuilder()
        blockB.nangangGlassTower(length: 83.5, width: 38.8, detail: detail,
                                glass: glass, frame: frame, roof: paleRoof)
        add(.flat(named: "nangang-block-b", from: blockB.mesh),
            at: Map3DPoint(-66.76, 0, -19.95), angle: 9.9422 * .pi / 180)

        // C has its own tagged 70 m/14 levels. White lower walls, a glass
        // upper band and a rounded dark end follow the developer's photos.
        var blockC = StationKitBuilder()
        blockC.box(0, 0.32, 0, 110, 40.8, 43.7, white)
        blockC.box(0, 44.02, 0, 111, 41.2, 25.3, glass)
        blockC.box(0, 69.32, 0, 112, 41.65, 0.68, paleRoof)
        for y: Float in [12, 24, 37] {
            for z: Float in [-20.6, 20.6] {
                blockC.box(0, y, z, 103, 0.22, 1.1, darkRim)
            }
        }
        for x in stride(from: Float(-49), through: 49, by: detail == .near ? 7 : 17) {
            for z: Float in [-20.68, 20.68] {
                blockC.box(x, 47, z, 4.0, 0.18, 18.5, darkGlass)
            }
        }
        blockC.cylinder(44, 0.32, 25, radius: 9.5, height: 63,
                        color: darkGlass, sides: detail == .near ? 16 : 10)
        blockC.cylinder(44, 63.32, 25, radius: 10.1, height: 1.0,
                        color: darkRim, sides: detail == .near ? 16 : 10)
        add(.flat(named: "nangang-block-c", from: blockC.mesh),
            at: Map3DPoint(-163.71, 0, -35.77), angle: 8.3804 * .pi / 180)

        // East-side station retail building: OSM has no height. The broad
        // glass entrance and curved steel roof come from exterior photos.
        var east = StationKitBuilder()
        east.box(0, 0.32, 0, 81.5, 40.5, 17.8, white)
        east.box(0, 1.0, -20.48, 52, 0.2, 15.0, glass)
        east.canopy(0, 18.12, 0, length: 83.0, width: 42.0,
                    rise: 4.8, color: paleRoof)
        east.cylinder(34, 0.32, -15.0, radius: 7.5, height: 19.5,
                      color: white, sides: detail == .near ? 14 : 8)
        east.cylinder(34, 19.82, -15.0, radius: 8.0, height: 0.6,
                      color: darkRim, sides: detail == .near ? 14 : 8)
        if detail == .near {
            for x in stride(from: Float(-35), through: 28, by: 8) {
                east.box(x, 1.0, -20.68, 0.42, 0.28, 15.0, frame)
            }
        } else {
            for x in stride(from: Float(-32), through: 24, by: 16) {
                east.box(x, 1.0, -20.68, 0.55, 0.28, 15.0, frame)
            }
        }
        add(.flat(named: "nangang-east-station", from: east.mesh),
            at: Map3DPoint(175.0, 0, 20.99), angle: 9.951 * .pi / 180)
    }
}
