import Foundation

/// Isolated exterior studies; the live station catalog never references this type.
public enum Map3DStationExteriorBatch2 {
    public enum LevelOfDetail: Sendable { case near, far }
    public enum Station: String, CaseIterable, Sendable {
        case keelung = "keelung"
        case chiayi = "chiayi"
        case tainan = "tainan"
        case beimen = "beimen"
        case fenqihu = "fenqihu"
        case alishan = "alishan"
        case wushulin = "wushulin"
        case xihu = "xihu"
        case qiaotou = "qiaotou"
    }
    // Local east/north metres from the documented longitude/latitude origin.
    // Extracted from osmtoday asia/taiwan.pbf on 2026-11-07 with pyosmium.
    // © OpenStreetMap contributors, ODbL 1.0.
    static let keelungOrigin: (Double, Double) = (121.73923, 25.13303)
    // way 929730121; height=none, levels=none, roof=none.
    static let way929730121: [(Float, Float)] = [
        (-106.928, -155.080),
        (-95.691, -162.082),
        (-89.917, -165.678),
        (-84.968, -157.518),
        (-81.521, -151.607),
        (-80.242, -149.770),
        (-78.821, -147.933),
        (-77.349, -146.174),
        (-75.908, -144.638),
        (-74.588, -143.358),
        (-73.388, -142.367),
        (-72.330, -141.477),
        (-71.151, -140.519),
        (-70.032, -139.651),
        (-68.863, -138.838),
        (-67.775, -137.992),
        (-66.777, -137.180),
        (-65.790, -136.311),
        (-65.114, -135.577),
        (-64.217, -134.586),
        (-63.653, -133.796),
        (-63.099, -132.894),
        (-62.655, -132.048),
        (-62.282, -131.213),
        (-61.960, -130.278),
        (-61.708, -129.265),
        (-61.547, -128.307),
        (-61.446, -127.439),
        (-61.386, -126.671),
        (-61.345, -125.803),
        (-61.355, -124.845),
        (-61.416, -124.122),
        (-61.476, -123.387),
        (-61.577, -122.652),
        (-61.768, -121.740),
        (-61.980, -120.927),
        (-62.192, -120.159),
        (-62.494, -119.168),
        (-62.887, -118.211),
        (-63.300, -117.331),
        (-63.845, -116.396),
        (-64.530, -115.483),
        (-65.376, -114.548),
        (-66.223, -113.691),
        (-67.221, -112.834),
        (-68.269, -112.055),
        (-69.347, -111.365),
        (-70.456, -110.730),
        (-71.625, -110.229),
        (-72.502, -109.906),
        (-73.439, -109.639),
        (-74.306, -109.439),
        (-75.172, -109.305),
        (-76.039, -109.216),
        (-76.785, -109.172),
        (-77.652, -109.205),
        (-78.508, -109.305),
        (-79.375, -109.439),
        (-80.322, -109.639),
        (-81.360, -109.929),
        (-82.449, -110.296),
        (-83.416, -110.663),
        (-84.374, -111.120),
        (-85.260, -111.576),
        (-86.248, -112.211),
        (-87.085, -112.856),
        (-87.830, -113.558),
        (-88.616, -114.404),
        (-89.272, -115.227),
        (-89.896, -116.096),
        (-90.481, -116.964),
        (-91.045, -117.877),
        (-91.610, -118.957),
        (-91.983, -119.858),
        (-92.265, -120.671),
        (-92.497, -121.439),
        (-92.708, -122.307),
        (-92.859, -123.153),
        (-92.980, -123.988),
        (-93.121, -124.901),
        (-93.303, -126.203),
        (-93.625, -127.740),
        (-94.038, -129.421),
        (-94.593, -131.257),
        (-95.318, -133.395),
        (-96.094, -135.354),
        (-97.072, -137.603),
        (-97.959, -139.584),
        (-98.896, -141.499),
    ]
    // way 1069178919; height=none, levels=none, roof=none.
    static let way1069178919: [(Float, Float)] = [
        (98.221, 159.388),
        (70.940, 136.100),
        (55.157, 109.906),
        (54.200, 108.325),
        (53.726, 106.878),
        (53.504, 105.620),
        (53.555, 104.474),
        (54.008, 102.938),
        (55.046, 100.644),
        (56.488, 98.195),
        (57.586, 96.470),
        (58.574, 94.733),
        (59.410, 93.052),
        (60.025, 91.227),
        (60.206, 89.691),
        (59.813, 87.319),
        (78.619, 75.998),
        (79.597, 100.166),
        (95.560, 104.273),
        (105.245, 120.916),
        (120.120, 146.475),
    ]
    // way 367861777; height=none, levels=3, roof=none.
    static let way367861777: [(Float, Float)] = [
        (22.111, -56.918),
        (37.007, -66.024),
        (14.563, -102.771),
        (-0.050, -93.843),
    ]
    static let chiayiOrigin: (Double, Double) = (120.44158, 23.4799)
    // way 286891391; height=none, levels=none, roof=none.
    static let way286891391: [(Float, Float)] = [
        (-11.936, -66.458),
        (-24.831, -55.515),
        (-27.394, -53.333),
        (-69.236, -102.637),
        (-63.794, -107.279),
        (-62.058, -108.726),
        (-59.465, -110.919),
        (-48.642, -98.173),
        (-41.107, -104.574),
        (-33.612, -95.746),
        (-25.138, -85.761),
        (-26.986, -84.180),
        (-24.525, -81.286),
    ]
    static let tainanOrigin: (Double, Double) = (120.21332, 22.99714)
    // way 204493488; height=none, levels=none, roof=none.
    static let way204493488: [(Float, Float)] = [
        (-183.795, 61.048),
        (-184.779, 66.547),
        (-191.245, 66.002),
        (-199.760, 63.809),
        (-207.559, 60.102),
        (-214.670, 54.847),
        (-220.378, 48.647),
        (-224.036, 43.025),
        (-226.957, 36.613),
        (-221.690, 34.142),
        (-217.273, 42.725),
        (-209.721, 51.196),
        (-203.675, 55.471),
        (-197.158, 58.532),
        (-189.626, 60.502),
    ]
    // way 204493489; height=none, levels=none, roof=none.
    static let way204493489: [(Float, Float)] = [
        (-227.520, 10.464),
        (-222.018, 10.909),
        (-219.691, 1.391),
        (-214.865, -8.995),
        (-207.559, -18.557),
        (-203.070, -22.754),
        (-196.676, -27.340),
        (-199.320, -31.348),
        (-206.001, -27.151),
        (-212.580, -21.407),
        (-220.265, -11.399),
        (-225.266, -0.301),
    ]
    // way 1568887226; height=none, levels=2, roof=none.
    static let way1568887226: [(Float, Float)] = [
        (-23.343, -38.083),
        (2.500, -42.457),
        (10.760, 6.323),
        (-15.074, 10.698),
    ]
    // way 1568933253; height=none, levels=none, roof=none.
    static let way1568933253: [(Float, Float)] = [
        (51.236, 394.084),
        (90.268, 387.015),
        (-5.441, -141.321),
        (-44.473, -134.252),
    ]
    static let beimenOrigin: (Double, Double) = (120.45438, 23.48763)
    // way 353120128; height=none, levels=none, roof=none.
    static let way353120128: [(Float, Float)] = [
        (17.111, 0.178),
        (20.726, -9.963),
        (40.798, -1.625),
        (36.959, 8.304),
    ]
    static let fenqihuOrigin: (Double, Double) = (120.69492, 23.50534)
    // way 444296747; height=none, levels=none, roof=none.
    static let way444296747: [(Float, Float)] = [
        (8.820, -8.416),
        (21.478, 5.154),
        (33.330, -5.900),
        (20.672, -19.470),
    ]
    static let alishanOrigin: (Double, Double) = (120.80434, 23.51)
    // way 344586161; height=none, levels=none, roof=none.
    static let way344586161: [(Float, Float)] = [
        (-25.009, -21.184),
        (-30.981, -15.240),
        (0.439, 16.297),
        (-5.594, 22.309),
        (9.616, 37.582),
        (13.883, 33.329),
        (20.263, 39.719),
        (27.429, 32.583),
    ]
    static let wushulinOrigin: (Double, Double) = (120.37378, 23.32866)
    static let xihuOrigin: (Double, Double) = (120.481765, 23.95205)
    static let qiaotouOrigin: (Double, Double) = (120.31468, 22.75303)
    // way 112644875; height=none, levels=none, roof=none.
    static let way112644875: [(Float, Float)] = [
        (-53.197, 113.079),
        (13.171, -20.861),
        (32.624, -11.221),
        (-33.743, 122.719),
    ]

