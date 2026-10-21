import Foundation

extension StationKitBuilder {
    private var wallColor: UInt32 { Map3DPalette.concreteWalls[0] }
    private var trimColor: UInt32 { Map3DPalette.playerRim }

    mutating func residentialWindow(_ x: Float,_ y: Float,_ z: Float,width: Float = 1.1,height: Float = 1.35) {
        // Recessed two-sash window. Every pane has an opaque reveal and wall
        // behind it; separate depths avoid coplanar glass/frame flicker.
        box(x-0.055,y-0.04,z,0.12,width+0.18,height+0.15,wallColor)
        box(x+0.015,y+0.03,z,0.035,width,height+0.02,trimColor)
        for side: Float in [-1,1] {
            box(x+0.04,y+0.10,z+side*width*0.25,0.025,width*0.5-0.085,height-0.14,Self.glass)
            box(x+0.065,y+0.02,z+side*(width*0.5+0.015),0.08,0.075,height+0.07,Self.white)
        }
        box(x+0.065,y+0.02,z,0.08,0.07,height+0.07,Self.white)
        box(x+0.065,y+height+0.02,z,0.08,width+0.18,0.08,Self.white)
        box(x+0.08,y-0.055,z,0.18,width+0.27,0.085,Map3DPalette.concrete)
    }
    mutating func residentialDoor(_ x: Float,_ y: Float,_ z: Float,width: Float = 1.3) {
        box(x,y,z,0.13,width,2.15,Map3DPalette.counters[1])
        box(x+0.075,y+0.10,z,0.025,width-0.16,1.85,trimColor)
        cylinder(x+0.10,y+1.0,z+width*0.34,radius:0.045,height:0.10,color:Map3DPalette.platformEdge,sides:8)
    }
    mutating func residentialBalcony(_ x: Float,_ y: Float,_ z: Float,width: Float) {
        // A walkable slab with a front parapet and side cheeks joined to
        // the wall, rather than a disconnected strip of railing.
        box(x+0.70,y,z,1.48,width,0.22,wallColor)
        box(x+1.36,y+0.22,z,0.16,width,0.44,Map3DPalette.concrete)
        for dz in stride(from:z-width/2+0.22,through:z+width/2-0.22,by:Float(0.65)) {
            box(x+1.38,y+0.65,dz,0.08,0.07,0.39,Self.steel)
        }
        box(x+1.38,y+1.00,z,0.10,width,0.09,Self.steel)
        for dz: Float in [-width/2+0.09,width/2-0.09] {
            box(x+0.73,y+0.22,z+dz,1.38,0.18,0.67,Map3DPalette.concrete)
            box(x+0.73,y+1.00,z+dz,1.38,0.09,0.09,Self.steel)
            beam(Map3DPoint(x+0.03,y-0.34,z+dz),Map3DPoint(x+1.24,y+0.05,z+dz),0.11,wallColor)
        }
    }
    mutating func residentialBalconyDoor(_ x: Float,_ y: Float,_ z: Float) {
        // The glazing sits in a complete backed opening above the balcony.
        box(x-0.055,y,z,0.12,1.70,2.35,wallColor)
        box(x+0.02,y+0.06,z,0.04,1.56,2.20,trimColor)
        for side: Float in [-1,1] {
            box(x+0.052,y+0.17,z+side*0.39,0.025,0.68,1.96,Self.glass)
        }
        for dz: Float in [-0.83,0,0.83] { box(x+0.08,y+0.05,z+dz,0.08,0.075,2.24,Self.white) }
        box(x+0.08,y+2.25,z,0.08,1.74,0.08,Self.white)
        box(x+0.08,y+0.04,z,0.12,1.74,0.10,Map3DPalette.concrete)
    }
    mutating func residentialHome(_ part: Map3DResidentialKit.Part) {
        let cream=Self.white,stone=wallColor,tile=Map3DPalette.playerRoof,roof=Map3DPalette.roof,blue=Map3DPalette.canopy
        switch part {
        case .narrowTownhouse:
            box(0,0,0,7.4,5.8,0.18,stone);box(-0.4,0.18,0,5.5,5.3,8.9,cream)
            for floor in 0..<3 { for z: Float in [-1.4,1.4] { residentialWindow(2.39,0.95+Float(floor)*2.85,z,width:1.1) } }
            residentialDoor(2.43,0.18,0,width:1.25)
            for y: Float in [3.05,5.90] { box(2.49,y,0,0.20,5.45,0.12,tile) }
            box(-0.4,9.08,0,6.2,5.8,0.25,roof)
            for z: Float in [-2.4,2.4] { box(-0.4,9.33,z,6.2,0.18,0.8,stone) }
        case .arcadeTownhouse:
            box(0,0,0,9,8.0,0.18,stone)
            box(-2.0,0.18,0,2.8,7.5,3.05,cream) // recessed shopfront wall
            residentialDoor(-0.52,0.18,0)
            for z: Float in [-2.28,2.28] { residentialWindow(-0.50,0.85,z,width:1.55,height:1.72) }
            box(-0.54,2.68,0,0.14,6.9,0.34,tile) // blank shop fascia fixed to the recessed wall
            box(-0.7,3.23,0,7.5,7.5,5.8,cream)
            box(-0.7,3.07,0,7.5,7.5,0.16,stone) // continuous arcade soffit
            for z: Float in [-3.25,3.25] {
                box(2.72,0.18,z,0.44,0.46,2.94,stone)
                box(2.72,0.18,z,0.66,0.68,0.25,Map3DPalette.concrete)
                box(2.72,2.99,z,0.58,0.59,0.24,stone)
            }
            box(2.94,3.08,0,0.25,7.72,0.25,blue) // fascia touches the soffit
            for floor in 0..<2 {
                let y=4.02+Float(floor)*2.82
                for z: Float in [-2.4,0,2.4] { residentialWindow(3.08,y,z,width:1.22,height:1.48) }
            }
            box(3.10,6.05,0,0.14,7.50,0.14,Map3DPalette.concrete)
            for z: Float in [-3.47,3.47] { box(3.09,3.42,z,0.14,0.17,5.25,stone) }
            box(-0.7,9.03,0,8.2,8.1,0.25,roof)
            box(3.05,9.23,0,0.24,8.10,0.26,stone)
        case .duplexHouse:
            box(0,0,0,10.4,13.5,0.18,stone)
            for z: Float in [-3.3,3.3] {
                box(-0.5,0.18,z,7.2,6.2,6.0,z<0 ? cream : tile)
                residentialDoor(3.18,0.18,z-0.55,width:1.15)
                for floor in 0..<2 { residentialWindow(3.16,1.05+Float(floor)*3,z+1.2,width:1.2) }
                residentialBalcony(3.1,3.15,z-0.6,width:2.2)
            }
            box(0,6.18,0,9.2,13.0,0.24,roof)
            box(4.0,0.18,0,0.20,0.20,6.0,stone) // shared party-wall nose
        case .roofTerraceHouse:
            box(0,0,0,9.4,9.3,0.18,stone);box(-0.7,0.18,0,6.7,7.4,6.2,tile)
            for floor in 0..<2 { for z: Float in [-2.3,0,2.3] { residentialWindow(2.71,0.95+Float(floor)*3.05,z,width:0.95) } }
            residentialDoor(2.75,0.18,0);box(-0.7,6.38,0,7.4,8.2,0.18,roof)
            for z: Float in [-3.9,3.9] { box(-0.7,6.56,z,7.4,0.17,1.05,cream) }
            box(2.93,6.56,0,0.17,7.8,1.05,cream)
            box(-2.2,6.56,-1.8,2.2,2.6,2.2,stone);box(-2.2,8.76,-1.8,2.5,2.9,0.15,blue)
        case .cornerHouse:
            box(0,0,0,10,10,0.18,stone);box(-0.8,0.18,0,7.2,7.2,6.2,cream)
            box(2.3,0.18,2.6,2.9,2.7,3.05,tile) // angled massing at street corner
            residentialDoor(3.02,0.18,-1.65)
            for floor in 0..<2 { for z: Float in [-2.1,0.6,2.3] { residentialWindow(2.84,1.05+Float(floor)*3,z,width:1.05) } }
            for floor in 0..<2 { box(-0.5,1.1+Float(floor)*3,3.66,1.35,0.06,1.3,Self.glass) }
            box(-0.8,6.38,0,8.2,8.4,0.22,roof);box(3.3,3.23,2.7,1.8,3.0,0.18,blue)
            for z: Float in [1.6,3.7] { box(4.0,0.18,z,0.12,0.12,3.05,Self.steel) }
        case .walkupApartment:
            box(0,0,0,11,12,0.18,stone);box(-0.5,0.18,0,8.5,11.3,12,cream)
            residentialDoor(3.81,0.18,0,width:1.7)
            for floor in 0..<4 {
                let y=0.95+Float(floor)*3
                for z: Float in [-4.3,-2.9,2.9,4.3] { residentialWindow(3.80,y,z,width:0.88,height:1.40) }
                if floor>0 {
                    residentialBalcony(3.78,Float(floor)*3+0.12,0,width:3.8)
                    residentialBalconyDoor(3.80,Float(floor)*3+0.30,0)
                }
            }
            box(-0.5,12.18,0,9.2,12.0,0.22,roof)
            for z: Float in [-5.7,5.7] { box(-0.5,12.40,z,9.2,0.16,0.85,stone) }
        case .courtyardHouse:
            box(0,0,0,15,18,0.16,Map3DPalette.plaza)
            box(-3,0.16,0,5.7,14.5,3.1,cream)
            box(2.4,0.16,-6.0,5.5,2.5,3.1,cream);box(2.4,0.16,6.0,5.5,2.5,3.1,cream)
            residentialDoor(-0.07,0.16,0,width:1.8)
            for z: Float in [-5,-2.5,2.5,5] { residentialWindow(-0.07,1.1,z,width:1.1) }
            gable(-3,3.26,0,6.5,15,1.35,Map3DPalette.templeRoof)
            for z: Float in [-6,6] { gable(2.4,3.26,z,6.0,3.0,0.8,Map3DPalette.templeRoof) }
            box(4.7,0.16,0,0.12,9.2,0.95,stone)
        case .farmHouse:
            box(0,0,0,15,17,0.16,Map3DPalette.park)
            box(-1.3,0.16,0,8.6,10.2,3.1,cream)
            box(3.0,0.16,-3.2,3.5,3.4,2.6,stone)
            residentialDoor(3.06,0.16,0,width:1.55)
            for z: Float in [-3.4,3.4] { residentialWindow(3.05,1.1,z,width:1.3) }
            gable(-1.3,3.26,0,9.5,11.2,1.9,Map3DPalette.templeRoof)
            box(3.3,2.70,-3.2,4.0,3.8,0.18,Map3DPalette.roof)
            for z: Float in [-4.8,-1.6] { box(4.6,0.16,z,0.15,0.15,2.55,Self.steel) }
        default: break
        }
    }

    mutating func residential(_ part: Map3DResidentialKit.Part) {
        switch part.category {
        case .home: residentialHome(part)
        case .boundary: residentialBoundary(part)
        case .yard: residentialYard(part)
        }
    }
}
