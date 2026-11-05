import Foundation

/// Assembly grid is illustrative; it is not surveyed airport engineering data.
public enum Map3DAirportStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case cityTerminal, islandTerminal, runway, taxiway, apron
        case papi, windsock, fence, tug, baggageCart, boardingStairs, fuelTruck
    }
    public struct Stand: Sendable {
        public let id: String
        public let noseStop: Map3DPoint
        public let heading: Map3DPoint
        public let maxWingspan: Float
        public let aircraftClass: String
    }
    public struct Link: Sendable {
        public let position: Map3DPoint
        public let heading: Map3DPoint
        public let length: Float
    }
    public struct Jetbridge: Sendable {
        public let id: String
        public let pivot: Map3DPoint
        public let exit: Map3DPoint
        public let translationAxis: Map3DPoint
        public let extensionRange: ClosedRange<Float>
    }
    public struct Connections: Sendable {
        public let stands: [Stand]
        public let runwayEnds: [Link]
        public let taxiwayLinks: [Link]
        public let jetbridges: [Jetbridge]
    }
    public static func connections(_ kind: Kind) -> Connections {
        let stands: [Stand] = kind == .apron ? zip([-24,0,24] as [Float],[17,36,65] as [Float]).enumerated().map { i,p in
            Stand(id:"S\(i+1)",noseStop:Map3DPoint(9,p.0,0),heading:Map3DPoint(1,0,0),maxWingspan:p.1,aircraftClass:["A","C","D"][i])
        } : []
        let ends: [Link] = kind == .runway ? [-30,30].map { x in Link(position:Map3DPoint(Float(x),0,0),heading:Map3DPoint(x < 0 ? 1 : -1,0,0),length:60) } : []
        let taxi: [Link] = kind == .runway ? [Link(position:Map3DPoint(0,15,0),heading:Map3DPoint(0,1,0),length:30)] :
            (kind == .taxiway ? [-15,15].map { Link(position:Map3DPoint(Float($0),0,0),heading:Map3DPoint(1,0,0),length:30) } : [])
        let bridges: [Jetbridge] = kind == .cityTerminal ? [-17,-5,5,20].enumerated().map { i,y in
            Jetbridge(id:"J\(i+1)",pivot:Map3DPoint(45,Float(y),y < 0 ? 3.25 : 4.35),exit:Map3DPoint(63,Float(y),y < 0 ? 3.25 : 4.35),translationAxis:Map3DPoint(1,0,0),extensionRange:0...7)
        } : []
        return Connections(stands:stands,runwayEnds:ends,taxiwayLinks:taxi,jetbridges:bridges)
    }
    public static func model(_ kind: Kind, far: Bool = false) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        let white=Map3DPalette.tileWhite, blue=Map3DPalette.counters[1], steel=Map3DPalette.tankStand
        let dark=Map3DPalette.playerRim, glass=Map3DPalette.glazing, deck=Map3DPalette.plaza
        let yellow=Map3DPalette.shopAwnings[1]
        switch kind {
        case .cityTerminal, .islandTerminal:
            let city=kind == .cityTerminal
            let l:Float=city ? 90 : 25, w:Float=city ? 42 : 13, h:Float=city ? 11 : 4.5
            b.box(0,0,0,l,w,h,white)
            b.box(0,h,0,l+2,w+2,.25,blue)
            b.box(l*.5,0,0,.08,w*.8,h*.7,glass)
            b.box(l*.5+2.3,h*.60,0,5,w*.68,.19,blue)
            for z in [-w*.31,Float(0),w*.31] { b.box(l*.5+.11,.55,z,.08,.15,h*.55,white) }
            if city {
                b.box(-l*.21,h+.25,-w*.17,9,5,1.55,steel)
                b.box(-54,0,-27,7,7,26,steel)
                b.box(-54,26,-27,10,10,3,glass)
                b.box(-54,29,-27,10.5,10.5,.22,blue)
                b.box(-72,0,63,36,30,12,steel)
                b.box(-72,0,47.95,30,.09,9,blue)
                for y:Float in [-17,-5,5,20] {
                    let base:Float=y<0 ? 2 : 3.1
                    b.box(54,base,y,18,2.4,2.5,white)
                    b.box(61,0,y,.3,.3,base,steel)
                }
            } else {
                b.box(l*.5+.14,.55,-w*.26,.10,1.55,2.25,dark)
                b.box(l*.5+4,0,0,8,w*.86,.08,deck)
            }
        case .runway:
            b.box(0,0,0,60,30,.08,dark)
            for x:Float in [-28,28] {
                for y:Float in [-9,-3,3,9] { b.box(x,.085,y,2.4,1.3,.018,white) }
            }
            for x in stride(from:-24,through:24,by:8) { b.box(Float(x),.09,0,3,.28,.015,white) }
            if !far {
                for y:Float in [-13,13] { for x:Float in [-16,16] { b.box(x,.09,y,7,.36,.015,white) } }
                for x in stride(from:-28,through:28,by:7) { for y:Float in [-14.7,14.7] { b.box(Float(x),.09,y,.18,.18,.16,white) } }
            }
        case .taxiway:
            b.box(0,0,0,30,12,.08,steel);b.box(0,.09,0,30,.18,.015,yellow)
            if !far { for x:Float in [-13,0,13] { for y:Float in [-5.9,5.9] { b.box(x,.09,y,.17,.17,.15,blue) } } }
        case .apron:
            b.box(0,0,0,80,80,.08,deck)
            for y:Float in [-24,0,24] {
                b.box(0,.09,y,24,.18,.015,yellow)
                b.box(9,.09,y,.24,3,.015,yellow)
            }
        case .papi:
            for i in 0..<4 { b.box(0,0,Float(i)*0.7,.26,.26,.34,i<2 ? Map3DPalette.shopAwnings[1] : white) }
        case .windsock:
            b.box(0,0,0,.10,.10,5,steel);b.box(.8,4.6,0,1.6,.42,.42,yellow)
        case .fence:
            for x:Float in [-4,0,4] { b.box(x,0,0,.1,.1,2.5,steel) }
            for z:Float in [.55,1.30,2.05] { b.box(0,z,0,8,.055,.055,steel) }
            if !far { for i in -7...7 { b.box(Float(i)*.5,.3,0,.035,.04,2.1,steel) } }
        case .tug, .baggageCart, .boardingStairs, .fuelTruck:
            let l:Float = switch kind { case .tug:2.7; case .baggageCart:4.5; case .boardingStairs:5; default:6.8 }
            let w:Float = kind == .fuelTruck ? 2.3 : 1.5
            b.box(0,.38,0,l,w,.35,steel)
            for x in [-l*.33,l*.33] { for y in [-w*.4,w*.4] { b.box(x,0,y,.38,.2,.45,dark) } }
            switch kind {
            case .tug:
                b.box(-.65,.73,0,1.05,w*.9,.75,white)
                b.box(-.11,1.02,0,.04,w*.72,.32,glass)
                b.box(l*.55,.45,0,.62,.15,.13,dark)
            case .baggageCart:
                b.box(-1.55,.73,0,.95,w*.8,.85,white)
                for x:Float in [-.3,1.25] {
                    b.box(x,.73,0,1.3,w*.84,.22,blue)
                    if !far { for z:Float in [-.42,.42] { b.box(x,.95,z,.65,.38,.4,yellow) } }
                }
            case .boardingStairs:
                b.box(-1.65,.73,0,.95,w*.8,1.05,white)
                let steps=far ? 4 : 8
                for i in 0..<steps { b.box(-.9+Float(i)*2.9/Float(steps),.75+Float(i+1)*2.3/Float(steps),0,2.9/Float(steps)+.02,w*.66,.12,steel) }
                b.box(2,3.05,0,.75,w*.72,.15,blue)
            case .fuelTruck:
                b.box(2.35,.73,0,1.25,w*.85,1.28,white)
                b.box(-.9,.84,0,4.45,w*.7,1.68,white)
                if !far { b.box(-.3,.88,w*.48,1.05,.18,.62,blue) }
            default: break
            }
        }
        return .flat(named:"airport-\(kind.rawValue)-\(far ? "far" : "near")",from:b.mesh)
    }
}
