import Foundation

extension StationKitBuilder {
    mutating func recreationVenue(_ p: Map3DRecreationKit.Part) {
        let length: Float,width: Float,height: Float
        switch p {
        case .fitnessStudio: (length,width,height)=(10,12,3.5)
        case .multipurposeHall: (length,width,height)=(14,18,5)
        case .bowlingLounge: (length,width,height)=(16,10,3.6)
        case .swimPavilion: (length,width,height)=(18,14,5)
        case .climbingHall: (length,width,height)=(12,10,9)
        case .dojo: (length,width,height)=(12,12,3.4)
        default: return
        }
        box(0,0,0,length+1,width+1,0.16,Map3DPalette.forecourt)
        box(-length/2,0.16,0,0.25,width,height,Self.white)
        for sign: Float in [-1,1] {
            box(0,0.16,sign*width/2,length,0.25,height,Self.white)
            box(length/2-0.12,0.16,sign*(width/2-0.12),0.25,0.25,height,Self.recreationGold)
            // Side glazing overlaps an actual opaque wall; no floating strips.
            for x: Float in [-length*0.30,0,length*0.30] {
                box(x,1.25,sign*(width/2+0.12),length*0.20,0.04,1.25,Self.glass)
            }
        }
        for z: Float in [-width*0.28,0,width*0.28] { pane(-length/2+0.13,1.0,z,width*0.19,1.2) }
        box(length/2-0.12,height,0,0.30,width,0.22,Self.recreationGold)
        let roofY=height+0.16
        switch p {
        case .fitnessStudio:
            let a=[Map3DPoint(-5.3,roofY,-6.3),Map3DPoint(5.3,roofY,-6.3),Map3DPoint(5.3,roofY+0.2,-6.3),Map3DPoint(-5.3,roofY+1.1,-6.3)]
            recreationPrism(a,a.map { $0+Map3DPoint(0,0,12.6) },Self.recreationRoof)
        case .multipurposeHall: gable(0,roofY,0,length+0.2,width+0.2,3.2,Self.recreationRoof)
        case .bowlingLounge:
            box(-2,roofY,0,12.5,10.6,0.6,Self.recreationRoof)
            box(6,roofY,0,4.6,10.6,0.22,Self.recreationGold)
        case .swimPavilion:
            var a=[Map3DPoint(-9.3,roofY,-7.3),Map3DPoint(-9.3,roofY,7.3)]
            for i in 0...10 { let t=Float(i)*Float.pi/10;a.append(.init(-9.3,roofY+0.15+sinf(t)*2.2,cosf(t)*7.3)) }
            recreationPrism(a,a.map { $0+Map3DPoint(18.6,0,0) },Self.recreationRoof)
        case .climbingHall:
            let a=[Map3DPoint(-6.3,roofY,-5.3),Map3DPoint(6.3,roofY,-5.3),Map3DPoint(6.3,roofY+1.5,-5.3),Map3DPoint(-6.3,roofY+0.22,-5.3)]
            recreationPrism(a,a.map { $0+Map3DPoint(0,0,10.6) },Self.recreationRoof)
            for z: Float in [-3,0,3] { box(-5.82,3.8,z,0.14,0.18,4.7,Self.recreationGold) }
        case .dojo:
            hip(0,roofY,0,length+0.2,width+0.2,1.8,Self.recreationRoof)
            box(0,0.16,0,8,8,0.025,Self.recreationGreen)
            for z: Float in [-4,-2,0,2,4] { box(0,0.185,z,8,0.025,0.008,Self.white) }
        default: break
        }
    }
}
