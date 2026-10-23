import Foundation

/// Seven near-equal low-skirt urban electric modules, independently reconstructed
/// from the owner's seven views. Display dimensions and concealed running gear
/// are estimates; this is a static asset, not an operational vehicle definition.
public enum Map3DSevenCarBlue {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, middleOne, middleTwo, middleThree, middleFour, middleFive, trailing
        public var cab: Float { self == .leading ? 1 : self == .trailing ? -1 : 0 }
        public var length: Float { cab == 0 ? 7.4 : 8.2 }
        public var centre: Float {
            switch self {
            case .leading: 23.2
            case .middleOne: 15.2
            case .middleTwo: 7.6
            case .middleThree: 0
            case .middleFour: -7.6
            case .middleFive: -15.2
            case .trailing: -23.2
            }
        }
    }
    public static let blue = Map3DPalette.trimBlue
    public static let white = Map3DPalette.shopAwnings[3]
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing,0.52)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder=StationKitBuilder();builder.sevenCarBlue(unit)
        return .flat(named:"blue-seven-\(unit.rawValue)",from:builder.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var builder=StationKitBuilder()
        for unit in Unit.allCases { builder.add(model(unit),at:Map3DPoint(unit.centre,0,0)) }
        return .flat(named:"blue-seven-formation",from:builder.mesh)
    }
}

