import Foundation

extension StationKitBuilder {
    mutating func parkPlayground(_ p: Map3DParkKit.Part) {
        let blue=Self.parkBlue,red=Self.parkRed,wood=Self.parkWood,steel=Self.steel
        switch p {
        case .slide: parkSlide(height:1.8,length:2.7,width:0.65)
        case .toddlerSlide: parkSlide(height:0.65,length:1.35,width:0.48)
        case .swingSet:
            for z: Float in [-1.9,1.9] { for x: Float in [-0.85,0.85] {
                beam(Map3DPoint(x,0.04,z),Map3DPoint(0,2.6,z),0.12,blue)
                box(x,0,z,0.26,0.26,0.08,Map3DPalette.concrete)
            } }
            beam(Map3DPoint(0,2.6,-2),Map3DPoint(0,2.6,2),0.14,red)
            for z: Float in [-0.85,0.85] {
                box(0,0.5,z,0.42,0.56,0.07,wood)
                for dz: Float in [-0.23,0.23] { parkRail(Map3DPoint(0,0.57,z+dz),Map3DPoint(0,2.6,z+dz),0.018,steel) }
            }
        case .seesaw:
            cylinder(0,0,0,radius:0.35,height:0.65,color:blue)
            beam(Map3DPoint(-1.6,0.3,0),Map3DPoint(1.6,0.9,0),0.16,wood)
            for s: Float in [-1,1] { let x=s*1.35,y: Float=s<0 ? 0.35 : 0.85
                box(x,y,0,0.38,0.48,0.08,red);box(x-s*0.23,y,0,0.04,0.04,0.28,steel)
                box(x-s*0.23,y+0.28,0,0.04,0.3,0.04,steel)
            }
        case .climbingFrame:
            for x: Float in [-1,1] { for z: Float in [-1,1] { parkPost(x,z,2.2,blue) } }
            for y: Float in [0.45,0.9,1.35,1.8,2.2] { for s: Float in [-1,1] {
                beam(Map3DPoint(-1,y,s),Map3DPoint(1,y,s),0.045,steel)
                beam(Map3DPoint(s,y,-1),Map3DPoint(s,y,1),0.045,steel)
            } }
            for z: Float in [-0.5,0,0.5] { beam(Map3DPoint(-1,2.2,z),Map3DPoint(1,2.2,z),0.045,red) }
        case .sandpit:
            box(0,0,0,3.4,3.4,0.12,Map3DPalette.playerRoof)
            for s: Float in [-1,1] { box(s*1.6,0,0,0.2,3.4,0.32,wood);box(0,0,s*1.6,3.4,0.2,0.32,wood) }
            for x: Float in [-1.4,1.4] { for z: Float in [-1.4,1.4] { box(x,0.32,z,0.6,0.6,0.06,red) } }
        case .roundabout:
            cylinder(0,0,0,radius:0.2,height:0.25,color:steel)
            cylinder(0,0.25,0,radius:1.05,height:0.12,color:blue,sides:24)
            for i in 0..<4 { let a=Float(i)*Float.pi/2,x=cosf(a)*0.72,z=sinf(a)*0.72
                cylinder(x,0.37,z,radius:0.035,height:0.65,color:steel)
                parkRail(Map3DPoint(x,1.02,z),Map3DPoint(0,1.02,0),0.035,red)
            }
        case .springRider:
            cylinder(0,0,0,radius:0.25,height:0.07,color:steel)
            // Explicit helix with connected top/bottom anchoring plates.
            for i in 0..<48 { let a=Float(i)*Float.pi/6,b=Float(i+1)*Float.pi/6
                parkRail(Map3DPoint(cosf(a)*0.12,0.10+Float(i)*0.006,sinf(a)*0.12),Map3DPoint(cosf(b)*0.12,0.10+Float(i+1)*0.006,sinf(b)*0.12),0.025,steel)
            }
            cylinder(0,0.07,0,radius:0.15,height:0.05,color:steel);cylinder(0,0.37,0,radius:0.15,height:0.05,color:steel)
            box(0,0.42,0,0.75,0.28,0.25,red);box(0,0.67,0,0.42,0.42,0.06,wood)
            box(0.28,0.65,0,0.22,0.26,0.32,red);box(0.39,0.82,0,0.25,0.26,0.15,red)
            box(0.15,0.82,0,0.04,0.55,0.04,steel)
            for z: Float in [-0.09,0.09] { box(0.29,0.97,z,0.07,0.055,0.13,red) }
            for z: Float in [-0.14,0.14] { box(0.36,0.89,z,0.035,0.025,0.035,Self.ink) }
            beam(Map3DPoint(-0.35,0.58,0),Map3DPoint(-0.58,0.72,0),0.055,red)

        case .playhouse:
            box(0,0,0,2.2,2.4,0.12,wood)
            box(-0.85,0.12,0,0.12,2.1,1.5,Map3DPalette.playerRoof)
            for z: Float in [-1,1] { box(0,0.12,z,1.8,0.12,0.7,blue);box(0,1.2,z,1.8,0.12,0.42,blue)
                for x: Float in [-0.8,0.8] { box(x,0.12,z,0.12,0.12,1.5,blue) }
            }
            for z: Float in [-0.85,0.85] { box(0.85,0.12,z,0.12,0.3,1.5,red) }
            gable(0,1.62,0,2,2.2,0.7,red)
        case .ropeBridge:
            for x: Float in [-1.8,1.8] { for z: Float in [-0.6,0.6] { parkPost(x,z,1.65,blue) } }
            func y(_ x: Float) -> Float { 0.4+0.16*x*x }
            for i in 0..<18 { let a=Float(i)*0.2-1.8,b=a+0.2
                beam(Map3DPoint(a,y(a),0),Map3DPoint(b,y(b),0),0.13,wood)
                box((a+b)/2,(y(a)+y(b))/2-0.06,0,0.17,1.1,0.12,wood)
                for z: Float in [-0.53,0.53] {
                    parkRail(Map3DPoint(a,y(a)+0.65,z),Map3DPoint(b,y(b)+0.65,z),0.023,steel)
                    parkRail(Map3DPoint(a,y(a),z),Map3DPoint(a,y(a)+0.65,z),0.015,steel)
                }
            }
            for x: Float in [-1.8,1.8] { box(x,0,0,0.38,1.1,y(x),wood) }
        case .steppingPods:
            for i in 0..<7 { let x=Float(i)*0.45-1.35,z: Float=i%2==0 ? -0.3 : 0.3
                cylinder(x,0,z,radius:0.22,height:0.2+Float(i%3)*0.1,color:i%2==0 ? blue : red)
            }
        case .musicChimes:
            for z: Float in [-1.05,1.05] { parkPost(0,z,1.7,blue) }
            box(0,1.65,0,0.10,2.2,0.10,wood)
            for i in 0..<7 { let z=Float(i)*0.27-0.81,h=0.55+Float(i)*0.10
                parkRail(Map3DPoint(0,1.50,z),Map3DPoint(0,1.65,z),0.018,steel)
                cylinder(0,1.50-h,z,radius:0.055,height:h,color:steel,sides:8)
            }
        default: break
        }
    }
}
