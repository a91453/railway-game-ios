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
    /// The cells a layer can draw, by row and then column: those with land
    /// (and so a building), those a station's catchment reaches, those
    /// near a park (decision 91) and those zoned (decision 98). Every other cell has no use, is worth an
    /// empty cell with no service (``LandValueRules/vacantBase``: a cell is
    /// worth more only with land, a station with service within the
    /// catchment or a park near by) and is not covered, so no layer draws
    /// it. They grow with what is built and lived in, not
    /// with the map (docs/research/WHOLE_TAIWAN_MAP.md).
    let cells: [Cell]

    struct Cell: Sendable {
        let row: Int
        let column: Int
        /// Its value in cents a m².
        let value: Int64
        /// Its use and density: 0 for no building or land, else
        /// `use × 8 + density` (``useCode(_:)``, 1 homes to 8 parks;
        /// density 1–4, 5 for existing stock).
        let kind: UInt8
        /// Whether a station's catchment reaches it.
        let covered: Bool
        /// Whether anyone lives or works in it (not a park, decision 91).
        let peopled: Bool
        /// Its zone (decision 98): 0 for none, else 1 to 8 in ``Zone``'s
        /// order (``zoneCode(_:)``).
        let zone: UInt8
    }

    /// The smallest a drawn rectangle may be on screen, in points.
    public static let minimumTilePoints = 6.0

    public init(world: GameWorld) {
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        self.rows = rows
        self.columns = columns
        var kinds: [CellPosition: UInt8] = [:], peopled: Set<CellPosition> = []
        for cell in world.land.cells where cell.row < rows && cell.column < columns {
            let position = CellPosition(row: cell.row, column: cell.column)
            if cell.residents + cell.jobs > 0 { peopled.insert(position) }
            if let building = world.buildings.building(row: cell.row, column: cell.column) {
                let density = building.kind == .existingStock ? 5 : building.density.rawValue
                kinds[position] = UInt8(Self.useCode(building.use) * 8 + density)
            } else {
                kinds[position] = UInt8(Self.useCode(cell.use) * 8)
            }
        }
        var covered: Set<CellPosition> = []
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
                        covered.insert(CellPosition(row: row, column: column))
                    }
                }
            }
        }
        // Decision 91: the cells a park makes worth more.
        var nearParks: Set<CellPosition> = []
        let parkReach = LandValueRules.parkReach
        for cell in world.land.cells where cell.use == .park {
            let point = cell.middle
            let firstRow = max(0, Int((point.y - parkReach) / length) - 1), lastRow = min(rows - 1, Int((point.y + parkReach) / length) + 1)
            let firstColumn = max(0, Int((point.x - parkReach) / length) - 1), lastColumn = min(columns - 1, Int((point.x + parkReach) / length) + 1)
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            for row in firstRow...lastRow {
                let dy = Int64(row) * length + length / 2 - point.y
                for column in firstColumn...lastColumn {
                    let dx = Int64(column) * length + length / 2 - point.x
                    if dx * dx + dy * dy < parkReach * parkReach {
                        nearParks.insert(CellPosition(row: row, column: column))
                    }
                }
            }
        }
        // Decision 98: the zoned cells.
        var zones: [CellPosition: UInt8] = [:]
        for cell in world.zones.cells where cell.row < rows && cell.column < columns {
            zones[cell.position] = UInt8(Self.zoneCode(cell.zone))
        }
        let positions = Set(kinds.keys).union(covered).union(nearParks).union(zones.keys).sorted()
        let values = world.landValues(at: positions)
        cells = zip(positions, values).map { position, value in
            let kind = kinds[position]
            return Cell(
                row: position.row, column: position.column, value: value.value,
                kind: kind ?? 0, covered: covered.contains(position), peopled: peopled.contains(position), zone: zones[position] ?? 0
            )
        }
    }

    /// A zone's number, 1 to 8 in ``Zone``'s order: the order a block's tie
    /// goes by and ``zoneColors`` follows.
    static func zoneCode(_ zone: Zone) -> Int {
        (Zone.allCases.firstIndex(of: zone) ?? 0) + 1
    }

    /// A use's number, 1 to 8 in ``LandUse``'s order: the order a block's
    /// tie goes by and ``useColor(use:density:)`` reads.
    static func useCode(_ use: LandUse) -> Int {
        (LandUse.allCases.firstIndex(of: use) ?? 0) + 1
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
    /// - Zoning (decision 98): each zoned cell in its zone's colour
    ///   (``zoneColors``); a block takes the zone most of its zoned cells
    ///   have (in ``Zone``'s order on a tie).
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
        // Whole blocks, those at the region's edges too, as before.
        let lowRow = firstRow / size * size, highRow = min(rows - 1, (lastRow / size + 1) * size - 1)
        let lowColumn = firstColumn / size * size, highColumn = min(columns - 1, (lastColumn / size + 1) * size - 1)
        struct Block {
            var uses = [Int](repeating: 0, count: LandUse.allCases.count + 1), densities = 0, drawn = 0, total: Int64 = 0
            var zones = [Int](repeating: 0, count: Zone.allCases.count + 1)
            var anyCovered = false, anyPeopled = false, anyUncovered = false
        }
        var blocks: [CellPosition: Block] = [:]
        // The first cell at or below the first row, by halving.
        var low = 0, high = cells.count
        while low < high {
            let middle = (low + high) / 2
            if cells[middle].row < lowRow { low = middle + 1 } else { high = middle }
        }
        for cell in cells[low...] {
            guard cell.row <= highRow else { break }
            guard (lowColumn...highColumn).contains(cell.column) else { continue }
            let key = CellPosition(row: cell.row / size, column: cell.column / size)
            var block = blocks[key] ?? Block()
            switch mode {
            case .landUse:
                let kind = Int(cell.kind)
                guard kind > 0 else { continue }
                block.uses[kind / 8] += 1
                block.densities += max(1, min(4, kind % 8))
                block.drawn += 1
            case .landValue:
                guard cell.peopled || cell.value > LandValueRules.vacantBase else { continue }
                block.total += cell.value
                block.drawn += 1
            case .zoning:
                guard cell.zone > 0 else { continue }
                block.zones[Int(cell.zone)] += 1
                block.drawn += 1
            default:
                if cell.covered {
                    block.anyCovered = true
                    block.anyPeopled = block.anyPeopled || cell.peopled
                } else if cell.peopled {
                    block.anyUncovered = true
                }
            }
            blocks[key] = block
        }
        var tiles: [TravelDemandMap.Tile] = []
        for key in blocks.keys.sorted() {
            guard let block = blocks[key] else { continue }
            let color: PopTravel.RGB
            let value: Int64
            switch mode {
            case .landUse:
                let uses = block.uses
                guard block.drawn > 0, let use = (1...LandUse.allCases.count).max(by: { uses[$0] < uses[$1] || (uses[$0] == uses[$1] && $0 > $1) }) else { continue }
                let density = (block.densities + block.drawn / 2) / block.drawn
                color = Self.useColor(use: use, density: density)
                value = Int64(use * 8 + density)
            case .landValue:
                guard block.drawn > 0 else { continue }
                value = block.total / Int64(block.drawn)
                color = Self.valueColor(cents: value)
            case .zoning:
                let zones = block.zones
                guard block.drawn > 0, let zone = (1...Zone.allCases.count).max(by: { zones[$0] < zones[$1] || (zones[$0] == zones[$1] && $0 > $1) })
                else { continue }
                color = Self.zoneColors[zone - 1]
                value = Int64(zone)
            default:
                if block.anyUncovered {
                    color = Self.uncoveredColor
                    value = 2
                } else if block.anyCovered {
                    color = block.anyPeopled ? Self.coveredColor : Self.coveredEmptyColor
                    value = 1
                } else {
                    continue
                }
            }
            let minX = Double(key.column * size) * length, minY = Double(key.row * size) * length
            tiles.append(TravelDemandMap.Tile(
                minX: minX, minY: minY, maxX: minX + Double(size) * length, maxY: minY + Double(size) * length, color: color, value: value
            ))
        }
        return tiles
    }

    // MARK: - Colours

    /// A use's four shades, D1 to D4 (existing stock draws as D4): homes
    /// green, shops blue, offices amber, darker for taller buildings; since
    /// decision 91 factories purple, schools and public offices red, sights
    /// teal, farms brown and parks a light green (ColorBrewer's sequential
    /// schemes, as the first three).
    static let useShades: [[PopTravel.RGB]] = [
        [PopTravel.RGB(0xC7E9C0), PopTravel.RGB(0x74C476), PopTravel.RGB(0x31A354), PopTravel.RGB(0x006D2C)],
        [PopTravel.RGB(0xC6DBEF), PopTravel.RGB(0x6BAED6), PopTravel.RGB(0x3182BD), PopTravel.RGB(0x08519C)],
        [PopTravel.RGB(0xFDD49E), PopTravel.RGB(0xFDAE61), PopTravel.RGB(0xE6550D), PopTravel.RGB(0xA63603)],
        [PopTravel.RGB(0xDADAEB), PopTravel.RGB(0x9E9AC8), PopTravel.RGB(0x756BB1), PopTravel.RGB(0x54278F)],
        [PopTravel.RGB(0xFCBBA1), PopTravel.RGB(0xFC9272), PopTravel.RGB(0xEF3B2C), PopTravel.RGB(0xA50F15)],
        [PopTravel.RGB(0xC7EAE5), PopTravel.RGB(0x80CDC1), PopTravel.RGB(0x35978F), PopTravel.RGB(0x01665E)],
        [PopTravel.RGB(0xF6E8C3), PopTravel.RGB(0xDFC27D), PopTravel.RGB(0xBF812D), PopTravel.RGB(0x8C510A)],
        [PopTravel.RGB(0xB8E186), PopTravel.RGB(0x7FBC41), PopTravel.RGB(0x4D9221), PopTravel.RGB(0x276419)],
    ]

    /// The colour of `use` (1 to 8 in ``LandUse``'s order: homes, shops,
    /// offices, factories, schools and public offices, sights, farms,
    /// parks) at `density` (1–4; 0, land without a building, draws as 1).
    public static func useColor(use: Int, density: Int) -> PopTravel.RGB {
        useShades[min(max(use, 1), useShades.count) - 1][min(max(density, 1), 4) - 1]
    }

    /// Each use's number for ``useColor(use:density:)`` and its name, for
    /// the land use legend.
    public static let useNames: [(use: Int, english: String, chinese: String)] = LandUse.allCases.map {
        (useCode($0), $0.names.english, $0.names.chinese)
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

    /// Each zone's colour, in ``Zone``'s order (decision 98): `Ci/`'s land
    /// use palette (`landuseColorByClass`: homes 居住用地, shops 商业服务,
    /// offices 商务办公, factories 工业用地, public 行政办公, sights 教育用地's
    /// cyan, as `Ci/` has no sights class), its nature reserve extent
    /// (`map.legend.reserveExtent`) for no development and its airport
    /// extent (`map.legend.airportExtent`) for reserved land.
    public static let zoneColors: [PopTravel.RGB] = [
        PopTravel.RGB(0xFFB74D), PopTravel.RGB(0xFF7043), PopTravel.RGB(0xEF5350), PopTravel.RGB(0xAB47BC),
        PopTravel.RGB(0x42A5F5), PopTravel.RGB(0x26C6DA), PopTravel.RGB(0x1B5E20), PopTravel.RGB(0x78909C),
    ]

    /// The colour of `zone`.
    public static func zoneColor(_ zone: Zone) -> PopTravel.RGB {
        zoneColors[zoneCode(zone) - 1]
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
    /// What the player zoned it for (decision 98), or `nil`.
    public var zone: Zone? = nil

    /// "Homes · D2 (6 storeys)", "Residents 120 · Jobs 4", "Land value
    /// $ 194.85 a m²", "Base $ 25.00 · Service + $ 149.85 · Access +
    /// $ 20.00" and "Set by Alpha" (or "No station adds to it").
    public func lines(in language: DisplayLanguage) -> [String] {
        var lines: [String] = []
        let useName: (String, String)? = use.map { ($0.names.english, $0.names.chinese) }
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
        if value.parkPremium > 0 {
            let park = Money(value.parkPremium).centsText
            lines.append(language.text("Near a park + \(park)", "鄰近公園 + \(park)"))
        }
        if value.companyPremium > 0 {
            let company = Money(value.companyPremium).centsText
            lines.append(language.text("Near your buildings + \(company)", "鄰近公司建物 + \(company)"))
        }
        if let zone {
            lines.append(language.text("Zoned: \(zone.title(in: .english))", "分區：\(zone.title(in: .traditionalChinese))"))
        }
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
            stationName: value.station.flatMap { station(id: $0)?.name }, zone: zones.zone(row: row, column: column)
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

extension LandUse {
    /// Its name on the city map, in English and in Traditional Chinese.
    public var names: (english: String, chinese: String) {
        switch self {
        case .residential: ("Homes", "住宅")
        case .commercial: ("Shops", "商業")
        case .office: ("Offices", "辦公")
        case .industrial: ("Industry", "工業物流")
        case .civic: ("Public", "公共設施")
        case .leisure: ("Leisure", "觀光休閒")
        case .agricultural: ("Farms", "農業")
        case .park: ("Parks", "公園綠地")
        }
    }
}
