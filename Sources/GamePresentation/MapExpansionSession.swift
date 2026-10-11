import GameCore

// Buying the map (ARCHITECTURE decision 160): on a blank map bought tile by
// tile, the land the company does not own yet is shaded on the map. The
// "Expand" button marks the tiles for sale, each with its price; a tap
// chooses one, the pill beside it says what it costs and whether the best
// day has unlocked it, and buys it, as one edit that undo takes back.
// GameCore decides what may be bought and what it costs (`buyMapTile`,
// `mapTileQuote`).

/// What the map draws of the tiles of the map (decision 160).
public struct MapExpansionOverlay: Hashable, Sendable {
    /// The ground the company owns, tile by tile.
    public var owned: [PlanRect]
    /// The tiles for sale while the player chooses one: where, the price
    /// and whether the best day has unlocked it.
    public var forSale: [Tile]
    /// The tile chosen to buy.
    public var chosen: PlanRect?

    public struct Tile: Hashable, Sendable {
        public let area: PlanRect
        public let price: Money
        public let isUnlocked: Bool
    }

    /// The tiles owned and for sale together: what the map shows while the
    /// player chooses one.
    public var region: WorldRegion? {
        let areas = owned + forSale.map(\.area)
        guard let first = areas.first else { return nil }
        return areas.dropFirst().reduce(
            WorldRegion(minX: Double(first.minX), minY: Double(first.minY), maxX: Double(first.maxX), maxY: Double(first.maxY))
        ) { region, area in
            WorldRegion(
                minX: min(region.minX, Double(area.minX)), minY: min(region.minY, Double(area.minY)),
                maxX: max(region.maxX, Double(area.maxX)), maxY: max(region.maxY, Double(area.maxY))
            )
        }
    }
}

extension WorldRegion {
    /// The tiles `world` owns of a map bought tile by tile (decision 160),
    /// the smallest rectangle round them; `nil` for a map that is not
    /// bought.
    public static func owned(in world: GameWorld) -> WorldRegion? {
        guard let owned = world.mapExpansion?.owned, let first = owned.first else { return nil }
        let length = Double(MapExpansion.tileLength)
        var region = WorldRegion(
            minX: Double(first.column) * length, minY: Double(first.row) * length,
            maxX: Double(first.column + 1) * length, maxY: Double(first.row + 1) * length
        )
        for tile in owned.dropFirst() {
            region.minX = min(region.minX, Double(tile.column) * length)
            region.minY = min(region.minY, Double(tile.row) * length)
            region.maxX = max(region.maxX, Double(tile.column + 1) * length)
            region.maxY = max(region.maxY, Double(tile.row + 1) * length)
        }
        region.maxX = min(region.maxX, Double(world.bounds.width))
        region.maxY = min(region.maxY, Double(world.bounds.height))
        return region
    }
}

extension GameSession {
    /// Whether this game buys its map tile by tile (decision 160).
    public var buysMap: Bool {
        world.mapExpansion != nil
    }

    /// The tiles of the map for the map to draw, or `nil` for a map that is
    /// not bought.
    public var mapExpansionOverlay: MapExpansionOverlay? {
        guard let expansion = world.mapExpansion else { return nil }
        func rect(_ tile: MapTile) -> PlanRect {
            let area = world.mapArea(of: tile)
            return PlanRect(minX: area.minX, minY: area.minY, maxX: area.maxX, maxY: area.maxY)
        }
        let forSale = isChoosingMapTile
            ? world.mapTilesForSale().compactMap { tile in
                world.mapTileQuote(tile).map { MapExpansionOverlay.Tile(area: rect(tile), price: $0.price, isUnlocked: $0.isUnlocked) }
            }
            : []
        return MapExpansionOverlay(owned: expansion.owned.map(rect), forSale: forSale, chosen: chosenMapTile.map(rect))
    }

    /// Starts choosing a tile to buy: the select tool, nothing selected.
    public func startChoosingMapTile() {
        guard buysMap else { return }
        selectTool(.select)
        clearSelection()
        isChoosingMapTile = true
        chosenMapTile = nil
        message = StatusMessage(
            kind: .success,
            text: world.mapTilesForSale().isEmpty
                ? language.text("You own the whole map.", "整張地圖都是你的了。")
                : language.text("Tap a tile next to your land to see its price.", "點選和你的土地相鄰的一塊，看看價格。")
        )
    }

