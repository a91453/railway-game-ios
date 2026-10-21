import Foundation

extension StationKitBuilder {
    mutating func worksFreight(_ part: Map3DWorksKit.Part) {
        let steel=Self.steel,yellow=Self.worksYellow,concrete=Map3DPalette.concrete
        switch part {
        case .container20,.container40,.openContainer,.containerOffice:
            let length: Float=part == .container40 ? 12.2 : 6.1,office=part == .containerOffice,open=part == .openContainer
            let color=office ? Map3DPalette.tileWhite : part == .container40 ? Map3DPalette.canopy : yellow
            box(0,0,0,length,2.44,0.12,steel)
            for z: Float in [-1.18,1.18] { box(0,0.12,z,length,0.08,2.40,color) }
            box(-length/2+0.04,0.12,0,0.08,2.44,2.4,color)
            for x in stride(from:-length/2+0.22,to:length/2,by:Float(0.32)) {
                for z: Float in [-1.225,1.225] { box(x,0.15,z,0.07,0.035,2.30,color) }
                if !open { box(x,2.56,0,0.07,2.44,0.04,color) }
            }
            if !open { box(0,2.52,0,length,2.44,0.04,color) }
            if office {
                box(length/2-0.04,0.12,0,0.08,2.44,2.4,color)
                pane(length/2+0.005,0.55,-0.5,0.8,1.35)
                for x: Float in [-1.8,-0.2,1.4] {
                    box(x,0.75,1.24,1.15,0.035,1.0,steel);box(x,0.82,1.262,0.99,0.015,0.84,Self.glass)
                }
                box(1.4,0,1.65,1.1,0.75,0.18,concrete)
            } else {
                for z: Float in [-0.58,0.58] {
                    box(length/2-0.04,0.12,z,0.08,1.15,2.4,color)
                    for dz: Float in [-0.35,0.35] { worksTube(Map3DPoint(length/2+0.06,0.22,z+dz),Map3DPoint(length/2+0.06,2.4,z+dz),0.025,steel,sides:6) }
                    box(length/2+0.08,1.1,z,0.04,0.30,0.07,steel)
                }
            }
            for x in [-length/2+0.06,length/2-0.06] { for z: Float in [-1.16,1.16] { box(x,0,z,0.12,0.12,0.12,steel);box(x,2.48,z,0.12,0.12,0.12,steel) } }
        case .warehouse,.maintenanceShed:
            let repair=part == .maintenanceShed,length: Float=repair ? 14 : 12,width: Float=repair ? 10 : 8
            box(0,0,0,length+0.6,width+0.6,0.2,concrete)
            // End openings are built as actual lintel and jambs, with no
            // dark window/door rectangle hovering in a missing wall.
            box(-length/2,0.2,0,0.18,width,4.6,Map3DPalette.concreteWalls[0])
            for z in [-width/2,width/2] { box(0,0.2,z,length,0.18,4.6,Map3DPalette.concreteWalls[0]) }
            for z in [-width*0.38,width*0.38] { box(length/2,0.2,z,0.18,width*0.24,3.9,Map3DPalette.concreteWalls[0]) }
            box(length/2,4.1,0,0.18,width,0.7,Map3DPalette.concreteWalls[0])
            gable(0,4.8,0,length,width,repair ? 1.4 : 1.0,repair ? Map3DPalette.canopy : Map3DPalette.roof)
            for z in [-width/2-0.11,width/2+0.11] {
                for x in stride(from:-length/2+1,to:length/2,by:Float(2)) { box(x,2.0,z,1.25,0.025,1.4,Self.glass) }
            }
            for x in stride(from:-length/2+0.5,to:length/2,by:Float(3)) { for z in [-width/2+0.18,width/2-0.18] { box(x,0.2,z,0.16,0.16,4.6,steel) } }
            if repair {
                track(-length/2+0.5,length/2-0.1,0,at:0.2)
                for z: Float in [-3,3] { box(-2,0.2,z,3,0.7,1.0,steel);box(-2,1.20,z,3.1,0.85,0.08,yellow) }
                box(1.0,3.5,0,0.45,width-0.3,0.35,yellow)
            } else {
                for z: Float in [-2.5,2.5] { for x: Float in [-4,-1,2] { box(x,0.2,z,1.6,1.1,1.4,Self.worksWood) } }
                box(length/2+0.9,0,0,1.8,width-1,0.55,concrete)
            }
        case .loadingCanopy:
            box(0,0,0,10,7,0.15,concrete)
            for x: Float in [-4,0,4] { for z: Float in [-2.6,2.6] { box(x,0.15,z,0.18,0.18,3.85,steel) };beam(Map3DPoint(x,4,-2.6),Map3DPoint(x,4,2.6),0.18,steel) }
            gable(0,4,0,10,6,0.75,Map3DPalette.canopy)
            box(0,0.15,-2,8,2,0.75,concrete)
        case .gantryCrane:
            for z: Float in [-3,3] {
                box(0,0,z,8,0.18,0.12,Map3DPalette.railTop)
                for x: Float in [-2.6,2.6] { worksWheel(x,0.24,z,radius:0.22,width:0.18,rail:true) }
                box(0,0.40,z,6.4,0.50,0.28,steel)
                for x: Float in [-2.5,2.5] { beam(Map3DPoint(x,0.68,z),Map3DPoint(x*0.72,5.8,z),0.20,yellow) }
            }
            for x: Float in [-1.8,1.8] { box(x,5.8,0,0.35,6.8,0.5,yellow) }
            for z: Float in [-2.8,2.8] { beam(Map3DPoint(-1.8,5.5,z),Map3DPoint(1.8,5.5,z),0.1,steel) }
            box(0,6.15,-0.7,3.7,0.8,0.20,steel)
            for x: Float in [-1.2,1.2] { worksTube(Map3DPoint(x,6.0,-0.7),Map3DPoint(x,3.3,-0.7),0.025,Self.ink,sides:6) }
            box(0,3.15,-0.7,3.0,1.1,0.22,yellow)
            box(-1.8,4.15,2.6,1.4,1.5,0.15,steel)
            worksCab(-1.8,4.3,2.6,length:1.2,width:1.15,height:1.3)
        case .cableReel:
            for x: Float in [-0.55,0.55] { box(x,0,0,0.2,1.65,0.16,Self.worksWood) }
            worksTube(Map3DPoint(0,0.90,-0.40),Map3DPoint(0,0.90,0.40),0.67,Self.ink,sides:20)
            for z: Float in [-0.46,0.46] {
                worksTube(Map3DPoint(0,0.9,z-0.06),Map3DPoint(0,0.9,z+0.06),0.76,Self.worksWood,sides:20)
                worksTube(Map3DPoint(0,0.9,z-0.065),Map3DPoint(0,0.9,z+0.065),0.09,steel,sides:8)
            }
            for i in 0..<10 { worksTube(Map3DPoint(0,0.9,-0.38+Float(i)*0.08),Map3DPoint(0,0.9,-0.36+Float(i)*0.08),0.69,steel,sides:20) }
        case .ibcTank:
            box(0,0,0,1.2,1.0,0.12,steel);box(0,0.12,0,1.1,0.9,1.05,Self.white)
            for x: Float in [-0.57,0.57] { for z in stride(from:Float(-0.45),through:0.45,by:0.15) { box(x,0.12,z,0.025,0.025,1.1,steel) } }
            for z: Float in [-0.47,0.47] { for x in stride(from:Float(-0.5),through:0.5,by:0.2) { box(x,0.12,z,0.025,0.025,1.1,steel) } }
            for y: Float in [0.25,0.6,0.95,1.20] { for x: Float in [-0.57,0.57] { box(x,y,0,0.025,0.96,0.025,steel) };for z: Float in [-0.47,0.47] { box(0,y,z,1.16,0.025,0.025,steel) } }
            cylinder(0,1.17,0,radius:0.12,height:0.06,color:Self.ink)
            worksTube(Map3DPoint(0.55,0.20,0),Map3DPoint(0.70,0.20,0),0.045,steel)
        case .pipeBundle:
            for x: Float in [-1.3,1.3] { box(x,0,0,0.22,1.7,0.16,Self.worksWood) }
            for (y,z) in [(Float(0.4),Float(-0.5)),(0.4,0),(0.4,0.5),(0.83,-0.25),(0.83,0.25),(1.26,0)] {
                worksTube(Map3DPoint(-2,y,z),Map3DPoint(2,y,z),0.24,steel,sides:12)
                for x: Float in [-2.005,2.005] { worksTube(Map3DPoint(x-0.005,y,z),Map3DPoint(x+0.005,y,z),0.18,Self.ink,sides:12) }
            }
            for x: Float in [-1.2,1.2] { box(x,1.45,0,0.06,0.55,0.035,Self.ink) }
        case .wheelRack:
            box(0,0,0,3.6,2.1,0.12,concrete)
            for z: Float in [-0.8,0.8] { box(0,0.12,z,3.4,0.12,0.14,steel) }
            for x: Float in [-1.1,0,1.1] {
                worksTube(Map3DPoint(x,0.65,-0.9),Map3DPoint(x,0.65,0.9),0.08,steel)
                for z: Float in [-0.5335,0.5335] { worksWheel(x,0.65,z,radius:0.40,width:0.12,rail:true) }
            }
        default: break
        }
    }
}
