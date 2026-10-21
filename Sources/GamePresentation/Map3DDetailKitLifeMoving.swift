import Foundation

extension StationKitBuilder {
    mutating func detailLife(_ part: Map3DDetailKit.Part) {
        let steel=Self.steel,wood=Map3DPalette.counters[1],white=Self.white,ink=Self.ink
        switch part {
        case .shopShelf:
            detailRack(width:1.4,height:1.9,depth:0.6)
            for i in 0..<3 { for j in 0..<5 { box(0,0.13+Float(i)*0.57,-0.52+Float(j)*0.26,0.35,0.19,0.28,Map3DPalette.counters[(i+j)%Map3DPalette.counters.count]) } }
            box(-0.30,0.05,0,0.045,1.4,1.82,Map3DPalette.concrete)
        case .chestFreezer:
            for z: Float in [-0.5,0.5] { box(0,0,z,0.55,0.10,0.08,ink) }
            box(0,0.08,0,0.70,1.2,0.72,white)
            box(0,0.8,0,0.74,1.24,0.07,steel)
            for z: Float in [-0.3,0.3] { box(0,0.87,z,0.62,0.54,0.025,Self.glass);box(0.29,0.89,z,0.045,0.20,0.025,white) }
            for z: Float in [-0.43,-0.31,-0.19] { box(0.355,0.2,z,0.015,0.045,0.20,steel) }
        case .cartonClosed:
            box(0,0,0,0.55,0.48,0.42,wood);box(0,0.42,0,0.57,0.09,0.012,Self.detailAccent)
            for x: Float in [-0.27,0.27] { box(x,0,0,0.015,0.09,0.42,Self.detailAccent) }
            box(0.28,0.12,0.12,0.015,0.12,0.10,white)
        case .cartonOpen:
            box(0,0,0,0.55,0.48,0.025,wood)
            for x: Float in [-0.26,0.26] { box(x,0,0,0.03,0.48,0.38,wood) }
            for z: Float in [-0.225,0.225] { box(0,0,z,0.55,0.03,0.38,wood) }
            for z: Float in [-0.31,0.31] { box(0,0.37,z,0.55,0.18,0.025,wood) }
        case .stackingCrate: detailCrate(0,0,0)
        case .foldingChair:
            for z: Float in [-0.21,0.21] {
                beam(Map3DPoint(-0.22,0,z),Map3DPoint(0.18,0.47,z),0.035,steel)
                beam(Map3DPoint(0.22,0,z),Map3DPoint(-0.20,0.47,z),0.035,steel)
                beam(Map3DPoint(-0.20,0.45,z),Map3DPoint(-0.26,0.85,z),0.035,steel)
            }
            box(0,0.44,0,0.44,0.48,0.04,Map3DPalette.canopy);box(-0.24,0.65,0,0.04,0.48,0.20,Map3DPalette.canopy)
        case .plantRack:
            detailRack(width:1.4,height:1.35,depth:0.45,levels:3)
            for y: Float in [0.13,0.73] { for z: Float in [-0.46,0,0.46] {
                detailFrustum(Map3DPoint(0,y,z),0.1,0.14,0.20,Map3DPalette.trunk)
                cylinder(0,y+0.20,z,radius:0.15,height:0.13,color:Self.detailGreen,sides:7)
                box(0,y+0.3,z,0.12,0.16,0.14,Map3DProp.greens[2])
            } }
        case .dryingRack:
            for z: Float in [-0.65,0.65] {
                beam(Map3DPoint(-0.45,0,z),Map3DPoint(0.35,1.45,z),0.035,steel)
                beam(Map3DPoint(0.45,0,z),Map3DPoint(-0.35,1.45,z),0.035,steel)
            }
            for x: Float in [-0.35,0,0.35] { beam(Map3DPoint(x,1.45,-0.65),Map3DPoint(x,1.45,0.65),0.025,steel) }
            for z: Float in [-0.4,0,0.4] { box(0,0.85,z,0.018,0.28,0.6,Map3DPalette.counters[Int((z+0.4)*5)%Map3DPalette.counters.count]);box(0.10,1.43,z,0.23,0.28,0.018,white) }
        case .laundryBasket:
            detailCrate(0,0,0,width:0.5,color:white)
            for z: Float in [-0.25,0.25] { box(0,0.34,z,0.25,0.025,0.05,steel) }
        case .pallet:
            for x: Float in [-0.45,0,0.45] { for z: Float in [-0.35,0,0.35] { box(x,0,z,0.14,0.14,0.10,wood) } }
            for z: Float in [-0.35,0,0.35] { box(0,0,z,1.1,0.13,0.025,wood) }
            for i in 0..<6 { box(-0.47+Float(i)*0.19,0.1,0,0.14,0.85,0.035,wood) }
        case .produceDisplay:
            for x: Float in [-0.32,0.32] { for z: Float in [-0.7,0.7] { box(x,0,z,0.06,0.06,0.8,steel) } }
            box(0,0.75,0,0.8,1.6,0.08,wood)
            for z: Float in [-0.5,0,0.5] {
                detailCrate(0,0.83,z,width:0.47,color:wood)
                for x: Float in [-0.10,0.10] { for dz: Float in [-0.12,0.12] { cylinder(x,0.88,z+dz,radius:0.085,height:0.10,color:z == 0 ? Self.detailRed : Self.detailGreen,sides:7) } }
            }
        case .handTruck:
            for z: Float in [-0.23,0.23] { detailWheel(-0.05,0.12,z);box(-0.12,0.14,z,0.045,0.045,1.0,steel) }
            box(0.08,0.06,0,0.42,0.55,0.04,steel)
            beam(Map3DPoint(-0.12,1.14,-0.23),Map3DPoint(-0.12,1.14,0.23),0.045,ink)
            for y: Float in [0.40,0.75] { box(-0.12,y,0,0.04,0.5,0.04,steel) }
        case .shopCounter:
            box(0,0,0,0.65,1.6,0.85,wood);box(0,0.85,0,0.8,1.75,0.07,white)
            box(-0.15,0.92,0.45,0.23,0.35,0.10,ink);box(-0.15,1.02,0.45,0.06,0.30,0.23,ink);box(-0.113,1.04,0.45,0.015,0.26,0.17,Self.glass)
        case .riceSack:
            detailFrustum(Map3DPoint(0,0,0),0.22,0.25,0.48,Map3DPalette.playerRoof)
            detailFrustum(Map3DPoint(0,0.48,0),0.25,0.12,0.16,Map3DPalette.playerRoof)
            box(0,0.63,0,0.08,0.28,0.025,wood)
            box(0.24,0.15,0,0.02,0.18,0.17,Self.detailGreen)
        case .plasticStool:
            for x: Float in [-0.14,0.14] { for z: Float in [-0.14,0.14] { box(x,0,z,0.055,0.055,0.33,Self.detailRed) } }
            box(0,0.33,0,0.38,0.38,0.055,Self.detailRed)
            box(0,0.388,0,0.16,0.04,0.006,ink)
        case .parcelStack:
            add(Map3DDetailKit.model(for:.pallet),at:.zero)
            for x: Float in [-0.27,0.27] { for z: Float in [-0.22,0.22] { add(Map3DDetailKit.model(for:.cartonClosed),at:Map3DPoint(x,0.135,z)) } }
            add(Map3DDetailKit.model(for:.cartonClosed),at:Map3DPoint(0,0.567,0))
        default: break
        }
    }

