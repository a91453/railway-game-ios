import Foundation

/// Optional static park assets, created on demand; no game state or simulation.
public enum Map3DParkKit {
    public enum Category: String, CaseIterable, Sendable { case playground, sport, garden }
    public enum Mount: String, Sendable { case ground }
    public enum Part: String, CaseIterable, Sendable {
        case slide, swingSet, seesaw, climbingFrame, sandpit, roundabout, springRider, playhouse, toddlerSlide, ropeBridge, steppingPods, musicChimes
        case basketballHoop, basketballCourt, tennisCourt, tennisNet, soccerGoal, miniSoccerPitch, badmintonCourt, tableTennis, outdoorGymBars, balanceBeam, skateQuarterPipe, bleachers
        case gazebo, pergola, archedFootbridge, parkGate, drinkingFountain, steppedFountain, pondEdge, raisedFlowerBed, compostBin, toolShed, boardwalkCorner, trellis
        public var id: String { "park-"+rawValue }
        public var name: String { switch self {
        case .slide: "高架溜滑梯"
        case .swingSet: "雙座鞦韆"
        case .seesaw: "翹翹板"
        case .climbingFrame: "攀爬架"
        case .sandpit: "沙坑"
        case .roundabout: "旋轉遊具"
        case .springRider: "搖搖馬"
        case .playhouse: "兒童遊戲屋"
        case .toddlerSlide: "幼兒滑梯"
        case .ropeBridge: "遊戲繩橋"
        case .steppingPods: "踏步樁"
        case .musicChimes: "敲擊音管"
        case .basketballHoop: "籃球架"
        case .basketballCourt: "籃球場地坪"
        case .tennisCourt: "網球場地坪"
        case .tennisNet: "網球網"
        case .soccerGoal: "足球球門"
        case .miniSoccerPitch: "迷你足球場"
        case .badmintonCourt: "羽球場地坪"
        case .tableTennis: "戶外桌球桌"
        case .outdoorGymBars: "戶外健身單槓"
        case .balanceBeam: "平衡木"
        case .skateQuarterPipe: "滑板四分之一管"
        case .bleachers: "階梯看台"
        case .gazebo: "八角涼亭"
        case .pergola: "格柵花架"
        case .archedFootbridge: "拱形步橋"
        case .parkGate: "公園入口架"
        case .drinkingFountain: "飲水台"
        case .steppedFountain: "階層噴泉"
        case .pondEdge: "景觀池"
        case .raisedFlowerBed: "高架花圃"
        case .compostBin: "堆肥箱"
        case .toolShed: "園藝工具屋"
        case .boardwalkCorner: "轉角木棧道"
        case .trellis: "攀藤花牆"
        } }
        public var category: Category { switch self {
        case .slide, .swingSet, .seesaw, .climbingFrame, .sandpit, .roundabout, .springRider, .playhouse, .toddlerSlide, .ropeBridge, .steppingPods, .musicChimes: .playground
        case .basketballHoop, .basketballCourt, .tennisCourt, .tennisNet, .soccerGoal, .miniSoccerPitch, .badmintonCourt, .tableTennis, .outdoorGymBars, .balanceBeam, .skateQuarterPipe, .bleachers: .sport
        case .gazebo, .pergola, .archedFootbridge, .parkGate, .drinkingFountain, .steppedFountain, .pondEdge, .raisedFlowerBed, .compostBin, .toolShed, .boardwalkCorner, .trellis: .garden
        } }
        public var mount: Mount { .ground }
        public var connectors: [Connector] {
            var c=[Connector(name:"mount",position:.zero,normal:Map3DPoint(0,0,-1))]
            if self == .archedFootbridge { c += [.init(name:"start",position:Map3DPoint(-2.5,0,0.12),normal:Map3DPoint(-1,0,0)),.init(name:"end",position:Map3DPoint(2.5,0,0.12),normal:Map3DPoint(1,0,0))] }
            if self == .basketballCourt { c += [.init(name:"hoopA",position:Map3DPoint(-11,0,0.08),normal:Map3DPoint(0,0,1)),.init(name:"hoopB",position:Map3DPoint(11,0,0.08),normal:Map3DPoint(0,0,1))] }
            return c
        }
    }
    public struct Connector: Sendable { public let name: String;public let position: Map3DPoint;public let normal: Map3DPoint }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.park(part);return .flat(named:part.id,from:b.mesh)
    }
}
extension Map3DModelPack {
    public init(parkKit parts: [Map3DParkKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map(Map3DParkKit.model(for:))
    }
}
