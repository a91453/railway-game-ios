import Foundation

/// Optional player-owned building scenery. No economy rules or live map registration.
public enum Map3DEstateKit {
    public enum Category: String, CaseIterable, Sendable { case leisure, hotel, residential, commercial }
    public enum Mount: String, Sendable { case ground }
    public enum Part: String, CaseIterable, Sendable {
        case themeParkGate, carouselPavilion, ferrisWheel, waterPlayHall, planetarium, fantasyCastle
        case courtyardInn, resortHotel, hotSpringInn, towerHotel, capsuleHostel, motorInn
        case skybridgeResidences, terracedCondominium, atriumApartments, maisonetteRow, pilotisResidence, roofGardenVilla
        case foodCourtHall, coworkingAtrium, gardenCenter, outletArcade, exhibitionHall, weddingBanquetHall
        public var id: String { "estate-"+rawValue }
        public var name: String { switch self {
        case .themeParkGate: "雙塔樂園入口"
        case .carouselPavilion: "旋轉木馬亭"
        case .ferrisWheel: "觀景摩天輪"
        case .waterPlayHall: "室內戲水館"
        case .planetarium: "圓頂天文館"
        case .fantasyCastle: "幻想城堡"
        case .courtyardInn: "中庭旅店"
        case .resortHotel: "池庭度假飯店"
        case .hotSpringInn: "雙翼溫泉旅館"
        case .towerHotel: "階冠高塔飯店"
        case .capsuleHostel: "階梯膠囊旅舍"
        case .motorInn: "架空汽車旅館"
        case .skybridgeResidences: "空橋雙塔住宅"
        case .terracedCondominium: "梯田集合住宅"
        case .atriumApartments: "天井公寓"
        case .maisonetteRow: "錯層連棟住宅"
        case .pilotisResidence: "架空庭院住宅"
        case .roofGardenVilla: "屋頂花園別墅"
        case .foodCourtHall: "雙頂美食廣場"
        case .coworkingAtrium: "共享辦公中庭"
        case .gardenCenter: "玻璃園藝中心"
        case .outletArcade: "折線商店街"
        case .exhibitionHall: "鋸齒屋頂展覽館"
        case .weddingBanquetHall: "雙翼宴會館"
        } }
        public var category: Category { switch self {
        case .themeParkGate,.carouselPavilion,.ferrisWheel,.waterPlayHall,.planetarium,.fantasyCastle: .leisure
        case .courtyardInn,.resortHotel,.hotSpringInn,.towerHotel,.capsuleHostel,.motorInn: .hotel
        case .skybridgeResidences,.terracedCondominium,.atriumApartments,.maisonetteRow,.pilotisResidence,.roofGardenVilla: .residential
        case .foodCourtHall,.coworkingAtrium,.gardenCenter,.outletArcade,.exhibitionHall,.weddingBanquetHall: .commercial
        } }
        public var mount: Mount { .ground }
        /// Native axes: +x front, +y left, +z up. All models have a solid plinth.
        public var connectors: [Connector] {
            let model=Map3DEstateKit.model(for:self)
            return [.init(name:"mount",position:.zero,normal:Map3DPoint(0,0,-1)),
                    .init(name:"approach",position:Map3DPoint(model.maximum.x,0,0.16),normal:Map3DPoint(1,0,0))]
        }
    }
    public struct Connector: Sendable {
        public let name: String
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.estate(part)
        return .flat(named:part.id,from:b.mesh)
    }
}
extension Map3DModelPack {
    public init(estateKit parts: [Map3DEstateKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map(Map3DEstateKit.model(for:))
    }
}
