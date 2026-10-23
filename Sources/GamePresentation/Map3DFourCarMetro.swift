import Foundation

/// Four equal conventional bogie cars reconstructed independently from five
/// owner-supplied views. Metres are display estimates, not engineering data.
public enum Map3DFourCarMetro {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, middleFront, middleRear, trailing
        public var centre: Float {
            switch self { case .leading: 18.45; case .middleFront: 6.15; case .middleRear: -6.15; case .trailing: -18.45 }
        }
    }
    public static let sand = Map3DPalette.containers[3]
    public static let white = Map3DPalette.shopAwnings[3]
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing,0.62)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder=StationKitBuilder()
        builder.fourCarMetro(unit)
        return .flat(named:"metro-four-\(unit.rawValue)",from:builder.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var builder=StationKitBuilder()
        for unit in Unit.allCases { builder.add(model(unit),at:Map3DPoint(unit.centre,0,0)) }
        return .flat(named:"metro-four-formation",from:builder.mesh)
    }
}

extension StationKitBuilder {
    mutating func fourCarMetro(_ unit: Map3DFourCarMetro.Unit) {
        let sand=Map3DFourCarMetro.sand,white=Map3DFourCarMetro.white
        let glass=Map3DFourCarMetro.glass,ink=Self.ink,steel=Self.steel
        let cab: Float=unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let half: Float=6.0,inside=Map3DPoint(0,2.1,0)
        // Low chamfered shoulders and a nearly upright cab. This shell, bogies,
        // cap, door rhythm and buffers are independent of the earlier LRTs.
        let profile: [(Float,Float)]=[(0.84,-1.27),(1.00,-1.35),(3.36,-1.35),(3.65,-1.16),
                                     (3.65,1.16),(3.36,1.35),(1.00,1.35),(0.84,1.27)]
        func nose(_ h: Float)->Float { cab*(half-(h-0.84)*0.055) }
        func ring(_ x: Float)->[Map3DPoint] {
            profile.map { h,z in
                let end=cab != 0 && x*cab>5.99
                return Map3DPoint(end ? nose(h):x,h,z*(end ? 0.96:1))
            }
        }
        let rings: [[Map3DPoint]]=[-half,-5.5,5.5,half].map(ring)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count,color: UInt32=[0,6].contains(i) ? sand : i == 7 ? ink:white
            face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:color)
            face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        } }
        face(rings[0],inside:inside,color:white);face(rings[3],inside:inside,color:white)
        box(0,0.80,0,11.98,2.64,0.07,steel)
        // Conventional high-floor underframe, eight visible wheel discs/car.
        box(0,0.78,0,11.5,2.26,0.14,ink)
        box(0,0.60,0,3.1,1.76,0.20,steel)
        for bx: Float in [-3.85,3.85] {
            box(bx,0.40,0,2.50,1.92,0.24,ink)
            box(bx,0.60,0,1.32,1.60,0.23,steel)
            for dx: Float in [-0.78,0.78] {
                civicTube(Map3DPoint(bx+dx,0.38,-1.12),Map3DPoint(bx+dx,0.38,1.12),radius:0.075,color:steel,sides:8)
                for sign: Float in [-1,1] {
                    civicTube(Map3DPoint(bx+dx,0.38,sign*0.94),Map3DPoint(bx+dx,0.38,sign*1.17),radius:0.38,color:Map3DStreetModel.tyre,sides:16)
                    civicTube(Map3DPoint(bx+dx,0.38,sign*1.17),Map3DPoint(bx+dx,0.38,sign*1.185),radius:0.235,color:steel,sides:12)
                }
            }
            for sign: Float in [-1,1] { box(bx,0.42,sign*1.14,2.27,0.13,0.18,steel) }
        }
        for sign: Float in [-1,1] {
            box(0,0.88,sign*1.344,11.04,0.022,0.25,sand)
            // Individual windows, thin dark gaskets; no continuous LRT glass belt.
            let outerWidths: [Float]=cab == 0 ? [1.10,1.10] : cab>0 ? [1.10,0.72]:[0.72,1.10]
            for (x,w,h): (Float,Float,Float) in [(-4.66,outerWidths[0],1.06),(0,2.14,1.15),(4.66,outerWidths[1],1.06)] {
                box(x,1.84,sign*1.353,w+0.07,0.014,h+0.07,ink)
                box(x,1.875,sign*1.363,w,0.008,h,glass)
            }
            for x: Float in [-2.63,2.63] {
                box(x,0.86,sign*1.354,1.57,0.018,2.27,ink)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.372,0.90,sign*1.369,0.71,0.012,2.19,steel)
                    box(x+leaf*0.372,1.91,sign*1.379,0.43,0.008,1.02,glass)
                }
                box(x,0.86,sign*1.371,1.60,0.06,0.034,white)
            }
        }
        // Two low inspection hatches/car: no unsupported pantograph or invented
        // HVAC tower. Their absent reference details stay documented as unknown.
        for x: Float in [-4.05,4.05] { box(x,3.65,0,1.06,1.10,0.044,white) }
        for sign: Float in [-1,1] where sign != cab {
            box(sign*6.065,0.98,0,0.17,2.04,2.31,ink)
            for dx: Float in [0.04,0.08,0.12] { box(sign*(6.0+dx),1.01,0,0.022,2.13,2.25,steel) }
            box(sign*6.05,0.54,0,0.22,0.35,0.20,steel)
        }
        if cab != 0 {
            // Every cap overlay is a closed prism on the same raked support plane.
            func cap(_ outline: [(Float,Float)],_ lift: Float,_ color: UInt32) {
                let front=outline.map { Map3DPoint(nose($0.0)+cab*lift,$0.0,$0.1) }
                let back=outline.map { Map3DPoint(nose($0.0)-cab*0.002,$0.0,$0.1) }
                let centre=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                face(front,inside:centre,color:color);face(back,inside:centre,color:color)
                for i in front.indices { let j=(i+1)%front.count;face([front[i],front[j],back[j],back[i]],inside:centre,color:color) }
            }
            cap([(0.89,-1.18),(0.89,1.18),(3.33,1.18),(3.53,1.07),(3.53,-1.07),(3.33,-1.18)],0.007,sand)
            cap([(1.35,-1.10),(1.35,1.10),(3.28,1.10),(3.42,0.99),(3.42,-0.99),(3.28,-1.10)],0.015,ink)
            cap([(2.10,-1.04),(2.10,1.04),(3.04,1.04),(3.04,-1.04)],0.023,glass)
            for sign: Float in [-1,1] {
                cap([(1.49,sign*0.82-0.13),(1.49,sign*0.82+0.13),(1.58,sign*0.82+0.13),(1.58,sign*0.82-0.13)],0.024,white)
                box(cab*5.98,0.67,sign*0.96,0.23,0.29,0.40,ink)
                box(cab*6.16,0.86,sign*0.96,0.24,0.47,0.26,steel)
            }
            box(cab*5.70,0.57,0,0.34,0.40,0.24,steel)
            box(cab*6.05,0.49,0,1.00,0.24,0.18,ink)
            box(cab*6.47,0.43,0,0.29,0.46,0.31,steel)
        }
    }
}
