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

    public static func model(for station: Station, detail: LevelOfDetail, includeContext: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        switch station {
        case .keelung:
            b.studyOutline(way929730121, elevation: 0)
            b.studyOutline(way1069178919, elevation: 0)
            b.studyOutline(way367861777, elevation: 0)
            b.keelungSouth(detail)
            b.keelungNorth(detail)
            b.keelungOld(detail)
        case .chiayi:
            b.studyOutline(way286891391, elevation: 0)
            b.chiayi1933(detail)
        case .tainan:
            b.studyOutline(way204493488, elevation: 0)
            b.studyOutline(way204493489, elevation: 0)
            b.studyOutline(way1568887226, elevation: 0)
            b.studyOutline(way1568933253, elevation: 8)
            b.tainan1936(detail)
            b.tainanUndergroundEntrance(detail)
        case .beimen:
            b.studyOutline(way353120128, elevation: 0)
            b.beimenTimber(detail)
        case .fenqihu:
            b.studyOutline(way444296747, elevation: 0)
            b.fenqihuTimber(detail)
        case .alishan:
            b.studyOutline(way344586161, elevation: 0)
            b.alishanCurrent(detail)
        case .wushulin: b.wushulinSugar(detail)
        case .xihu: b.xihuSugar(detail)
        case .qiaotou:
            b.studyOutline(way112644875, elevation: 8)
            b.qiaotouSugar(detail)
        }
        if includeContext { b.optionalContext(station,detail:detail) }
        b.mesh = clippedForRailClearance(b.mesh, station: station)
        let suffix=detail == .near ? "near" : "far"
        return .flat(named: "station-exterior-batch2-\(station.rawValue)-\(includeContext ? "scene-" : "")\(suffix)", from: b.mesh)
    }

    /// Optional display context stays separate from the station body model.
    /// No map selection or saved game references these pieces.
    public static func contextModel(for station: Station, detail: LevelOfDetail) -> Map3DModelPack.Model? {
        guard [.alishan,.wushulin,.qiaotou].contains(station) else { return nil }
        var b=StationKitBuilder()
        b.optionalContext(station,detail:detail)
        b.mesh=clippedForRailClearance(b.mesh,station:station)
        return .flat(named:"station-exterior-batch2-\(station.rawValue)-context-\(detail == .near ? "near" : "far")",from:b.mesh)
    }

    // Surface track and platform edges from the same 2026-11-07 OSM PBF, in each station's metres.
    // Tainan's new platforms and tracks are underground and do not constrain its surface entrance.
    static func clearancePaths(for station: Station) -> [[(Float, Float)]] {
        switch station {
        case .keelung: return [
            [(-72.6,-127.0),(-67.6,-130.0),(50.6,70.7),(45.5,73.6)], // platforms 525611054
            [(-57.3,-135.8),(-62.2,-132.8),(57.2,67.4),(62.2,64.4)], // 525611064
        ]
        case .chiayi: return [
            [(97.6,118.6),(99.9,116.7),(17.4,17.0),(23.4,12.0),(19.2,7.0),(10.1,-4.0),(-94.0,-129.8),(-102.3,-123.0)], // platform 286891395
            [(98.2,123.6),(4.4,8.2),(-121.6,-141.4)], // rail 374524088, local section
            [(-124.7,-138.9),(96.1,125.5)], // rail 518370754, local section
        ]
        case .tainan: return []
        case .beimen: return [[(-24.0,15.0),(32.3,39.9),(35.1,33.5),(-21.1,8.5)]] // platform 1283227169
        case .fenqihu: return [
            [(26.1,15.9),(-48.9,-61.1)], // platform 320332839
            [(23.6,5.8),(6.1,-11.6),(-3.0,-21.0),(-8.8,-27.0)], // platform 444714191
        ]
        case .alishan: return [[(44.4,49.9),(48.2,46.1),(-36.0,-40.2),(-39.9,-36.4),(-25.0,-21.2),(27.4,32.6)]] // platform 1138466088
        case .wushulin, .xihu: return [] // OSM has only station nodes here
        case .qiaotou: return [[(-43.5,124.4),(17.5,1.5),(8.2,-3.1),(-52.8,119.8)]] // elevated platform 1316259255; model starts at 8 m
        }
    }

    static func clippedForRailClearance(_ mesh: Map3DMesh, station: Station) -> Map3DMesh {
        let paths = clearancePaths(for: station)
        guard !paths.isEmpty else { return mesh }
        var kept = Map3DMesh()
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[i + $0])] }
            let ground = triangle.map { ($0.x, $0.z) }
            let hits = triangle.map(\.y).min()! < 5.5 && paths.contains { path in
                path.indices.dropLast().contains { j in
                    triangleTouchesCorridor(ground, path[j], path[j + 1], radius: 2.2)
                }
            }
            if !hits { kept.appendTriangle(triangle) }
        }
        return kept
    }

    static func triangleTouchesCorridor(_ t: [(Float, Float)], _ a: (Float, Float), _ b: (Float, Float), radius: Float) -> Bool {
        func cross(_ p: (Float,Float), _ q: (Float,Float), _ r: (Float,Float)) -> Float {
            (q.0-p.0)*(r.1-p.1)-(q.1-p.1)*(r.0-p.0)
        }
        func distance(_ p: (Float,Float), _ u: (Float,Float), _ v: (Float,Float)) -> Float {
            let dx=v.0-u.0, dy=v.1-u.1
            let f=max(0,min(1,((p.0-u.0)*dx+(p.1-u.1)*dy)/max(dx*dx+dy*dy,0.0001)))
            let x=p.0-u.0-f*dx, y=p.1-u.1-f*dy
            return x*x+y*y
        }
        func inside(_ p: (Float,Float)) -> Bool {
            guard abs(cross(t[0],t[1],t[2])) > 0.0001 else { return false }
            let c=(0..<3).map { cross(t[$0],t[($0+1)%3],p) }
            return c.allSatisfy { $0 >= 0 } || c.allSatisfy { $0 <= 0 }
        }
        if inside(a) || inside(b) { return true }
        for j in 0..<3 {
            let u=t[j], v=t[(j+1)%3]
            if cross(a,b,u)*cross(a,b,v) <= 0 && cross(u,v,a)*cross(u,v,b) <= 0 { return true }
            if min(distance(u,a,b),distance(v,a,b),distance(a,u,v),distance(b,u,v)) < radius*radius { return true }
        }
        return false
    }
}

