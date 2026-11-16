// Decision 803 (BUILD-MODE-CLEAN, the owner, 2026-11-16: the track laying
// screen is still too cluttered): while a building tool is out, the screen
// keeps what the build needs and puts the rest away, as decision 568 did
// for a new line picked on the map. On a phone held sideways the station
// master stood in the lower middle of the map, over the stretch drawn.

/// What the screen shows around the map while a building tool is out.
public struct BuildModeChrome: Equatable, Sendable {
    /// Whether a building tool is out (``ScreenTools/showsBuildingTools(tool:)``),
    /// outside the tutorial, whose steps point at the controls as they are.
    public let isBuilding: Bool
    /// Whether the station master names the first line's steps (decision
    /// 508, "I'll do it myself"): the steps are done with the building
    /// tools, so it stays to say them.
    public let guidesFirstLine: Bool

    public init(isBuilding: Bool, guidesFirstLine: Bool = false) {
        self.isBuilding = isBuilding
        self.guidesFirstLine = guidesFirstLine
    }

    /// The station master in the corner, with its title and its bubble:
    /// back when the tools are put away, remembering what it has said.
    public var showsStationMaster: Bool { !isBuilding || guidesFirstLine }
    /// The small map of the whole world, in the corner over the zoom
    /// buttons.
    public var showsMiniMap: Bool { !isBuilding }
    /// The map's bubbles over its stations (what needs the player) and
    /// where the city's requests point: they lay under the finger that
    /// draws, and a tap on one opened a panel in place of a track point.
    public var showsAlerts: Bool { !isBuilding }
    /// The fares floating up from the stations and the trips stamped full.
    public var showsFaresAndStamps: Bool { !isBuilding }
}

extension GameSession {
    /// What the screen shows around the map while a building tool is out
    /// (decision 803). `guidesFirstLine`: whether the station master is
    /// naming the first line's steps (``FirstLineGuide/hint(in:choice:)``).
    public func buildModeChrome(guidesFirstLine: Bool = false) -> BuildModeChrome {
        BuildModeChrome(
            isBuilding: tutorial == nil && ScreenTools.showsBuildingTools(tool: tool),
            guidesFirstLine: guidesFirstLine
        )
    }
}
