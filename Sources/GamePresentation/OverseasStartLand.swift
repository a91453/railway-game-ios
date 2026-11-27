import Foundation
import GameCore

// Decision 992 (OVERSEAS-BUY-LAND, the owner's choice of 2026-11-25 in
// decision 969's §3): a new game on Hong Kong's map starts with four tiles,
// two by two, about 33 km square, and buys the rest as its railway grows,
// as Japan's has since decision 969 and Taiwan's places since this one
// (``RealWorldExpansion``). Hong Kong's and Japan's maps can also be opened
// whole from the start, as the whole of Taiwan can; such a game counts no
// achievements (``GameWorld/wholeMapOpen``). Rovaniemi, the winter event's
// map, stays whole and counted. A game already played keeps what it had:
// an old Hong Kong game stays whole and counted.
//
// The owner's references have no map bought from a start of four tiles
// (gap, as for decisions 160 and 969). Which four on Hong Kong's map is
// this project's rule: the two by two with the most people.

extension OverseasMap {
    /// Decision 992: whether a new game on its map starts with four tiles
    /// and buys the rest, and the map picker also offers its whole map
    /// open (``wholeMapSummary(in:)``): Hong Kong's and Japan's; not
    /// Rovaniemi's, which is whole.
    public var buysLand: Bool {
        switch self {
        case .hongKong, .fukuoka: true
        case .rovaniemi: false
        }
    }

    /// The name of its map picker row that opens the whole map
    /// (``buysLand``).
    public func wholeMapName(in language: DisplayLanguage) -> String {
        let name = pickerName(in: language)
        return language.text("\(name): the whole map", "\(name)（整張全開）")
    }

    /// Decision 999: what the map picker's rows call its map: Japan for
    /// Fukuoka's, whose map is several prefectures since decision 991; the
    /// city's name for the rest.
    public func pickerName(in language: DisplayLanguage) -> String {
        switch self {
        case .fukuoka: language.text("Japan", "日本")
        case .hongKong, .rovaniemi: name(in: language)
        }
    }

    /// What the row of its whole map says (``buysLand``); `nil` for a map
    /// that is whole anyway.
    public func wholeMapSummary(in language: DisplayLanguage) -> String? {
        switch self {
        case .hongKong: language.text(
            "The whole of Hong Kong, about 63 by 45 km, all open from the start with no land to buy. Achievements and rankings do not count it.",
            "整個香港，約 63 × 45 公里，一開始全部開放、不用買地。不計成就與排名。"
        )
        case .fukuoka: language.text(
            "The whole of the Japan map, the Fukuoka, Saga, Nagasaki and Kumamoto prefectures, all open from the start with no land to buy. Achievements and rankings do not count it. With a large network, older devices may slow down.",
            "日本整張地圖，福岡、佐賀、長崎、熊本四縣，一開始全部開放、不用買地。不計成就與排名。路網蓋得大時，較舊的裝置可能變慢。"
        )
        case .rovaniemi: nil
        }
    }
}

extension OverseasGround {
    /// Decision 992: the tiles a new game on this map starts with, by row
    /// and then column: on a map that grew or names where its games
    /// begin, the layout's (``MapPack/Layout/startTiles``, decisions 969
    /// and 991, the first place's); on one that
    /// did not, the two by two with the most people in the pack's
    /// `population.json`, the first by row and then column where two have
    /// as many; the world's first two by two for a pack without people.
    /// Empty for a map that is whole (``OverseasMap/buysLand``) or smaller
    /// than two tiles by two.
    public var startTiles: [MapTile] {
        guard city.buysLand else { return [] }
        // Decision 991: or those round where a new game begins.
        if layout.anchorBounds != nil || !layout.starts.isEmpty { return layout.startTiles }
        let length = MapExpansion.tileLength
        let rows = Int((bounds.height + length - 1) / length), columns = Int((bounds.width + length - 1) / length)
        guard rows >= 2, columns >= 2 else { return [] }
        let frame = RealWorldFrame(anchor: anchor, bounds: bounds)
        var best: (tiles: [MapTile], residents: Int64)?
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let tiles = [MapTile(row: row, column: column), MapTile(row: row, column: column + 1),
                             MapTile(row: row + 1, column: column), MapTile(row: row + 1, column: column + 1)]
                let residents = self.residents(of: tiles, frame: frame)
                if residents > (best?.residents ?? -1) { best = (tiles, residents) }
            }
        }
        return best?.tiles ?? []
    }

    /// The people of the pack's `population.json` whose cells' middles lie
    /// in the box of `tiles` on the world of `frame`; 0 without people.
    func residents(of tiles: [MapTile], frame: RealWorldFrame) -> Int64 {
        guard let population, let top = tiles.map(\.row).min(), let bottom = tiles.map(\.row).max(),
              let left = tiles.map(\.column).min(), let right = tiles.map(\.column).max() else { return 0 }
        let length = Double(MapExpansion.tileLength)
        let northWest = frame.coordinate(worldX: Double(left) * length, worldY: Double(top) * length)
        let southEast = frame.coordinate(
            worldX: min(Double(right + 1) * length, Double(bounds.width)), worldY: min(Double(bottom + 1) * length, Double(bounds.height))
        )
        let cells = population.cells(north: northWest.latitude, south: southEast.latitude, west: northWest.longitude, east: southEast.longitude)
        return cells.reduce(Int64(0)) { sum, cell in
            let inside = (southEast.latitude..<northWest.latitude).contains(cell.centerLatitude)
                && (northWest.longitude..<southEast.longitude).contains(cell.centerLongitude)
            return inside ? sum + Int64(cell.count) : sum
        }
    }
}

