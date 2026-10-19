import GameCore

/// A new line drawn on the map while its stations are picked (decision
/// 100, later: the line is built on the map, its ✓ beside the last station
/// picked, so a phone need not open the lines panel): the stations it will
/// call at, in order, the ones the player tapped (numbered on the map), and
/// what the ✓ says.
public struct MapLineDraft: Equatable, Sendable {
    /// The stations the line will call at, in order (``GameSession/lineDraftStops``).
    public let calls: [PlanPoint]
    /// The stations picked, in the order they were tapped.
    public let picked: [PlanPoint]
    /// Where the ✓ goes under: the last station picked.
    public let anchor: PlanPoint
    /// One line over the ✓: the draft's summary (``GameSession/lineDraftSummary``),
    /// and what opening the line brings; or what to tap next.
    public let caption: String
    /// Whether the ✓ can create the line: two stops or more.
    public let canCreate: Bool
    /// Decision 264: what opening it costs and brings under simple rules.
    public var opening: LineOpeningPreview? = nil
}

/// A station on the map that can join the selected line (decision 196,
/// later: tapping a station adds it to a line on the map).
public struct MapStopSuggestion: Equatable, Sendable {
    public let station: StationID
    public let line: LineID
    /// Where the button goes under: the station.
    public let anchor: PlanPoint
    /// "Add Gamma to Main".
    public let caption: String
}

extension GameSession {
    /// The new line on the map while its stations are picked, or `nil`
    /// when none is being picked.
    public var mapLineDraft: MapLineDraft? {
        guard isPickingLineStops || !lineDraft.isEmpty else { return nil }
        let picked = lineDraft.compactMap { world.station(id: $0)?.point }
        guard let anchor = picked.last else { return nil }
        let stops = lineDraftStops
        let calls = stops.compactMap { world.station(id: $0)?.point }
        let canCreate = stops.count >= 2
        let caption: String
        if !canCreate {
            caption = language.text("Tap the line's next station", "點路線的下一站")
        } else {
            // The draft's one line (CTM study 4.2): its stops, length,
            // time and price, or why no track joins them.
            caption = lineDraftSummary?.text ?? ""
        }
        let opening = canCreate ? lineOpeningPreview : nil
        return MapLineDraft(
            calls: calls, picked: picked, anchor: anchor,
            caption: opening.map { caption + "\n" + $0.contentsText(in: language) } ?? caption, canCreate: canCreate, opening: opening
        )
    }

    /// The selected station, when the selected line does not call at it
    /// and no new line is being picked: it can join that line, where it
    /// fits (``addStationToSelectedLine(_:)``).
    public var mapStopSuggestion: MapStopSuggestion? {
        guard !isPickingLineStops, lineDraft.isEmpty,
              let station = selectedStation, let line = selectedLine,
              !line.stops.contains(station.id) else { return nil }
        return MapStopSuggestion(
            station: station.id,
            line: line.id,
            anchor: station.point,
            caption: language.text("Add \(station.name) to \(line.name)", "把 \(station.name) 加入 \(line.name)")
        )
    }
}
