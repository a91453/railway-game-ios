import Foundation

/// Phase-one CAF Urbos 3 (CAF's Kaohsiung EPD: Urbos 100), normal livery.
/// Five independent rigid modules; the two suspended modules have NO wheels.
/// See the source/dimension confidence table; module splits are visual estimates.
public enum Map3DKaohsiungCAF {
    public enum Unit: String, CaseIterable, Sendable { case c1, s1, r, s2, c2 }
    public static let joint: Float = 0.60
    public static func length(_ u: Unit) -> Float {
        switch u { case .c1,.c2: 7.783; case .s1,.s2: 6.10; case .r: 4.0 }
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var r=CAFUrbosRecipe(unit:unit,far:far);r.build()
        return .flat(named:"klrt-caf-"+unit.rawValue+(far ? "-far" : ""),from:r.g.b.mesh)
    }
}

private struct CAFUrbosRecipe {
    typealias UV = KLRTGeometry.UV
    let unit: Map3DKaohsiungCAF.Unit
    let far: Bool
    var g=KLRTGeometry()
    let white=Map3DPalette.tileWhite
    let green=Map3DPalette.shopAwnings[0]
    let ink=Map3DPalette.playerRim
    let glass=Map3DTrainStyle.glass
    let metal=Map3DColor.shaded(StationKitBuilder.steel,0.62)
    let tyre=Map3DStreetModel.tyre
    var cab: Bool { unit == .c1 || unit == .c2 }
    var suspended: Bool { unit == .s1 || unit == .s2 }
    var half: Float { Map3DKaohsiungCAF.length(unit)/2 }
    let hs: [Float] = [0.18,0.34,0.72,1.18,2.65,2.88,3.08,3.15]
    let widths: [Float] = [1.08,1.26,1.325,1.325,1.325,1.27,1.12,0.96]
    func width(_ h: Float) -> Float { KLRTGeometry.lerp(h,hs,widths) }
    func nose(_ h: Float,_ w: Float) -> Float {
        half-KLRTGeometry.lerp(h,[0.18,0.50,0.72,1.18,2.30,2.88,3.15],[0.22,0.02,0,0.06,0.55,1.04,1.38])
            - KLRTGeometry.lerp(abs(w),[0,0.48,0.92,1.325],[0,0.045,0.20,0.66])
    }
    func front(_ v: UV) -> Map3DPoint { Map3DPoint(cab ? nose(v.y,v.x*width(v.y)) : half,v.y,v.x*width(v.y)) }
    func side(_ v: UV,_ s: Float) -> Map3DPoint { Map3DPoint(v.x,v.y,s*width(v.y)) }
    func rect(_ a: Float,_ b: Float,_ c: Float,_ d: Float) -> [UV] { KLRTGeometry.rectangle(a,b,c,d) }
    mutating func build() {
        let profile=self
        var frontRegions: [([UV],UInt32)] = []
        if cab {
            // U-shaped green wreath, white lower bridge, broad curved screen.
            frontRegions.append((rect(-0.94,0.94,0.42,3.10),green))
            frontRegions.append(([UV(-1,0.22),UV(1,0.22),UV(1,0.56),UV(0.72,0.43),UV(-0.72,0.43),UV(-1,0.56)],white))
            frontRegions.append(([UV(-0.90,0.93),UV(0,0.78),UV(0.90,0.93),UV(0.87,1.28),UV(-0.87,1.28)],white))
            frontRegions.append(([UV(-0.78,1.20),UV(0.78,1.20),UV(0.84,1.34),UV(0.83,2.68),UV(0.72,2.96),UV(-0.72,2.96),UV(-0.83,2.68),UV(-0.84,1.34)],ink))
            frontRegions.append(([UV(-0.75,1.24),UV(0.75,1.24),UV(0.80,1.37),UV(0.79,2.67),UV(0.69,2.91),UV(-0.69,2.91),UV(-0.79,2.67),UV(-0.80,1.37)],glass))
            // Lamps are surface-fitted colour partitions, circular in front elevation.
            for sign: Float in [-1,1] {
                for (w,h) in [(Float(0.68),Float(1.10)),(0.86,1.10),(0.68,0.93),(0.86,0.94)] {
                    if !far { frontRegions.append((KLRTGeometry.ellipse(sign*w,h,0.041,0.060,sides:10),metal)) }
                    frontRegions.append((KLRTGeometry.ellipse(sign*w,h,0.028,0.041,sides:far ? 8:12), h<1 ? (w<0.8 ? Map3DPalette.lantern:metal):Map3DTrainStyle.headlamp))
                }
                frontRegions.append((KLRTGeometry.ellipse(sign*0.69,0.53,0.023,0.028,sides:8),Map3DPalette.platformEdge))
            }
            frontRegions.append((KLRTGeometry.ellipse(0,3.02,0.027,0.035,sides:8),Map3DTrainStyle.headlamp))
        }
        if cab { frontRegions.append(([UV(-0.03,1.27),UV(0.0,1.24),UV(0.49,1.78),UV(0.46,1.81)],ink)) }
        let us: [Float] = far ? [-1,0,1] : [-1,-0.86,-0.70,-0.44,0,0.44,0.70,0.86,1]
        for j in 0..<(hs.count-1) {
            for i in 0..<(us.count-1) {
                g.surface(rect(us[i],us[i+1],hs[j],hs[j+1]),map:profile.front,inward:Map3DPoint(-0.025,0,0),base:cab ? white:ink,regions:frontRegions,backing:white)
            }
        }
        // Back cap is a dark structural diaphragm, fully covered by the bellows in assembly.
        g.slab(hs.enumerated().map { i,h in Map3DPoint(-half,h,-widths[i]) } + hs.enumerated().reversed().map { i,h in Map3DPoint(-half,h,widths[i]) },inward:Map3DPoint(0.025,0,0),color:ink,backing:white)
        for s: Float in [-1,1] {
            var regions: [([UV],UInt32)] = []
            let end=cab ? nose(2.65,1.325) : half
            // Large white/green diagonals are cut into the side skin itself.
            regions.append((rect(-half,half,0.18,0.32),green))
            regions.append(([UV(-half,0.18),UV(-half+1.90,0.18),UV(-half,1.05)],green))
            regions.append(([UV(-half,2.84),UV(-half+0.85,2.84),UV(-half+1.75,3.15),UV(-half,3.15)],green))
            if !far { regions.append((rect(-half+0.12,cab ? 0.88:half-0.12,1.045,2.745),ink)) }
            if cab {
                regions.append((KLRTGeometry.ellipse(2.36,1.80,1.78,1.61,sides:far ? 12:16),green))
                regions.append((KLRTGeometry.ellipse(2.67,1.85,1.43,1.28,sides:far ? 12:16),white))
                for (x,w) in [(Float(-2.66),Float(1.21)),(-1.23,1.23)] {
                    if !far { regions.append((rect(x-w/2-0.025,x+w/2+0.025,1.06,2.73),ink)) }
                    regions.append((rect(x-w/2,x+w/2,1.09,2.70),glass))
                }
                regions.append(([UV(1.56,1.22),UV(nose(1.22,1.325)-0.04,1.22),UV(end-0.04,2.65),UV(1.56,2.65),UV(1.20,2.18),UV(1.15,1.66)],glass))
            } else {
                let windows: [(Float,Float)] = suspended ? [(-1.89,1.63),(1.92,1.57)] : [(-0.96,1.48),(0.88,1.55)]
                for (x,w) in windows {
                    if !far { regions.append((rect(x-w/2-0.025,x+w/2+0.025,1.06,2.73),ink)) }
                    regions.append((rect(x-w/2,x+w/2,1.09,2.70),glass))
                }
            }
            if cab || suspended {
                let d: Float = cab ? 0.19 : 0.0
                if !far { regions.append((rect(d-0.67,d+0.67,0.34,2.75),ink)) }
                regions.append((rect(d-0.635,d+0.635,0.38,2.71),glass))
                if !far { regions.append((rect(d-0.012,d+0.012,0.38,2.71),metal)) }
                if !far { regions.append((rect(d-0.65,d+0.65,0.335,0.37),Map3DPalette.platformEdge)) }
                if !far { regions.append((KLRTGeometry.ellipse(d+0.54,1.10,0.045,0.045,sides:8),Map3DPalette.platformEdge)) }
            }
            if unit == .s2 { regions=regions.map { (p,c) in (p.reversed().map {UV(-$0.x,$0.y)},c) } }
            // Both LODs share every front/side perimeter bend: skipping a bend
            // leaves a wedge-shaped daylight gap despite closed patch solids.
            let sideHeights=hs
            for j in 0..<(sideHeights.count-1) {
                let h0=sideHeights[j],h1=sideHeights[j+1]
                let x0=cab ? nose(h0,width(h0)) : half,x1=cab ? nose(h1,width(h1)) : half
                let poly=[UV(-half,h0),UV(x0,h0),UV(x1,h1),UV(-half,h1)]
                g.surface(poly,map:{ profile.side($0,s) },inward:Map3DPoint(0,0,-s*0.025),base:white,regions:regions,backing:white,planar:true)
            }
        }
        // Top/bottom skin spans the true front perimeter; roof equipment sits at3.15.
        for h in [Float(0.72),hs.last!] {
            for i in 0..<(us.count-1) {
                let a=us[i]*width(h),z=us[i+1]*width(h)
                let p=[Map3DPoint(-half,h,a),Map3DPoint(cab ? nose(h,a):half,h,a),Map3DPoint(cab ? nose(h,z):half,h,z),Map3DPoint(-half,h,z)]
                g.slab(p,inward:Map3DPoint(0,h<1 ? 0.025 : -0.025,0),color:white,backing:white)
            }
        }
        // The 1/3/5 modules alone carry bogies. Radius/centres are photo estimates.
        if !suspended {
            let centre: Float = cab ? -1.65 : 0
            g.box(centre,0.26,0,2.65,1.40,0.31,ink)
            for dx: Float in [-0.90,0.90] { for s: Float in [-1,1] {
                g.wheel(centre+dx,s*0.7175,radius:0.30,sides:far ? 8:16,color:tyre)
            }}
            if !far { for s: Float in [-1,1] {g.box(centre,0.38,s*0.85,2.55,0.12,0.16,metal)} }
        }
        // Visible exposed covers, not a claim to reproduce the complete 750mm ACR box.
        if cab {
            g.box(-1.34,3.15,0,3.211,1.845,0.45,metal)
            g.box(0.85,3.15,0,0.76,1.10,0.20,white)
            if !far {
                for x in stride(from:Float(-2.75),through:Float(0.06),by:Float(0.25)) {g.box(x,3.60,0,0.036,1.60,0.018,ink)}
                g.box(unit == .c1 ? -0.8 : -2.0,3.60,0.40,0.14,0.15,0.02,metal)
            }
        } else if suspended {
            g.box(0.30,3.15,0,2.92,1.63,0.30,metal)
            if !far {for x in stride(from:Float(-0.95),through:Float(1.50),by:Float(0.22)) {g.box(x,3.45,0,0.028,1.38,0.018,ink)}}
        } else {
            g.box(-0.72,3.15,0,0.90,1.48,0.31,metal)
            // Folded central single-arm charging collector, as seen running between stations.
            g.box(0.48,3.15,0,1.32,1.10,0.08,ink)
            for s: Float in [-1,1] {
                g.b.beam(Map3DPoint(0.02,3.23,s*0.38),Map3DPoint(1.13,3.42,s*0.31),0.045,ink)
                g.b.beam(Map3DPoint(1.13,3.42,s*0.31),Map3DPoint(0.27,3.52,s*0.19),0.045,metal)
            }
            g.box(0.27,3.51,0,0.25,1.28,0.07,ink)
        }
        // One owner per complete joint; no double bellows and no duplicated wheels.
        if unit != .c2 {
            g.bellows(-half,direction:-1,length:Map3DKaohsiungCAF.joint,width:2.42,bottom:0.34,top:3.10,folds:far ? 3:7,color:Map3DColor.shaded(metal,0.74))
        }
    }
}
