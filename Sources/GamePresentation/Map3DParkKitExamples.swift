import Foundation

extension Map3DParkKit {
    public enum Example: String, CaseIterable, Sendable {
        case playground, sportsGround, gardenWalk, pocketPark
        public var id: String { "park-example-"+rawValue }
        public var name: String { switch self {
        case .playground: "社區兒童遊戲區"
        case .sportsGround: "校園運動休憩區"
        case .gardenWalk: "池畔涼亭與步橋"
        case .pocketPark: "社區花園與健身角"
        } }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        func add(_ p: Part,_ x: Float,_ y: Float,_ z: Float,angle: Float = 0) { b.add(model(for:p),at:Map3DPoint(x,y,z),angle:angle) }
        switch example {
        case .playground:
            b.box(0,0,0,22,22,0.12,Map3DPalette.park)
            add(.slide,-4,0.12,-5);add(.swingSet,4,0.12,-5)
            add(.climbingFrame,-4,0.12,3);add(.sandpit,4,0.12,2)
            add(.seesaw,0,0.12,-1);add(.springRider,6,0.12,6);add(.steppingPods,-2,0.12,7)
            add(.musicChimes,-7,0.12,7);add(.playhouse,7,0.12,-9)
        case .sportsGround:
            b.box(0,0,0,38,34,0.12,Map3DPalette.plaza)
            add(.basketballCourt,0,0.12,-7)
            add(.basketballHoop,-11,0.20,-7);add(.basketballHoop,11,0.20,-7,angle:Float.pi)
            add(.bleachers,0,0.12,3,angle:Float.pi/2)
            add(.badmintonCourt,-6,0.12,10);add(.tableTennis,8,0.12,10)
            add(.outdoorGymBars,14,0.12,7);add(.drinkingFountain,10,0.12,3)
        case .gardenWalk:
            b.box(0,0,0,24,24,0.12,Map3DPalette.park)
            add(.pondEdge,0,0.12,0)
            // Cross the short pond axis; real footings raise the abutments,
            // while adjoining path tops meet the bridge end deck at y=.32.
            add(.archedFootbridge,0,0.20,0,angle:Float.pi/2)
            for s: Float in [-1,1] {
                b.box(0,0.12,s*2.35,1.5,0.30,0.08,Map3DPalette.concrete)
                b.box(0,0.12,s*3.5,1.5,3,0.20,Map3DPalette.plaza)
            }
            add(.gazebo,-6,0.12,-6);add(.pergola,6,0.12,-5)
            add(.raisedFlowerBed,-6,0.12,5);add(.raisedFlowerBed,6,0.12,5)
            add(.parkGate,8,0.12,0,angle:Float.pi/2);add(.drinkingFountain,-3,0.12,-6)
        case .pocketPark:
            b.box(0,0,0,18,20,0.12,Map3DPalette.park)
            add(.toolShed,-6,0.12,-6);add(.compostBin,-6,0.12,-2)
            add(.trellis,-7,0.12,4);add(.raisedFlowerBed,-4,0.12,4)
            add(.steppedFountain,1,0.12,0);add(.pergola,4,0.12,-6)
            add(.outdoorGymBars,5,0.12,5);add(.balanceBeam,1,0.12,6)
            add(.boardwalkCorner,-1,0.12,-6)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
