// Decision 226, later (TestFlight, 2026-10-16): which of the screen's own
// tools show, by the tool chosen and the screen's height. The tutorial uses
// the same controls as the game (its steps had pointed at a dock and a rail
// it alone kept, and at Network where the game shows Build), so each of its
// steps points only at tools that show at that step.

/// The tools on the screen around the map.
public enum ScreenTools {
    /// The building tools and Done (``TutorialTarget/networkTool`` …
    /// ``TutorialTarget/selectTool``): while a tool other than Select is
    /// chosen, the tutorial too.
    public static func showsBuildingTools(tool: ConstructionTool) -> Bool {
        tool != .select
    }

    /// Lines and Data: always in the dock along the bottom (a regular
    /// height: an iPad); in the column of a phone held sideways only while
    /// the building tools are not out, as they take their place.
    public static func showsEntries(tool: ConstructionTool, compactHeight: Bool) -> Bool {
        !compactHeight || !showsBuildingTools(tool: tool)
    }

    /// The tutorial's targets that are tools of the screen: Build, the
    /// building tools and Done, and Lines.
    public static let toolTargets: Set<TutorialTarget> = [
        .buildEntry, .networkTool, .trainTool, .buildingTool, .selectTool, .linesButton,
    ]

    /// Those of ``toolTargets`` that show with `tool` chosen.
    public static func shownTargets(tool: ConstructionTool, compactHeight: Bool) -> Set<TutorialTarget> {
        var shown: Set<TutorialTarget> = [.buildEntry]
        if showsBuildingTools(tool: tool) {
            shown.formUnion([.networkTool, .trainTool, .buildingTool, .selectTool])
        }
        if showsEntries(tool: tool, compactHeight: compactHeight) {
            shown.insert(.linesButton)
        }
        return shown
    }
}
