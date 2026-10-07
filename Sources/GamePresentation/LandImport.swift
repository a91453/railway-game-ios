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
/// for every five people, about its working population). A cell is offices where the
/// offices' and schools' jobs are the most of it, shops where the shops'
/// and sights' are, and homes otherwise.
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
        let grid = population.people
        let length = Double(Land.cellLength)
        // The jobs of a WorldPop cell: in offices and schools, and in shops
        // and sights.
        func jobs(_ cell: GridCounts.Cell) -> (office: Int64, shop: Int64) {
            guard let places else { return (0, 0) }
            func count(_ kind: PlaceGrid.Kind) -> Int64 {
                Int64(places.layers[kind]?.counts[cell] ?? 0) * (jobsPerPlace[kind] ?? 0)
            }
            return (count(.offices) + count(.schools), count(.shops) + count(.attractions))
        }
        var members: [GridCounts.Cell: [(row: Int, column: Int)]] = [:]
        var sourceJobs: [GridCounts.Cell: (office: Int64, shop: Int64)] = [:]
        for row in 0..<Land.rows(in: bounds) {
            for column in 0..<Land.columns(in: bounds) {
                let place = frame.coordinate(worldX: (Double(column) + 0.5) * length, worldY: (Double(row) + 0.5) * length)
                let source = grid.cell(latitude: place.latitude, longitude: place.longitude)
                if members[source] == nil {
                    let work = jobs(source)
                    guard (grid.counts[source] ?? 0) > 0 || work.office + work.shop > 0 else { continue }
                    sourceJobs[source] = work
                }
                members[source, default: []].append((row, column))
            }
        }
        guard !members.isEmpty else { return nil }
        let cellArea = length * length / Double(WorldCoordinate.unitsPerMetre * WorldCoordinate.unitsPerMetre)
        let lastRow = Land.rows(in: bounds) - 1, lastColumn = Land.columns(in: bounds) - 1
        var cells: [LandCell] = []
        for (source, inside) in members {
            let people = Int64(grid.counts[source] ?? 0)
            let work = sourceJobs[source] ?? (0, 0)
            let use: LandUse = work.office >= people && work.office >= work.shop
                ? .office
                : work.shop >= people ? .commercial : .residential
            let atEdge = inside.contains { $0.row == 0 || $0.column == 0 || $0.row == lastRow || $0.column == lastColumn }
            let slots = Int64(atEdge ? max(inside.count, Int((grid.area(of: source) / cellArea).rounded())) : inside.count)
            func share(_ total: Int64, _ index: Int) -> Int64 {
                let (base, extra) = total.quotientAndRemainder(dividingBy: slots)
                return min(Land.maximumPerCell, base + (Int64(index) < extra ? 1 : 0))
            }
            for (index, cell) in inside.enumerated() {
                let residents = share(people, index), jobs = share(work.office + work.shop, index)
                guard residents + jobs > 0 else { continue }
                cells.append(LandCell(row: cell.row, column: cell.column, use: use, residents: residents, jobs: jobs))
            }
        }
        return cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }
}
