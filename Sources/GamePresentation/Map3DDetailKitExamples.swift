import Foundation

extension Map3DDetailKit {
    public enum Example: String, CaseIterable, Sendable {
        case railService, apartmentFacade, platformSafety, streetCorner, marketAlley, workshop
        public var id: String { "detail-example-"+rawValue }
        public var name: String { switch self {
        case .railService: "軌道維修與轉轍設備"
        case .apartmentFacade: "住宅鐵窗與貼牆管線"
        case .platformSafety: "車站安全設備與排隊區"
        case .streetCorner: "街角排水與道路設施"
        case .marketAlley: "市場店面與生活道具"
        case .workshop: "可動門片與維修工坊"
        } }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        b.box(0,0,0,10,12,0.12,Map3DPalette.plaza)
        func add(_ part: Part,_ x: Float,_ y: Float,_ z: Float,_ pose: Float = 0) {
            b.add(model(for:part,pose:pose),at:Map3DPoint(x,y,z))
        }
        func wall() { b.box(-2.1,0.12,0,0.2,9,3.4,Map3DPalette.concreteWalls[0]) }
        switch example {
        case .railService:
            // Exact 1.067 m wheel-centre gauge is only a modelling convention;
            // no rail-authoritative geometry is changed by this example.
            b.track(-4.5,4.5,0,at:0.12)
            for x: Float in [-3,-1,1,3] {
                for z: Float in [-0.5335,0.5335] { add(.railFastener,x,0.40,z) }
            }
            add(.pointMotor,0,0.12,2);add(.turnoutLinkage,0,0.12,0.95)
            add(.tensionWeights,-3,0.12,-3)
            for x: Float in [-3,-1,1,3] { add(.cableTrough,x,0.12,-1.8);add(.maintenanceWalkway,x,0.12,3.8) }
            add(.axleCounter,3,0.35,0.7)
        case .apartmentFacade:
            wall()
            for z: Float in [-2.7,0,2.7] { add(.grilleBay,-2,1.2,z) }
            add(.wallPipeStraight,-2,0.12,-4);add(.wallPipeElbow,-2,2.12,-4)
            add(.wallPipeTee,-2,0.12,3.8);add(.meterBank,-2,0.65,2.4)
            add(.wallTap,-2,0.4,1.6);add(.awningBrace,-2,2.65,-1.1);add(.awningBrace,-2,2.65,1.1)
            b.box(-1.5,3.45,0,1.0,2.5,0.08,Map3DPalette.roof)
            add(.plantRack,-0.9,0.12,-3);add(.dryingRack,2,0.12,2);add(.gasCage,2,0.12,-2)
        case .platformSafety:
            wall()
            add(.routeMapCase,-2,1.4,-2.5);add(.aedCabinet,-2,1.2,0);add(.fireCabinet,-2,0.7,1.3)
            add(.emergencyIntercom,-2,1.1,2.2);add(.cctvCamera,-2,2.6,3.2);add(.paSpeaker,-2,2.5,-3.7)
            for x: Float in [0,2] { add(.queueBelt,x,0.12,-1);add(.queueBelt,x,0.12,0.6) }
            add(.baggageTrolley,1,0.12,3.7);add(.cleaningCart,3,0.12,3.7)
        case .streetCorner:
            b.box(2,0.12,0,5,12,0.04,Map3DPalette.road(.minor))
            for z: Float in [-4,-2,0,2,4] { b.add(model(for:.curbStraight),at:Map3DPoint(-0.5,0.16,z),angle:.pi/2) }
            for z: Float in [-3,1,4] { add(.gutterGrate,-0.1,0.16,z) }
            add(.manholeCover,2,0.16,0);add(.convexMirror,-1.3,0.12,-4);add(.hydrant,-1.3,0.12,3.8)
            add(.roadBarrier,2,0.16,3.6);add(.trafficCone,1,0.16,2.4);add(.trafficCone,3,0.16,2.4)
            add(.parkingMeter,-1.4,0.12,1.5);add(.treeGrate,-2.7,0.12,-1.5)
            b.tree(-2.7,0.16,-1.5,size:0.6)
        case .marketAlley:
            wall();add(.shopShelf,-1.5,0.12,-2);add(.chestFreezer,-1.4,0.12,0);add(.shopCounter,-1.4,0.12,2.1)
            add(.produceDisplay,1.0,0.12,2.0);add(.parcelStack,2.8,0.12,-2.7);add(.handTruck,3.4,0.12,-0.9)
            add(.foldingChair,1.2,0.12,-0.6);add(.plasticStool,2,0.12,0.8);add(.riceSack,0.8,0.12,-3)
            add(.plantRack,-1.2,0.12,4);add(.stackingCrate,2.7,0.12,3.8)
        case .workshop:
            wall();add(.hingedDoor,-2,0.12,-3.3,.pi/3);add(.serviceWindow,-2,1.2,1.2,.pi/4)
            add(.ventFan,-2,1.8,3.2,.pi/6);add(.cabinetDoor,-2,0.3,-0.3,.pi/4)
            add(.lostPropertyShelf,-1.2,0.12,4.6);add(.wheelset,1.5,0.12,-2.6,.pi/3)
            add(.barrierArm,3.2,0.12,2.8,.pi/5);add(.handTruck,0,0.12,2.7)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