    public static func model(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        switch station {
        case .keelung:
            b.studyOutline(way929730121, elevation: 0)
            b.studyBuilding(way929730121, elevation: 0, wood: false, detail: detail)
            b.studyOutline(way1069178919, elevation: 0)
            b.studyBuilding(way1069178919, elevation: 0, wood: false, detail: detail)
            b.studyOutline(way367861777, elevation: 0)
            b.studyBuilding(way367861777, elevation: 0, wood: false, detail: detail)
            b.studyCanopy(way929730121, elevation: 8, detail: detail)
            b.studyCanopy(way1069178919, elevation: 8, detail: detail)
        case .chiayi:
            b.studyOutline(way286891391, elevation: 0)
            b.studyBuilding(way286891391, elevation: 0, wood: false, flat: true, detail: detail)
            b.studyClock(way286891391, detail: detail)
        case .tainan:
            b.studyOutline(way204493488, elevation: 0)
            b.studyBuilding(way204493488, elevation: 0, wood: false, flat: true, detail: detail)
            b.studyOutline(way204493489, elevation: 0)
            b.studyBuilding(way204493489, elevation: 0, wood: false, flat: true, detail: detail)
            b.studyClock(way204493488, detail: detail)
            b.studyOutline(way1568887226, elevation: 0)
            b.studyBuilding(way1568887226, elevation: 0, wood: false, detail: detail)
            b.studyOutline(way1568933253, elevation: 8)
            b.studyCanopy(way1568933253, elevation: 8, detail: detail)
        case .beimen:
            b.studyOutline(way353120128, elevation: 0)
            b.studyBuilding(way353120128, elevation: 0, wood: true, greenWood: true, detail: detail)
        case .fenqihu:
            b.studyOutline(way444296747, elevation: 0)
            b.studyBuilding(way444296747, elevation: 0, wood: true, detail: detail)
        case .alishan:
            b.studyOutline(way344586161, elevation: 0)
            b.studyBuilding(way344586161, elevation: 0, wood: false, flat: true, detail: detail)
            b.studyUpperHall(way344586161, detail: detail)
        case .wushulin:
            b.studyBuilding(at: 0, north: 0, length: 22, width: 10, wood: true, detail: detail) // OSM has a station point but no building outline.
        case .xihu:
            b.studyBuilding(at: 0, north: 0, length: 18, width: 11, wood: true, detail: detail) // OSM has a station point but no building outline.
        case .qiaotou:
            b.studyOutline(way112644875, elevation: 8)
            b.studyBuilding(way112644875, elevation: 8, wood: true, detail: detail)
        }
        return .flat(named: "station-exterior-batch2-\(station.rawValue)-\(detail == .near ? "near" : "far")", from: b.mesh)
    }
}

