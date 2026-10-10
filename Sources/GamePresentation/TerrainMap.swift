import GameCore

/// The height and steep slope layer (ARCHITECTURE decision 124, the
/// design's third step; the roadmap's "height and steep slope layer"): the
/// ground tinted by its height and shaded as if lit from the north-west,
/// and the steep slopes (decision 115) hatched.
///
/// Worked out once for a map (``init(world:heights:)``, off the main
/// thread) and then asked only for what is in view, like ``CityMap``:
/// - On a real-world map the heights are the app's heights file
///   (``HeightGrid``), the same the track's ground is read from, sampled at
///   the 64 m cells' corners; a map larger than ``maximumCorners`` a side
///   (the whole of Taiwan) at every second, third … corner.
/// - Without the file, the ground the world has read (GameCore's
///   ``GameCore/GameWorld/groundHeight(at:)``) where it has read it.
/// - A world without ground (a blank map) is flat: nothing is drawn.
///
/// Water is left undrawn: the map under it shows it. Presentation only;
/// nothing here changes the world.
///
/// Reference (`a91453/railway-reference-private` `05d7000`):
/// `Railway/site_archive_clean/rail-3d/integration/map3d.js`'s MapLibre
/// `landscape-hillshade` layer: light from 315°, exaggeration 0.42, shadow
/// `#5c785f`, highlight `#fff4d6` (``shadow``, ``highlight``). It has no
/// height colours (no hypsometric ramp anywhere in the reference: gap); the
/// tints (``tints``) are this project's.
public struct TerrainMap: Sendable {
    /// The most corners a side the map keeps: 1,025 × 1,025 heights, 4 MB.
    public static let maximumCorners = 1_025

    /// How many 64 m cells lie between two kept corners.
    public let step: Int
    /// The kept corners a side.
    let rows: Int
    let columns: Int
    /// Each kept corner's height in metres, by row and then column;
    /// `nan` where it is not known.
    let heights: [Float]
    /// The world's water and steep slopes.
    let terrain: Terrain
    /// The world's cells.
    let cellRows: Int
    let cellColumns: Int
    /// Whether there is nothing to draw: a world without ground.
    public let isFlat: Bool

    public init(world: GameWorld, heights grid: HeightGrid?) {
        let cellRows = Land.rows(in: world.bounds), cellColumns = Land.columns(in: world.bounds)
        self.cellRows = cellRows
        self.cellColumns = cellColumns
        terrain = world.terrain
        let frame = RealWorldFrame(world: world)
        let step = max(1, (max(cellRows, cellColumns) + Self.maximumCorners - 2) / (Self.maximumCorners - 1))
        self.step = step
        // A corner past the last cells when they are not a whole number of
        // steps, so the map's east and south edges have heights too.
        let rows = (cellRows + step - 1) / step + 1, columns = (cellColumns + step - 1) / step + 1
        self.rows = rows
        self.columns = columns
        let length = Double(Land.cellLength) * Double(step)
        if let grid, let frame {
            // Web Mercator puts a point's latitude by its y alone and its
            // longitude by its x alone; going south row by row, only the
            // rows still ahead are kept.
            let longitudes = (0..<columns).map { frame.coordinate(worldX: Double($0) * length, worldY: 0).longitude }
            var reader = HeightGrid.Reader(grid)
            var heights: [Float] = []
            heights.reserveCapacity(rows * columns)
            for row in 0..<rows {
                let latitude = frame.coordinate(worldX: 0, worldY: Double(row) * length).latitude
                reader.forgetRows(above: reader.row(at: latitude))
                for longitude in longitudes {
                    heights.append(Float(reader.height(latitude: latitude, longitude: longitude)))
                }
            }
            self.heights = heights
            isFlat = false
        } else if world.ground.isMapped {
            let metre = Float(WorldCoordinate.unitsPerMetre)
            heights = (0..<rows).flatMap { row in
                (0..<columns).map { column in
                    // The corner past the edge reads the ground at the edge.
                    let point = PlanPoint(
                        x: min(Int64(column * step) * Land.cellLength, world.bounds.width - 1),
                        y: min(Int64(row * step) * Land.cellLength, world.bounds.height - 1)
                    )
                    return world.groundHeight(at: point).map { Float($0) / metre } ?? .nan
                }
            }
            isFlat = false
        } else {
            heights = []
            isFlat = true
        }
    }

