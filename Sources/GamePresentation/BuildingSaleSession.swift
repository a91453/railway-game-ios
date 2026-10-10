import GameCore

// Selling the company's buildings (city building P0-D, ARCHITECTURE decision
// 130): in the building tool's sell mode a tap chooses one of the company's
// buildings (BuildingSession.swift); the map marks it, the card shows what
// it would bring in, part by part, and the gain or loss against its book
// value, and the action button or the map's pill sells it, as one edit that
// undo takes back. GameCore works out every number (`saleQuote(of:)`).

/// What selling ``GameSession/saleCandidate`` would do (decision 130).
public struct BuildingSalePreview: Hashable, Sendable {
    public let building: PlacedBuilding
    public let quote: PlacedBuildingSaleQuote
}

extension GameSession {
    /// What selling the ``saleCandidate`` would bring in; `nil` without
    /// one, or in another mode or tool.
    public var salePreview: BuildingSalePreview? {
        guard tool == .building, buildingMode == .sell, let id = saleCandidate,
              let building = world.placedBuilding(id: id), let quote = world.saleQuote(of: id)
        else { return nil }
        return BuildingSalePreview(building: building, quote: quote)
    }

    /// The card's lines for the ``salePreview``: the building and how full
    /// it is, the land's part, the building's part, the price against the
    /// book value, and the gain or loss. Free play sells for nothing.
    public var salePreviewLines: [String] {
        guard let preview = salePreview else { return [] }
        let quote = preview.quote, building = preview.building
        let name = language.text(
            "\(building.kind.title(in: .english)) #\(building.id.rawValue)", "\(building.kind.title(in: .traditionalChinese)) #\(building.id.rawValue)"
        )
        let full = quote.capacity > 0 ? quote.occupants * 100 / quote.capacity : 0
        let people = language.text(
            "\(name) · \(quote.occupants) of \(quote.capacity) people (\(full)%)", "\(name) · 入住 \(quote.occupants) / \(quote.capacity) 人（\(full)%）"
        )
        guard world.accounts.mode == .management else {
            return [people, language.text("Free play: the city takes it over for nothing.", "自由模式：免費交給城市接手。")]
        }
        let percent = PlacedBuildingRules.saleLandPercent
        let land = language.text(
            "Land: \(percent)% of its right now \(quote.landRight.moneyText) = \(quote.land.moneyText)",
            "土地：目前的土地使用權 \(quote.landRight.moneyText) × \(percent)% = \(quote.land.moneyText)"
        )
        let factor = quote.occupancyFactor / 10
        let buildingLine = quote.occupancyFactor >= 1_000
            ? language.text(
                "Building: book value \(quote.buildingBookValue.moneyText), in full at half full = \(quote.building.moneyText)",
                "建物：帳面價值 \(quote.buildingBookValue.moneyText)，入住過半全額 = \(quote.building.moneyText)"
            )
            : language.text(
                "Building: book value \(quote.buildingBookValue.moneyText) × \(factor)% (under half full) = \(quote.building.moneyText)",
                "建物：帳面價值 \(quote.buildingBookValue.moneyText) × \(factor)%（入住未過半）= \(quote.building.moneyText)"
            )
        let price = language.text(
            "Price \(quote.price.moneyText) · on the books at \(quote.bookValue.moneyText)",
            "售價 \(quote.price.moneyText) · 帳面價值 \(quote.bookValue.moneyText)"
        )
        return [people, land, buildingLine, price, gainText(quote.gain)]
    }

    /// The gain or loss selling the ``saleCandidate`` would realize, for
    /// the map's pill; `nil` without one or in free play, which keeps no
    /// accounts.
    public var saleGainText: String? {
        guard world.accounts.mode == .management, let quote = salePreview?.quote else { return nil }
        return gainText(quote.gain)
    }

    /// "Realized gain $ 1,200" or "Realized loss $ 3,400".
    func gainText(_ gain: Money) -> String {
        gain < .zero
            ? language.text("Realized loss \(Money(0 - gain.amount).moneyText)", "已實現損失 \(Money(0 - gain.amount).moneyText)")
            : language.text("Realized gain \(gain.moneyText)", "已實現利益 \(gain.moneyText)")
    }

    /// Sells the ``saleCandidate`` with ``GameWorld/sellPlacedBuilding(_:)``,
    /// as one edit that undo takes back, reports what it brought in and the
    /// gain or loss in ``message``, and clears the candidate once sold.
    @discardableResult
    public func confirmSale() -> Bool {
        guard let id = saleCandidate else {
            message = StatusMessage(kind: .failure, text: language.text("Tap one of your buildings to sell it.", "請點選要出售的建物。"))
            return false
        }
        guard let building = world.placedBuilding(id: id) else {
            saleCandidate = nil
            message = StatusMessage(kind: .failure, text: GameError.unknownPlacedBuilding(id).playerMessage(in: language))
            return false
        }
        let managed = world.accounts.mode == .management
        let name = { (language: DisplayLanguage) in "\(building.kind.title(in: language)) #\(id.rawValue)" }
        let sold = perform { world throws(GameError) in
            let quote = try world.sellPlacedBuilding(id)
            guard managed else {
                return language.text("Handed \(name(.english).lowercased()) to the city.", "\(name(.traditionalChinese)) 交給城市接手。")
            }
            let gain = gainText(quote.gain)
            return language.text(
                "Sold \(name(.english).lowercased()) to the city for \(quote.price.moneyText). \(gain).",
                "\(name(.traditionalChinese)) 賣給城市，收入 \(quote.price.moneyText)。\(gain)。"
            )
        }
        if sold {
            saleCandidate = nil
        }
        return sold
    }

    /// Drops the building chosen to sell, without selling it: the map's
    /// cancel button beside it.
    public func clearSaleCandidate() {
        saleCandidate = nil
    }
}