private extension StationKitBuilder {
    mutating func studyClock(_ points: [(Float, Float)], detail: Map3DStationExteriorBatch2.LevelOfDetail) {
        guard detail == .near else { return }
        let xs = points.map(\.0), zs = points.map(\.1)
        guard let hiX = xs.max(), let loZ = zs.min(), let hiZ = zs.max() else { return }
        let z = (loZ + hiZ) / 2
        box(hiX - 3, 8.5, z, 6, 7, 3.8, Map3DColor.rgb(0xD7D2C5))
        clockFace(hiX + 0.1, 10.9, z, size: 2.2)
    }
    mutating func studyUpperHall(_ points: [(Float, Float)], detail: Map3DStationExteriorBatch2.LevelOfDetail) {
        let xs = points.map(\.0), zs = points.map(\.1)
        guard let loX = xs.min(), let hiX = xs.max(), let loZ = zs.min(), let hiZ = zs.max() else { return }
        let x = (loX + hiX) / 2, z = (loZ + hiZ) / 2
        let timber = Map3DColor.rgb(0x76513F)
        for side: Float in [-1, 1] {
            let zz = z + side * 10
            gable(x, 12.5, zz, 25, 18, 4.2, timber)
            for xx in [x - 10, x + 10] {
                box(xx, 8.5, zz - 7, 0.35, 0.35, 4, timber)
                box(xx, 8.5, zz + 7, 0.35, 0.35, 4, timber)
            }
        }
    }
    mutating func studyOutline(_ points: [(Float, Float)], elevation: Float) {
        // Vertical ground-colour edges retain every OSM vertex; no filled ground polygon.
        for i in points.indices {
            let a = points[i], c = points[(i + 1) % points.count]
            let p = Map3DPoint(a.0, elevation + 0.32, a.1)
            let q = Map3DPoint(c.0, elevation + 0.32, c.1)
            mesh.addQuad(p, q, Map3DPoint(c.0, elevation, c.1), Map3DPoint(a.0, elevation, a.1), color: Map3DPalette.ground)
        }
    }
    mutating func studyBuilding(_ points: [(Float, Float)], elevation: Float, wood: Bool, flat: Bool = false, greenWood: Bool = false, detail: Map3DStationExteriorBatch2.LevelOfDetail) {
        let xs = points.map(\.0), zs = points.map(\.1)
        guard let loX = xs.min(), let hiX = xs.max(), let loZ = zs.min(), let hiZ = zs.max() else { return }
        studyBuilding(at: (loX + hiX) / 2, north: (loZ + hiZ) / 2, length: min(hiX - loX, 56), width: min(hiZ - loZ, 25), elevation: elevation, wood: wood, flat: flat, greenWood: greenWood, detail: detail)
    }
    mutating func studyBuilding(at x: Float, north z: Float, length: Float, width: Float, elevation: Float = 0, wood: Bool, flat: Bool = false, greenWood: Bool = false, detail: Map3DStationExteriorBatch2.LevelOfDetail) {
        let wall: UInt32 = Map3DColor.rgb(greenWood ? 0x758A7B : wood ? 0x9A7658 : 0xD7D2C5)
        let roof: UInt32 = Map3DColor.rgb(wood ? 0x44444A : 0x5A6769)
        let h: Float = wood ? 5.4 : 8.5
        let l = max(length - 2, 8), w = max(width - 2, 7)
        box(x, elevation, z, l, w, h, wall)
        if flat { box(x, elevation + h, z, l + 2, w + 2, 0.3, roof) }
        else { hip(x, elevation + h, z, l + 2, w + 2, wood ? 2.0 : 2.8, roof) }
        // The kit marks the glass itself as emissive for night renderers.
        let count = detail == .near ? 5 : 2
        for i in 0..<count {
            let zz = z - w * 0.40 + w * 0.80 * (Float(i) + 0.5) / Float(count)
            let start = mesh.vertices.count
            box(x + l / 2 + 0.03, elevation + 1.4, zz, 0.10, min(w / Float(count) * 0.52, 3.2), 2.4, Map3DPalette.glazing)
            mesh.makeGlowing(from: start)
        }
        if detail == .near {
            for sign: Float in [-1, 1] {
                for i in 0..<4 {
                    let xx = x - l * 0.38 + l * 0.76 * Float(i) / 3
                    cylinder(xx, elevation, z + sign * (w / 2 + 0.65), radius: 0.17, height: h, color: wood ? Map3DColor.rgb(0x715238) : Map3DPalette.concrete, sides: 6)
                }
            }
        }
    }
    mutating func studyCanopy(_ points: [(Float, Float)], elevation: Float, detail: Map3DStationExteriorBatch2.LevelOfDetail) {
        let xs = points.map(\.0), zs = points.map(\.1)
        guard let loX = xs.min(), let hiX = xs.max(), let loZ = zs.min(), let hiZ = zs.max() else { return }
        let x = (loX + hiX) / 2, z = (loZ + hiZ) / 2
        canopy(x, elevation + 5, z, length: min(hiX - loX, 80), width: min(hiZ - loZ, 30), rise: 1.6, color: Map3DColor.rgb(0xD5DAD8))
        if detail == .near {
            let start = mesh.vertices.count
            box(x, elevation + 3.2, z, min(hiX - loX, 60), 0.4, 0.18, Map3DPalette.glazing)
            mesh.makeGlowing(from: start)
        }
    }
}
