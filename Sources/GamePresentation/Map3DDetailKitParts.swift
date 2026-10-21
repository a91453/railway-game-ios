import Foundation

extension Map3DDetailKit {
    public enum Category: String, CaseIterable, Sendable { case rail, building, interior, street, life, moving }
    public enum Part: String, CaseIterable, Sendable {
        case jointFishplate, railFastener, concreteSleeper, woodSleeper, guardRail, turnoutLinkage, pointMotor, insulatedJoint, catenaryInsulator, tensionWeights, cableTrough, cableTroughCorner, trackDrain, axleCounter, derailDevice, maintenanceWalkway
        case windowGrille, grilleBay, awningBrace, wallPipeStraight, wallPipeElbow, wallPipeTee, meterBox, meterBank, gasCylinder, gasCage, tileCorner, corrugatedExtension, wallCableTray, pipeClamp, wallTap, wallVentHood
        case cctvCamera, domeCamera, paSpeaker, hornSpeaker, emergencyIntercom, fireCabinet, aedCabinet, queuePost, queueBelt, baggageTrolley, routeMapCase, ceilingLight, pendantLight, fireExtinguisher, cleaningCart, lostPropertyShelf
        case curbStraight, curbCorner, gutterGrate, manholeCover, catchBasin, trafficCone, convexMirror, guardrailEnd, roadBarrier, wheelStop, hydrant, drainOutlet, utilityCover, treeGrate, parkingMeter, temporaryFence
        case shopShelf, chestFreezer, cartonClosed, cartonOpen, stackingCrate, foldingChair, plantRack, dryingRack, laundryBasket, pallet, produceDisplay, handTruck, shopCounter, riceSack, plasticStool, parcelStack
        case hingedDoor, shutterSlat, gateFlap, wheelset, connectingRod, slidingDoor, barrierArm, ventFan, foldingGate, cabinetDoor, trolleyCaster, turnoutBlade, roofHatch, escalatorStep, platformDoorLeaf, serviceWindow
        public var id: String { "detail-"+rawValue }
        public var name: String { switch self {
            case .jointFishplate: "鋼軌接頭夾板"
            case .railFastener: "鋼軌扣件"
            case .concreteSleeper: "混凝土枕木"
            case .woodSleeper: "木枕"
            case .guardRail: "護軌段"
            case .turnoutLinkage: "轉轍器連桿座"
            case .pointMotor: "轉轍機"
            case .insulatedJoint: "絕緣接頭"
            case .catenaryInsulator: "電車線絕緣子"
            case .tensionWeights: "電車線張力墜砣"
            case .cableTrough: "電纜槽直段"
            case .cableTroughCorner: "電纜槽轉角"
            case .trackDrain: "軌旁排水槽"
            case .axleCounter: "軸計數器"
            case .derailDevice: "止輪脫軌器"
            case .maintenanceWalkway: "軌旁維修走道"
            case .windowGrille: "平面鐵窗"
            case .grilleBay: "外凸鐵窗籠"
            case .awningBrace: "雨遮三角支架"
            case .wallPipeStraight: "外牆管線直段"
            case .wallPipeElbow: "外牆管線彎頭"
            case .wallPipeTee: "外牆管線三通"
            case .meterBox: "電表箱"
            case .meterBank: "集中電表組"
            case .gasCylinder: "桶裝瓦斯"
            case .gasCage: "瓦斯桶防護籠"
            case .tileCorner: "磁磚牆角"
            case .corrugatedExtension: "鐵皮加蓋"
            case .wallCableTray: "壁掛電纜橋架"
            case .pipeClamp: "管線固定環"
            case .wallTap: "外牆水龍頭"
            case .wallVentHood: "排風防雨罩"
            case .cctvCamera: "支架監視器"
            case .domeCamera: "半球監視器"
            case .paSpeaker: "廣播音箱"
            case .hornSpeaker: "號角喇叭"
            case .emergencyIntercom: "緊急對講機"
            case .fireCabinet: "消防箱"
            case .aedCabinet: "AED 設備箱"
            case .queuePost: "排隊欄柱"
            case .queueBelt: "排隊伸縮帶"
            case .baggageTrolley: "行李推車"
            case .routeMapCase: "路網圖框"
            case .ceilingLight: "嵌頂長燈"
            case .pendantLight: "吊掛燈"
            case .fireExtinguisher: "滅火器"
            case .cleaningCart: "清潔推車"
            case .lostPropertyShelf: "失物保管架"
            case .curbStraight: "路緣石直段"
            case .curbCorner: "路緣石轉角"
            case .gutterGrate: "水溝蓋"
            case .manholeCover: "圓形人孔蓋"
            case .catchBasin: "集水井"
            case .trafficCone: "交通錐"
            case .convexMirror: "道路反光鏡"
            case .guardrailEnd: "護欄端頭"
            case .roadBarrier: "道路阻隔墩"
            case .wheelStop: "停車擋輪塊"
            case .hydrant: "消防栓"
            case .drainOutlet: "排水出口"
            case .utilityCover: "設備井蓋"
            case .treeGrate: "樹穴格柵"
            case .parkingMeter: "停車計費柱"
            case .temporaryFence: "活動施工圍籬"
            case .shopShelf: "商店貨架"
            case .chestFreezer: "上掀冷凍櫃"
            case .cartonClosed: "封口紙箱"
            case .cartonOpen: "開口紙箱"
            case .stackingCrate: "塑膠周轉籃"
            case .foldingChair: "折疊椅"
            case .plantRack: "盆栽架"
            case .dryingRack: "曬衣架"
            case .laundryBasket: "洗衣籃"
            case .pallet: "棧板"
            case .produceDisplay: "蔬果陳列台"
            case .handTruck: "搬貨手推車"
            case .shopCounter: "商店櫃檯"
            case .riceSack: "米袋"
            case .plasticStool: "塑膠矮凳"
            case .parcelStack: "包裹疊組"
            case .hingedDoor: "鉸鏈門片"
            case .shutterSlat: "捲門分片"
            case .gateFlap: "閘門擋板"
            case .wheelset: "鐵道輪軸"
            case .connectingRod: "往復連桿"
            case .slidingDoor: "橫移門片"
            case .barrierArm: "升降柵欄"
            case .ventFan: "排風扇葉"
            case .foldingGate: "格柵側開門"
            case .cabinetDoor: "設備箱門片"
            case .trolleyCaster: "推車腳輪"
            case .turnoutBlade: "活動尖軌"
            case .roofHatch: "屋頂檢修蓋"
            case .escalatorStep: "電扶梯踏階"
            case .platformDoorLeaf: "月台門片"
            case .serviceWindow: "服務窗上掀片"
        } }
        public var category: Category { switch self {
            case .jointFishplate, .railFastener, .concreteSleeper, .woodSleeper, .guardRail, .turnoutLinkage, .pointMotor, .insulatedJoint, .catenaryInsulator, .tensionWeights, .cableTrough, .cableTroughCorner, .trackDrain, .axleCounter, .derailDevice, .maintenanceWalkway: .rail
            case .windowGrille, .grilleBay, .awningBrace, .wallPipeStraight, .wallPipeElbow, .wallPipeTee, .meterBox, .meterBank, .gasCylinder, .gasCage, .tileCorner, .corrugatedExtension, .wallCableTray, .pipeClamp, .wallTap, .wallVentHood: .building
            case .cctvCamera, .domeCamera, .paSpeaker, .hornSpeaker, .emergencyIntercom, .fireCabinet, .aedCabinet, .queuePost, .queueBelt, .baggageTrolley, .routeMapCase, .ceilingLight, .pendantLight, .fireExtinguisher, .cleaningCart, .lostPropertyShelf: .interior
            case .curbStraight, .curbCorner, .gutterGrate, .manholeCover, .catchBasin, .trafficCone, .convexMirror, .guardrailEnd, .roadBarrier, .wheelStop, .hydrant, .drainOutlet, .utilityCover, .treeGrate, .parkingMeter, .temporaryFence: .street
            case .shopShelf, .chestFreezer, .cartonClosed, .cartonOpen, .stackingCrate, .foldingChair, .plantRack, .dryingRack, .laundryBasket, .pallet, .produceDisplay, .handTruck, .shopCounter, .riceSack, .plasticStool, .parcelStack: .life
            case .hingedDoor, .shutterSlat, .gateFlap, .wheelset, .connectingRod, .slidingDoor, .barrierArm, .ventFan, .foldingGate, .cabinetDoor, .trolleyCaster, .turnoutBlade, .roofHatch, .escalatorStep, .platformDoorLeaf, .serviceWindow: .moving
        } }
        public var mount: Mount { switch self {
            case .aedCabinet, .awningBrace, .cabinetDoor, .cctvCamera, .drainOutlet, .emergencyIntercom, .fireCabinet, .foldingGate, .grilleBay, .hingedDoor, .hornSpeaker, .meterBank, .meterBox, .paSpeaker, .pipeClamp, .platformDoorLeaf, .routeMapCase, .serviceWindow, .slidingDoor, .tileCorner, .ventFan, .wallCableTray, .wallPipeElbow, .wallPipeStraight, .wallPipeTee, .wallTap, .wallVentHood, .windowGrille: .wall
            case .ceilingLight, .domeCamera, .pendantLight: .ceiling
            case .corrugatedExtension, .roofHatch: .roof
            case .jointFishplate,.railFastener,.guardRail,.insulatedJoint,.axleCounter,.derailDevice,.turnoutBlade: .rail
            default: .ground
        } }
    }
}
