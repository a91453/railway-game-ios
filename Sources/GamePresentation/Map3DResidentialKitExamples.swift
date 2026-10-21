import Foundation

extension Map3DResidentialKit {
    public enum Example: String, CaseIterable, Sendable {
        case laneStreet, cornerBlock, ruralCourtyard, roofGarden
        public var id: String { "residential-example-" + rawValue }
        public var name: String { switch self {
        case .laneStreet: "台灣巷弄透天街廓"
        case .cornerBlock: "轉角住宅與街邊小亭"
        case .ruralCourtyard: "鄉間庭院與住宅"
        case .roofGarden: "露台住宅與屋頂設備"
        } }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        func add(_ part: Part,_ x: Float,_ y: Float,_ z: Float,angle: Float = 0) {
            b.add(model(for:part),at:Map3DPoint(x,y,z),angle:angle)
        }
        switch example {
        case .laneStreet:
            b.box(0,0,0,25,25,0.12,Map3DPalette.plaza)
            b.box(7,0.12,0,5,25,0.02,Map3DPalette.road(.minor))
            add(.narrowTownhouse,-4,0.12,-6);add(.arcadeTownhouse,-4,0.12,5)
            add(.ironGate,1.5,0.12,-11);add(.drainageChannel,4.2,0.12,-5)
            add(.drainageChannel,4.2,0.12,1);add(.planter,2.5,0.12,9)
        case .cornerBlock:
            b.box(0,0,0,30,27,0.12,Map3DPalette.plaza)
            b.box(8,0.12,0,5,27,0.02,Map3DPalette.road(.minor))
            add(.cornerHouse,-5,0.12,-6);add(.cornerKiosk,-4,0.12,8)
            add(.utilityPole,4.2,0.12,11);add(.brickWall,3,0.12,-10)
            add(.planter,3,0.12,-3);add(.drainageChannel,5,0.12,4)
        case .ruralCourtyard:
            b.box(0,0,0,38,42,0.12,Map3DPalette.park)
            add(.courtyardHouse,-7,0.12,-10);add(.farmHouse,-7,0.12,11)
            add(.fruitTree,8,0.12,-12);add(.clothesline,8,0.12,4)
            add(.tileWall,13,0.12,-7);add(.ironGate,13,0.12,-1)
        case .roofGarden:
            b.box(0,0,0,22,23,0.12,Map3DPalette.plaza)
            add(.roofTerraceHouse,-2,0.12,0)
            // The roof's top is 6.56m above this building mount.
            add(.waterTank,-3.7,6.68,1.7);add(.roofSolar,-1.1,6.68,1.2)
            add(.planter,5.2,0.12,-7);add(.bikeShed,6.0,0.12,6)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
