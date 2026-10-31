import GameCore

/// Decision 514: what will happen on a cell the player zoned for a use and
/// the city has not built on yet, read from the rules the city grows by
/// (decisions 98 and 139, ``GameWorld``'s `spread(towards:levels:)`): a
/// growing station builds one zoned cell of its catchment a night, the one
/// worth most, and passes over a use the city does not want.
///
/// The player saw a zone stay empty and could not tell why (owner,
/// 2026-10-30: "目前看起來分區沒什麼作用"); the zoning layer marks each cell
/// with one of these, and a tapped cell says it in words.
public enum ZoneOutlook: Int, CaseIterable, Hashable, Sendable {
    /// Within 800 m of a station that grew last night: built on, one cell
    /// a night near each such station.
    case builds = 1
    /// Within 800 m of a station, but none of them grew last night (no one
    /// rode yet, or no train ran).
    case waitsForStation
    /// No open station within 800 m: the city never builds it.
    case tooFar
    /// Near a growing station, but the city does not want this use now:
    /// passed over until it does.
    case notWanted

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .builds: language.text("Will be built", "會蓋")
        case .waitsForStation: language.text("Waiting for the station", "等車站成長")
        case .tooFar: language.text("Too far from a station", "離車站太遠")
        case .notWanted: language.text("Not needed now", "目前不缺")
        }
    }

    /// What a tapped cell says about it: one sentence, what the player can
    /// do.
    public func explanation(in language: DisplayLanguage) -> String {
        switch self {
        case .builds:
            language.text(
                "The town builds on zones near a busy station, one cell a day.",
                "附近車站有人搭車，城市每天會在分區蓋一格。"
            )
        case .waitsForStation:
            language.text(
                "Builds once trains carry passengers from the station nearby.",
                "附近車站有列車載到旅客、開始成長後才會蓋。"
            )
        case .tooFar:
            language.text(
                "No station within 800 m: build one nearby, or zone closer to a station.",
                "800 公尺內沒有車站：在附近蓋車站，或劃在車站旁邊。"
            )
        case .notWanted:
            language.text(
                "The town has enough of this for now: it builds when demand comes back.",
                "城市目前不缺這種用途，需求回升時才會蓋。"
            )
        }
    }

    /// The zoning legend's sentence (decision 514).
    public static func hint(in language: DisplayLanguage) -> String {
        language.text(
            "Zones near a station fill in once its trains carry passengers and the town grows.",
            "分區要劃在車站附近，車站有人搭車、開始成長時才會蓋。"
        )
    }
}

/// Decision 514: the outlook of every zoned, still empty cell of a world
/// (``ZoneOutlook``), worked out once from it.
public struct ZoningOutlook: Sendable {
    /// The stations that grew last night (their town's last service share
    /// above 0, so their rate was), with town growth on and the land setting
    /// ridership; and every open station, by place.
    let growing: [PlanPoint]
    let open: [PlanPoint]
    /// The city's demand now, `nil` with its valves off (every use wanted).
    let levels: CityDemand.Levels?

    public init(world: GameWorld) {
        open = world.stations.filter { $0.operationMode != .closed }.map(\.location)
        let grows = world.townGrowth != nil && world.landDemand && world.accounts.mode == .management
        let growingIDs = Set((grows ? world.townGrowth?.places ?? [] : []).filter { place in
            place.lastService > 0
                && place.lastService * TownGrowth.serviceGrowth / 1_000 + place.lastReached * TownGrowth.reachGrowth > 0
        }.map(\.station))
        growing = world.stations.filter { $0.operationMode != .closed && growingIDs.contains($0.id) }.map(\.location)
        levels = world.cityDemand == nil ? nil : world.cityDemandLevels
    }

