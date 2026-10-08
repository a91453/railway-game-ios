import GameCore

// City building P0-A (ARCHITECTURE decision 92): the building tool places
// the chosen building where the player taps, through GameCore; since P0-C1
// (decision 94) a managed company pays for it, and the tool can demolish the
// company's buildings too.

/// What a tap with the building tool does (decision 94).
public enum BuildingToolMode: CaseIterable, Hashable, Sendable {
    case build
    case demolish

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .build: language.text("Build", "建造")
        case .demolish: language.text("Demolish", "拆除")
        }
    }
}

extension PlacedBuildingKind {
    /// Its name in the building tool.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .house: language.text("House", "小住宅")
        case .shop: language.text("Shop", "商店")
        case .office: language.text("Office block", "辦公樓")
        }
    }
}

extension GameSession {
    /// A tap with the building tool at `point`: in ``BuildingToolMode/build``
    /// it places ``buildingKind`` there (``placeBuilding(at:)``), in
    /// ``BuildingToolMode/demolish`` it demolishes the company's building
    /// there or within `reach` of it, the one whose centre is nearest.
    @discardableResult
    public func tapBuildingTool(at point: PlanPoint, reach: Int64) -> Bool {
        switch buildingMode {
        case .build:
            return placeBuilding(at: point)
        case .demolish:
            let near = world.placedBuildings.filter { building in
                point.x >= building.minX - reach && point.x < building.maxX + reach
                    && point.y >= building.minY - reach && point.y < building.maxY + reach
            }
            guard let building = near.min(by: { distance($0, point) < distance($1, point) }) else {
                message = StatusMessage(kind: .failure, text: language.text("Tap one of your buildings to demolish it.", "請點選要拆除的建物。"))
                return false
            }
            return demolishBuilding(building.id)
        }
    }

    /// Places a building of ``buildingKind`` centred on `point` with
    /// ``GameWorld/placeBuilding(_:at:)``, as one edit that undo takes
    /// back, and reports the outcome, with what it cost a managed company,
    /// in ``message``. Returns whether it was placed.
    @discardableResult
    public func placeBuilding(at point: PlanPoint) -> Bool {
        let kind = buildingKind
        return perform { world throws(GameError) in
            let building = try world.placeBuilding(kind, at: point)
            guard building.cost > .zero else {
                return language.text(
                    "Built \(kind.title(in: .english).lowercased()) #\(building.id.rawValue).",
                    "蓋好\(kind.title(in: .traditionalChinese)) #\(building.id.rawValue)。"
                )
            }
            return language.text(
                "Built \(kind.title(in: .english).lowercased()) #\(building.id.rawValue) for \(building.cost.moneyText).",
                "蓋好\(kind.title(in: .traditionalChinese)) #\(building.id.rawValue)，花費 \(building.cost.moneyText)。"
            )
        }
    }

    /// Demolishes the company's building `id` with
    /// ``GameWorld/removePlacedBuilding(_:)``, as one edit that undo takes
    /// back, and reports the outcome in ``message``.
    @discardableResult
    public func demolishBuilding(_ id: PlacedBuildingID) -> Bool {
        guard let building = world.placedBuilding(id: id) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownPlacedBuilding(id).playerMessage(in: language))
            return false
        }
        let fee = world.demolitionCost(of: building)
        let name = { (language: DisplayLanguage) in building.kind.title(in: language) }
        return perform { world throws(GameError) in
            try world.removePlacedBuilding(id)
            guard fee > .zero else {
                return language.text(
                    "Demolished \(name(.english).lowercased()) #\(id.rawValue).", "拆除\(name(.traditionalChinese)) #\(id.rawValue)。"
                )
            }
            return language.text(
                "Demolished \(name(.english).lowercased()) #\(id.rawValue) for \(fee.moneyText).",
                "拆除\(name(.traditionalChinese)) #\(id.rawValue)，花費 \(fee.moneyText)。"
            )
        }
    }

    /// How many buildings the player has placed, and who lives and works in
    /// them once anyone does, for the building tool.
    public var placedBuildingsText: String {
        let count = world.placedBuildings.count
        let placed = language.text(count == 1 ? "1 building placed" : "\(count) buildings placed", "已蓋 \(count) 棟")
        let residents = world.placedBuildings.reduce(Int64(0)) { $0 + $1.residents }
        let jobs = world.placedBuildings.reduce(Int64(0)) { $0 + $1.jobs }
        guard residents + jobs > 0 else { return placed }
        return placed + language.text(" · \(residents) residents, \(jobs) jobs", " · 居民 \(residents) 人、就業 \(jobs) 個")
    }

    /// What a managed company's buildings earn and cost a day as things
    /// stand, to the cent (a day's upkeep is a few dollars), or `nil`
    /// without any (or in free play).
    public var buildingEconomyText: String? {
        guard world.accounts.mode == .management, !world.placedBuildings.isEmpty else { return nil }
        var rent = Money.zero, costs = Money.zero
        for building in world.placedBuildings {
            rent = rent + world.dailyRent(of: building)
            let upkeep = world.dailyUpkeep(of: building)
            costs = costs + upkeep.upkeep + upkeep.tax
        }
        return language.text(
            "Rent \(rent.centsText) a day · upkeep and land tax \(costs.centsText)",
            "每日租金 \(rent.centsText) · 維護與土地資產稅 \(costs.centsText)"
        )
    }

    /// What ``buildingKind`` costs a managed company: its building, and the
    /// land under it at that land's value; `nil` in free play, where it is
    /// free.
    public var buildingQuoteText: String? {
        guard world.accounts.mode == .management else { return nil }
        let kind = buildingKind
        let building = Money(kind.floorArea * PlacedBuildingRules.floorCost.amount)
        return language.text(
            "\(kind.title(in: .english)): \(building.moneyText) to build, plus the land's value for \(kind.footprintArea) m²",
            "\(kind.title(in: .traditionalChinese))：建造費 \(building.moneyText)，另加 \(kind.footprintArea) m² 的土地使用權（依地價）"
        )
    }

    private func distance(_ building: PlacedBuilding, _ point: PlanPoint) -> Int64 {
        let dx = building.centre.x - point.x, dy = building.centre.y - point.y
        return dx * dx + dy * dy
    }
}
