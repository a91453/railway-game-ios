import Foundation

extension StationKitBuilder {
    mutating func detailRail(_ part: Map3DDetailKit.Part) {
        let steel=Self.steel,rail=Map3DPalette.rail,top=Map3DPalette.railTop,concrete=Map3DPalette.concrete
        switch part {
        case .jointFishplate,.insulatedJoint:
            // Actual gap between two short I-section rails; paired fishplates.
            for x: Float in [-0.31,0.31] {
                box(x,0,0,0.60,0.15,0.03,rail);box(x,0.03,0,0.60,0.045,0.10,rail);box(x,0.13,0,0.60,0.075,0.04,top)
            }
            for z: Float in [-0.049,0.049] {
                box(0,0.04,z,0.48,0.045,0.08,part == .insulatedJoint ? Self.white : steel)
                for x: Float in [-0.18,-0.06,0.06,0.18] { detailTube(Map3DPoint(x,0.08,z-0.035),Map3DPoint(x,0.08,z+0.035),0.025,Self.ink,sides:6) }
            }
            if part == .insulatedJoint { box(0,0,0,0.018,0.15,0.17,Self.white) }
        case .railFastener:
            box(0,0,0,0.30,0.34,0.025,Self.ink)
            box(0,0.025,0,0.27,0.15,0.03,rail)
            for z: Float in [-0.12,0.12] {
                beam(Map3DPoint(-0.07,0.06,z),Map3DPoint(0.07,0.085,z*0.55),0.035,Self.detailRed)
                cylinder(0,0.025,z,radius:0.027,height:0.055,color:steel,sides:6)
            }
        case .concreteSleeper,.woodSleeper:
            let wood=part == .woodSleeper
            box(0,0,0,wood ? 0.23 : 0.28,2.05,wood ? 0.15 : 0.19,wood ? Map3DPalette.trunk : concrete)
            for z: Float in [-0.5335,0.5335] {
                box(0,wood ? 0.15 : 0.19,z,0.32,0.3,0.025,Self.ink)
                for dz: Float in [-0.11,0.11] { cylinder(0,wood ? 0.175 : 0.215,z+dz,radius:0.025,height:0.04,color:steel,sides:6) }
            }
        case .guardRail:
            box(0,0,0,2,0.15,0.03,rail);box(0,0.03,0,2,0.045,0.10,rail);box(0,0.13,0,2,0.08,0.04,top)
            for x: Float in [-0.7,0,0.7] { box(x,0,0.12,0.10,0.30,0.035,steel) }
        case .turnoutLinkage:
            box(0,0,0,0.7,1.65,0.09,concrete)
            for z: Float in [-0.65,0.65] { box(0,0.09,z,0.22,0.18,0.17,steel) }
            detailTube(Map3DPoint(0,0.21,-0.8),Map3DPoint(0,0.21,0.8),0.04,rail)
            for z: Float in [-0.58,0.58] { cylinder(0,0.19,z,radius:0.08,height:0.055,color:Self.detailAccent) }
        case .pointMotor:
            box(0,0,0,1.0,0.75,0.10,concrete);box(0,0.1,0,0.8,0.56,0.26,Self.ink)
            box(0,0.36,0,0.86,0.6,0.045,steel)
            detailTube(Map3DPoint(0,0.22,0.28),Map3DPoint(0,0.22,0.85),0.04,top)
            for x: Float in [-0.3,0.3] { box(x,0.13,-0.285,0.09,0.02,0.09,Self.detailAccent) }
        case .catenaryInsulator:
            box(0,0,0,0.30,0.30,0.08,steel);cylinder(0,0.08,0,radius:0.07,height:0.75,color:Self.white)
            for i in 0..<6 { cylinder(0,0.14+Float(i)*0.10,0,radius:0.17,height:0.045,color:Self.white) }
            cylinder(0,0.79,0,radius:0.05,height:0.16,color:steel)
        case .tensionWeights:
            box(0,0,0,0.9,0.85,0.12,concrete)
            for z: Float in [-0.30,0.30] { box(-0.24,0.12,z,0.08,0.08,3.0,steel) }
            box(-0.24,3.08,0,0.12,0.75,0.10,steel)
            detailTube(Map3DPoint(-0.24,3.08,0),Map3DPoint(0.20,2.80,0),0.025,Self.ink)
            detailTube(Map3DPoint(0.20,0.6,0),Map3DPoint(0.20,2.80,0),0.023,Self.ink)
            for i in 0..<7 { cylinder(0.20,0.55+Float(i)*0.14,0,radius:0.22,height:0.12,color:concrete) }
            detailWheel(0.20,2.80,0,0.17,0.08)
        case .cableTrough,.trackDrain:
            box(0,0,0,2,0.48,0.06,concrete)
            for z: Float in [-0.21,0.21] { box(0,0.06,z,2,0.06,0.22,concrete) }
            if part == .cableTrough {
                for x: Float in [-0.75,-0.25,0.25,0.75] { box(x,0.28,0,0.48,0.49,0.055,concrete) }
            } else { for i in 0..<16 { box(-0.94+Float(i)*0.125,0.27,0,0.045,0.43,0.035,steel) } }
        case .cableTroughCorner:
            box(-0.25,0,0,1,0.5,0.08,concrete);box(0.25,0,0.25,0.5,1,0.08,concrete)
            for z: Float in [-0.22,0.22] { box(-0.25,0.08,z,0.95,0.06,0.22,concrete) }
            for x: Float in [0.03,0.47] { box(x,0.08,0.48,0.06,0.5,0.22,concrete) }
            box(-0.25,0.30,0,1,0.5,0.05,concrete);box(0.25,0.30,0.48,0.5,0.52,0.05,concrete)
        case .axleCounter:
            box(0,0,0,0.35,0.25,0.04,steel);box(0,0.04,0.06,0.25,0.13,0.14,Self.detailAccent)
            detailTube(Map3DPoint(0,0.08,0.1),Map3DPoint(0.25,0.08,0.3),0.025,Self.ink)
        case .derailDevice:
            box(0,0,0,0.55,0.4,0.05,steel);box(0,0.05,0,0.4,0.23,0.12,Self.detailAccent)
            beam(Map3DPoint(-0.25,0.08,0),Map3DPoint(0.20,0.26,0),0.13,Self.detailAccent)
            box(0.22,0.05,0.18,0.12,0.1,0.38,Self.detailRed)
        case .maintenanceWalkway:
            box(0,0,0,2,0.8,0.08,concrete)
            for x: Float in [-0.8,0,0.8] { box(x,0.08,-0.36,0.055,0.055,1.0,steel) }
            for y: Float in [0.60,1.05] { beam(Map3DPoint(-1,y,-0.36),Map3DPoint(1,y,-0.36),0.05,steel) }
        default: break
        }
    }
    mutating func detailBuilding(_ part: Map3DDetailKit.Part) {
        let steel=Self.steel,white=Self.white
        switch part {
        case .windowGrille,.grilleBay:
            let depth: Float=part == .grilleBay ? 0.42 : 0.12
            detailPlate(0,-0.66,width:0.14,height:1.35);detailPlate(0,0.66,width:0.14,height:1.35)
            detailFrame(depth,0,0,1.4,1.4,0.05)
            for z: Float in [-0.5,-0.25,0,0.25,0.5] { box(depth,0,z,0.04,0.04,1.4,steel) }
            for y: Float in [0.45,0.9] { box(depth,y,0,0.04,1.4,0.04,steel) }
            for y: Float in [0.02,1.36] { for z: Float in [-0.68,0.68] { beam(Map3DPoint(0.02,y,z),Map3DPoint(depth,y,z),0.045,steel) } }
            if part == .grilleBay { for z: Float in [-0.68,0.68] { box(depth/2,0.02,z,depth,0.045,1.35,steel) };box(depth/2,0,0,depth,1.4,0.05,steel) }
        case .awningBrace:
            detailPlate(0,0,width:0.18,height:0.85)
            beam(Map3DPoint(0.02,0.8,0),Map3DPoint(0.9,0.8,0),0.065,steel)
            beam(Map3DPoint(0.04,0.02,0),Map3DPoint(0.9,0.8,0),0.065,steel)
        case .wallPipeStraight,.wallPipeElbow,.wallPipeTee:
            let elbow=part == .wallPipeElbow
            detailTube(Map3DPoint(0.12,0,0),Map3DPoint(0.12,elbow ? 0.8 : 2,0),0.055,white)
            for y: Float in elbow ? [0.15,0.65] : [0.25,1.75] { detailPlate(y-0.06,0,width:0.18,height:0.12);beam(Map3DPoint(0.03,y,0),Map3DPoint(0.12,y,0),0.045,steel) }
            if part != .wallPipeStraight {
                let y: Float=elbow ? 0.8 : 1
                detailTube(Map3DPoint(0.12,y,0),Map3DPoint(0.12,y,0.8),0.055,white)
                detailPlate(y-0.06,0.6,width:0.18,height:0.12);beam(Map3DPoint(0.03,y,0.6),Map3DPoint(0.12,y,0.6),0.045,steel)
            }
        case .meterBox,.meterBank:
            let count=part == .meterBank ? 4 : 1
            detailPlate(0,0,width:Float(count)*0.4,height:0.65)
            for i in 0..<count {
                let z=(Float(i)-Float(count-1)/2)*0.4
                box(0.14,0.06,z,0.22,0.34,0.52,white)
                detailTube(Map3DPoint(0.25,0.35,z),Map3DPoint(0.27,0.35,z),0.1,Self.glass)
                box(0.26,0.15,z,0.025,0.18,0.07,Self.ink)
                detailTube(Map3DPoint(0.1,0,z),Map3DPoint(0.1,-0.22,z),0.025,steel)
            }
        case .gasCylinder:
            cylinder(0,0,0,radius:0.19,height:0.06,color:steel)
            cylinder(0,0.06,0,radius:0.22,height:0.47,color:Map3DPalette.tankSteel)
            cylinder(0,0.53,0,radius:0.15,height:0.09,color:Map3DPalette.tankSteel)
            cylinder(0,0.62,0,radius:0.035,height:0.08,color:Self.detailAccent)
            for z: Float in [-0.11,0.11] { box(0,0.6,z,0.06,0.035,0.18,steel) }
            box(0,0.75,0,0.06,0.25,0.035,steel)
        case .gasCage:
            box(0,0,0,0.8,1.3,0.08,Map3DPalette.concrete)
            for x: Float in [-0.36,0.36] { for z in stride(from:Float(-0.6),through:0.6,by:0.2) { box(x,0.08,z,0.035,0.035,1.1,steel) };box(x,1.14,0,0.04,1.25,0.05,steel) }
            for z: Float in [-0.6,0.6] { for x: Float in [-0.18,0,0.18] { box(x,0.08,z,0.035,0.035,1.1,steel) };box(0,1.14,z,0.8,0.04,0.05,steel) }
            for z: Float in [-0.3,0.3] { add(Map3DDetailKit.model(for:.gasCylinder),at:Map3DPoint(0,0.08,z)) }
        case .tileCorner:
            box(0.07,0,0,0.14,1.2,2.4,Map3DPalette.concreteWalls[0]);box(0.47,0,-0.53,0.94,0.14,2.4,Map3DPalette.concreteWalls[0])
            for row in 0..<12 { for col in 0..<6 { box(0.145,Float(row)*0.2+0.008,-0.5+Float(col)*0.2,0.015,0.184,0.184,Map3DPalette.tileWhite) } }
            for row in 0..<12 { for col in 0..<4 { box(0.23+Float(col)*0.2,Float(row)*0.2+0.008,-0.61,0.184,0.015,0.184,Map3DPalette.tileWhite) } }
        case .corrugatedExtension:
            box(0,0,0,3.2,3.0,0.12,Map3DPalette.concrete)
            for z: Float in [-1.45,1.45] { box(0,0.12,z,3.2,0.08,2.4,Map3DPalette.roof) }
            box(-1.55,0.12,0,0.08,3,2.4,Map3DPalette.roof)
            for z: Float in [-1.4,1.4] { for x: Float in [-1.5,1.5] { box(x,0.12,z,0.08,0.08,2.42,steel) } }
            box(0,2.52,0,3.4,3.2,0.10,Map3DPalette.roof)
            for i in 0..<16 { box(-1.5+Float(i)*0.2,2.62,0,0.045,3.2,0.025,steel) }
            detailFrame(1.55,0.12,0,2.8,2.4,0.08)
        case .wallCableTray:
            for y: Float in [0.2,1.4] { detailPlate(y,0,width:0.4,height:0.15);box(0.15,y,0,0.28,0.08,0.06,steel) }
            for z: Float in [-0.22,0.22] { box(0.2,0,z,0.28,0.04,2,steel) }
            for i in 0..<10 { box(0.2,Float(i)*0.21,0,0.26,0.45,0.035,steel) }
            for z: Float in [-0.1,0,0.1] { detailTube(Map3DPoint(0.24,0,z),Map3DPoint(0.24,2,z),0.025,Self.ink) }
        case .pipeClamp:
            detailPlate(0,0,width:0.22,height:0.22)
            detailTube(Map3DPoint(0.04,0.11,0),Map3DPoint(0.14,0.11,0),0.055,steel)
            for z: Float in [-0.08,0.08] { box(0.14,0.04,z,0.06,0.025,0.14,steel) }
            for y: Float in [0.04,0.16] { box(0.14,y,0,0.06,0.16,0.025,steel) }
        case .wallTap:
            detailPlate(0,0,width:0.18,height:0.22)
            detailTube(Map3DPoint(0.04,0.11,0),Map3DPoint(0.23,0.11,0),0.035,steel)
            detailTube(Map3DPoint(0.23,0.11,0),Map3DPoint(0.23,0.01,0),0.035,steel)
            box(0.14,0.15,0,0.07,0.18,0.035,Self.detailAccent)
        case .wallVentHood:
            detailPlate(0,0,width:0.7,height:0.65)
            box(0.20,0.08,0,0.35,0.54,0.48,Map3DPalette.roof)
            for i in 0..<5 { box(0.39,0.12+Float(i)*0.085,0,0.035,0.50,0.03,steel) }
            box(0.24,0.56,0,0.46,0.68,0.06,Map3DPalette.roof)
        default: break
        }
    }
}