extension GameWorld {
    /// Decision 992: a new game on a city's map (``newOverseasGame(_:balance:eventSeed:)``),
    /// opened whole when `wholeMap` (marked so, ``openWholeMap()``: it
    /// counts no achievements), else starting with the four tiles of
    /// ``OverseasGround/startTiles`` and buying the rest, each asking the
    /// riders their people call for, as a grown map's do
    /// (``OverseasGround/ridersStep(owning:in:)``). A map that is whole
    /// anyway (Rovaniemi) is whole and not marked, either way.
    /// Decision 991: a game that buys its land begins round the `start`th
    /// of the map's places (``MapPack/Layout/starts``).
    public static func newOverseasGame(
        _ ground: OverseasGround, wholeMap: Bool, balance: Money = startingBalance, eventSeed: UInt32 = 1, start: Int = 0
    ) -> GameWorld {
        guard ground.city.buysLand else { return newOverseasGame(ground, balance: balance, eventSeed: eventSeed, start: start) }
        guard wholeMap else {
            var world = newOverseasGame(ground, balance: balance, eventSeed: eventSeed, start: start)
            let tiles = ground.startTiles
            if world.mapExpansion == nil, !tiles.isEmpty {
                do throws(GameError) {
                    try world.enableMapExpansion(owning: tiles, townSeed: nil, ridersStep: ground.ridersStep(owning: tiles, in: world))
                } catch {
                    // Four tiles of the world, side by side, nothing built.
                    preconditionFailure("Could not buy the map of \(ground.city): \(error)")
                }
            }
            return world
        }
        // Laid as a game on the map is (``newOverseasGame(_:balance:eventSeed:)``),
        // over the first extent of a map that grew and grown to the map as
        // it is now, but with no land to buy.
        var world = newGame(
            anchor: ground.anchor, bounds: ground.layout.anchorBounds ?? ground.bounds, balance: balance, eventSeed: eventSeed, land: []
        )
        world.setLandOnDemand()
        world.setFarDemand(true)
        do throws(GameError) {
            if world.bounds != ground.bounds { try world.growMap(to: ground.bounds) }
            try world.openWholeMap()
        } catch {
            // A new world grows to its own map, and buys none of it.
            preconditionFailure("Could not open the whole map of \(ground.city): \(error)")
        }
        return world
    }
}

// Decision 999 (the owner, 2026-11-26: 「開圖也能選 熊本開局 福岡開局 佐賀開局等」):
// a map whose pack names several places to begin (decision 991's
// `starts`) has a map picker row for each, and a new game picked there
// owns the 2 × 2 tiles round that place (``MapPack/Layout/startTiles(at:)``).

/// Decision 999: one row of the map picker that starts a new game on a
/// city's map (``GameLauncher/overseasStartRows(for:in:)``).
public struct OverseasStartRow: Equatable, Sendable {
    public let city: OverseasMap
    /// Which of the map's places the game begins round
    /// (``MapPack/Layout/starts``), 0 for the first.
    public let start: Int
    /// Its accessibility identifier: the city's row's for the first
    /// place, as it was before there was a choice.
    public let id: String
    public let name: String
    public let summary: String
}

extension GameLauncher {
    /// Decision 999: the rows that start a new game on `row`'s map: one
    /// for each place its pack names to begin round, while the map is open
    /// and names more than one; else the one row of the city.
    public func overseasStartRows(for row: OverseasMapRow, in language: DisplayLanguage) -> [OverseasStartRow] {
        let city = row.city, id = "realWorld.overseas.\(city.rawValue)"
        let layout = overseasGrounds.first { $0.city == city }?.layout ?? overseasAwaited.first { $0.city == city }?.layout
        guard row.closed == nil, city.buysLand, let starts = layout?.starts, starts.count > 1 else {
            return [OverseasStartRow(city: city, start: 0, id: id, name: city.pickerName(in: language), summary: city.mapSummary(in: language))]
        }
        let map = city.pickerName(in: language)
        return starts.enumerated().map { index, start in
            let place = language.text(start.englishName, start.name)
            return OverseasStartRow(
                city: city, start: index, id: index == 0 ? id : "\(id).start.\(index)",
                name: language.text("\(map): start in \(place)", "\(map)：從\(place)開始"),
                summary: index == 0 ? city.mapSummary(in: language) : language.text(
                    "You start with about 33 by 33 km round \(place) and buy the rest of the map as your railway grows.",
                    "一開始是\(place)一帶約 33 × 33 公里，地圖其餘部分用買的。"
                )
            )
        }
    }
}