    mutating func detailMoving(_ part: Map3DDetailKit.Part,moving m: inout StationKitBuilder) {
        let steel=Self.steel,ink=Self.ink,white=Self.white
        switch part {
        case .hingedDoor,.slidingDoor,.platformDoorLeaf:
            let sliding=part != .hingedDoor
            // Frame and lower rail remain fixed; panel rotates/slides separately.
            detailPlate(0,0,width:0.12,height:2.3);detailFrame(0.06,0,0.56,1.12,2.3,0.12)
            if sliding { box(0.12,2.3,1.1,0.20,2.4,0.12,steel) }
            m.box(0.10,0.04,0.55,0.065,1.02,2.17,part == .platformDoorLeaf ? steel : Map3DPalette.counters[1])
            m.box(0.14,0.85,0.55,0.018,0.82,1.0,Self.glass)
            m.box(0.16,0.85,0.95,0.06,0.04,0.30,ink)
            if !sliding { for y: Float in [0.25,1.85] { cylinder(0.1,y,0,radius:0.045,height:0.15,color:steel) } }
        case .shutterSlat:
            for z: Float in [-0.85,0.85] { box(0,0,z,0.12,0.05,0.32,steel) }
            m.box(0,0,0,0.055,1.7,0.14,Map3DPalette.roof);m.box(0.028,0.11,0,0.025,1.7,0.025,steel)
        case .gateFlap:
            box(0,0,0,0.4,0.22,1,steel)
            m.box(0,0.7,0.42,0.045,0.8,0.25,Self.glass)
            m.box(0,0.94,0.42,0.05,0.8,0.025,Self.detailAccent)
        case .wheelset:
            // Two flanged wheels, axle and visible nonradial brake pads/spokes.
            for z: Float in [-0.60,0.60] { box(0,0.38,z,0.24,0.16,0.16,steel) }
            m.detailTube(Map3DPoint(0,0.46,-0.70),Map3DPoint(0,0.46,0.70),0.075,steel)
            for z: Float in [-0.5335,0.5335] {
                m.detailTube(Map3DPoint(0,0.46,z-0.05),Map3DPoint(0,0.46,z+0.05),0.43,Map3DPalette.railTop,sides:24)
                m.detailTube(Map3DPoint(0,0.46,z-0.065),Map3DPoint(0,0.46,z-0.045),0.46,steel,sides:24)
                m.box(0,0.17,z+0.055,0.065,0.02,0.58,ink)
                m.box(0.10,0.61,z+0.06,0.12,0.025,0.12,Self.detailAccent)
            }
        case .connectingRod:
            for x: Float in [-0.7,0.7] { box(x,0,0,0.10,0.3,0.30,steel) }
            m.box(0,0.12,0,1.6,0.08,0.08,Map3DPalette.railTop)
            for x: Float in [-0.8,0.8] { m.detailTube(Map3DPoint(x,0.16,-0.06),Map3DPoint(x,0.16,0.06),0.13,steel);m.detailTube(Map3DPoint(x,0.16,-0.065),Map3DPoint(x,0.16,0.065),0.05,ink) }
        case .barrierArm:
            box(0,0,0,0.4,0.4,0.9,Map3DPalette.canopy)
            m.box(-1.4,0.84,0,3.0,0.10,0.12,white)
            for x: Float in [-2.6,-2,-1.4,-0.8,-0.2] { m.box(x,0.84,0,0.22,0.115,0.125,Self.detailRed) }
            m.detailTube(Map3DPoint(0,0.9,-0.1),Map3DPoint(0,0.9,0.1),0.15,steel)
        case .ventFan:
            detailPlate(0,0,width:1.2,height:1.2);detailFrame(0.12,0,0,1.2,1.2,0.18)
            for z: Float in [-0.5,0.5] { beam(Map3DPoint(0.16,0.1,z),Map3DPoint(0.16,1.1,-z),0.035,steel) }
            m.detailTube(Map3DPoint(0.14,0.6,0),Map3DPoint(0.22,0.6,0),0.13,ink)
            m.box(0.18,0.6,-0.20,0.045,0.38,0.14,white)
            m.box(0.18,0.72,0.12,0.045,0.18,0.38,white)
            m.box(0.18,0.23,0.13,0.045,0.18,0.27,white)
        case .foldingGate:
            detailPlate(0,0,width:0.12,height:2.2);box(0.1,0,1.3,0.12,0.10,2.2,steel)
            for z: Float in [0,1.3] { m.box(0.1,0,z,0.05,0.05,2.2,steel) }
            for i in 0..<5 { let z=Float(i)*0.26
                m.beam(Map3DPoint(0.1,0.1,z),Map3DPoint(0.1,2.1,z+0.26),0.03,steel)
                m.beam(Map3DPoint(0.1,2.1,z),Map3DPoint(0.1,0.1,z+0.26),0.03,steel)
            }
        case .cabinetDoor:
            detailPlate(0,0,width:0.12,height:1.25);detailFrame(0.14,0.10,0.4,0.8,1.15,0.1)
            m.box(0.18,0.12,0.4,0.05,0.76,1.08,steel);m.box(0.22,0.48,0.72,0.06,0.03,0.16,ink)
            for y: Float in [0.8,0.9,1.0] { m.box(0.21,y,0.35,0.02,0.5,0.025,ink) }
        case .trolleyCaster:
            box(0,0.27,0,0.24,0.24,0.04,steel)
            for z: Float in [-0.07,0.07] { box(0,0.13,z,0.12,0.03,0.15,steel) }
            m.detailWheel(0,0.16,0,0.16,0.10);m.box(0.05,0.20,0.06,0.045,0.015,0.05,Self.detailAccent)
        case .turnoutBlade:
            for x: Float in [-1,-0.5,0,0.5,1] { box(x,0,0.08,0.16,0.5,0.045,Map3DPalette.concrete) }
            // A tapered closed prism, rather than a full-width duplicate rail.
            let a=Map3DPoint(-1,0.045,-0.015),b=Map3DPoint(1,0.045,-0.04),c=Map3DPoint(1,0.045,0.04),d=Map3DPoint(-1,0.045,0.005),h=Map3DPoint(0,0.13,0)
            let inside=Map3DPoint(0,0.11,0)
            for f in [[a,b,c,d],[a+h,d+h,c+h,b+h],[a,a+h,b+h,b],[b,b+h,c+h,c],[c,c+h,d+h,d],[d,d+h,a+h,a]] { m.face(f,inside:inside,color:Map3DPalette.railTop) }
        case .roofHatch:
            box(0,0,0,1.15,0.95,0.10,Map3DPalette.concrete);detailFrame(0,0.1,0,0.95,0.06,1.15)
            m.box(0,0.14,0,1.0,0.8,0.06,steel);m.box(0.25,0.20,0,0.06,0.24,0.05,ink)
        case .escalatorStep:
            for z: Float in [-0.45,0.45] { beam(Map3DPoint(-0.3,0,z),Map3DPoint(0.6,0.675,z),0.07,steel) }
            m.box(0,0.23,0,0.4,0.8,0.06,steel);m.box(-0.19,0.06,0,0.04,0.8,0.17,steel)
            for z in stride(from:Float(-0.36),through:0.36,by:0.06) { m.box(0,0.29,z,0.4,0.015,0.012,ink) }
            for z: Float in [-0.39,0.39] { m.box(0,0.29,z,0.40,0.02,0.015,Self.detailAccent) }
        case .serviceWindow:
            detailPlate(0,0,width:1.2,height:1.3);detailFrame(0.08,0,0,1.2,1.3,0.10)
            m.box(0.12,0.10,0,0.05,1.08,1.1,white);m.box(0.15,0.23,0,0.02,0.92,0.80,Self.glass)
            m.box(0.18,0.13,0,0.06,0.22,0.04,ink)
        default: break
        }
    }
}
