// The map layer's legend, folded to its title and colour bar (TestFlight
// 59.1: "the legend is too big to see the map", on an iPhone held
// sideways). Folded, it starts on a short screen; the player's own choice
// is kept as a device preference, not in the save. The `Ci/` reference's
// legends (`.map-overlay-legend`) only show or hide with their layer:
// native.

/// Whether the map layer's legend is folded, as a stored preference.
public enum LegendFold {
    /// The `UserDefaults` key: 0 not chosen yet, 1 folded, 2 open.
    public static let key = "mapLegendFold"

    /// Whether the legend shows folded: as the player last left it, else
    /// folded on a short screen (a phone held sideways) and open on others.
    ///
    /// Beside a card or panel that takes more than a third of the width (a
    /// phone's, where the legend then stands in the middle of the map over
    /// its stations, #593), folded whatever was stored, unless the player
    /// opened it there (`openedBesideCard`, not stored: it folds again
    /// beside the next card).
    public static func isFolded(stored: Int, compactHeight: Bool, besideCard: Bool = false, openedBesideCard: Bool = false) -> Bool {
        if besideCard { return !openedBesideCard }
        return switch stored {
        case 1: true
        case 2: false
        default: compactHeight
        }
    }

    /// The stored value for the player's choice.
    public static func stored(folded: Bool) -> Int {
        folded ? 1 : 2
    }
}
