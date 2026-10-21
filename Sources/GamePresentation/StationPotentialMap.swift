import Foundation
import GameCore

// Decision 311 (City Transport Manager study 4.1): while a station or a
// line is being built, the map shows where a station would have riders.
// With no station of a new line picked yet, each 64 m cell counts the
// residents and jobs within ``Land/catchmentRadius`` of its middle, as
// ``GameCore/Land/totals(within:of:)`` and `landCatchment` count a
// station's. Once the new line has stations, each cell is weighed by how
// many of the trips from them would ride that far (decision 137's curve,
// ``GameCore/DistanceDemand/share(squaredDistance:)``, when the world
// keeps it), and a cell a station already reaches counts for less. The
// morning and the evening weigh the residents and each kind of job by how
// strongly trips arrive in those hours (``GameCore/StationDemandKind``'s
// `arrivalShape`): where people go in the morning, where they go back to
// in the evening. It is an estimate from the game's own model, by
// straight-line distance, which decision 311 says and the player's text
// does not.
//
// Only what is in view is worked out, in square chunks of
// ``chunkBlocks`` blocks a side, each kept once worked out: panning works
// out only the chunks it brings into view, and a new map comes only with
// a new ``Key`` (a command that changes the land, the stations or the new
// line's stations), never with a tick.

/// The hours the potential map weighs people by (decision 311).
public enum PotentialPeriod: String, CaseIterable, Hashable, Sendable {
    /// Everyone, the day round.
    case allDay
    /// Where trips arrive from 07:00 to 10:00.
    case morning
    /// Where trips arrive from 17:00 to 20:00.
    case evening

    /// The hours weighed, or `nil` for the whole day.
    var hours: Range<Int>? {
        switch self {
        case .allDay: nil
        case .morning: 7..<10
        case .evening: 17..<20
        }
    }

    /// How strongly trips arrive at a place of `kind` in these hours, in
    /// thousandths of the day's mean: their `arrivalShape`'s mean, 1000
    /// for the whole day.
    func weight(of kind: StationDemandKind) -> Int64 {
        guard let hours else { return 1_000 }
        let shape = kind.arrivalShape
        return hours.reduce(0) { $0 + shape[$1] } / Int64(hours.count)
    }

    /// "All day", "Morning", "Evening".
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .allDay: language.text("All day", "全天")
        case .morning: language.text("Morning", "早上")
        case .evening: language.text("Evening", "傍晚")
        }
    }
}

/// Where a station would have riders, cell by cell, in view (decision
/// 311). Derived from ``GameWorld`` and never kept as a copy of it beyond
/// its ``Key``.
public struct StationPotentialMap: Sendable {
    /// What a map is worked out from: the land, the open stations that are
    /// not the new line's, the new line's, whether trips keep decision
    /// 137's share by distance, and the hours. Equal across ticks; a
    /// command that changes one of them makes a new key.
    public struct Key: Equatable, Sendable {
        let land: Land
        let served: [PlanPoint]
        let drafts: [PlanPoint]
        let distanceDemand: Bool
        let period: PotentialPeriod
        let rows: Int
        let columns: Int

        /// `drafts`: the stations picked for a new line, in any order; those
        /// that do not exist are left out.
        public init(world: GameWorld, drafts: [StationID], period: PotentialPeriod) {
            let picked = Set(drafts)
            land = world.land
            served = world.stations.filter { $0.operationMode != .closed && !picked.contains($0.id) }.map(\.location)
            self.drafts = world.stations.filter { picked.contains($0.id) }.map(\.location)
            distanceDemand = world.distanceDemand
            self.period = period
            rows = Land.rows(in: world.bounds)
            columns = Land.columns(in: world.bounds)
        }

        /// Whether a new line has stations: the map then shows where trips
        /// from them go.
        public var hasDrafts: Bool { !drafts.isEmpty }
    }

    public let key: Key
    private let chunks: ChunkCache

    /// A chunk's side, in blocks.
    static let chunkBlocks = 32
    /// What a cell a station already reaches counts for once a new line
    /// has stations, in thousandths.
    public static let servedShare: Int64 = 400
    /// The bands' lower bounds: residents and jobs within 800 m. Fewer than
    /// the first is not drawn.
    public static let bands: [Int64] = [250, 1_000, 2_500, 5_000, 10_000, 20_000]
    /// The bands' colours, pale warm yellow through green and teal to the
    /// icon's navy (docs/UI_THEME.md, decision 311).
    public static let colors: [PopTravel.RGB] = [
        PopTravel.RGB(0xFFE7A8), PopTravel.RGB(0xC6D98B), PopTravel.RGB(0x7CC08C),
        PopTravel.RGB(0x3A9BA6), PopTravel.RGB(0x2D6890), PopTravel.RGB(0x262C57),
    ]

