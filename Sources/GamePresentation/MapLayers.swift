import Foundation
import GameCore

/// Presentation preferences for map overlays and informational details.
///
/// Kept by presentation views, never by GameCore or the save format.
public struct MapLayerPreferences: Equatable, Hashable, Sendable {
    /// Whether station names are drawn on the map.
    public var showsStationNames: Bool
    /// Whether waiting passenger count badges are drawn at stations.
    public var showsWaitingCounts: Bool
    /// Whether 800m station catchment service circles are drawn.
    public var showsCatchmentRings: Bool

    public init(
        showsStationNames: Bool = true,
        showsWaitingCounts: Bool = true,
        showsCatchmentRings: Bool = true
    ) {
        self.showsStationNames = showsStationNames
        self.showsWaitingCounts = showsWaitingCounts
        self.showsCatchmentRings = showsCatchmentRings
    }

    /// The default layer preferences for a standard view.
    public static let `default` = MapLayerPreferences()
}

/// Namespace for map layer calculations and presentation data derivations.
public enum MapLayers {
    /// Station catchment radius in metres (800 metres, ~10 minutes walk).
    public static var catchmentRadiusMetres: Double {
        StationDemand.catchmentRadius
    }

    /// Station catchment radius in world units (800 metres × 64 units/metre = 51,200 world units).
    public static var catchmentRadiusWorldUnits: Double {
        catchmentRadiusMetres * Double(WorldCoordinate.unitsPerMetre)
    }

    /// Calculates the screen radius in points for the catchment area at the given projection scale.
    public static func catchmentScreenRadius(pointsPerUnit: Double) -> Double {
        catchmentRadiusWorldUnits * pointsPerUnit
    }

    /// Derives a snapshot of waiting passenger counts for each station in the world.
    ///
    /// Provides explicit Equatable dependency for MapCanvas to redraw when waiting counts change.
    public static func waitingPassengerCounts(in world: GameWorld) -> [StationID: Int64] {
        var counts: [StationID: Int64] = [:]
        counts.reserveCapacity(world.stations.count)
        for station in world.stations {
            counts[station.id] = world.waitingPassengers(at: station.id).reduce(Int64(0)) { $0 + $1.count }
        }
        return counts
    }
}
