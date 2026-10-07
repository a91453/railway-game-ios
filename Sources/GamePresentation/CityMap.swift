import GameCore

/// The city's map layers (Phase 6d, ARCHITECTURE decision 76): each 64 m
/// cell's use and density, its land value, and the stations' catchment
/// coverage, worked out from the world once (``init(world:)``) and then
/// asked only for what is in view.
///
/// Derived from ``GameWorld`` and never kept as a second copy of it: the
/// map makes a new one when the land, its buildings, the stations or the
/// last measured service change, not on every frame. Like
/// ``PopulationHeatmap``, cells drawn smaller than ``minimumTilePoints`` are
/// merged into square blocks of 2, 4, 8 … cells a side.
///
/// The references have no city layers to port (`Ci/` colours its land use
/// from vector tiles it does not ship; gap): the colours and steps are this
/// project's.
public struct CityMap: Sendable {
    /// The world's cells (``Land/rows(in:)`` × ``Land/columns(in:)``).
    public let rows: Int
    public let columns: Int
    /// Each cell's value in cents a m², by row and then column.
    let values: [Int64]
    /// Each cell's use and density: 0 for no building or land, else
    /// `use × 8 + density` (use 1 homes, 2 shops, 3 offices; density 1–4,
    /// 5 for existing stock).
    let kinds: [UInt8]
    /// Whether a station's catchment reaches each cell.
    let covered: [Bool]
    /// Whether anyone lives or works in each cell.
    let peopled: [Bool]

    /// The smallest a drawn rectangle may be on screen, in points.
    public static let minimumTilePoints = 6.0

    public init(world: GameWorld) {
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        self.rows = rows
        self.columns = columns
        values = world.landValues().map(\.value)
        var kinds = [UInt8](repeating: 0, count: rows * columns)
        var peopled = [Bool](repeating: false, count: rows * columns)
        for cell in world.land.cells where cell.row < rows && cell.column < columns {
            let index = cell.row * columns + cell.column
            peopled[index] = true
            if let building = world.buildings.building(row: cell.row, column: cell.column) {
                let density = building.kind == .existingStock ? 5 : building.density.rawValue
                kinds[index] = UInt8(Self.useCode(building.use) * 8 + density)
            } else {
                kinds[index] = UInt8(Self.useCode(cell.use) * 8)
            }
        }
        var covered = [Bool](repeating: false, count: rows * columns)
        let length = Land.cellLength, radius = Land.catchmentRadius
        // A closed station reaches no one (decision 77).
        for station in world.stations where station.operationMode != .closed {
            let point = station.location
            let firstRow = max(0, Int((point.y - radius) / length) - 1), lastRow = min(rows - 1, Int((point.y + radius) / length) + 1)
            let firstColumn = max(0, Int((point.x - radius) / length) - 1), lastColumn = min(columns - 1, Int((point.x + radius) / length) + 1)
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            for row in firstRow...lastRow {
                let dy = Int64(row) * length + length / 2 - point.y
                for column in firstColumn...lastColumn {
                    let dx = Int64(column) * length + length / 2 - point.x
                    if dx * dx + dy * dy < radius * radius {
                        covered[row * columns + column] = true
                    }
                }
            }
        }
        self.kinds = kinds
        self.covered = covered
        self.peopled = peopled
    }

    private static func useCode(_ use: LandUse) -> Int {
        switch use {
        case .residential: 1
        case .commercial: 2
        case .office: 3
        }
    }

    // MARK: - Drawing

    /// How many cells a side a block has at `pointsPerUnit`: 1, or the
    /// smallest power of two that makes a block at least
    /// ``minimumTilePoints`` wide.
    public static func blockSize(pointsPerUnit: Double) -> Int {
        let cellWidth = Double(Land.cellLength) * pointsPerUnit
        guard cellWidth.isFinite, cellWidth > 0 else { return 1 }
        var size = 1
        while Double(size) * cellWidth < minimumTilePoints, size < 1 << 12 {
            size *= 2
        }
        return size
    }

