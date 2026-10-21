import Foundation

extension StationKitBuilder {
    mutating func worksVehicle(_ part: Map3DWorksKit.Part) {
        let yellow=Self.worksYellow,steel=Self.steel,ink=Self.ink
        switch part {
        case .excavator,.miniExcavator:
            let small=part == .miniExcavator
            // A compact offset cab, exposed ring and folded two-piece boom.
            worksTracks(length:small ? 2.6 : 3.8,width:small ? 1.7 : 2.5)
            cylinder(0,0.54,0,radius:small ? 0.55 : 0.85,height:0.24,color:steel,sides:16)
            box(-0.40,0.76,0,small ? 1.7 : 2.5,small ? 1.5 : 2.2,0.45,yellow)
            worksCab(-0.2,1.15,small ? -0.35 : -0.6,length:small ? 1.0 : 1.5,width:small ? 0.75 : 0.95,height:small ? 1.05 : 1.5)
            box(-1.0,1.21,small ? 0.25 : 0.50,small ? 0.8 : 1.15,small ? 0.70 : 1.1,0.35,yellow)
            let a=Map3DPoint(0.25,1.16,0.32),b=Map3DPoint(small ? 1.6 : 2.0,small ? 2.6 : 3.6,0.32),c=Map3DPoint(small ? 2.25 : 3.1,0.70,0.32)
            beam(a,b,small ? 0.20 : 0.30,yellow);beam(b,c,small ? 0.17 : 0.24,yellow)
            worksHydraulic(a+Map3DPoint(-0.15,0.05,0.13),b+Map3DPoint(-0.20,-0.1,0.13))
            worksHydraulic(b+Map3DPoint(0.15,0,0.14),c+Map3DPoint(0.1,0.2,0.14))
            worksBucket(c,width:small ? 0.60 : 1.0)
        case .forklift,.telehandler:
            let reach=part == .telehandler
            for x: Float in [-0.85,0.85] { for z: Float in [-0.68,0.68] { worksWheel(x,0.38,z,radius:0.38,width:0.28) } }
            box(0,0.38,0,2.4,1.35,0.45,yellow)
            box(-0.8,0.83,0,0.65,1.35,0.42,yellow)
            for z: Float in [-0.58,0.58] { for x: Float in [-0.55,0.45] { box(x,0.83,z,0.06,0.06,1.55,steel) } }
            box(-0.05,2.38,0,1.4,1.45,0.09,yellow)
            box(-0.30,0.95,0,0.48,0.50,0.12,ink);box(-0.5,1.07,0,0.12,0.50,0.50,ink)
            worksTube(Map3DPoint(0.25,0.83,0),Map3DPoint(0.25,1.5,0),0.035,steel)
            if reach {
                beam(Map3DPoint(-0.65,1.0,0.3),Map3DPoint(2.0,2.0,0.3),0.23,yellow)
                worksHydraulic(Map3DPoint(-0.5,0.8,0.4),Map3DPoint(1.7,1.7,0.4))
                box(2.0,1.25,0.3,0.14,0.9,0.8,steel)
                for z: Float in [-0.05,0.65] { box(2.45,1.25,z,1.0,0.10,0.07,steel) }
            } else {
                for z: Float in [-0.42,0.42] { box(1.17,0.55,z,0.12,0.12,2.05,steel) }
                box(1.22,0.73,0,0.17,1.0,0.60,steel)
                for z: Float in [-0.35,0.35] { box(1.80,0.73,z,1.20,0.12,0.07,steel) }
                for z: Float in [-0.35,0.35] { worksTube(Map3DPoint(1.18,0.9,z),Map3DPoint(1.18,2.4,z),0.025,ink) }
            }
        case .crawlerCrane,.railCrane:
            let rail=part == .railCrane
            if rail {
                box(0,0.55,0,6.4,2.4,0.35,steel)
                for x: Float in [-2.4,-1.6,1.6,2.4] { for z: Float in [-0.5335,0.5335] { worksWheel(x,0.34,z,radius:0.315,width:0.14,rail:true) } }
                for x: Float in [-2.7,2.7] { box(x,0.9,0,0.14,3.8,0.12,yellow);for z: Float in [-1.8,1.8] { box(x,0,z,0.35,0.35,1.0,steel) } }
            } else { worksTracks(length:4.4,width:2.8) }
            cylinder(0,rail ? 0.9 : 0.6,0,radius:0.8,height:0.25,color:steel)
            box(-0.45,1.0,0,2.1,2.3,0.60,yellow)
            worksCab(0,1.4,-0.65,length:1.4,width:0.9,height:1.25)
            let a=Map3DPoint(0.3,1.35,0.25),b=Map3DPoint(rail ? 4.5 : 3.8,rail ? 6.5 : 7.5,0.25),d=b-a
            for z: Float in [-0.18,0.68] { beam(a+Map3DPoint(0,0,z-0.25),b+Map3DPoint(0,0,z-0.25),0.09,yellow) }
            for i in 0..<8 {
                let p=a+d*(Float(i)/8),q=a+d*(Float(i+1)/8)
                beam(p+Map3DPoint(0,0,-0.43),q+Map3DPoint(0,0,0.43),0.045,steel)
                beam(p+Map3DPoint(0,0,0.43),q+Map3DPoint(0,0,-0.43),0.045,steel)
            }
            worksTube(Map3DPoint(-0.8,1.6,0.25),b,0.018,ink,sides:6)
            worksTube(b,b-Map3DPoint(0,2,0),0.02,ink,sides:6)
            worksHook(b-Map3DPoint(0,2.0,0))
            if !rail { box(-1.4,1.0,0,0.8,2.3,0.8,steel) }
        case .roadRoller:
            worksTube(Map3DPoint(1.0,0.62,-1.05),Map3DPoint(1.0,0.62,1.05),0.62,steel,sides:20)
            for z: Float in [-0.85,0.85] { worksWheel(-1.0,0.58,z,radius:0.58,width:0.45) }
            box(-0.6,0.58,0,2.3,1.7,0.65,yellow)
            for z: Float in [-1.05,1.05] { beam(Map3DPoint(0,0.9,z),Map3DPoint(1.1,0.62,z),0.16,yellow) }
            worksCab(-0.6,1.23,0,length:1.45,width:1.45,height:1.45)
        case .mixerTruck,.dumpTruck,.serviceTruck,.flatbedTruck,.tankerTruck:
            worksTruckBase(part)
        default: break
        }
    }
    mutating func worksTruckBase(_ part: Map3DWorksKit.Part) {
        let yellow=Self.worksYellow,steel=Self.steel
        let length: Float = part == .flatbedTruck ? 8 : 6.4
        box(0,0.60,0,length,2.1,0.25,steel)
        for x in [-length/2+1.1,-length/2+2.3,length/2-1.0] { for z: Float in [-1.03,1.03] { worksWheel(x,0.48,z) } }
        worksCab(length/2-1.1,0.85,0,length:2.0,width:2.0,height:1.8,color:part == .serviceTruck ? Map3DPalette.canopy : yellow)
        for z: Float in [-1.08,1.08] { box(length/2-1.15,0.53,z,0.7,0.22,0.12,steel) }
        let cargoX: Float = -0.85
        switch part {
        case .mixerTruck:
            // Short faceted drum on two real supports; distinct from a tank.
            for x: Float in [-2.3,0.3] { box(x,0.85,0,0.28,1.7,0.40,steel) }
            worksTube(Map3DPoint(-2.5,1.95,0),Map3DPoint(0.3,1.65,0),0.82,Map3DPalette.tileWhite,sides:16)
            worksTube(Map3DPoint(-2.65,1.95,0),Map3DPoint(-2.4,1.95,0),0.48,yellow,sides:12)
            for x: Float in [-1.8,-0.6] { worksTube(Map3DPoint(x,1.87,0),Map3DPoint(x+0.12,1.86,0),0.84,yellow,sides:16) }
            beam(Map3DPoint(-2.6,1.7,0),Map3DPoint(-3.45,0.95,0),0.20,steel)
        case .dumpTruck:
            box(cargoX,0.85,0,3.9,2.12,0.14,steel)
            for z: Float in [-1.02,1.02] { box(cargoX,0.99,z,3.9,0.10,1.05,yellow);for x: Float in [-2.3,-1.3,-0.3,0.7] { box(x,0.99,z,0.10,0.14,1.05,steel) } }
            for x: Float in [-2.8,1.1] { box(x,0.99,0,0.10,2.1,1.05,yellow) }
            for i in 0..<7 { worksBlob(Map3DPoint(-2.3+Float(i%4)*0.8,1.3,Float(i%2)*0.7-0.35),Map3DPoint(0.65,0.35,0.55),Map3DPalette.ballast,sides:7,rings:4) }
        case .serviceTruck:
            box(cargoX,0.85,0,3.8,2.1,1.7,Map3DPalette.canopy)
            for z: Float in [-1.06,1.06] { box(cargoX,1.2,z,3.7,0.025,0.18,Self.white) }
            box(-2.77,0.98,0,0.05,1.9,1.43,Self.steel)
            for z: Float in [-0.35,0.35] { box(-2.81,1.5,z,0.04,0.04,0.25,Self.ink) }
            box(cargoX,2.55,0,3.0,1.5,0.08,steel)
            for z: Float in [-0.75,0.75] { box(cargoX,2.62,z,3.0,0.06,0.08,steel) }
        case .flatbedTruck:
            box(-1.05,0.85,0,5.7,2.3,0.13,Self.worksWood)
            box(1.75,0.98,0,0.10,2.3,0.85,yellow)
            for z: Float in [-1.18,1.18] { for x: Float in [-3.5,-2,-0.5,1] { box(x,0.98,z,0.07,0.07,0.65,steel) } }
        case .tankerTruck:
            for x: Float in [-2.2,0.2] { box(x,0.85,0,0.3,1.7,0.35,steel) }
            worksTube(Map3DPoint(-2.7,1.75,0),Map3DPoint(1.0,1.75,0),0.86,Map3DPalette.tankBlue,sides:16)
            for x: Float in [-2.2,0.3] { worksTube(Map3DPoint(x,1.75,0),Map3DPoint(x+0.08,1.75,0),0.88,steel,sides:16) }
            cylinder(-0.6,2.58,0,radius:0.27,height:0.10,color:steel)
            for z: Float in [-0.5,0.5] { beam(Map3DPoint(-2.6,0.9,z),Map3DPoint(-2.6,2.6,z),0.045,steel) }
            for y: Float in [1,1.4,1.8,2.2,2.6] { beam(Map3DPoint(-2.6,y,-0.5),Map3DPoint(-2.6,y,0.5),0.04,steel) }
        default: break
        }
    }
    mutating func worksBucket(_ p: Map3DPoint,width: Float) {
        worksPrism([(p.x-0.1,p.y+0.15),(p.x+0.65,p.y-0.35),(p.x+0.15,p.y-0.50),(p.x-0.32,p.y-0.40),(p.x-0.42,p.y-0.05)],z:p.z,width:width,color:Self.steel)
        for z: Float in [-0.35,0,0.35] { box(p.x+0.61,p.y-0.38,p.z+z*width,0.23,0.13*width,0.09,Self.ink) }
    }
    mutating func worksHook(_ p: Map3DPoint) {
        box(p.x,p.y-0.2,p.z,0.25,0.25,0.30,Self.worksYellow)
        beam(p-Map3DPoint(0,0.18,0),p-Map3DPoint(0,0.5,0),0.07,Self.steel)
        beam(p-Map3DPoint(0,0.5,0),p+Map3DPoint(0.18,-0.6,0),0.07,Self.steel)
        beam(p+Map3DPoint(0.18,-0.6,0),p+Map3DPoint(0.28,-0.4,0),0.07,Self.steel)
    }
}