    /// The outlook of the cell at `row`, `column` zoned `zone`, or `nil` for
    /// a zone that keeps the city off, a cell the city has built on (land),
    /// or water or a steep slope. The checks go in the order the player has
    /// to see to them: a station, then its trains, then the demand.
    public func outlook(row: Int, column: Int, zone: Zone, in world: GameWorld) -> ZoneOutlook? {
        guard let use = zone.use, world.land.cell(row: row, column: column) == nil,
              !world.terrain.isWater(row: row, column: column), !world.terrain.isSteep(row: row, column: column)
        else { return nil }
        let length = Land.cellLength, radius = Land.catchmentRadius
        let middle = PlanPoint(x: Int64(column) * length + length / 2, y: Int64(row) * length + length / 2)
        func reaches(_ point: PlanPoint) -> Bool {
            let dx = middle.x - point.x, dy = middle.y - point.y
            return dx * dx + dy * dy < radius * radius
        }
        guard open.contains(where: reaches) else { return .tooFar }
        guard growing.contains(where: reaches) else { return .waitsForStation }
        if let level = levels?.level(of: use), level < 0 { return .notWanted }
        return .builds
    }

    /// Decision 522: the cells of `rectangle` whose middle lies 800 m or
    /// more from every point of `stations` (``ZoneOutlook/tooFar``'s
    /// reach), as runs of columns along each row, by row and then column.
    /// Works a row at a time from the stations that can reach it, so a
    /// large drag on a map of hundreds of stations stays quick.
    public static func runsOutOfReach(in rectangle: CellRectangle, of stations: [PlanPoint]) -> [CellRectangle] {
        let length = Land.cellLength, radius = Land.catchmentRadius
        let area = rectangle.planRect
        let near = stations.filter {
            $0.x > area.minX - radius && $0.x < area.maxX + radius && $0.y > area.minY - radius && $0.y < area.maxY + radius
        }
        /// The largest whole number whose square is at most `value`.
        func squareRoot(_ value: Int64) -> Int64 {
            var root = Int64(Double(value).squareRoot())
            while root * root > value { root -= 1 }
            while (root + 1) * (root + 1) <= value { root += 1 }
            return root
        }
        /// The lowest whole number at least `value / length`.
        func columnAtLeast(_ value: Int64) -> Int {
            Int(value >= 0 ? (value + length - 1) / length : -((-value) / length))
        }
        /// The highest whole number at most `value / length`.
        func columnAtMost(_ value: Int64) -> Int {
            Int(value >= 0 ? value / length : -((-value + length - 1) / length))
        }
        var runs: [CellRectangle] = []
        for row in rectangle.rows {
            let middleY = Int64(row) * length + length / 2
            // The columns each station reaches on this row: a middle x with
            // (x − station.x)² < radius² − dy².
            var reached: [ClosedRange<Int>] = []
            for station in near {
                let dy = middleY - station.y
                let room = radius * radius - dy * dy
                guard room > 0 else { continue }
                let reach = squareRoot(room - 1)
                let first = max(rectangle.columns.lowerBound, columnAtLeast(station.x - reach - length / 2))
                let last = min(rectangle.columns.upperBound, columnAtMost(station.x + reach - length / 2))
                if first <= last { reached.append(first...last) }
            }
            reached.sort { $0.lowerBound < $1.lowerBound }
            var column = rectangle.columns.lowerBound
            for range in reached {
                if range.lowerBound > column {
                    runs.append(CellRectangle(rows: row...row, columns: column...(range.lowerBound - 1)))
                }
                column = max(column, range.upperBound + 1)
            }
            if column <= rectangle.columns.upperBound {
                runs.append(CellRectangle(rows: row...row, columns: column...rectangle.columns.upperBound))
            }
        }
        return runs
    }

    /// Every zoned, empty cell's outlook, by row and then column.
    public func outlooks(in world: GameWorld) -> [(position: CellPosition, outlook: ZoneOutlook)] {
        world.zones.cells.compactMap { cell in
            outlook(row: cell.row, column: cell.column, zone: cell.zone, in: world).map { (cell.position, $0) }
        }
    }

    /// How many zoned, empty cells have each outlook.
    public func counts(in world: GameWorld) -> [ZoneOutlook: Int] {
        var counts: [ZoneOutlook: Int] = [:]
        for (_, outlook) in outlooks(in: world) {
            counts[outlook, default: 0] += 1
        }
        return counts
    }
}
