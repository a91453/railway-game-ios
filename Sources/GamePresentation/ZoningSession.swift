import GameCore

// City building P0-B (ARCHITECTURE decision 98): the building tool's third
// mode zones the 64 m cells the player taps, or the rectangle the player
// drags across, for the zone chosen (or clears them), through GameCore's
// `setZone`. A drag is one edit, as the owner's Simulator takes one undo
// snapshot for a whole brush stroke (`onTerrainStroke`); while the finger is
// down the map shows the rectangle, and the zoning layer shows the zones.

extension Zone {
    /// Its name in the zoning tool and on the map.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .residential: language.text("Homes", "住宅區")
        case .commercial: language.text("Shops", "商業區")
        case .office: language.text("Offices", "辦公區")
        case .industrial: language.text("Industry", "工業區")
        case .civic: language.text("Public", "公共設施")
        case .leisure: language.text("Leisure", "觀光休閒")
        case .noDevelopment: language.text("No development", "不開發")
        case .reserved: language.text("Reserved", "保留地")
        }
    }
}

/// A rectangle of 64 m cells: rows `rows` by columns `columns`.
public struct CellRectangle: Hashable, Sendable {
    public let rows: ClosedRange<Int>
    public let columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    public var count: Int {
        rows.count * columns.count
    }

    /// Where it lies on the plan, in world units.
    public var planRect: PlanRect {
        PlanRect(
            minX: Int64(columns.lowerBound) * Land.cellLength, minY: Int64(rows.lowerBound) * Land.cellLength,
            maxX: Int64(columns.upperBound + 1) * Land.cellLength, maxY: Int64(rows.upperBound + 1) * Land.cellLength
        )
    }
}

extension GameSession {
    /// The cells from the one `start` lies in to the one `end` lies in,
    /// both clamped into the world, and at most ``Zoning/maximumSide``
    /// cells a side counted from `start`'s; `nil` for a world without
    /// cells.
    public func zoneRectangle(from start: PlanPoint, to end: PlanPoint) -> CellRectangle? {
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        guard rows > 0, columns > 0 else { return nil }
        func cell(_ value: Int64, _ count: Int) -> Int {
            min(count - 1, max(0, Int(value >= 0 ? value / Land.cellLength : -1)))
        }
        func span(_ from: Int, _ to: Int) -> ClosedRange<Int> {
            let reach = Zoning.maximumSide - 1
            let to = min(from + reach, max(from - reach, to))
            return min(from, to)...max(from, to)
        }
        let firstRow = cell(start.y, rows), firstColumn = cell(start.x, columns)
        return CellRectangle(rows: span(firstRow, cell(end.y, rows)), columns: span(firstColumn, cell(end.x, columns)))
    }

    /// The finger moved from `start` to `end` with the zoning tool: the map
    /// shows the rectangle it would zone (``zoneDrag``). Changes nothing.
    public func dragZone(from start: PlanPoint, to end: PlanPoint) {
        zoneDrag = zoneRectangle(from: start, to: end)
    }

    /// The finger lifted at `end`, having started at `start`: zones the
    /// rectangle (``zone(_:)``) and stops showing it.
    @discardableResult
    public func endZoneDrag(from start: PlanPoint, to end: PlanPoint) -> Bool {
        zoneDrag = nil
        guard let rectangle = zoneRectangle(from: start, to: end) else { return false }
        return zone(rectangle)
    }

    /// The drag was cancelled: nothing is zoned.
    public func cancelZoneDrag() {
        zoneDrag = nil
    }

    /// Zones `rectangle` ``zoningZone`` (or clears it) with
    /// ``GameWorld/setZone(_:rows:columns:)``, as one edit that undo takes
    /// back, and reports how many cells changed in ``message``.
    @discardableResult
    public func zone(_ rectangle: CellRectangle) -> Bool {
        let zone = zoningZone
        return perform { world throws(GameError) in
            let changed = try world.setZone(zone, rows: rectangle.rows, columns: rectangle.columns)
            guard changed > 0 else {
                return language.text("No cell changed.", "沒有格子改變。")
            }
            guard let zone else {
                return language.text(
                    changed == 1 ? "Cleared the zone of 1 cell." : "Cleared the zones of \(changed) cells.", "清除 \(changed) 格的分區。"
                )
            }
            return language.text(
                changed == 1 ? "Zoned 1 cell: \(zone.title(in: .english))." : "Zoned \(changed) cells: \(zone.title(in: .english)).",
                "劃設\(zone.title(in: .traditionalChinese)) \(changed) 格。"
            )
        }
    }

    /// How many cells are zoned, for the zoning tool.
    public var zonedCellsText: String {
        let count = world.zones.cells.count
        return language.text(count == 1 ? "1 cell zoned" : "\(count) cells zoned", "已劃分區 \(count) 格")
    }

    /// The city's demand (decision 139), for the zoning tool: "City demand:
    /// homes +12% · shops −8% · work +3%"; `nil` with the valves off.
    public var cityDemandText: String? {
        guard world.cityDemand != nil else { return nil }
        let levels = world.cityDemandLevels
        // Whole per cents away from zero: a demand below one per cent
        // still holds a use back or lets it build (``spread`` builds only
        // what is not negative), so it never reads "0%".
        func percent(_ level: Int64) -> String {
            let value = (abs(level) + 9) / 10
            return level > 0 ? "+\(value)%" : level < 0 ? "−\(value)%" : "0%"
        }
        return language.text(
            "City demand: homes \(percent(levels.homes)) · shops \(percent(levels.shops)) · work \(percent(levels.work))",
            "城市需求：住宅 \(percent(levels.homes)) · 商業 \(percent(levels.shops)) · 辦公與工業 \(percent(levels.work))"
        )
    }

    /// What the chosen zone does, for the zoning tool.
    public var zoningHelpText: String {
        guard let zone = zoningZone else {
            return language.text("Tap or drag to clear zones.", "點一格或拖曳一塊範圍來清除分區。")
        }
        switch zone {
        case .noDevelopment:
            return language.text(
                "The city builds nothing new here, and what stands here neither grows nor is raised.",
                "城市不在這裡蓋新建物，已有的建物不再成長或升級。"
            )
        case .reserved:
            return language.text("Kept for your track and buildings: the city builds nothing new here.", "保留給軌道或公司建物：城市不在這裡蓋新建物。")
        default:
            let help = language.text(
                "Tap or drag: growing stations build \(zone.title(in: .english).lowercased()) on empty zoned cells first, those worth most first. Zoned cells near your buildings are worth more.",
                "點一格或拖曳一塊範圍：成長中的車站先在空的分區格蓋\(zone.title(in: .traditionalChinese))，地價高的先蓋；公司建物附近的分區格地價較高。"
            )
            // Decision 139: homes, shops, offices and factories wait for
            // their demand.
            guard world.cityDemand != nil, zone.use.flatMap(world.cityDemandLevels.level(of:)) != nil else { return help }
            return help + language.text(
                " They are built only while the city wants that use.",
                "只有城市需要這種用途（需求不是負的）時才會蓋。"
            )
        }
    }
}
