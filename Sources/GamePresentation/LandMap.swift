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

    /// The city's buildings within 800 m of station `id` (Phase 6c-1), by
    /// height: "Buildings within 800 m: low-rise 120 · mid-rise 30 ·
    /// high-rise 5 · towers 1 · existing stock 2" (D1 to D4, each left out
    /// when there are none), or `nil` when none stand there or the station
    /// does not exist.
    public func catchmentBuildingsText(of id: StationID, in language: DisplayLanguage) -> String? {
        guard let buildings = catchmentBuildings(of: id), !buildings.isEmpty else { return nil }
        let names: [(BuildingDensity, String, String)] = [
            (.d1, "low-rise", "低層"), (.d2, "mid-rise", "中層"), (.d3, "high-rise", "高層"), (.d4, "towers", "超高層"),
        ]
        var parts: [(String, String)] = []
        for (density, english, chinese) in names {
            let count = buildings.count { $0.kind == .city && $0.density == density }
            if count > 0 {
                let number = Money(Int64(count)).displayText
                parts.append(("\(english) \(number)", "\(chinese) \(number) 棟"))
            }
        }
        let stock = buildings.count { $0.kind == .existingStock }
        if stock > 0 {
            let number = Money(Int64(stock)).displayText
            parts.append(("existing stock \(number)", "既有存量 \(number) 棟"))
        }
        return language.text(
            "Buildings within 800 m: " + parts.map(\.0).joined(separator: " · "),
            "800 公尺內建物：" + parts.map(\.1).joined(separator: " · ")
        )
    }
}