extension StationKitBuilder {
    mutating func sevenCarBlue(_ unit: Map3DSevenCarBlue.Unit) {
        let cab=unit.cab,half=unit.length/2,blue=Map3DSevenCarBlue.blue
        let white=Map3DSevenCarBlue.white,glass=Map3DSevenCarBlue.glass
        let ink=Self.ink,steel=Self.steel
        // Independent twelve-point section: low skirt, flat sides, narrow white
        // upper fascia, blue shoulder and broad white roof. No previous cab mesh.
        let profile: [(Float,Float)]=[(0.60,-1.27),(0.70,-1.325),(2.89,-1.325),
            (3.08,-1.325),(3.19,-1.22),(3.25,-1.12),(3.25,1.12),
            (3.19,1.22),(3.08,1.325),(2.89,1.325),(0.70,1.325),(0.60,1.27)]
        func nose(_ h: Float)->Float { cab*(half-(h-0.40)*0.18) }
        func ring(_ x: Float,_ end: Bool)->[Map3DPoint] {
            profile.map { h,z in Map3DPoint(end ? nose(h):x,h,z*(end ? 0.93:1)) }
        }
        let xs: [Float]=[-half,-half+0.95,half-0.95,half]
        let rings=xs.enumerated().map { i,x in ring(x,cab != 0 && (cab>0 ? i==3:i==0)) }
        let inside=Map3DPoint(0,1.9,0)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count,color: UInt32=i==5 || i==2 || i==8 ? white:i==11 ? ink:blue
            face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:color)
            face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        } }
        face(rings[0],inside:inside,color:blue);face(rings[3],inside:inside,color:blue)
        // Full-width floor clears the wheel crowns by 50mm. Low lateral skirts
        // cover their upper edges without a solid floor intersecting the wheels.
        box(0,0.55,0,unit.length-0.15,2.38,0.10,ink)
        for side: Float in [-1,1] {
            let skirtSection: [(Float,Float)]=[(0.18,1.23),(0.18,1.32),(0.62,1.32),(0.62,1.23)]
            let skirtXs: [Float]=[-half,-half+0.95,half-0.95,half]
            let skirtRings=skirtXs.enumerated().map { i,x in
                let tip=cab != 0 && (cab>0 ? i==3:i==0)
                return skirtSection.map { h,z in Map3DPoint(tip ? nose(h)-cab*0.002:x,h,side*z*(tip ? 0.90:1)) }
            }
            let centre=Map3DPoint(0,0.40,side*1.275)
            face(skirtRings[0],inside:centre,color:blue);face(skirtRings[3],inside:centre,color:blue)
            for k in 0..<3 { for i in skirtSection.indices {
                let j=(i+1)%skirtSection.count
                let localCentre=(skirtRings[k]+skirtRings[k+1]).reduce(Map3DPoint.zero) { $0+$1*0.125 }
                face([skirtRings[k][i],skirtRings[k][j],skirtRings[k+1][j],skirtRings[k+1][i]],inside:localCentre,color:blue)
            } }
        }
        box(0,0.43,0,1.8,1.6,0.17,steel)
        // Concealed conventional two-axle supports are a display completion,
        // NOT a claim that the photograph identifies the real bogie/axle design.
        let bogieCentre: Float=cab == 0 ? 2.28:2.50
        for bx: Float in [-bogieCentre,bogieCentre] {
            box(bx,0.31,0,1.65,1.75,0.16,ink)
            box(bx,0.44,0,0.8,1.42,0.13,steel)
            for dx: Float in [-0.52,0.52] {
                civicTube(Map3DPoint(bx+dx,0.25,-1.08),Map3DPoint(bx+dx,0.25,1.08),radius:0.055,color:steel,sides:8)
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(bx+dx,0.25,side*0.94),Map3DPoint(bx+dx,0.25,side*1.14),radius:0.25,color:Map3DStreetModel.tyre,sides:12)
                    civicTube(Map3DPoint(bx+dx,0.25,side*1.14),Map3DPoint(bx+dx,0.25,side*1.155),radius:0.145,color:steel,sides:12)
                }
            }
        }
        for side: Float in [-1,1] {
            let windows: [(Float,Float)]
            if cab == 0 { windows=[(-3.11,0.70),(0,1.96),(3.11,0.70)] }
            else { windows=[(-cab*3.08,1.04),(cab*0.40,2.08),(cab*2.48,0.72)] }
            for (x,w) in windows {
                box(x,1.035,side*1.329,w+0.055,0.014,1.70,ink)
                box(x,1.065,side*1.340,w,0.008,1.64,glass)
            }
            let doors: [Float]=cab == 0 ? [-1.97,1.97]:[-cab*1.68]
            for x in doors {
                box(x,0.405,side*1.330,1.30,0.016,2.36,ink)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.317,0.435,side*1.343,0.618,0.012,2.30,Map3DPalette.tankWhite)
                    box(x+leaf*0.317,0.435,side*1.353,0.618,0.006,0.60,blue)
                    box(x+leaf*0.317,1.065,side*1.355,0.49,0.008,1.64,glass)
                }
                box(x,0.405,side*1.343,1.32,0.045,0.026,white)
            }
        }
        // Two end-car HVACs; one plus two flush vents on each middle module.
        let hvac: [Float]=cab == 0 ? [0]:[-cab*2.45,cab*1.58]
        for x in hvac {
            box(x,3.25,0,1.45,1.52,0.12,steel)
            box(x,3.37,0,1.27,1.34,0.035,ink)
            for dx: Float in [-0.42,-0.21,0,0.21,0.42] { box(x+dx,3.405,0,0.035,1.12,0.012,steel) }
        }
        if cab == 0 { for x: Float in [-2.65,2.65] { box(x,3.25,0,0.67,0.97,0.024,steel) } }
        for side: Float in [-1,1] where side != cab {
            func joint(_ x: Float,_ depth: Float,_ scale: Float,_ color: UInt32) {
                let centre=Map3DPoint(x,1.91,0)
                let jointProfile=profile.map { h,z in (h < 0.70 ? Float(0.18):h,z) }
                let a=jointProfile.map { h,z in Map3DPoint(x-depth/2,1.91+(h-1.91)*scale,z*scale) }
                let b=jointProfile.map { h,z in Map3DPoint(x+depth/2,1.91+(h-1.91)*scale,z*scale) }
                face(a,inside:centre,color:color);face(b,inside:centre,color:color)
                for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:centre,color:color) }
            }
            joint(side*(half+0.05),0.10,0.976,ink)
            for dx: Float in [0.02,0.055,0.085] { joint(side*(half+dx),0.015,0.993,steel) }
        }
        if cab != 0 {
            // A closed tapered chin fills the cab underside ahead of the first
            // wheel, joining the real floor rather than covering the wheel crown.
            let chinFront: [Map3DPoint]=[(Float(0.18),Float(-1.19)),(0.18,1.19),(0.65,1.19),(0.65,-1.19)].map { h,z in Map3DPoint(nose(h),h,z) }
            let chinBack=chinFront.map { Map3DPoint(cab*(half-0.55),$0.y,$0.z) }
            let chinCentre=Map3DPoint(cab*(half-0.25),0.44,0)
            face(chinFront,inside:chinCentre,color:blue);face(chinBack,inside:chinCentre,color:blue)
            for i in chinFront.indices { let j=(i+1)%chinFront.count;face([chinFront[i],chinFront[j],chinBack[j],chinBack[i]],inside:chinCentre,color:blue) }
            // Closed convex overlays on precisely the same raked front support.
            func cap(_ shape: [(Float,Float)],_ lift: Float,_ color: UInt32) {
                let front=shape.map { Map3DPoint(nose($0.0)+cab*lift,$0.0,$0.1) }
                let back=shape.map { Map3DPoint(nose($0.0)-cab*0.002,$0.0,$0.1) }
                let centre=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                face(front,inside:centre,color:color);face(back,inside:centre,color:color)
                for i in front.indices { let j=(i+1)%front.count;face([front[i],front[j],back[j],back[i]],inside:centre,color:color) }
            }
            cap([(0.78,-1.09),(0.78,1.09),(2.98,1.09),(3.075,0.98),(3.075,-0.98),(2.98,-1.09)],0.006,white)
            cap([(0.90,-0.94),(0.90,0.94),(2.91,0.94),(2.96,0.88),(2.96,-0.88),(2.91,-0.94)],0.014,ink)
            cap([(1.28,-0.84),(1.28,0.84),(2.74,0.84),(2.74,-0.84)],0.022,glass)
            // Geometric wiper lies directly on the windscreen rather than floats.
            let a=Map3DPoint(nose(2.49)+cab*0.031,2.49,-0.58),b=Map3DPoint(nose(1.43)+cab*0.031,1.43,0.42)
            civicTube(a,b,radius:0.012,color:ink,sides:6)
            for side: Float in [-1,1] {
                let z=side*0.65
                cap([(0.965,z-0.22),(0.965,z+0.22),(1.215,z+0.22),(1.215,z-0.22)],0.023,steel)
                cap([(1.005,z-0.16),(1.005,z+0.16),(1.175,z+0.16),(1.175,z-0.16)],0.029,white)
            }
            cap([(0.645,-0.47),(0.645,0.47),(0.69,0.47),(0.69,-0.47)],0.007,ink)
        }
        if unit == .leading {
            // One asymmetric pantograph, supported between the two roof boxes.
            box(-0.42,3.25,0,0.90,0.90,0.10,ink)
            for z: Float in [-0.31,0.31] {
                box(-0.42,3.35,z,0.15,0.15,0.12,white)
                civicTube(Map3DPoint(-0.42,3.47,z),Map3DPoint(-0.04,3.81,z),radius:0.025,color:steel,sides:6)
                civicTube(Map3DPoint(-0.04,3.81,z),Map3DPoint(-0.51,4.09,z),radius:0.025,color:steel,sides:6)
            }
            box(-0.51,4.085,0,0.10,1.65,0.035,ink)
        }
    }
}
