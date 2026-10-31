import GameCore

// Decision 509 (100.1, the owner: "怎麼感覺分區功能好像都沒再用", "好像跟建築
// 混在一起了"): zoning was the fourth mode of the building tool, behind
// Put up, Demolish and Sell, and no one found it. It is now a button of
// its own in the building tools, after Buildings: Network, Train,
// Buildings, Zoning, Buses. The button is the building tool in its zoning
// mode (decision 98), so the map's taps, drags and overlay are the ones
// zoning always had; only the way in changed.

/// A button of the building tools, in the order they stand (decision 509).
public enum BuildToolbarButton: CaseIterable, Hashable, Sendable {
    case network
    case train
    case building
    /// The building tool in its zoning mode (decision 98).
    case zoning
    case bus

    /// The tool it chooses.
    public var tool: ConstructionTool {
        switch self {
        case .network: .network
        case .train: .train
        case .building, .zoning: .building
        case .bus: .bus
        }
    }

    /// Its name under its icon.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .zoning: language.text("Zoning", "分區")
        default: tool.title(in: language)
        }
    }

    /// Its accessibility identifier: the tool's (`tool.building`), as the
    /// UI tests have always named them, and `tool.zoning`.
    public var identifier: String {
        self == .zoning ? "tool.zoning" : "tool.\(tool)"
    }
}

extension BuildingToolMode {
    /// The modes the building tool's own picker offers: zoning has its own
    /// button (decision 509).
    public static let buildingModes: [BuildingToolMode] = [.build, .demolish, .sell]
}

extension GameSession {
    /// The building tools offered, in order: in a lesson only those it has
    /// unlocked (decision 266), zoning with the building tool.
    public var buildToolbarButtons: [BuildToolbarButton] {
        BuildToolbarButton.allCases.filter { allows($0.tool) }
    }

    /// Whether `button` is the one chosen.
    public func isChosen(_ button: BuildToolbarButton) -> Bool {
        guard tool == button.tool else { return false }
        switch button {
        case .building: return buildingMode != .zone
        case .zoning: return buildingMode == .zone
        default: return true
        }
    }

    /// Chooses `button`: its tool, and for the building tool the mode it
    /// stands for. A button chosen again stays chosen.
    public func choose(_ button: BuildToolbarButton) {
        selectTool(button.tool)
        switch button {
        case .zoning where buildingMode != .zone: buildingMode = .zone
        case .building where buildingMode == .zone: buildingMode = .build
        default: break
        }
    }
}
