import Foundation

extension StationKitBuilder {
    mutating func parkGarden(_ p: Map3DParkKit.Part) {
        let wood=Self.parkWood,steel=Self.steel,green=Self.parkGreen,concrete=Map3DPalette.concrete
        switch p {
        case .gazebo:
            cylinder(0,0,0,radius:2.35,height:0.20,color:concrete,sides:8)
            cylinder(0,0.20,0,radius:2.2,height:0.10,color:wood,sides:8)
            let top=Map3DPoint(0,3.8,0),base=Map3DPoint(0,2.75,0)
            for i in 0..<8 { let a=Float(i)*Float.pi/4,b=Float(i+1)*Float.pi/4
                let u=Map3DPoint(cosf(a)*2.55,2.8,sinf(a)*2.55),v=Map3DPoint(cosf(b)*2.55,2.8,sinf(b)*2.55)
                face([top,u,v],inside:Map3DPoint(0,3,0),color:Self.parkBlue)
                face([base,v-Map3DPoint(0,0.1,0),u-Map3DPoint(0,0.1,0)],inside:Map3DPoint(0,3,0),color:Self.parkBlue)
                face([u,u-Map3DPoint(0,0.1,0),v-Map3DPoint(0,0.1,0),v],inside:Map3DPoint(0,3,0),color:Self.parkBlue)
                let x=cosf(a)*2,z=sinf(a)*2
                box(x,0.30,z,0.13,0.13,2.42,wood)
                beam(Map3DPoint(x,2.72,z),Map3DPoint(cosf(b)*2,2.72,sinf(b)*2),0.10,wood)
                if i>1 { beam(Map3DPoint(x,1.1,z),Map3DPoint(cosf(b)*2,1.1,sinf(b)*2),0.08,wood) }
            }
        case .pergola:
            for x: Float in [-1.4,1.4] { for z: Float in [-2,2] { box(x,0,z,0.16,0.16,2.5,wood) } }
            for x: Float in [-1.4,1.4] { box(x,2.5,0,0.16,4.6,0.20,wood) }
            for z in stride(from:Float(-2.2),through:2.2,by:0.44) { box(0,2.70,z,3.4,0.12,0.15,wood) }
            for x: Float in [-1.4,1.4] { for z: Float in [-2,2] { beam(Map3DPoint(x,2,z),Map3DPoint(x*0.6,2.5,z),0.09,wood) } }
        case .archedFootbridge:
            func y(_ x: Float) -> Float { 0.12+0.75*(1-(x/2.5)*(x/2.5)) }
            for i in 0..<20 { let a=Float(i)*0.25-2.5,b=a+0.25
                let p=[Map3DPoint(a,y(a),-0.7),Map3DPoint(b,y(b),-0.7),Map3DPoint(b,y(b),0.7),Map3DPoint(a,y(a),0.7)]
                let q=p.map { $0-Map3DPoint(0,0.12,0) },inside=Map3DPoint((a+b)/2,(y(a)+y(b))/2-0.06,0)
                face(p,inside:inside,color:wood);face(q,inside:inside,color:wood)
                for j in 0..<4 { let k=(j+1)%4;face([p[j],p[k],q[k],q[j]],inside:inside,color:wood) }
                for z: Float in [-0.65,0.65] { for h: Float in [0.35,0.85] { beam(Map3DPoint(a,y(a)+h,z),Map3DPoint(b,y(b)+h,z),0.06,Self.parkRed) } }
            }
            for x: Float in [-2.5,-1.25,0,1.25,2.5] { for z: Float in [-0.65,0.65] { box(x,y(x)-0.04,z,0.08,0.08,0.97,Self.parkRed) } }
            // End abutments only; the centre is an open span over water.
            for x: Float in [-2.35,2.35] { box(x,0,0,0.30,1.5,0.25,concrete) }
        case .parkGate:
            for z: Float in [-2,2] { box(0,0,z,0.5,0.5,0.25,concrete);box(0,0.25,z,0.20,0.20,2.6,wood) }
            box(0,2.65,0,0.30,4.7,0.30,wood)
            box(0.16,2.70,0,0.03,2.2,0.18,Self.parkGreen)
        case .drinkingFountain:
            cylinder(0,0,0,radius:0.45,height:0.08,color:concrete,sides:12)
            cylinder(0,0.08,0,radius:0.17,height:0.83,color:concrete,sides:12)
            cylinder(0,0.91,0,radius:0.28,height:0.08,color:steel,sides:16)
            cylinder(0,0.99,0,radius:0.21,height:0.015,color:Self.ink,sides:16)
            for z: Float in [-0.25,0.25] { box(0,0.99,z,0.4,0.06,0.055,steel) }
            box(-0.17,0.99,0,0.07,0.45,0.08,steel)
            parkRail(Map3DPoint(-0.17,1.07,0),Map3DPoint(0,1.10,0),0.018,steel)
        case .steppedFountain:
            cylinder(0,0,0,radius:1.6,height:0.18,color:concrete,sides:24)
            cylinder(0,0.18,0,radius:1.40,height:0.04,color:Map3DPalette.water,sides:24)
            cylinder(0,0.22,0,radius:0.25,height:1.5,color:concrete)
            for level in 0..<2 { let y: Float=level==0 ? 0.8 : 1.6,r: Float=level==0 ? 0.85 : 0.5
                cylinder(0,y,0,radius:r,height:0.10,color:concrete,sides:20)
                cylinder(0,y+0.10,0,radius:r-0.08,height:0.015,color:Map3DPalette.water,sides:20)
                for i in 0..<8 { let a=Float(i)*Float.pi/4
                    cylinder(cosf(a)*(r-0.10),level==0 ? 0.22 : 0.9,sinf(a)*(r-0.10),radius:0.012,height:level==0 ? 0.6 : 0.72,color:Map3DPalette.water,sides:6)
                }
            }
        case .pondEdge:
            box(0,0,0,6,4,0.15,concrete);box(0,0.15,0,5.55,3.55,0.03,Map3DPalette.water)
            for z: Float in [-1.9,1.9] { box(0,0.15,z,6,0.2,0.18,concrete) }
            for x: Float in [-2.9,2.9] { box(x,0.15,0,0.2,3.8,0.18,concrete) }
            for x: Float in [-1.4,0.2,1.4] { cylinder(x,0.18,0.7,radius:0.18,height:0.015,color:green,sides:8) }
        case .raisedFlowerBed:
            box(0,0,0,2.5,1.2,0.50,wood);box(0,0.50,0,2.3,1,0.025,Map3DPalette.trunk)
            for i in -3...3 { for z: Float in [-0.28,0.28] { let x=Float(i)*0.30
                cylinder(x,0.525,z,radius:0.018,height:0.18,color:green,sides:6)
                cylinder(x,0.69,z,radius:0.12,height:0.08,color:i%2==0 ? Self.parkRed : Map3DPalette.playerRoof,sides:6)
            } }
        case .compostBin:
            box(0,0,0,1.15,1.15,0.12,wood)
            for i in 0..<6 { let y=0.12+Float(i)*0.14
                for z: Float in [-0.53,0.53] { box(0,y,z,1.15,0.08,0.10,wood) }
                for x: Float in [-0.53,0.53] { box(x,y,0,0.08,1.15,0.10,wood) }
            }
            for x: Float in [-0.48,0.48] { for z: Float in [-0.48,0.48] { box(x,0,z,0.08,0.08,1,steel) } }
            box(0,0.12,0,0.9,0.9,0.6,Map3DPalette.trunk)
        case .toolShed:
            box(0,0,0,2.4,2.8,0.12,concrete);box(0,0.12,0,2.1,2.5,2.1,green)
            gable(0,2.22,0,2.2,2.6,0.7,Self.parkBlue)
            box(1.06,0.12,0,0.03,1.0,1.8,wood);box(1.09,0.96,-0.35,0.035,0.05,0.12,steel)
            box(0,0.8,1.26,0.85,0.06,0.80,Self.white);box(0,0.88,1.296,0.70,0.025,0.65,Self.glass)
        case .boardwalkCorner:
            for x: Float in [-1.6,0,1.6] { for z: Float in [-0.5,0.5] { box(x,0,z,0.12,0.12,0.45,steel) } }
            for i in -8...8 { box(Float(i)*0.2,0.45,0,0.18,1.3,0.08,wood) }
            for z in stride(from:Float(0.8),through:3.2,by:0.2) { box(1.1,0.45,z,1.3,0.18,0.08,wood) }
            for z: Float in [1.6,3.1] { for x: Float in [0.6,1.6] { box(x,0,z,0.12,0.12,0.45,steel) } }
            for z: Float in [-0.6,3.2] { box(1.7,0,z,0.08,0.08,1.3,wood) }
            box(1.7,1.25,1.3,0.08,3.9,0.08,wood)
        case .trellis:
            for z: Float in [-1.2,1.2] { box(0,0,z,0.12,0.12,2.2,wood) }
            for i in 0..<6 { box(0,0.25+Float(i)*0.35,0,0.06,2.4,0.055,wood) }
            for i in -3...3 { box(0,0.25,Float(i)*0.35,0.06,0.045,1.8,wood) }
            for z: Float in [-0.75,0,0.75] { box(0,0,z,0.45,0.55,0.28,concrete)
                cylinder(0.06,0.28,z,radius:0.012,height:1.7,color:Map3DPalette.trunk,sides:6)
                for i in 0..<4 { let y=0.28+Float(i)*0.42;box(0.06,y,z,0.08,0.20,0.35,green) }
            }
        default: break
        }
    }
}
