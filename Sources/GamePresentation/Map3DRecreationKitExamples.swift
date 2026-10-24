import Foundation

extension Map3DRecreationKit {
    public enum Example: String, CaseIterable, Sendable {
        case fitnessRoom = "fitnessStudio"
        case trainingCenter
        case bowlingCenter = "bowlingLounge"
        case swimmingCenter
        public var id: String { "recreation-example-"+rawValue }
        public var name: String { switch self {
        case .fitnessRoom: "社區健身館內部"
        case .trainingCenter: "攀岩與武道運動園區"
        case .bowlingCenter: "雙球道保齡球休閒館"
        case .swimmingCenter: "泳訓館與池畔配套"
        } }
    }
    public struct Placement: Sendable {
        public let part: Part
        /// Native metres, angle radians clockwise viewed from +z.
        public let position: Map3DPoint
        public let angle: Float
        /// Actual supporting surface; not a collision or navigation declaration.
        public let support: String
    }
    public static func placements(for example: Example) -> [Placement] {
        func p(_ part: Part,_ x: Float,_ right: Float,_ height: Float = 0.28,_ angle: Float = 0,_ support: String = "venueFloor") -> Placement {
            .init(part:part,position:.init(x,-right,height),angle:angle,support:support)
        }
        switch example {
        case .fitnessRoom:
            return [p(.fitnessStudio,0,0,0.12,0,"sceneGround"),p(.treadmill,1,-4),p(.exerciseBike,1,-1.4),p(.rowingErgometer,1,2),p(.adjustableBench,-2.7,-3),p(.dumbbellRack,-3,0),p(.plateTree,-3,3.5)]
        case .trainingCenter:
            return [p(.multipurposeHall,-14,0,0.12,0,"sceneGround"),p(.dojo,8,-9,0.12,0,"sceneGround"),p(.climbingHall,8,7,0.12,0,"sceneGround"),p(.boxingRing,-14,0),p(.umpireChair,-14,-6),p(.ballCart,-12,6),p(.climbingWall,6,7)]
        case .bowlingCenter:
            return [p(.bowlingLounge,0,0,0.12,0,"sceneGround"),p(.bowlingLane,0,-2.4),p(.bowlingLane,0,2.4),p(.lockerBank,-6,0),p(.ballCart,5,0)]
        case .swimmingCenter:
            return [p(.swimPavilion,0,0,0.12,0,"sceneGround"),p(.trainingPool,-1,0),p(.divingPlatform,7.3,0,0.28,Float.pi,"venueFloor+apron"),p(.startBlock,5.5,-2,1.36,Float.pi,"poolDeck"),p(.lifeguardSeat,-3,5.5),p(.poolLaneReel,10.6,4,0.28,0,"apron"),p(.showerArch,10.6,-4,0.28,0,"apron")]
        }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        if example == .trainingCenter { b.box(-3,0,0,42,34,0.12,Map3DPalette.forecourt) }
        else { b.box(1.5,0,0,25,19,0.12,Map3DPalette.forecourt) }
        if example == .swimmingCenter { b.box(10.75,0.12,0,2.5,15,0.16,Map3DPalette.forecourt) }
        for p in placements(for:example) { b.add(model(for:p.part),at:.init(p.position.x,p.position.z,-p.position.y),angle:p.angle) }
        return .flat(named:example.id,from:b.mesh)
    }
}
