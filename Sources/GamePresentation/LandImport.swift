import Foundation
import GameCore

/// A real-world map's land (Phase 6a, ARCHITECTURE decision 72): WorldPop's
/// people spread over GameCore's 64 m cells, once, when the game starts.
/// The world saves the cells; the grid and the Earth are never read again,
/// so a save does not depend on them.
///
/// Each 64 m cell takes the WorldPop cell its middle lies in (30″, some
/// 900 × 840 m in Taiwan, about 190 of them). The WorldPop cell's people
/// are shared evenly among slots, the first `people mod slots` in
/// row-major order one more (the largest remainder, ties by index):
///
/// - inside the world, the slots are its 64 m cells, so all its people
///   are kept;
/// - where it reaches the world's edge (one of its 64 m cells is in the
///   first or last row or column), the slots are as many 64 m cells as its
///   area holds, `area / 64² m²` rounded (at least those inside), so the
///   part inside gets its share only.
///
/// Every cell is homes: WorldPop counts residents, and the jobs round them
/// are Phase 6b's (gap).
public enum LandImport {
    /// The cells of a world of `bounds` laid over the Earth by `frame`, or
    /// `nil` where no one in the grid lives in it (a map outside Taiwan,
    /// or all sea), for which a new game founds towns instead.
    public static func cells(population: PopulationGrid, frame: RealWorldFrame, bounds: WorldBounds) -> [LandCell]? {
        let grid = population.people
        let length = Double(Land.cellLength)
        var members: [GridCounts.Cell: [(row: Int, column: Int)]] = [:]
        for row in 0..<Land.rows(in: bounds) {
            for column in 0..<Land.columns(in: bounds) {
                let place = frame.coordinate(worldX: (Double(column) + 0.5) * length, worldY: (Double(row) + 0.5) * length)
                let source = grid.cell(latitude: place.latitude, longitude: place.longitude)
                guard let people = grid.counts[source], people > 0 else { continue }
                members[source, default: []].append((row, column))
            }
        }
        guard !members.isEmpty else { return nil }
        let cellArea = length * length / Double(WorldCoordinate.unitsPerMetre * WorldCoordinate.unitsPerMetre)
        let lastRow = Land.rows(in: bounds) - 1, lastColumn = Land.columns(in: bounds) - 1
        var cells: [LandCell] = []
        for (source, inside) in members {
            let people = Int64(grid.counts[source] ?? 0)
            let atEdge = inside.contains { $0.row == 0 || $0.column == 0 || $0.row == lastRow || $0.column == lastColumn }
            let slots = Int64(atEdge ? max(inside.count, Int((grid.area(of: source) / cellArea).rounded())) : inside.count)
            let (base, extra) = people.quotientAndRemainder(dividingBy: slots)
            for (index, cell) in inside.enumerated() {
                let residents = min(Land.maximumPerCell, base + (Int64(index) < extra ? 1 : 0))
                guard residents > 0 else { continue }
                cells.append(LandCell(row: cell.row, column: cell.column, use: .residential, residents: residents, jobs: 0))
            }
        }
        return cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }
}
