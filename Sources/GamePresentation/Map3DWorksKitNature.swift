import Foundation

extension StationKitBuilder {
    mutating func worksNature(_ part: Map3DWorksKit.Part) {
        let green=Self.worksGreen,wood=Self.worksWood
        switch part {
        case .bambooClump:
            for i in 0..<7 {
                let angle=Float(i)*2.4,r: Float=i==0 ? 0 : 0.6,h: Float=3.5+Float(i%3)*0.65
                let p=Map3DPoint(cosf(angle)*r,0,sinf(angle)*r),tip=p+Map3DPoint(cosf(angle)*0.25,h,sinf(angle)*0.25)
                worksTube(p,tip,0.055,green,sides:8)
                for j in 1..<8 { let q=p+(tip-p)*(Float(j)/8);worksTube(q-Map3DPoint(0,0.015,0),q+Map3DPoint(0,0.015,0),0.065,Map3DPalette.embankment,sides:8) }
                for j in 0..<3 {
                    let q=p+(tip-p)*(0.56+Float(j)*0.16),v=Map3DPoint(cosf(angle+Float(j)),0.15,sinf(angle+Float(j)))*0.8
                    beam(q,q+v,0.022,wood)
                    for k in 1...4 { let t=Float(k)/4,a=q+v*t
                        worksLeaf(a,a+Map3DPoint(0.25,0.18,0.25),width:0.07)
                        worksLeaf(a,a+Map3DPoint(-0.25,0.12,-0.25),width:0.07)
                    }
                }
            }
        case .fernPatch:
            cylinder(0,0,0,radius:0.12,height:0.12,color:wood,sides:7)
            for i in 0..<7 {
                let a=Float(i)*2*Float.pi/7,d=Map3DPoint(cosf(a),0,sinf(a)),start=Map3DPoint(0,0.08,0),tip=d*0.8+Map3DPoint(0,0.40,0)
                beam(start,tip,0.018,green)
                for j in 1...6 {
                    let t=Float(j)/7,p=start+(tip-start)*t,w=(1-t)*0.25,side=Map3DPoint(-d.z,0,d.x)
                    for sign: Float in [-1,1] { worksLeaf(p,p+side*(sign*w)+d*0.15+Map3DPoint(0,0.06,0),width:0.045) }
                }
            }
        case .reedPatch:
            for i in 0..<13 {
                let a=Float(i)*2.4,r=Float(i%4)*0.13,p=Map3DPoint(cosf(a)*r,0,sinf(a)*r),h=0.8+Float(i%5)*0.13
                worksTube(p,p+Map3DPoint(0,h,0),0.012,green,sides:6)
                worksTube(p+Map3DPoint(0,h,0),p+Map3DPoint(0,h+0.23,0),0.035,wood,sides:7)
                for sign: Float in [-1,1] { worksLeaf(p+Map3DPoint(0,h*0.3,0),p+Map3DPoint(sign*0.35,h*0.85,sign*0.15),width:0.055) }
            }
        case .riverRocks:
            for (x,z,r) in [(Float(-0.6),Float(-0.3),Float(0.55)),(0.5,0.1,0.70),(0.1,-0.6,0.3),(-0.3,0.55,0.35)] {
                worksBlob(Map3DPoint(x,r*0.45,z),Map3DPoint(r,r*0.45,r*0.7),Map3DPalette.concreteWalls[Int(r*10)%3],sides:7,rings:4)
            }
        case .treeStump:
            cylinder(0,0,0,radius:0.34,height:0.52,color:wood,sides:9)
            cylinder(0,0.52,0,radius:0.30,height:0.015,color:Map3DPalette.playerRoof,sides:9)
            for i in 0..<5 { let a=Float(i)*2*Float.pi/5
                let end=Map3DPoint(cosf(a)*0.6,0.04,sinf(a)*0.6)
                beam(Map3DPoint(cosf(a)*0.25,0.14,sinf(a)*0.25),end,0.08,wood)
            }
            worksTube(Map3DPoint(0,0.535,0),Map3DPoint(0,0.545,0),0.14,wood,sides:9)
        case .leafyTree:
            cylinder(0,0,0,radius:0.14,height:2.7,color:wood,sides:8)
            for (x,y,z,r) in [(Float(-0.6),Float(2.9),Float(0.2),Float(0.95)),(0.6,3.2,0.1,1.05),(0,3.0,-0.6,0.8),(0,3.8,0,0.85)] {
                beam(Map3DPoint(0,1.8,0),Map3DPoint(x,y,z),0.10,wood)
                worksBlob(Map3DPoint(x,y,z),Map3DPoint(r,r*0.8,r),Map3DProp.greens[Int(y*10)%5],sides:9,rings:6)
            }
        case .palmTree:
            let top=Map3DPoint(0.3,4,0)
            worksTube(Map3DPoint.zero,top,0.14,wood,sides:9)
            for j in 0..<12 { let p=top*(Float(j)/12);worksTube(p,p+Map3DPoint(0,0.025,0),0.15,Map3DPalette.arcade,sides:9) }
            for i in 0..<9 { let a=Float(i)*2*Float.pi/9,d=Map3DPoint(cosf(a),0,sinf(a)),mid=top+d*0.75+Map3DPoint(0,0.35,0),tip=top+d*1.8-Map3DPoint(0,0.4,0)
                worksLeaf(top,tip,width:0.20,color:green)
                beam(top,mid,0.035,green);beam(mid,tip,0.03,green)
                for j in 1...7 { let t=Float(j)/8,p=mid+(tip-mid)*t,side=Map3DPoint(-d.z,0,d.x)
                    for sign: Float in [-1,1] { worksLeaf(p,p+side*(sign*0.25*(1-t))+d*0.18-Map3DPoint(0,0.12,0),width:0.06) }
                }
            }
        case .vegetableRows:
            box(0,0,0,3.4,3.2,0.05,Map3DPalette.farm)
            for z: Float in [-1,0,1] {
                box(0,0.05,z,3.2,0.65,0.12,wood)
                for i in 0..<5 { let x=Float(i)*0.6-1.2
                    worksBlob(Map3DPoint(x,0.29,z),Map3DPoint(0.23,0.14,0.23),green,sides:8,rings:4)
                    for sign: Float in [-1,1] { worksLeaf(Map3DPoint(x,0.20,z),Map3DPoint(x+sign*0.33,0.32,z+0.05),width:0.16) }
                }
            }
        case .ricePaddy:
            box(0,0,0,4,4,0.06,wood);box(0,0.06,0,3.7,3.7,0.025,Map3DPalette.water)
            for i in 0..<6 { for j in 0..<6 { let x=Float(i)*0.55-1.4,z=Float(j)*0.55-1.4
                for sign: Float in [-1,1] { beam(Map3DPoint(x,0.08,z),Map3DPoint(x+sign*0.12,0.53,z+sign*0.07),0.018,green) }
            } }
            for z: Float in [-1.9,1.9] { box(0,0.06,z,4,0.20,0.11,Map3DPalette.embankment) }
        case .grainSilo:
            cylinder(0,0,0,radius:1.7,height:0.18,color:Map3DPalette.concrete,sides:16)
            cylinder(0,0.18,0,radius:1.40,height:4.0,color:Map3DPalette.tankSteel,sides:20)
            for i in 0..<10 { cylinder(0,0.3+Float(i)*0.38,0,radius:1.43,height:0.035,color:Self.steel,sides:20) }
            worksCone(Map3DPoint(0,4.18,0),radius:1.5,height:0.82,color:Map3DPalette.canopy)
            for y: Float in [0.7,2.2,3.7] { for z: Float in [-0.25,0.25] { beam(Map3DPoint(1.35,y,z),Map3DPoint(1.48,y,z),0.04,Self.steel) } }
            for z: Float in [-0.25,0.25] { beam(Map3DPoint(1.48,0.18,z),Map3DPoint(1.48,4.2,z),0.045,Self.steel) }
            for y in stride(from:Float(0.3),through:4.2,by:0.3) { beam(Map3DPoint(1.48,y,-0.25),Map3DPoint(1.48,y,0.25),0.035,Self.steel) }
        case .barn:
            box(0,0,0,6,5,0.15,Map3DPalette.concrete);box(0,0.15,0,5.6,4.6,2.7,wood)
            gable(0,2.85,0,5.6,4.6,1.15,Map3DPalette.canopy)
            box(2.83,0.15,0,0.06,2.2,2.4,Map3DPalette.counters[1])
            for z: Float in [-1,1] { box(2.87,0.15,z,0.04,0.06,2.4,Self.white) }
            for sign: Float in [-1,1] { beam(Map3DPoint(2.90,0.2,sign),Map3DPoint(2.90,2.5,-sign),0.055,Self.white) }
            for x: Float in [-2,-1,0,1,2] { for z: Float in [-2.32,2.32] { box(x,0.2,z,0.05,0.04,2.5,Self.white) } }
        case .woodenJetty:
            for x: Float in [-2,0,2] { for z: Float in [-0.8,0.8] { cylinder(x,0,z,radius:0.08,height:0.85,color:wood,sides:8) } }
            for z: Float in [-0.8,0.8] { box(0,0.60,z,4.6,0.14,0.16,wood) }
            for i in 0..<18 { box(-2.15+Float(i)*0.25,0.76,0,0.23,1.9,0.07,Map3DPalette.counters[1]) }
            for x: Float in [-2,0,2] { box(x,0.83,-0.87,0.08,0.08,0.85,wood) }
            beam(Map3DPoint(-2.2,1.65,-0.87),Map3DPoint(2.2,1.65,-0.87),0.065,wood)
        default: break
        }
    }
}