    /// The rectangles to fill for city layer `mode` in `region`, cells
    /// merged into blocks of `blockSize` a side, north to south and west to
    /// east; nothing for a layer that is not the city's.
    ///
    /// - Land use: each cell with a building or land, its use's colour by
    ///   its density (``useColor(use:density:)``); a block takes the use most
    ///   of its cells have (homes, then shops, then offices on a tie) and
    ///   their average density.
    /// - Land value: each cell with land, or worth more than an empty cell
    ///   with no service, by its value's step (``valueColor(cents:)``); a
    ///   block by its cells' average.
    /// - Coverage: cells with people that no station reaches in
    ///   ``uncoveredColor``, else the cells a catchment reaches in
    ///   ``coveredColor`` (stronger with people); a block is uncovered if
    ///   any of its cells is.
    public func tiles(for mode: PopTravelMode, in region: WorldRegion, blockSize: Int = 1) -> [TravelDemandMap.Tile] {
        guard mode.isCityLayer, rows > 0, columns > 0,
              region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite
        else { return [] }
        let size = max(1, blockSize)
        let length = Double(Land.cellLength)
        let firstRow = max(0, Int((region.minY / length).rounded(.down))), lastRow = min(rows - 1, Int((region.maxY / length).rounded(.down)))
        let firstColumn = max(0, Int((region.minX / length).rounded(.down))), lastColumn = min(columns - 1, Int((region.maxX / length).rounded(.down)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        var tiles: [TravelDemandMap.Tile] = []
        let blockRows = (firstRow / size)...(lastRow / size), blockColumns = (firstColumn / size)...(lastColumn / size)
        for blockRow in blockRows {
            for blockColumn in blockColumns {
                var uses = [0, 0, 0, 0], densities = 0, drawn = 0, total: Int64 = 0
                var anyCovered = false, anyPeopled = false, anyUncovered = false
                for row in (blockRow * size)..<min(rows, (blockRow + 1) * size) {
                    for column in (blockColumn * size)..<min(columns, (blockColumn + 1) * size) {
                        let index = row * columns + column
                        switch mode {
                        case .landUse:
                            let kind = Int(kinds[index])
                            guard kind > 0 else { continue }
                            uses[kind / 8] += 1
                            densities += max(1, min(4, kind % 8))
                            drawn += 1
                        case .landValue:
                            guard peopled[index] || values[index] > LandValueRules.vacantBase else { continue }
                            total += values[index]
                            drawn += 1
                        default:
                            if covered[index] {
                                anyCovered = true
                                anyPeopled = anyPeopled || peopled[index]
                            } else if peopled[index] {
                                anyUncovered = true
                            }
                        }
                    }
                }
                let color: PopTravel.RGB
                let value: Int64
                switch mode {
                case .landUse:
                    guard drawn > 0, let use = (1...3).max(by: { uses[$0] < uses[$1] || (uses[$0] == uses[$1] && $0 > $1) }) else { continue }
                    let density = (densities + drawn / 2) / drawn
                    color = Self.useColor(use: use, density: density)
                    value = Int64(use * 8 + density)
                case .landValue:
                    guard drawn > 0 else { continue }
                    value = total / Int64(drawn)
                    color = Self.valueColor(cents: value)
                default:
                    if anyUncovered {
                        color = Self.uncoveredColor
                        value = 2
                    } else if anyCovered {
                        color = anyPeopled ? Self.coveredColor : Self.coveredEmptyColor
                        value = 1
                    } else {
                        continue
                    }
                }
                let minX = Double(blockColumn * size) * length, minY = Double(blockRow * size) * length
                tiles.append(TravelDemandMap.Tile(
                    minX: minX, minY: minY, maxX: minX + Double(size) * length, maxY: minY + Double(size) * length, color: color, value: value
                ))
            }
        }
        return tiles
    }

    // MARK: - Colours

    /// A use's four shades, D1 to D4 (existing stock draws as D4): homes
    /// green, shops blue, offices amber, darker for taller buildings.
    static let useShades: [[PopTravel.RGB]] = [
        [PopTravel.RGB(0xC7E9C0), PopTravel.RGB(0x74C476), PopTravel.RGB(0x31A354), PopTravel.RGB(0x006D2C)],
        [PopTravel.RGB(0xC6DBEF), PopTravel.RGB(0x6BAED6), PopTravel.RGB(0x3182BD), PopTravel.RGB(0x08519C)],
        [PopTravel.RGB(0xFDD49E), PopTravel.RGB(0xFDAE61), PopTravel.RGB(0xE6550D), PopTravel.RGB(0xA63603)],
    ]

    /// The colour of `use` (1 homes, 2 shops, 3 offices) at `density`
    /// (1–4; 0, land without a building, draws as 1).
    public static func useColor(use: Int, density: Int) -> PopTravel.RGB {
        useShades[min(max(use, 1), 3) - 1][min(max(density, 1), 4) - 1]
    }

    /// The land value legend's steps, in dollars a m²: a value at or above
    /// a step and below the next takes its colour.
    public static let valueSteps: [Int64] = [0, 20, 40, 60, 90, 120, 160, 200, 250]
    /// Their colours, pale yellow to deep red.
    public static let valueColors: [PopTravel.RGB] = [
        PopTravel.RGB(0xFFFFCC), PopTravel.RGB(0xFFEDA0), PopTravel.RGB(0xFED976), PopTravel.RGB(0xFEB24C), PopTravel.RGB(0xFD8D3C),
        PopTravel.RGB(0xFC4E2A), PopTravel.RGB(0xE31A1C), PopTravel.RGB(0xBD0026), PopTravel.RGB(0x800026),
    ]

    /// The step of a value of `cents` a m².
    public static func valueStep(cents: Int64) -> Int {
        let dollars = cents / 100
        return (valueSteps.lastIndex { dollars >= $0 } ?? 0)
    }

    public static func valueColor(cents: Int64) -> PopTravel.RGB {
        valueColors[valueStep(cents: cents)]
    }

    /// Cells a catchment reaches with people, and without.
    public static let coveredColor = PopTravel.RGB(0x2B8CBE)
    public static let coveredEmptyColor = PopTravel.RGB(0xA6BDDB)
    /// Cells with people no station reaches: magenta, to stand out.
    public static let uncoveredColor = PopTravel.RGB(0xE7298A)
}

// MARK: - The tapped cell

/// What a tapped cell's tooltip shows on a city layer (Phase 6d).
public struct CityCellInfo: Hashable, Sendable {
    public let row: Int
    public let column: Int
    public let use: LandUse?
    public let kind: BuildingKind?
    public let density: BuildingDensity?
    public let residents: Int64
    public let jobs: Int64
    public let value: LandValue
    /// The name of the station the premiums are measured at.
    public let stationName: String?

    /// "Homes · D2 (6 storeys)", "Residents 120 · Jobs 4", "Land value
    /// $ 194.85 a m²", "Base $ 25.00 · Service + $ 149.85 · Access +
    /// $ 20.00" and "Set by Alpha" (or "No station adds to it").
    public func lines(in language: DisplayLanguage) -> [String] {
        var lines: [String] = []
        let useName: (String, String)? = use.map {
            switch $0 {
            case .residential: ("Homes", "住宅")
            case .commercial: ("Shops", "商業")
            case .office: ("Offices", "辦公")
            }
        }
        if let useName {
            if kind == .existingStock {
                lines.append(language.text("\(useName.0) · existing stock", "\(useName.1) · 既有存量"))
            } else if let density {
                lines.append(language.text(
                    "\(useName.0) · D\(density.rawValue) (\(density.floors) storeys)",
                    "\(useName.1) · D\(density.rawValue)（\(density.floors) 層）"
                ))
            } else {
                lines.append(language.text(useName.0, useName.1))
            }
            let residents = Money(residents).displayText, jobs = Money(jobs).displayText
            lines.append(language.text("Residents \(residents) · Jobs \(jobs)", "居民 \(residents) 人 · 就業 \(jobs) 個"))
        } else {
            lines.append(language.text("Empty land", "空地"))
        }
        let total = Money(value.value).centsText
        lines.append(language.text("Land value \(total) a m²", "地價 每平方公尺 \(total)"))
        let base = Money(value.base).centsText, service = Money(value.servicePremium).centsText, access = Money(value.accessPremium).centsText
        lines.append(language.text("Base \(base) · Service + \(service) · Access + \(access)", "基準 \(base) · 服務 + \(service) · 可達 + \(access)"))
        if let stationName {
            lines.append(language.text("Set by \(stationName)", "決定價格的車站：\(stationName)"))
        } else {
            lines.append(language.text("No station adds to it", "沒有車站影響地價"))
        }
        return lines
    }
}

extension GameWorld {
    /// The city tooltip of the cell world point (`x`, `y`) lies in, or
    /// `nil` outside the world.
    public func cityCellInfo(atX x: Double, y: Double) -> CityCellInfo? {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0 else { return nil }
        let length = Double(Land.cellLength)
        let row = Int(y / length), column = Int(x / length)
        guard let value = landValue(row: row, column: column) else { return nil }
        let cell = land.cell(row: row, column: column)
        let building = buildings.building(row: row, column: column)
        return CityCellInfo(
            row: row, column: column, use: building?.use ?? cell?.use, kind: building?.kind, density: building?.density,
            residents: cell?.residents ?? 0, jobs: cell?.jobs ?? 0, value: value,
            stationName: value.station.flatMap { station(id: $0)?.name }
        )
    }

    /// The average land value of the cells within 800 m of station `id`
    /// (their middles closer than ``Land/catchmentRadius``), in cents a m²,
    /// or `nil` for a station that does not exist.
    public func catchmentLandValue(of id: StationID) -> Int64? {
        guard let station = station(id: id) else { return nil }
        let length = Land.cellLength, radius = Land.catchmentRadius
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let point = station.location
        let firstRow = max(0, Int((point.y - radius) / length) - 1), lastRow = min(rows - 1, Int((point.y + radius) / length) + 1)
        let firstColumn = max(0, Int((point.x - radius) / length) - 1), lastColumn = min(columns - 1, Int((point.x + radius) / length) + 1)
        var total: Int64 = 0, count: Int64 = 0
        if firstRow <= lastRow, firstColumn <= lastColumn {
            let values = landValues(rows: firstRow...lastRow, columns: firstColumn...lastColumn)
            let width = lastColumn - firstColumn + 1
            for row in firstRow...lastRow {
                let dy = Int64(row) * length + length / 2 - point.y
                for column in firstColumn...lastColumn {
                    let dx = Int64(column) * length + length / 2 - point.x
                    guard dx * dx + dy * dy < radius * radius else { continue }
                    total += values[(row - firstRow) * width + column - firstColumn].value
                    count += 1
                }
            }
        }
        return count > 0 ? total / count : nil
    }

    /// "Average land value within 800 m: $ 145.20 a m²", or `nil` for a
    /// world without land or a station that does not exist.
    public func catchmentLandValueText(of id: StationID, in language: DisplayLanguage) -> String? {
        guard !land.isEmpty, let value = catchmentLandValue(of: id) else { return nil }
        let text = Money(value).centsText
        return language.text("Average land value within 800 m: \(text) a m²", "腹地平均地價：每平方公尺 \(text)")
    }
}
