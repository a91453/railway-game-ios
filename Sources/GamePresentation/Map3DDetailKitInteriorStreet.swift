import Foundation

extension StationKitBuilder {
    mutating func detailInterior(_ part: Map3DDetailKit.Part) {
        let steel=Self.steel,ink=Self.ink,white=Self.white
        switch part {
        case .cctvCamera:
            detailPlate(0,0,width:0.18,height:0.25)
            beam(Map3DPoint(0.03,0.12,0),Map3DPoint(0.38,0.25,0),0.06,steel)
            box(0.48,0.20,0,0.42,0.20,0.18,white)
            detailTube(Map3DPoint(0.69,0.29,0),Map3DPoint(0.72,0.29,0),0.065,ink)
            box(0.51,0.38,0,0.51,0.25,0.035,white)
        case .domeCamera:
            cylinder(0,-0.05,0,radius:0.17,height:0.05,color:white)
            cylinder(0,-0.20,0,radius:0.13,height:0.15,color:ink)
            cylinder(0,-0.23,0,radius:0.08,height:0.03,color:Self.glass)
        case .paSpeaker:
            detailPlate(0,0,width:0.27,height:0.50);box(0.17,0.03,0,0.30,0.25,0.44,white)
            for i in 0..<7 { box(0.325,0.07+Float(i)*0.05,0,0.012,0.20,0.018,ink) }
        case .hornSpeaker:
            detailPlate(0,0,width:0.2,height:0.32);beam(Map3DPoint(0.02,0.16,0),Map3DPoint(0.27,0.16,0),0.055,steel)
            detailTube(Map3DPoint(0.2,0.16,0),Map3DPoint(0.50,0.16,0),0.09,white)
            detailTube(Map3DPoint(0.45,0.16,0),Map3DPoint(0.62,0.16,0),0.22,white)
            detailTube(Map3DPoint(0.62,0.16,0),Map3DPoint(0.63,0.16,0),0.17,ink)
        case .emergencyIntercom:
            detailPlate(0,0,width:0.26,height:0.48);box(0.10,0.03,0,0.15,0.23,0.42,Self.detailAccent)
            for i in 0..<4 { box(0.18,0.27+Float(i)*0.025,0,0.015,0.12,0.008,ink) }
            detailTube(Map3DPoint(0.18,0.14,0),Map3DPoint(0.20,0.14,0),0.042,Self.detailRed)
        case .fireCabinet,.aedCabinet:
            let fire=part == .fireCabinet,w: Float=fire ? 0.65 : 0.45,h: Float=fire ? 0.95 : 0.55
            detailPlate(0,0,width:w+0.04,height:h+0.04);box(0.15,0.02,0,0.26,w,h,fire ? Self.detailRed : white)
            box(0.285,0.13,0,0.015,w-0.12,h-0.2,Self.glass)
            box(0.30,0.20,w/2-0.05,0.03,0.035,0.15,steel)
            if fire {
                detailTube(Map3DPoint(0.30,0.58,0),Map3DPoint(0.32,0.58,0),0.17,white)
                detailTube(Map3DPoint(0.32,0.58,0),Map3DPoint(0.33,0.58,0),0.11,Self.detailRed)
            } else {
                box(0.30,0.22,0,0.035,0.20,0.17,Self.detailGreen)
                box(0.32,0.25,0,0.02,0.12,0.03,white);box(0.32,0.22,0,0.02,0.03,0.10,white)
            }
        case .queuePost,.queueBelt:
            if part == .queuePost {
                cylinder(0,0,0,radius:0.18,height:0.045,color:steel);cylinder(0,0.045,0,radius:0.035,height:0.92,color:steel);cylinder(0,0.91,0,radius:0.075,height:0.09,color:ink)
            } else {
                for z: Float in [-0.8,0.8] { add(Map3DDetailKit.model(for:.queuePost),at:Map3DPoint(0,0,z)) }
                box(0,0.91,0,0.035,1.6,0.07,Map3DPalette.canopy)
            }
        case .baggageTrolley,.cleaningCart:
            let clean=part == .cleaningCart
            for x: Float in [-0.34,0.34] { for z: Float in [-0.26,0.26] { detailWheel(x,0.12,z);box(x,0.12,z,0.06,0.06,0.12,steel) } }
            box(0,0.22,0,0.84,0.64,0.06,steel)
            for z: Float in [-0.28,0.28] { box(-0.36,0.28,z,0.055,0.055,0.87,steel) }
            beam(Map3DPoint(-0.36,1.12,-0.28),Map3DPoint(-0.36,1.12,0.28),0.06,ink)
            if clean {
                box(0.12,0.28,0,0.44,0.48,0.55,Self.detailAccent);box(-0.18,0.44,0,0.12,0.62,0.08,steel)
                detailTube(Map3DPoint(-0.35,0.28,0.12),Map3DPoint(-0.25,1.45,0.12),0.025,Map3DPalette.trunk)
                box(-0.35,0.28,0.12,0.16,0.30,0.06,white)
            } else {
                for i in 0..<6 { box(-0.31+Float(i)*0.125,0.28,0,0.045,0.6,0.035,steel) }
                box(-0.20,0.28,0,0.22,0.5,0.38,Map3DPalette.canopy);box(0.18,0.28,0,0.32,0.40,0.28,Map3DPalette.counters[1])
            }
        case .routeMapCase:
            detailPlate(0,0,width:1.2,height:0.9);box(0.07,0.04,0,0.08,1.1,0.80,white)
            for (y,color) in [(Float(0.25),Map3DPalette.canopy),(0.48,Self.detailRed),(0.65,Self.detailGreen)] {
                box(0.115,y,0,0.015,0.84,0.035,color)
                for z: Float in [-0.3,0,0.3] { box(0.125,y-0.015,z,0.015,0.07,0.07,ink);box(0.135,y,z,0.015,0.04,0.04,white) }
            }
        case .ceilingLight:
            box(0,-0.10,0,1.2,0.28,0.10,steel)
            let start=mesh.vertices.count;box(0,-0.13,0,1.1,0.22,0.03,Map3DProp.lampLight);mesh.makeGlowing(from:start)
        case .pendantLight:
            cylinder(0,-0.04,0,radius:0.12,height:0.04,color:steel)
            cylinder(0,-0.8,0,radius:0.018,height:0.76,color:ink)
            cylinder(0,-0.90,0,radius:0.25,height:0.12,color:Map3DPalette.canopy)
            let start=mesh.vertices.count;cylinder(0,-0.93,0,radius:0.21,height:0.03,color:Map3DProp.lampLight);mesh.makeGlowing(from:start)
        case .fireExtinguisher:
            cylinder(0,0,0,radius:0.105,height:0.45,color:Self.detailRed)
            cylinder(0,0.45,0,radius:0.05,height:0.07,color:steel)
            box(0,0.51,0,0.08,0.17,0.035,ink)
            beam(Map3DPoint(0,0.48,0.08),Map3DPoint(0,0.11,0.13),0.03,ink)
            box(0.108,0.15,0,0.015,0.09,0.14,white)
        case .lostPropertyShelf:
            detailRack(width:1.8,height:1.9,depth:0.5,levels:4)
            for i in 0..<3 { for j in 0..<3 { box(0,0.13+Float(i)*0.58,-0.6+Float(j)*0.6,0.42,0.48,0.28,Map3DPalette.counters[(i+j)%Map3DPalette.counters.count]) } }
        default: break
        }
    }
    mutating func detailStreet(_ part: Map3DDetailKit.Part) {
        let steel=Self.steel,concrete=Map3DPalette.concrete,ink=Self.ink
        switch part {
        case .curbStraight: box(0,0,0,2,0.22,0.22,Map3DPalette.sidewalk)
        case .curbCorner:
            box(-0.4,0,0,1.2,0.22,0.22,Map3DPalette.sidewalk);box(0.09,0,0.49,0.22,1.2,0.22,Map3DPalette.sidewalk)
        case .gutterGrate,.utilityCover:
            box(0,0,0,1.0,0.5,0.035,ink)
            if part == .gutterGrate { for i in 0..<10 { box(-0.45+Float(i)*0.10,0.035,0,0.045,0.48,0.025,steel) } }
            else { box(0,0.035,0,0.94,0.44,0.025,steel);for z: Float in [-0.17,0.17] { box(0,0.06,z,0.12,0.035,0.015,ink) } }
        case .manholeCover:
            cylinder(0,0,0,radius:0.40,height:0.035,color:ink,sides:24);cylinder(0,0.035,0,radius:0.36,height:0.025,color:steel,sides:24)
            for z: Float in [-0.2,-0.1,0,0.1,0.2] { box(0,0.06,z,0.52,0.025,0.008,ink) }
            for x: Float in [-0.2,0.2] { box(x,0.06,0,0.035,0.16,0.012,ink) }
        case .catchBasin:
            box(0,0,0,0.9,0.7,0.08,concrete)
            for x: Float in [-0.4,0.4] { box(x,0.08,0,0.1,0.7,0.45,concrete) }
            for z: Float in [-0.3,0.3] { box(0,0.08,z,0.9,0.1,0.45,concrete) }
            for i in 0..<7 { box(-0.3+Float(i)*0.10,0.53,0,0.045,0.6,0.035,steel) }
        case .trafficCone:
            box(0,0,0,0.38,0.38,0.045,ink)
            detailFrustum(Map3DPoint(0,0.045,0),0.15,0.025,0.52,Self.detailAccent)
            detailFrustum(Map3DPoint(0,0.27,0),0.097,0.075,0.09,Self.white)
        case .convexMirror:
            box(0,0,0,0.40,0.40,0.08,concrete);cylinder(0,0.08,0,radius:0.035,height:2.2,color:steel)
            beam(Map3DPoint(0,2.15,0),Map3DPoint(0.20,2.15,0),0.055,steel)
            detailTube(Map3DPoint(0.16,2.15,0),Map3DPoint(0.23,2.15,0),0.38,Self.detailAccent,sides:24)
            detailTube(Map3DPoint(0.23,2.15,0),Map3DPoint(0.24,2.15,0),0.32,Self.glass,sides:24)
            box(0.22,2.52,0,0.20,0.80,0.04,Self.detailAccent)
        case .guardrailEnd:
            for x: Float in [-0.65,0.35] { box(x,0,0,0.12,0.12,0.75,steel);box(x,0.74,0,0.18,0.18,0.025,steel) }
            box(-0.15,0.50,0.04,1.7,0.10,0.22,Map3DPalette.railTop)
            box(0.66,0.42,0.04,0.14,0.16,0.4,Map3DPalette.railTop)
            box(0.74,0.53,0.04,0.025,0.12,0.12,Self.detailAccent)
        case .roadBarrier:
            box(0,0,0,1.4,0.6,0.15,concrete);box(0,0.15,0,1.35,0.35,0.65,concrete)
            for x: Float in [-0.45,0,0.45] { box(x,0.52,0.18,0.2,0.02,0.15,Self.detailAccent) }
        case .wheelStop:
            box(0,0,0,0.20,1.6,0.16,ink)
            for z: Float in [-0.5,0.5] { box(0,0.16,z,0.20,0.28,0.025,Self.detailAccent);cylinder(0,0.185,z,radius:0.025,height:0.01,color:steel,sides:6) }
        case .hydrant:
            cylinder(0,0,0,radius:0.16,height:0.06,color:steel);cylinder(0,0.06,0,radius:0.10,height:0.65,color:Self.detailRed)
            cylinder(0,0.71,0,radius:0.13,height:0.10,color:Self.detailRed)
            detailTube(Map3DPoint(0,0.50,-0.23),Map3DPoint(0,0.50,0.23),0.075,Self.detailRed)
            for z: Float in [-0.24,0.24] { detailTube(Map3DPoint(0,0.50,z-0.025),Map3DPoint(0,0.50,z+0.025),0.09,steel,sides:6) }
            cylinder(0,0.81,0,radius:0.03,height:0.05,color:steel,sides:6)
        case .drainOutlet:
            detailPlate(0,0,width:0.65,height:0.55)
            detailTube(Map3DPoint(0.04,0.23,0),Map3DPoint(0.28,0.23,0),0.18,concrete)
            detailTube(Map3DPoint(0.28,0.23,0),Map3DPoint(0.30,0.23,0),0.135,ink)
            for z: Float in [-0.08,0,0.08] { box(0.315,0.10,z,0.02,0.02,0.26,steel) }
        case .treeGrate:
            for z: Float in [-0.64,0.64] { box(0,0,z,1.4,0.12,0.04,steel) }
            for x: Float in [-0.64,0.64] { box(x,0,0,0.12,1.4,0.04,steel) }
            for x: Float in [-0.5,-0.4,0.4,0.5] { box(x,0,0,0.035,1.2,0.04,steel) }
            for z: Float in [-0.5,-0.4,0.4,0.5] { box(0,0,z,1.2,0.035,0.04,steel) }
            for z: Float in [-0.32,0.32] { box(0,0,z,0.65,0.04,0.04,steel) }
        case .parkingMeter:
            cylinder(0,0,0,radius:0.16,height:0.05,color:steel);cylinder(0,0.05,0,radius:0.04,height:1.1,color:steel)
            box(0,1.1,0,0.20,0.26,0.40,Map3DPalette.canopy);box(0.108,1.28,0,0.02,0.18,0.14,Self.glass)
            box(0.11,1.17,0,0.025,0.12,0.025,ink)
        case .temporaryFence:
            for z: Float in [-1,1] { box(0,0,z,0.6,0.18,0.08,concrete);box(0,0.08,z,0.06,0.06,1.9,steel) }
            for y: Float in [0.15,1.92] { box(0,y,0,0.06,2,0.06,steel) }
            for i in 0..<11 { box(0,0.18,-0.9+Float(i)*0.18,0.025,0.025,1.7,steel) }
            for y: Float in [0.6,1.2] { box(0,y,0,0.025,2,0.025,steel) }
        default: break
        }
    }
    mutating func detailFrustum(_ p: Map3DPoint,_ bottom: Float,_ top: Float,_ height: Float,_ color: UInt32) {
        let n=16
        func ring(_ r: Float,_ y: Float) -> [Map3DPoint] { (0..<n).map { i in let a=Float(i)*2*Float.pi/Float(n);return p+Map3DPoint(cosf(a)*r,y,sinf(a)*r) } }
        let a=ring(bottom,0),b=ring(top,height),inside=p+Map3DPoint(0,height/2,0)
        face(a,inside:inside,color:color);face(b,inside:inside,color:color)
        for i in 0..<n { let j=(i+1)%n;face([a[i],a[j],b[j],b[i]],inside:inside,color:color) }
    }
}
