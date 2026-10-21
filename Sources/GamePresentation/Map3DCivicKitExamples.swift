import Foundation

extension Map3DCivicKit {
    public enum Example: String, CaseIterable, Sendable {
        case civicStreet, roomCutaway, templePlaza, marketCourtyard
        public var id: String { "civic-example-"+rawValue }
        public var name: String { switch self {
        case .civicStreet: "社區公共建築街廓"
        case .roomCutaway: "住宅與工作室剖視"
        case .templePlaza: "台式廟埕"
        case .marketCourtyard: "市場與小吃廣場"
        } }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        func add(_ p: Part,_ x: Float,_ y: Float,_ z: Float,angle: Float = 0) { b.add(model(for:p),at:Map3DPoint(x,y,z),angle:angle) }
        switch example {
        case .civicStreet:
            b.box(0,0,0,36,44,0.12,Map3DPalette.plaza)
            b.box(4,0.12,0,7,44,0.02,Map3DPalette.road(.minor))
            add(.clinic,-7,0.12,-13);add(.policePost,-7,0.12,2);add(.postOffice,-7,0.12,16)
            add(.publicToilet,12,0.12,-13,angle:Float.pi);add(.dayCareCenter,12,0.12,5,angle:Float.pi)
        case .roomCutaway:
            b.box(0,0,0,10,10,0.15,Map3DPalette.counters[1])
            b.box(-4.9,0.15,0,0.2,10,3.2,Map3DPalette.playerRoof);b.box(0,0.15,-4.9,10,0.2,3.2,Map3DPalette.playerRoof)
            add(.singleBed,-3.2,0.15,2.7);add(.bedsideTable,-2.5,0.15,1.4);add(.wardrobe,-4.4,0.15,0)
            add(.writingDesk,-4.35,0.15,-2.8);add(.deskLamp,-4.35,0.95,-2.8);add(.officeChair,-3.3,0.15,-2.8)
            add(.twoSeatSofa,0,0.15,2.8);add(.coffeeTable,1.3,0.15,2.8)
            add(.bookcase,-4.55,0.15,-1.2);add(.studioCamera,2.5,0.15,-2)
            add(.wallClock,-4.8,2.55,1);add(.curtains,-4.8,1.15,3)
            add(.projectionScreen,-1,1.75,-4.8,angle:Float.pi/2)
            // Small ceiling beam anchors the downward mounting plate at y=3.35.
            b.box(0,3.35,-1.4,10,0.3,0.15,Map3DPalette.playerRoof);add(.ceilingProjector,0,3.35,-1.4)
        case .templePlaza:
            b.box(0,0,0,30,32,0.12,Map3DPalette.plaza)
            add(.templeHall,-6,0.12,0);add(.templeGate,8,0.12,0)
            add(.incenseBurner,2.5,0.12,0);add(.offeringTable,0,0.12,0)
            add(.lanternString,4,0.12,-8);add(.lanternString,4,0.12,8)
            for z: Float in [-12,12] { for x: Float in [-10,-6,-2,2,6] { add(.templeWall,x,0.12,z,angle:Float.pi/2) } }
        case .marketCourtyard:
            b.box(0,0,0,34,34,0.12,Map3DPalette.plaza)
            add(.marketHall,-7,0.12,-5)
            add(.marketCanopy,8,0.12,-7);add(.marketStall,8,0.12,-9);add(.marketStall,8,0.12,-5)
            add(.produceCart,6,0.12,1);add(.snackCart,10,0.12,1)
            add(.umbrellaTable,7,0.12,7);add(.umbrellaTable,11,0.12,11)
            add(.lanternString,2,0.12,7)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
