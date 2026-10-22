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

    /// Whether the map shows its button to expand the map: in a game that
    /// buys its map, while choosing a tile (the button then ends it) or
    /// with no building tool out and no tutorial. Beside the building
    /// tools' Done button it was tapped by mistake, and a tap on the map
    /// and ✓ then bought a tile (TestFlight 56.1).
    public var showsMapExpansionButton: Bool {
        buysMap && (isChoosingMapTile || (tool == .select && tutorial == nil))
    }

    /// Decision 336: whether `problem`, shown while building or in the
    /// banner, is the refusal of land not bought yet, in a game that buys
    /// its map: beside it a button goes to expanding the map
    /// (``startChoosingMapTile()``), which the map's own button is hidden
    /// for while a building tool is out.
    public func offersMapExpansion(for problem: String?) -> Bool {
        guard buysMap, !isChoosingMapTile, tutorial == nil, let problem else { return false }
        // The refusal names no tile: any tile's says the same.
        return problem == GameError.mapTileNotOwned(MapTile(row: 0, column: 0)).playerMessage(in: language)
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

    /// Starts choosing a tile to buy: the select tool, nothing selected,
    /// and a running game paused as the building tools pause it (decision
    /// 99), so a tile bought can be undone until the player stops choosing
    /// (decision 160, later). From a building tool that paused it, the
    /// game is resumed and paused again in this one call, so no time runs
    /// between.
    public func startChoosingMapTile() {
        guard buysMap else { return }
        selectTool(.select)
        clearSelection()
        isChoosingMapTile = true
        chosenMapTile = nil
        let paused = pauseForBuilding()
        let tap = world.mapTilesForSale().isEmpty
            ? language.text("You own the whole map.", "整張地圖都是你的了。")
            : language.text("Tap a tile next to your land to see its price.", "點選和你的土地相鄰的一塊，看看價格。")
        message = StatusMessage(
            kind: .success,
            text: paused
                ? tap + language.text(" The game pauses while you expand, and a tile bought can be undone.", "擴建時遊戲暫停，買下的地可以復原。")
                : tap
        )
    }

    /// Lets go of the tile chosen, still choosing: the pill's cancel.
    public func clearChosenMapTile() {
        chosenMapTile = nil
    }

    /// Stops choosing a tile to buy, lets go of the one chosen, and resumes
    /// the game ``startChoosingMapTile()`` paused.
    public func stopChoosingMapTile() {
        guard isChoosingMapTile else { return }
        endChoosingMapTile()
        endPauseForBuilding()
    }

    /// Stops choosing a tile to buy, and lets go of the one chosen; the
    /// pause is the next tool's to keep or end (``selectTool(_:)``).
    func endChoosingMapTile() {
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
        let needed = Money(expansion.ridersNeeded(toOwn: expansion.owned.count + 1)).displayText
        return language.text(
            "\(owned) · the next \(price), from \(needed) riders a day (best \(Money(expansion.bestDayRiders).displayText))",
            "\(owned) · 下一塊 \(price)，每日運量 \(needed) 人次解鎖（目前最佳 \(Money(expansion.bestDayRiders).displayText)）"
        )
    }

    /// Buys the ``chosenMapTile`` with ``GameWorld/buyMapTile(_:)``, as one
    /// edit that undo takes back, says so in ``message``, and lets go of
    /// it once bought, still choosing: the game stays paused, so the buy
    /// can be undone, until the player stops choosing (decision 160,
    /// later).
    @discardableResult
    public func buyChosenMapTile() -> Bool {
        guard let tile = chosenMapTile else {
            message = StatusMessage(kind: .failure, text: language.text("Tap a tile to buy first.", "請先點選要買的一塊。"))
            return false
        }
        let towns = world.mapExpansion?.townSeed != nil
        let bought = perform(.buyMapTile(tile)) { _, before, _ in
            let price = before.mapExpansion?.nextPrice ?? .zero
            return towns
                ? language.text("Bought the tile for \(price.moneyText). Its towns wait for your railway.", "以 \(price.moneyText) 買下這一塊，那裡的城鎮正等著你的鐵路。")
                : language.text("Bought the tile for \(price.moneyText).", "以 \(price.moneyText) 買下這一塊。")
        }
        if bought != nil {
            chosenMapTile = nil
        }
        return bought != nil
    }
}

/// A lock on a tile of the map not bought yet (decision 167, later): the
/// tiles beside the land owned, the ones the player can buy next, each
/// carry one while the player is not choosing a tile; a tap on it opens
/// that tile's card (``GameSession/openMapLock(_:)``). The tiles further
/// out are only shaded. The lock is open once the best day has unlocked
/// the tile, shut until then.
public struct MapLock: Hashable, Sendable, Identifiable {
    public let tile: MapTile
    /// Where the lock stands on the screen: the middle of the part of the
    /// tile in view.
    public let at: ScreenPoint
    /// Whether the best day has unlocked the tile (always, in free play).
    public let isUnlocked: Bool

    public var id: MapTile { tile }

    /// The smallest part of a tile in view, each way, that gets a lock, in
    /// points: a sliver along the screen's edge, or a tile zoomed out to a
    /// few points, gets none.
    public static let smallestPart: Double = 56
}

extension GameSession {
    /// Whether the map shows its locks: in a game that buys its map, with
    /// no building tool out, no tutorial and no tile being chosen (then
    /// the tiles for sale show their prices instead).
    public var showsMapLocks: Bool {
        buysMap && !isChoosingMapTile && tool == .select && tutorial == nil
    }

    /// The locks on the tiles for sale in view through `projection` on a
    /// `viewport`, clear of what floats over its edges (`insets`); none
    /// unless ``showsMapLocks``.
    public func mapLocks(on projection: some MapProjection, viewport: ScreenSize, clearOf insets: ScreenInsets = ScreenInsets()) -> [MapLock] {
        guard showsMapLocks else { return [] }
        let clear = (
            minX: insets.leading, minY: insets.top,
            maxX: viewport.width - insets.trailing, maxY: viewport.height - insets.bottom
        )
        return world.mapTilesForSale().compactMap { tile in
            guard let quote = world.mapTileQuote(tile) else { return nil }
            let area = world.mapArea(of: tile)
            let corners = [
                projection.screenPoint(worldX: Double(area.minX), worldY: Double(area.minY)),
                projection.screenPoint(worldX: Double(area.maxX), worldY: Double(area.maxY)),
            ]
            let minX = max(clear.minX, corners.map(\.x).min()!), maxX = min(clear.maxX, corners.map(\.x).max()!)
            let minY = max(clear.minY, corners.map(\.y).min()!), maxY = min(clear.maxY, corners.map(\.y).max()!)
            guard maxX - minX >= MapLock.smallestPart, maxY - minY >= MapLock.smallestPart else { return nil }
            return MapLock(tile: tile, at: ScreenPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), isUnlocked: quote.isUnlocked)
        }
    }

    /// A lock tapped: starts choosing a tile, as the Expand button does,
    /// with `tile` chosen, so its card shows at once. `false`, and nothing
    /// changes, for a tile not for sale.
    @discardableResult
    public func openMapLock(_ tile: MapTile) -> Bool {
        guard showsMapLocks, world.mapTilesForSale().contains(tile) else { return false }
        startChoosingMapTile()
        chosenMapTile = tile
        message = nil
        return true
    }
}
