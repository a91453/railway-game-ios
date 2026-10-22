import Foundation

/// Optional static commercial and transit assets; no authoritative game rules,
/// map placement or state simulation.
public enum Map3DCommercialKit {
    public enum Category: String, CaseIterable, Sendable {
        case building, shop, facility
    }

    public enum Mount: String, Sendable {
        case ground, wall, ceiling
    }

    public enum Part: String, CaseIterable, Sendable {
        // Category 1: 12 Commercial Buildings
        case departmentStore, cinema, supermarket, cornerOffice, yellowCafe, gasStation
        case parkingGarage, commercialHotel, bankBranch, stackedShopHouse, warehouseStore, metroEntrance

        // Category 2: 12 Shops & Dining Facilities
        case bubbleTeaShop, bentoShop, bakery, pharmacy, cornerGrocery, stationeryStore
        case ramenYatai, nightMarketFryer, nightMarketFruit, nightMarketGame, vendingBank, mobileFoodCart

        // Category 3: 12 Signage, Furniture & Vehicles
        case verticalNeonSign, horizontalSignboard, totemLightbox, aFrameSign, commercialBannerPole, retractableAwning
        case cafeUmbrellaSet, commercialPlanter, commercialRecycling, coolingTower, fireEscapeStair, transitFeederBus

        public var id: String { "commercial-" + rawValue }

        public var name: String {
            switch self {
            case .departmentStore: "百貨商場"
            case .cinema: "復古裝飾風電影院"
            case .supermarket: "生鮮超市"
            case .cornerOffice: "街角商務辦公樓"
            case .yellowCafe: "暖黃磚瓦咖啡館"
            case .gasStation: "公路加油站"
            case .parkingGarage: "多層立體停車場"
            case .commercialHotel: "商務飯店"
            case .bankBranch: "銀行分行"
            case .stackedShopHouse: "商住複合透天樓"
            case .warehouseStore: "批發物流商場"
            case .metroEntrance: "捷運地下街出入口"

            case .bubbleTeaShop: "騎樓手搖飲店"
            case .bentoShop: "台式便當小吃店"
            case .bakery: "傳統烘焙麵包坊"
            case .pharmacy: "健保西藥房"
            case .cornerGrocery: "傳統柑仔店/雜貨店"
            case .stationeryStore: "文具書局"
            case .ramenYatai: "拉麵熱食屋台"
            case .nightMarketFryer: "夜市炸物鹽酥雞攤"
            case .nightMarketFruit: "夜市現切水果攤"
            case .nightMarketGame: "夜市打彈珠遊戲攤"
            case .vendingBank: "自動販賣機組合"
            case .mobileFoodCart: "外帶餐車"

            case .verticalNeonSign: "垂直霓虹/燈箱招牌"
            case .horizontalSignboard: "橫式店面招牌"
            case .totemLightbox: "雙面獨立燈箱立牌"
            case .aFrameSign: "A字黑板菜單立牌"
            case .commercialBannerPole: "商業路燈羅馬旗"
            case .retractableAwning: "騎樓帆布伸縮雨棚"
            case .cafeUmbrellaSet: "露天咖啡陽傘座組"
            case .commercialPlanter: "商圈花箱護欄組"
            case .commercialRecycling: "商圈分類資源回收箱"
            case .coolingTower: "商辦屋頂水冷卻塔"
            case .fireEscapeStair: "外掛逃生鋼梯"
            case .transitFeederBus: "市區接駁公車"
            }
        }

        public var category: Category {
            switch self {
            case .departmentStore, .cinema, .supermarket, .cornerOffice, .yellowCafe, .gasStation,
                 .parkingGarage, .commercialHotel, .bankBranch, .stackedShopHouse, .warehouseStore, .metroEntrance:
                return .building
            case .bubbleTeaShop, .bentoShop, .bakery, .pharmacy, .cornerGrocery, .stationeryStore,
                 .ramenYatai, .nightMarketFryer, .nightMarketFruit, .nightMarketGame, .vendingBank, .mobileFoodCart:
                return .shop
            case .verticalNeonSign, .horizontalSignboard, .totemLightbox, .aFrameSign, .commercialBannerPole, .retractableAwning,
                 .cafeUmbrellaSet, .commercialPlanter, .commercialRecycling, .coolingTower, .fireEscapeStair, .transitFeederBus:
                return .facility
            }
        }

        public var mount: Mount {
            switch self {
            case .verticalNeonSign, .horizontalSignboard, .retractableAwning, .fireEscapeStair:
                return .wall
            default:
                return .ground
            }
        }
    }

    public struct Connector: Sendable {
        public let name: String
        /// Native coordinates: x front, y left, z up, metres.
        public let position: Map3DPoint
        public let normal: Map3DPoint

        public init(name: String, position: Map3DPoint, normal: Map3DPoint) {
            self.name = name
            self.position = position
            self.normal = normal
        }
    }

    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.commercial(part)
        return .flat(named: part.id, from: b.mesh)
    }
}

extension Map3DCommercialKit.Part {
    public var connectors: [Map3DCommercialKit.Connector] {
        let normal: Map3DPoint = mount == .wall ? Map3DPoint(-1, 0, 0) : mount == .ceiling ? Map3DPoint(0, 0, 1) : Map3DPoint(0, 0, -1)
        var c = [Map3DCommercialKit.Connector(name: "mount", position: .zero, normal: normal)]
        switch self {
        case .bubbleTeaShop:
            c.append(.init(name: "counter", position: Map3DPoint(0, 0, 0.95), normal: Map3DPoint(0, 0, 1)))
        case .bentoShop:
            c.append(.init(name: "counter", position: Map3DPoint(0, 0, 0.85), normal: Map3DPoint(0, 0, 1)))
        case .bakery:
            c.append(.init(name: "shelf", position: Map3DPoint(0, 0, 0.80), normal: Map3DPoint(0, 0, 1)))
        case .pharmacy:
            c.append(.init(name: "counter", position: Map3DPoint(0, 0, 0.90), normal: Map3DPoint(0, 0, 1)))
        case .cafeUmbrellaSet:
            c.append(.init(name: "tableTop", position: Map3DPoint(0, 0, 0.74), normal: Map3DPoint(0, 0, 1)))
        case .transitFeederBus:
            c.append(.init(name: "frontDoor", position: Map3DPoint(2.8, -1.25, 0.35), normal: Map3DPoint(0, -1, 0)))
            c.append(.init(name: "rearDoor", position: Map3DPoint(-0.8, -1.25, 0.35), normal: Map3DPoint(0, -1, 0)))
        default:
            break
        }
        return c
    }
}

extension Map3DModelPack {
    public init(commercialKit parts: [Map3DCommercialKit.Part], includeStandard: Bool = false) {
        models = (includeStandard ? Self.standard.models : []) + parts.map(Map3DCommercialKit.model(for:))
    }
}
