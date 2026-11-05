import Foundation

/// On-demand geometry for studies. Native x forward, y left, z up; metres.
/// These models are not registered in the game scene or used for operations.
public enum Map3DAircraftStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case commuter19, regional70, narrowJet, wideJet
    }
    public struct Dimensions: Sendable {
        public let length: Float
        public let wingspan: Float
        public let height: Float
    }
    public struct Joint: Sendable {
        public let part: String
        public let pivot: Map3DPoint
        public let axis: Map3DPoint
        public let lower: Float
        public let upper: Float
    }
    public struct Metadata: Sendable {
        public let dimensions: Dimensions
        public let door: Map3DPoint
        public let joints: [Joint]
        public let glowParts: [String]
    }
    public static func metadata(_ kind: Kind) -> Metadata {
        let d=dimensions(kind)
        let radius:Float = switch kind { case .commuter19: 1.20; case .regional70: 1.45; case .narrowJet: 1.98; case .wideJet: 2.98 }
        let wingHeight:Float = switch kind { case .commuter19: 2.944; case .regional70: 3.544; case .narrowJet: 2.5474; case .wideJet: 3.5274 }
        let doorHeight: Float = switch kind { case .commuter19: 1.8; case .regional70: 3.2; case .narrowJet: 4.3; case .wideJet: 5.9 }
        let props: [Joint] = (kind == .commuter19 || kind == .regional70) ? [-1,1].map { side in
            Joint(part:"propeller-\(side)",pivot:Map3DPoint(0,Float(side) * (radius+d.wingspan*0.12),wingHeight),axis:Map3DPoint(1,0,0),lower:0,upper:2 * .pi)
        } : []
        return Metadata(dimensions:d,door:Map3DPoint(d.length * 0.35,radius,doorHeight),
            joints:props + [Joint(part:"landing-gear",pivot:Map3DPoint(0,0,1),axis:Map3DPoint(0,1,0),lower:0,upper:kind == .commuter19 ? 0 : 1.2),
                            Joint(part:"door",pivot:Map3DPoint(d.length * 0.35,radius,doorHeight),axis:Map3DPoint(0,0,1),lower:0,upper:1.57)],
            glowParts:["left-red","right-green","tail-white","anti-collision-red","strobe-white","cabin-windows"])
    }
    public static func dimensions(_ kind: Kind) -> Dimensions {
        switch kind {
        case .commuter19: Dimensions(length:16.56,wingspan:16.97,height:4.86)
        case .regional70: Dimensions(length:27.17,wingspan:27.05,height:7.65)
        case .narrowJet: Dimensions(length:44.51,wingspan:35.80,height:11.76)
        case .wideJet: Dimensions(length:66.80,wingspan:64.75,height:17.05)
        }
    }
    public static func model(_ kind: Kind, far: Bool = false, palette: Int = 0) -> Map3DModelPack.Model {
        let d=dimensions(kind), dark=Map3DPalette.playerRim
        let paint=[Map3DPalette.counters[1],Map3DPalette.gymGreen,Map3DPalette.shopAwnings[1]][max(0,min(2,palette))]
        let white=Map3DPalette.tileWhite, steel=Map3DPalette.tankStand, glass=Map3DPalette.glazing
        let r:Float = switch kind { case .commuter19: 1.20; case .regional70: 1.45; case .narrowJet: 1.98; case .wideJet: 2.98 }
        let floor:Float = switch kind { case .commuter19: 0.88; case .regional70: 1.05; case .narrowJet: 1.30; case .wideJet: 1.65 }
        let belly=floor+r, high=(kind == .commuter19 || kind == .regional70)
        let wingHeight=belly+(high ? r*0.72 : -r*0.37)
        var b=StationKitBuilder()
        b.box(0,belly-r,0,d.length,r*1.7,r*1.7,white)
        if !far {
            b.box(0,belly-r*0.20,0,d.length*0.75,r*1.72,0.16,paint)
            let windows=max(4,Int(d.length/2.2))
            for i in 0..<windows {
                let x = -d.length*0.27+(Float(i)+0.5)*d.length*0.66/Float(windows)
                for side:Float in [-1,1] { b.box(x,belly+r*0.20,side*r*0.86,0.35,0.04,0.27,glass) }
            }
            b.box(d.length*0.35,metadata(kind).door.z-0.65,r*0.85,0.8,0.04,1.3,steel)
        }
        for side:Float in [-1,1] {
            b.box(0,wingHeight,side*(d.wingspan*0.25),d.length*0.22,d.wingspan*0.5,0.18,paint)
            b.box(-d.length*0.38,kind == .regional70 ? d.height-0.2 : belly+r*0.68,side*d.wingspan*0.085,d.length*0.12,d.wingspan*0.17,0.14,paint)
            let ex:Float = kind == .commuter19 || kind == .regional70 ? 0 : -d.length*0.04
            b.box(ex,high ? wingHeight-r*0.35 : max(floor+r*0.25,wingHeight-r*0.3),side*d.wingspan*0.18,d.length*0.08,r*0.55,r*0.40,steel)
            if high { b.box(ex+d.length*0.045,wingHeight-r*0.75,side*d.wingspan*0.18,0.09,r*1.6,0.10,dark) }
            if !far { b.box(0,wingHeight,side*(d.wingspan*0.5-0.12),0.22,0.15,0.22,side>0 ? Map3DPalette.shopAwnings[1] : Map3DPalette.gymGreen) }
        }
        b.box(-d.length*0.39,belly,0,d.length*0.13,0.24,d.height-belly,paint)
        for (x,side) in [(d.length*0.18,Float(0)),(-d.length*0.10,d.wingspan*0.11),(-d.length*0.10,-d.wingspan*0.11)] {
            b.box(x,0,side,0.38,0.30,floor,dark)
        }
        return .flat(named:"aircraft-\(kind.rawValue)-\(far ? "far" : "near")",from:b.mesh)
    }
}
