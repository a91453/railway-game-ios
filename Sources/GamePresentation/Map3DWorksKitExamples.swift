import Foundation

extension Map3DWorksKit {
    public enum Example: String, CaseIterable, Sendable {
        case construction, cargoDepot, ruralFarm, riverside
        public var id: String { "works-example-"+rawValue }
        public var name: String { switch self {
        case .construction: "軌旁施工基地"
        case .cargoDepot: "貨運裝卸與維修場"
        case .ruralFarm: "支線沿線農村"
        case .riverside: "溪岸動物與植栽"
        } }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        func add(_ part: Part,_ x: Float,_ y: Float,_ z: Float,angle: Float = 0) {
            b.add(model(for:part),at:Map3DPoint(x,y,z),angle:angle)
        }
        switch example {
        case .construction:
            b.box(0,0,0,24,20,0.12,Map3DPalette.ballast)
            add(.excavator,-4,0.12,-4);add(.dumpTruck,4,0.12,-5)
            add(.roadRoller,4,0.12,3);add(.containerOffice,-7,0.12,4)
            add(.pipeBundle,-2,0.12,4);add(.cableReel,0,0.12,7)
            add(.bambooClump,-9,0.12,-7);add(.riverRocks,9,0.12,7)
        case .cargoDepot:
            b.box(0,0,0,40,30,0.12,Map3DPalette.plaza)
            add(.warehouse,-10,0.12,-7)
            add(.container20,8,0.12,-8);add(.container20,8,2.72,-8)
            add(.container40,5,0.12,-12)
            add(.loadingCanopy,-6,0.12,7)
            add(.gantryCrane,9,0.12,3);add(.container20,9,0.12,2.5)
            add(.forklift,-1,0.12,-1);add(.flatbedTruck,9,0.12,11)
            add(.wheelRack,-6,0.12,11);add(.ibcTank,-1,0.12,9)
        case .ruralFarm:
            b.box(0,0,0,24,22,0.12,Map3DPalette.farm)
            add(.barn,-7,0.12,-5);add(.grainSilo,-7,0.12,3)
            add(.ricePaddy,3,0.12,5);add(.ricePaddy,7,0.12,5)
            add(.vegetableRows,-1,0.12,5)
            add(.waterBuffalo,1,0.12,-3);add(.dairyCow,-2,0.12,-3)
            add(.sheep,-1,0.12,-6);add(.hen,2,0.12,-6);add(.rooster,3,0.12,-5.8)
            add(.stationCat,-4,0.12,-2);add(.bambooClump,7,0.12,-7);add(.leafyTree,-8,0.12,8)
        case .riverside:
            b.box(0,0,0,16,16,0.12,Map3DPalette.park)
            b.box(0,0.12,0,8,6,0.05,Map3DPalette.water)
            add(.woodenJetty,0,0.12,-3.6)
            // Water connector is at native z=.13; align it to y=.17.
            add(.koi,-1,0.04,0);add(.koi,1,0.04,1,angle:1.2)
            add(.duck,5,0.12,1);add(.egret,5.3,0.12,2)
            add(.turtle,-5,0.12,-1);add(.sparrow,-4.6,0.12,2)
            add(.curledCat,3,0.12,-6);add(.riverRocks,5.5,0.12,5)
            add(.reedPatch,-4.6,0.12,-2);add(.fernPatch,-5,0.12,4)
            add(.bambooClump,-6,0.12,-5);add(.palmTree,6,0.12,-5)
            add(.treeStump,-6,0.12,6)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