private extension StationKitBuilder {
    typealias Detail = Map3DStationExteriorBatch2.LevelOfDetail
    func rgb(_ n: UInt32) -> UInt32 { Map3DColor.rgb(n) }
    mutating func lit(_ x: Float,_ y: Float,_ z: Float,_ l: Float,_ w: Float,_ h: Float,_ color: UInt32) {
        let start = mesh.vertices.count
        box(x,y,z,l,w,h,color)
        mesh.makeGlowing(from:start)
    }
    mutating func studyHip(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ rise: Float,_ color: UInt32) {
        let halfL=length/2+0.4, halfW=width/2+0.4
        let a=Map3DPoint(x+halfL,y,z-halfW), b=Map3DPoint(x+halfL,y,z+halfW)
        let c=Map3DPoint(x-halfL,y,z+halfW), d=Map3DPoint(x-halfL,y,z-halfW)
        let inside=Map3DPoint(x,y-1,z)
        if halfL >= halfW {
            let ridge=halfL-halfW
            let rf=Map3DPoint(x+ridge,y+rise,z), rb=Map3DPoint(x-ridge,y+rise,z)
            face([rf,b,a],inside:inside,color:color)
            face([rf,rb,c,b],inside:inside,color:Map3DColor.shaded(color,0.94))
            face([rb,d,c],inside:inside,color:Map3DColor.shaded(color,0.82))
            face([rb,rf,a,d],inside:inside,color:Map3DColor.shaded(color,0.88))
        } else {
            let ridge=halfW-halfL
            let rp=Map3DPoint(x,y+rise,z+ridge), rn=Map3DPoint(x,y+rise,z-ridge)
            face([rp,b,c],inside:inside,color:color)
            face([rp,rn,d,c],inside:inside,color:Map3DColor.shaded(color,0.94))
            face([rn,d,a],inside:inside,color:Map3DColor.shaded(color,0.82))
            face([rn,rp,b,a],inside:inside,color:Map3DColor.shaded(color,0.88))
        }
        box(x,y-0.12,z,length+0.8,width+0.8,0.12,color)
    }
    mutating func studyGable(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ rise: Float,_ roof: UInt32,_ gableWall: UInt32) {
        mesh.addGableRoof(base:Map3DPoint(x,y,z),forward:Self.forward,length:length,width:width,rise:rise,overhang:0.35,color:roof,gable:gableWall)
        box(x,y-0.12,z,length+0.7,width+0.7,0.12,roof)
    }
    mutating func studyLongGable(_ x: Float,_ y: Float,_ z: Float,depth: Float,span: Float,rise: Float,roof: UInt32,gableWall: UInt32) {
        // The roof ridge follows the long platform-facing facade (local z).
        mesh.addGableRoof(base:Map3DPoint(x,y,z),forward:Map3DPoint(0,0,1),length:span,width:depth,rise:rise,overhang:0.7,color:roof,gable:gableWall)
        box(x,y-0.12,z,depth+1.4,span+1.4,0.12,roof)
    }
    mutating func studyOutline(_ points: [(Float, Float)], elevation: Float) {
        // OpenStreetMap survey edges: no opaque ground pad. Elevated parts stay above train clearance.
        for i in points.indices {
            let a = points[i], c = points[(i + 1) % points.count]
            mesh.addQuad(Map3DPoint(a.0,elevation+0.32,a.1),Map3DPoint(c.0,elevation+0.32,c.1),
                         Map3DPoint(c.0,elevation,c.1),Map3DPoint(a.0,elevation,a.1),color:Map3DPalette.ground)
        }
    }
    mutating func windows(_ front: Float,_ y: Float,_ z: Float, _ span: Float, count: Int, glass: UInt32, frame: UInt32, tall: Float = 2.4, detail: Detail) {
        for i in 0..<count {
            let zz = z - span/2 + span*(Float(i)+0.5)/Float(count)
            let width = span/Float(count)*0.62
            box(front,y-0.12,zz,0.18,width+0.28,tall+0.24,frame)
            lit(front+0.12,y,zz,0.06,width,tall,glass)
            if detail == .near {
                box(front+0.18,y+tall*0.51,zz,0.08,width+0.12,0.09,frame)
                box(front+0.18,y,zz,0.08,0.08,tall,frame)
            }
        }
    }
    mutating func archedWindows(_ front: Float,_ y: Float,_ z: Float,_ span: Float,count: Int,tall: Float,glass: UInt32,frame: UInt32,detail: Detail) {
        let spacing=span/Float(count),width=spacing*0.58,arch=min(0.9,width*0.48)
        for i in 0..<count {
            let zz=z-span/2+(Float(i)+0.5)*spacing
            if detail == .far {
                box(front,y-0.10,zz,0.16,width+0.20,tall+0.10,frame)
                lit(front+0.10,y,zz,0.05,width,tall,glass)
                continue
            }
            lit(front,y,zz,0.10,width,tall-arch,glass)
            let top=y+tall-arch
            let arc=(0...4).map { k -> Map3DPoint in
                let t=Float(k)/4
                return Map3DPoint(front+0.11,top+arch*sinf(t*Float.pi),zz-width/2+t*width)
            }
            let start=mesh.vertices.count
            face(arc,inside:Map3DPoint(front-1,top,zz),color:glass)
            mesh.makeGlowing(from:start)
            for side: Float in [-1,1] { box(front+0.13,y,zz+side*width/2,0.18,0.16,tall-arch,frame) }
            box(front+0.14,y-0.10,zz,0.18,width+0.35,0.17,frame)
            if detail == .near { for j in 0..<4 { beam(arc[j],arc[j+1],0.17,frame) } }
        }
    }
    mutating func roundWindow(_ front: Float,_ y: Float,_ z: Float,radius: Float,frame: UInt32,glass: UInt32) {
        let ring=(0..<12).map { k -> Map3DPoint in
            let a=Float(k)*2*Float.pi/12
            return Map3DPoint(front,y+sinf(a)*radius,z+cosf(a)*radius)
        }
        let start=mesh.vertices.count
        face(ring,inside:Map3DPoint(front-1,y,z),color:glass)
        mesh.makeGlowing(from:start)
        for i in ring.indices { beam(ring[i]+Map3DPoint(0.05,0,0),ring[(i+1)%ring.count]+Map3DPoint(0.05,0,0),0.15,frame) }
    }
    mutating func stationSign(_ front: Float,_ y: Float,_ z: Float,width: Float,board: UInt32 = Map3DColor.rgb(0xEDEFE9),ink: UInt32 = Map3DColor.rgb(0x285588)) {
        box(front,y,z,0.22,width,0.88,board)
        for i in 0..<6 {
            let zz=z-width*0.39+Float(i)*width*0.156
            box(front+0.14,y+0.22,zz,0.06,width*0.065,0.37,ink)
        }
    }
    mutating func roofNameTiles(_ front: Float,_ y: Float,_ z: Float,span: Float) {
        let blue=rgb(0x24558C),white=rgb(0xF5F3E8)
        for i in 0..<5 {
            let zz=z-span*0.40+Float(i)*span*0.17
            box(front,y,zz,0.35,span*0.135,1.55,white)
            box(front+0.22,y+0.42,zz,0.06,span*0.075,0.72,blue)
        }
        let englishZ=z+span*0.47
        box(front,y,englishZ,0.30,span*0.25,1.15,white)
        for i in 0..<5 { box(front+0.19,y+0.40,englishZ-span*0.09+Float(i)*span*0.044,0.05,span*0.022,0.32,blue) }
    }
    mutating func singleSlopeShelter(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,rise: Float,color: UInt32,detail: Detail) {
        let a=Map3DPoint(x-length/2,y+rise,z-width/2),b=Map3DPoint(x-length/2,y+rise,z+width/2)
        let c=Map3DPoint(x+length/2,y,z+width/2),d=Map3DPoint(x+length/2,y,z-width/2)
        face([a,b,c,d],inside:Map3DPoint(x,y-1,z),color:color)
        face([d,c,b,a].map { $0-Map3DPoint(0,0.18,0) },inside:Map3DPoint(x,y+1,z),color:Map3DColor.shaded(color,0.78))
        if detail == .near {
            for i in 0..<16 {
                let zz=z-width/2+(Float(i)+0.5)*width/16
                beam(Map3DPoint(x-length/2,y+rise+0.025,zz),Map3DPoint(x+length/2,y+0.025,zz),0.045,Map3DColor.shaded(color,0.88))
            }
        }
    }
    mutating func archRow(_ front: Float,_ y: Float,_ z: Float, _ span: Float, count: Int, stone: UInt32, glass: UInt32, detail: Detail) {
        for i in 0..<count {
            let dz = span/Float(count), centre = z-span/2+(Float(i)+0.5)*dz
            let side = dz*0.34
            box(front,y,centre-side,0.6,0.55,3.2,stone)
            box(front,y,centre+side,0.6,0.55,3.2,stone)
            let start = mesh.vertices.count
            box(front+0.04,y+0.1,centre,0.10,dz*0.53,2.55,glass)
            mesh.makeGlowing(from:start)
            if detail == .near {
                // Five short voussoirs give the arcade a visible arch rather than a flat lintel.
                let q: [(Float,Float)] = [(-side,3.05),(-side*0.8,3.55),(-side*0.36,3.83),(side*0.36,3.83),(side*0.8,3.55),(side,3.05)]
                for k in 0..<5 {
                    beam(Map3DPoint(front+0.3,y+q[k].1,centre+q[k].0),
                         Map3DPoint(front+0.3,y+q[k+1].1,centre+q[k+1].0),0.20,stone)
                }
            } else { box(front,y+3.0,centre,0.7,dz,0.38,stone) }
        }
    }
    mutating func roofDetail(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ color: UInt32, detail: Detail, rise: Float = 0, hipped: Bool = false) {
        guard detail == .near else { return }
        // Tile ribs follow the roof planes. Flat horizontal bars used to poke through pitched roofs.
        for i in 0..<20 {
            let xx=x-length/2+(Float(i)+0.5)*length/20
            if rise > 0 {
                if hipped && width > length {
                    let zz=z-width/2+(Float(i)+0.5)*width/20
                    // Small tile ends stay on the eaves. Long beams projected
                    // above a hipped silhouette as a row of floating poles.
                    for side: Float in [-1,1] {
                        box(x+side*length*0.49,y-0.26,zz,0.16,0.13,0.16,color)
                    }
                } else {
                    let endHeight = hipped ? min(rise, (length/2-abs(xx-x))*rise/(length*0.17)) : rise
                    let a=Map3DPoint(xx,y+0.12,z-width*0.45)
                    let b=Map3DPoint(xx,y+max(0,endHeight)+0.12,z)
                    let c=Map3DPoint(xx,y+0.12,z+width*0.45)
                    beam(a,b,0.055,color)
                    beam(b,c,0.055,color)
                }
            } else {
                box(xx,y+0.08,z,0.055,width*0.9,0.07,color)
            }
        }
        for i in 0..<12 {
            let xx=x-length/2+(Float(i)+0.5)*length/12
            for side: Float in [-1,1] {
                box(xx,y-0.35,z+side*width/2,0.16,0.32,0.38,color)
            }
        }
    }
    mutating func timberSiding(_ x: Float,_ y: Float,_ z: Float,_ depth: Float,_ span: Float,_ color: UInt32, detail: Detail,rear: Bool = true) {
        guard detail == .near else { return }
        // Repeated boards across the two long walls, plus corner posts.
        for i in 0..<22 {
            let zz=z-span/2+(Float(i)+0.5)*span/22
            for side: Float in (rear ? [-1,1] : [1]) {
                box(x+side*depth/2,y,zz,0.10,0.055,4.1,color)
            }
        }
        for zz in [z-span/2,z+span/2] {
            for xx in [x-depth/2,x+depth/2] { box(xx,y,zz,0.36,0.36,4.9,color) }
        }
    }
    mutating func eaveLights(_ x: Float,_ y: Float,_ z: Float,_ span: Float, detail: Detail) {
        for i in 0..<(detail == .near ? 14 : 6) {
            let zz=z-span/2+(Float(i)+0.5)*span/Float(detail == .near ? 14 : 6)
            lit(x,y,zz,0.14,0.65,0.10,Map3DPalette.glazing)
        }
    }
    mutating func keelungSouth(_ detail: Detail) {
        let x:Float = -84, z:Float = -137, steel=rgb(0xB8C5C9), dark=rgb(0x42525A)
        box(x,0,z,30,46,7,rgb(0xE0E5E4))
        windows(x+15.1,1.5,z,39,count:12,glass:rgb(0x8CACB4),frame:steel,detail:detail)
        canopy(x,8.2,z,length:43,width:54,rise:2.8,color:rgb(0xD4DEE0))
        if detail == .near {
            for i in 0..<12 {
                let zz=z-23+Float(i)*46/11
                beam(Map3DPoint(x-18,6.35,zz),Map3DPoint(x+18,7.45,zz),0.16,dark)
            }
            for side: Float in [-1,1] { for i in 0..<9 { box(x+side*16,0,z-21+Float(i)*42/8,0.30,0.30,6.2,steel) } }
        }
        stationSign(x+15.4,6.1,z,width:24)
        eaveLights(x+14.8,6.9,z,45,detail:detail)
    }
    mutating func keelungNorth(_ detail: Detail) {
        let x:Float = 87,z:Float = 118,steel=rgb(0xBFCACD),dark=rgb(0x4D5B60)
        box(x,0,z,35,62,7.4,rgb(0xA7AFB1))
        box(x+17.7,0,z,0.24,62,1.8,rgb(0x8B969B))
        windows(x+17.6,2.0,z,50,count:13,glass:rgb(0x78A2AC),frame:steel,tall:3.3,detail:detail)
        // The photographed north entrance has a glazed barrel canopy in
        // front of its stone wall, with ribs and cross members on the curve.
        let canopyX=x+15
        canopy(canopyX,7.5,z,length:34,width:68,rise:3.4,color:rgb(0xA9CDD1))
        if detail == .near {
            for i in 0..<8 {
                let zz=z-31+Float(i)*62/7
                let yy=7.5+3.4*sinf((zz-z+34)/68*Float.pi)+0.08
                beam(Map3DPoint(canopyX-17,yy,zz),Map3DPoint(canopyX+17,yy,zz),0.16,dark)
            }
            for xx: Float in [canopyX-11,canopyX,canopyX+11] {
                for i in 0..<12 {
                    let za=z-34+Float(i)*68/12,zb=z-34+Float(i+1)*68/12
                    let ya=7.5+3.4*sinf(Float(i)*Float.pi/12)+0.10
                    let yb=7.5+3.4*sinf(Float(i+1)*Float.pi/12)+0.10
                    beam(Map3DPoint(xx,ya,za),Map3DPoint(xx,yb,zb),0.14,dark)
                }
            }
        }
        for zz in [z-29,z+29] { box(canopyX+16.5,0,zz,0.56,0.56,7.55,steel) }
        stationSign(x+17.9,5.25,z,width:34,board:rgb(0xE0E3E3),ink:rgb(0x245697))
        box(x+18.0,3.5,z,0.30,27,0.35,rgb(0xC9823D))
        eaveLights(x+18,6.5,z,55,detail:detail)
    }
    mutating func keelungOld(_ detail: Detail) {
        let x:Float = 18,z:Float = -80
        box(x,0,z,23,32,7,rgb(0xD1C8B7))
        // The small OSM old-station outline remains; its unverified dark hip
        // used to appear as an isolated triangle in the south close-up.
        box(x,7,z,25,34,0.28,rgb(0xD1C8B7))
        windows(x+11.6,1.4,z,26,count:7,glass:rgb(0x9AB4B4),frame:rgb(0xEEE9DD),detail:detail)
    }
    mutating func chiayi1933(_ detail: Detail) {
        let x:Float = -40,z:Float = -82, ivory=rgb(0xEDE5D2),ochre=rgb(0xC9922E),cap=rgb(0xB58D53)
        box(x,0,z,26,52,8,ivory)
        box(x,8,z,27,53,0.28,cap)
        for side: Float in [-1,1] { box(x+side*13.1,8.28,z,0.55,53,1.2,ivory) }
        for side: Float in [-1,1] { box(x,8.28,z+side*26.1,27,0.55,1.2,ivory) }
        archRow(x+13.2,0.8,z,43,count:7,stone:ochre,glass:rgb(0x9EBCBA),detail:detail)
        // The 2021 photo has five tall upper arches and a clock under a row of
        // roof name tiles, on a raised flat central mass.
        box(x+9,0,z,18,16,14,ivory)
        box(x+9,14,z,19,17,0.3,cap)
        for side: Float in [-1,1] { box(x+9+side*9.1,14.3,z,0.55,17,0.9,ivory) }
        for side: Float in [-1,1] { box(x+9,14.3,z+side*8.1,19,0.55,0.9,ivory) }
        archedWindows(x+18.2,7.2,z,15,count:5,tall:4.9,glass:rgb(0x9DB8B9),frame:ochre,detail:detail)
        roundWindow(x+18.4,13.25,z,radius:0.78,frame:ochre,glass:rgb(0xF4F2E8))
        roofNameTiles(x+18.1,15.1,z,span:17)
        box(x+18.25,0,z-8.0,0.30,0.35,14,ochre)
        box(x+18.25,0,z+8.0,0.30,0.35,14,ochre)
        box(x+18.4,12.25,z,0.22,16.2,0.22,ochre)
        box(x+18.3,14.0,z,0.30,17.5,0.25,ochre)
        box(x+18.3,15.0,z,0.22,0.22,3.4,rgb(0x777B78))
        if detail == .near {
            for i in 0..<21 { let zz=z-25+Float(i)*50/20; box(x-12,0.5,zz,0.15,0.12,7.5,ochre) }
            for i in 0..<18 { let zz=z-25+Float(i)*50/17;box(x+13.5,8.5,zz,0.15,0.18,0.7,ochre) }
        }
        // Deep flat entrance portico at the first-floor head, not a thin bar
        // slicing through the upper facade.
        box(x+20,4.65,z,8,24,0.55,rgb(0xC5BFAF))
        box(x+24.1,4.77,z,0.22,24,0.32,ochre)
        eaveLights(x+23.8,4.45,z,21,detail:detail)
    }
    mutating func tainan1936(_ detail: Detail) {
        let white=rgb(0xF2F0EA),trim=rgb(0xDBDAD3),pink=rgb(0xD7C3B9),glass=rgb(0x9FB5B6)
        let x:Float = -208,z:Float = 20
        for wingZ: Float in [-4,44] {
            box(x,0,wingZ,25,26,11,white)
            box(x+12.62,0,wingZ,0.20,26,1.0,pink)
            archRow(x+12.7,0.7,wingZ,22,count:4,stone:trim,glass:glass,detail:detail)
            archedWindows(x+12.75,6.3,wingZ,22,count:5,tall:4.0,glass:glass,frame:white,detail:detail)
            box(x,11,wingZ,26,27,0.26,white)
            box(x+12.8,11.1,wingZ,0.46,27.5,0.32,trim)
            box(x+14.0,4.65,wingZ,3.6,25,0.34,white)
            box(x+15.9,4.72,wingZ,0.22,25,0.22,trim)
            eaveLights(x+15.6,4.30,wingZ,23,detail:detail)
        }
        // The 2006 front photo: a higher centre, three large entrance arches,
        // bullseye windows and a dense row of tall second-floor arches.
        box(x,0,z,27,22,14,white)
        box(x+13.65,0,z,0.22,22,1.0,pink)
        archRow(x+13.8,0.8,z,14,count:3,stone:white,glass:glass,detail:detail)
        for side: Float in [-1,1] { roundWindow(x+13.85,2.65,z+side*9.3,radius:0.78,frame:trim,glass:glass) }
        archedWindows(x+13.85,7.0,z,18,count:4,tall:5.2,glass:glass,frame:white,detail:detail)
        box(x,14,z,28,23,0.30,white)
        box(x+13.9,14.3,z,0.50,23.5,0.36,trim)
        box(x+16.8,4.82,z,6.0,21,0.46,white)
        box(x+19.9,4.95,z,0.28,21,0.34,pink)
        if detail == .near {
            for zz in [z-8,z+8] { beam(Map3DPoint(x+13.9,3.7,zz),Map3DPoint(x+19.4,4.8,zz),0.22,trim) }
        }
        roofNameTiles(x+13.8,14.75,z,span:20)
        box(x+13.8,14.4,z,0.16,0.16,3.6,rgb(0x717A78))
        eaveLights(x+19.5,4.45,z,18,detail:detail)
    }
    mutating func tainanUndergroundEntrance(_ detail: Detail) {
        let x:Float = -6,z:Float = -16,white=rgb(0xE9EEEB),glass=rgb(0x86A9AF)
        // Surface entrance belongs beside the underground platforms; no slab across rail tracks.
        box(x,0,z,22,38,6,white)
        windows(x+11.1,0.9,z,32,count:9,glass:glass,frame:rgb(0xCAD8D8),tall:3.8,detail:detail)
        canopy(x,6.3,z,length:27,width:46,rise:1.2,color:rgb(0xDCE7E5))
        if detail == .near { for i in 0..<10 { box(x+12.5,0,z-18+Float(i)*4,0.28,0.28,6,rgb(0xC9D3D1)) } }
        eaveLights(x+11,5.8,z,37,detail:detail)
    }
    mutating func beimenTimber(_ detail: Detail) {
        let x:Float=29,z:Float = -1,green=rgb(0x526B5B),dark=rgb(0x363D39),frame=rgb(0xF0F0E5)
        box(x,0,z,18,22,4.5,green)
        studyLongGable(x,4.5,z,depth:20,span:24,rise:3.8,roof:dark,gableWall:green)
        windows(x+9.1,1.25,z,18,count:6,glass:rgb(0xA9C3BD),frame:frame,tall:2.35,detail:detail)
        // Rows of slender white-framed openings continue around all four walls.
        for i in 0..<6 {
            let zz=z-9+(Float(i)+0.5)*18/6
            box(x-9.15,1.14,zz,0.16,2.25,2.65,frame)
            lit(x-9.27,1.25,zz,0.05,2.0,2.35,rgb(0xA9C3BD))
        }
        for side: Float in [-1,1] {
            for xx in [x-5,x,x+5] {
                box(xx,1.15,z+side*11.12,1.8,0.15,2.65,frame)
                lit(xx,1.28,z+side*11.22,1.55,0.05,2.35,rgb(0xA9C3BD))
            }
        }
        for side: Float in [-1,1] { box(x+side*9.15,1.04,z,0.18,21.5,0.18,frame) }
        for side: Float in [-1,1] { box(x,1.04,z+side*11.12,17.8,0.18,0.18,frame) }
        if detail == .near {
            for i in 0..<20 {
                let zz=z-10+(Float(i)+0.5)
                for side: Float in [-1,1] { box(x+side*9.7,4.22,zz,0.16,0.10,0.20,rgb(0x505A52)) }
            }
        }
        box(x,8.27,z,0.22,21,0.22,rgb(0x222B27))
        stationSign(x+9.3,3.70,z,width:12)
        timberSiding(x,0,z,18,22,rgb(0x405446),detail:detail)
        eaveLights(x+9.4,4.20,z,19,detail:detail)
    }
    mutating func fenqihuTimber(_ detail: Detail) {
        // The photographed wall follows the diagonal OSM footprint beside
        // the platform. Keep the study near that footprint; the broad roof
        // clears trains above 5.5 m instead of losing a whole clipped facet.
        let x:Float=21,z:Float = -7,wood=rgb(0x858784),dark=rgb(0x697973),frame=rgb(0xEDEDE8)
        box(x,0,z,18,21,5.6,wood)
        studyHip(x,5.6,z,20,23,2.5,dark)
        windows(x+9.1,1.3,z,18,count:6,glass:rgb(0xAFC2BF),frame:frame,tall:2.5,detail:detail)
        if detail == .near {
            // Wall boards stay attached to the surviving front facade, unlike
            // the old clipped rear siding and roof tile tips.
            for i in 0..<54 {
                let zz=z-10+(Float(i)+0.5)*20/54
                box(x+9.08,0.25,zz,0.10,0.07,4.45,rgb(0x747B78))
            }
        }
        // The 2023 platform shelter is fully in front of the main eave;
        // old rear siding boxes were clipped into unsupported rods.
        canopy(x+13,3.75,z,length:6,width:25,rise:0.12,color:rgb(0x77746D))
        for i in 0..<(detail == .near ? 8 : 4) { let zz=z-11.5+Float(i)*23/Float(detail == .near ? 7:3);box(x+15.4,0,zz,0.34,0.34,3.55,rgb(0x666863)) }
        timberSiding(x,0,z,18,21,rgb(0x69716E),detail:detail,rear:false)
        box(x,8.05,z,0.22,3,0.18,rgb(0x475651))
        stationSign(x+9.4,4.72,z,width:11)
        eaveLights(x+9.4,5.30,z,18,detail:detail)
    }
    mutating func alishanCurrent(_ detail: Detail) {
        let x:Float = -2,z:Float=9,concrete=rgb(0xD2D4CF),timber=rgb(0x815C48),roof=rgb(0x5C4845)
        // The photograph has a closed concrete ground storey with three
        // recessed entrances. The upper timber terrace sits on this volume.
        // The lower front is slightly ahead of the upper platform. Its
        // shorter facade leaves the mapped platform corridor behind it.
        let lowerX=x+11,lowerZ=z-9,lowerFront=lowerX+17.15
        box(lowerX,0,lowerZ,34,38,8.5,concrete)
        box(x,8.1,z,34,52,0.4,concrete)
        for zz in [lowerZ-12,lowerZ,lowerZ+12] {
            box(lowerFront,0.4,zz,0.18,9.2,6.2,rgb(0x75817F))
            lit(lowerFront+0.12,1.0,zz,0.08,8.2,3.8,rgb(0xA8B6AF))
            for side: Float in [-1,1] { box(lowerFront+0.24,0.3,zz+side*4.5,0.24,0.25,6.2,concrete) }
            box(lowerFront+0.24,6.3,zz,0.24,9.4,0.30,concrete)
        }
        stationSign(lowerFront+0.4,7.12,lowerZ,width:19,board:rgb(0xE7E4D8),ink:rgb(0x795341))
        // Two separate front gables sit side by side; their roofs do not overlap.
        for side: Float in [-1,1] {
            let zz=z+side*13
            for xx in [x-12,x+12] { for dz in [-9 as Float,9] { box(xx,8.5,zz+dz,0.45,0.45,6,timber) } }
            studyGable(x,14.5,zz,29,21,4.2,roof,timber)
            // The photographed upper level is an open timber truss and railing,
            // not a wall with windows suspended below the two roofs.
            box(x+14.6,9.2,zz,0.35,19,0.22,timber)
            box(x+14.6,10.6,zz,0.35,19,0.22,timber)
            box(x+14.6,14.35,zz,0.45,19,0.30,timber)
            let lampCount=detail == .near ? 7 : 4
            for i in 0..<lampCount {
                let lampZ=zz-7.5+Float(i)*15/Float(lampCount-1)
                lit(x+14.95,10.7,lampZ,0.25,0.8,0.7,Map3DPalette.glazing)
            }
            beam(Map3DPoint(x+14.6,14.5,zz-9),Map3DPoint(x+14.6,18.7,zz),0.35,timber)
            beam(Map3DPoint(x+14.6,18.7,zz),Map3DPoint(x+14.6,14.5,zz+9),0.35,timber)
            beam(Map3DPoint(x+14.7,14.5,zz),Map3DPoint(x+14.7,18.7,zz),0.28,timber)
            beam(Map3DPoint(x+14.7,16.5,zz),Map3DPoint(x+14.7,14.5,zz-7.5),0.22,timber)
            beam(Map3DPoint(x+14.7,16.5,zz),Map3DPoint(x+14.7,14.5,zz+7.5),0.22,timber)
            for i in 0..<4 {
                let a=zz-9+Float(i)*4.5, b=a+4.5
                box(x+14.6,8.5,a,0.28,0.28,2.1,timber)
                if detail == .near {
                    beam(Map3DPoint(x+14.6,9.3,a),Map3DPoint(x+14.6,10.6,b),0.16,timber)
                    beam(Map3DPoint(x+14.6,10.6,a),Map3DPoint(x+14.6,9.3,b),0.16,timber)
                }
            }
            roofDetail(x,14.6,zz,27,20,rgb(0x7B5E52),detail:detail,rise:4.2)
        }
        if detail == .near {
            for side: Float in [-1,1] { let zz=z+side*13
                beam(Map3DPoint(x+14.6,14.5,zz-9),Map3DPoint(x+14.6,14.5,zz+9),0.30,timber)
                beam(Map3DPoint(x+14.6,14.5,zz-9),Map3DPoint(x+14.6,16.6,zz),0.24,timber)
                beam(Map3DPoint(x+14.6,16.6,zz),Map3DPoint(x+14.6,14.5,zz+9),0.24,timber)
            }
        }
        // Continuous lighting is fixed to the concrete soffit above the
        // entrance bays, rather than glazing floating in the open concourse.
        lit(x+15.1,7.84,z,0.25,46,0.24,Map3DPalette.glazing)
        eaveLights(x+15.2,7.8,z,46,detail:detail)
    }
    mutating func wushulinSugar(_ detail: Detail) {
        let x:Float=0,z:Float=0,wall=rgb(0x604637),roof=rgb(0x3D4445),blue=rgb(0x8DAFB6)
        box(x,0,z,12,34,4.8,wall)
        studyLongGable(x,4.8,z,depth:14,span:36,rise:3.4,roof:roof,gableWall:wall)
        windows(x+6.1,1.35,z,28,count:9,glass:rgb(0xA6C1B2),frame:rgb(0xEFEFE7),tall:2.4,detail:detail)
        box(x+6.15,0.75,z,0.22,32,0.55,blue)
        box(x+6.2,2.5,z,0.20,32,0.16,rgb(0x806755))
        canopy(x+9,3.85,z,length:5,width:36,rise:0.15,color:roof)
        for i in 0..<(detail == .near ? 11 : 5) {let zz=z-16.5+Float(i)*33/Float(detail == .near ? 10:4);box(x+11.3,0,zz,0.34,0.34,3.65,blue)}
        timberSiding(x,0,z,12,34,rgb(0x49352C),detail:detail)
        box(x,8.17,z,0.24,21,0.25,rgb(0x272C2D))
        stationSign(x+7.2,5.0,z,width:12,board:rgb(0xE7E1D1))
        eaveLights(x+6.2,4.3,z,30,detail:detail)
    }
    mutating func xihuSugar(_ detail: Detail) {
        // Confirmed 2020 photo of the restored *station itself*: dark wood
        // framing, pale infill and a long low timber boarding veranda.
        let x:Float=0,z:Float=0,wall=rgb(0x664B3F),roof=rgb(0x53443D),frame=rgb(0x694B3D)
        box(x,0,z,17,28,4.4,wall)
        box(x+8.52,0,z,0.16,27,0.90,rgb(0xA6A49B))
        box(x+8.53,3.25,z,0.16,27,0.85,rgb(0xE9E4D4))
        studyHip(x,4.4,z,19,30,2.3,roof)
        windows(x+8.6,1.18,z,25,count:8,glass:rgb(0x9FAFA9),frame:frame,tall:2.35,detail:detail)
        canopy(x+14,4.05,z,length:10,width:34,rise:0.14,color:rgb(0x6F5948))
        for i in 0..<(detail == .near ? 10 : 5) {
            let zz=z-16+Float(i)*32/Float(detail == .near ? 9:4)
            box(x+18.2,0,zz,0.34,0.34,3.85,frame)
            if detail == .near { beam(Map3DPoint(x+18.2,3.3,zz),Map3DPoint(x+13.8,4.0,zz),0.16,frame) }
        }
        timberSiding(x,0,z,17,28,rgb(0x4E392F),detail:detail)
        roofDetail(x,4.5,z,18,28,rgb(0x725B4E),detail:detail,rise:2.3,hipped:true)
        stationSign(x+8.8,3.54,z,width:10,board:rgb(0xC69B70),ink:rgb(0x543A2D))
        eaveLights(x+8.7,4.0,z,25,detail:detail)
    }
    mutating func qiaotouSugar(_ detail: Detail) {
        let x:Float = -10,z:Float=51,concrete=rgb(0xADB8BC),roof=rgb(0xAFC8CB),glass=rgb(0x91B1B6)
        // OSM way 112644875 spans roughly 86 x 144 m at layer=1: do not cap it to a 25 m hut.
        // Keep the whole elevated envelope above the 5.5 m train clearance.
        box(x,8,z,58,140,0.8,rgb(0x899A9E))
        box(x,8.8,z,48,134,9.2,concrete)
        windows(x+24.1,10,z,122,count:22,glass:glass,frame:rgb(0xC7D4D4),tall:4,detail:detail)
        canopy(x,18,z,length:55,width:140,rise:3.0,color:roof)
        for zz in stride(from:z-55,through:z+55,by:Float(22)) {
            for xx in [x-25,x+25] { box(xx,0,zz,1.8,1.8,8,rgb(0x919FA1)) }
        }
        if detail == .near {
            for i in 0..<20 {
                let zz=z-64+Float(i)*128/19
                let yy=18+3*sinf((zz-z+70)/140*Float.pi)+0.06
                beam(Map3DPoint(x-27,yy,zz),Map3DPoint(x+27,yy,zz),0.18,rgb(0x75888D))
            }
        }
        stationSign(x+24.4,15.6,z,width:43,board:rgb(0xE7EBE8),ink:rgb(0x286090))
        eaveLights(x+24.3,17,z,132,detail:detail)
        // The photographed sugar-rail ticket office and open shelter sit beside
        // the much larger MRT station. Their plan position and sizes are estimates.
        let boothX:Float=32, boothZ:Float=25
        box(boothX,0,boothZ,10,13,4.2,rgb(0xA95D4B))
        box(boothX,4.2,boothZ,11,14,0.35,rgb(0xC7C7BA))
        box(boothX+5.12,1.12,boothZ,0.16,7.5,2.15,rgb(0xDDD5C9))
        lit(boothX+5.25,1.26,boothZ,0.08,7.0,1.8,rgb(0xA8C0C0))
        box(boothX+5.35,1.05,boothZ,0.25,8.0,0.22,rgb(0xD6C8B6))
        stationSign(boothX+5.3,3.20,boothZ,width:10,board:rgb(0xA64E42),ink:rgb(0xF3F0E4))
        singleSlopeShelter(boothX+9.5,3.72,boothZ+15,length:7,width:30,rise:0.15,color:rgb(0xBEC6C1),detail:detail)
        for i in 0..<(detail == .near ? 9:4) {
            let zz=boothZ+1+Float(i)*28/Float(detail == .near ? 8:3)
            box(boothX+12.7,0,zz,0.38,0.38,3.55,rgb(0x59605C))
        }
        box(boothX+5.8,3.42,boothZ+8.0,1.8,0.24,0.24,rgb(0x727976))
        eaveLights(boothX+11.8,3.45,boothZ+15,28,detail:detail)
    }
    mutating func optionalContext(_ station: Map3DStationExteriorBatch2.Station,detail: Detail) {
        switch station {
        case .alishan:
            let x:Float = -2,z:Float = -8,stone=rgb(0xA9ACA9),wood=rgb(0x865F4D)
            // A wide separate stair reaches the upper terrace. It is not a
            // ground pad in the station body and is omitted by default.
            for i in 0..<12 {
                let xx=x+15.4+Float(i)*1.42
                box(xx,0,z,1.42,33,8.12-Float(i)*0.64,stone)
            }
            for side: Float in [-1,1] {
                let zz=z+side*16.5
                beam(Map3DPoint(x+15,9.0,zz),Map3DPoint(x+31,1.5,zz),0.22,wood)
                if detail == .near {
                    for i in 0..<7 { box(x+15.5+Float(i)*2.3,0.8,z+side*16.5,0.28,0.28,7.4-Float(i)*1.0,wood) }
                }
            }
        case .wushulin:
            let blue=rgb(0x83AFBD)
            box(13,0,0,3.4,36,0.28,rgb(0xB2A99A))
            box(14.7,1.12,0,0.16,35,0.12,blue)
            for i in 0..<(detail == .near ? 13:7) {
                let zz:Float = -17+Float(i)*34/Float(detail == .near ? 12:6)
                box(14.7,0.28,zz,0.16,0.16,0.88,blue)
            }
        case .qiaotou:
            box(47,0,40,3.4,31,0.28,rgb(0xA7AAA5))
            box(48.7,1.14,40,0.16,30,0.12,rgb(0x8B765F))
            for i in 0..<(detail == .near ? 11:5) {
                let zz:Float = 25+Float(i)*30/Float(detail == .near ? 10:4)
                box(48.7,0.28,zz,0.16,0.16,0.88,rgb(0x8B765F))
            }
        default: break
        }
    }
}
