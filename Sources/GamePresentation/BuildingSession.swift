import GameCore

// City building P0-A (ARCHITECTURE decision 92): the building tool places
// the chosen building where the player taps, through GameCore.

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
    /// Places a building of ``buildingKind`` centred on `point` with
    /// ``GameWorld/placeBuilding(_:at:)``, as one edit that undo takes
    /// back, and reports the outcome in ``message``. Returns whether it
    /// was placed.
    @discardableResult
    public func placeBuilding(at point: PlanPoint) -> Bool {
        let kind = buildingKind
        return perform { world throws(GameError) in
            let building = try world.placeBuilding(kind, at: point)
            return language.text(
                "Built \(kind.title(in: .english).lowercased()) #\(building.id.rawValue).",
                "蓋好\(kind.title(in: .traditionalChinese)) #\(building.id.rawValue)。"
            )
        }
    }

    /// How many buildings the player has placed, for the building tool.
    public var placedBuildingsText: String {
        let count = world.placedBuildings.count
        return language.text(count == 1 ? "1 building placed" : "\(count) buildings placed", "已蓋 \(count) 棟")
    }
}