    /// Lets go of the tile chosen, still choosing: the pill's cancel.
    public func clearChosenMapTile() {
        chosenMapTile = nil
    }

    /// Stops choosing a tile to buy, and lets go of the one chosen.
    public func stopChoosingMapTile() {
        isChoosingMapTile = false
        chosenMapTile = nil
    }

    /// A tap at `point` while choosing a tile: chooses the tile there if it
    /// is for sale, or says why it is not. Never changes the world.
    @discardableResult
    public func tapMapExpansion(at point: PlanPoint) -> Bool {
        guard isChoosingMapTile, world.bounds.contains(point) else { return false }
        let tile = MapExpansion.tile(at: point)
        guard world.mapTilesForSale().contains(tile) else {
            chosenMapTile = nil
            message = StatusMessage(
                kind: .failure,
                text: world.ownsMapTile(tile)
                    ? language.text("You own this tile already.", "這一塊已經是你的了。")
                    : GameError.mapTileNotAdjacent.playerMessage(in: language)
            )
            return false
        }
        chosenMapTile = tile
        message = nil
        return true
    }

    /// What buying the ``chosenMapTile`` would cost and change.
    public var chosenMapTileQuote: MapTileQuote? {
        guard isChoosingMapTile, let tile = chosenMapTile else { return nil }
        return world.mapTileQuote(tile)
    }

    /// The line over the pill's buttons: the riders it still needs, or the
    /// outside connections it would end; `nil` when there is nothing to
    /// say.
    public var chosenMapTileCaption: String? {
        guard let quote = chosenMapTileQuote else { return nil }
        guard quote.isUnlocked else {
            return language.text(
                "Unlocks at \(Money(quote.ridersNeeded).displayText) riders a day · best so far \(Money(quote.bestDayRiders).displayText)",
                "每日運量 \(Money(quote.ridersNeeded).displayText) 人次解鎖 · 目前最佳 \(Money(quote.bestDayRiders).displayText)"
            )
        }
        let names = quote.outsideConnectionsLost.compactMap { world.station(id: $0)?.name }
        guard !names.isEmpty else { return nil }
        let list = names.joined(separator: language.text(", ", "、"))
        return language.text(
            "\(list) will no longer be an outside connection",
            "\(list) 會變成一般車站，不再是外地連絡站"
        )
    }

    /// The map's tiles in a line, for the economy panel: how many are owned
    /// and what the next costs and needs; `nil` for a map that is not
    /// bought.
    public var mapExpansionText: String? {
        guard let expansion = world.mapExpansion else { return nil }
        let total = world.mapTileRows * world.mapTileColumns
        let owned = language.text("Map: \(expansion.owned.count) of \(total) tiles", "地圖：已擁有 \(expansion.owned.count) / \(total) 塊")
        guard expansion.owned.count < total else { return owned }
        let price = expansion.nextPrice.moneyText
        guard world.accounts.mode == .management else {
            return language.text("\(owned) · the next \(price)", "\(owned) · 下一塊 \(price)")
        }
        let needed = Money(MapExpansion.ridersNeeded(toOwn: expansion.owned.count + 1)).displayText
        return language.text(
            "\(owned) · the next \(price), from \(needed) riders a day (best \(Money(expansion.bestDayRiders).displayText))",
            "\(owned) · 下一塊 \(price)，每日運量 \(needed) 人次解鎖（目前最佳 \(Money(expansion.bestDayRiders).displayText)）"
        )
    }

    /// Buys the ``chosenMapTile`` with ``GameWorld/buyMapTile(_:)``, as one
    /// edit that undo takes back, says so in ``message``, and stops
    /// choosing once bought.
    @discardableResult
    public func buyChosenMapTile() -> Bool {
        guard let tile = chosenMapTile else {
            message = StatusMessage(kind: .failure, text: language.text("Tap a tile to buy first.", "請先點選要買的一塊。"))
            return false
        }
        let towns = world.mapExpansion?.townSeed != nil
        let bought = perform { world throws(GameError) in
            let price = world.mapExpansion?.nextPrice ?? .zero
            try world.buyMapTile(tile)
            return towns
                ? language.text("Bought the tile for \(price.moneyText). Its towns wait for your railway.", "以 \(price.moneyText) 買下這一塊，那裡的城鎮正等著你的鐵路。")
                : language.text("Bought the tile for \(price.moneyText).", "以 \(price.moneyText) 買下這一塊。")
        }
        if bought {
            stopChoosingMapTile()
        }
        return bought
    }
}
