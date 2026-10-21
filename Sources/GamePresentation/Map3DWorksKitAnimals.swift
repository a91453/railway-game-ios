import Foundation

extension StationKitBuilder {
    mutating func worksAnimal(_ part: Map3DWorksKit.Part) {
        let white=Self.white,ink=Self.ink,wood=Self.worksWood,steel=Self.steel
        switch part {
        case .stationCat:
            let fur=Map3DPalette.playerRoof
            worksBlob(Map3DPoint(-0.04,0.27,0),Map3DPoint(0.29,0.13,0.12),fur)
            for x: Float in [-0.2,0.15] { for z: Float in [-0.08,0.08] {
                box(x,0,z,0.07,0.065,0.04,fur);beam(Map3DPoint(x,0.035,z),Map3DPoint(x-0.025,0.25,z),0.045,fur)
            } }
            let head=Map3DPoint(0.23,0.39,0),r=Map3DPoint(0.12,0.12,0.115)
            worksBlob(head,r,fur);worksEyes(head,r,eye:0.014)
            for z: Float in [-0.073,0.073] { worksPrism([(0.15,0.45),(0.27,0.45),(0.20,0.60)],z:z,width:0.055,color:fur) }
            worksBlob(Map3DPoint(0.35,0.36,0),Map3DPoint(0.035,0.022,0.035),wood)
            worksTail([Map3DPoint(-0.28,0.30,0),Map3DPoint(-0.44,0.43,0),Map3DPoint(-0.47,0.63,0),Map3DPoint(-0.40,0.69,0)],thickness:0.045,color:fur)
        case .curledCat:
            let fur=Map3DPalette.counters[1]
            worksBlob(Map3DPoint(0,0.13,0),Map3DPoint(0.26,0.13,0.22),fur)
            worksBlob(Map3DPoint(0.16,0.17,0.07),Map3DPoint(0.12,0.10,0.12),fur)
            for z: Float in [0,0.14] { worksPrism([(0.10,0.22),(0.23,0.22),(0.19,0.34)],z:z,width:0.05,color:fur) }
            for z: Float in [0.01,0.12] { beam(Map3DPoint(0.26,0.18,z-0.025),Map3DPoint(0.27,0.18,z+0.025),0.008,ink) }
            worksTail([Map3DPoint(-0.17,0.12,-0.12),Map3DPoint(-0.08,0.08,-0.23),Map3DPoint(0.14,0.08,-0.20),Map3DPoint(0.26,0.10,-0.05)],thickness:0.065,color:fur)
        case .waterBuffalo,.dairyCow,.sheep:
            let sheep=part == .sheep,buffalo=part == .waterBuffalo,scale: Float=sheep ? 0.62 : 1
            let fur=buffalo ? steel : sheep ? Map3DPalette.playerRoof : white
            worksBlob(Map3DPoint(0,0.91*scale,0),Map3DPoint(0.86*scale,0.40*scale,0.35*scale),fur,patches:part == .dairyCow)
            for x: Float in [-0.52,0.50] { for z: Float in [-0.23,0.23] {
                box(x*scale,0,z*scale,0.14*scale,0.14*scale,0.10*scale,ink)
                beam(Map3DPoint(x*scale,0.08*scale,z*scale),Map3DPoint(x*scale,0.75*scale,z*scale),0.11*scale,fur)
            } }
            let head=Map3DPoint(0.83*scale,1.08*scale,0),r=Map3DPoint(0.31*scale,0.28*scale,0.23*scale)
            worksBlob(head,r,buffalo ? steel : sheep ? wood : white)
            worksBlob(Map3DPoint(1.07*scale,0.94*scale,0),Map3DPoint(0.17*scale,0.12*scale,0.20*scale),buffalo ? ink : Map3DPalette.counters[0])
            worksEyes(head,r,eye:0.025*scale)
            for sign: Float in [-1,1] {
                worksBlob(head+Map3DPoint(-0.08,0.05,sign*0.26)*scale,Map3DPoint(0.15,0.045,0.11)*scale,fur)
                if buffalo { worksTail([head+Map3DPoint(-0.1,0.19,sign*0.17),head+Map3DPoint(-0.35,0.31,sign*0.5),head+Map3DPoint(-0.30,0.52,sign*0.64)],thickness:0.07,color:ink) }
                else if !sheep { worksTail([head+Map3DPoint(-0.02,0.19,sign*0.13),head+Map3DPoint(0.05,0.36,sign*0.20)],thickness:0.055,color:Map3DPalette.playerRoof) }
            }
            worksTail([Map3DPoint(-0.77*scale,1.0*scale,0),Map3DPoint(-0.96*scale,0.68*scale,0.04),Map3DPoint(-0.98*scale,0.4*scale,0.10)],thickness:0.045*scale,color:fur)
            if sheep { for x: Float in [-0.4,0,0.4] { for z: Float in [-0.22,0.22] { worksBlob(Map3DPoint(x,0.65,z),Map3DPoint(0.19,0.17,0.14),fur,sides:8,rings:4) } } }
        case .hen,.rooster,.duck,.egret,.sparrow:
            worksBird(part)
        case .koi:
            worksBlob(Map3DPoint(0,0.13,0),Map3DPoint(0.43,0.12,0.12),white,patches:true)
            worksBlob(Map3DPoint(0.19,0.15,0.04),Map3DPoint(0.16,0.09,0.09),Map3DPalette.templeRidge)
            worksPrism([(-0.35,0.13),(-0.63,0.03),(-0.60,0.24)],z:0,width:0.07,color:Map3DPalette.templeRidge)
            worksBlob(Map3DPoint(0.34,0.13,0),Map3DPoint(0.11,0.08,0.11),white)
            worksEyes(Map3DPoint(0.34,0.13,0),Map3DPoint(0.11,0.08,0.11),eye:0.012)
            for z: Float in [-0.12,0.12] { worksLeaf(Map3DPoint(0.05,0.12,z),Map3DPoint(-0.12,0.09,z*2.2),width:0.08,color:Map3DPalette.templeRidge) }
        case .turtle:
            worksBlob(Map3DPoint(0,0.15,0),Map3DPoint(0.28,0.14,0.21),Self.worksGreen,sides:10,rings:6)
            worksBlob(Map3DPoint(0.31,0.12,0),Map3DPoint(0.12,0.08,0.08),Map3DPalette.embankment)
            worksEyes(Map3DPoint(0.31,0.12,0),Map3DPoint(0.12,0.08,0.08),eye:0.012)
            for x: Float in [-0.16,0.16] { for z: Float in [-0.17,0.17] { worksBlob(Map3DPoint(x,0.04,z),Map3DPoint(0.10,0.04,0.08),Map3DPalette.embankment,sides:8,rings:4) } }
            worksTail([Map3DPoint(-0.22,0.08,0),Map3DPoint(-0.37,0.04,0)],thickness:0.035,color:Map3DPalette.embankment)
            for x: Float in [-0.1,0.05] { box(x,0.276,0,0.012,0.17,0.012,Self.ink) }
        default: break
        }
    }
    mutating func worksBird(_ part: Map3DWorksKit.Part) {
        let tall=part == .egret,small=part == .sparrow,duck=part == .duck,rooster=part == .rooster
        let scale: Float=small ? 0.43 : 1,leg: Float=tall ? 0.45 : 0.12
        let fur=tall || duck ? Self.white : rooster ? Map3DPalette.counters[1] : Map3DPalette.counters[0]
        for z: Float in [-0.07,0.07] {
            box(0.02,0,z*scale,0.15*scale,0.055*scale,0.025*scale,Self.worksYellow)
            worksTube(Map3DPoint(0,0.02*scale,z*scale),Map3DPoint(-0.02,(leg+0.08)*scale,z*scale),0.015*scale,Self.worksYellow,sides:6)
        }
        worksBlob(Map3DPoint(-0.05*scale,(leg+0.20)*scale,0),Map3DPoint(duck ? 0.30*scale : 0.22*scale,0.19*scale,0.15*scale),fur)
        let head=Map3DPoint(0.18*scale,(leg+(tall ? 0.65 : 0.42))*scale,0),r=Map3DPoint(0.10*scale,0.11*scale,0.10*scale)
        if tall { worksTail([Map3DPoint(0.04,leg+0.25,0),Map3DPoint(0.16,leg+0.40,0),head],thickness:0.055,color:fur) }
        worksBlob(head,r,small ? Self.worksWood : fur);worksEyes(head,r,eye:0.012*scale)
        if small {
            for z: Float in [-0.07,0.07] { worksBlob(head+Map3DPoint(0,-0.025*scale,z*scale),Map3DPoint(0.055,0.035,0.025)*scale,Self.white,sides:8,rings:4) }
            worksBlob(head+Map3DPoint(0.06*scale,-0.07*scale,0),Map3DPoint(0.04,0.035,0.055)*scale,Self.ink,sides:8,rings:4)
        }
        worksPrism([(head.x+0.08*scale,head.y-0.02*scale),(head.x+(tall ? 0.35 : duck ? 0.23 : 0.17)*scale,head.y-0.04*scale),(head.x+0.08*scale,head.y+0.025*scale)],z:0,width:duck ? 0.11 : 0.045*scale,color:Self.worksYellow)
        for z: Float in [-0.14,0.14] { worksBlob(Map3DPoint(-0.05*scale,(leg+0.23)*scale,z*scale),Map3DPoint(0.16,0.09,0.035)*scale,duck ? Map3DPalette.canopy : Map3DColor.shaded(fur,0.8)) }
        if part == .hen || rooster {
            for x: Float in [0.12,0.19,0.25] { worksBlob(Map3DPoint(x,(leg+0.53)*scale,0),Map3DPoint(0.035,0.055,0.025)*scale,Map3DPalette.templeRidge,sides:6,rings:4) }
        }
        if rooster {
            for (i,z) in [Float(-0.07),0,0.07].enumerated() {
                worksTail([Map3DPoint(-0.18,leg+0.22,z),Map3DPoint(-0.33,leg+0.43,z),Map3DPoint(-0.49,leg+0.40,z),Map3DPoint(-0.58,leg+0.22,z)],thickness:0.07,color:i==1 ? Self.ink : Self.worksGreen)
            }
        } else {
            for z: Float in [-0.06,0.06] { worksPrism([(-0.18*scale,(leg+0.14)*scale),(-0.41*scale,(leg+0.33)*scale),(-0.19*scale,(leg+0.30)*scale)],z:z*scale,width:0.04*scale,color:fur) }
        }
    }
    mutating func worksEyes(_ p: Map3DPoint,_ radii: Map3DPoint,eye: Float) {
        for sign: Float in [-1,1] {
            // Eye centres follow the head ellipsoid; half the bead embeds.
            let x=p.x+radii.x*sqrtf(1-0.60*0.60-0.10*0.10)
            worksBlob(Map3DPoint(x,p.y+radii.y*0.10,p.z+sign*radii.z*0.60),Map3DPoint(eye,eye,eye),Self.ink,sides:8,rings:4)
        }
    }
    mutating func worksTail(_ points: [Map3DPoint],thickness: Float,color: UInt32) {
        for i in 1..<points.count { worksTube(points[i-1],points[i],thickness/2,color,sides:8) }
        for p in points.dropFirst().dropLast() { worksBlob(p,Map3DPoint(thickness/2,thickness/2,thickness/2),color,sides:8,rings:4) }
    }
}
