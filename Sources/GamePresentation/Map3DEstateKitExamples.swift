import Foundation

extension Map3DEstateKit {
    public enum Example: String, CaseIterable, Sendable {
        case amusementPark, resortQuarter, housingEstate, commercialPlaza
        public var id: String { "estate-example-"+rawValue }
        public var name: String { switch self {
        case .amusementPark: "樂園主題區"
        case .resortQuarter: "旅宿街區"
        case .housingEstate: "住宅社區"
        case .commercialPlaza: "商業生活廣場"
        } }
    }
    /// Native coordinates; radians clockwise viewed from +z.
    public struct Placement: Sendable {
        public let part: Part
        public let position: Map3DPoint
        public let angle: Float
    }
    public static func placements(for example: Example) -> [Placement] {
        let category: Category
        switch example {
        case .amusementPark: category = .leisure
        case .resortQuarter: category = .hotel
        case .housingEstate: category = .residential
        case .commercialPlaza: category = .commercial
        }
        return Part.allCases.filter { $0.category==category }.enumerated().map { i,part in
            .init(part:part,position:Map3DPoint(Float(i/3)*28-14,Float(i%3)*26-26,0.16),angle:i/3==0 ? 0:Float.pi)
        }
    }
    public static func model(for example: Example) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        b.box(0,0,0,55,78,0.16,Map3DPalette.forecourt)
        b.box(0,0.16,0,5,78,0.015,Map3DPalette.concrete)
        for p in placements(for:example) { b.add(model(for:p.part),at:Map3DPoint(p.position.x,p.position.z,-p.position.y),angle:p.angle) }
        return .flat(named:example.id,from:b.mesh)
    }
}
