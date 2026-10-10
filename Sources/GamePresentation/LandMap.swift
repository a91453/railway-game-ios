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

    /// The cells of land within 800 m of station `id` by their building's
    /// density (Phase 6c-1, one building a cell): "Cells within 800 m by
    /// density: low-rise 120 · mid-rise 30 · high-rise 5 · towers 1 ·
    /// existing stock 2" (D1 to D4, each left out when there are none), or
    /// `nil` when no building stands there or the station does not exist.
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
                parts.append(("\(english) \(number)", "\(chinese) \(number) 格"))
            }
        }
        let stock = buildings.count { $0.kind == .existingStock }
        if stock > 0 {
            let number = Money(Int64(stock)).displayText
            parts.append(("existing stock \(number)", "既有存量 \(number) 格"))
        }
        return language.text(
            "Cells within 800 m by density: " + parts.map(\.0).joined(separator: " · "),
            "800 公尺內各密度的格：" + parts.map(\.1).joined(separator: " · ")
        )
    }

    /// What station `id`'s town growth measured at the last midnight and
    /// whether it raises the city's buildings (Phase 6c-2): "Yesterday:
    /// 100% of trips served · 2 stations reached · buildings 90% full rise",
    /// or "... · buildings 90% full rise at 80% served and 1 station
    /// reached" (decision 129: nine tenths full is full);
    /// `nil` while the land does not grow there with the city's buildings.
    public func cityGrowthText(of id: StationID, in language: DisplayLanguage) -> String? {
        guard landDemand, cityBuildings, accounts.mode == .management, let place = townGrowth(of: id) else { return nil }
        let percent = "\(place.lastService / 10)%"
        let reached = place.lastReached
        let rises = place.lastService >= LandDemand.upgradeService && place.lastReached >= LandDemand.upgradeReached
        let need = "\(LandDemand.upgradeService / 10)%", full = "\(LandDemand.upgradeFullness / 10)%"
        return language.text(
            "Yesterday: \(percent) of trips served · \(reached) \(reached == 1 ? "station" : "stations") reached · "
                + (rises ? "buildings \(full) full rise" : "buildings \(full) full rise at \(need) served and \(LandDemand.upgradeReached) station reached"),
            "昨日：旅次服務 \(percent) · 可達 \(reached) 站 · "
                + (rises ? "\(full)滿的建物會升級" : "服務達 \(need) 且可達至少 \(LandDemand.upgradeReached) 站時，\(full)滿的建物才會升級")
        )
    }
}
