// Selling the company's buildings (city building P0-D, ARCHITECTURE
// decision 130): the A-Train way, where a building that has grown a town
// round it is sold and the city takes it over. The price is the right to
// use its land at what the land is worth now, less a twentieth, and what is
// left of its building on the books, in full once it is half full and
// pro rata below; the gain or loss against its book value is realized, as
// decision 85 books what is written off. The building stays: its people
// become the city's on the cell under it, and the cells it claimed are the
// city's again.
//
// The reference has no property (docs/research/CITY_BUILDING_STUDY.md §2):
// the rule and its numbers are native, the study's §4.3.

extension PlacedBuildingRules {
    /// What a sale pays for the right to use the land, in hundredths of
    /// that right at the land's value now.
    public static let saleLandPercent: Int64 = 95
}

/// What selling one of the company's buildings brings in (decision 130).
public struct PlacedBuildingSaleQuote: Hashable, Sendable {
    /// The right to use its land now: the land value of the cell under its
    /// centre (cents a m²) by its footprint, as building it would pay.
    public let landRight: Money
    /// What is left of its building on the books: what the building (not
    /// its land) cost, written down straight-line over the class's life for
    /// the days its asset record has run; nothing without a record.
    public let buildingBookValue: Money
    /// Who lives and works in it, and who it holds when full.
    public let occupants: Int64
    public let capacity: Int64
    /// What is left of the whole asset record on the books, its land and
    /// buy-outs too: what the sale is measured against.
    public let bookValue: Money

    public init(landRight: Money, buildingBookValue: Money, occupants: Int64, capacity: Int64, bookValue: Money) {
        self.landRight = landRight
        self.buildingBookValue = buildingBookValue
        self.occupants = occupants
        self.capacity = capacity
        self.bookValue = bookValue
    }

    /// What the land brings: ``PlacedBuildingRules/saleLandPercent`` of
    /// its right, rounded down.
    public var land: Money {
        Money(landRight.amount * PlacedBuildingRules.saleLandPercent / 100)
    }

    /// What the building brings: its book value when it is at least half
    /// full, else that share of it, `bookValue × occupants × 2 ÷ capacity`
    /// rounded down.
    public var building: Money {
        guard capacity > 0, occupants * 2 < capacity else { return buildingBookValue }
        return AssetRecord.share(of: buildingBookValue, numerator: occupants * 2, denominator: capacity)
    }

    /// How much of the building's book value the price takes, in
    /// thousandths: 1000 at half full or more.
    public var occupancyFactor: Int64 {
        guard capacity > 0 else { return 1_000 }
        return min(1_000, occupants * 2_000 / capacity)
    }

    public var price: Money {
        land + building
    }

    /// The gain realized, or the loss when negative: the price less the
    /// book value.
    public var gain: Money {
        price - bookValue
    }
}

extension GameWorld {
    // MARK: - Queries

    /// What selling the company's building `id` brings in now (decision
    /// 130), or `nil` for a building that does not exist. Free play keeps
    /// no accounts: a sale there brings nothing and is measured against
    /// nothing.
    public func saleQuote(of id: PlacedBuildingID) -> PlacedBuildingSaleQuote? {
        guard let building = placedBuilding(id: id) else { return nil }
        let capacity = building.kind.capacity
        let occupants = building.residents + building.jobs
        guard accounts.mode == .management else {
            return PlacedBuildingSaleQuote(
                landRight: .zero, buildingBookValue: .zero, occupants: occupants, capacity: capacity.residents + capacity.jobs, bookValue: .zero
            )
        }
        let value = landTerms(of: building).value
        let record = accounts.assets.first { $0.kind == .building && $0.owner == id.rawValue }
        let buildingBookValue = record.map { record in
            let written = AssetRecord.share(of: building.buildingCost, numerator: record.days, denominator: record.kind.assetClass.lifeDays)
            return min(record.bookValue, building.buildingCost - written)
        } ?? .zero
        return PlacedBuildingSaleQuote(
            landRight: Money(building.kind.footprintArea * value), buildingBookValue: buildingBookValue,
            occupants: occupants, capacity: capacity.residents + capacity.jobs, bookValue: record?.bookValue ?? .zero
        )
    }

