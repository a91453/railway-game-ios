import Foundation

/// Optional static scenery. Nothing here registers assets in the live map.
public enum Map3DCoastalKit {
    public enum Category: String, CaseIterable, Sendable { case coast, harbor, camp }
    public enum Mount: String, Sendable { case ground }
    public enum Part: String, CaseIterable, Sendable {
        case beaconTower, coastShelter, lifeguardTower, boatWorkshop, auctionShelter, slipway, seawallStairs, floatingPontoon
        case rowingSkiff, motorDinghy, boatTrailer, mooringBollard, lifeRingStand, netDryingRack, fishSortingTable, insulatedFishCrate
        case domeTent, ridgeTent, hammockStand, campKitchen, foldingChair, campTable, firePit, kayakRack
        public var id: String { "coastal-"+rawValue }
        public var name: String { switch self {
        case .beaconTower: "港口燈塔"
        case .coastShelter: "海岸候憩亭"
        case .lifeguardTower: "海灘救生瞭望台"
        case .boatWorkshop: "小船修理屋"
        case .auctionShelter: "漁港理貨棚"
        case .slipway: "小船下水斜台"
        case .seawallStairs: "海堤階梯"
        case .floatingPontoon: "浮筒登船台"
        case .rowingSkiff: "岸置划槳小艇"
        case .motorDinghy: "舷外機漁艇"
        case .boatTrailer: "小艇拖架"
        case .mooringBollard: "雙耳繫船柱"
        case .lifeRingStand: "救生圈架"
        case .netDryingRack: "漁網晾曬架"
        case .fishSortingTable: "漁獲分揀桌"
        case .insulatedFishCrate: "保冷魚箱"
        case .domeTent: "圓拱露營帳"
        case .ridgeTent: "前庭屋脊帳"
        case .hammockStand: "自立吊床"
        case .campKitchen: "營地炊事台"
        case .foldingChair: "折疊露營椅"
        case .campTable: "折腳露營桌"
        case .firePit: "架高焚火台"
        case .kayakRack: "獨木舟存放架"
        } }
        public var category: Category { switch self {
        case .beaconTower,.coastShelter,.lifeguardTower,.boatWorkshop,.auctionShelter,.slipway,.seawallStairs,.floatingPontoon: .coast
        case .rowingSkiff,.motorDinghy,.boatTrailer,.mooringBollard,.lifeRingStand,.netDryingRack,.fishSortingTable,.insulatedFishCrate: .harbor
        default: .camp
        } }
        /// All standalone assets rest on z=0. For boats/pontoon on water,
        /// translate by water height minus the separate waterline connector.
        public var mount: Mount { .ground }
        public var connectors: [Connector] {
            var result=[Connector(name:"mount",position:.zero,normal:Map3DPoint(0,0,-1))]
            switch self {
            case .rowingSkiff: result.append(.init(name:"waterline",position:Map3DPoint(0,0,0.24),normal:Map3DPoint(0,0,1)))
            case .motorDinghy: result.append(.init(name:"waterline",position:Map3DPoint(0,0,0.32),normal:Map3DPoint(0,0,1)))
            case .floatingPontoon:
                result += [.init(name:"waterline",position:Map3DPoint(0,0,0.22),normal:Map3DPoint(0,0,1)),.init(name:"deck",position:Map3DPoint(0,0,0.52),normal:Map3DPoint(0,0,1))]
            case .fishSortingTable: result.append(.init(name:"worktop",position:Map3DPoint(0,0,0.9),normal:Map3DPoint(0,0,1)))
            case .campTable: result.append(.init(name:"tabletop",position:Map3DPoint(0,0,0.7),normal:Map3DPoint(0,0,1)))
            case .boatTrailer: result.append(.init(name:"keelRest",position:Map3DPoint(0,0,0.62),normal:Map3DPoint(0,0,1)))
            case .slipway:
                result += [.init(name:"lowEnd",position:Map3DPoint(3,0,0.12),normal:Map3DPoint(1,0,0)),.init(name:"highEnd",position:Map3DPoint(-3,0,1.2),normal:Map3DPoint(-1,0,0))]
            default: break
            }
            return result
        }
    }
    public struct Connector: Sendable {
        public let name: String
        /// Native coordinates: +x front, +y left, +z up, metres.
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.coastal(part)
        return .flat(named:part.id,from:b.mesh)
    }
}

extension Map3DModelPack {
    public init(coastalKit parts: [Map3DCoastalKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map(Map3DCoastalKit.model(for:))
    }
}
