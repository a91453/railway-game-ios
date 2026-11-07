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
        b.mesh = clippedForRailClearance(b.mesh, station: station)
        return .flat(named: "station-exterior-batch2-\(station.rawValue)-\(detail == .near ? "near" : "far")", from: b.mesh)
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
                    let endHeight=min(rise,(width/2-abs(zz-z))*rise/(width*0.17))
                    beam(Map3DPoint(x-length*0.45,y+0.12,zz),Map3DPoint(x,y+endHeight+0.12,zz),0.055,color)
                    beam(Map3DPoint(x,y+endHeight+0.12,zz),Map3DPoint(x+length*0.45,y+0.12,zz),0.055,color)
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
    mutating func timberSiding(_ x: Float,_ y: Float,_ z: Float,_ depth: Float,_ span: Float,_ color: UInt32, detail: Detail) {
        guard detail == .near else { return }
        // Repeated boards across the two long walls, plus corner posts.
        for i in 0..<22 {
            let zz=z-span/2+(Float(i)+0.5)*span/22
            for side: Float in [-1,1] {
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
                beam(Map3DPoint(x-18,6.3,zz),Map3DPoint(x+18,10.5,zz),0.16,dark)
            }
            for side: Float in [-1,1] { for i in 0..<9 { box(x+side*16,0,z-21+Float(i)*42/8,0.30,0.30,6.2,steel) } }
        }
        roofDetail(x,8.25,z,37,49,steel,detail:detail)
        eaveLights(x+14.8,6.9,z,45,detail:detail)
    }
    mutating func keelungNorth(_ detail: Detail) {
        let x:Float = 87,z:Float = 118,steel=rgb(0xBFCACD),dark=rgb(0x4D5B60)
        box(x,0,z,35,62,6.5,rgb(0xD6DCDD))
        windows(x+17.6,1.5,z,50,count:13,glass:rgb(0x78A2AC),frame:steel,detail:detail)
        // North entrance has a light steel-and-glass elliptical canopy over a lower masonry base.
        canopy(x,8.5,z,length:60,width:70,rise:1.5,color:rgb(0xC7D9DA))
        if detail == .near {
            for i in 0..<18 {
                let zz=z-30+Float(i)*60/17
                beam(Map3DPoint(x-24,8,zz),Map3DPoint(x+24,8,zz),0.13,dark)
            }
            for side: Float in [-1,1] { for i in 0..<7 { box(x+side*18,0,z-28+Float(i)*56/6,0.35,0.35,7.8,steel) } }
        }
        eaveLights(x+18,6.5,z,55,detail:detail)
        roofDetail(x,8.5,z,50,62,steel,detail:detail)
    }
    mutating func keelungOld(_ detail: Detail) {
        let x:Float = 18,z:Float = -80
        box(x,0,z,23,32,7,rgb(0xD1C8B7))
        studyHip(x,7,z,26,35,2.2,rgb(0x55585B))
        windows(x+11.6,1.4,z,26,count:7,glass:rgb(0x9AB4B4),frame:rgb(0xEEE9DD),detail:detail)
        roofDetail(x,7,z,23,32,rgb(0x6B6E70),detail:detail)
    }
    mutating func chiayi1933(_ detail: Detail) {
        let x:Float = -40,z:Float = -82, ivory=rgb(0xE8DECB),ochre=rgb(0xB89968),red=rgb(0x985747)
        box(x,0,z,26,52,8,ivory)
        studyHip(x,8,z,30,56,2.4,red)
        archRow(x+13.2,0.8,z,43,count:7,stone:ochre,glass:rgb(0x9EBCBA),detail:detail)
        // Central square clock tower rises above the red tiled hipped wings.
        box(x+9,0,z,18,16,14,ivory)
        studyHip(x+9,14,z,20,18,2,red)
        clockFace(x+18.2,11,z,size:2.6)
        windows(x+18.2,6.5,z,12,count:3,glass:rgb(0x9DB8B9),frame:ochre,tall:3.0,detail:detail)
        if detail == .near {
            for i in 0..<21 { let zz=z-25+Float(i)*50/20; box(x-12,0.5,zz,0.15,0.12,7.5,ochre) }
        }
        roofDetail(x,8.1,z,27,52,rgb(0xA96A57),detail:detail,rise:2.4,hipped:true)
        eaveLights(x+13.2,5.1,z,45,detail:detail)
    }
    mutating func tainan1936(_ detail: Detail) {
        let white=rgb(0xE8E7DF),trim=rgb(0xB7B7AE),glass=rgb(0x9FB5B6),roof=rgb(0x737A78)
        for (x,z,span) in [(-205 as Float,50 as Float,30 as Float),(-212,-10,37)] {
            box(x,0,z,25,span,10,white)
            box(x,10,z,27,span+2,0.4,roof)
            archRow(x+12.7,0.8,z,span-3,count:span>35 ? 6:5,stone:trim,glass:glass,detail:detail)
            windows(x+12.6,6.0,z,span-4,count:span>35 ? 7:6,glass:glass,frame:trim,tall:2.5,detail:detail)
            if detail == .near {
                for i in 0..<14 { let zz=z-span/2+(Float(i)+0.5)*span/14;box(x-12.6,0,zz,0.16,0.14,9,trim) }
            }
            eaveLights(x+12.8,4.5,z,span-2,detail:detail)
        }
        // A recessed central hall joins the two mapped 1936 station wings.
        box(-208,0,21,25,30,10,white)
        box(-208,10,21,26,31,0.4,roof)
        archRow(-195.3,0.8,21,26,count:4,stone:trim,glass:glass,detail:detail)
        windows(-195.2,6,21,26,count:5,glass:glass,frame:trim,tall:2.5,detail:detail)
        eaveLights(-195.1,4.5,21,27,detail:detail)
        // The white, two-storey 1936 frontage has a restrained raised central hall.
        box(-203,10,50,12,13,2,white)
        clockFace(-196.8,10.6,50,size:1.8)
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
        let x:Float=29,z:Float = -1,green=rgb(0x718370),dark=rgb(0x3E4740),frame=rgb(0xC3C7AF)
        box(x,0,z,18,22,5,green)
        gable(x,5,z,21,25,2.5,dark)
        windows(x+9.1,1.1,z,16,count:5,glass:rgb(0xA9C3BD),frame:frame,tall:2.6,detail:detail)
        // Hinoki gable end and projecting eave are the landmark silhouette.
        if detail == .near {
            for i in 0..<7 { let zz=z-11+Float(i)*22/6;box(x+10,0,zz,0.35,0.35,5,frame) }
            beam(Map3DPoint(x+10,5,z-11),Map3DPoint(x+10,7.5,z),0.25,frame)
            beam(Map3DPoint(x+10,7.5,z),Map3DPoint(x+10,5,z+11),0.25,frame)
        }
        timberSiding(x,0,z,18,22,dark,detail:detail)
        roofDetail(x,5.2,z,19,23,rgb(0x59635A),detail:detail,rise:2.5)
        eaveLights(x+9.5,4.8,z,19,detail:detail)
    }
    mutating func fenqihuTimber(_ detail: Detail) {
        let x:Float=21,z:Float = -7,wood=rgb(0x917257),dark=rgb(0x464547)
        box(x,0,z,18,21,5.6,wood)
        studyHip(x,5.6,z,21,25,1.8,dark)
        windows(x+9.1,1.4,z,18,count:6,glass:rgb(0xAFBFAD),frame:rgb(0xC7B295),detail:detail)
        // Separate narrow platform shelter with an open underside and repeated timber posts.
        canopy(x-13,5.8,z,length:9,width:31,rise:0.25,color:rgb(0x77746D))
        for i in 0..<(detail == .near ? 9 : 4) { let zz=z-14+Float(i)*28/Float(detail == .near ? 8:3);box(x-15,0,zz,0.3,0.3,5.6,wood) }
        timberSiding(x,0,z,18,21,rgb(0x70553E),detail:detail)
        roofDetail(x,5.7,z,19,23,rgb(0x616063),detail:detail,rise:1.8,hipped:true)
        eaveLights(x+9.4,5,z,20,detail:detail)
    }
    mutating func alishanCurrent(_ detail: Detail) {
        let x:Float = -2,z:Float=9,concrete=rgb(0xD2D4CF),timber=rgb(0x815C48),roof=rgb(0x5C4845)
        box(x,0,z,34,52,8.5,concrete)
        archRow(x+17.2,0.7,z,43,count:7,stone:concrete,glass:rgb(0x9BAEAA),detail:detail)
        // Two separate front gables sit side by side; their roofs do not overlap.
        for side: Float in [-1,1] {
            let zz=z+side*13
            for xx in [x-12,x+12] { for dz in [-9 as Float,9] { box(xx,8.5,zz+dz,0.45,0.45,6,timber) } }
            gable(x,14.5,zz,29,21,4.2,roof)
            windows(x+14.6,10.3,zz,14,count:4,glass:rgb(0xA6B4AA),frame:timber,tall:3.3,detail:detail)
            roofDetail(x,14.6,zz,27,20,rgb(0x7B5E52),detail:detail,rise:4.2)
        }
        if detail == .near {
            for side: Float in [-1,1] { let zz=z+side*13
                beam(Map3DPoint(x+14.6,14.5,zz-9),Map3DPoint(x+14.6,18.7,zz),0.35,timber)
                beam(Map3DPoint(x+14.6,18.7,zz),Map3DPoint(x+14.6,14.5,zz+9),0.35,timber)
            }
        }
        eaveLights(x+17.4,7.8,z,46,detail:detail)
    }
    mutating func wushulinSugar(_ detail: Detail) {
        let x:Float=0,z:Float=0,wall=rgb(0xD2D1C5),roof=rgb(0x404A4B),green=rgb(0x54766B)
        box(x,0,z,12,34,4.8,wall)
        gable(x,4.8,z,16,38,1.6,roof)
        windows(x+6.1,1.2,z,28,count:9,glass:rgb(0xA6C1B2),frame:green,detail:detail)
        canopy(x+8,4,z,length:6,width:39,rise:0.2,color:roof)
        for i in 0..<(detail == .near ? 11 : 4) {let zz=z-18+Float(i)*36/Float(detail == .near ? 10:3);box(x+10,0,zz,0.35,0.35,4,green)}
        timberSiding(x,0,z,12,34,green,detail:detail)
        roofDetail(x,4.9,z,15,36,rgb(0x66706B),detail:detail,rise:1.6)
        eaveLights(x+6.2,4.3,z,31,detail:detail)
    }
    mutating func xihuSugar(_ detail: Detail) {
        let x:Float=0,z:Float=0,wall=rgb(0xD4B685),roof=rgb(0x65534C),frame=rgb(0x6C866F)
        box(x,0,z,17,25,5.1,wall)
        studyHip(x,5.1,z,20,29,1.7,roof)
        windows(x+8.6,1.1,z,20,count:6,glass:rgb(0xA7C3BA),frame:frame,detail:detail)
        // Xihu's open boarding shed is deeper and offset from the small ticket room.
        canopy(x-13,4.8,z+5,length:10,width:35,rise:0.35,color:rgb(0xAAA58E))
        for i in 0..<(detail == .near ? 10 : 4) {let zz=z-11+Float(i)*33/Float(detail == .near ? 9:3);box(x-16,0,zz,0.36,0.36,4.8,frame)}
        timberSiding(x,0,z,17,25,rgb(0x9E7957),detail:detail)
        roofDetail(x,5.2,z,19,27,rgb(0x806B5B),detail:detail,rise:1.7,hipped:true)
        eaveLights(x+8.7,4.5,z,23,detail:detail)
    }
    mutating func qiaotouSugar(_ detail: Detail) {
        let x:Float = -10,z:Float=51,brick=rgb(0xB87665),roof=rgb(0x454D50),glass=rgb(0x91B1B6)
        // OSM way 112644875 spans roughly 86 x 144 m at layer=1: do not cap it to a 25 m hut.
        // Keep the whole elevated envelope above the 5.5 m train clearance.
        box(x,8,z,48,134,10,brick)
        windows(x+24.1,10,z,122,count:22,glass:glass,frame:rgb(0xCFB5A7),tall:4,detail:detail)
        canopy(x,18,z,length:57,width:143,rise:1.4,color:roof)
        if detail == .near {
            for i in 0..<28 { let zz=z-67+Float(i)*134/27;box(x+24.4,8,zz,0.23,0.23,10,rgb(0x695C59)) }
            for i in 0..<16 { let zz=z-65+Float(i)*130/15;beam(Map3DPoint(x-26,17,zz),Map3DPoint(x+26,19,zz),0.15,rgb(0x707C7C)) }
        }
        roofDetail(x,18,z,52,140,rgb(0x717A7A),detail:detail)
        eaveLights(x+24.3,17,z,132,detail:detail)
        // The photographed sugar-rail ticket office and open shelter sit beside
        // the much larger MRT station. Their plan position and sizes are estimates.
        let boothX:Float=32, boothZ:Float=25
        box(boothX,0,boothZ,10,13,4.2,rgb(0xA95D4B))
        box(boothX,4.2,boothZ,11,14,0.35,rgb(0xC7C7BA))
        windows(boothX+5.2,1.0,boothZ,10,count:3,glass:rgb(0xB8CAC9),frame:rgb(0xE5D6C3),tall:2.3,detail:detail)
        box(boothX+5.4,3.6,boothZ,0.18,10,0.5,rgb(0x5E635D))
        canopy(boothX+12,4.1,boothZ+14,length:8,width:39,rise:0.2,color:rgb(0xBEC6C1))
        for i in 0..<(detail == .near ? 11:4) {
            let zz=boothZ-4+Float(i)*36/Float(detail == .near ? 10:3)
            box(boothX+15,0,zz,0.38,0.38,4.1,rgb(0x716B5F))
        }
        eaveLights(boothX+14,3.8,boothZ+14,35,detail:detail)
    }
}
