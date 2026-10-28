import Foundation

/// Primitive construction only. Each train supplies its own stations, colour boundaries and fittings.
struct MetroStudyGeometry {
    var kit = StationKitBuilder()
    let cab: Bool
    let trailer: Bool
    let curved: Bool
    let length: Float
    let body: UInt32
    let blue: UInt32
    var ink: UInt32 { curved ? Map3DColor.shaded(Map3DPalette.tankStand,0.38) : Map3DColor.shaded(Map3DPalette.tankStand,0.42) }
    let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.62)
    let steel = StationKitBuilder.steel
    var half: Float { length / 2 - 0.18 }

    mutating func prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let centre = (a+b).reduce(Map3DPoint.zero) { $0 + $1 * (1 / Float(a.count+b.count)) }
        kit.face(a, inside: centre, color: color)
        kit.face(b, inside: centre, color: color)
        for i in a.indices { let j=(i+1)%a.count; kit.face([a[i],a[j],b[j],b[i]],inside:centre,color:color) }
    }
    func station(_ x: Float) -> [Map3DPoint] {
        // C381 has a longer rounded FRP front; C371 retains an upright face.
        let taper = cab && curved ? max(0,(x-(half-1.05))/1.05) : 0
        let plan: [(Float,Float)] = [(1.03,-1.38),(1.13,-1.56),(3.06,-1.59),(3.30,-1.52),(3.48,-1.31),(3.585,-0.92),(3.585,0),(3.585,0.92),(3.48,1.31),(3.30,1.52),(3.06,1.59),(1.13,1.56),(1.03,1.38)]
        return plan.map { h,z in
            // Only the upright C371 driving end: a shallow arched brow,
            // blending over the last 320 mm into the unchanged roof section.
            let brow = !curved && cab ? max(0, (x-(half-0.32))/0.32) : 0
            let drop = h > 3.29 ? brow * 0.11 * min(1,abs(z)/1.52) : 0
            let lateral=max(-1.59,min(1.59,z*(1-taper*(curved ? 0.025 : 0.095))))
            var height=h-taper*(curved ? 0.04 : 0.11)-drop
            let blend=curved ? taper : brow
            if cab && h>3.29 {
                let spring: Float = curved ? 3.17 : 3.18
                let rise: Float = curved ? 0.415 : 0.405
                let top=spring+rise*sqrtf(max(0,1-(lateral/1.55)*(lateral/1.55)))-0.008
                height=min(height,h+(top-h)*blend)
            }
            return Map3DPoint(curved ? x-taper*0.12 : x,height,lateral)
        }
    }
    mutating func panel(_ x:Float,_ bottom:Float,_ width:Float,_ height:Float,_ color:UInt32,_ depth:Float=0.018) {
        for side:Float in [-1,1] { kit.box(x,bottom,side*(1.59+depth/2),width,depth,height,color) }
    }
    mutating func facePanel(_ side:Float,_ height:Float,_ width:Float,_ tall:Float,_ color:UInt32,_ proud:Float=0.025) {
        // side is the cross-car coordinate, not a mirror of another model's geometry.
        let setback:Float = -0.015
        kit.box(half-setback+proud,height-tall/2,side,0.022,width,tall,color)
    }
    /// Closed curved fascia panel in builder metres (vertical, lateral), with solid support.
    mutating func frontPatch(_ yz: [(Float,Float)], _ color: UInt32, lift: Float = 0, thickness: Float = 0.034) {
        func face(_ offset: Float) -> [Map3DPoint] {
            yz.map { h,z in
                let crown: Float = curved ? 0.22 : 0.09
                let centre = max(0,1-abs(z)/1.62)
                let x=half+0.048+crown*centre*centre+lift+offset
                return Map3DPoint(x,h,z)
            }
        }
        if curved {
            prism(face(-thickness),face(0),color)
        } else {
            // Clip into shared lateral planes before triangulating the caps.
            // Only the outer perimeter gets side walls: no duplicate walls at
            // internal slice boundaries, and every layer uses the same bow.
            let knots: [Float] = [-1.62,-1.44,-1.20,-0.90,-0.60,-0.36,0.36,0.60,0.90,1.20,1.44,1.62]
            func clip(_ polygon: [(Float,Float)], at z: Float, greater: Bool) -> [(Float,Float)] {
                var result: [(Float,Float)] = []
                for i in polygon.indices {
                    let a=polygon[i], b=polygon[(i+1)%polygon.count]
                    let ia=greater ? a.1 >= z : a.1 <= z
                    let ib=greater ? b.1 >= z : b.1 <= z
                    if ia { result.append(a) }
                    if ia != ib {
                        let t=(z-a.1)/(b.1-a.1)
                        if t > 0 && t < 1 { result.append((a.0+t*(b.0-a.0),z)) }
                    }
                }
                return result
            }
            func point(_ p: (Float,Float), _ offset: Float) -> Map3DPoint {
                Map3DPoint(c371FaceX(p.1)+lift+offset,p.0,p.1)
            }
            let inside=Map3DPoint(half-0.10,2.15,0)
            for i in 0..<(knots.count-1) {
                let polygon=clip(clip(yz,at:knots[i],greater:true),at:knots[i+1],greater:false)
                if polygon.count < 3 { continue }
                kit.face(polygon.map { point($0,0) },inside:inside,color:color)
                // A distinct interior point keeps both caps outward even
                // when the backing layer is inside the original shell.
                let centre=polygon.map { point($0,-thickness/2) }.reduce(.zero,+)*(1/Float(polygon.count))
                kit.face(polygon.map { point($0,-thickness) },inside:centre,color:color)
            }
            for i in yz.indices {
                let a=yz[i], b=yz[(i+1)%yz.count]
                var ts: [Float] = [0,1]
                if a.1 != b.1 {
                    ts += knots.map { ($0-a.1)/(b.1-a.1) }.filter { $0 > 0 && $0 < 1 }
                }
                ts.sort()
                for j in 0..<(ts.count-1) {
                    func at(_ t: Float) -> (Float,Float) { (a.0+t*(b.0-a.0),a.1+t*(b.1-a.1)) }
                    let u=at(ts[j]), v=at(ts[j+1])
                    let centre=yz.map { point($0,-thickness/2) }.reduce(.zero,+)*(1/Float(yz.count))
                    kit.face([point(u,0),point(v,0),point(v,-thickness),point(u,-thickness)],inside:centre,color:color)
                }
            }
        }
    }
    func c371FaceX(_ lateral: Float) -> Float {
        let z=abs(lateral),knots: [Float] = [0.36,0.60,0.90,1.20,1.44,1.62]
        func bow(_ x: Float) -> Float { 0.13*(1-(x/1.62)*(x/1.62)) }
        if z<=knots[0] { return half+0.035+bow(knots[0]) }
        for i in 0..<(knots.count-1) where z<=knots[i+1] {
            let a=knots[i],b=knots[i+1]
            return half+0.035+bow(a)+(bow(b)-bow(a))*(z-a)/(b-a)
        }
        return half+0.035
    }
    func roundRect(_ left: Float,_ right: Float,_ low: Float,_ high: Float,_ r: Float, steps count: Int? = nil) -> [(Float,Float)] {
        let steps=count ?? (curved ? 5 : 4)
        let corners: [(Float,Float,Float)] = [(low+r,right-r,-Float.pi/2),(high-r,right-r,0),(high-r,left+r,Float.pi/2),(low+r,left+r,Float.pi)]
        return corners.flatMap { cy,cz,start in (0..<steps).map { i in
            let a=start+Float(i)*Float.pi/(2*Float(steps))
            return (cy+r*sinf(a),cz+r*cosf(a))
        } }
    }
    mutating func build() {
        let stations: [Float] = curved && cab ? [-half, half-1.05, half-0.52, half] : (cab ? [-half,half-0.32,half] : [-half,half])
        let rings=stations.map(station)
        for i in 0..<(rings.count-1) { for j in 0..<rings[i].count {
            let k=(j+1)%rings[i].count
            kit.face([rings[i][j],rings[i][k],rings[i+1][k],rings[i+1][j]],inside:Map3DPoint((stations[i]+stations[i+1])/2,2.1,0),color:body)
        } }
        kit.face(rings[0],inside:Map3DPoint(0,2.1,0),color:body)
        kit.face(rings[rings.count-1],inside:Map3DPoint(0,2.1,0),color:body)
        kit.box(0,0.92,0,length-0.25,2.45,0.12,steel)
        // Four double leaf doors, each with a separate pair of glass panes.
        let doors: [Float] = [-7.8,-2.6,2.6,7.8]
        let doorEdge = Map3DColor.shaded(body,curved ? 0.76 : 0.70)
        for d in doors {
            panel(d,1.12,1.48,2.03,doorEdge,0.019)
            for leaf:Float in [-1,1] {
                panel(d+leaf*0.365,1.14,0.70,1.99,body,0.030)
                panel(d+leaf*0.365,2.25,0.36,0.67,glass,0.041)
            }
        }
        for x:Float in [-10.05,-6.18,-4.25,-0.96,0.96,4.25,6.18] {
            panel(x,curved ? 2.19 : 2.17,curved ? 1.48 : 1.42,curved ? 0.86 : 0.92,curved ? Map3DColor.shaded(body,0.72) : steel)
            panel(x,curved ? 2.23 : 2.20,curved ? 1.40 : 1.36,curved ? 0.78 : 0.84,glass,0.027)
        }
        if !cab {
            panel(10.05,curved ? 2.19 : 2.17,curved ? 1.48 : 1.42,curved ? 0.86 : 0.92,curved ? Map3DColor.shaded(body,0.72) : steel)
            panel(10.05,curved ? 2.23 : 2.20,curved ? 1.40 : 1.36,curved ? 0.78 : 0.84,glass,0.027)
        }
        else {
            panel(9.58,1.18,0.60,1.96,doorEdge)
            panel(9.58,2.24,0.40,0.73,glass,0.030)
            panel(10.44,2.18,0.66,0.92,glass,0.031)
        }
        // C371 has one waist stripe. C381's two fine lines run below the windows.
        if curved {
            c381SideBands()
        } else { panel(0,1.43,length-0.10,0.30,blue,0.047) }
        panel(0,3.16,length-0.35,0.035,steel,0.018)
        for bx:Float in [-8.25,8.25] {
            kit.box(bx,0.57,0,3.35,2.0,0.24,steel)
            kit.box(bx,0.75,0,1.35,1.60,0.11,ink)
            for dx:Float in [-1.15,1.15] { for side:Float in [-1,1] {
                kit.civicTube(Map3DPoint(bx+dx,0.425,side*0.69),Map3DPoint(bx+dx,0.425,side*0.86),radius:0.425,color:Map3DStreetModel.tyre,sides:12)
                if !curved {
                    kit.civicTube(Map3DPoint(bx+dx,0.425,side*0.86),Map3DPoint(bx+dx,0.425,side*0.89),radius:0.19,color:steel,sides:10)
                }
            } }
            if !curved {
                for side:Float in [-1,1] { kit.box(bx,0.53,side*0.94,3.00,0.075,0.18,steel) }
            }
        }
        if cab && !curved {
            // Standard two-axle bogies: real axle shafts connect the existing
            // wheels. Tyre rings, hubs and rail contacts are unchanged.
            for bx: Float in [-8.25,8.25] { for dx: Float in [-1.15,1.15] {
                kit.civicTube(Map3DPoint(bx+dx,0.425,-0.70),Map3DPoint(bx+dx,0.425,0.70),radius:0.075,color:steel,sides:8)
            } }
        }
        for x:Float in trailer ? [-4.0,0,4.0] : [-4.6,-1.6,1.6,4.6] { kit.box(x,0.60,0,2.2,1.75,0.34,steel) }
        if curved {
            for x:Float in [-5.75,5.75] {
                kit.box(x,3.595,0,4.1,1.7,0.105,steel)
                for delta:Float in [-1.42,-0.72,0,0.72,1.42] { kit.box(x+delta,3.701,0,0.045,1.45,0.012,ink) }
            }
            for i in -12...12 {
                let x=Float(i)*0.82
                if abs(x+5.75)>2.3 && abs(x-5.75)>2.3 { kit.box(x,3.584,0,0.025,2.28,0.012,steel) }
            }
        } else {
            // C371 photos show continuous corrugation on the low roof,
            // with a few flush service grilles, not two exposed HVAC blocks.
            let roof=Map3DPalette.shedWalls[2]
            for i in -9...9 {
                let z=Float(i)*0.093
                kit.box(-0.15,3.579,z,length-1.25,0.018,0.012,roof)
            }
            for x:Float in [-8.65,8.65] {
                for side:Float in [-1,1] {
                    kit.box(x,3.579,side*0.87,0.43,0.24,0.025,steel)
                    for step:Float in [-0.12,0.12] { kit.box(x+step,3.601,side*0.87,0.025,0.21,0.008,ink) }
                }
            }
            for x:Float in [-10.9,10.7] { kit.box(x,3.579,0,0.045,2.52,0.018,steel) }
        }
        for x:Float in [-half+0.04,half-0.04] where x < 0 || !cab { kit.box(x,1.03,0,0.13,1.5,2.30,ink) }
        for end:Float in [-1,1] { kit.box(end*(length/2-0.015),0.66,0,0.15,0.28,0.18,ink) }
        if cab {
            // The two fascia profiles are separate, supported solids. C381 bends
            // 220 mm toward the centre; C371 is nearly vertical at the face.
            if curved {
                buildC381Cab()
            } else {
                // A shallow rounded silver end cap gives the fascia real
                // shoulders and a curved chin instead of a square slab.
                let brow = (-16...16).map { i -> (Float,Float) in
                    let a=Float(i)*Float.pi/32
                    return (3.18+0.405*cosf(a),1.55*sinf(a))
                }
                let endProfile: [(Float,Float)] = [(1.02,-1.43),(1.08,-1.53)] + brow + [(1.08,1.53),(1.02,1.43)]
                frontPatch(endProfile,body,lift:-0.027,thickness:0.15)
                let maskBrow = (-16...16).map { i -> (Float,Float) in
                    let a=Float(i)*Float.pi/32
                    return (3.14+0.30*cosf(a),1.43*sinf(a))
                }
                frontPatch([(1.82,-1.23),(1.86,-1.36),(1.99,-1.43)] + maskBrow +
                           [(1.99,1.43),(1.86,1.36),(1.82,1.23)],ink)
                for sign:Float in [-1,1] {
                    let l:Float = sign < 0 ? -1.32 : 0.48
                    let r:Float = sign < 0 ? -0.48 : 1.32
                    let pane=roundRect(l,r,1.96,3.10,0.10).map { h,z in
                        // Inboard upper edge follows the slightly raked real pane.
                        (h,z-sign*0.045*max(0,min(1,(h-1.96)/1.14)))
                    }
                    frontPatch(pane,glass,lift:0.025)
                }
                frontPatch(roundRect(-0.405,0.405,1.81,3.28,0.065,steps:3),Map3DColor.shaded(steel,0.55),lift:0.024)
                frontPatch(roundRect(-0.391,0.391,1.825,3.265,0.055,steps:3),ink,lift:0.041)
                // The dark upper sign bay, unlettered to avoid route identity,
                // and the small red centre marker sit within the front mask.
                frontPatch([(3.17,0.66),(3.17,1.31),(3.32,1.31),(3.32,0.66)],Map3DColor.shaded(ink,0.82),lift:0.022)
                frontPatch([(3.29,-0.075),(3.29,0.075),(3.40,0.075),(3.40,-0.075)],Map3DColor.rgb(0xD9473F),lift:0.024)
                frontPatch([(1.38,-1.50),(1.38,1.50),(1.73,1.50),(1.73,-1.50)],blue,lift:0.045)
                frontPatch([(0.96,-1.43),(0.96,1.43),(1.015,1.43),(1.015,-1.43)],steel,lift:0.045)
                // The gangway continues below the black glazing into the
                // silver apron; the blue band stays continuous across it.
                frontPatch([(0.94,-0.38),(0.94,0.38),(1.38,0.38),(1.38,-0.38)],Map3DColor.shaded(body,0.86),lift:0.061)
                frontPatch([(0.95,-0.34),(0.95,0.34),(1.37,0.34),(1.37,-0.34)],body,lift:0.073)
                for side:Float in [-1,1] {
                    frontPatch([(3.00,side*0.57),(3.00,side*1.21),(3.045,side*1.21),(3.045,side*0.57)],Map3DPalette.shopAwnings[0],lift:0.053)
                }
                // A low, backed rib panel; brackets remain behind the fascia
                // and touch both the floor and the shallow cross-member.
                frontPatch([(0.87,-1.42),(0.87,1.42),(1.02,1.42),(1.02,-1.42)],ink,lift:0.068,thickness:0.10)
                for h: Float in [0.89,0.935,0.98] {
                    frontPatch([(h,-1.42),(h,1.42),(h+0.012,1.42),(h+0.012,-1.42)],Map3DColor.shaded(steel,0.48),lift:0.077,thickness:0.018)
                }
                kit.box(half-0.25,0.84,0,0.26,2.12,0.12,ink)
                for sign: Float in [-1,1] { kit.box(half-0.16,0.74,sign*0.95,0.22,0.18,0.22,ink) }
                // The real C371 retains two round nose fittings. Keep them
                // small and dark, with a bracket joining the shallow beam.
                for sign: Float in [-1,1] {
                    kit.box(half-0.125,0.73,sign*1.11,0.17,0.28,0.16,ink)
                    kit.civicTube(Map3DPoint(half-0.06,0.68,sign*1.15),Map3DPoint(half+0.025,0.68,sign*1.15),radius:0.085,color:Map3DColor.shaded(steel,0.45),sides:12)
                    kit.civicTube(Map3DPoint(half+0.01,0.68,sign*1.15),Map3DPoint(half+0.03,0.68,sign*1.15),radius:0.044,color:ink,sides:12)
                }
                kit.box(half-0.17,0.65,0,0.22,0.28,0.31,ink)
                kit.box(half+0.02,0.60,0,0.22,0.26,0.15,ink)
                kit.box(half+0.17,0.64,0,0.13,0.22,0.12,steel)

            }
            // C371's rounded lamp apertures follow the nose's shared planes.
            for sign: Float in [-1,1] where !curved {
                let z=sign*1.04
                frontPatch(roundRect(z-0.335,z+0.335,1.385,1.655,0.110,steps:6),Map3DColor.shaded(body,0.72),lift:0.049,thickness:0.030)
                frontPatch(roundRect(z-0.320,z+0.320,1.400,1.640,0.103,steps:6),ink,lift:0.059,thickness:0.025)
                func circle(_ h: Float,_ z: Float,_ radius: Float) -> [(Float,Float)] {
                    (0..<20).map { i in let a=Float(i)*Float.pi/10;return (h+radius*sinf(a),z+radius*cosf(a)) }
                }
                for shift: Float in [-0.145,0.145] {
                    let zz=z+shift
                    frontPatch(circle(1.52,zz,0.091),steel,lift:0.069,thickness:0.025)
                    frontPatch(circle(1.52,zz,0.077),shift*sign<0 ? Map3DPalette.tunnelLamp : Map3DColor.rgb(0xD9473F),lift:0.079,thickness:0.020)
                    if shift*sign>0 { frontPatch(circle(1.52,zz,0.056),ink,lift:0.089,thickness:0.020) }
                }
                let markerX=c371FaceX(1.23)
                kit.civicTube(Map3DPoint(markerX,3.34,sign*1.23),Map3DPoint(markerX+0.02,3.34,sign*1.23),radius:0.045,color:Map3DPalette.tunnelLamp,sides:12)
                let footX=c371FaceX(1.06)+0.029,tipX=c371FaceX(0.61)+0.029
                kit.beam(Map3DPoint(footX,1.99,sign*1.06),Map3DPoint(tipX,2.46,sign*0.61),0.018,ink)
            }
        }
    }
}
