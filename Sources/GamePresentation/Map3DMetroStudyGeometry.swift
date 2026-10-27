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
    let ink = Map3DPalette.playerRim
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
        return plan.map { h,z in Map3DPoint(x,h-taper*0.11,max(-1.59,min(1.59,z*(1-taper*0.095)))) }
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
    mutating func frontPatch(_ yz: [(Float,Float)], _ color: UInt32, lift: Float = 0) {
        func face(_ offset: Float) -> [Map3DPoint] {
            yz.map { h,z in
                let crown: Float = curved ? 0.22 : 0.025
                let centre = max(0,1-abs(z)/1.62)
                let x=half+0.048+crown*centre*centre+lift+offset
                return Map3DPoint(x,h,z)
            }
        }
        prism(face(-0.034),face(0),color)
    }
    func roundRect(_ left: Float,_ right: Float,_ low: Float,_ high: Float,_ r: Float) -> [(Float,Float)] {
        let steps=curved ? 5 : 4
        let corners: [(Float,Float,Float)] = [(low+r,right-r,-Float.pi/2),(high-r,right-r,0),(high-r,left+r,Float.pi/2),(low+r,left+r,Float.pi)]
        return corners.flatMap { cy,cz,start in (0..<steps).map { i in
            let a=start+Float(i)*Float.pi/(2*Float(steps))
            return (cy+r*sinf(a),cz+r*cosf(a))
        } }
    }
    mutating func build() {
        let stations: [Float] = curved && cab ? [-half, half-1.05, half-0.52, half] : [-half,half]
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
        for d in doors {
            panel(d,1.12,1.48,2.03,ink,0.019)
            for leaf:Float in [-1,1] {
                panel(d+leaf*0.365,1.14,0.70,1.99,body,0.030)
                panel(d+leaf*0.365,2.25,0.36,0.67,glass,0.041)
            }
        }
        for x:Float in [-10.05,-6.18,-4.25,-0.96,0.96,4.25,6.18] {
            panel(x,2.19,1.48,0.86,ink)
            panel(x,2.23,1.40,0.78,glass,0.027)
        }
        if !cab { panel(10.05,2.19,1.48,0.86,ink);panel(10.05,2.23,1.40,0.78,glass,0.027) }
        else {
            panel(9.58,1.18,0.60,1.96,ink)
            panel(9.58,2.24,0.40,0.73,glass,0.030)
            panel(10.44,2.18,0.66,0.92,glass,0.031)
        }
        // C371 has one waist stripe. C381's two fine lines run below the windows.
        if curved {
            panel(0,1.43,length-0.10,0.30,blue,0.046)
            panel(0,1.17,length-0.10,0.065,blue,0.046)
        } else { panel(0,1.43,length-0.10,0.27,blue,0.047) }
        panel(0,3.16,length-0.35,0.035,steel,0.018)
        for bx:Float in [-8.25,8.25] {
            kit.box(bx,0.57,0,3.35,2.0,0.24,steel)
            kit.box(bx,0.75,0,1.35,1.60,0.11,ink)
            for dx:Float in [-1.15,1.15] { for side:Float in [-1,1] {
                kit.civicTube(Map3DPoint(bx+dx,0.425,side*0.69),Map3DPoint(bx+dx,0.425,side*0.86),radius:0.425,color:Map3DStreetModel.tyre,sides:12)
            } }
        }
        for x:Float in trailer ? [-4.0,0,4.0] : [-4.6,-1.6,1.6,4.6] { kit.box(x,0.60,0,2.2,1.75,0.34,steel) }
        for x:Float in [-5.75,5.75] {
            kit.box(x,3.595,0,4.1,1.7,0.105,steel)
            for delta:Float in [-1.42,-0.72,0,0.72,1.42] { kit.box(x+delta,3.701,0,0.045,1.45,0.012,ink) }
        }
        for i in -12...12 {
            let x=Float(i)*0.82
            if abs(x+5.75)>2.3 && abs(x-5.75)>2.3 { kit.box(x,3.584,0,0.025,2.28,0.012,steel) }
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
                frontPatch(roundRect(-1.47,1.47,1.79,3.42,0.12),ink)
                for sign:Float in [-1,1] {
                    let l:Float = sign < 0 ? -1.32 : 0.48
                    let r:Float = sign < 0 ? -0.48 : 1.32
                    frontPatch(roundRect(l,r,2.07,3.13,0.075),glass,lift:0.025)
                }
                frontPatch(roundRect(-0.42,0.42,1.91,3.30,0.06),steel,lift:0.026)
                frontPatch(roundRect(-0.35,0.35,2.04,3.14,0.045),ink,lift:0.042)
                frontPatch([(1.38,-1.50),(1.38,1.50),(1.73,1.50),(1.73,-1.50)],blue,lift:0.045)
                frontPatch([(0.72,-1.43),(0.72,1.43),(0.93,1.43),(0.93,-1.43)],ink,lift:0.045)
            }
            // Distinct headlamp pods; two visible lenses per side and supported wipers.
            for sign:Float in [-1,1] {
                let x=half+(curved ? 0.225 : 0.085)
                let z=sign*1.05
                kit.box(x,1.37,z,0.05,0.69,0.31,ink)
                for shift:Float in [-0.17,0.17] {
                    let zz=z+shift
                    kit.civicTube(Map3DPoint(x+0.035,1.53,zz),Map3DPoint(x+0.057,1.53,zz),radius:0.105,color:shift*sign<0 ? Map3DPalette.tunnelLamp : steel,sides:12)
                }
                kit.civicTube(Map3DPoint(x,3.34,sign*1.23),Map3DPoint(x+0.02,3.34,sign*1.23),radius:0.045,color:Map3DPalette.tunnelLamp,sides:8)
                kit.beam(Map3DPoint(x+0.04,2.01,sign*1.06),Map3DPoint(x+0.03,2.46,sign*0.61),0.018,ink)
            }
            kit.box(half+0.10,3.31,0,0.035,0.35,0.11,ink)
        }
    }
}
