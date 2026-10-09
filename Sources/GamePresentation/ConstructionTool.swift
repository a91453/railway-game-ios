import GameCore

/// What the action button does.
///
/// Presentation state only: the tool is never stored in GameCore, and
/// choosing one changes nothing in the world until the player acts.
public enum ConstructionTool: CaseIterable, Hashable, Sendable {
    /// Inspect stations and trains without changing anything.
    case select
    /// Builds the track network at any angle, its platforms, and removes
    /// it (Stage C1; see ``GameSession/networkMode``).
    case network
    /// Places the selected train at the selected station, or sends it
    /// there once it is on the track (see ``GameSession/applyTool()``).
    case train
    /// Places the chosen building where the player taps (city building
    /// P0-A, decision 92; see ``GameSession/placeBuilding(at:)``).
    case building

    /// The tools the app offers: every tool. Stage F1 left the grid's
    /// track, station and remove tools out of the app; Stage F3c removed
    /// them.
    public static let networkTools: [ConstructionTool] = allCases

    /// Whether choosing the tool pauses a running game (ARCHITECTURE
    /// decision 99): the tools that build and remove. Game time moving on
    /// empties the undo history (decision 82), so an edit made while the
    /// game runs can be undone only until the next tick.
    public var pausesGame: Bool {
        switch self {
        case .network, .building: true
        case .select, .train: false
        }
    }

    /// Short name for the tool picker.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .select: language.text("Select", "選取")
        case .network: language.text("Network", "路網")
        case .train: language.text("Train", "列車")
        case .building: language.text("Buildings", "建物")
        }
    }
}

/// The way a train faces when it is placed (see
/// ``GameSession/placementHeading``): a compass point on the map. A platform
/// runs at any angle, so the train faces the way along it nearer this one.
public enum CompassHeading: CaseIterable, Hashable, Sendable {
    case north
    case east
    case south
    case west

    /// "North", or "北".
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .north: language.text("North", "北")
        case .east: language.text("East", "東")
        case .south: language.text("South", "南")
        case .west: language.text("West", "西")
        }
    }

    /// "N", or "北".
    public func abbreviation(in language: DisplayLanguage) -> String {
        switch self {
        case .north: language.text("N", "北")
        case .east: language.text("E", "東")
        case .south: language.text("S", "南")
        case .west: language.text("W", "西")
        }
    }
}
