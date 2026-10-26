import Foundation

/// Photo-based automatic-door Chu-Kuang study; no engineering or operational-series claim.
/// Independently proportioned shell, window stations, roof and underframe.
public enum Map3DChuKuangPassenger {
    public enum Role: String, CaseIterable, Sendable { case standard; case conductorStudy = "conductor-study" }
    public static let bodyHalfLength: Float = 9.65
    public static let couplingHalfLength: Float = 10.0
    public static let gangwayHalfLength: Float = 9.98
    public static let bodyColor = Map3DColor.rgb(UInt32(TrainLivery.chuKuangCoach))
    public static let glassColor = Map3DE500.glassColor
    public static func model(_ role: Role, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder(); b.chuBody(role, far: far)
        return .flat(named: "chukuang-" + role.rawValue + (far ? "-far" : ""), from: b.mesh)
    }
    public static func windows(_ role: Role, left: Bool) -> [(Float, Float)] {
        // Independently recorded side studies. Unseen opposite-side details are estimates.
        if role == .standard && !left { return [(-7.95,0.50),(-6.9,0.50),(-5.7,0.62),(-3.8,1.84),(-1.6,1.84),(0.6,1.84),(2.8,1.84),(5.0,1.84),(6.65,0.62),(7.8,0.56)] }
        if role == .standard { return [(-7.65,0.56),(-6.48,0.62),(-4.8,1.84),(-2.4,1.84),(0,1.84),(2.4,1.84),(4.8,1.84),(6.48,0.62),(7.65,0.56)] }
        if left { return [(-7.65,0.56),(-6.48,0.62),(-4.8,1.84),(-2.4,1.84),(-0.68,0.55),(0.68,0.55),(2.4,1.84),(4.8,1.84),(7.0,1.84)] }
        return [(-7.0,1.84),(-4.8,1.84),(-2.4,1.84),(-0.68,0.55),(0.68,0.55),(2.4,1.84),(4.8,1.84),(6.48,0.62),(7.65,0.56)]
    }
}

