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
    /// Which of the population and travel layers is drawn (the reference's
    /// `G.popTravelMode` while `G.popTravelMapLayerEnabled`), or `nil` for
    /// none. Only one at a time, as in the reference's map layer panel.
    public var popTravelMode: PopTravelMode?

    public init(
        showsStationNames: Bool = true,
        showsWaitingCounts: Bool = true,
        showsCatchmentRings: Bool = true,
        popTravelMode: PopTravelMode? = nil
    ) {
        self.showsStationNames = showsStationNames
        self.showsWaitingCounts = showsWaitingCounts
        self.showsCatchmentRings = showsCatchmentRings
        self.popTravelMode = popTravelMode
    }

    /// Whether the population grid is drawn (the reference's
    /// `layer-toggle-population-grid`). Turning it on shows population in
    /// place of another layer; turning it off hides it only when it is the
    /// one shown (`togglePopTravelLayerFromMapPanel`).
    public var showsPopulationHeatmap: Bool {
        get { popTravelMode == .population }
        set { setShows(.population, newValue) }
    }

    /// Whether layer `mode` is the one drawn.
    public func shows(_ mode: PopTravelMode) -> Bool {
        popTravelMode == mode
    }

    /// Turns layer `mode` on, in place of any other, or off when it is the
    /// one shown (`togglePopTravelLayerFromMapPanel(mode, checked)`).
    public mutating func setShows(_ mode: PopTravelMode, _ shows: Bool) {
        if shows {
            popTravelMode = mode
        } else if popTravelMode == mode {
            popTravelMode = nil
        }
    }

    /// The default layer preferences for a standard view.
    public static let `default` = MapLayerPreferences()
}

/// Namespace for map layer calculations and presentation data derivations.
public enum MapLayers {
    /// Station catchment radius in metres: 800 m, ~10 minutes' walk (the
    /// reference's `metroFlowCatchmentRadiusForType`, which uses 400 m only
    /// for APM and sky rail lines; the game has no such line types).
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
