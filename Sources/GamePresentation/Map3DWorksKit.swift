import Foundation

public enum Map3DWorksKit {
    public enum Category: String, CaseIterable, Sendable { case engineering, freight, animal, nature }
    public enum Mount: String, Sendable { case ground, rail, water }
    public enum Part: String, CaseIterable, Sendable {
        case excavator, miniExcavator, forklift, crawlerCrane, railCrane, roadRoller, mixerTruck, dumpTruck, serviceTruck, flatbedTruck, tankerTruck, telehandler
        case container20, container40, openContainer, containerOffice, warehouse, maintenanceShed, loadingCanopy, gantryCrane, cableReel, ibcTank, pipeBundle, wheelRack
        case stationCat, curledCat, waterBuffalo, dairyCow, sheep, hen, rooster, duck, egret, sparrow, koi, turtle
        case bambooClump, fernPatch, reedPatch, riverRocks, treeStump, leafyTree, palmTree, vegetableRows, ricePaddy, grainSilo, barn, woodenJetty
        public var id: String { "works-"+rawValue }
        public var name: String { switch self {
            case .excavator: "履帶挖土機"
            case .miniExcavator: "小型挖土機"
            case .forklift: "堆高機"
            case .crawlerCrane: "履帶吊車"
            case .railCrane: "軌道維修吊車"
            case .roadRoller: "單鋼輪壓路機"
            case .mixerTruck: "混凝土預拌車"
            case .dumpTruck: "砂石傾卸車"
            case .serviceTruck: "工程維修車"
            case .flatbedTruck: "平板貨車"
            case .tankerTruck: "灑水工程車"
            case .telehandler: "伸縮臂搬運車"
            case .container20: "20 呎遊戲貨櫃"
            case .container40: "40 呎遊戲貨櫃"
            case .openContainer: "開頂貨櫃"
            case .containerOffice: "貨櫃工務所"
            case .warehouse: "貨運倉庫"
            case .maintenanceShed: "軌道維修工場"
            case .loadingCanopy: "貨場裝卸棚"
            case .gantryCrane: "貨場門式起重機"
            case .cableReel: "工業電纜捲盤"
            case .ibcTank: "籠式儲液桶"
            case .pipeBundle: "鋼管束與墊架"
            case .wheelRack: "輪軸存放架"
            case .stationCat: "站前散步貓"
            case .curledCat: "蜷睡車站貓"
            case .waterBuffalo: "田間水牛"
            case .dairyCow: "牧場乳牛"
            case .sheep: "綿羊"
            case .hen: "母雞"
            case .rooster: "公雞"
            case .duck: "鴨子"
            case .egret: "白鷺鷥"
            case .sparrow: "麻雀"
            case .koi: "池塘錦鯉"
            case .turtle: "池邊烏龜"
            case .bambooClump: "竹叢"
            case .fernPatch: "蕨類叢"
            case .reedPatch: "蘆葦叢"
            case .riverRocks: "溪岸石群"
            case .treeStump: "樹樁"
            case .leafyTree: "闊葉樹"
            case .palmTree: "棕櫚樹"
            case .vegetableRows: "菜畦"
            case .ricePaddy: "水田"
            case .grainSilo: "農村穀倉筒"
            case .barn: "農具穀倉"
            case .woodenJetty: "河岸木棧台"
        } }
        public var category: Category { switch self {
            case .excavator, .miniExcavator, .forklift, .crawlerCrane, .railCrane, .roadRoller, .mixerTruck, .dumpTruck, .serviceTruck, .flatbedTruck, .tankerTruck, .telehandler: .engineering
            case .container20, .container40, .openContainer, .containerOffice, .warehouse, .maintenanceShed, .loadingCanopy, .gantryCrane, .cableReel, .ibcTank, .pipeBundle, .wheelRack: .freight
            case .stationCat, .curledCat, .waterBuffalo, .dairyCow, .sheep, .hen, .rooster, .duck, .egret, .sparrow, .koi, .turtle: .animal
            case .bambooClump, .fernPatch, .reedPatch, .riverRocks, .treeStump, .leafyTree, .palmTree, .vegetableRows, .ricePaddy, .grainSilo, .barn, .woodenJetty: .nature
        } }
        public var mount: Mount { self == .railCrane ? .rail : self == .koi ? .water : .ground }
    }
    public struct Connector: Sendable {
        public let name: String
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.works(part)
        return .flat(named:part.id,from:b.mesh)
    }
}

extension Map3DWorksKit.Part {
    public var connectors: [Map3DWorksKit.Connector] {
        var ports=[Map3DWorksKit.Connector(name:"mount",position:self == .koi ? Map3DPoint(0,0,0.13) : .zero,normal:Map3DPoint(0,0,-1))]
        if self == .container20 || self == .container40 {
            let length: Float = self == .container40 ? 12.2 : 6.1
            ports.append(.init(name:"stack",position:Map3DPoint(0,0,2.6),normal:Map3DPoint(0,0,1)))
            ports.append(.init(name:"end",position:Map3DPoint(length/2,0,0),normal:Map3DPoint(1,0,0)))
        }
        return ports
    }
}

extension Map3DModelPack {
    public init(worksKit parts: [Map3DWorksKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map(Map3DWorksKit.model(for:))
    }
}
