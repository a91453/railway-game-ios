import GameCore

// Decision 224, option 5B: the layers used most, one tap each in a strip on
// the map, beside the full layer list; and option 6C: the station master
// wears the company's title (decision 181), with how far it is to the next.

/// A layer the map's quick strip turns on and off: the same settings as
/// the layer list (``MapLayerPreferences``).
public enum MapQuickLayer: CaseIterable, Hashable, Sendable {
    case stationNames
    case waitingCounts
    case passengerLoad
    case population

    /// Its short name under its button.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .stationNames: language.text("Names", "站名")
        case .waitingCounts: language.text("Waiting", "候車")
        case .passengerLoad: language.text("Load", "載客量")
        case .population: language.text("People", "人口")
        }
    }

    /// Its SF Symbol, the one the layer list gives it.
    public var symbolName: String {
        switch self {
        case .stationNames: "character.textbox"
        case .waitingCounts: "person.2"
        case .passengerLoad: "chart.bar.xaxis"
        case .population: "person.3.sequence"
        }
    }

    /// Whether it is on in `layers`.
    public func isOn(in layers: MapLayerPreferences) -> Bool {
        switch self {
        case .stationNames: layers.showsStationNames
        case .waitingCounts: layers.showsWaitingCounts
        case .passengerLoad: layers.shows(.sectionFlow)
        case .population: layers.shows(.population)
        }
    }

    /// `layers` with it turned the other way. Load and people are two of
    /// the layers shown one at a time: turning one on turns the other off.
    public func toggled(_ layers: MapLayerPreferences) -> MapLayerPreferences {
        var layers = layers
        let on = !isOn(in: layers)
        switch self {
        case .stationNames: layers.showsStationNames = on
        case .waitingCounts: layers.showsWaitingCounts = on
        case .passengerLoad: layers.setShows(.sectionFlow, on)
        case .population: layers.setShows(.population, on)
        }
        return layers
    }
}

/// The company's title the station master wears (decision 224, 6C).
public struct StationMasterTitle: Equatable, Sendable {
    public let title: CompanyTitle
    /// How far the score is from this title to the next, 0 to 1; 1 for the
    /// top title.
    public let progress: Double

    public init(rank: CompanyRank) {
        title = rank.title
        if let next = rank.title.next {
            let span = max(1, next.minimumScore - rank.title.minimumScore)
            progress = min(1, max(0, Double(rank.score - rank.title.minimumScore) / Double(span)))
        } else {
            progress = 1
        }
    }

    /// Shown in free play only: a scenario has its own goals and ratings.
    public static func isShown(in world: GameWorld) -> Bool {
        world.scenario == nil
    }
}
