import Foundation

/// Independent seven-section static recipe from the owner's four new views.
/// Metre proportions are display estimates, not a specific manufacturer's plan.
public enum Map3DSevenSectionLRT {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, suspendedFront, middleFront, suspendedCentre, middleRear, suspendedRear, trailing
        public var length: Float {
            switch self { case .leading,.trailing: 9; case .middleFront,.middleRear: 7; default: 4.1 }
        }
        public var centre: Float {
            switch self {
            case .leading: 18.25; case .suspendedFront: 11.5; case .middleFront: 5.75
            case .suspendedCentre: 0; case .middleRear: -5.75; case .suspendedRear: -11.5; case .trailing: -18.25
            }
        }
        public var hasBogie: Bool { [.leading,.middleFront,.middleRear,.trailing].contains(self) }
    }
    public static let blue = Map3DPalette.trimBlue
    public static let white = Map3DPalette.shopAwnings[3]
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing,0.62)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        b.sevenSectionLRT(unit)
        return .flat(named:"lrt-seven-\(unit.rawValue)",from:b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        for unit in Unit.allCases { b.add(model(unit),at:Map3DPoint(unit.centre,0,0)) }
        return .flat(named:"lrt-seven-formation",from:b.mesh)
    }
}

extension StationKitBuilder {
    mutating func sevenSectionLRT(_ unit: Map3DSevenSectionLRT.Unit) {
        let blue=Map3DSevenSectionLRT.blue,white=Map3DSevenSectionLRT.white
        let glass=Map3DSevenSectionLRT.glass,ink=Self.ink,steel=Self.steel
        let half=unit.length/2,cab: Float=unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let inside=Map3DPoint(0,1.65,0),root=half-1.45
        // A twelve-corner section gives this longer reference a fine shoulder
        // break and tucked lower skirt; independent of the five-section shell.
        let profile: [(Float,Float)]=[
            (0.24,-1.17),(0.36,-1.30),(0.64,-1.325),(2.84,-1.325),(3.09,-1.22),(3.25,-1.02),
            (3.25,1.02),(3.09,1.22),(2.84,1.325),(0.64,1.325),(0.36,1.30),(0.24,1.17)
        ]
        func nose(_ h: Float) -> Float { cab*(half-max(0,h-0.36)*0.255) }
        func station(_ x: Float) -> [Map3DPoint] {
            profile.map { h,z in
                let outer=cab != 0 && x*cab>half-0.001
                return Map3DPoint(outer ? nose(h) : x,h,z*(outer ? 0.875 : 1))
            }
        }
        let xs: [Float]=[-half,-root,root,half],rings=xs.map(station)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count
            let color: UInt32 = i == 11 ? ink : [0,1,3,4,6,7,9,10].contains(i) ? blue : white
            face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:color)
            face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        } }
        face(rings[0],inside:inside,color:white);face(rings[3],inside:inside,color:white)
        box(0,0.28,0,unit.length-0.52,2.25,0.19,ink)
        if unit.hasBogie {
            let x: Float=cab*1.20
            box(x,0.31,0,2.20,1.94,0.22,ink)
            for dx: Float in [-0.72,0.72] {
                civicTube(Map3DPoint(x+dx,0.29,-1.10),Map3DPoint(x+dx,0.29,1.10),radius:0.07,color:steel,sides:8)
                for sign: Float in [-1,1] {
                    civicTube(Map3DPoint(x+dx,0.29,sign*0.95),Map3DPoint(x+dx,0.29,sign*1.12),radius:0.29,color:Map3DStreetModel.tyre,sides:12)
                    civicTube(Map3DPoint(x+dx,0.29,sign*1.12),Map3DPoint(x+dx,0.29,sign*1.133),radius:0.15,color:steel,sides:10)
                }
            }
            box(x,0.47,0,1.82,1.82,0.13,steel)
        }
        for sign: Float in [-1,1] {
            let low: Float=cab<0 ? -root : -half+0.11
            let high: Float=cab>0 ? root : half-0.11
            box((low+high)/2,0.70,sign*1.328,high-low,0.010,2.12,ink)
            box((low+high)/2,0.38,sign*1.319,high-low,0.020,0.24,blue)
            box((low+high)/2,0.64,sign*1.330,high-low,0.008,0.035,white)
            if unit.hasBogie {
                let doors: [Float]=cab == 0 ? [-2.08,2.08] : [Float(-3.03),Float(0.28)].map { $0*cab }
                let bays: [(Float,Float)]=cab == 0 ? [(Float(0),Float(2.50))] : [(cab*(-1.40),Float(1.78)),(cab*1.95,Float(1.88))]
                for (x,w) in bays {
                    box(x,1.13,sign*1.338,w,0.008,1.43,glass)
                    box(x,2.50,sign*1.343,w*0.85,0.002,0.045,Map3DColor.shaded(Map3DPalette.glazing,0.45))
                }
                for x in doors {
                    box(x,0.38,sign*1.337,1.33,0.012,2.39,steel)
                    for leaf: Float in [-1,1] {
                        box(x+leaf*0.318,0.42,sign*1.347,0.612,0.008,2.31,ink)
                        box(x+leaf*0.318,1.18,sign*1.356,0.42,0.006,1.38,glass)
                        box(x+leaf*0.055,1.00,sign*1.362,0.018,0.010,0.20,white)
                    }
                    box(x,0.37,sign*1.352,1.36,0.065,0.035,white)
                }
                let hx: Float=cab == 0 ? 0 : cab*1.95
                box(hx,0.41,sign*1.335,cab == 0 ? 2.15 : 1.88,0.008,0.15,Map3DColor.shaded(blue,0.74))
                box(hx,0.43,sign*1.341,cab == 0 ? 2.09 : 1.82,0.004,0.11,blue)
            } else { box(0,1.13,sign*1.338,unit.length-0.62,0.008,1.43,glass) }
        }
        // Six joints. Each independently exported unit contains its own half.
        for sign: Float in [-1,1] where sign != cab {
            box(sign*(half+0.047),0.34,0,0.106,2.39,2.69,ink)
            for offset: Float in [0.016,0.046,0.076] {
                box(sign*(half+offset),0.38,0,0.018,2.47,2.63,Map3DColor.shaded(steel,0.70))
            }
            box(sign*(half+0.04),0.25,0,0.12,0.40,0.13,ink)
        }
        if cab != 0 {
            // Cap plates have explicit closed support volumes on the raked cap.
            func cap(_ outline: [(Float,Float)],_ lift: Float,_ color: UInt32) {
                let front=outline.map { Map3DPoint(nose($0.0)+cab*lift,$0.0,$0.1) }
                let back=outline.map { Map3DPoint(nose($0.0)-cab*0.002,$0.0,$0.1) }
                let c=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                face(front,inside:c,color:color);face(back,inside:c,color:color)
                for i in front.indices { let j=(i+1)%front.count;face([front[i],front[j],back[j],back[i]],inside:c,color:color) }
            }
            cap([(0.52,-1.01),(0.52,1.01),(2.84,1.01),(3.06,0.87),(3.06,-0.87),(2.84,-1.01)],0.007,blue)
            cap([(0.75,-0.96),(0.75,0.96),(2.82,0.96),(2.97,0.84),(2.97,-0.84),(2.82,-0.96)],0.014,ink)
            cap([(1.02,-0.86),(1.02,0.86),(2.76,0.86),(2.76,-0.86)],0.022,glass)
            for sign: Float in [-1,1] {
                cap([(0.80,sign*0.67-0.16),(0.80,sign*0.67+0.16),(0.88,sign*0.67+0.16),(0.92,sign*0.67-0.16)],0.023,white)
            }
            let r=station(cab*root),t=station(cab*half)
            for (a,b) in [(2,3),(8,9)] {
                let triangles=cab>0 ? [[r[a],r[b],t[b]],[r[a],t[b],t[a]]] : [[t[a],t[b],r[b]],[t[a],r[b],r[a]]]
                for triangle in triangles {
                    let mid=triangle.reduce(Map3DPoint.zero) { $0+$1*(1/3) }
                    var normal=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized!
                    if normal.dot(mid-inside)<0 { normal=normal * -1 }
                    // Clip a pane to this actual shell triangle. This low-level
                    // planar clipping method is shared practice, not a reused cab.
                    func clip(_ ps: [Map3DPoint],_ distance: (Map3DPoint)->Float) -> [Map3DPoint] {
                        guard !ps.isEmpty else { return [] };var result: [Map3DPoint]=[]
                        for i in ps.indices {
                            let p=ps[i],q=ps[(i+1)%ps.count],dp=distance(p),dq=distance(q)
                            if dp>=0 { result.append(p) }
                            if (dp>=0) != (dq>=0) { result.append(p+(q-p)*(dp/(dp-dq))) }
                        };return result
                    }
                    for (bottom,top,inset,lift,color): (Float,Float,Float,Float,UInt32) in [(0.72,2.80,0.03,0.008,ink),(1.10,2.70,0.13,0.017,glass)] {
                        var polygon=clip(triangle) { $0.y-bottom }
                        polygon=clip(polygon) { top-$0.y };polygon=clip(polygon) { $0.x*cab-root-0.025 }
                        polygon=clip(polygon) { half-inset-($0.x*cab+max(0,$0.y-0.36)*0.255) }
                        guard polygon.count>=3 else { continue }
                        let front=polygon.map { $0+normal*lift },back=polygon.map { $0-normal*0.002 }
                        let c=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                        face(front,inside:c,color:color);face(back,inside:c,color:color)
                        for i in front.indices { let j=(i+1)%front.count;face([front[i],front[j],back[j],back[i]],inside:c,color:color) }
                    }
                }
            }
        }
        let boxes: [Float]=unit.hasBogie ? cab == 0 ? [-1.38,1.38] : [-2.65,-0.45,1.72] : [0]
        for x in boxes {
            box(x,3.25,0,unit.hasBogie ? 1.44 : 2.22,1.28,0.028,ink)
            box(x,3.276,0,unit.hasBogie ? 1.35 : 2.13,1.18,0.095,steel)
        }
        if unit == .trailing {
            box(-0.45,3.371,0,1.22,1.10,0.07,ink)
            for sign: Float in [-1,1] {
                cylinder(-0.45,3.44,sign*0.39,radius:0.07,height:0.13,color:white,sides:8)
                beam(Map3DPoint(-0.45,3.55,sign*0.39),Map3DPoint(0.33,4.02,sign*0.39),0.043,steel)
                beam(Map3DPoint(0.33,4.02,sign*0.39),Map3DPoint(-0.26,4.45,sign*0.39),0.037,steel)
            }
            box(-0.26,4.42,0,0.16,1.70,0.045,ink)
        }
    }
}
