import GameCore

// What the inspector shows of a company building the select tool picked
// (ARCHITECTURE decision 173): for a trading subsidiary its books, return
// and what selling it would bring; for the others what they hold.

extension GameSession {
    /// The inspector's text for the company's building `id`, or `nil` for an
    /// ID the world does not have.
    func buildingInspectorText(of id: PlacedBuildingID) -> String? {
        guard let building = world.placedBuilding(id: id) else { return nil }
        let name = "\(building.kind.title(in: language)) #\(id.rawValue)"
        let capacity = building.kind.capacity
        let people = language.text(
            "\(building.residents + building.jobs) of \(capacity.residents + capacity.jobs) people",
            "入住 \(building.residents + building.jobs) / \(capacity.residents + capacity.jobs) 人"
        )
        guard building.kind.isSubsidiary, world.accounts.mode == .management else {
            return "\(name) · \(people)"
        }
        let books = building.books
        func line(_ title: String, _ month: SubsidiaryMonth) -> String {
            language.text(
                "\(title): sales \(month.sales.moneyText), costs \(month.cost.moneyText), profit \(month.profit.moneyText)",
                "\(title)：營收 \(month.sales.moneyText)、成本 \(month.cost.moneyText)、損益 \(month.profit.moneyText)"
            )
        }
        let total = language.text(
            "Since opening: profit \(books.totalProfit.moneyText)", "開業以來：損益 \(books.totalProfit.moneyText)"
        )
        let cost = building.cost.amount
        let roi = cost > 0 ? books.trailingProfit.amount * 1_000 / cost : 0
        let yield = language.text(
            "12-month return \(Self.tenthsText(roi))% of its cost", "近 12 個月報酬率 \(Self.tenthsText(roi))%（占造價）"
        )
        let price = world.saleQuote(of: id)?.price ?? .zero
        let estimate = language.text("Would sell for \(price.moneyText)", "估計售價 \(price.moneyText)")
        return [
            "\(name) · \(people)",
            line(language.text("This month", "本月"), books.thisMonth),
            line(language.text("Last month", "上月"), books.lastMonth),
            total, yield, estimate,
        ].joined(separator: "\n")
    }

    /// Tenths of a percent as "12.5" or "-0.5".
    static func tenthsText(_ tenths: Int64) -> String {
        let sign = tenths < 0 ? "-" : ""
        let magnitude = abs(tenths)
        return "\(sign)\(magnitude / 10).\(magnitude % 10)"
    }
}