    public init(key: Key) {
        self.key = key
        chunks = ChunkCache()
    }

    public init(world: GameWorld, drafts: [StationID] = [], period: PotentialPeriod = .allDay) {
        self.init(key: Key(world: world, drafts: drafts, period: period))
    }

    /// The band of `value` (an index into ``colors``), or `nil` below the
    /// first.
    public static func band(of value: Int64) -> Int? {
        bands.lastIndex { value >= $0 }
    }

    /// How many chunks are kept, for the tests.
    var chunksWorkedOut: Int { chunks.count }

    /// Cell (`row`, `column`)'s value: the people a station there would
    /// have, weighed as the key says; 0 outside the map.
    public func value(row: Int, column: Int) -> Int64 {
        guard (0..<key.rows).contains(row), (0..<key.columns).contains(column) else { return 0 }
        let chunk = self.chunk(row: row / Self.chunkBlocks, column: column / Self.chunkBlocks, blockSize: 1)
        return chunk.values[(row % Self.chunkBlocks) * Self.chunkBlocks + column % Self.chunkBlocks]
    }

    /// The rectangles to fill in `region`, cells merged into blocks of
    /// `blockSize` a side (``CityMap/blockSize(pointsPerUnit:)``), each in
    /// its band's colour; blocks below the first band are left out.
    public func tiles(in region: WorldRegion, blockSize: Int = 1) -> [TravelDemandMap.Tile] {
        guard key.rows > 0, key.columns > 0, region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite
        else { return [] }
        let size = max(1, blockSize)
        let blockLength = Double(Land.cellLength) * Double(size)
        let blockRows = (key.rows + size - 1) / size, blockColumns = (key.columns + size - 1) / size
        let firstRow = max(0, Int((region.minY / blockLength).rounded(.down))), lastRow = min(blockRows - 1, Int((region.maxY / blockLength).rounded(.down)))
        let firstColumn = max(0, Int((region.minX / blockLength).rounded(.down))), lastColumn = min(blockColumns - 1, Int((region.maxX / blockLength).rounded(.down)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        var tiles: [TravelDemandMap.Tile] = []
        let side = Self.chunkBlocks
        for chunkRow in (firstRow / side)...(lastRow / side) {
            for chunkColumn in (firstColumn / side)...(lastColumn / side) {
                let chunk = self.chunk(row: chunkRow, column: chunkColumn, blockSize: size)
                for (offset, value) in chunk.values.enumerated() {
                    let row = chunkRow * side + offset / side, column = chunkColumn * side + offset % side
                    guard (firstRow...lastRow).contains(row), (firstColumn...lastColumn).contains(column), let band = Self.band(of: value)
                    else { continue }
                    let minX = Double(column) * blockLength, minY = Double(row) * blockLength
                    tiles.append(TravelDemandMap.Tile(minX: minX, minY: minY, maxX: minX + blockLength, maxY: minY + blockLength,
                                                      color: Self.colors[band], value: value))
                }
            }
        }
        return tiles
    }

    // MARK: - Chunks

    struct ChunkKey: Hashable {
        let row: Int
        let column: Int
        let blockSize: Int
    }

    struct Chunk: Sendable {
        /// Each block's value, by row and then column, ``chunkBlocks`` a
        /// side (0 past the map's edge).
        let values: [Int64]
    }

    /// The chunks worked out so far, behind a lock: the map's canvas draws
    /// off the main thread.
    final class ChunkCache: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [ChunkKey: Chunk] = [:]

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return chunks.count
        }

        func chunk(_ key: ChunkKey, make: () -> Chunk) -> Chunk {
            lock.lock()
            if let chunk = chunks[key] {
                lock.unlock()
                return chunk
            }
            lock.unlock()
            let chunk = make()
            lock.lock()
            chunks[key] = chunk
            lock.unlock()
            return chunk
        }
    }

    private func chunk(row: Int, column: Int, blockSize: Int) -> Chunk {
        chunks.chunk(ChunkKey(row: row, column: column, blockSize: blockSize)) {
            workOut(chunkRow: row, chunkColumn: column, blockSize: blockSize)
        }
    }

    /// Each kind of job, as GameCore sorts a cell's when it shares the land
    /// among stations (`shares(of:among:)`).
    static func jobKind(of use: LandUse) -> StationDemandKind {
        switch use {
        case .office, .industrial, .agricultural: .office
        case .civic: .civic
        case .leisure: .scenic
        case .residential, .commercial, .park: .shopping
        }
    }

