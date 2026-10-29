import Foundation

/// Phase-two Alstom Citadis 305 / X05. Independent shape and equipment recipe.
/// M1–SC1–NP–SC2–M2, two powered bogies, central trailer bogie, suspended SCs.
public enum Map3DKaohsiungCitadis {
    public enum Unit: String, CaseIterable, Sendable { case m1, sc1, np, sc2, m2 }
    public static let joint: Float = 0.60
    public static func length(_ u: Unit) -> Float {
        switch u { case .m1,.m2: 7.85; case .sc1,.sc2: 5.85; case .np: 3.60 }
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var r=Citadis305Recipe(unit:unit,far:far);r.build()
        return .flat(named:"klrt-citadis-"+unit.rawValue+(far ? "-far" : ""),from:r.g.b.mesh)
    }
}

private struct Citadis305Recipe {
    typealias UV = KLRTGeometry.UV
    let unit: Map3DKaohsiungCitadis.Unit
    let far: Bool
    var g=KLRTGeometry()
    let white=Map3DPalette.tileWhite
    let green=Map3DPalette.shopAwnings[0]
    let black=Map3DColor.shaded(Map3DPalette.playerRim,0.57)
    let glass=Map3DTrainStyle.glass
    let grey=Map3DColor.shaded(StationKitBuilder.steel,0.67)
    let tyre=Map3DStreetModel.tyre
    var motor: Bool { unit == .m1 || unit == .m2 }
    var sc: Bool { unit == .sc1 || unit == .sc2 }
    var half: Float { Map3DKaohsiungCitadis.length(unit)/2 }
    // The Alstom has a taller black face, flatter lower nose and squarer shoulder.
    let hs: [Float] = [0.20,0.37,0.85,1.14,2.73,2.97,3.13,3.20]
    let widths: [Float] = [1.11,1.26,1.325,1.325,1.325,1.29,1.16,0.99]
    func width(_ h: Float) -> Float { KLRTGeometry.lerp(h,hs,widths) }
    func bow(_ h: Float,_ w: Float) -> Float {
        half-KLRTGeometry.lerp(h,[0.20,0.50,0.85,1.70,2.73,3.20],[0.17,0.01,0,0.22,0.70,1.0])
            - KLRTGeometry.lerp(abs(w),[0,0.65,1.02,1.325],[0,0.025,0.12,0.33])
    }
    func front(_ v: UV) -> Map3DPoint { Map3DPoint(motor ? bow(v.y,v.x*width(v.y)) : half,v.y,v.x*width(v.y)) }
    func side(_ v: UV,_ s: Float) -> Map3DPoint { Map3DPoint(v.x,v.y,s*width(v.y)) }
    func rect(_ a: Float,_ b: Float,_ c: Float,_ d: Float) -> [UV] { KLRTGeometry.rectangle(a,b,c,d) }
    mutating func build() {
        let profile=self
        var regions: [([UV],UInt32)] = []
        if motor {
            // Tall rounded trapezoidal black face; green rim and white cheeks.
            regions.append(([UV(-0.57,0.32),UV(0.57,0.32),UV(0.71,0.43),UV(0.84,1.03),UV(0.89,2.85),UV(0.76,3.13),UV(-0.76,3.13),UV(-0.89,2.85),UV(-0.84,1.03),UV(-0.71,0.43)],green))
            regions.append(([UV(-0.54,0.40),UV(0.54,0.40),UV(0.67,0.49),UV(0.79,1.06),UV(0.84,2.85),UV(0.73,3.09),UV(-0.73,3.09),UV(-0.84,2.85),UV(-0.79,1.06),UV(-0.67,0.49)],black))
            regions.append(([UV(-0.74,1.14),UV(0.74,1.14),UV(0.80,2.68),UV(0.76,2.77),UV(-0.76,2.77),UV(-0.80,2.68)],glass))
            for s: Float in [-1,1] {
                regions.append((KLRTGeometry.ellipse(s*0.56,0.92,0.115,0.185,sides:far ? 8:16),white))
                regions.append((KLRTGeometry.ellipse(s*0.56,0.98,0.050,0.060,sides:far ? 8:12),Map3DTrainStyle.headlamp))
                regions.append((KLRTGeometry.ellipse(s*0.55,0.83,0.034,0.036,sides:8),Map3DPalette.lantern))
            }
            regions.append((KLRTGeometry.ellipse(0,2.96,0.032,0.043,sides:8),Map3DTrainStyle.headlamp))
        }
        if motor && !far { regions.append(([UV(0.12,1.17),UV(0.15,1.15),UV(0.65,1.94),UV(0.62,1.96)],black)) }
        let us: [Float] = far ? [-1,0,1] : [-1,-0.88,-0.74,-0.47,0,0.47,0.74,0.88,1]
        if far && !motor {
            g.slab(hs.enumerated().map { i,h in Map3DPoint(half,h,-widths[i]) } + hs.enumerated().reversed().map { i,h in Map3DPoint(half,h,widths[i]) },inward:Map3DPoint(-0.024,0,0),color:black,backing:white)
        } else {
            for j in 0..<(hs.count-1) {for i in 0..<(us.count-1) {
                // Constant-width bands are exactly coplanar at this LOD;
                // avoid splitting their identical plane into extra prisms.
                g.surface(rect(us[i],us[i+1],hs[j],hs[j+1]),map:profile.front,inward:Map3DPoint(-0.024,0,0),base:motor ? white:black,regions:regions,backing:white,planar:far && widths[j] == widths[j+1])
            }}
        }
        g.slab(hs.enumerated().map { i,h in Map3DPoint(-half,h,-widths[i]) } + hs.enumerated().reversed().map { i,h in Map3DPoint(-half,h,widths[i]) },inward:Map3DPoint(0.024,0,0),color:black,backing:white)
        for s: Float in [-1,1] {
            var sideRegions: [([UV],UInt32)] = []
            // Alstom's lower green diagonal and broad separate white panels.
            sideRegions.append(([UV(-half,0.20),UV(half,0.20),UV(half,0.36),UV(-half+1.20,1.02),UV(-half,1.02)],green))
            sideRegions.append(([UV(-half,2.87),UV(-half+0.76,2.87),UV(-half+1.22,3.20),UV(-half,3.20)],green))
            sideRegions.append((rect(-half+0.12,motor ? 0.94:half-0.12,0.98,2.80),black))
            let windows: [(Float,Float)] = motor ? [(-2.68,1.24),(-1.27,1.25)] : sc ? [(-1.85,1.52),(1.86,1.47)] : [(-0.85,1.38),(0.78,1.35)]
            for (x,w) in windows {
                if !far { sideRegions.append((rect(x-w/2-0.020,x+w/2+0.020,0.99,2.79),black)) }
                sideRegions.append((rect(x-w/2,x+w/2,1.02,2.76),glass))
            }
            if motor {
                sideRegions.append(([UV(1.05,1.08),UV(bow(1.08,1.325)-0.035,1.08),UV(bow(2.73,1.325)-0.035,2.73),UV(1.17,2.73)],glass))
            }
            if motor || sc {
                let d: Float=motor ? 0.26 : 0.0
                if !far { sideRegions.append((rect(d-0.67,d+0.67,0.35,2.80),black)) }
                sideRegions.append((rect(d-0.637,d+0.637,0.39,2.76),glass))
                if !far { sideRegions.append((rect(d-0.011,d+0.011,0.39,2.76),grey)) }
                if !far { sideRegions.append((rect(d-0.65,d+0.65,0.345,0.38),Map3DPalette.platformEdge)) }
                if !far { sideRegions.append((KLRTGeometry.ellipse(d+0.56,1.06,0.038,0.038,sides:8),Map3DPalette.platformEdge)) }
            }
            if unit == .sc2 { sideRegions=sideRegions.map { (p,c) in (p.reversed().map {UV(-$0.x,$0.y)},c) } }
            let sideHeights=hs
            for j in 0..<(sideHeights.count-1) {
                let h0=sideHeights[j],h1=sideHeights[j+1]
                let x0=motor ? bow(h0,width(h0)):half,x1=motor ? bow(h1,width(h1)):half
                g.surface([UV(-half,h0),UV(x0,h0),UV(x1,h1),UV(-half,h1)],map:{profile.side($0,s)},inward:Map3DPoint(0,0,-s*0.024),base:white,regions:sideRegions,backing:white,planar:true)
            }
        }
        for h in [Float(0.72),hs.last!] {for i in 0..<(us.count-1) {
            let a=us[i]*width(h),z=us[i+1]*width(h)
            g.slab([Map3DPoint(-half,h,a),Map3DPoint(motor ? bow(h,a):half,h,a),Map3DPoint(motor ? bow(h,z):half,h,z),Map3DPoint(-half,h,z)],inward:Map3DPoint(0,h<1 ? 0.024 : -0.024,0),color:white,backing:white)
        }}
        if !sc {
            let centre: Float=motor ? -1.73:0
            g.box(centre,0.27,0,2.56,1.39,0.29,black)
            for dx: Float in [-0.80,0.80] {for s: Float in [-1,1] {g.wheel(centre+dx,s*0.7175,radius:0.295,sides:far ? 8:16,color:tyre)}}
            if !far {for s: Float in [-1,1] {g.box(centre,0.37,s*0.84,2.40,0.11,0.13,grey)}}
        }
        if motor {
            // Cab/saloon HVAC; unlike CAF, no ACR cover here.
            g.box(-1.40,3.20,0,2.30,1.58,0.24,grey)
            g.box(0.22,3.20,0,0.80,1.05,0.14,white)
            if !far {for x in stride(from:Float(-2.37),through:Float(-0.45),by:Float(0.20)) {g.box(x,3.44,0,0.027,1.30,0.018,black)}}
        } else if sc {
            // Official Autonomy diagram places the two Ecopacks on SC1/SC2.
            let x: Float=unit == .sc1 ? -0.80:0.80
            g.box(x,3.20,0,2.53,1.72,0.40,grey)
            g.box(-x*1.65,3.20,0,1.05,1.45,0.20,white)
            if !far {for dx in stride(from:Float(-1.10),through:Float(1.10),by:Float(0.20)) {g.box(x+dx,3.60,0,0.027,1.45,0.018,black)}}
        } else {
            g.box(-0.18,3.20,0,2.40,1.22,0.07,black)
            // Folded standard collector AND the separate compact E-collect shoe.
            for s: Float in [-1,1] {
                g.b.beam(Map3DPoint(-1.18,3.27,s*0.33),Map3DPoint(0.30,3.40,s*0.29),0.038,grey)
                g.b.beam(Map3DPoint(0.30,3.40,s*0.29),Map3DPoint(-0.68,3.51,s*0.13),0.038,black)
            }
            g.box(-0.68,3.50,0,0.24,1.20,0.07,black)
            g.box(1.15,3.20,0,0.45,0.85,0.19,grey)
            g.box(1.15,3.39,0,0.48,1.13,0.08,black)
        }
        if unit != .m2 { g.bellows(-half,direction:-1,length:Map3DKaohsiungCitadis.joint,width:2.38,bottom:0.35,top:3.14,folds:far ? 3:8,color:grey) }
    }
}
