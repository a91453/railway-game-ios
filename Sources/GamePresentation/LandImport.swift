import Foundation
import GameCore

/// A real-world map's land (Phase 6a–6b, ARCHITECTURE decisions 72, 73):
/// WorldPop's people and the jobs of OpenStreetMap's places spread over
/// GameCore's 64 m cells, once, when the game starts. The world saves the
/// cells; the grids and the Earth are never read again, so a save does not
/// depend on them.
///
/// Each 64 m cell takes the WorldPop cell its middle lies in (30″, some
/// 900 × 840 m in Taiwan, about 190 of them). The WorldPop cell's people,
/// and its jobs, are shared evenly among slots, the first `n mod slots` in
/// row-major order one more (the largest remainder, ties by index):
///
/// - inside the world, the slots are its 64 m cells, so everyone is kept;
/// - where it reaches the world's edge (one of its 64 m cells is in the
///   first or last row or column), the slots are as many 64 m cells as its
///   area holds, `area / 64² m²` rounded (at least those inside), so the
///   part inside gets its share only.
///
/// The jobs are the places the app bundles counted on the same grid
/// (``PlaceGrid``), each worth ``jobsPerPlace`` (gap: the game's numbers,
/// set so Taiwan's places make some 8.6 million jobs, a little under two
/// for every five people, about its working population). A cell is offices,
/// shops, schools and public offices, or sights where that kind of place's
/// jobs are the most of it and at least its people (decision 90: schools
/// and sights were counted with offices and shops before), and homes
/// otherwise.
public enum LandImport {
    /// The jobs of each kind of place: a shop or restaurant 25, an office
    /// 500, a school 300 (its staff and pupils draw trips alike), a sight
    /// 50. OpenStreetMap maps every shop but few office buildings, so an
    /// office stands for many.
    public static let jobsPerPlace: [PlaceGrid.Kind: Int64] = [.shops: 25, .offices: 500, .schools: 300, .attractions: 50]

    /// The cells of a world of `bounds` laid over the Earth by `frame`, or
    /// `nil` where no one in the grid lives or works in it (a map outside
    /// Taiwan, or all sea), for which a new game founds towns instead.
    /// Without `places`, every cell is homes without jobs.
    public static func cells(population: PopulationGrid, places: PlaceGrid? = nil, frame: RealWorldFrame, bounds: WorldBounds) -> [LandCell]? {
        let spread = spread(population: population, places: places, frame: frame, bounds: bounds, in: nil)
        return spread.reachesTheWorld ? spread.cells : nil
    }

    /// The cells of `blocks` of a world whose land is read in as it is
    /// needed (decision 88): exactly the cells of those blocks that
    /// ``cells(population:places:frame:bounds:)`` would give the whole
    /// world, so the land does not depend on which blocks are read first.
    public static func cells(
        in blocks: Set<LandBlock>, population: PopulationGrid, places: PlaceGrid? = nil, frame: RealWorldFrame, bounds: WorldBounds
    ) -> [LandCell] {
        guard !blocks.isEmpty else { return [] }
        return spread(population: population, places: places, frame: frame, bounds: bounds, in: blocks).cells
    }

