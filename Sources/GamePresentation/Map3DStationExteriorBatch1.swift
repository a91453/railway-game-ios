import Foundation

/// The exterior studies of #1904. Decision 625 stands them on the 3D map
/// (`Map3DStationExteriors.swift`); the station kit's catalogue does not list them.
public enum Map3DStationExteriorBatch1 {
    public enum LevelOfDetail: Sendable { case near, far }
    public enum Station: String, CaseIterable, Sendable { case taichungTRA = "tra-taichung", hsinchuTRA = "tra-hsinchu", hualienTRA = "tra-hualien", taitungTRA = "tra-taitung", banqiaoTRA = "tra-banqiao", nangangTRA = "tra-nangang", taoyuanHSR = "hsr-taoyuan", hsinchuHSR = "hsr-hsinchu", taichungHSR = "hsr-taichung", tainanHSR = "hsr-tainan", zuoyingHSR = "hsr-zuoying" }

    public static func model(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model {
        .flat(named: "station-exterior-study-\(station.rawValue)-\(detail == .near ? "near" : "far")", from: mesh(for: station, detail: detail))
    }

    /// Decision 625: the study as built, in its own metres east (+x), up
    /// (+y) and north (+z) of ``origin(of:)``, its night glass glowing.
    static func mesh(for station: Station, detail: LevelOfDetail) -> Map3DMesh {
        var builder = StationKitBuilder()
        switch station {
        case .taichungTRA: builder.taichungExteriorStudy(detail: detail)
        case .hsinchuTRA: builder.hsinchuExteriorStudy(detail: detail)
        case .hualienTRA: builder.hualienExteriorStudy(detail: detail)
        case .taitungTRA: builder.taitungExteriorStudy(detail: detail)
        case .banqiaoTRA: builder.banqiaoExteriorStudy(detail: detail)
        case .nangangTRA: builder.nangangExteriorStudy(detail: detail)
        case .taoyuanHSR: builder.taoyuanHSRExteriorStudy(detail: detail)
        case .hsinchuHSR: builder.hsinchuHSRExteriorStudy(detail: detail)
        case .taichungHSR: builder.taichungHSRExteriorStudy(detail: detail)
        case .tainanHSR: builder.tainanHSRExteriorStudy(detail: detail)
        case .zuoyingHSR: builder.zuoyingHSRExteriorStudy(detail: detail)
        }
        let litColours = nightGlassColours(for: station)
        builder.mesh.restyleVertices { vertex in
            if litColours.contains(vertex.color) && abs(vertex.ny) < 0.55 {
                vertex.layer = Map3DVertex.glowing
            }
        }
        return builder.mesh
    }

    static func nightGlassColours(for station: Station) -> Set<UInt32> {
        let colours: [UInt32]
        // StationKitBuilder.box shades each of its four vertical sides.
        let sideShades: [Float] = [1, 0.92, 0.80, 0.70, 0.86]
        switch station {
        case .taichungTRA:
            return Set(sideShades.map { Map3DColor.shaded(Map3DPalette.glazing, $0) })
        case .hsinchuTRA: colours = [0xAFC7CD]
        case .hualienTRA: colours = [0x9BB7B9]
        case .taitungTRA: colours = [0x8CACB1]
        case .banqiaoTRA: colours = [0x728C94, 0x688189, 0x5B6970]
        case .nangangTRA: colours = [0x607D84]
        case .taoyuanHSR: colours = [0x8EABB0, 0x607F86]
        case .hsinchuHSR: colours = [0x8EAEB2, 0x66878B]
        case .taichungHSR: colours = [0x98B7B8, 0x6A8589]
        case .tainanHSR: colours = [0x9CB5B9, 0x637F86]
        case .zuoyingHSR: colours = [0x91B7BD, 0x648991]
        }
        return Set(colours.flatMap { colour in
            sideShades.map { Map3DColor.shaded(Map3DColor.rgb(colour), $0) }
        })
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

    // Taoyuan HSR and Airport MRT A18: osmtoday Taiwan PBF, 2026-11-06.
    // Metres east/north from (121.214539, 25.01347985); © OpenStreetMap contributors, ODbL 1.0.
    static let taoyuanHSRFootprint: [(Float, Float)] = [ // OSM way 23547222
        (-18.067, -53.613), (-10.732, -45.584), (-4.585, -38.879),
        (-1.370, -35.277), (15.810, -15.962), (30.975, 1.073),
        (33.716, -1.418), (41.344, -8.012), (46.272, -12.137),
        (62.243, 5.654), (86.296, -17.052), (70.717, -34.987),
        (75.897, -39.869), (82.255, -45.851), (85.137, -48.553),
        (69.669, -65.255), (51.612, -84.736), (35.893, -101.704),
        (32.366, -98.524), (23.922, -91.386), (20.838, -88.772),
        (4.031, -106.286), (-21.292, -82.534), (-4.907, -65.677),
        (-7.578, -63.220), (-14.541, -56.837),
    ]
    static let taoyuanA18Footprint: [(Float, Float)] = [ // OSM way 560119012
        (15.730, 106.286), (25.222, 97.368), (26.380, 99.503),
        (38.341, 88.839), (-42.604, 0.128), (-30.885, -10.914),
        (-28.013, -7.878), (-22.954, -12.526), (-27.237, -17.964),
        (-30.703, -21.744), (-33.495, -24.813), (-34.422, -25.936),
        (-50.957, -9.568), (-59.724, -18.931), (-75.584, -3.664),
        (-86.296, -5.354), (-76.451, 5.754), (-68.420, 14.205),
    ]

    // Hsinchu HSR and TRA Liujia: osmtoday Taiwan PBF, 2026-11-06.
    // Metres east/north from (121.04001555, 24.8083231); © OpenStreetMap contributors, ODbL 1.0.
    static let hsinchuHSRFootprint: [(Float, Float)] = [ // OSM way 321663134
        (37.078, 173.509), (46.394, 165.958), (67.782, 161.110),
        (79.601, 162.111), (48.473, 38.707), (60.777, 23.584),
        (75.513, -0.200), (65.905, -10.096), (55.660, -20.627),
        (43.578, -32.413), (39.510, -36.372), (34.302, -41.453),
        (29.720, -45.924), (1.125, -173.509), (-9.140, -170.573),
        (-30.679, -162.934), (-33.888, -161.488), (-3.467, -28.833),
        (-26.944, -21.105), (-37.976, -17.836), (-8.160, 37.473),
        (-2.660, 46.324), (8.857, 64.816),
    ]
    static let liujiaFootprint: [(Float, Float)] = [ // OSM way 321663135
        (-79.601, -105.001), (-45.930, -107.314), (-43.871, -72.154),
        (-43.618, -69.753), (-47.282, -69.641), (-46.889, -59.812),
        (-61.120, -58.700), (-74.272, -57.866), (-75.019, -69.363),
        (-77.159, -69.219), (-77.350, -75.446),
    ]

    // Taichung HSR / TRA Xinwuri / Taichung MRT / two transfer links.
    // osmtoday Taiwan PBF 2026-11-06. Metres east/north from
    // (120.61474665, 24.1112536); © OpenStreetMap contributors, ODbL 1.0.
    static let xinwuriFootprint: [(Float, Float)] = [ // OSM way 337921979
        (7.688, -149.713), (-93.034, -138.137), (-116.692, -135.413),
        (-125.989, -134.757), (-135.986, -134.868), (-144.826, -135.258),
        (-150.226, -135.647), (-153.250, -167.304), (-148.257, -170.039),
        (-139.630, -172.841), (-130.018, -174.787), (-121.483, -176.044),
        (-60.485, -182.793), (-60.769, -185.284), (-63.936, -213.817),
        (-52.599, -214.829), (-38.897, -215.941), (-37.192, -196.893),
        (-36.259, -185.273), (4.562, -189.543), (21.928, -190.266),
        (29.174, -201.696), (36.908, -199.295), (37.700, -189.654),
        (43.972, -188.575), (49.301, -186.074), (50.630, -169.283),
        (46.915, -164.491), (39.638, -159.820), (31.965, -157.241),
        (56.486, -133.656), (32.473, -130.888),
    ]
    static let taichungHSRFootprint: [(Float, Float)] = [ // OSM way 544377825
        (110.684, 215.941), (119.443, 201.696), (142.218, 199.906),
        (153.250, 212.360), (145.577, 69.074), (141.944, 19.526),
        (138.716, -9.207), (137.620, -18.903), (133.023, -59.890),
        (132.008, -68.874), (127.684, -107.392), (121.128, -141.329),
        (112.511, -127.674), (89.786, -124.772), (78.744, -136.147),
        (65.702, -134.757), (56.486, -133.656), (32.473, -130.888),
        (26.373, -125.617), (44.409, -111.373), (60.901, -97.451),
        (69.630, -98.285), (76.085, 25.041), (80.824, 74.645),
        (103.792, 195.914),
    ]
    static let taichungLinkEWFootprint: [(Float, Float)] = [ // OSM way 862779520
        (-87.807, -84.575), (-79.799, -85.320), (-69.873, -86.332),
        (-65.742, -86.676), (-64.657, -75.468), (-111.750, -70.142),
        (-112.592, -77.725), (-87.361, -80.839),
    ]
    static let taichungLinkNSFootprint: [(Float, Float)] = [ // OSM way 862779521
        (-79.799, -85.320), (-83.098, -117.622),
        (-73.172, -118.767), (-69.873, -86.332),
    ]
    static let taichungMRTFootprint: [(Float, Float)] = [ // OSM way 862779522
        (-116.692, -135.413), (-93.034, -138.137), (7.688, -149.713),
        (15.392, -143.864), (32.473, -130.888), (-73.172, -118.767),
        (-83.098, -117.622), (-146.257, -110.372), (-148.632, -131.699),
    ]

    // Relation 9351022 outer rings: station = ways 672619073+075;
    // platform = ways 672619074+076. The other two outlines are ways.
    // PBF 2026-11-06, metres east/north from 120.28626105 E, 22.92464555 N.
    // © OpenStreetMap contributors, ODbL 1.0.
    static let tainanHSRFootprint: [(Float, Float)] = [
        (-33.955, 15.806), (-51.703, 55.547), (-66.686, 56.037),
        (-93.477, 45.462), (-89.483, 35.354), (-99.284, 26.581),
        (-64.556, -53.412), (-56.506, -52.656), (-53.208, -51.222),
        (-48.180, -46.307), (-43.418, -57.271), (-29.459, -51.211),
        (-24.164, -48.909), (-27.103, -42.137), (-10.861, -35.088),
        (-18.019, -18.608), (-29.223, 7.189), (-31.487, 11.314),
    ]
    static let tainanPlatformWestFootprint: [(Float, Float)] = [
        (-6.795, 13.382), (60.265, -130.737), (72.544, -125.022),
        (-68.980, 179.274), (-81.618, 173.392), (-11.690, 22.978),
        (-9.704, 19.098),
    ]
    static let tainanPlatformEastFootprint: [(Float, Float)] = [ // way 266850895
        (89.534, -122.631), (99.284, -117.661),
        (-39.680, 181.754), (-47.965, 178.640),
    ]
    static let shalunFootprint: [(Float, Float)] = [ // way 316034163
        (50.607, -181.754), (62.129, -176.539),
        (0.702, -40.914), (-6.488, -44.172), (-23.755, -51.989),
        (-5.935, -91.341), (7.020, -85.470),
    ]

    // OSM ways 111991261 and 303296097, Taiwan PBF 2026-11-06.
    // Metres east/north from 120.3074864 E, 22.68726485 N.
    // © OpenStreetMap contributors, ODbL 1.0.
    static let zuoyingHSRFootprint: [(Float, Float)] = [
        (78.739, 24.146), (90.065, 34.498), (108.983, 13.783),
        (43.960, -45.595), (-28.089, -111.390), (-30.603, -108.665),
        (-45.920, -91.875), (-32.480, -79.599), (-67.351, -41.415),
        (45.161, 60.918),
    ]
    static let xinzuoyingFootprint: [(Float, Float)] = [
        (15.183, 111.390), (17.748, 108.565), (22.119, 103.762),
        (32.275, 92.598), (26.048, 86.938), (47.643, 63.187),
        (45.161, 60.918), (-67.351, -41.415), (-70.408, -44.194),
        (-95.399, -16.718), (-102.160, -9.279), (-105.618, -5.476),
        (-108.983, -1.785), (-80.236, 24.368), (-86.741, 31.240),
        (-13.070, 98.191), (-6.709, 91.475),
    ]

}

private extension StationKitBuilder {
    mutating func litBox(_ x: Float, _ y: Float, _ z: Float,
                         _ length: Float, _ width: Float, _ height: Float, _ color: UInt32) {
        let start = mesh.vertices.count
        box(x, y, z, length, width, height, color)
        mesh.makeGlowing(from: start)
    }

    mutating func litFace(_ points: [Map3DPoint], inside: Map3DPoint, color: UInt32) {
        let start = mesh.vertices.count
        face(points, inside: inside, color: color)
        mesh.makeGlowing(from: start)
    }

    mutating func footprint(_ points: [(Float, Float)], color: UInt32, baseY: Float = 0, height: Float = 0.32) {
        guard points.count >= 3 else { return }
        // Keep every surveyed vertex without exposing a coloured polygon
        // outside the station. Ground outlines are only a thin ground-colour
        // edge; elevated roof outlines retain their filled top surface.
        let p = points.map { Map3DPoint($0.0, baseY + height, $0.1) }
        if baseY == 0 {
            for i in points.indices {
                let j = (i + 1) % points.count
                let a = p[i], b = p[j]
                face([a, b, Map3DPoint(b.x, 0, b.z), Map3DPoint(a.x, 0, a.z)],
                     inside: .zero, color: Map3DPalette.ground)
            }
            return
        }
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
        hall.litBox(0, 27.36, -28, 204, 0.34, 0.18, warmWall)
        hall.box(0, 12.9, 0, 239, 0.55, 14.5, StationKitBuilder.glass)
        for z: Float in [-32.65, 32.65] {
            hall.box(0, 13.12, z, 231, 0.24, 14.3, StationKitBuilder.glass)
        }
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
        station.box(-46, 0.32, 0, 47, 15.2, 8.68, wall)
        station.box(46, 0.32, 0, 47, 15.2, 8.68, wall)
        station.hip(-46, 9, 0, 49, 16.2, 4.3, roof)
        station.hip(46, 9, 0, 49, 16.2, 4.3, roof)
        // The broad raised central roof and its pale Baroque entrance.
        station.box(0, 0.32, 0, 45, 17.2, 13.88, wall)
        station.box(0, 0.32, -8.0, 22, 3.2, 13.88, wall)
        station.gable(0, 14.2, -8.0, 23.0, 4.3, 3.0, trim)
        station.hip(0, 14.2, 0, 47, 19.5, 4.5, roof)
        station.box(0, 1.2, -9.68, 8, 0.2, 10.0, glass)
        station.box(0, 11.2, -9.78, 14, 0.35, 0.8, trim)
        station.box(0, 0.32, -9.62, 22, 0.5, 1.0, brick)
        // Clock tower is separate from the measured OSM height.
        station.box(0, 16.0, 0, 8.2, 8.2, 7.0, wall)
        station.hip(0, 23.0, 0, 9, 9, 3.5, roof)
        station.box(0, 26.5, 0, 0.35, 0.35, 1.2, StationKitBuilder.steel)
        station.clockFace(0, 19.4, -4.23, size: 2.2)
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
            station.litBox(0, 4.45, -10.5, 124, 0.24, 0.14, trim)
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
            station.litBox(0, 4.45, -10.0, 120, 0.24, 0.14, trim)
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
            for x in stride(from: Float(-60), through: 60, by: 40) {
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
        let screenStep: Float = detail == .near ? 3.3 : 12.4
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
            if detail == .near {
                umbrella.canopy(x, edgeHeight, 0, length: 15.5, width: 28.5, rise: 1.8, color: paleRoof)
            } else {
                umbrella.gable(x, edgeHeight, 0, 15.5, 28.5, 1.8, paleRoof)
            }
            umbrella.litBox(x, edgeHeight - 0.3, -9, 12, 0.26, 0.16, warmWall)
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
        for x in stride(from: Float(-37), through: 37, by: detail == .near ? 7.5 : 20) {
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
            for x in stride(from: Float(-87), through: 87, by: detail == .near ? 15 : 65) {
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

        // The entrance hall rises above the two vault rows and remains readable
        // from the street; its raised glass front is estimated from photographs.
        var hall = StationKitBuilder()
        hall.box(0, 0.32, 0, 85, 22.8, 15.1, tiledWall)
        hall.box(0, 15.42, 0, 87.5, 24, 0.88, platformRoof)
        hall.box(0, 8.0, -11.62, 45, 0.24, 6.5, glass)
        hall.box(0, 14.5, -11.85, 48, 0.45, 0.75, tiledWall)
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
        let pitch: Float = detail == .near ? 10.5 : 38.0
        if detail == .far {
            // Two shallow continuous roofs retain the double-row entrance.
            for (z, edgeHeight) in [(Float(-5.75), Float(6.6)), (Float(5.75), Float(9.5))] {
                portico.gable(0, edgeHeight, z, 88, 11.8, 1.65, arcRoof)
            }
        }
        for x in stride(from: Float(-38), through: 38, by: pitch) {
            if detail == .near {
                for (z, edgeHeight) in [(Float(-5.75), Float(6.6)), (Float(5.75), Float(9.5))] {
                    var vault = StationKitBuilder()
                    vault.canopy(0, 0, 0, length: 12.0, width: 11.1,
                                 rise: 1.8, color: arcRoof)
                    portico.add(.flat(named: "taitung-vault", from: vault.mesh),
                                at: Map3DPoint(x, edgeHeight, z), angle: Float.pi / 2)
                }
            }
            for z: Float in [-10.5, 0.0, 10.5] {
                portico.box(x, 0.32, z, 0.65, 0.65, z == -10.5 ? 6.28 : 9.18, columns)
                if detail == .near {
                    portico.box(x, 5.8, z, 0.3, 3.7, 0.28, darkRoof)
                }
            }
        }
        portico.box(0, 0.32, -11.7, 88, 0.55, 0.75, brick)
        portico.litBox(0, 6.25, -8.5, 74, 0.35, 0.18, tiledWall)
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
            let step: Float = detail == .near ? 14 : 56
            for x in stride(from: -length / 2 + 7, through: length / 2 - 7, by: step) {
                supports.box(x, 0.32, 0, 0.65, 0.65, 4.98, columns)
                if detail == .near {
                    supports.box(x, 4.9, 0, 0.32, 9.0, 0.25, darkRoof)
                }
            }
            supports.box(0, 5.62, -4.3, length - 1, 0.3, 0.3, darkRoof)
            supports.box(0, 5.62, 4.3, length - 1, 0.3, 0.3, darkRoof)
            supports.litBox(0, 5.42, -3.9, length - 15, 0.3, 0.14, tiledWall)
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
            podium.litBox(x, 19.1, -49, 21, 0.3, 0.16, trim)
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
                                        : [0, 11, 22]
        let frontColumns = detail == .near ? Int(length / 5.0) : 3
        let sideColumns = detail == .near ? Int(width / 5.0) : 2
        for floor in floors {
            let y = Float(31.0 + Double(floor) * 4.55)
            let height: Float = detail == .near ? 2.6 : 3.1
            for index in 0..<frontColumns {
                let x = -length / 2 + (Float(index) + 0.5) * length / Float(frontColumns)
                for z: Float in [-(width - 0.9) / 2 - 0.05, (width - 0.9) / 2 + 0.05] {
                    let panel = [Map3DPoint(x - 1.8, y, z), Map3DPoint(x + 1.8, y, z),
                                 Map3DPoint(x + 1.8, y + height, z),
                                 Map3DPoint(x - 1.8, y + height, z)]
                    litFace(panel, inside: Map3DPoint(0, y, 0), color: roof)
                }
            }
            for index in 0..<sideColumns {
                let z = -width / 2 + (Float(index) + 0.5) * width / Float(sideColumns)
                for x: Float in [-(length - 0.9) / 2 - 0.05, (length - 0.9) / 2 + 0.05] {
                    let panel = [Map3DPoint(x, y, z - 1.7), Map3DPoint(x, y, z + 1.7),
                                 Map3DPoint(x, y + height, z + 1.7),
                                 Map3DPoint(x, y + height, z - 1.7)]
                    litFace(panel, inside: Map3DPoint(0, y, 0), color: roof)
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
        for y in stride(from: Float(5), through: 23, by: detail == .near ? 4 : 18) {
            for z: Float in [-63.2, 63.2] {
                main.box(0, y, z, 204, 0.22, 0.45, white)
            }
        }
        main.box(0, 1.0, -63.18, 59, 0.26, 15.5, darkGlass)
        main.canopy(0, 17.0, -67, length: 75, width: 33,
                    rise: 2.8, color: paleRoof)
        main.litBox(0, 16.7, -76, 62, 0.34, 0.18, white)
        for x in stride(from: Float(-32), through: 32, by: detail == .near ? 8 : 32) {
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
        for x in stride(from: Float(-49), through: 49, by: detail == .near ? 7 : 26) {
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
        east.litBox(0, 17.82, -15, 68, 0.34, 0.18, white)
        east.cylinder(34, 0.32, -15.0, radius: 7.5, height: 19.5,
                      color: white, sides: detail == .near ? 14 : 8)
        east.cylinder(34, 19.82, -15.0, radius: 8.0, height: 0.6,
                      color: darkRim, sides: detail == .near ? 14 : 8)
        if detail == .near {
            for x in stride(from: Float(-35), through: 28, by: 8) {
                east.box(x, 1.0, -20.68, 0.42, 0.28, 15.0, frame)
            }
        } else {
            for x in stride(from: Float(-32), through: 24, by: 28) {
                east.box(x, 1.0, -20.68, 0.55, 0.28, 15.0, frame)
            }
        }
        add(.flat(named: "nangang-east-station", from: east.mesh),
            at: Map3DPoint(175.0, 0, 20.99), angle: 9.951 * .pi / 180)
    }

    mutating func taoyuanHSRExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let roof = Map3DColor.rgb(0xE6E9E6)
        let frame = Map3DColor.rgb(0xCBD6D3)
        let stone = Map3DColor.rgb(0xD5CDC0)
        let glass = Map3DColor.rgb(0x8EABB0)
        let darkGlass = Map3DColor.rgb(0x607F86)
        let skylight = Map3DColor.rgb(0xB6CACB)
        let red = Map3DColor.rgb(0xB98E8E)
        let steel = Map3DColor.rgb(0x8F9E9C)

        footprint(Map3DStationExteriorBatch1.taoyuanHSRFootprint, color: stone)
        // A18 is tagged min_level=2/layer=1, but no measured base height.
        footprint(Map3DStationExteriorBatch1.taoyuanA18Footprint,
                  color: frame, baseY: 8.0, height: 0.32)

        // The 20 m hall is the reference display estimate. The flat, striped
        // skylight roof and glass colonnade follow exterior photographs.
        var hsr = StationKitBuilder()
        hsr.box(0, 0.32, 0, 119, 69.5, 17.5, glass)
        hsr.box(0, 17.82, 0, 121.7, 73.4, 2.18, roof)
        hsr.litBox(0, 17.55, -32, 100, 0.35, 0.16, frame)
        for z in stride(from: Float(-27), through: 27, by: detail == .near ? 7 : 14) {
            hsr.box(0, 19.9, z, 110, detail == .near ? 2.6 : 3.4, 0.16, skylight)
            if detail == .near {
                hsr.box(0, 20.06, z, 110, 0.15, 0.10, steel)
            }
        }
        for x in stride(from: Float(-54), through: 54, by: detail == .near ? 7.2 : 18) {
            for z: Float in [-35.1, 35.1] {
                hsr.cylinder(x, 0.32, z, radius: 0.42, height: 17.5,
                             color: frame, sides: detail == .near ? 8 : 6)
            }
        }
        for y: Float in [6.2, 12.2] {
            for z: Float in [-34.8, 34.8] {
                hsr.box(0, y, z, 116, 0.16, 0.27, frame)
            }
        }
        hsr.box(0, 0.32, -35.2, 14, 0.28, 13.8, darkGlass)
        hsr.box(-58, 0.32, 0, 0.5, 69, 17.5, stone)
        hsr.box(58, 0.32, 0, 0.5, 69, 17.5, stone)
        // Decision 625 續: facade cues seen from the map's camera: the
        // roof's dark steel edge, the ground floor's dark glazing between
        // stone piers, and an entrance canopy each side in the red accent.
        for z: Float in [-36.85, 36.85] {
            hsr.box(0, 17.82, z, 122.3, 0.5, 2.3, steel)
        }
        for x: Float in [-61, 61] {
            hsr.box(x, 17.82, 0, 0.5, 74.2, 2.3, steel)
        }
        for z: Float in [-35.45, 35.45] {
            hsr.box(0, 0.32, z, 112, 0.2, 5.4, darkGlass)
            hsr.box(0, 0.32, z * 1.004, 118, 0.2, 0.9, stone)
            hsr.box(0, 5.6, z + (z < 0 ? -3 : 3), 26, 6, 0.45, red)
        }
        add(.flat(named: "taoyuan-hsr-hall", from: hsr.mesh),
            at: Map3DPoint(33.34, 0, 50.46), angle: 47.1966 * .pi / 180)

        // The MRT concourse floats over its OSM outline. Its 8 m base,
        // 22 m eaves and 30 m vault peak are illustrative, not OSM heights.
        var a18 = StationKitBuilder()
        for x in stride(from: Float(-66), through: 66, by: detail == .near ? 22 : 44) {
            for z: Float in [-20, 20] {
                a18.box(x, 0, z, 1.2, 1.2, 8, stone)
            }
        }
        a18.box(0, 8.32, 0, 148, 47, 12.5, glass)
        a18.box(0, 8.32, -23.55, 146, 0.25, 9.0, red)
        a18.box(0, 8.32, 23.55, 146, 0.25, 8.0, stone)
        for x in stride(from: Float(-66), through: 66, by: detail == .near ? 12 : 30) {
            a18.box(x, 8.32, -23.78, 0.5, 0.2, 12.4, steel)
            if detail == .near {
                a18.beam(Map3DPoint(x - 5, 10, -23.9),
                         Map3DPoint(x + 5, 19, -23.9), 0.42, red)
            }
        }
        a18.canopy(0, 21.3, 0, length: 152, width: 52,
                   rise: 8.7, color: roof)
        a18.litBox(0, 20.98, -19, 126, 0.35, 0.16, frame)
        for x in stride(from: Float(-66), through: 66, by: detail == .near ? 18 : 36) {
            a18.beam(Map3DPoint(x, 21.6, -24.5),
                     Map3DPoint(x, 27.8, 0), 0.32, steel)
            a18.beam(Map3DPoint(x, 27.8, 0),
                     Map3DPoint(x, 21.6, 24.5), 0.32, steel)
        }
        add(.flat(named: "taoyuan-a18", from: a18.mesh),
            at: Map3DPoint(-15.42, 0, -33.94), angle: 47.7138 * .pi / 180)
    }

    mutating func hsinchuHSRExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let whiteRoof = Map3DColor.rgb(0xE9ECE8)
        let trim = Map3DColor.rgb(0xD9E1DF)
        let concrete = Map3DColor.rgb(0xCDD2CE)
        let steel = Map3DColor.rgb(0xAABAB9)
        let glass = Map3DColor.rgb(0x8EAEB2)
        let darkGlass = Map3DColor.rgb(0x66878B)
        let shadow = Map3DColor.rgb(0x657577)

        footprint(Map3DStationExteriorBatch1.hsinchuHSRFootprint, color: concrete)
        footprint(Map3DStationExteriorBatch1.liujiaFootprint, color: trim)

        // OSM has three levels and concrete material, but no height or roof
        // tags. The 28 m peak follows the reference display and exterior photos.
        var hsr = StationKitBuilder()
        hsr.box(0, 0.32, 0, 335, 66, 8.3, concrete)
        hsr.box(0, 8.62, 0, 330, 75, 0.75, trim)
        hsr.box(0, 9.37, 0, 142, 65, 9.0, glass)
        hsr.box(0, 9.37, -32.58, 138, 0.28, 8.6, darkGlass)
        for x in stride(from: Float(-63), through: 63, by: detail == .near ? 7 : 21) {
            for z: Float in [-32.8, 32.8] {
                hsr.box(x, 9.37, z, 0.42, 0.42, 9.0, trim)
            }
        }
        for y: Float in [12.5, 15.8] {
            for z: Float in [-32.8, 32.8] {
                hsr.box(0, y, z, 138, 0.16, 0.28, steel)
            }
        }
        hsr.canopy(0, 18.9, 0, length: 342, width: 94,
                   rise: 9.1, color: whiteRoof)
        hsr.litBox(0, 18.55, -39, 292, 0.4, 0.18, trim)
        for z in stride(from: Float(-39), through: 39, by: detail == .near ? 9.75 : 19.5) {
            let y = 18.9 + sinf((z + 47) / 94 * .pi) * 9.1
            hsr.box(0, y + 0.02, z, 340, 0.15, 0.06, trim)
        }
        for x in stride(from: Float(-153), through: 153, by: detail == .near ? 18 : 36) {
            for z: Float in [-41, 41] {
                hsr.box(x, 8.62, z, 0.68, 0.68, 10.2, steel)
                if detail == .near {
                    hsr.beam(Map3DPoint(x, 19.2, z),
                             Map3DPoint(x, 25.7, 0), 0.34, shadow)
                }
            }
        }
        // Slender glass end walls make the exposed hall visible below the roof.
        for x: Float in [-70.8, 70.8] {
            hsr.box(x, 9.37, 0, 0.26, 61.5, 8.2, glass)
        }
        add(.flat(named: "hsinchu-hsr-hall", from: hsr.mesh),
            at: Map3DPoint(22.14, 0, -0.42), angle: 70.4724 * .pi / 180)

        // Liujia has two OSM levels and a flat roof. Its 13 m height,
        // open lower level and column rhythm remain photo/reference estimates.
        var liujia = StationKitBuilder()
        liujia.box(0, 0.32, 0, 45.5, 32.2, 6.2, concrete)
        liujia.box(0, 6.52, 0, 43.2, 30.5, 5.8, glass)
        liujia.box(0, 12.32, 0, 47.5, 33.8, 0.68, whiteRoof)
        for x in stride(from: Float(-19), through: 19, by: detail == .near ? 7.5 : 19) {
            for z: Float in [-16.0, 16.0] {
                liujia.box(x, 0.32, z, 0.62, 0.62, 12.0, trim)
            }
        }
        liujia.box(0, 1.0, -16.18, 20, 0.22, 5.5, darkGlass)
        liujia.box(0, 6.52, -15.4, 42, 0.22, 0.42, steel)
        add(.flat(named: "liujia-station", from: liujia.mesh),
            at: Map3DPoint(-61.24, 0, 82.58), angle: 86.1353 * .pi / 180)
    }

    mutating func taichungHSRExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let roof = Map3DColor.rgb(0xE6EAE6)
        let trim = Map3DColor.rgb(0xD8E0DD)
        let wall = Map3DColor.rgb(0xD4D8D1)
        let steel = Map3DColor.rgb(0xA8B8B6)
        let glass = Map3DColor.rgb(0x98B7B8)
        let darkGlass = Map3DColor.rgb(0x6A8589)
        let shade = Map3DColor.rgb(0x697A7B)

        footprint(Map3DStationExteriorBatch1.taichungHSRFootprint, color: wall)
        footprint(Map3DStationExteriorBatch1.xinwuriFootprint, color: wall)
        footprint(Map3DStationExteriorBatch1.taichungMRTFootprint, color: trim,
                  baseY: 8, height: 0.32)
        for outline in [Map3DStationExteriorBatch1.taichungLinkEWFootprint,
                        Map3DStationExteriorBatch1.taichungLinkNSFootprint] {
            footprint(outline, color: steel, baseY: 4, height: 0.32)
        }

        // The three halls have no OSM height tags. The 30/18/23 m peaks are
        // reference-display estimates; roof and facade come from photos.
        var hsr = StationKitBuilder()
        hsr.box(0, 0.32, 0, 351, 75, 11.5, wall)
        hsr.box(0, 11.82, 0, 350, 84, 7.2, glass)
        hsr.box(0, 19.02, 0, 348, 83, 5.8, trim)
        hsr.canopy(0, 25, 0, length: 360, width: 95,
                   rise: 5, color: roof)
        hsr.litBox(0, 24.7, -40, 306, 0.4, 0.18, trim)
        for z in stride(from: Float(-38), through: 38, by: detail == .near ? 9.5 : 100) {
            let y = 25 + sinf((z + 47.5) / 95 * .pi) * 5
            hsr.box(0, y + 0.02, z, 356, 0.14, 0.06, trim)
        }
        for x in stride(from: Float(-160), through: 160, by: detail == .near ? 16 : 100) {
            for z: Float in [-43, 43] {
                hsr.box(x, 0.32, z, 0.85, 0.85, 24.4, steel)
                if detail == .near {
                    hsr.beam(Map3DPoint(x, 20, z),
                             Map3DPoint(x, 25.2, z * 0.77), 0.3, shade)
                }
            }
        }
        for z: Float in [-42.1, 42.1] {
            hsr.box(0, 0.32, z, 347, 0.28, 8.5, darkGlass)
        }
        for x in stride(from: Float(-162), through: 162, by: detail == .near ? 9 : 64) {
            for z: Float in [-42.35, 42.35] {
                hsr.box(x, 1.0, z, 0.38, 0.2, 18.0, trim)
            }
        }
        add(.flat(named: "taichung-hsr-hall", from: hsr.mesh),
            at: Map3DPoint(107.0, 0, -38.07), angle: 79.0653 * .pi / 180)

        var tra = StationKitBuilder()
        tra.box(0, 0.32, 0, 204, 74, 12.0, wall)
        tra.box(0, 12.32, 0, 208, 84, 5.68, roof)
        tra.box(0, 1, -37.2, 52, 0.25, 15.8, darkGlass)
        tra.box(0, 0.32, -42.5, 45, 8.0, 17.0, darkGlass)
        for x in stride(from: Float(-20), through: 20, by: detail == .near ? 4 : 10) {
            tra.box(x, 0.32, -46.65, 0.3, 0.2, 17.0, steel)
        }
        for x in stride(from: Float(-96), through: 96, by: detail == .near ? 12 : 64) {
            for z: Float in [-37.5, 37.5] {
                tra.box(x, 0.32, z, 0.6, 0.5, 12, trim)
            }
        }
        tra.box(0, 18, -24, 58, 43, 1.0, roof)
        for x in stride(from: Float(-21), through: 21, by: detail == .near ? 10.5 : 21) {
            tra.box(x, 0.32, -43, 0.6, 0.6, 18.0, steel)
        }
        add(.flat(named: "xinwuri-station", from: tra.mesh),
            at: Map3DPoint(-48.18, 0, 174.11), angle: 0.6372 * .pi / 180)

        var mrt = StationKitBuilder()
        for x in stride(from: Float(-76), through: 76, by: detail == .near ? 19 : 76) {
            for z: Float in [-8.5, 8.5] {
                mrt.box(x, 0, z, 0.8, 0.8, 8, steel)
            }
        }
        mrt.box(0, 8.32, 0, 176, 20, 10.2, glass)
        for z: Float in [-10.2, 10.2] {
            mrt.box(0, 8.32, z, 174, 0.25, 8.8, darkGlass)
        }
        for x in stride(from: Float(-78), through: 78, by: detail == .near ? 9 : 100) {
            for z: Float in [-10.45, 10.45] {
                mrt.box(x, 8.32, z, 0.3, 0.2, 10.0, trim)
            }
        }
        mrt.canopy(0, 18.5, 0, length: 180, width: 21.5,
                   rise: 4.5, color: roof)
        mrt.litBox(0, 18.22, -8.8, 150, 0.32, 0.16, trim)
        if detail == .near {
            for x in stride(from: Float(-72), through: 72, by: 18) {
                mrt.beam(Map3DPoint(x, 18.5, -10),
                         Map3DPoint(x, 22.7, 0), 0.25, steel)
            }
        }
        add(.flat(named: "taichung-mrt", from: mrt.mesh),
            at: Map3DPoint(-58.18, 0, 131.47), angle: -6.5481 * .pi / 180)

        for (name, at, angle, length, width) in [
            ("taichung-link-east-west", Map3DPoint(-88.87, 0, 78.69), Float(-6.4527), Float(47.6), Float(11.6)),
            ("taichung-link-north-south", Map3DPoint(-76.57, 0, 102.16), Float(84.1794), Float(32.6), Float(10.0))
        ] {
            var link = StationKitBuilder()
            link.box(0, 4.32, 0, length, width, 6.8, glass)
            link.box(0, 11.12, 0, length + 0.5, width + 0.4, 0.88, roof)
            if detail == .near {
                for x in stride(from: -length / 2 + 4, through: length / 2 - 4, by: 6) {
                    for z in [-width / 2, width / 2] {
                        link.box(x, 4.32, z, 0.25, 0.2, 6.8, steel)
                    }
                }
            }
            add(.flat(named: name, from: link.mesh), at: at,
                angle: angle * .pi / 180)
        }
    }


    mutating func tainanHSRExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let roof = Map3DColor.rgb(0xE7EBEA)
        let fascia = Map3DColor.rgb(0xD8E0DF)
        let wall = Map3DColor.rgb(0xC9D3D2)
        let glass = Map3DColor.rgb(0x9CB5B9)
        let steel = Map3DColor.rgb(0xAABABB)
        let darkGlass = Map3DColor.rgb(0x637F86)
        let shadow = Map3DColor.rgb(0x687779)

        footprint(Map3DStationExteriorBatch1.tainanHSRFootprint, color: wall)
        footprint(Map3DStationExteriorBatch1.tainanPlatformWestFootprint,
                  color: fascia, baseY: 23.68)
        footprint(Map3DStationExteriorBatch1.tainanPlatformEastFootprint,
                  color: fascia, baseY: 23.68)
        footprint(Map3DStationExteriorBatch1.shalunFootprint, color: wall)

        // The HSR relation has three levels, but no height or roof tags.
        // Low, broad metal canopy and raised central monitor follow photos;
        // 27 m is the reference display estimate, not an OSM height.
        var hall = StationKitBuilder()
        hall.box(0, 0.32, 0, 106, 43, 9.4, wall)
        hall.box(0, 9.72, 0, 108, 45, 8.5, glass)
        hall.box(0, 0.5, -22.68, 103, 0.28, 7.0, darkGlass)
        hall.canopy(0, 18.3, 0, length: 113, width: 55,
                    rise: 2.8, color: roof)
        hall.litBox(0, 18.0, -23, 91, 0.35, 0.17, fascia)
        hall.box(0, 21.0, 0, 63, 31, 5.7, fascia)
        hall.box(0, 26.7, 0, 64, 32, 0.3, roof)
        for x in stride(from: Float(-48), through: 48,
                        by: detail == .near ? 8 : 24) {
            for z: Float in [-22.9, 22.9] {
                hall.box(x, 0.32, z, 0.46, 0.46, 18, steel)
            }
            if detail == .near {
                hall.box(x, 18.4, -27.2, 0.12, 0.16, 0.75, fascia)
            }
        }
        for x in stride(from: Float(-28), through: 28,
                        by: detail == .near ? 8 : 28) {
            for z: Float in [-15.7, 15.7] {
                hall.box(x, 21, z, 0.23, 0.22, 5.7, glass)
            }
        }
        hall.box(0, 9.72, -22.9, 100, 0.2, 0.48, shadow)
        add(.flat(named: "tainan-hsr-hall", from: hall.mesh),
            at: Map3DPoint(-56.7, 0, -0.75), angle: -66.5323 * .pi / 180)

        // Two separate, long elevated canopies: relation ring and way.
        // Deck, roof height and support interval are visual estimates.
        for (name, centre, length, width, angle) in [
            ("tainan-platform-west", Map3DPoint(-4.55, 24.2, 0), Float(335.98), Float(13.98), Float(-65.0575)),
            ("tainan-platform-east", Map3DPoint(25.8, 30.3, 0), Float(331.54), Float(10.95), Float(-65.4683)),
        ] {
            var platform = StationKitBuilder()
            platform.box(0, 11.6, 0, length - 2, width - 1.5, 1.7, wall)
            platform.box(0, 13.3, 0, length - 2, width - 1.5, 0.3, shadow)
            platform.box(0, 22.2, 0, length, width, 1.8, roof)
            platform.litBox(0, 21.92, -width * 0.32, length - 24, 0.3, 0.16, fascia)
            platform.box(0, 23.7, 0, length, 0.32, 0.3, fascia)
            for x in stride(from: -length / 2 + 10, through: length / 2 - 10,
                            by: detail == .near ? 18 : 42) {
                for z in [-width * 0.32, width * 0.32] {
                    platform.box(x, 0.32, z, 0.62, 0.62, 11.28, wall)
                    platform.box(x, 13.6, z, 0.36, 0.36, 8.6, steel)
                }
                if detail == .near {
                    platform.beam(Map3DPoint(x, 21.1, -width * 0.32),
                                  Map3DPoint(x, 22.2, -width * 0.48), 0.2, shadow)
                    platform.beam(Map3DPoint(x, 21.1, width * 0.32),
                                  Map3DPoint(x, 22.2, width * 0.48), 0.2, shadow)
                }
            }
            add(.flat(named: name, from: platform.mesh),
                at: Map3DPoint(centre.x, 0, centre.y), angle: angle * .pi / 180)
        }

        // Shalun: photo shows the long pitched metal roof and window band.
        // Its 17 m peak is the reference display estimate.
        var shalun = StationKitBuilder()
        shalun.box(0, 0.32, 0, 146, 22, 6.3, wall)
        shalun.box(0, 6.62, 0, 147, 24, 6.3, glass)
        shalun.gable(0, 12.9, 0, 149, 27, 4.1, roof)
        for x in stride(from: Float(-68), through: 68,
                        by: detail == .near ? 9 : 27) {
            for z: Float in [-12.1, 12.1] {
                shalun.box(x, 6.62, z, 0.33, 0.28, 6.1, steel)
            }
        }
        shalun.box(0, 6.62, -12.3, 142, 0.2, 0.44, darkGlass)
        add(.flat(named: "shalun-station", from: shalun.mesh),
            at: Map3DPoint(19.2, 0, -114.3), angle: -65.6331 * .pi / 180)
    }

    mutating func zuoyingHSRExteriorStudy(detail: Map3DStationExteriorBatch1.LevelOfDetail) {
        let roof = Map3DColor.rgb(0xEEF1EE)
        let fascia = Map3DColor.rgb(0xDEE5E3)
        let wall = Map3DColor.rgb(0xD0D8D7)
        let steel = Map3DColor.rgb(0xB0C0C1)
        let glass = Map3DColor.rgb(0x91B7BD)
        let darkGlass = Map3DColor.rgb(0x648991)
        let truss = Map3DColor.rgb(0x667B80)

        footprint(Map3DStationExteriorBatch1.zuoyingHSRFootprint, color: wall)
        footprint(Map3DStationExteriorBatch1.xinzuoyingFootprint, color: wall)

        // Both OSM ways carry eight levels but no height or roof shape.
        // The HSR roof's 32 m crown is reference-display scale. Photos
        // supply its deep white eave, exposed steel and teal window bands.
        var hsr = StationKitBuilder()
        hsr.box(0, 0.32, 0, 177, 52, 8.7, wall)
        hsr.box(0, 9.02, 0, 178, 54, 13.7, fascia)
        for z: Float in [-27.1, 27.1] {
            hsr.box(0, 10.3, z, 172, 0.24, 2.9, glass)
            hsr.box(0, 16.2, z, 172, 0.24, 2.8, glass)
            hsr.box(0, 22.8, z, 172, 0.35, 0.7, truss)
        }
        hsr.box(0, 0.32, -27.4, 27, 0.22, 8.7, darkGlass)
        // Decision 625 續: facade cues seen from the map's camera: the
        // ground floor's dark glazing over a grey plinth, glass bands
        // round the ends, and an entrance canopy each side.
        for z: Float in [-26.2, 26.2] {
            hsr.box(0, 2.0, z, 170, 0.22, 5.2, darkGlass)
            hsr.box(0, 0.32, z, 176, 0.24, 1.2, truss)
            hsr.box(0, 7.4, z + (z < 0 ? -3.6 : 3.6), 34, 7, 0.5, truss)
        }
        for x: Float in [-89.2, 89.2] {
            hsr.box(x, 10.3, 0, 0.24, 50, 2.9, glass)
            hsr.box(x, 16.2, 0, 0.24, 50, 2.8, glass)
            hsr.box(x * 0.994, 2.0, 0, 0.22, 48, 5.2, darkGlass)
        }
        hsr.canopy(0, 26.5, 0, length: 186, width: 80,
                   rise: 5.5, color: roof)
        hsr.litBox(0, 26.2, -33, 160, 0.36, 0.18, fascia)
        for x in stride(from: Float(-82), through: 82,
                        by: detail == .near ? 13.6 : 41) {
            for z: Float in [-29.5, 29.5] {
                hsr.box(x, 0.32, z, 0.85, 0.85, 24.4, steel)
                if detail == .near {
                    hsr.beam(Map3DPoint(x, 23.8, z),
                             Map3DPoint(x, 26.5, z.sign == .minus ? -39 : 39),
                             0.28, truss)
                }
            }
        }
        if detail == .near {
            for x in stride(from: Float(-80), through: 80, by: 16) {
                for side: Float in [-1, 1] {
                    hsr.beam(Map3DPoint(x, 23.4, side * 27),
                             Map3DPoint(x + 3.5, 26.5, side * 37),
                             0.22, steel)
                }
            }
        }
        for x in stride(from: Float(-80), through: 80,
                        by: detail == .near ? 10 : 32) {
            for z: Float in [-27.35, 27.35] {
                hsr.box(x, 10.3, z, 0.22, 0.14, 8.7, steel)
            }
        }
        add(.flat(named: "zuoying-hsr-hall", from: hsr.mesh),
            at: Map3DPoint(14.1, 0, -19.96), angle: 42.4015 * .pi / 180)

        // New Zuoying's long white slab is lower and flatter. Skylight
        // strips and the front colonnade are photo-based approximations.
        var tra = StationKitBuilder()
        tra.box(0, 0.32, 0, 158, 47, 8.2, wall)
        tra.box(0, 8.52, 0, 160, 50, 13.5, fascia)
        for z: Float in [-25.15, 25.15] {
            tra.box(0, 11.5, z, 155, 0.24, 2.8, glass)
            tra.box(0, 17.5, z, 155, 0.24, 2.2, glass)
            tra.box(0, 22.02, z, 156, 0.28, 0.55, truss)
        }
        tra.box(0, 0.32, -25.4, 26, 0.22, 8.2, darkGlass)
        for z: Float in [-23.7, 23.7] {
            tra.box(0, 2.0, z, 150, 0.22, 4.8, darkGlass)
            tra.box(0, 0.32, z, 157, 0.24, 1.1, truss)
            tra.box(0, 7.0, z + (z < 0 ? -3.4 : 3.4), 30, 6.6, 0.5, truss)
        }
        tra.box(0, 24.5, 0, 170, 68, 1.5, roof)
        if detail == .near {
            for x in stride(from: Float(-70), through: 70, by: 17.5) {
                tra.box(x, 26.01, 0, 2.1, 46, 0.10, glass)
            }
        } else {
            for x in stride(from: Float(-63), through: 63, by: 42) {
                tra.box(x, 26.01, 0, 2.1, 46, 0.10, glass)
            }
        }
        for x in stride(from: Float(-72), through: 72,
                        by: detail == .near ? 12 : 36) {
            for z: Float in [-27, 27] {
                tra.box(x, 0.32, z, 0.82, 0.82, 23.7, steel)
                if detail == .near {
                    tra.beam(Map3DPoint(x, 22.2, z),
                             Map3DPoint(x, 24.5, z.sign == .minus ? -33 : 33),
                             0.22, truss)
                }
            }
        }
        for x in stride(from: Float(-72), through: 72,
                        by: detail == .near ? 10 : 30) {
            for z: Float in [-25.4, 25.4] {
                tra.box(x, 11.5, z, 0.24, 0.14, 8.2, steel)
            }
        }
        add(.flat(named: "xinzuoying-station", from: tra.mesh),
            at: Map3DPoint(-30.7, 0, 37.04), angle: 42.2875 * .pi / 180)
    }
}
