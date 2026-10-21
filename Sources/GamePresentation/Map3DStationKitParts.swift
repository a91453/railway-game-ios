extension Map3DStationKit {
    public enum Part: String, CaseIterable, Sendable {
        case platformStraight
        case platformEnd
        case islandPlatform
        case sidePlatform
        case platformCurve
        case platformRamp
        case platformStairs
        case platformCanopy
        case canopyEnd
        case vColumn
        case yColumn
        case roofTruss
        case overbridge
        case bridgeStairs
        case escalator
        case liftTower
        case fareGate
        case wideGate
        case ticketMachine
        case ticketCounter
        case serviceBooth
        case informationBoard
        case platformSign
        case exitSign
        case clockPole
        case timetableBoard
        case wayfindingPylon
        case tactileStraight
        case tactileJunction
        case platformScreenDoors
        case halfHeightScreenDoors
        case safetyFence
        case bench
        case backlessBench
        case waitingShelter
        case baggageLocker
        case drinkingFountain
        case binPair
        case publicPhone
        case vendingMachine
        case toiletBlock
        case bikeRack
        case bikeShelter
        case busShelter
        case taxiCanopy
        case bollardRow
        case planterBench
        case stationTree
        case catenaryPortal
        case bufferStop
        case signalMast
        case relayCabinet
        case utilityHut
        case ventShaft
        case smokeVent
        case stairHead
        case undergroundExit
        case stationEntrance
        case stationRoofWing
        case skylight
        case footpathTile
        case forecourtTile
        case lampPole
        case chargingPoint
        case wallPlain
        case wallWindow
        case wallTwinWindow
        case wallDoor
        case wallShopfront
        case wallLouver
        case wallCorner
        case arcadeBay
        case floorSlab
        case balcony
        case balconyCorner
        case roofParapet
        case roofAccess
        case gableRoof
        case hipRoof
        case flatRoof
        case roofDrain
        case downpipe
        case acBracket
        case acCondenser
        case waterTank
        case waterTankStand
        case solarArray
        case roofDuct
        case roofFan
        case fireEscape
        case externalStairs
        case shopAwning
        case rollerShutter
        case blankSign
        case loadingBay
        case fenceGate
        public var id: String { "part-"+rawValue }
        public var name: String {
            switch self {
            case .platformStraight: "直線月台節段"
            case .platformEnd: "月台端部"
            case .islandPlatform: "島式月台"
            case .sidePlatform: "側式月台"
            case .platformCurve: "弧形月台節段"
            case .platformRamp: "月台無障礙坡道"
            case .platformStairs: "月台階梯"
            case .platformCanopy: "月台曲頂雨棚"
            case .canopyEnd: "雨棚端罩"
            case .vColumn: "V 型雨棚柱"
            case .yColumn: "Y 型雨棚柱"
            case .roofTruss: "鋼構屋架"
            case .overbridge: "跨線天橋"
            case .bridgeStairs: "天橋階梯"
            case .escalator: "電扶梯"
            case .liftTower: "透明電梯塔"
            case .fareGate: "驗票閘門"
            case .wideGate: "寬型無障礙閘門"
            case .ticketMachine: "自動售票機"
            case .ticketCounter: "售票櫃檯"
            case .serviceBooth: "服務亭"
            case .informationBoard: "資訊顯示架"
            case .platformSign: "月台指示牌"
            case .exitSign: "出口指示架"
            case .clockPole: "站前時鐘柱"
            case .timetableBoard: "時刻表告示架"
            case .wayfindingPylon: "導引立柱"
            case .tactileStraight: "直行導盲磚"
            case .tactileJunction: "導盲磚轉接"
            case .platformScreenDoors: "全高月台門"
            case .halfHeightScreenDoors: "半高月台門"
            case .safetyFence: "月台安全欄杆"
            case .bench: "有背候車椅"
            case .backlessBench: "無背候車椅"
            case .waitingShelter: "候車小亭"
            case .baggageLocker: "寄物櫃"
            case .drinkingFountain: "飲水設備"
            case .binPair: "分類垃圾桶"
            case .publicPhone: "公共電話亭"
            case .vendingMachine: "無品牌販賣機"
            case .toiletBlock: "公廁模組"
            case .bikeRack: "自行車架"
            case .bikeShelter: "自行車棚"
            case .busShelter: "公車候車亭"
            case .taxiCanopy: "計程車排班雨棚"
            case .bollardRow: "行人防護柱列"
            case .planterBench: "樹池座椅"
            case .stationTree: "站前樹池"
            case .catenaryPortal: "電車線門架"
            case .bufferStop: "軌道止衝擋"
            case .signalMast: "鐵道號誌柱"
            case .relayCabinet: "鐵道控制箱"
            case .utilityHut: "機電小屋"
            case .ventShaft: "地下通風井"
            case .smokeVent: "排煙百葉塔"
            case .stairHead: "樓梯出入口亭"
            case .undergroundExit: "地下站樓梯出口"
            case .stationEntrance: "站房入口框架"
            case .stationRoofWing: "車站挑簷屋頂"
            case .skylight: "屋頂採光罩"
            case .footpathTile: "人行道鋪面"
            case .forecourtTile: "站前廣場鋪面"
            case .lampPole: "站前照明柱"
            case .chargingPoint: "充電停靠柱"
            case .wallPlain: "實牆模組"
            case .wallWindow: "單窗牆模組"
            case .wallTwinWindow: "雙窗牆模組"
            case .wallDoor: "出入門牆模組"
            case .wallShopfront: "商店櫥窗牆"
            case .wallLouver: "百葉機房牆"
            case .wallCorner: "轉角牆模組"
            case .arcadeBay: "騎樓柱跨模組"
            case .floorSlab: "結構樓板"
            case .balcony: "陽台含背牆與門"
            case .balconyCorner: "轉角陽台"
            case .roofParapet: "屋頂女兒牆"
            case .roofAccess: "屋頂樓梯間"
            case .gableRoof: "雙坡屋頂"
            case .hipRoof: "四坡屋頂"
            case .flatRoof: "平屋頂平台"
            case .roofDrain: "屋頂排水口"
            case .downpipe: "外牆落水管"
            case .acBracket: "接牆冷氣支架"
            case .acCondenser: "冷氣室外機"
            case .waterTank: "屋頂水塔"
            case .waterTankStand: "水塔基架"
            case .solarArray: "屋頂太陽能板"
            case .roofDuct: "屋頂風管"
            case .roofFan: "屋頂排風機"
            case .fireEscape: "外牆逃生梯"
            case .externalStairs: "室外階梯"
            case .shopAwning: "商店遮雨棚"
            case .rollerShutter: "鐵捲門框"
            case .blankSign: "無字招牌框"
            case .loadingBay: "貨運裝卸平台"
            case .fenceGate: "圍牆與鐵門"
            }
        }
        public var category: String {
            switch self {
            case .wallPlain,.wallWindow,.wallTwinWindow,.wallDoor,.wallShopfront,.wallLouver,.wallCorner,.arcadeBay,.floorSlab,.balcony,.balconyCorner,.roofParapet,.roofAccess,.gableRoof,.hipRoof,.flatRoof,.roofDrain,.downpipe,.acBracket,.acCondenser,.waterTank,.waterTankStand,.solarArray,.roofDuct,.roofFan,.fireEscape,.externalStairs,.shopAwning,.rollerShutter,.blankSign,.loadingBay,.fenceGate: "building-part"
            default: "station-part"
            }
        }
        public var mount: Mount {
            switch self {
            case .acBracket,.blankSign,.downpipe,.fireEscape,.rollerShutter,.shopAwning,.balcony,.balconyCorner: .wall
            case .acCondenser,.flatRoof,.gableRoof,.hipRoof,.roofAccess,.roofDrain,.roofDuct,.roofFan,.roofParapet,.skylight,.solarArray,.waterTank,.waterTankStand,.canopyEnd,.roofTruss,.stationRoofWing: .roof
            default: .ground
            }
        }
        public var connectors: [Connector] {
            var result=[Connector(name:"mount",position:.zero,normal:mount == .wall ? Map3DPoint(-1,0,0) : Map3DPoint(0,0,-1))]
            switch self {
            case .platformStraight,.sidePlatform,.islandPlatform,.platformCanopy:
                result += [Connector(name:"start",position:Map3DPoint(-4,0,0),normal:Map3DPoint(-1,0,0)),Connector(name:"end",position:Map3DPoint(4,0,0),normal:Map3DPoint(1,0,0))]
            case .floorSlab,.footpathTile,.forecourtTile,.flatRoof:
                for (name,p) in [("front",Map3DPoint(2,0,0)),("back",Map3DPoint(-2,0,0)),("left",Map3DPoint(0,2,0)),("right",Map3DPoint(0,-2,0))] {
                    result.append(Connector(name:name,position:p,normal:p*0.5))
                }
            case .wallPlain,.wallWindow,.wallTwinWindow,.wallDoor,.wallShopfront,.wallLouver,.wallCorner,.arcadeBay,.balcony,.balconyCorner:
                result.append(Connector(name:"next-floor",position:Map3DPoint(0,0,3.2),normal:Map3DPoint(0,0,1)))
            default: break
            }
            return result
        }
    }
}