    /// The height at world point (`x`, `y`) in metres: the bilinear blend
    /// of the kept corners round it; `nil` outside the world, on a flat map
    /// or where a corner is not known.
    public func height(atX x: Double, y: Double) -> Double? {
        guard !isFlat, x.isFinite, y.isFinite else { return nil }
        let length = Double(Land.cellLength) * Double(step)
        let gx = x / length, gy = y / length
        guard gx >= 0, gy >= 0, gx <= Double(columns - 1), gy <= Double(rows - 1) else { return nil }
        let column = min(columns - 2, Int(gx)), row = min(rows - 2, Int(gy))
        guard column >= 0, row >= 0 else { return Double(heights[0]) }
        let fx = gx - Double(column), fy = gy - Double(row)
        func at(_ r: Int, _ c: Int) -> Double { Double(heights[r * columns + c]) }
        let value = at(row, column) * (1 - fx) * (1 - fy) + at(row, column + 1) * fx * (1 - fy)
            + at(row + 1, column) * (1 - fx) * fy + at(row + 1, column + 1) * fx * fy
        return value.isNaN ? nil : value
    }

    /// The layer's squares in `region`: each block of `blockSize` 64 m
    /// cells a side (``CityMap/blockSize(pointsPerUnit:)``), north to south
    /// and west to east, tinted by the height at its middle (``tint(metres:)``)
    /// (to 25 m) and shaded by the slope across it (``shade(_:eastward:southward:)``);
    /// `steep`, the blocks whose middle cell is a steep slope, for the
    /// hatching. Blocks whose middle cell is water, or whose height is not
    /// known, are left out. A tile's value is its height to the metre.
    public func tiles(in region: WorldRegion, blockSize: Int = 1) -> (shaded: [TravelDemandMap.Tile], steep: [TravelDemandMap.Tile]) {
        guard !isFlat, cellRows > 0, cellColumns > 0,
              region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite
        else { return ([], []) }
        let size = max(1, blockSize)
        let length = Double(Land.cellLength)
        let blockLength = length * Double(size)
        let firstRow = max(0, Int(region.minY / blockLength)), lastRow = min((cellRows - 1) / size, Int(region.maxY / blockLength))
        let firstColumn = max(0, Int(region.minX / blockLength)), lastColumn = min((cellColumns - 1) / size, Int(region.maxX / blockLength))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return ([], []) }
        // The slope is measured across the block, and at least across the
        // kept corners' spacing.
        let reach = max(blockLength, length * Double(step)) / 2
        var shaded: [TravelDemandMap.Tile] = [], steep: [TravelDemandMap.Tile] = []
        for blockRow in firstRow...lastRow {
            for blockColumn in firstColumn...lastColumn {
                let minX = Double(blockColumn) * blockLength, minY = Double(blockRow) * blockLength
                let maxX = min(minX + blockLength, Double(cellColumns) * length), maxY = min(minY + blockLength, Double(cellRows) * length)
                let x = (minX + maxX) / 2, y = (minY + maxY) / 2
                let row = min(cellRows - 1, Int(y / length)), column = min(cellColumns - 1, Int(x / length))
                guard !terrain.isWater(row: row, column: column), let height = height(atX: x, y: y) else { continue }
                let west = self.height(atX: max(0, x - reach), y: y) ?? height, east = self.height(atX: x + reach, y: y) ?? height
                let north = self.height(atX: x, y: max(0, y - reach)) ?? height, south = self.height(atX: x, y: y + reach) ?? height
                let metres = 2 * reach / Double(WorldCoordinate.unitsPerMetre)
                // The tint by 25 m steps and the shade by eighths: a few
                // hundred colours, each filled once a draw.
                let tint = Self.tint(metres: (height / 25).rounded() * 25)
                let color = Self.shade(tint, eastward: (east - west) / metres, southward: (south - north) / metres)
                let tile = TravelDemandMap.Tile(minX: minX, minY: minY, maxX: maxX, maxY: maxY, color: color, value: Int64(height.rounded()))
                shaded.append(tile)
                if terrain.isSteep(row: row, column: column) {
                    steep.append(tile)
                }
            }
        }
        return (shaded, steep)
    }

    // MARK: - Colours

    /// The tints by height, in metres: low green through tan and brown to
    /// pale grey on the peaks, blended between the steps.
    public static let tints: [(metres: Double, color: PopTravel.RGB)] = [
        (0, PopTravel.RGB(0xB5D6A7)),
        (100, PopTravel.RGB(0xD5E3A3)),
        (300, PopTravel.RGB(0xE9DCA0)),
        (800, PopTravel.RGB(0xD7B884)),
        (1_500, PopTravel.RGB(0xB8946D)),
        (2_500, PopTravel.RGB(0x9F8E83)),
        (3_500, PopTravel.RGB(0xEEECE8)),
    ]

    /// The reference's hillshade colours (`landscape-hillshade`).
    public static let shadow = PopTravel.RGB(0x5C785F)
    public static let highlight = PopTravel.RGB(0xFFF4D6)
    /// The steep slopes' hatching.
    public static let steepColor = PopTravel.RGB(0x8C2D04)

    /// The tint at `metres` (``tints``).
    public static func tint(metres: Double) -> PopTravel.RGB {
        guard let upper = tints.firstIndex(where: { $0.metres > metres }) else { return tints[tints.count - 1].color }
        guard upper > 0 else { return tints[0].color }
        let low = tints[upper - 1], high = tints[upper]
        return blend(low.color, high.color, (metres - low.metres) / (high.metres - low.metres))
    }

    /// `color` lit from the north-west, 45° up (the reference's
    /// illumination direction 315): darker toward ``shadow`` on a slope
    /// facing away, lighter toward ``highlight`` on one facing the light,
    /// unchanged on the flat. The gradients are rises a metre east and
    /// south; the strength is the reference's exaggeration, 0.42, taken in
    /// eighths.
    public static func shade(_ color: PopTravel.RGB, eastward: Double, southward: Double) -> PopTravel.RGB {
        // The ground's normal (east, north, up), and the light's way.
        let normal = (x: -eastward, y: southward, z: 1.0)
        let size = (normal.x * normal.x + normal.y * normal.y + 1).squareRoot()
        let light = (x: -0.5, y: 0.5, z: 0.5.squareRoot())
        let lit = (normal.x * light.x + normal.y * light.y + normal.z * light.z) / size
        let flat = light.z
        let amount = (0.42 * (lit - flat) / flat * 8).rounded() / 8
        return amount < 0 ? blend(color, shadow, min(1, -amount * 2)) : blend(color, highlight, min(1, amount * 2))
    }

    static func blend(_ a: PopTravel.RGB, _ b: PopTravel.RGB, _ t: Double) -> PopTravel.RGB {
        let t = min(1, max(0, t))
        func mix(_ p: UInt8, _ q: UInt8) -> UInt8 {
            UInt8((Double(p) * (1 - t) + Double(q) * t).rounded())
        }
        return PopTravel.RGB(red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
    }

    // MARK: - The tapped cell

    /// What the tooltip of the cell world point (`x`, `y`) lies in says:
    /// "Height 235 m" and "Steep slope (over 30%)", "Water" or "Not steep";
    /// `nil` outside the world or where the height is not known.
    public func cellLines(atX x: Double, y: Double, in language: DisplayLanguage) -> [String]? {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0 else { return nil }
        let length = Double(Land.cellLength)
        let row = Int(y / length), column = Int(x / length)
        guard row < cellRows, column < cellColumns else { return nil }
        if terrain.isWater(row: row, column: column) {
            return [language.text("Water", "水域")]
        }
        guard let height = height(atX: x, y: y) else { return nil }
        let metres = Int(height.rounded())
        return [
            language.text("Height \(metres) m", "海拔 \(metres) 公尺"),
            terrain.isSteep(row: row, column: column)
                ? language.text("Steep slope (over 30%): the city does not build here", "陡坡（超過 30%）：城市不在這裡開發")
                : language.text("Not steep", "非陡坡"),
        ]
    }
}
