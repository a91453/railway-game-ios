import Foundation

extension StationKitBuilder {
    mutating func parkSport(_ p: Map3DParkKit.Part) {
        let steel=Self.steel,blue=Self.parkBlue,wood=Self.parkWood,white=Self.white
        switch p {
        case .basketballHoop:
            box(-0.50,0,0,1.0,1.25,0.20,blue);parkPost(-0.65,0,3.25)
            beam(Map3DPoint(-0.65,2.8,0),Map3DPoint(0.35,3.25,0),0.09,steel)
            box(0.35,2.7,0,0.10,1.5,0.95,white)
            box(0.412,2.91,0,0.025,0.56,0.05,Self.parkRed)
            for z: Float in [-0.27,0.27] { box(0.412,2.91,z,0.025,0.035,0.38,Self.parkRed) }
            box(0.412,3.26,0,0.025,0.56,0.035,Self.parkRed)
            parkRail(Map3DPoint(0.4,2.95,0),Map3DPoint(0.52,2.95,0),0.025,steel)
            parkCircle(0.75,2.95,0,radius:0.23,color:Self.parkRed,segments:20)
            for i in 0..<10 { let a=Float(i)*Float.pi/5
                parkRail(Map3DPoint(0.75+cosf(a)*0.23,2.95,sinf(a)*0.23),Map3DPoint(0.75+cosf(a)*0.13,2.58,sinf(a)*0.13),0.009,white)
            }
        case .basketballCourt:
            parkRectCourt(length:24,width:13,color:Map3DPalette.park);parkCircle(0,0.09,0,radius:1.8,color:white)
            for s: Float in [-1,1] {
                box(s*9.5,0.08,0,5,4.8,0.005,Map3DPalette.roof)
                for z: Float in [-2.4,2.4] { parkLine(s*12,z,s*7,z) };parkLine(s*7,-2.4,s*7,2.4)
                parkCircle(s*7,0.095,0,radius:1.5,color:white)
            }
        case .tennisCourt:
            parkRectCourt(length:23.8,width:10.9,color:Self.parkGreen)
            for z: Float in [-4.1,4.1] { parkLine(-11.9,z,11.9,z) }
            for x: Float in [-6.4,6.4] { parkLine(x,-4.1,x,4.1) };parkLine(-6.4,0,6.4,0)
        case .tennisNet:
            for z: Float in [-5.9,5.9] { box(0,0,z,0.45,0.45,0.08,steel);parkPost(0,z,1.1) }
            parkNet(0,0.2,0,width:11.8,height:0.85);box(0,1.05,0,0.04,11.8,0.05,white)
        case .soccerGoal:
            for z: Float in [-1.5,1.5] {
                parkPost(0,z,2.0,white);beam(Map3DPoint(0,2,z),Map3DPoint(-1,0.04,z),0.06,white)
                box(-0.5,0,z,1.06,0.06,0.06,white)
            }
            box(0,1.95,0,0.11,3.1,0.10,white);parkNet(-1,0.03,0,width:3,height:0.65)
            for i in 0...12 { let z=Float(i)*0.25-1.5
                parkRail(Map3DPoint(0,1.95,z),Map3DPoint(-1,0.65,z),0.009,white)
            }
            for i in 1...4 { let t=Float(i)/4;box(-t,1.95-1.3*t,0,0.018,3,0.018,white) }
        case .miniSoccerPitch:
            parkRectCourt(length:24,width:16,color:Self.parkGreen);parkCircle(0,0.09,0,radius:2,color:white)
            for s: Float in [-1,1] { for z: Float in [-4,4] { parkLine(s*12,z,s*7,z) };parkLine(s*7,-4,s*7,4) }
        case .badmintonCourt:
            parkRectCourt(length:13.4,width:6.1,color:blue)
            for x: Float in [-5.9,-1.98,1.98,5.9] { parkLine(x,-3.05,x,3.05) }
            for z: Float in [-2.59,2.59] { parkLine(-6.7,z,6.7,z) };parkLine(-6.7,0,6.7,0)
        case .tableTennis:
            civicLegs(0,0,0,length:1.9,width:1.0,height:0.7,color:steel)
            box(0,0.70,0,2.74,1.52,0.06,blue)
            for z: Float in [-0.74,0.74] { parkLine(-1.35,z,1.35,z,0.77) }
            for x: Float in [-1.35,1.35] { parkLine(x,-0.74,x,0.74,0.77) };parkLine(-1.35,0,1.35,0,0.77)
            parkNet(0,0.76,0,width:1.65,height:0.15)
            for z: Float in [-0.825,0.825] { box(0,0.70,z,0.04,0.04,0.24,steel) }
        case .outdoorGymBars:
            for z: Float in [-1.3,0,1.3] { let h: Float=z==0 ? 2.3 : 1.7
                for x: Float in [-0.65,0.65] { parkPost(x,z,h,blue) }
                beam(Map3DPoint(-0.65,h,z),Map3DPoint(0.65,h,z),0.06,steel)
            }
        case .balanceBeam:
            for x: Float in [-1.3,0,1.3] { box(x,0,0,0.20,0.35,0.45,steel) }
            box(0,0.45,0,3.4,0.22,0.15,wood)
        case .skateQuarterPipe:
            let n=12,r: Float=1.8
            for i in 0..<n { let a=Float(i)*Float.pi/2/Float(n),b=Float(i+1)*Float.pi/2/Float(n)
                let x1 = -0.9+r*sinf(a),x2 = -0.9+r*sinf(b),y1=0.1+r*(1-cosf(a)),y2=0.1+r*(1-cosf(b))
                let shape=[Map3DPoint(x1,0,-1.4),Map3DPoint(x2,0,-1.4),Map3DPoint(x2,y2,-1.4),Map3DPoint(x1,y1,-1.4)]
                let back=shape.map { $0+Map3DPoint(0,0,2.8) },inside=Map3DPoint((x1+x2)/2,(y1+y2)/4,0)
                face(shape,inside:inside,color:wood);face(back,inside:inside,color:wood)
                for j in 0..<4 { let k=(j+1)%4;face([shape[j],shape[k],back[k],back[j]],inside:inside,color:Map3DPalette.concrete) }
            }
            box(1.25,0,0,0.7,2.8,1.9,wood)
            parkRail(Map3DPoint(0.9,1.93,-1.4),Map3DPoint(0.9,1.93,1.4),0.035,steel)
            for z: Float in [-1.3,1.3] { parkPost(1.5,z,2.6) }
            beam(Map3DPoint(1.5,2.6,-1.3),Map3DPoint(1.5,2.6,1.3),0.04,steel)
        case .bleachers:
            for i in 0..<4 { let x=Float(i)*0.6,y=Float(i)*0.36
                for z: Float in [-1.8,0,1.8] { box(x,0,z,0.10,0.10,y+0.40,steel) }
                box(x,y+0.4,0,0.42,4.2,0.06,wood)
                box(x-0.28,0,0,0.20,4.2,y+0.08,Map3DPalette.concrete)
            }
            for z: Float in [-2.05,2.05] { box(1.8,0,z,0.06,0.06,2.15,steel) }
            box(1.8,2.1,0,0.06,4.2,0.06,steel)
        default: break
        }
    }
}
