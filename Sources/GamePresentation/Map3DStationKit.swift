import Foundation

/// On-demand station and construction assets. This does not change map
/// placement, station capacity, track geometry or authoritative game state.
public enum Map3DStationKit {
    public enum Profile: String, Sendable, CaseIterable {
        case taipei, taichung, kaohsiung, hsinchu, tainan, chiayi, keelung
        case nangang, banqiao, hualien, taitung, zuoying
        case hsrTaichung, hsrTaoyuan, hsrHsinchu, hsrTainan
        case timber, heritage, formosa, centralPark
        case regional, halt, elevated, underground, lightRail, highSpeed
    }
    public struct Station: Sendable {
        public let id: String
        public let name: String
        public let system: String
        public let latitude: Double
        public let longitude: Double
        public let lines: [String]
        public let profile: Profile
        public let tier: Int
        public let seed: UInt32
        public let planned: Bool
        public let isLandmark: Bool
    }
    public enum Mount: String, Sendable { case ground, wall, roof }
    public struct Connector: Sendable {
        public let name: String
        /// Native model coordinates: x front, y left, z up, metres.
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public static func station(id: String) -> Station? { stations.first { $0.id==id } }
    public static func model(for station: Station) -> Map3DModelPack.Model {
        var builder=StationKitBuilder();builder.station(station)
        return .flat(named:station.id,from:builder.mesh)
    }
    public static func model(for part: Part) -> Map3DModelPack.Model {
        var builder=StationKitBuilder();builder.part(part)
        return .flat(named:part.id,from:builder.mesh)
    }
    public static func model(id: String) -> Map3DModelPack.Model? {
        if let station=station(id:id) { return model(for:station) }
        if let part=Part.allCases.first(where:{ $0.id==id }) { return model(for:part) }
        if id=="station-kit-example" { return exampleModel() }
        return nil
    }
    /// A complete modular assembly, with furniture outside the walking lane.
    public static func exampleModel() -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        b.box(0,0,0,40,44,0.2,Map3DPalette.plaza)
        for z: Float in [-6,6] {
            b.add(model(for:.platformStraight),at:Map3DPoint(-10,0.2,z))
            b.add(model(for:.platformStraight),at:Map3DPoint(-2,0.2,z))
            b.add(model(for:.platformCanopy),at:Map3DPoint(-10,1.4,z))
            b.add(model(for:.platformCanopy),at:Map3DPoint(-2,1.4,z))
            // The ramp's HIGH end meets x=2, the last platform's edge.
            b.add(model(for:.platformRamp),at:Map3DPoint(4,0.2,z),angle:.pi)
            b.add(model(for:.bench),at:Map3DPoint(-11,1.4,z))
        }
        b.track(-15,5,0,at:0.2)
        b.add(model(for:.overbridge),at:Map3DPoint(-13,1.4,0))
        b.add(model(for:.stationEntrance),at:Map3DPoint(12,0.2,0))
        for z: Float in [-15,-11,11,15] { b.add(model(for:.arcadeBay),at:Map3DPoint(10,0.2,z)) }
        for z: Float in [-7,0,7] { b.add(model(for:.fareGate),at:Map3DPoint(9,0.2,z)) }
        b.add(model(for:.ticketMachine),at:Map3DPoint(15,0.2,-9))
        b.add(model(for:.waitingShelter),at:Map3DPoint(15,0.2,11))
        b.add(model(for:.stationTree),at:Map3DPoint(15,0.2,18))
        return .flat(named:"station-kit-example",from:b.mesh)
    }
}

extension Map3DModelPack {
    /// Callers select the handful of assets they need, rather than loading
    /// the entire station catalog into a live map.
    public init(stationKit stations: [Map3DStationKit.Station],parts: [Map3DStationKit.Part] = [],includeStandard: Bool = true) {
        models=(includeStandard ? Self.standard.models : [])+stations.map(Map3DStationKit.model(for:))+parts.map(Map3DStationKit.model(for:))
    }
}
