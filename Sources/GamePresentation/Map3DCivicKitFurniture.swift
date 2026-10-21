import Foundation

extension StationKitBuilder {
    mutating func civicFurniture(_ p: Map3DCivicKit.Part) {
        let wood=Self.civicWood,white=Self.white,steel=Self.steel,blue=Map3DPalette.canopy,red=Self.civicRed
        switch p {
        case .singleBed,.doubleBed:
            let w: Float=p == .singleBed ? 1.05 : 1.65
            civicLegs(0,0,0,length:1.8,width:w-0.2,height:0.32)
            box(0,0.25,0,2.05,w,0.16,wood);civicCushion(0,0.41,0,1.98,w-0.06,0.24,white)
            box(-0.99,0.15,0,0.10,w+0.1,0.9,wood)
            civicCushion(-0.68,0.65,0,0.45,w-0.16,0.12,Map3DPalette.playerRoof)
            box(0.30,0.65,0,1.15,w-0.04,0.035,blue)
        case .wardrobe,.storageCabinet:
            let metal=p == .storageCabinet,h: Float=metal ? 1.85 : 2.05,w: Float=metal ? 0.85 : 1.25
            box(0,0,0,0.6,w,h,metal ? steel : wood)
            for side: Float in [-1,1] {
                box(0.312,0.10,side*w/4,0.025,w/2-0.04,h-0.18,metal ? Map3DPalette.canopy : Map3DPalette.playerRoof)
                box(0.35,0.85,side*0.055,0.045,0.025,0.18,steel)
                if metal { for i in 0..<3 { box(0.33,1.5+Float(i)*0.06,side*w/4,0.012,w*0.32,0.018,Self.ink) } }
            }
        case .bedsideTable:
            civicLegs(0,0,0,length:0.40,width:0.42,height:0.15)
            box(0,0.12,0,0.52,0.54,0.45,wood)
            for y: Float in [0.17,0.36] { box(0.27,y,0,0.025,0.46,0.17,Map3DPalette.playerRoof);box(0.295,y+0.07,0,0.03,0.16,0.025,steel) }
        case .writingDesk,.workbench:
            let repair=p == .workbench,w: Float=repair ? 1.9 : 1.3,h: Float=repair ? 0.9 : 0.8
            civicLegs(0,0,0,length:0.52,width:w-0.15,height:h-0.07,color:repair ? steel : wood)
            box(0,h-0.07,0,0.72,w,0.07,wood)
            if repair {
                box(-0.34,h,0,0.07,w,0.65,steel)
                for i in -3...3 { box(-0.285,h+0.17,Float(i)*0.2,0.025,0.04,0.27,Self.white) }
                box(0,0.15,0,0.55,w-0.16,0.05,steel)
            }
        case .officeChair:
            cylinder(0,0.04,0,0.06,0.40,steel)
            for i in 0..<5 { let a=Float(i)*2*Float.pi/5,x=cosf(a)*0.27,z=sinf(a)*0.27
                beam(Map3DPoint(0,0.12,0),Map3DPoint(x,0.06,z),0.04,steel);cylinder(x,0,z,0.045,0.07,Self.ink)
            }
            civicCushion(0,0.44,0,0.5,0.52,0.10,blue);box(-0.21,0.5,0,0.07,0.44,0.5,blue)
            for s: Float in [-1,1] { box(0,0.5,s*0.29,0.04,0.04,0.18,steel);box(0.02,0.68,s*0.29,0.32,0.07,0.04,Self.ink) }
        case .loungeChair,.twoSeatSofa:
            let w: Float=p == .twoSeatSofa ? 1.6 : 0.75
            civicLegs(0,0,0,length:0.58,width:w-0.12,height:0.18)
            civicCushion(0,0.15,0,0.86,w,0.22,Map3DPalette.canopy)
            civicCushion(0.1,0.37,0,0.65,w-0.16,0.16,Map3DPalette.playerRoof)
            civicCushion(-0.33,0.32,0,0.18,w,0.6,Map3DPalette.canopy)
            for s: Float in [-1,1] { civicCushion(0.03,0.37,s*w/2,0.76,0.15,0.28,blue) }
        case .coffeeTable:
            civicLegs(0,0,0,length:0.50,width:0.85,height:0.38);box(0,0.38,0,0.65,1.0,0.06,wood)
        case .bookcase:
            for z: Float in [-0.55,0.55] { box(0,0,z,0.38,0.055,1.65,wood) }
            box(-0.17,0,0,0.04,1.15,1.65,wood)
            for row in 0..<5 { let y=Float(row)*0.4;box(0,y,0,0.38,1.15,0.05,wood)
                if row<4 { for i in 0..<7 { box(0,y+0.05,Float(i)*0.14-0.42,0.28,0.09,0.22+Float(i%3)*0.025,i%2==0 ? blue : Map3DPalette.playerRoof) } }
            }
        case .utilitySink:
            civicLegs(0,0,0,length:0.48,width:0.65,height:0.8,color:steel)
            box(0,0.74,0,0.64,0.8,0.08,steel);box(0,0.82,0,0.48,0.59,0.025,Self.ink)
            for x: Float in [-0.28,0.28] { box(x,0.82,0,0.07,0.8,0.10,white) }
            for z: Float in [-0.36,0.36] { box(0,0.82,z,0.5,0.08,0.10,white) }
            civicTube(Map3DPoint(-0.24,0.9,0),Map3DPoint(-0.24,1.15,0),radius:0.025,color:steel)
            civicTube(Map3DPoint(-0.24,1.15,0),Map3DPoint(0,1.15,0),radius:0.025,color:steel)
        case .wallClock:
            civicTube(Map3DPoint(0,0,0),Map3DPoint(0.08,0,0),radius:0.25,color:wood,sides:24)
            civicTube(Map3DPoint(0.08,0,0),Map3DPoint(0.09,0,0),radius:0.22,color:white,sides:24)
            beam(Map3DPoint(0.10,0,0),Map3DPoint(0.10,0.16,0),0.018,Self.ink)
            beam(Map3DPoint(0.10,0,0),Map3DPoint(0.10,-0.06,0.11),0.022,Self.ink)
        case .deskLamp:
            cylinder(0,0,0,0.15,0.04,steel)
            beam(Map3DPoint(0,0.04,0),Map3DPoint(-0.16,0.37,0),0.035,steel)
            beam(Map3DPoint(-0.16,0.37,0),Map3DPoint(0.14,0.52,0),0.035,steel)
            civicTube(Map3DPoint(0.14,0.52,0),Map3DPoint(0.22,0.42,0),radius:0.10,color:blue)
        case .ceilingProjector:
            box(0,-0.04,0,0.22,0.22,0.04,steel);box(0,-0.3,0,0.05,0.05,0.26,steel)
            box(0,-0.5,0,0.36,0.46,0.2,white)
            civicTube(Map3DPoint(0.18,-0.4,-0.1),Map3DPoint(0.23,-0.4,-0.1),radius:0.065,color:Self.ink)
        case .projectionScreen:
            box(0.025,-0.68,0,0.05,1.9,1.36,steel);box(0.06,-0.61,0,0.025,1.76,1.22,white)
            box(0.06,0.66,0,0.12,2.0,0.10,Self.ink)
        case .poolTable:
            civicLegs(0,0,0,length:1.65,width:0.8,height:0.70);box(0,0.62,0,2.15,1.2,0.17,wood)
            box(0,0.79,0,1.95,1.0,0.025,Self.civicGreen)
            for z: Float in [-0.56,0.56] { box(0,0.79,z,2.15,0.1,0.07,wood) }
            for x: Float in [-1.025,1.025] { box(x,0.79,0,0.1,1.05,0.07,wood) }
            for x: Float in [-0.92,0,0.92] { for z: Float in [-0.46,0.46] { cylinder(x,0.816,z,0.055,0.012,Self.ink) } }
        case .cafeTable:
            cylinder(0,0,0,0.28,0.05,steel);cylinder(0,0.05,0,0.045,0.70,steel);cylinder(0,0.75,0,0.47,0.06,wood,sides:24)
        case .barCounter:
            box(0,0,0,0.65,1.9,1.02,wood);box(0,1.02,0,0.82,2.0,0.07,Map3DPalette.playerRoof)
            for z: Float in [-0.62,0,0.62] { box(0.335,0.12,z,0.025,0.52,0.76,Map3DPalette.playerRoof) }
        case .barStool:
            civicLegs(0,0,0,length:0.32,width:0.32,height:0.70,color:steel)
            for z: Float in [-0.16,0.16] { box(0,0.25,z,0.36,0.035,0.035,steel) }
            cylinder(0,0.7,0,0.26,0.08,red)
        case .curtains:
            box(0.025,0,0,0.05,1.8,1.6,white);box(0.06,0.08,0,0.025,1.60,1.43,Self.glass)
            for z: Float in [-0.84,0.84] { for i in 0..<4 { box(0.11+Float(i%2)*0.03,-0.02,z+Float(i)*0.08*(z>0 ? -1 : 1),0.07,0.09,1.7,red) } }
            civicTube(Map3DPoint(0.1,1.72,-1.0),Map3DPoint(0.1,1.72,1.0),radius:0.03,color:steel)
            for z: Float in [-0.9,0.9] { box(0.07,1.68,z,0.14,0.06,0.08,steel) }
        case .acousticPanel:
            box(0.025,0,0,0.05,0.65,1.15,steel)
            for i in 0..<9 { box(0.075,0.04,Float(i)*0.068-0.272,0.075,0.04,1.07,Self.ink) }
        case .studioCamera:
            for i in 0..<3 { let a=Float(i)*2*Float.pi/3
                beam(Map3DPoint(cosf(a)*0.36,0.02,sinf(a)*0.36),Map3DPoint(0,1.04,0),0.04,steel)
                cylinder(cosf(a)*0.36,0,sinf(a)*0.36,0.045,0.05,Self.ink)
            }
            box(0,1.04,0,0.4,0.30,0.28,Self.ink)
            civicTube(Map3DPoint(0.2,1.18,0),Map3DPoint(0.35,1.18,0),radius:0.09,color:steel)
            box(-0.04,1.32,0,0.28,0.04,0.08,steel)
        default: break
        }
    }
}
