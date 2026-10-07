import GameCore

/// The world's land on the map and in the station panel (Phase 6a,
/// ARCHITECTURE decision 72): derived from ``GameWorld/land`` only, never
/// kept as a second copy of it.
public enum LandMap {
    /// The population layer of a blank map: one square a cell of land with
    /// residents, filled with the population gradient's step for its
    /// residents per km² (a 64 m cell is 0.004096 km², so a cell of 41
    /// residents is some 10,000 a km², the gradient's end). A real-world
    /// map draws WorldPop's grid instead (``PopulationHeatmap``), which its
    /// land comes from.
    public static func tiles(of land: Land) -> [TravelDemandMap.Tile] {
        let length = Double(Land.cellLength)
        let squareKilometres = Double(Land.cellLength * Land.cellLength)
            / Double(WorldCoordinate.unitsPerMetre * WorldCoordinate.unitsPerMetre) / 1_000_000
        return land.cells.compactMap { cell in
            guard cell.residents > 0 else { return nil }
            let band = PopTravel.populationBand(people: Double(cell.residents) / squareKilometres)
            let x = Double(cell.column) * length, y = Double(cell.row) * length
            return TravelDemandMap.Tile(
                minX: x, minY: y, maxX: x + length, maxY: y + length,
                color: PopTravel.populationBandColor(band), value: cell.residents
            )
        }
    }
}

extension GameWorld {
    /// Who lives and works within 800 m of station `id` (Phase 6a): "Within
    /// 800 m: 24,984 residents · 16,614 jobs", or `nil` for a world without
    /// land or a station that does not exist.
    public func landCatchmentText(of id: StationID, in language: DisplayLanguage) -> String? {
        guard !land.isEmpty, let totals = landCatchment(of: id) else { return nil }
        let residents = Money(totals.residents).displayText
        let jobs = Money(totals.jobs).displayText
        return language.text(
            "Within 800 m: \(residents) residents · \(jobs) jobs",
            "800 公尺內：居民 \(residents) 人 · 就業 \(jobs) 個"
        )
    }
}
