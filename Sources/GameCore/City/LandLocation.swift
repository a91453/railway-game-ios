// Where land lies (decision 1025): how dear a real place's land is against
// the rest of the country, from the real-price registry's sales of the
// same zone (實價登錄; the presentation's `LandPriceGrid`). Each square of
// ``LandLocations/squareCells`` cells a side (256 m) the map has read can
// hold a factor in thousandths; a cell's land value multiplies its use's
// base by its square's factor (``LandValueRules/located(_:factor:)``), so
// a field in a city's middle is dear and a shop zone in the hills cheap,
// and a cell the player zones keeps its place's factor under its new use.
// A square without one (a blank map, a map abroad, a save from before)
// is worth what it was.
//
// The factors come with the land, as its coverage does (decision 147):
// the presentation reads them from the app's file when it reads a map's
// land, and the world saves them, so a save does not depend on the file.

/// A square of land and the factor its place sets its land value by
/// (decision 1025).
public struct LandLocation: Hashable, Sendable {
    /// Its row and column of squares, ``LandLocations/squareCells`` cells
    /// a side, from the world's origin.
    public let row: Int
    public let column: Int
    /// Thousandths, ``LandLocations/lowest`` to ``LandLocations/highest``.
    public let factor: Int64

    public init(row: Int, column: Int, factor: Int64) {
        self.row = row
        self.column = column
        self.factor = factor
    }
}

/// The factors of the squares a map has read (decision 1025).
public struct LandLocations: Hashable, Sendable {
    /// A square's side, in cells: 4, 256 m.
    public static let squareCells = 4
    /// A factor's bounds, in thousandths: a tenth to ten times the
    /// country's median of the same zone.
    public static let lowest: Int64 = 100
    public static let highest: Int64 = 10_000

    private var factors: [CellPosition: Int64] = [:]

    public init() {}

    public var isEmpty: Bool { factors.isEmpty }
    public var count: Int { factors.count }

    /// The square cell `row`, `column` lies in.
    public static func square(row: Int, column: Int) -> CellPosition {
        CellPosition(row: row / squareCells, column: column / squareCells)
    }

    /// The factor of the square the cell at `row`, `column` lies in, or
    /// `nil` where none is known.
    public func factor(row: Int, column: Int) -> Int64? {
        guard row >= 0, column >= 0 else { return nil }
        return factors[Self.square(row: row, column: column)]
    }

    /// Every square with a factor, by row and then column.
    public var all: [LandLocation] {
        factors.keys.sorted().map { LandLocation(row: $0.row, column: $0.column, factor: factors[$0]!) }
    }

    /// The rows of squares a world of `bounds` has.
    public static func squareRows(in bounds: WorldBounds) -> Int {
        (Land.rows(in: bounds) + squareCells - 1) / squareCells
    }

    public static func squareColumns(in bounds: WorldBounds) -> Int {
        (Land.columns(in: bounds) + squareCells - 1) / squareCells
    }

    static func isValid(_ location: LandLocation, in bounds: WorldBounds) -> Bool {
        (0..<squareRows(in: bounds)).contains(location.row) && (0..<squareColumns(in: bounds)).contains(location.column)
            && (lowest...highest).contains(location.factor)
    }

    /// Why these factors cannot be a world of `bounds`'s, or `nil`.
    func problem(in bounds: WorldBounds) -> String? {
        all.allSatisfy { Self.isValid($0, in: bounds) } ? nil : "A land location lies outside the world or its factor is out of range."
    }

    /// Sets `locations`' factors, keeping those already known.
    mutating func merge(_ locations: [LandLocation]) {
        for location in locations {
            let square = CellPosition(row: location.row, column: location.column)
            if factors[square] == nil {
                factors[square] = location.factor
            }
        }
    }
}

extension LandLocations: Codable {
    /// Squares next to each other in a row: `{"row", "column", "factors":
    /// [n, …]}`, the first square's column, one factor a square.
    private struct Run: Codable {
        var row: Int
        var column: Int
        var factors: [Int64]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        var factors: [CellPosition: Int64] = [:]
        for run in try container.decode([Run].self) {
            guard !run.factors.isEmpty, run.row >= 0, run.column >= 0, run.factors.count <= Int.max - run.column else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A run of land locations has no squares.")
            }
            for (offset, factor) in run.factors.enumerated() {
                let square = CellPosition(row: run.row, column: run.column + offset)
                guard factors[square] == nil, (Self.lowest...Self.highest).contains(factor) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "A land location is listed twice or out of range.")
                }
                factors[square] = factor
            }
        }
        self.factors = factors
    }

    public func encode(to encoder: any Encoder) throws {
        var runs: [Run] = []
        for location in all {
            if let last = runs.last, last.row == location.row, last.column + last.factors.count == location.column {
                runs[runs.count - 1].factors.append(location.factor)
            } else {
                runs.append(Run(row: location.row, column: location.column, factors: [location.factor]))
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(runs)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Gives the squares of `locations` their place's factor (decision
    /// 1025), as the map's land is read: a square that has one keeps it,
    /// so reading the same land again changes nothing. Refused, changing
    /// nothing, for a square outside the world, a factor out of range, or
    /// a square listed twice.
    public mutating func setLandLocations(_ locations: [LandLocation]) throws(GameError) {
        guard locations.allSatisfy({ LandLocations.isValid($0, in: bounds) }),
              Set(locations.map { CellPosition(row: $0.row, column: $0.column) }).count == locations.count
        else { throw .invalidLand }
        landLocations.merge(locations)
    }
}