    // MARK: - Commands

    /// Sells the company's building `id` (decision 130): a managed company
    /// receives its ``saleQuote(of:)`` price, takes its asset record off the
    /// books and realizes the gain or loss against its book value (decision
    /// 85's capital days: ``CapitalDay/saleProceeds`` and
    /// ``CapitalDay/saleBookValue``). The building stays and becomes the
    /// city's: its residents and jobs move onto the cell of land under it
    /// (``handOverToCity(_:)``), and the cells it claimed are the city's to
    /// grow on again. Its ID is not handed out again. Free play sells for
    /// nothing, and the city takes the building over all the same.
    ///
    /// - Throws: ``GameError/unknownPlacedBuilding(_:)``.
    @discardableResult
    public mutating func sellPlacedBuilding(_ id: PlacedBuildingID) throws(GameError) -> PlacedBuildingSaleQuote {
        guard let building = placedBuilding(id: id), let quote = saleQuote(of: id) else { throw .unknownPlacedBuilding(id) }
        placedBuildings.removeAll { $0.id == id }
        sellAsset(.building, owner: id.rawValue, for: quote.price)
        handOverToCity(building)
        refreshLandDemand()
        return quote
    }

    // MARK: - Handing over

    /// The cell of land a sold building's people move to: the cell under
    /// its centre, or for a building on the shore whose centre is over the
    /// water, the first cell under it on land, by row and then column;
    /// `nil` when every cell under it is water.
    func handOverCell(of building: PlacedBuilding) -> CellPosition? {
        let centre = CellPosition(row: Land.cellIndex(building.centre.y), column: Land.cellIndex(building.centre.x))
        guard terrain.isWater(row: centre.row, column: centre.column) else { return centre }
        let firstRow = Land.cellIndex(building.minY), lastRow = Land.cellIndex(building.maxY - 1)
        let firstColumn = Land.cellIndex(building.minX), lastColumn = Land.cellIndex(building.maxX - 1)
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn where !terrain.isWater(row: row, column: column) {
                return CellPosition(row: row, column: column)
            }
        }
        return nil
    }

    /// Hands `building`, sold, over to the city (decision 130): its
    /// residents and jobs move onto ``handOverCell(of:)``. A cell with no
    /// one becomes a cell of the building's use; one with people keeps its
    /// use and adds them (a park, which holds no one, takes the building's
    /// use), each count stopping at ``Land/maximumPerCell``. With the
    /// city's buildings on, the cell's building stays if it still holds
    /// the cell's main count, and is otherwise pulled down for the one that
    /// holds it, numbered after every other; with no number left, the land
    /// stays as it was and the people leave, as growth does. A building
    /// with no one in it leaves no land.
    mutating func handOverToCity(_ building: PlacedBuilding) {
        guard building.residents + building.jobs > 0, let position = handOverCell(of: building) else { return }
        guard let cell = land.cell(row: position.row, column: position.column) else {
            addLand(LandCell(row: position.row, column: position.column, use: building.kind.use, residents: building.residents, jobs: building.jobs))
            return
        }
        let merged = LandCell(
            row: cell.row, column: cell.column, use: cell.use == .park ? building.kind.use : cell.use,
            residents: min(Land.maximumPerCell, cell.residents + building.residents),
            jobs: min(Land.maximumPerCell, cell.jobs + building.jobs)
        )
        if cityBuildings, let standing = buildings.building(row: cell.row, column: cell.column) {
            let holds = standing.capacity(on: merged)
            let fits = standing.use == merged.use
                && Building.mainCount(of: merged.use, residents: holds.residents, jobs: holds.jobs)
                    >= Building.mainCount(of: merged.use, residents: merged.residents, jobs: merged.jobs)
            if !fits {
                guard let id = buildings.nextID else { return }
                buildings.remove(on: [position])
                buildings.append(Building.fitting(merged, id: id))
            }
        }
        guard let index = land.cells.firstIndex(where: { $0.position == position }) else { return }
        land.cells[index] = merged
    }
}