    /// The land of the world, or of `blocks` of it, by row and then column,
    /// and whether any WorldPop cell with people or jobs reaches the world.
    ///
    /// Web Mercator puts a 64 m cell's middle in WorldPop's row by its y
    /// alone and in its column by its x alone, so the 64 m cells of a
    /// WorldPop cell are a rectangle of rows by columns: each WorldPop cell
    /// is shared out over its rectangle, in row-major order, without going
    /// through every 64 m cell of the world (some 27 million for the whole
    /// of Taiwan).
    private static func spread(
        population: PopulationGrid, places: PlaceGrid?, frame: RealWorldFrame, bounds: WorldBounds, in blocks: Set<LandBlock>?
    ) -> (cells: [LandCell], reachesTheWorld: Bool) {
        let grid = population.people
        let length = Double(Land.cellLength)
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        // The 64 m rows of each WorldPop row, and columns of each column:
        // the WorldPop cell a 64 m cell's middle lies in, as ever.
        var rowSpans: [Int: ClosedRange<Int>] = [:]
        for row in 0..<rows {
            let latitude = frame.coordinate(worldX: 0.5 * length, worldY: (Double(row) + 0.5) * length).latitude
            let source = grid.cell(latitude: latitude, longitude: grid.west).row
            rowSpans[source] = (rowSpans[source]?.lowerBound ?? row)...row
        }
        var columnSpans: [Int: ClosedRange<Int>] = [:]
        for column in 0..<columns {
            let longitude = frame.coordinate(worldX: (Double(column) + 0.5) * length, worldY: 0.5 * length).longitude
            let source = grid.cell(latitude: grid.north, longitude: longitude).column
            columnSpans[source] = (columnSpans[source]?.lowerBound ?? column)...column
        }
        // The jobs of a WorldPop cell: in offices, shops, schools and
        // sights (decision 90 keeps the last two apart).
        func jobs(_ cell: GridCounts.Cell) -> (office: Int64, shop: Int64, civic: Int64, leisure: Int64) {
            guard let places else { return (0, 0, 0, 0) }
            func count(_ kind: PlaceGrid.Kind) -> Int64 {
                Int64(places.layers[kind]?.counts[cell] ?? 0) * (jobsPerPlace[kind] ?? 0)
            }
            return (count(.offices), count(.shops), count(.schools), count(.attractions))
        }
        var sources = Set(grid.counts.keys)
        if let places {
            for layer in places.layers.values {
                sources.formUnion(layer.counts.keys)
            }
        }
        let cellArea = length * length / Double(WorldCoordinate.unitsPerMetre * WorldCoordinate.unitsPerMetre)
        let lastRow = rows - 1, lastColumn = columns - 1
        var reachesTheWorld = false
        var cells: [LandCell] = []
        for source in sources {
            guard let rowSpan = rowSpans[source.row], let columnSpan = columnSpans[source.column] else { continue }
            let people = Int64(grid.counts[source] ?? 0)
            let work = jobs(source)
            let allJobs = work.office + work.shop + work.civic + work.leisure
            guard people > 0 || allJobs > 0 else { continue }
            reachesTheWorld = true
            if let blocks {
                let firstBlock = LandBlock(cellRow: rowSpan.lowerBound, column: columnSpan.lowerBound)
                let lastBlock = LandBlock(cellRow: rowSpan.upperBound, column: columnSpan.upperBound)
                let touches = (firstBlock.row...lastBlock.row).contains { row in
                    (firstBlock.column...lastBlock.column).contains { blocks.contains(LandBlock(row: row, column: $0)) }
                }
                guard touches else { continue }
            }
            // The use most of it is: offices, then shops, then schools and
            // public offices, then sights on a tie with each other or with
            // the people, else homes (decision 90).
            let uses: [(LandUse, Int64)] = [(.office, work.office), (.commercial, work.shop), (.civic, work.civic), (.leisure, work.leisure)]
            let most = uses.reduce((LandUse.residential, Int64(-1))) { best, use in use.1 > best.1 ? use : best }
            let use = most.1 >= people ? most.0 : .residential
            let inside = rowSpan.count * columnSpan.count
            let atEdge = rowSpan.lowerBound == 0 || columnSpan.lowerBound == 0 || rowSpan.upperBound == lastRow || columnSpan.upperBound == lastColumn
            let slots = Int64(atEdge ? max(inside, Int((grid.area(of: source) / cellArea).rounded())) : inside)
            func share(_ total: Int64, _ index: Int) -> Int64 {
                let (base, extra) = total.quotientAndRemainder(dividingBy: slots)
                return min(Land.maximumPerCell, base + (Int64(index) < extra ? 1 : 0))
            }
            for row in rowSpan {
                for column in columnSpan {
                    if let blocks, !blocks.contains(LandBlock(cellRow: row, column: column)) { continue }
                    let index = (row - rowSpan.lowerBound) * columnSpan.count + column - columnSpan.lowerBound
                    let residents = share(people, index), jobs = share(allJobs, index)
                    guard residents + jobs > 0 else { continue }
                    cells.append(LandCell(row: row, column: column, use: use, residents: residents, jobs: jobs))
                }
            }
        }
        return (cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }, reachesTheWorld)
    }
}
