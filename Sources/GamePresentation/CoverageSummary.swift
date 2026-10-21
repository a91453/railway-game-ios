import GameCore

// Decision 292 (City Transport Manager study 4.0, step M1): while a station
// or a line is being built, one tap shows the catchment coverage layer
// (``PopTravelMode/coverage``, decision 76) and another, or leaving the
// tool, puts back the layer the player had (decision 311 shows it, or where
// people are, as soon as building begins: ``BuildingLayerShortcut``). Its key says how much of the
// map's residents and jobs the stations reach. That is an estimate: a cell
// counts when its middle is within 800 m of a station in a straight line,
// whatever the trains' service or the way on foot, so the key says so; a
// cell two stations reach counts once; a map with no land says "—", not 0%.

/// How many of the map's residents and jobs live or work within a
/// station's catchment (decision 292).
public struct CoverageSummary: Equatable, Sendable {
    /// Residents and jobs on the map's land.
    public let people: Int64
    /// Of ``people``, those in the cells a station reaches.
    public let covered: Int64

    public init(people: Int64, covered: Int64) {
        self.people = people
        self.covered = covered
    }

    init(world: GameWorld, covered cells: Set<CellPosition>, rows: Int, columns: Int) {
        var people: Int64 = 0, covered: Int64 = 0
        for cell in world.land.cells where cell.row < rows && cell.column < columns {
            let here = cell.residents + cell.jobs
            people += here
            if cells.contains(CellPosition(row: cell.row, column: cell.column)) { covered += here }
        }
        self.init(people: people, covered: covered)
    }

    /// The share reached, in whole percent rounded down, so 100 only when
    /// everyone is; `nil` with no one on the map.
    public var percent: Int64? {
        guard people > 0 else { return nil }
        return covered * 100 / people
    }

    /// "62%", "under 1%", or "—" with no one on the map.
    public func shareText(in language: DisplayLanguage) -> String {
        guard let percent else { return "—" }
        if percent == 0, covered > 0 { return language.text("under 1%", "不到 1%") }
        return "\(percent)%"
    }

    /// The key's line: what share, and that it is an estimate.
    public func text(in language: DisplayLanguage) -> String {
        let share = shareText(in: language)
        return language.text(
            "Residents and jobs within 800 m of a station: \(share) (straight-line estimate)",
            "車站 800 公尺內的居民與工作：\(share)（直線範圍的估算）"
        )
    }
}

extension GameWorld {
    /// How many of the residents and jobs the stations reach
    /// (``CoverageSummary``), as the coverage layer counts them.
    public func catchmentCoverage() -> CoverageSummary {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        return CoverageSummary(world: self, covered: CityMap.coveredCells(of: self, rows: rows, columns: columns), rows: rows, columns: columns)
    }
}

extension GameSession {
    /// Whether the map offers the building layer's switch (decisions 292
    /// and 311, ``BuildingLayerShortcut``): while a track or a platform is
    /// being placed, or a new line's stations are picked; not in the
    /// tutorial, whose card leads.
    public var offersCoverageShortcut: Bool {
        guard tutorial == nil else { return false }
        if tool == .network, networkMode == .build || networkMode == .platform { return true }
        return isPickingLineStops || !lineDraft.isEmpty
    }
}
