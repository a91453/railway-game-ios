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
    var ink: UInt32 { curved ? Map3DPalette.playerRim : Map3DColor.shaded(Map3DPalette.tankStand,0.42) }
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
            return Map3DPoint(x,h-taper*0.11-drop,max(-1.59,min(1.59,z*(1-taper*0.095))))
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
            // Two planar halves share the same shallow transverse bow.
            // A fan across a nonlinear surface made the silver backing poke
            // through the mask, despite each solid being closed.
            for side: Float in [-1,1] {
                var clipped: [(Float,Float)] = []
                for i in yz.indices {
                    let a=yz[i], b=yz[(i+1)%yz.count]
                    let insideA=a.1*side >= 0, insideB=b.1*side >= 0
                    if insideA { clipped.append(a) }
                    if insideA != insideB {
                        let t = -a.1/(b.1-a.1)
                        if t > 0 && t < 1 { clipped.append((a.0+t*(b.0-a.0),0)) }
                    }
                }
                guard clipped.count >= 3 else { continue }
                func layer(_ offset: Float) -> [Map3DPoint] {
                    clipped.map { h,z in Map3DPoint(half+0.048+0.09*(1-abs(z)/1.62)+lift+offset,h,z) }
                }
                prism(layer(-thickness),layer(0),color)
            }
        }
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
        let doorEdge = curved ? ink : Map3DColor.shaded(body,0.70)
        for d in doors {
            panel(d,1.12,1.48,2.03,doorEdge,0.019)
            for leaf:Float in [-1,1] {
                panel(d+leaf*0.365,1.14,0.70,1.99,body,0.030)
                panel(d+leaf*0.365,2.25,0.36,0.67,glass,0.041)
            }
        }
        for x:Float in [-10.05,-6.18,-4.25,-0.96,0.96,4.25,6.18] {
            panel(x,curved ? 2.19 : 2.17,curved ? 1.48 : 1.42,curved ? 0.86 : 0.92,curved ? ink : steel)
            panel(x,curved ? 2.23 : 2.20,curved ? 1.40 : 1.36,curved ? 0.78 : 0.84,glass,0.027)
        }
        if !cab {
            panel(10.05,curved ? 2.19 : 2.17,curved ? 1.48 : 1.42,curved ? 0.86 : 0.92,curved ? ink : steel)
            panel(10.05,curved ? 2.23 : 2.20,curved ? 1.40 : 1.36,curved ? 0.78 : 0.84,glass,0.027)
        }
        else {
            panel(9.58,1.18,0.60,1.96,curved ? ink : doorEdge)
            panel(9.58,2.24,0.40,0.73,glass,0.030)
            panel(10.44,2.18,0.66,0.92,glass,0.031)
        }
        // C371 has one waist stripe. C381's two fine lines run below the windows.
        if curved {
            panel(0,1.43,length-0.10,0.30,blue,0.046)
            panel(0,1.17,length-0.10,0.065,blue,0.046)
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
                frontPatch(roundRect(-1.48,1.48,1.85,3.47,0.22),ink)
                for sign:Float in [-1,1] {
                    let l:Float = sign < 0 ? -1.35 : 0.45
                    let r:Float = sign < 0 ? -0.45 : 1.35
                    frontPatch(roundRect(l,r,2.10,3.22,0.13),glass,lift:0.026)
                }
                // The evacuation door has its own window and visible surround.
                frontPatch(roundRect(-0.40,0.40,1.94,3.29,0.10),steel,lift:0.024)
                frontPatch(roundRect(-0.34,0.34,2.03,3.19,0.085),glass,lift:0.044)
                // Real-world logo omitted; broad blue wings dip at the centre.
                let wing: [(Float,Float,Float)] = [(-1.48,1.49,1.71),(-1.12,1.49,1.71),(-0.72,1.35,1.55),(0,1.21,1.42),(0.72,1.35,1.55),(1.12,1.49,1.71),(1.48,1.49,1.71)]
                for i in 0..<(wing.count-1) {
                    let a=wing[i],b=wing[i+1]
                    frontPatch([(a.1,a.0),(b.1,b.0),(b.2,b.0),(a.2,a.0)],blue,lift:0.047)
                }
                frontPatch([(0.68,-1.40),(0.68,1.40),(0.99,1.40),(0.99,-1.40)],body,lift:0.044)
                frontPatch([(0.99,-1.43),(0.99,1.43),(1.055,1.43),(1.055,-1.43)],ink,lift:0.062)
            } else {
                // A shallow rounded silver end cap gives the fascia real
                // shoulders and a curved chin instead of a square slab.
                frontPatch([(1.00,-1.35),(1.08,-1.50),(3.03,-1.53),(3.27,-1.46),
                            (3.43,-1.25),(3.53,-0.87),(3.55,0),(3.53,0.87),
                            (3.43,1.25),(3.27,1.46),(3.03,1.53),(1.08,1.50),(1.00,1.35)],
                           body,lift:-0.027,thickness:0.15)
                frontPatch([(1.82,-1.23),(1.86,-1.36),(1.99,-1.43),(3.18,-1.43),
                            (3.29,-1.34),(3.36,-1.12),(3.40,-0.70),(3.42,0),
                            (3.40,0.70),(3.36,1.12),(3.29,1.34),(3.18,1.43),
                            (1.99,1.43),(1.86,1.36),(1.82,1.23)],ink)
                for sign:Float in [-1,1] {
                    let l:Float = sign < 0 ? -1.32 : 0.48
                    let r:Float = sign < 0 ? -0.48 : 1.32
                    frontPatch(roundRect(l,r,1.96,3.10,0.135),glass,lift:0.025)
                }
                frontPatch(roundRect(-0.385,0.385,1.90,3.31,0.045,steps:2),Map3DColor.shaded(steel,0.55),lift:0.024)
                frontPatch(roundRect(-0.355,0.355,1.94,3.27,0.035,steps:2),ink,lift:0.041)
                // The dark upper sign bay, unlettered to avoid route identity,
                // and the small red centre marker sit within the front mask.
                frontPatch([(3.17,0.66),(3.17,1.31),(3.32,1.31),(3.32,0.66)],Map3DColor.shaded(ink,0.82),lift:0.022)
                frontPatch([(3.29,-0.075),(3.29,0.075),(3.40,0.075),(3.40,-0.075)],Map3DColor.rgb(0xD9473F),lift:0.024)
                frontPatch([(1.38,-1.50),(1.38,1.50),(1.73,1.50),(1.73,-1.50)],blue,lift:0.045)
                frontPatch([(0.80,-1.43),(0.80,1.43),(0.91,1.43),(0.91,-1.43)],steel,lift:0.045)
                // The gangway continues below the black glazing into the
                // silver apron; the blue band stays continuous across it.
                frontPatch([(0.94,-0.38),(0.94,0.38),(1.38,0.38),(1.38,-0.38)],Map3DColor.shaded(body,0.86),lift:0.061)
                frontPatch([(0.95,-0.34),(0.95,0.34),(1.37,0.34),(1.37,-0.34)],body,lift:0.073)
                for side:Float in [-1,1] {
                    frontPatch([(3.00,side*0.57),(3.00,side*1.21),(3.045,side*1.21),(3.045,side*0.57)],Map3DPalette.shopAwnings[0],lift:0.053)
                }
                kit.box(half+0.13,0.62,0,0.21,0.62,0.23,ink)
                kit.box(half+0.28,0.64,0,0.17,0.31,0.10,steel)
            }
            // Distinct headlamp pods; two visible lenses per side and supported wipers.
            for sign:Float in [-1,1] {
                let x=half+(curved ? 0.225 : 0.12)
                let z=sign*1.05
                if curved {
                    kit.box(x,1.37,z,0.05,0.69,0.31,ink)
                } else {
                    frontPatch(roundRect(z-0.31,z+0.31,1.405,1.635,0.105,steps:2),ink,lift:0.057,thickness:0.025)
                }
                for shift:Float in [-0.17,0.17] {
                    let zz=z+shift
                    let lensX = curved ? x+0.035 : half+0.048+0.09*(1-abs(zz)/1.62)+0.052
                    kit.civicTube(Map3DPoint(lensX,1.53,zz),Map3DPoint(curved ? x+0.057 : lensX+0.022,1.53,zz),radius:curved ? 0.105 : 0.087,color:shift*sign<0 ? Map3DPalette.tunnelLamp : steel,sides:12)
                }
                if curved {
                    kit.civicTube(Map3DPoint(x,3.34,sign*1.23),Map3DPoint(x+0.02,3.34,sign*1.23),radius:0.045,color:Map3DPalette.tunnelLamp,sides:8)
                    kit.beam(Map3DPoint(x+0.04,2.01,sign*1.06),Map3DPoint(x+0.03,2.46,sign*0.61),0.018,ink)
                } else {
                    let markerX=half+0.048+0.09*(1-1.23/1.62)
                    kit.civicTube(Map3DPoint(markerX,3.34,sign*1.23),Map3DPoint(markerX+0.02,3.34,sign*1.23),radius:0.045,color:Map3DPalette.tunnelLamp,sides:8)
                    let footX=half+0.048+0.09*(1-1.06/1.62)+0.029
                    let tipX=half+0.048+0.09*(1-0.61/1.62)+0.029
                    kit.beam(Map3DPoint(footX,1.99,sign*1.06),Map3DPoint(tipX,2.46,sign*0.61),0.018,ink)
                }
            }
            if curved { kit.box(half+0.10,3.31,0,0.035,0.35,0.11,ink) }
        }
    }
}
