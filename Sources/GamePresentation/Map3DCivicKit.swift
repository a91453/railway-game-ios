import Foundation

/// Optional static assets; no game rules, map placement or authoritative state.
public enum Map3DCivicKit {
    public enum Category: String, CaseIterable, Sendable { case building, furniture, culture }
    public enum Mount: String, Sendable { case ground, wall, ceiling }
    public enum Part: String, CaseIterable, Sendable {
        case clinic, policePost, fireStation, postOffice, primarySchool, kindergarten, library, communityHall, schoolGym, dayCareCenter, publicToilet, marketHall
        case singleBed, doubleBed, wardrobe, bedsideTable, writingDesk, officeChair, loungeChair, twoSeatSofa, coffeeTable, bookcase, workbench, utilitySink, wallClock, deskLamp, ceilingProjector, projectionScreen, poolTable, cafeTable, barCounter, barStool, curtains, acousticPanel, storageCabinet, studioCamera
        case templeGate, templeHall, templeSideHall, incenseBurner, lanternString, templeWall, offeringTable, marketStall, produceCart, snackCart, marketCanopy, umbrellaTable
        public var id: String { "civic-"+rawValue }
        public var name: String { switch self {
            case .clinic: "社區診所"
            case .policePost: "警察派出所"
            case .fireStation: "消防分隊"
            case .postOffice: "社區郵務所"
            case .primarySchool: "國小校舍"
            case .kindergarten: "幼兒園"
            case .library: "社區圖書館"
            case .communityHall: "社區活動中心"
            case .schoolGym: "學校體育館"
            case .dayCareCenter: "日間照護中心"
            case .publicToilet: "公園公廁"
            case .marketHall: "市場主棟"
            case .singleBed: "單人床"
            case .doubleBed: "雙人床"
            case .wardrobe: "雙門衣櫃"
            case .bedsideTable: "床頭櫃"
            case .writingDesk: "書桌"
            case .officeChair: "辦公椅"
            case .loungeChair: "休閒椅"
            case .twoSeatSofa: "雙人沙發"
            case .coffeeTable: "茶几"
            case .bookcase: "開放書櫃"
            case .workbench: "維修工作桌"
            case .utilitySink: "工作水槽"
            case .wallClock: "壁鐘"
            case .deskLamp: "桌燈"
            case .ceilingProjector: "吊掛投影機"
            case .projectionScreen: "壁掛投影幕"
            case .poolTable: "撞球桌"
            case .cafeTable: "咖啡圓桌"
            case .barCounter: "接待吧檯"
            case .barStool: "吧檯高腳椅"
            case .curtains: "窗框與窗簾"
            case .acousticPanel: "壁掛吸音板"
            case .storageCabinet: "工具置物櫃"
            case .studioCamera: "攝影機與腳架"
            case .templeGate: "台式廟門"
            case .templeHall: "台式廟宇正殿"
            case .templeSideHall: "廟宇側殿"
            case .incenseBurner: "廟埕香爐"
            case .lanternString: "燈籠串與支架"
            case .templeWall: "廟埕圍牆"
            case .offeringTable: "廟宇供桌"
            case .marketStall: "市場攤位"
            case .produceCart: "蔬果推車"
            case .snackCart: "小吃餐車"
            case .marketCanopy: "市場連續雨棚"
            case .umbrellaTable: "遮陽傘桌組"
        } }
        public var category: Category { switch self {
            case .clinic, .policePost, .fireStation, .postOffice, .primarySchool, .kindergarten, .library, .communityHall, .schoolGym, .dayCareCenter, .publicToilet, .marketHall: .building
            case .singleBed, .doubleBed, .wardrobe, .bedsideTable, .writingDesk, .officeChair, .loungeChair, .twoSeatSofa, .coffeeTable, .bookcase, .workbench, .utilitySink, .wallClock, .deskLamp, .ceilingProjector, .projectionScreen, .poolTable, .cafeTable, .barCounter, .barStool, .curtains, .acousticPanel, .storageCabinet, .studioCamera: .furniture
            case .templeGate, .templeHall, .templeSideHall, .incenseBurner, .lanternString, .templeWall, .offeringTable, .marketStall, .produceCart, .snackCart, .marketCanopy, .umbrellaTable: .culture
        } }
        public var mount: Mount { switch self {
            case .wallClock,.projectionScreen,.curtains,.acousticPanel: .wall
            case .ceilingProjector: .ceiling
            default: .ground
        } }
    }
    public struct Connector: Sendable {
        public let name: String
        /// Native coordinates: x front, y left, z up, metres.
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.civic(part)
        return .flat(named:part.id,from:b.mesh)
    }
}

extension Map3DCivicKit.Part {
    public var connectors: [Map3DCivicKit.Connector] {
        let normal: Map3DPoint=mount == .wall ? Map3DPoint(-1,0,0) : mount == .ceiling ? Map3DPoint(0,0,1) : Map3DPoint(0,0,-1)
        var c=[Map3DCivicKit.Connector(name:"mount",position:.zero,normal:normal)]
        if self == .writingDesk { c.append(.init(name:"desktop",position:Map3DPoint(0,0,0.80),normal:Map3DPoint(0,0,1))) }
        if self == .templeWall {
            c += [.init(name:"start",position:Map3DPoint(0,2,0),normal:Map3DPoint(0,1,0)),.init(name:"end",position:Map3DPoint(0,-2,0),normal:Map3DPoint(0,-1,0))]
        }
        return c
    }
}

extension Map3DModelPack {
    public init(civicKit parts: [Map3DCivicKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map(Map3DCivicKit.model(for:))
    }
}
