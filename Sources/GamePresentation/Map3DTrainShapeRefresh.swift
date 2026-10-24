import Foundation

/// Independent photo-led static studies. Not assigned to operating train types.
public enum Map3DTrainShapeRefresh {
    public static let ids = ["refresh-e200", "refresh-700t-cab", "refresh-700t-middle", "refresh-700t-panto", "refresh-700t-tail"]
    public static func model(_ id: String) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        if id == ids[0] { b.refreshElectric() }
        else { b.refreshHighSpeed(cab: id == ids[1] || id == ids[4], panto: id == ids[3]) }
        let m = Map3DModelPack.Model.flat(named: id, from: b.mesh)
        if id == ids[4] {
            var reverse = StationKitBuilder(); reverse.add(m, at: .zero, angle: .pi)
            return .flat(named: id, from: reverse.mesh)
        }
        return m
    }
    /// Display formation: cab + ten middle cars + reverse cab. Metre offsets
    /// are display estimates. Pantographs on cars 4 and 9 (one-based).
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for i in 0..<12 {
            let id = i == 0 ? ids[1] : i == 11 ? ids[4] : [3,8].contains(i) ? ids[3] : ids[2]
            b.add(model(id), at: Map3DPoint(Float(11-2*i)*12.7,0,0))
        }
        return .flat(named: "refresh-700t-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    private var refreshWhite: UInt32 { Map3DPalette.shopAwnings[3] }
    private var refreshTeal: UInt32 { Map3DPalette.shopAwnings[0] }
    private var refreshGlass: UInt32 { Map3DColor.shaded(Map3DPalette.glazing,0.5) }
    private mutating func refreshRunning(_ centres: [Float], axles: [Float], radius: Float, gauge: Float) {
        // Six-sided wheel cross sections have extrema at sin(60°).
        let contactHeight=radius*sqrtf(3)/2
        for x in centres {
            box(x,0.49,0,axles.last! - axles.first! + 0.8,gauge+0.22,0.25,Self.ink)
            for dx in axles {
                civicTube(Map3DPoint(x+dx,contactHeight,-gauge/2),Map3DPoint(x+dx,contactHeight,gauge/2),radius:0.075,color:Self.steel,sides:6)
                for s: Float in [-1,1] {
                    civicTube(Map3DPoint(x+dx,contactHeight,s*(gauge/2-0.04)),Map3DPoint(x+dx,contactHeight,s*(gauge/2+0.15)),radius:radius,color:Map3DStreetModel.tyre,sides:6)
                }
            }
            box(x,0.72,0,1.2,gauge,0.35,Self.steel)
        }
    }
    private mutating func refreshPanto(_ x: Float, roof: Float) {
        box(x,roof,0,1.8,1.15,0.12,Self.steel)
        for z: Float in [-0.43,0.43] {
            cylinder(x,roof+0.12,z,radius:0.12,height:0.18,color:refreshWhite,sides:8)
            for sign: Float in [-1,1] {
                beam(Map3DPoint(x,roof+0.28,z),Map3DPoint(x+sign*0.65,roof+0.57,z),0.045,Self.ink)
                beam(Map3DPoint(x+sign*0.65,roof+0.57,z),Map3DPoint(x,roof+0.9,z),0.045,Self.ink)
            }
        }
        box(x,roof+0.88,0,0.16,1.5,0.07,Self.steel)
    }
    mutating func refreshElectric() {
        // E200 dimensions from the project's sourced engineering catalog.
        let half: Float = 8.5245, w: Float = 1.486
        let profile: [(Float,Float)] = [(1.13,-w),(3.35,-w),(3.92,-1.14),(3.92,1.14),(3.35,w),(1.13,w)]
        let rings = [-half,-half+0.42,half-0.42,half].map { x in
            profile.map { h,z in Map3DPoint(x.sign == .minus ? x + (h>3.35 ? 0.18:0) : x - (h>3.35 ? 0.18:0),h,z) }
        }
        let inside = Map3DPoint(0,2.5,0)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:i==5 ? Self.ink:refreshWhite)
        } }
        for k in [0,3] {
            face([rings[k][0],rings[k][1],rings[k][4],rings[k][5]],inside:inside,color:refreshWhite)
            face([rings[k][1],rings[k][2],rings[k][3],rings[k][4]],inside:inside,color:refreshWhite)
        }
        for sign: Float in [-1,1] { box(sign*(half+0.008),1.13,0,0.018,2*w,1.62,refreshTeal) }
        box(0,0.99,0,16.8,2.65,0.14,Self.ink)
        refreshRunning([-5.1,5.1],axles:[-1.5,0,1.5],radius:0.51,gauge:1.067)
        for s: Float in [-1,1] {
            box(0,1.15,s*1.482,16.15,0.02,1.42,refreshTeal)
            box(0,2.64,s*1.486,16.15,0.022,0.055,refreshTeal)
            for x: Float in [-7.2,7.2] {
                box(x,1.3,s*1.49,0.63,0.018,2.05,Map3DPalette.tankWhite)
                box(x,2.65,s*1.502,0.44,0.012,0.57,refreshGlass)
                box(x+(x>0 ? 0.63:-0.63),2.73,s*1.49,0.53,0.02,0.55,refreshGlass)
            }
            // Recessed-looking engine-room seams, not oversized vent boxes.
            for x: Float in [-4.5,-2.7,-0.9,0.9,2.7,4.5] {
                box(x,2.86,s*1.49,1.45,0.014,0.39,Self.steel)
                for j in 0..<5 { box(x,2.9+Float(j)*0.063,s*1.5,1.34,0.008,0.019,refreshWhite) }
            }
            let x=s*half
            // Two front windows; face panel is almost upright below shoulder.
            for z: Float in [-0.68,0.68] {
                for (lo,hi): (Float,Float) in [(2.96,3.35),(3.35,3.61)] {
                    func front(_ h: Float)->Float { x-s*max(0,h-3.35)*0.18/0.57+s*0.022 }
                    let p=[Map3DPoint(front(lo),lo,z-0.58),Map3DPoint(front(lo),lo,z+0.58),Map3DPoint(front(hi),hi,z+0.58),Map3DPoint(front(hi),hi,z-0.58)]
                    refreshPanel(p,thickness:0.025,color:refreshGlass)
                }
                box(x,3.68,z*0.3,0.035,0.22,0.19,Map3DPalette.platformEdge)
            }
            for z: Float in [-1,1] {
                beam(Map3DPoint(x+s*0.02,2.66,z*1.35),Map3DPoint(x+s*0.02,1.91,0),0.065,refreshWhite)
            }
            box(x,0.54,0,0.11,2.55,0.48,Self.steel)
            box(x+s*0.15,0.83,0,0.44,0.34,0.22,Self.ink)
        }
        for x: Float in [-4.8,4.8] { refreshPanto(x,roof:3.92) }
        box(0,3.92,0,5.8,1.9,0.13,Self.steel)
    }
    mutating func refreshHighSpeed(cab: Bool,panto: Bool) {
        // Display dimensions: 25 m body, 3.38 m wide, 3.65 m roof.
        // Nose has a broad low tip and a rising cockpit, not an ellipsoid cap.
        let inside=Map3DPoint(0,2,0), segments=24
        let xs: [Float] = cab ? [-12.5,-10,-6,0,4.7,5.4,6.2,7,7.8,8.6,9.4,10.2,11,11.7,12.2,12.45,12.5] : [-12.5,12.5]
        func ring(_ x: Float)->[Map3DPoint] {
            let t=cab ? max(0,(x-4.7)/7.8):0
            let h: Float = 3.65-2.55*(t*t*(3-2*t))
            let width: Float = max(0.025,1.69*sqrtf(max(0,1-powf(t,6))))
            return (0..<segments).map { i in
                let a=Float(i)*2*Float.pi/Float(segments),c=cosf(a),s=sinf(a)
                let z=width*(c>=0 ? 1:-1)*powf(abs(c),0.58)
                let y: Float=0.78+(h-0.78)*(0.5+0.5*(s>=0 ? 1:-1)*powf(abs(s),0.65))
                return Map3DPoint(x,y,z)
            }
        }
        let rings=xs.map(ring)
        for k in 0..<rings.count-1 { for i in 0..<segments {
            let j=(i+1)%segments
            let localCentre=Map3DPoint((xs[k]+xs[k+1])/2,(rings[k].map(\.y).max()!+rings[k+1].map(\.y).max()!+1.56)/4,0)
            let color: UInt32 = (14...21).contains(i) ? Self.steel : [12,13,22,23].contains(i) ? refreshTeal:refreshWhite
            face([rings[k][i],rings[k][j],rings[k+1][j]],inside:localCentre,color:color)
            face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:localCentre,color:color)
        } }
        face(rings[0],inside:inside,color:refreshWhite);face(rings.last!,inside:inside,color:refreshWhite)
        refreshRunning([-8.8, cab ? 3.4:8.8],axles:[-1.25,1.25],radius:0.40,gauge:1.435)
        box(0,0.92,0,cab ? 17:23.8,2.55,0.12,Self.ink)
        // Conformal window and door solids follow the actual cross section.
        func flank(_ h: Float)->Float {
            let s=(h-0.78)/(3.65-0.78)*2-1
            return 1.69*powf(max(0,1-powf(abs(s),2/0.65)),0.58/2)
        }
        for sign: Float in [-1,1] {
            box(cab ? -3.7:0,0.55,sign*1.42,cab ? 17.4:23.8,0.09,0.67,Self.steel)
            for i in 0..<(cab ? 12:18) {
                let x: Float = -9.3+Float(i)*0.81
                let bottom: Float=2.0,top: Float=2.69
                let p=[Map3DPoint(x-0.25,bottom,sign*(flank(bottom)+0.014)),Map3DPoint(x+0.25,bottom,sign*(flank(bottom)+0.014)),Map3DPoint(x+0.25,top,sign*(flank(top)+0.014)),Map3DPoint(x-0.25,top,sign*(flank(top)+0.014))]
                refreshPanel(p,thickness:0.025,color:refreshGlass)
            }
            for x: Float in cab ? [-11,3.1]:[-11,11] {
                for k in 0..<3 {
                    let lo: Float=1.1+Float(k)*0.6267,hi=lo+0.6267
                    let p=[Map3DPoint(x-0.38,lo,sign*(flank(lo)+0.014)),Map3DPoint(x+0.38,lo,sign*(flank(lo)+0.014)),Map3DPoint(x+0.38,hi,sign*(flank(hi)+0.014)),Map3DPoint(x-0.38,hi,sign*(flank(hi)+0.014))]
                    refreshPanel(p,thickness:0.025,color:k == 2 ? refreshGlass:Map3DPalette.tankWhite)
                }
            }
        }
        if cab {
            // Windshield mapped onto the upper nose rings, backed by the shell.
            for k in 6...8 { for i in 2...9 {
                let j=i+1
                let p=[rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]].map { Map3DPoint($0.x,$0.y+0.015,$0.z) }
                refreshPanel(p,thickness:0.025,color:refreshGlass)
                if k == 8 && [3,4,7,8].contains(i) {
                    let centre=p.reduce(Map3DPoint.zero) { $0+$1*0.25 }
                    let lamp=p.map { centre+($0-centre)*0.48+Map3DPoint(0,0.014,0) }
                    refreshPanel(lamp,thickness:0.025,color:Map3DPalette.tunnelLamp)
                }
            } }
        }
        for end: Float in cab ? [-1]:[-1,1] {
            box(end*12.58,1.05,0,0.18,2.15,2.07,Self.ink)
            box(end*12.58,0.66,0,0.32,0.35,0.3,Self.steel)
        }
        if panto { refreshPanto(6.8,roof:3.65) }
    }
    private mutating func refreshPanel(_ p: [Map3DPoint],thickness: Float,color: UInt32) {
        let raw=(p[1]-p[0]).cross(p[2]-p[0]).normalized!
        let centre=p.reduce(Map3DPoint.zero) { $0+$1*0.25 }
        let normal=raw.dot(centre-Map3DPoint(0,2,0))>=0 ? raw:raw*(-1)
        let back=p.map { $0-normal*thickness }
        let c=(p+back).reduce(Map3DPoint.zero) { $0+$1*(1/8) }
        face(p,inside:c,color:color);face(back,inside:c,color:color)
        for i in 0..<4 { let j=(i+1)%4;face([p[i],back[i],back[j],p[j]],inside:c,color:color) }
    }
}
