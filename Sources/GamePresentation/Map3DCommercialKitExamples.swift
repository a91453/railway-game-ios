import Foundation

extension Map3DCommercialKit {
    public enum Example: String, CaseIterable, Sendable {
        case commercialAvenue, nightMarketAlley, stationTransitHub, neighborhoodRetailCorner

        public var id: String { "commercial-example-" + rawValue }

        public var name: String {
            switch self {
            case .commercialAvenue: "繁華商業大道"
            case .nightMarketAlley: "台灣夜市商圈"
            case .stationTransitHub: "站前商業轉運站"
            case .neighborhoodRetailCorner: "社區街角生活商圈"
            }
        }
    }

    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        func add(_ p: Part, _ x: Float, _ y: Float, _ z: Float, angle: Float = 0) {
            b.add(model(for: p), at: Map3DPoint(x, y, z), angle: angle)
        }

        switch example {
        case .commercialAvenue:
            // Ground plaza & road surface
            b.box(0, 0, 0, 36, 44, 0.12, Map3DPalette.plaza)
            b.box(4, 0.12, 0, 8, 44, 0.02, Map3DPalette.road(.primary))
            // Buildings on left
            add(.departmentStore, -9, 0.12, -12)
            add(.cinema, -8, 0.12, 10)
            // Shops & street furniture
            add(.yellowCafe, 12, 0.12, -10, angle: Float.pi)
            add(.cafeUmbrellaSet, 12, 0.12, -3)
            add(.commercialPlanter, 0, 0.12, -6)
            add(.commercialPlanter, 0, 0.12, 6)
            add(.commercialBannerPole, 0, 0.12, -14)
            add(.commercialBannerPole, 0, 0.12, 14)
            // Transit bus driving down avenue
            add(.transitFeederBus, 4, 0.14, 2, angle: Float.pi / 2)

        case .nightMarketAlley:
            // Night market pedestrian alleyway
            b.box(0, 0, 0, 26, 32, 0.12, Map3DPalette.plaza)
            // Left row of food stalls
            add(.ramenYatai, -5, 0.12, -8)
            add(.nightMarketFryer, -5, 0.12, 0)
            add(.nightMarketFruit, -5, 0.12, 8)
            // Right row of game stall & seating
            add(.nightMarketGame, 5, 0.12, -6, angle: Float.pi)
            add(.mobileFoodCart, 5, 0.12, 6, angle: Float.pi)
            // Center dining stools & waste recycling
            add(.commercialRecycling, 0, 0.12, 12)
            add(.aFrameSign, -1, 0.12, -12)
            add(.totemLightbox, 1, 0.12, -12)

        case .stationTransitHub:
            // Station transit interchange with metro entrance, commercial buildings & bus curb
            b.box(0, 0, 0, 34, 38, 0.12, Map3DPalette.plaza)
            // Roadway curb for transit feeder
            b.box(8, 0.12, 0, 7, 38, 0.02, Map3DPalette.road(.minor))
            // Metro entrance pavilion
            add(.metroEntrance, -2, 0.12, -10)
            // Corner office & bank branch
            add(.cornerOffice, -9, 0.12, 8)
            add(.bankBranch, 12, 0.12, 10, angle: Float.pi)
            // Vending machine bank & transit totem
            add(.vendingBank, -2, 0.12, -2)
            add(.totemLightbox, 4.2, 0.12, -12)
            // Low-floor transit feeder bus stopped at curb
            add(.transitFeederBus, 8, 0.14, 0, angle: Float.pi / 2)

        case .neighborhoodRetailCorner:
            // Community retail intersection
            b.box(0, 0, 0, 30, 32, 0.12, Map3DPalette.plaza)
            b.box(0, 0.12, 0, 6, 32, 0.02, Map3DPalette.road(.minor))
            // Supermarket & shophouses
            add(.supermarket, -8, 0.12, -6)
            add(.stackedShopHouse, -7, 0.12, 10)
            // Bakery, pharmacy, bubble tea shop
            add(.bakery, 7, 0.12, -8, angle: Float.pi)
            add(.pharmacy, 7, 0.12, 0, angle: Float.pi)
            add(.bubbleTeaShop, 7, 0.12, 8, angle: Float.pi)
            // Sidewalk signage & cafe umbrella set
            add(.aFrameSign, 4, 0.12, -5)
            add(.cafeUmbrellaSet, 4, 0.12, 11)
            add(.commercialRecycling, -4, 0.12, 3)
        }

        return .flat(named: example.id, from: b.mesh)
    }
}