    /// A chunk's blocks: each sums the weighed people (in thousandths) of
    /// the blocks whose middles lie within ``Land/catchmentRadius`` of its
    /// own, as a station there would reach (exactly
    /// ``GameCore/Land/totals(within:of:)`` for cells); merged blocks are
    /// scaled to that reach's area, so a block's value is the people of a
    /// catchment of its density, whatever the zoom. Then, with a new line's stations, the
    /// share of trips that would ride from the nearest of them and the
    /// cells already reached.
    private func workOut(chunkRow: Int, chunkColumn: Int, blockSize size: Int) -> Chunk {
        let side = Self.chunkBlocks
        let length = Land.cellLength, radius = Land.catchmentRadius
        let blockLength = length * Int64(size)
        // How far, in blocks, the reach goes: block middles closer than the
        // radius, row by row (`spans[dy]` columns either side).
        var reach = 0
        while Int64(reach + 1) * blockLength < radius { reach += 1 }
        let spans: [Int] = (0...reach).map { dy in
            var dx = 0
            while Int64(dx + 1) * Int64(dx + 1) * blockLength * blockLength + Int64(dy * dy) * blockLength * blockLength < radius * radius { dx += 1 }
            return dx
        }
        let reached = Int64(spans.enumerated().reduce(0) { $0 + ($1.offset == 0 ? 1 : 2) * (2 * $1.element + 1) })
        // The cells a catchment of 64 m cells holds, to scale big blocks.
        var cellReach = 0
        while Int64(cellReach + 1) * length < radius { cellReach += 1 }
        var catchmentCells: Int64 = 0
        for dy in -cellReach...cellReach {
            for dx in -cellReach...cellReach where Int64(dx * dx + dy * dy) * length * length < radius * radius {
                catchmentCells += 1
            }
        }
        // The weighed people of each block in the chunk and `reach` round it.
        let originRow = chunkRow * side - reach, originColumn = chunkColumn * side - reach
        let width = side + 2 * reach
        var grid = [Int64](repeating: 0, count: width * width)
        let period = key.period
        let residentWeight = period.weight(of: .residential)
        let jobWeights = Dictionary(uniqueKeysWithValues: LandUse.allCases.map { ($0, period.weight(of: Self.jobKind(of: $0))) })
        let cells = key.land.cells
        let firstCellRow = max(0, originRow * size), lastCellRow = min(key.rows, (originRow + width) * size) - 1
        let firstCellColumn = max(0, originColumn * size), lastCellColumn = min(key.columns, (originColumn + width) * size) - 1
        if firstCellRow <= lastCellRow, firstCellColumn <= lastCellColumn {
            for cellRow in firstCellRow...lastCellRow {
                var index = Self.firstIndex(in: cells, row: cellRow, column: firstCellColumn)
                if index < cells.count, cells[index].row > cellRow { continue }
                if index >= cells.count { break }
                while index < cells.count, cells[index].row == cellRow, cells[index].column <= lastCellColumn {
                    let cell = cells[index]
                    let at = (cellRow / size - originRow) * width + cell.column / size - originColumn
                    grid[at] += cell.residents * residentWeight + cell.jobs * (jobWeights[cell.use] ?? 1_000)
                    index += 1
                }
            }
        }
        // Each row's running sums, so a span is two reads.
        var sums = [Int64](repeating: 0, count: width * (width + 1))
        for row in 0..<width {
            for column in 0..<width {
                sums[row * (width + 1) + column + 1] = sums[row * (width + 1) + column] + grid[row * width + column]
            }
        }
        let blockRows = (key.rows + size - 1) / size, blockColumns = (key.columns + size - 1) / size
        let area = reached * Int64(size) * Int64(size)
        var values = [Int64](repeating: 0, count: side * side)
        for offsetRow in 0..<side {
            let row = chunkRow * side + offsetRow
            guard row < blockRows else { break }
            for offsetColumn in 0..<side {
                let column = chunkColumn * side + offsetColumn
                guard column < blockColumns else { break }
                var total: Int64 = 0
                for dy in -reach...reach {
                    let span = spans[abs(dy)]
                    let gridRow = offsetRow + reach + dy
                    let low = offsetColumn + reach - span, high = offsetColumn + reach + span
                    total += sums[gridRow * (width + 1) + high + 1] - sums[gridRow * (width + 1) + low]
                }
                if area != catchmentCells {
                    total = total * catchmentCells / area
                }
                if key.hasDrafts {
                    let middle = PlanPoint(x: Int64(column) * blockLength + blockLength / 2, y: Int64(row) * blockLength + blockLength / 2)
                    if key.distanceDemand {
                        let nearest = key.drafts.map { Self.squaredDistance($0, middle) }.min() ?? 0
                        total = total * DistanceDemand.share(squaredDistance: nearest) / 1_000
                    }
                    if key.served.contains(where: { Self.squaredDistance($0, middle) < radius * radius }) {
                        total = total * Self.servedShare / 1_000
                    }
                }
                values[offsetRow * side + offsetColumn] = total / 1_000
            }
        }
        return Chunk(values: values)
    }

