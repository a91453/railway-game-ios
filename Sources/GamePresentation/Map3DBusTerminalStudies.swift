import Foundation

/// On-demand, non-operational studies. Native coordinates: x forward, y left, z up, metres.
public enum Map3DBusTerminalStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case large, medium, expressStop, canopy8, sawtoothIsland, seatGroup
        case ticketCounter, ticketMachine, departureBoard, luggageCart
        case stopSign, shelter, footbridge, liftTower, largeThreeCoaches
    }
    public struct Parking: Sendable {
        public let id: String
        public let front: Map3DPoint
        public let heading: Map3DPoint
        public let usableLength: Float
        public let clearWidth: Float
    }
    public struct Road: Sendable {
        public let position: Map3DPoint
        public let heading: Map3DPoint
    }
    public struct Connections: Sendable {
        public let parking: [Parking]
        public let entry: Road?
        public let exit: Road?
    }
    public static func connections(for kind: Kind) -> Connections {
        let count: Int
        switch kind { case .large, .largeThreeCoaches: count=8; case .medium: count=5; case .expressStop: count=1; default: count=0 }
        if kind == .expressStop {
            return Connections(parking:[Parking(id:"shoulder-01",front:Map3DPoint(10,0,0.08),heading:Map3DPoint(1,0,0),usableLength:15,clearWidth:3.6)],entry:Road(position:Map3DPoint(-19,0,0),heading:Map3DPoint(1,0,0)),exit:Road(position:Map3DPoint(19,0,0),heading:Map3DPoint(1,0,0)))
        }
        guard count > 0 else { return Connections(parking:[],entry:nil,exit:nil) }
        let angle: Float = 22 * .pi / 180
        let first = -Float(count-1)*4.8/2
        let parking=(0..<count).map { i in
            Parking(id:String(format:"bay-%02d",i+1),front:Map3DPoint(11.12,first+Float(i)*4.8+2.23,0.08),heading:Map3DPoint(cosf(angle),sinf(angle),0),usableLength:15,clearWidth:3.6)
        }
        return Connections(parking:parking,entry:Road(position:Map3DPoint(-38,-Float(count)*2.4-5,0),heading:Map3DPoint(1,0,0)),exit:Road(position:Map3DPoint(-38,Float(count)*2.4+5,0),heading:Map3DPoint(-1,0,0)))
    }
    public static func model(_ kind: Kind, far: Bool = false) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        let white=Map3DPalette.tileWhite, blue=Map3DPalette.counters[1], steel=Map3DPalette.tankStand
        let dark=Map3DPalette.playerRim, glass=Map3DPalette.glazing, deck=Map3DPalette.plaza
        func box(_ x:Float,_ y:Float,_ z:Float,_ l:Float,_ w:Float,_ h:Float,_ c:UInt32) { b.box(x,y,z,l,w,h,c) }
        switch kind {
        case .canopy8:
            box(0,3.35,0,8,4.2,0.22,blue)
            for x:Float in [-3.55,3.55] { for z:Float in [-1.75,1.75] { box(x,0,z,0.16,0.16,3.35,steel) } }
            if !far { box(0,3.29,0,6,0.12,0.035,white) }
        case .sawtoothIsland:
            box(0,0,0,16,4.3,0.24,deck);box(0,0,2.13,16,0.12,0.37,white)
        case .seatGroup:
            for z:Float in [-0.7,0.7] { for x:Float in [-0.55,0.55] { box(x,0,z,0.10,0.10,0.46,steel) };box(0,0.46,z,1.6,0.48,0.10,blue);if !far { box(0,0.55,z+0.23,1.6,0.10,0.48,blue) } }
        case .ticketCounter:
            box(0,0,0,3.2,0.85,1.05,white);box(0,1.05,0,3.25,0.95,0.08,dark)
        case .ticketMachine:
            box(0,0,0,0.75,0.56,1.76,white);box(0,1.12,0.292,0.48,0.025,0.4,dark)
        case .departureBoard:
            box(0,0,0,4,0.16,1.45,dark);if !far { for x:Float in [-1.3,0,1.3] { box(x,0.65,0.087,0.75,0.015,0.08,white) } }
        case .luggageCart:
            box(0,0.3,0,1.5,0.75,0.16,steel);for x:Float in [-0.55,0.55] { for z:Float in [-0.3,0.3] { box(x,0,z,0.18,0.10,0.30,dark) } };box(-0.8,0.4,0,0.08,0.78,0.75,steel)
        case .stopSign:
            box(0,0,0,0.12,0.12,3,steel);box(0,2.45,0,0.9,0.15,0.55,blue)
        case .shelter:
            box(0,2.65,0,5,2.4,0.18,blue);for x:Float in [-2.25,2.25] { box(x,0,-0.95,0.13,0.13,2.65,steel) };box(0,0,-1.1,4.7,0.10,2.35,glass)
        case .footbridge:
            box(0,5.5,0,8,2.5,0.25,deck);for z:Float in [-1.2,1.2] { box(0,5.75,z,8,0.09,1.1,steel) }
        case .liftTower:
            box(0,0,0,3,3,5.75,white);box(0,5.75,0,3.4,3.4,0.15,blue)
        case .large, .medium, .largeThreeCoaches:
            let n=kind == .medium ? 5 : 8, first = -Float(kind == .medium ? 4 : 7)*2.4
            box(0,0,0,kind == .medium ? 64 : 82,kind == .medium ? 48 : 64,0.08,deck)
            box(-16,0.08,0,20,Float(n)*4.8+10,0.03,steel)
            for i in 0..<n {
                let z=first+Float(i)*4.8
                box(5,0.08,z,16,4.3,0.24,deck)
                if i%2 == 0 { box(3,3.67,z+2.1,8,4.2,0.22,blue);for x:Float in [-0.55,6.55] { for side:Float in [-1.75,1.75] { box(x,0.32,z+2.1+side,0.16,0.16,3.35,steel) } } }
                if !far { box(1,0.32,z+1.7,1.6,0.48,0.55,blue) }
            }
            box(22,0.08,0,15,Float(n)*4.8+9,4.4,white);box(14.48,0.45,0,0.05,Float(n)*4.8+7,3.5,glass)
            box(22,4.48,0,16,Float(n)*4.8+10,0.32,blue);box(14.42,3.75,0,0.08,12,0.45,dark)
            for i in 0..<3 { box(26,0.08,first+Float(i)*4,3.2,0.85,1.05,white);box(18,0.08,first+Float(i)*2.5,0.75,0.56,1.76,white) }
            box(-31,0.08,-Float(n)*2.4-5,14,4,0.03,dark);box(-31,0.08,Float(n)*2.4+5,14,4,0.03,dark)
            box(31,0.08,Float(n)*2.4+5,12,4,0.03,blue);box(31,0.08,-Float(n)*2.4-5,12,4,0.03,blue)
            if kind == .largeThreeCoaches { for i in [0,3,6] { box(3,0.08,first+Float(i)*4.8,13.19,2.5,3.76,white) } }
        case .expressStop:
            box(0,0,0,38,15,0.08,steel);box(7,0.08,-3,13,5,0.17,deck)
            box(6,2.9,-4,5,2.4,0.18,blue);for x:Float in [3.75,8.25] { box(x,0.25,-4.95,0.13,0.13,2.65,steel) }
            box(12,0.25,-3,0.12,0.12,3,steel);box(-2,5.5,-3,8,2.5,0.25,deck);box(-7,0.08,-3,3,3,5.75,white)
            for i in 0..<14 { box(-15+Float(i)*0.55,0.08,-3,0.55,2.4,Float(i+1)*0.39,deck) }
        }
        return .flat(named:"bus-terminal-\(kind.rawValue)\(far ? "-far" : "-near")",from:b.mesh)
    }
}
