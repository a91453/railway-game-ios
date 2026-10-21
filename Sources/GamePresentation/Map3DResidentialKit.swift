import Foundation

/// Optional static neighbourhood assets. Construct only the parts a scene needs.
public enum Map3DResidentialKit {
    public enum Category: String, CaseIterable, Sendable { case home, boundary, yard }
    public enum Mount: String, Sendable { case ground, wall }
    public enum Part: String, CaseIterable, Sendable {
        case narrowTownhouse, arcadeTownhouse, duplexHouse, roofTerraceHouse
        case cornerHouse, walkupApartment, courtyardHouse, farmHouse
        case brickWall, tileWall, ironGate, slidingGate, porchCanopy, carport, balconyModule, drainageChannel
        case waterTank, roofSolar, planter, fruitTree, bikeShed, clothesline, utilityPole, cornerKiosk
        public var id: String { "residential-" + rawValue }
        public var name: String { switch self {
        case .narrowTownhouse: "窄面透天厝"
        case .arcadeTownhouse: "有騎樓的透天厝"
        case .duplexHouse: "雙戶連棟住宅"
        case .roofTerraceHouse: "頂樓露台住宅"
        case .cornerHouse: "轉角住宅"
        case .walkupApartment: "四層公寓"
        case .courtyardHouse: "庭院式平房"
        case .farmHouse: "鄉間紅瓦住宅"
        case .brickWall: "洗石子與磚界牆"
        case .tileWall: "馬賽克街牆"
        case .ironGate: "鐵欄庭院門"
        case .slidingGate: "橫拉車道門"
        case .porchCanopy: "有柱玄關雨棚"
        case .carport: "獨立車棚"
        case .balconyModule: "貼牆陽台模組"
        case .drainageChannel: "路邊排水溝"
        case .waterTank: "屋頂水塔與支架"
        case .roofSolar: "斜架太陽能板"
        case .planter: "庭院長花槽"
        case .fruitTree: "庭院果樹"
        case .bikeShed: "機車腳踏車棚"
        case .clothesline: "有柱曬衣架"
        case .utilityPole: "街角電線桿"
        case .cornerKiosk: "轉角雜貨小亭"
        } }
        public var category: Category { switch self {
        case .narrowTownhouse,.arcadeTownhouse,.duplexHouse,.roofTerraceHouse,.cornerHouse,.walkupApartment,.courtyardHouse,.farmHouse: .home
        case .brickWall,.tileWall,.ironGate,.slidingGate,.porchCanopy,.carport,.balconyModule,.drainageChannel: .boundary
        default: .yard
        } }
        public var mount: Mount { self == .balconyModule ? .wall : .ground }
    }
    public struct Connector: Sendable {
        public let name: String
        /// Native coordinates: x front, y left, z up; metres.
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.residential(part)
        return .flat(named: part.id, from: builder.mesh)
    }
}

extension Map3DResidentialKit.Part {
    public var connectors: [Map3DResidentialKit.Connector] {
        let normal = mount == .wall ? Map3DPoint(-1,0,0) : Map3DPoint(0,0,-1)
        var result = [Map3DResidentialKit.Connector(name:"mount",position:.zero,normal:normal)]
        if self == .brickWall || self == .tileWall {
            result += [.init(name:"left",position:Map3DPoint(0,2,0),normal:Map3DPoint(0,1,0)),
                       .init(name:"right",position:Map3DPoint(0,-2,0),normal:Map3DPoint(0,-1,0))]
        }
        if self == .balconyModule {
            result.append(.init(name:"floor",position:Map3DPoint(0.7,0,0),normal:Map3DPoint(0,0,1)))
        }
        return result
    }
}

extension Map3DModelPack {
    public init(residentialKit parts: [Map3DResidentialKit.Part], includeStandard: Bool = false) {
        models = (includeStandard ? Self.standard.models : []) + parts.map(Map3DResidentialKit.model(for:))
    }
}
