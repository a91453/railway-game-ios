import Foundation

extension Map3DCoastalKit {
    public enum Example: String, CaseIterable, Sendable {
        case fishingHarbor, boatyard, seasideCamp, coastRestStop
        public var id: String { "coastal-example-"+rawValue }
        public var name: String { switch self {
        case .fishingHarbor: "小漁港理貨岸"
        case .boatyard: "修船與岸置工作場"
        case .seasideCamp: "海岸露營休憩區"
        case .coastRestStop: "濱海步道休息站"
        } }
    }
    /// Placement positions use native axes. Angles follow StationKitBuilder:
    /// radians, clockwise viewed from +z (x' = c*x+s*y, y' = -s*x+c*y).
    /// The same records build the scene and are exported for subsequent assembly.
    public struct Placement: Sendable {
        public let part: Part
        public let position: Map3DPoint
        public let angle: Float
    }
    public static func placements(for example: Example) -> [Placement] {
        func p(_ part: Part,_ x: Float,_ height: Float,_ right: Float,_ angle: Float = 0) -> Placement {
            .init(part:part,position:Map3DPoint(x,-right,height),angle:angle)
        }
        switch example {
        case .fishingHarbor:
            return [p(.auctionShelter,-5,0.3,-4),p(.fishSortingTable,-4,0.42,-4),p(.insulatedFishCrate,-5.7,0.42,-4),
                    p(.netDryingRack,-5,0.3,3),p(.mooringBollard,0,0.3,-5),p(.lifeRingStand,0,0.3,2),
                    p(.floatingPontoon,4,0.08,-3),p(.motorDinghy,5.5,-0.02,3,Float.pi/2)]
        case .boatyard:
            return [p(.boatWorkshop,-4,0.12,-3),p(.boatTrailer,4,0.12,-3),p(.rowingSkiff,4,0.74,-3),
                    p(.netDryingRack,-4,0.12,3),p(.fishSortingTable,0,0.12,3),p(.insulatedFishCrate,0,1.02,3),p(.slipway,4,0.12,3)]
        case .seasideCamp:
            return [p(.domeTent,-5,0.12,-4),p(.ridgeTent,-4,0.12,4),p(.hammockStand,2,0.12,-5),
                    p(.campKitchen,-1,0.12,0),p(.campTable,3,0.12,0),p(.foldingChair,3,0.12,-1.3,Float.pi/2),
                    p(.foldingChair,3,0.12,1.3,-Float.pi/2),p(.firePit,6,0.12,3),p(.kayakRack,6,0.12,-4)]
        case .coastRestStop:
            return [p(.beaconTower,-5,0.12,-3),p(.coastShelter,1,0.12,-3),p(.lifeguardTower,5,0.12,3),
                    p(.lifeRingStand,1,0.12,2),p(.seawallStairs,-4,0.12,3)]
        }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        if example == .fishingHarbor {
            b.box(-4,0,-1,10,16,0.3,Map3DPalette.concrete)
            b.box(5,-0.15,-1,8,16,0.45,Map3DPalette.water)
        } else { b.box(0,0,0,18,16,0.12,example == .boatyard ? Map3DPalette.concrete:Map3DPalette.forecourt) }
        for p in placements(for:example) {
            b.add(model(for:p.part),at:Map3DPoint(p.position.x,p.position.z,-p.position.y),angle:p.angle)
        }
        return .flat(named:example.id,from:b.mesh)
    }
}