extension StationKitBuilder {
    private mutating func chuPrism(_ section: [(Float, Float)], x: Float, length: Float, color: UInt32) {
        let rings: [[Map3DPoint]] = [-1, 1].map { end in section.map { Map3DPoint(x + Float(end) * length / 2, $0.1, $0.0) } }
        let inside = Map3DPoint(x, section.map(\.1).reduce(0, +) / Float(section.count), 0)
        for i in section.indices {
            let j = (i + 1) % section.count
            face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], inside: inside, color: color)
        }
        for ring in rings { face(ring, inside: inside, color: color) }
    }
    private mutating func chuPanel(_ points: [Map3DPoint], offset: Map3DPoint, color: UInt32) {
        let q = points.map { $0 + offset }, inside = (points + q).reduce(.zero, +) * (1 / Float(points.count * 2))
        face(points, inside: inside, color: color)
        face(q, inside: inside, color: color)
        for i in points.indices {
            let j = (i + 1) % points.count
            face([points[i], points[j], q[j], q[i]], inside: inside, color: color)
        }
    }
    private func chuRounded(_ x: Float, _ y: Float, width: Float, height: Float, radius: Float, far: Bool) -> [(Float, Float)] {
        let n = far ? 2 : 4
        var p: [(Float, Float)] = []
        for (cx, cy, a) in [(x + width / 2 - radius, y + height / 2 - radius, Float(0)),
                            (x - width / 2 + radius, y + height / 2 - radius, Float.pi / 2),
                            (x - width / 2 + radius, y - height / 2 + radius, Float.pi),
                            (x + width / 2 - radius, y - height / 2 + radius, Float.pi * 1.5)] {
            for i in 0...n {
                let t = a + Float(i) * Float.pi / (2 * Float(n))
                p.append((cx + cosf(t) * radius, cy + sinf(t) * radius))
            }
        }
        return p
    }
    private mutating func chuSideWindow(_ x: Float, _ y: Float, side: Float, width: Float, height: Float, far: Bool, opaque: Bool = false) {
        let frame = chuRounded(x, y, width: width + 0.075, height: height + 0.075, radius: 0.14, far: far)
        let pane = chuRounded(x, y, width: width, height: height, radius: 0.12, far: far)
        chuPanel(frame.map { Map3DPoint($0.0, $0.1, side * 1.4435) }, offset: Map3DPoint(0, 0, side * 0.013), color: Self.ink)
        chuPanel(pane.map { Map3DPoint($0.0, $0.1, side * 1.4575) }, offset: Map3DPoint(0, 0, side * 0.012), color: opaque ? Map3DPalette.shopAwnings[3] : Map3DChuKuangPassenger.glassColor)
    }

    fileprivate mutating func chuBody(_ role: Map3DChuKuangPassenger.Role, far: Bool) {
        let orange = Map3DChuKuangPassenger.bodyColor, cream = Map3DColor.rgb(0xECE2BC)
        let dark = Self.ink, steel = Self.steel, tire = Map3DStreetModel.tyre
        let half = Map3DChuKuangPassenger.bodyHalfLength
        // Closed shell rings: the classic end sweep is IN the body surface.
        // Shared stations/levels keep every paint subdivision topologically joined.
        let xs: [Float] = [-half,-8.85,-8.25,-7.7,7.7,8.25,8.85,half]
        let steps = far ? 12 : 20
        func boundary(_ x: Float) -> Float {
            let t = max(0,min(1,(abs(x)-7.7)/1.15))
            return 1.98 + 1.15 * t*t*(3-2*t)
        }
        var rings: [[Map3DPoint]] = []
        for x in xs {
            let top = boundary(x)
            let levels: [Float] = [1.12,1.86,1.92,top,3.16]
            var sec: [(Float,Float)] = [(-1.44,1.12),(1.44,1.12)]
            for h in levels.dropFirst() {sec.append((1.44,h))}
            for i in 1..<steps { let a = Float(i)*Float.pi/Float(steps);sec.append((1.44*cosf(a),3.16+0.48*sinf(a))) }
            sec.append((-1.44,3.16))
            for h in levels.dropFirst().dropLast().reversed(){sec.append((-1.44,h))}
            rings.append(sec.map {Map3DPoint(x,$0.1,$0.0)})
        }
        let n=rings[0].count, inside=Map3DPoint(0,2.4,0)
        for k in 0..<rings.count-1 {for i in 0..<n {
            let j=(i+1)%n
            let color: UInt32
            if i==2 || i==n-2 {color=cream} // 60mm waist line, both real side faces
            else if i>=5 && i<5+steps {color=steel}
            else if i==4 || i==n-4 {color=cream}
            else {color=orange}
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        }}
        for end:Float in [-1,1] {
            let x=end*half
            let levels:[Float]=[1.12,1.86,1.92,boundary(x),3.16]
            for i in 0..<levels.count-1 {
                face([Map3DPoint(x,levels[i],-1.44),Map3DPoint(x,levels[i],1.44),Map3DPoint(x,levels[i+1],1.44),Map3DPoint(x,levels[i+1],-1.44)],inside:inside,color:i==1 ? cream:orange)
            }
            let roof=rings[end<0 ? 0:rings.count-1]
            face(Array(roof[5...5+steps]),inside:inside,color:steel)
        }
        box(0,0.99,0,18.95,2.58,0.13,dark)
        // Low curved air-conditioner cowlings, seated on this shell's roof facets.
        for x:Float in [-6.95,6.95] {
            let widths:[Float]=[-1.08,-0.72,-0.36,0,0.36,0.72,1.08]
            func roof(_ z:Float)->Float {
                let a=acosf(z/1.44), t=a/Float.pi*Float(steps),i=floorf(t),f=t-i
                return 3.16+0.48*((1-f)*sinf(i*Float.pi/Float(steps))+f*sinf((i+1)*Float.pi/Float(steps)))
            }
            for i in 0..<widths.count-1 {
                let z0=widths[i],z1=widths[i+1]
                let low0=roof(z0),low1=roof(z1)
                let hi0:Float=abs(z0)>0.9 ? 3.68:3.78, hi1:Float=abs(z1)>0.9 ? 3.68:3.78
                let mid=Map3DPoint(x,(low0+low1+hi0+hi1)/4,(z0+z1)/2)
                let ends=[x-1.375,x+1.375].map {X in [Map3DPoint(X,low0,z0),Map3DPoint(X,low1,z1),Map3DPoint(X,hi1,z1),Map3DPoint(X,hi0,z0)]}
                for ring in ends {face(ring,inside:mid,color:steel)}
                for edge in [0,2] {face([ends[0][edge],ends[0][edge+1],ends[1][edge+1],ends[1][edge]],inside:mid,color:steel)}
                if i==0 {face([ends[0][0],ends[0][3],ends[1][3],ends[1][0]],inside:mid,color:steel)}
                if i==widths.count-2 {face([ends[0][1],ends[0][2],ends[1][2],ends[1][1]],inside:mid,color:steel)}
            }
            box(x,3.78,0,1.95,1.35,0.008,dark)
            if !far { for d:Float in [-0.8,-0.4,0,0.4,0.8]{box(x+d,3.788,0,0.035,1.35,0.012,steel)} }
        }
        for side:Float in [-1,1] {
            for (x,w) in Map3DChuKuangPassenger.windows(role,left:side<0) {
                chuSideWindow(x,2.52,side:side,width:w,height:w>1 ? 0.88:0.72,far:far)
                if w<0.7 && abs(x)<7 && !far {box(x,2.61,side*1.471,w-0.04,0.014,0.024,steel)}
            }
            for end:Float in [-1,1] {
                let x=end*8.92
                box(x,1.18,side*1.446,0.76,0.012,1.96,dark)
                box(x,1.20,side*1.457,0.70,0.010,1.92,orange)
                chuSideWindow(x,2.56,side:side,width:0.36,height:0.94,far:far)
                box(x,1.86,side*1.468,0.70,0.012,0.06,cream)
                box(x,1.02,side*1.49,0.72,0.20,0.07,steel)
                box(x,0.82,side*1.49,0.64,0.24,0.07,steel)
                if !far {box(x-end*0.21,2.01,side*1.48,0.07,0.02,0.04,steel)}
            }
            box(-5.8,3.09,side*1.448,0.58,0.016,0.18,dark)
        }
        for end:Float in [-1,1] {
            box(end*9.68,1.15,0,0.06,0.96,2.08,dark)
            box(end*9.72,1.20,0,0.025,0.83,1.96,orange)
            box(end*9.74,2.48,0,0.016,0.46,0.55,Map3DChuKuangPassenger.glassColor)
            let folds=far ? 2:5
            for i in 0..<folds {let x=end*(9.66+(Float(i)+0.5)*0.32/Float(folds))
                for z:Float in [-0.55,0.55] {box(x,1.18,z,0.32/Float(folds),0.10,2.12,dark)}
                box(x,3.2,0,0.32/Float(folds),1.20,0.10,dark)
                box(x,1.18,0,0.32/Float(folds),1.20,0.08,dark)
            }
            box(end*9.75,0.78,0,0.4,0.32,0.24,dark)
            box(end*9.945,0.78,0,0.11,0.44,0.24,steel)
        }
        // Two independent two-axle bogies. Visible equaliser / axleboxes, no PP chassis reuse.
        for centre:Float in [-6.9,6.9] {
            box(centre,0.92,0,3.25,1.95,0.14,dark)
            for side:Float in [-1,1] {
                box(centre,0.56,side*1.04,3.2,0.15,0.24,steel)
                for dx:Float in [-1.05,1.05] {
                    civicTube(Map3DPoint(centre+dx,0.425,side*0.50),Map3DPoint(centre+dx,0.425,side*0.67),radius:0.425,color:tire,sides:far ? 12:20)
                    civicTube(Map3DPoint(centre+dx,0.425,side*0.67),Map3DPoint(centre+dx,0.425,side*1.04),radius:0.09,color:steel,sides:8)
                    box(centre+dx,0.40,side*1.04,0.36,0.22,0.30,dark)
                    box(centre+dx,0.71,side*1.04,0.5,0.20,0.11,steel)
                }
                box(centre,0.72,side*1.04,0.55,0.24,0.16,dark)
            }
        }
        for (x,l,z) in [(Float(-3.9),Float(1.7),Float(-0.65)),(-1.4,2.0,-0.65),(1.4,1.2,0.65),(3.4,1.8,0.65)] {
            box(x,0.44,z,l,0.88,0.50,steel)
            if !far {for dx:Float in [-0.3,0.3]{box(x+dx*l,0.49,z<0 ? -1.098:1.098,0.03,0.015,0.36,dark)}}
        }
    }
}
