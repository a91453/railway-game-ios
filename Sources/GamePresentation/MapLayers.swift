import Foundation

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
