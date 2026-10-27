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
            panel(0,1.61,length-0.10,0.072,blue,0.046)
            panel(0,1.78,length-0.10,0.11,blue,0.046)
            panel(0,1.14,length-0.10,0.07,blue,0.046)
        } else { panel(0,1.43,length-0.10,0.27,blue,0.047) }
        for bx:Float in [-8.25,8.25] {
            kit.box(bx,0.57,0,3.35,2.0,0.24,steel)
            kit.box(bx,0.75,0,1.35,1.60,0.11,ink)
            for dx:Float in [-1.15,1.15] { for side:Float in [-1,1] {
                kit.civicTube(Map3DPoint(bx+dx,0.425,side*0.69),Map3DPoint(bx+dx,0.425,side*0.86),radius:0.425,color:Map3DStreetModel.tyre,sides:12)
            } }
        }
        for x:Float in trailer ? [-4.0,0,4.0] : [-4.6,-1.6,1.6,4.6] { kit.box(x,0.60,0,2.2,1.75,0.34,steel) }
        for x:Float in [-5.75,5.75] { kit.box(x,3.61,0,4.1,1.7,0.11,steel) }
        for x:Float in [-half+0.04,half-0.04] where x < 0 || !cab { kit.box(x,1.03,0,0.13,1.5,2.30,ink) }
        for end:Float in [-1,1] { kit.box(end*(length/2-0.015),0.66,0,0.15,0.28,0.18,ink) }
        if cab {
            // Independent front treatments: upright twin C371 panes, versus C381's
            // broad wrapped windshield and glazed emergency exit with lower skirt.
            facePanel(0,2.63,2.95,1.43,ink)
            if curved {
                facePanel(0,2.48,0.64,1.03,glass,0.052)
                for s:Float in [-1,1] { facePanel(s*0.91,2.58,0.93,1.04,glass,0.055) }
                facePanel(0,1.04,3.03,0.40,body,0.060)
                facePanel(0,1.52,3.07,0.20,blue,0.065)
                facePanel(0,0.67,2.84,0.30,ink,0.065)
            } else {
                facePanel(0,2.53,0.66,1.01,body,0.054)
                for s:Float in [-1,1] { facePanel(s*0.93,2.56,0.88,0.98,glass,0.060) }
                facePanel(0,1.50,3.01,0.27,blue,0.066)
                facePanel(0,0.91,2.85,0.25,ink,0.060)
            }
            for s:Float in [-1,1] {
                facePanel(s*1.06,1.64,0.54,0.20,Map3DPalette.tunnelLamp,0.078)
                kit.beam(Map3DPoint(half+0.02,2.02,s*0.91),Map3DPoint(half+0.02,2.42,s*0.73),0.021,ink)
            }
        }
    }
}
