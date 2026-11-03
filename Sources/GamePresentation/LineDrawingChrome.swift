// Decision 568: while a new line is picked station by station on the map,
// the screen keeps what that needs and puts the rest away. The owner's
// report (2026-11-03, a phone on its side): the draft's one line stood
// twice, in the map's pill and in the lines panel; the pill lay over the
// layer's legend; the pill's ↶ (the last stop back) stood beside the
// game's own Undo and Redo, two kinds of taking back; and the layer strip,
// the next step, the map's expansion button were all still out.

/// What the screen shows around a new line being picked on the map.
public struct LineDrawingChrome: Equatable, Sendable {
    /// Whether a new line is being picked on the map, its ✓ pill showing
    /// the draft (``GameSession/drawsLineOnMap(linesPanelOpen:)``), outside
    /// the tutorial, whose steps point at the controls as they were.
    public let isDrawing: Bool

    public init(isDrawing: Bool) {
        self.isDrawing = isDrawing
    }

    /// The layer strip under the status pill, with the night skip and the
    /// next step beside it, or the map's round layers button in its place.
    public var showsLayers: Bool { !isDrawing }
    /// The map's button that starts expanding the map.
    public var showsMapExpansion: Bool { !isDrawing }
    /// The game's Undo and Redo: the pill's ↶ takes back the last stop
    /// instead, the one taking back while drawing.
    public var showsWorldEdits: Bool { !isDrawing }
    /// The layer's legend, folded to its title row whatever the player
    /// left it as, so the pill has room above it; it opens as before after.
    public var foldsLegend: Bool { isDrawing }
    /// The draft's one line and what opening it brings in the lines panel:
    /// the pill says them, so the panel keeps the stations alone.
    public var panelShowsSummary: Bool { !isDrawing }
}

extension GameSession {
    /// Whether the map's ✓ pill is the new line's: a new line is being
    /// picked (``mapLineDraft``) and a tap on the map picks its stations,
    /// beside the lines panel or with Select while no tile of the map is
    /// being chosen; no network preview has the pill.
    public func drawsLineOnMap(linesPanelOpen: Bool) -> Bool {
        // As ``mapLineDraft``, without working out its words: a station
        // picked is still on the map.
        lineDraft.contains { world.station(id: $0) != nil }
            && (linesPanelOpen || (tool == .select && !isChoosingMapTile))
            && networkPreview == nil
    }

    /// What the screen shows around a new line picked on the map
    /// (decision 568).
    public func lineDrawingChrome(linesPanelOpen: Bool) -> LineDrawingChrome {
        LineDrawingChrome(isDrawing: tutorial == nil && drawsLineOnMap(linesPanelOpen: linesPanelOpen))
    }
}
