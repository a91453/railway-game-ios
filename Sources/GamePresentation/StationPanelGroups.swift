// The station panel's groups (decision 472, UI health check N, 3-28): the
// panel's twenty-odd sections in four groups, the everyday ones first,
// each but the first folded or unfolded by its heading and reached from
// the toolbar's menu. Which section sits in which group,
// and which group a tutorial step's button is in, is decided here so a
// Linux test can hold it; the app draws the sections in this order.

/// A group of the station panel's sections.
public enum StationPanelGroup: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Platforms, trains due, the way to another station, how the station
    /// runs, depots and transfers: what a player opens a station for.
    case operations
    /// Trips by hour, who waits and where they go, the station's demand
    /// and events.
    case riders
    /// Shops, the real station, the people, land, roads and buses round it.
    case area
    /// The freight yard and demolishing the station.
    case freight

    public var id: String { rawValue }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .operations: language.text("Operations", "營運")
        case .riders: language.text("Riders", "旅客與運量")
        case .area: language.text("Surroundings", "周邊與土地")
        case .freight: language.text("Freight & Removal", "貨運與拆除")
        }
    }

    /// Its SF Symbol, beside the title.
    public var systemImage: String {
        switch self {
        case .operations: "tram.fill"
        case .riders: "chart.bar.fill"
        case .area: "building.2.fill"
        case .freight: "shippingbox.fill"
        }
    }

    /// Whether it has a heading that folds it. The first group has none:
    /// the panel opens on its rows exactly as before the groups, so a
    /// short panel (a phone on its side) still shows them at once.
    public var isFoldable: Bool {
        self != .operations
    }

    /// Its sections, in the order the panel shows them.
    public var parts: [StationPanelPart] {
        StationPanelPart.allCases.filter { $0.group == self }
    }

    /// The group holding the panel button tutorial target `target`, or
    /// `nil` for a target that is not in the station panel.
    public static func holding(_ target: TutorialTarget) -> StationPanelGroup? {
        StationPanelPart.allCases.first { $0.tutorialTargets.contains(target) }?.group
    }

    /// The group a map bubble's tap opens the panel at (decision 477), or
    /// `nil` for the panel's top: a town short of materials at its freight
    /// group, whose first row says what the town is short of and whose
    /// yard brings them.
    public static func answering(_ alert: MapAlert.Kind) -> StationPanelGroup? {
        switch alert {
        case .materialsShort: .freight
        default: nil
        }
    }
}

/// One section of the station panel, in the panel's order.
public enum StationPanelPart: String, CaseIterable, Hashable, Sendable {
    // Operations.
    case buyLine, operations, departureBoard, journey, rename, operationMode, depot, transfer, platforms
    // Riders.
    case tripsByHour, passengers, demand, events, tripsByStation
    // Surroundings.
    case commerce, realStation, catchment, land, road, bus
    // Freight and removal.
    case freight, removal

    public var group: StationPanelGroup {
        switch self {
        case .buyLine, .operations, .departureBoard, .journey, .rename, .operationMode, .depot, .transfer, .platforms:
            .operations
        case .tripsByHour, .passengers, .demand, .events, .tripsByStation:
            .riders
        case .commerce, .realStation, .catchment, .land, .road, .bus:
            .area
        case .freight, .removal:
            .freight
        }
    }

    /// The tutorial's panel buttons in it (``TutorialStep/revealsInPanel``).
    public var tutorialTargets: [TutorialTarget] {
        self == .freight ? [.freightYard] : []
    }
}

/// Which of the station panel's groups are folded: kept between stations
/// and launches as their names joined by commas. All are unfolded at
/// first, so every control is where a lesson or a player last found it.
public struct StationPanelFolds: Hashable, Sendable {
    public private(set) var folded: Set<StationPanelGroup>

    public init(_ folded: Set<StationPanelGroup> = []) {
        self.folded = folded
    }

    /// Read from its stored text; a name it does not know is left out.
    public init(stored: String) {
        folded = Set(stored.split(separator: ",").compactMap { StationPanelGroup(rawValue: String($0)) }.filter(\.isFoldable))
    }

    /// The text it is stored as, in the groups' order.
    public var stored: String {
        StationPanelGroup.allCases.filter(folded.contains).map(\.rawValue).joined(separator: ",")
    }

    public func isFolded(_ group: StationPanelGroup) -> Bool {
        folded.contains(group)
    }

    public mutating func toggle(_ group: StationPanelGroup) {
        guard group.isFoldable else { return }
        if folded.contains(group) { folded.remove(group) } else { folded.insert(group) }
    }

    /// Unfolds `group`, as jumping to it or a lesson asking for a button
    /// in it does.
    public mutating func unfold(_ group: StationPanelGroup) {
        folded.remove(group)
    }
}
