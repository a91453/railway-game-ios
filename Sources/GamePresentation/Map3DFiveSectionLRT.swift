import Foundation

/// Five articulated sections reconstructed from the owner's five new views.
/// Static library asset. Not an operational train type or an animated rig.
/// Authoring x forward / y up / z right -> Model.flat -> native x forward / y left / z up.
public enum Map3DFiveSectionLRT {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, suspendedFront, middle, suspendedRear, trailing
        public var length: Float {
            switch self { case .leading, .trailing: 9; case .middle: 7; default: 4.1 }
        }
        public var centre: Float {
            switch self { case .leading: 12.5; case .suspendedFront: 5.75; case .middle: 0; case .suspendedRear: -5.75; case .trailing: -12.5 }
        }
    }
    public static let coral = Map3DPalette.shopAwnings[1]
    public static let cream = Map3DPalette.shopAwnings[3]
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing,0.62)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.fiveSectionLRT(unit)
        return .flat(named: "lrt-five-\(unit.rawValue)", from: b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for unit in Unit.allCases { b.add(model(unit), at: Map3DPoint(unit.centre, 0, 0)) }
        return .flat(named: "lrt-five-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    mutating func fiveSectionLRT(_ unit: Map3DFiveSectionLRT.Unit) {
        let coral = Map3DFiveSectionLRT.coral, cream = Map3DFiveSectionLRT.cream
        let glass = Map3DFiveSectionLRT.glass, ink = Self.ink, steel = Self.steel
        let half = unit.length / 2
        let cab: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let suspended = unit == .suspendedFront || unit == .suspendedRear
        let centre = Map3DPoint(0, 1.6, 0)
        // Low skirt, upright glazing, chamfered shoulder. A raked AND narrowed
        // outer cap forms each nose; none of the older tram geometry is reused.
        let section: [(Float, Float)] = [
            (0.22,-1.16),(0.35,-1.325),(2.95,-1.325),(3.25,-1.10),
            (3.25,1.10),(2.95,1.325),(0.35,1.325),(0.22,1.16)
        ]
        func endX(_ h: Float, lift: Float = 0) -> Float { cab * (half - max(0,h-0.35)*0.23 + lift) }
        func ring(_ x: Float) -> [Map3DPoint] {
            section.map { h,z in
                let outer = cab != 0 && x*cab > half-0.01
                return Map3DPoint(outer ? endX(h) : x,h,z*(outer ? 0.88 : 1))
            }
        }
        let xs: [Float] = [-half,-half+1.3,half-1.3,half]
        let rings = xs.map(ring)
        for k in 0..<3 { for i in section.indices {
            let j = (i+1)%section.count
            let color = i == 7 ? ink : ([1,5].contains(i) ? cream : coral)
            face([rings[k][i],rings[k][j],rings[k+1][j]],inside:centre,color:color)
            face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:centre,color:color)
        } }
        face(rings[0],inside:centre,color:cab < 0 ? coral : cream)
        face(rings[3],inside:centre,color:cab > 0 ? coral : cream)
        box(0,0.28,0,unit.length-0.55,2.27,0.20,ink)
        // Three bogies for the full set: end modules + centre. Short sections
        // are genuinely suspended. Wheels hidden by the skirt remain real mesh.
        if !suspended {
            let bx: Float = cab == 0 ? 0 : cab*1.1
            box(bx,0.30,0,2.30,1.95,0.24,ink)
            for dx: Float in [-0.75,0.75] {
                civicTube(Map3DPoint(bx+dx,0.29,-1.12),Map3DPoint(bx+dx,0.29,1.12),radius:0.065,color:steel,sides:8)
                for sign: Float in [-1,1] {
                    civicTube(Map3DPoint(bx+dx,0.29,sign*0.94),Map3DPoint(bx+dx,0.29,sign*1.11),radius:0.29,color:Map3DStreetModel.tyre,sides:12)
                    civicTube(Map3DPoint(bx+dx,0.29,sign*1.11),Map3DPoint(bx+dx,0.29,sign*1.125),radius:0.14,color:steel,sides:10)
                }
            }
        }
        // Flush side panels, opaque matte glazing; all sheets are closed solids.
        // Long modules: two double doors each side. Short modules: one broad bay.
        for sign: Float in [-1,1] {
            let bandEnd = cab == 0 ? half-0.12 : half-1.31
            let lo: Float = cab < 0 ? -bandEnd : -half+0.12
            let hi: Float = cab > 0 ? bandEnd : half-0.12
            box((lo+hi)/2,0.70,sign*1.328,hi-lo,0.010,2.22,ink)
            box((lo+hi)/2,0.40,sign*1.328,hi-lo,0.010,0.26,coral)
            if suspended {
                box(0,1.12,sign*1.338,unit.length-0.60,0.008,1.46,glass)
            } else {
                // Cab end door rhythm extends inward from the sloping nose.
                let doors: [Float] = cab == 0 ? [-2.10,2.10] : [Float(-3.12),Float(0.10)].map { $0*cab }
                let windows: [(Float,Float)] = cab == 0 ? [(Float(0),Float(2.64))] : [(cab*(-1.51),Float(1.78)),(cab*1.84,Float(1.90))]
                for (x,w) in windows {
                    box(x,1.12,sign*1.338,w,0.008,1.46,glass)
                    box(x,2.53,sign*1.343,w*0.82,0.002,0.045,Map3DColor.shaded(Map3DPalette.glazing,0.45))
                }
                for x in doors {
                    box(x,0.35,sign*1.340,1.35,0.010,2.55,steel)
                    for leaf: Float in [-1,1] {
                        box(x+leaf*0.326,0.39,sign*1.350,0.625,0.008,2.46,ink)
                        box(x+leaf*0.326,1.26,sign*1.358,0.43,0.006,1.36,glass)
                        box(x+leaf*0.055,0.98,sign*1.363,0.018,0.009,0.21,cream)
                    }
                    box(x,0.35,sign*1.357,1.37,0.07,0.035,cream)
                }
                // Shallow equipment hatch stays attached to the low skirt.
                let hx: Float = cab == 0 ? 0 : cab*1.72
                box(hx,0.45,sign*1.336,cab == 0 ? 1.9 : 1.55,0.008,0.15,Map3DColor.shaded(coral,0.78))
                box(hx,0.47,sign*1.342,cab == 0 ? 1.84 : 1.49,0.004,0.11,coral)
            }
        }
        // Independent unit owns one half of each bellows and its coupling.
        // Nominal shell gap .20 m: each half reaches .10 m beyond its end.
        for sign: Float in [-1,1] where sign != cab {
            box(sign*(half+0.048),0.33,0,0.104,2.40,2.73,ink)
            for step: Float in [0,1,2] {
                box(sign*(half+0.014+step*0.029),0.37,0,0.018,2.48,2.68,Map3DColor.shaded(steel,0.69))
            }
            box(sign*(half+0.04),0.24,0,0.13,0.42,0.14,ink)
        }
        if cab != 0 {
            // Convex extruded cap pieces follow the same nose plane exactly.
            func plate(_ points: [(Float,Float)], _ lift: Float, _ color: UInt32) {
                let a=points.map { Map3DPoint(endX($0.0,lift:lift),$0.0,$0.1) }
                let b=points.map { Map3DPoint(endX($0.0,lift:-0.002),$0.0,$0.1) }
                let c=(a+b).reduce(Map3DPoint.zero) { $0+$1*(1/Float(a.count+b.count)) }
                face(a,inside:c,color:color);face(b,inside:c,color:color)
                for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:c,color:color) }
            }
            plate([(0.65,-1.01),(0.65,1.01),(2.91,1.01),(3.05,0.91),(3.05,-0.91),(2.91,-1.01)],0.010,ink)
            plate([(1.02,-0.91),(1.02,0.91),(2.81,0.91),(2.81,-0.91)],0.019,glass)
            for sign: Float in [-1,1] {
                plate([(0.78,sign*0.68-0.17),(0.78,sign*0.68+0.17),(0.86,sign*0.68+0.17),(0.90,sign*0.68-0.17)],0.021,cream)
            }
            // Clip the actual two shell triangles against the window aperture.
            // Interpolating a rectangle across this twisted quad caused a hole;
            // each new pane now lies on its own supporting triangle plane.
            let root=ring(cab*(half-1.3)),tip=ring(cab*half)
            for pair in [(1,2),(5,6)] {
                let a=root[pair.0],b=root[pair.1],c=tip[pair.1],d=tip[pair.0]
                for triangle in [[a,b,c],[a,c,d]] {
                    let mid=triangle.reduce(Map3DPoint.zero) { $0+$1*(1/3) }
                    var n=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized!
                    if n.dot(mid-centre)<0 { n=n * -1 }
                    func clip(_ points: [Map3DPoint],_ distance: (Map3DPoint)->Float) -> [Map3DPoint] {
                        guard !points.isEmpty else { return [] }
                        var out: [Map3DPoint]=[]
                        for i in points.indices {
                            let a=points[i],b=points[(i+1)%points.count],da=distance(a),db=distance(b)
                            if da>=0 { out.append(a) }
                            if (da>=0) != (db>=0) { out.append(a+(b-a)*(da/(da-db))) }
                        }
                        return out
                    }
                    for (h0,h1,x0,inset,lift,color): (Float,Float,Float,Float,Float,UInt32) in [
                        (0.70,2.92,half-1.299,0.025,0.007,ink),
                        (1.10,2.78,half-1.25,0.12,0.016,glass)
                    ] {
                        var pane=triangle
                        pane=clip(pane) { $0.y-h0 };pane=clip(pane) { h1-$0.y }
                        pane=clip(pane) { $0.x*cab-x0 }
                        pane=clip(pane) { half-inset-($0.x*cab+max(0,$0.y-0.35)*0.23) }
                        guard pane.count>=3 else { continue }
                        let front=pane.map { $0+n*lift },back=pane.map { $0-n*0.002 }
                        let inside=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                        face(front,inside:inside,color:color);face(back,inside:inside,color:color)
                        for i in front.indices { let j=(i+1)%front.count
                            face([front[i],front[j],back[j],back[i]],inside:inside,color:color)
                        }
                    }
                }
            }
        }
        // Equipment is intentionally broad and low, as in the reference.
        let roofXs: [Float] = suspended ? [0] : cab == 0 ? [-1.35,1.35] : [-2.6,-0.5,1.6]
        for x in roofXs {
            box(x,3.25,0,suspended ? 2.25 : 1.42,1.32,0.035,ink)
            box(x,3.28,0,suspended ? 2.10 : 1.32,1.20,0.10,steel)
        }
        // Only the trailing outer module carries a supported single-arm panto.
        if unit == .trailing {
            box(-0.5,3.38,0,1.25,1.12,0.075,ink)
            for sign: Float in [-1,1] {
                cylinder(-0.5,3.45,sign*0.40,radius:0.075,height:0.13,color:cream,sides:8)
                beam(Map3DPoint(-0.5,3.56,sign*0.40),Map3DPoint(0.32,4.05,sign*0.40),0.045,steel)
                beam(Map3DPoint(0.32,4.05,sign*0.40),Map3DPoint(-0.30,4.53,sign*0.40),0.038,steel)
            }
            box(-0.3,4.50,0,0.16,1.72,0.045,ink)
        }
    }
}