    static func squaredDistance(_ a: PlanPoint, _ b: PlanPoint) -> Int64 {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// The index of the first of `cells` (sorted by row and then column) at
    /// or after (`row`, `column`), by halving.
    static func firstIndex(in cells: [LandCell], row: Int, column: Int) -> Int {
        var low = 0, high = cells.count
        while low < high {
            let middle = (low + high) / 2
            let cell = cells[middle]
            if cell.row < row || (cell.row == row && cell.column < column) { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

extension StationPotentialMap {
    /// The legend's title: where people are, or once a new line has
    /// stations, where trips from them go.
    public static func title(hasDrafts: Bool, in language: DisplayLanguage) -> String {
        hasDrafts ? language.text("Where your stations reach", "從你的站可以去哪") : PopTravelMode.potential.title(in: language)
    }

    /// The legend's one line: what the colours say, never how they are
    /// worked out (docs/UI_THEME.md).
    public static func line(hasDrafts: Bool, in language: DisplayLanguage) -> String {
        hasDrafts
            ? language.text(
                "Darker: more riders from your stations would go there. Places a station already reaches are paler.",
                "顏色越深，從你的站去那裡的人越多；已經有車站的地方比較淡。"
            )
            : language.text(
                "Darker: more people live and work nearby, so a station there gets more riders.",
                "顏色越深，附近住的人、工作的人越多，車站蓋在那裡搭車的人越多。"
            )
    }

    /// What the ⓘ beside the title says.
    public static func info(in language: DisplayLanguage) -> String {
        language.text(
            "Shown while you build, so you can see where to put stations. Morning shows where people head to, evening where they head home. Coverage shows the homes and workplaces near a station, and those no station reaches yet. Tap the button in the corner to hide it.",
            "建造時會出現，幫你看車站要放哪裡。「早上」看大家要去哪裡，「傍晚」看大家回到哪裡。「涵蓋」看哪些住家與工作的地方在車站附近、哪些還沒有車站。按角落的按鈕可以收起。"
        )
    }
}

/// The layer the map shows while a station or a line is being built
/// (decision 311, which takes decision 292's switch further): where
/// people are (``PopTravelMode/potential``) or how far the stations reach
/// (``PopTravelMode/coverage``), over the player's own layer, which it
/// never changes. Kept by the map as transient state; only whether it
/// shows when building begins and which of the two it shows are kept as
/// device preferences.
public struct BuildingLayerShortcut: Equatable, Sendable {
    /// The layer shown over the player's own while building, or `nil`.
    public private(set) var shown: PopTravelMode?
    /// Which of the two the switch shows: ``PopTravelMode/potential``
    /// unless the player chose ``PopTravelMode/coverage``.
    public private(set) var choice: PopTravelMode = .potential

    /// The `UserDefaults` key of whether it shows as soon as building
    /// begins (true until the player puts it away).
    public static let autoShowsKey = "mapBuildingLayerAutoShows"

    public init() {}

    /// The layer the map draws: this one while it shows, else the
    /// player's (never ``PopTravelMode/potential``, which is only this
    /// switch's).
    public func layer(over players: PopTravelMode?) -> PopTravelMode? {
        shown ?? (players == .potential ? nil : players)
    }

    /// Whether the switch shows its layer.
    public var isOn: Bool { shown != nil }

    /// Building began: the chosen layer shows, unless the player put it
    /// away last time (`autoShows` false).
    public mutating func buildingBegan(autoShows: Bool) {
        shown = autoShows ? choice : nil
    }

    /// Building ended: the player's own layer shows again.
    public mutating func buildingEnded() {
        shown = nil
    }

    /// The corner button, or the legend's close button: puts the layer
    /// away or brings it back. Returns whether it should show the next time
    /// building begins.
    @discardableResult
    public mutating func toggle() -> Bool {
        shown = shown == nil ? choice : nil
        return shown != nil
    }

    /// The legend's switch between where people are and how far the
    /// stations reach; any other layer is not one of the two.
    public mutating func choose(_ mode: PopTravelMode) {
        guard mode == .potential || mode == .coverage else { return }
        choice = mode
        if shown != nil { shown = mode }
    }

    /// The player chose a layer of their own (the layer list or the quick
    /// layers): it shows instead.
    public mutating func playerChoseLayer() {
        shown = nil
    }
}
