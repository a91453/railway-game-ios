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
        let doorHeight: Float = switch kind { case .commuter19: 1.7; case .regional70: 2.9; case .narrowJet: 4.3; case .wideJet: 5.9 }
        return Metadata(dimensions:d,door:Map3DPoint(d.length * 0.35,0,doorHeight),
            joints:[Joint(part:"propeller",pivot:Map3DPoint(0,0,0),axis:Map3DPoint(1,0,0),lower:0,upper:2 * .pi),
                    Joint(part:"landing-gear",pivot:Map3DPoint(0,0,1),axis:Map3DPoint(0,1,0),lower:0,upper:kind == .commuter19 ? 0 : 1.2),
                    Joint(part:"door",pivot:Map3DPoint(d.length * 0.35,0,doorHeight),axis:Map3DPoint(0,0,1),lower:0,upper:1.57)],
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
        let r:Float = switch kind { case .commuter19: 2.15; case .regional70: 2.8; case .narrowJet: 3.95; case .wideJet: 5.95 }
        let floor:Float = switch kind { case .commuter19: 0.88; case .regional70: 1.05; case .narrowJet: 1.30; case .wideJet: 1.65 }
        let belly=floor+r, high=(kind == .commuter19 || kind == .regional70)
        let wingHeight=belly+(high ? r*0.72 : -r*0.37)
        var b=StationKitBuilder()
        b.box(0,belly-r,0,d.length,r*1.7,r*1.7,white)
        if !far {
            b.box(0,belly-r*.20,0,d.length*.75,r*1.72,.16,paint)
            let windows=max(4,Int(d.length/2.2))
            for i in 0..<windows {
                let x = -d.length*.27+(Float(i)+0.5)*d.length*.66/Float(windows)
                for side:Float in [-1,1] { b.box(x,belly+r*.20,side*r*.86,.35,.04,.27,glass) }
            }
            b.box(d.length*.35,belly-r*.25,r*.85,.8,.04,r*.95,steel)
        }
        for side:Float in [-1,1] {
            b.box(0,wingHeight,side*(d.wingspan*.25),d.length*.22,d.wingspan*.5,.18,paint)
            b.box(-d.length*.38,kind == .regional70 ? d.height-.2 : belly+r*.68,side*d.wingspan*.085,d.length*.12,d.wingspan*.17,.14,paint)
            let ex:Float = kind == .commuter19 || kind == .regional70 ? 0 : -d.length*.04
            b.box(ex,high ? wingHeight-r*.35 : max(floor+r*.25,wingHeight-r*.3),side*d.wingspan*.18,d.length*.08,r*.55,r*.40,steel)
            if high { b.box(ex+d.length*.045,wingHeight-r*.75,side*d.wingspan*.18,.09,r*1.6,.10,dark) }
            if !far { b.box(0,wingHeight,side*(d.wingspan*.5-.12),.22,.15,.22,side>0 ? Map3DPalette.shopAwnings[1] : Map3DPalette.gymGreen) }
        }
        b.box(-d.length*.39,belly,0,d.length*.13,.24,d.height-belly,paint)
        for (x,side) in [(d.length*.18,Float(0)),(-d.length*.10,d.wingspan*.11),(-d.length*.10,-d.wingspan*.11)] {
            b.box(x,0,side,.38,.30,floor,dark)
        }
        return .flat(named:"aircraft-\(kind.rawValue)-\(far ? "far" : "near")",from:b.mesh)
    }
}
