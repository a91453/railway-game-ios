import Foundation

/// Optional static sports scenery, with open-front venues for visible assembly.
public enum Map3DRecreationKit {
    public enum Category: String, CaseIterable, Sendable { case venue, fitness, sport, aquatic }
    public enum Mount: String, Sendable { case ground }
    public enum Part: String, CaseIterable, Sendable {
        case fitnessStudio, multipurposeHall, bowlingLounge, swimPavilion, climbingHall, dojo
        case treadmill, exerciseBike, rowingErgometer, adjustableBench, dumbbellRack, plateTree
        case climbingWall, boxingRing, bowlingLane, umpireChair, ballCart, lockerBank
        case trainingPool, divingPlatform, startBlock, lifeguardSeat, poolLaneReel, showerArch
        public var id: String { "recreation-"+rawValue }
        public var name: String { switch self {
        case .fitnessStudio: "開放式健身館"
        case .multipurposeHall: "多用途運動館"
        case .bowlingLounge: "保齡球休閒館"
        case .swimPavilion: "拱頂泳訓館"
        case .climbingHall: "高挑攀岩館"
        case .dojo: "木構武道館"
        case .treadmill: "電動跑步機"
        case .exerciseBike: "固定式健身車"
        case .rowingErgometer: "划船訓練機"
        case .adjustableBench: "斜背重訓椅"
        case .dumbbellRack: "雙層啞鈴架"
        case .plateTree: "槓片收納樹"
        case .climbingWall: "自立斜面攀岩牆"
        case .boxingRing: "四柱拳擊擂台"
        case .bowlingLane: "保齡球球道"
        case .umpireChair: "高腳裁判椅"
        case .ballCart: "帶輪球車"
        case .lockerBank: "三格置物櫃與更衣椅"
        case .trainingPool: "架高泳訓池"
        case .divingPlatform: "支柱式跳水台"
        case .startBlock: "泳池出發台"
        case .lifeguardSeat: "泳池救生高椅"
        case .poolLaneReel: "泳道繩收納捲架"
        case .showerArch: "池畔淋浴架"
        } }
        public var category: Category { switch self {
        case .fitnessStudio,.multipurposeHall,.bowlingLounge,.swimPavilion,.climbingHall,.dojo: .venue
        case .treadmill,.exerciseBike,.rowingErgometer,.adjustableBench,.dumbbellRack,.plateTree: .fitness
        case .climbingWall,.boxingRing,.bowlingLane,.umpireChair,.ballCart,.lockerBank: .sport
        case .trainingPool,.divingPlatform,.startBlock,.lifeguardSeat,.poolLaneReel,.showerArch: .aquatic
        } }
        public var mount: Mount { .ground }
        /// Native metres: x front / y left / z up. Box construction is y-up internally.
        public var connectors: [Connector] {
            var c=[Connector(name:"mount",position:.zero,normal:Map3DPoint(0,0,-1))]
            if category == .venue { c.append(.init(name:"floor",position:.init(0,0,0.16),normal:.init(0,0,1))) }
            if self == .trainingPool { c += [.init(name:"waterSurface",position:.init(0,0,0.78),normal:.init(0,0,1)),.init(name:"frontDeck",position:.init(6.5,1,1.08),normal:.init(0,0,1))] }
            if self == .divingPlatform { c.append(.init(name:"boardTip",position:.init(2.6,0,2.90),normal:.init(0,0,1))) }
            return c
        }
    }
    public struct Connector: Sendable { public let name: String;public let position: Map3DPoint;public let normal: Map3DPoint }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.recreation(part);return .flat(named:part.id,from:b.mesh)
    }
}
extension Map3DModelPack {
    public init(recreationKit parts: [Map3DRecreationKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models:[])+parts.map(Map3DRecreationKit.model(for:))
    }
}
