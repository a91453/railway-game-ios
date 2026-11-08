import GameCore

// What the tourism panel, the map's star marks and the station master show
// of the sights (ARCHITECTURE decision 174), and the session's command for
// the souvenir shop, in English or Traditional Chinese (see
// ``DisplayLanguage``). All of it is read from the world; nothing here is
// kept.

extension StationMasterAdvice {
    /// `stars` hundredths of a star as "3.5★": whole and quarter stars
    /// keep their decimals ("3.25★").
    public static func starsText(_ stars: Int) -> String {
        let whole = stars / 100, rest = stars % 100
        if rest == 0 { return "\(whole)★" }
        if rest % 10 == 0 { return "\(whole).\(rest / 10)★" }
        return "\(whole).\(rest < 10 ? "0" : "")\(rest)★"
    }
}

extension Attraction {
    /// Its name in `language`.
    public func name(in language: DisplayLanguage) -> String {
        language.text(englishName, name)
    }

    /// Its rating before any hotel, "3.5★".
    public var starsText: String {
        StationMasterAdvice.starsText(stars)
    }
}

extension GameWorld {
    /// `attraction`'s rating now, with the hotels near it (decision 174),
    /// "3.75★".
    public func starsText(of attraction: Attraction) -> String {
        StationMasterAdvice.starsText(stars(of: attraction))
    }
}

extension AttractionKind {
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .coast: language.text("Coast", "海岸")
        case .mountain: language.text("Mountain", "山岳")
        case .hotSpring: language.text("Hot spring", "溫泉")
        case .town: language.text("Old town", "城鎮文化")
        }
    }
}

extension AttractionStatus {
    /// What the tourism panel says; `edge` when the map's edge sends
    /// tourists too (outside connections on), so joining to it helps
    /// (decision 601: the whole-Taiwan map has no such edge).
    public func title(in language: DisplayLanguage, edge: Bool = false) -> String {
        switch self {
        case .ok: language.text("Tourists are coming", "觀光客會來")
        case .noStation: language.text("No station within 800 m with a train", "800 公尺內沒有車站（或沒有列車停靠）")
        case .noSource:
            edge
                ? language.text("No route from where tourists come. Join its station to one where people live, or to the map's edge.",
                                "沒有客源路線。把它的車站接到有人住的車站，或地圖邊緣吧。")
                : language.text("No route from where tourists come. Join its station to one where people live.",
                                "沒有客源路線。把它的車站接到有人住的車站吧。")
        case .typhoon: language.text("A typhoon blows over it today", "今天颱風影響這裡")
        }
    }
}

/// A sight as the tourism panel lists it.
public struct AttractionRow: Identifiable, Hashable, Sendable {
    public let id: AttractionID
    public let name: String
    public let kind: String
    public let stars: Int
    public let starsText: String
    public let souvenir: Int
    /// The hotels near it that raise its rating (at most two count).
    public let hotels: Int
    /// "A sightseeing train calls (+0.5★)" when one calls near it
    /// (decision 286), else `nil`.
    public let sightseeingTrainText: String?
    public let status: AttractionStatus
    public let statusText: String
    /// The station that serves it, by name.
    public let stationName: String?
    /// The tourists it draws today, the day that ended, this year and last.
    public let today: Int64
    public let yesterday: Int64
    public let thisYear: Int64
    public let lastYear: Int64
    /// The next level of the souvenir shop: its price and what it does, or
    /// `nil` at the top level.
    public let nextShop: ShopOffer?
    /// Where the point lies, for the map.
    public let point: PlanPoint
    /// How far it lies off the tiles the company owns, in metres, on a
    /// map bought tile by tile (decision 160); `nil` on them, or on a map
    /// that is the company's everywhere (decision 663).
    public var offMapMetres: Int64? = nil

    /// "About 8 km off your map", for a sight off it; `nil` on it.
    public func offMapText(in language: DisplayLanguage) -> String? {
        guard let metres = offMapMetres else { return nil }
        let kilometres = max(1, (metres + 500) / 1_000)
        return language.text("About \(kilometres) km off your map", "在你的地圖外約 \(kilometres) 公里")
    }
}

/// The next level of a souvenir shop.
public struct ShopOffer: Hashable, Sendable {
    public let cost: Money
    public let canAfford: Bool
    /// "3.5★ → 3.75★, tourists a day 315 → 331 (today)…"
    public let preview: String
}

extension GameWorld {
    /// Whether this game has sights, so that the tourism panel is shown.
    public var hasTourism: Bool {
        tourism != nil
    }

    /// The sights for the tourism panel, the best rated first.
    public func attractionRows(in language: DisplayLanguage) -> [AttractionRow] {
        guard let tourism else { return [] }
        let day = clock.now.seconds / GameTime.secondsPerDay
        // One network for every sight, not one each (CRASH-SIGHTS).
        let statuses = attractionStatuses()
        let rows: [AttractionRow] = tourism.attractions.map { sight in
            let status = statuses[sight.id] ?? .noStation
            let today = status == .ok ? touristsExpected(for: sight, onDay: day) : 0
            var offer: ShopOffer?
            if sight.souvenir < Tourism.maximumSouvenirLevel {
                let next = sight.withSouvenir(level: sight.souvenir + 1)
                let after = status == .ok ? touristsExpected(for: next, onDay: day) : 0
                let cost = Money(Tourism.souvenirCost)
                let revenue = Tourism.shopRevenue(tourists: after, level: next.souvenir)
                offer = ShopOffer(
                    cost: cost, canAfford: economy.canAfford(cost),
                    preview: language.text(
                        "\(starsText(of: sight)) → \(starsText(of: next)); about \(today) → \(after) tourists today and \(revenue.moneyText) a day in the shop (upkeep \(Money(Tourism.souvenirCost * Int64(next.souvenir) * Tourism.upkeepPerDay / 100_000).moneyText)).",
                        "\(starsText(of: sight)) → \(starsText(of: next))；今天觀光客約 \(today) → \(after) 人，名產店每天約收 \(revenue.moneyText)（維護 \(Money(Tourism.souvenirCost * Int64(next.souvenir) * Tourism.upkeepPerDay / 100_000).moneyText)）。"
                    )
                )
            }
            return AttractionRow(
                id: sight.id, name: sight.name(in: language), kind: sight.kind.title(in: language), stars: stars(of: sight),
                starsText: starsText(of: sight), souvenir: sight.souvenir, hotels: hotelsNear(sight),
                sightseeingTrainText: Self.sightseeingTrainText(stars: sightseeingTrainStars(near: sight), in: language),
                status: status, statusText: status.title(in: language, edge: outsideConnections),
                stationName: attractionStation(of: sight.id).flatMap { station(id: $0)?.name }, today: today,
                yesterday: sight.yesterday, thisYear: sight.thisYear, lastYear: sight.lastYear, nextShop: offer, point: sight.point,
                offMapMetres: metresOffOwnedGround(sight.point)
            )
        }
        // Decision 663 (the Mac playtest's A12): the sights on the
        // company's map by stars, then those off it, nearest first.
        return rows.sorted { a, b in
            switch (a.offMapMetres, b.offMapMetres) {
            case (nil, nil): a.stars != b.stars ? a.stars > b.stars : a.id < b.id
            case (nil, _): true
            case (_, nil): false
            case let (x?, y?): x != y ? x < y : a.id < b.id
            }
        }
    }

    /// How far `point` lies from the nearest tile the company owns, in
    /// whole metres (decision 663); `nil` when it lies on one, or the map
    /// is not bought tile by tile.
    func metresOffOwnedGround(_ point: PlanPoint) -> Int64? {
        guard let owned = mapExpansion?.owned, !ownsGround(at: point) else { return nil }
        var nearest: Int64?
        for tile in owned {
            let area = mapArea(of: tile)
            let dx = max(area.minX - point.x, 0, point.x - area.maxX)
            let dy = max(area.minY - point.y, 0, point.y - area.maxY)
            let squared = dx * dx + dy * dy
            if nearest.map({ squared < $0 }) ?? true { nearest = squared }
        }
        return nearest.map { Int64(Double($0).squareRoot()) / WorldCoordinate.unitsPerMetre }
    }

    /// What the panel says of a sight a sightseeing train calls near, the
    /// trains there adding `stars`; `nil` when none does.
    static func sightseeingTrainText(stars: Int, in language: DisplayLanguage) -> String? {
        guard stars > 0 else { return nil }
        let stars = StationMasterAdvice.starsText(stars)
        return language.text("A sightseeing train calls here (+\(stars))", "有觀光列車停靠（+\(stars)）")
    }

    /// `stars` hundredths as a count of stars: "0.5 stars", "1 star".
    static func starsCount(_ stars: Int, in language: DisplayLanguage) -> String {
        let number = StationMasterAdvice.starsText(stars).dropLast()
        return language.text("\(number) \(stars == 100 ? "star" : "stars")", "\(number) 星")
    }

    /// What the train catalog says under a sightseeing type (decision 286),
    /// in a world with sights; `nil` for any other type or world.
    public func sightseeingNote(for type: TrainType?, in language: DisplayLanguage) -> String? {
        guard hasTourism, let type, type.isSightseeing else { return nil }
        let stars = Self.starsCount(type.sightseeingStars, in: language)
        return language.text(
            "Sightseeing train: calling at a station within 800 m of a sight adds \(stars) to it, so more tourists come.",
            "觀光列車：停靠景點 800 公尺內的車站時，景點加 \(stars)，觀光客會變多。"
        )
    }

    /// The sightseeing train types (decision 286) that add `stars`, by
    /// name: "Hai-Feng sightseeing train, Blue Train sightseeing train".
    static func sightseeingTrainNames(adding stars: Int, in language: DisplayLanguage) -> String {
        TrainType.offered.filter { $0.sightseeingStars == stars }.map { $0.title(in: language) }.joined(separator: language.text(", ", "、"))
    }

    /// The year's tourists at every sight, for the panel's heading.
    public var touristsThisYear: Int64 {
        tourism?.attractions.reduce(0) { $0 + $1.thisYear } ?? 0
    }

    /// The tourism panel's help text.
    public func tourismHelp(in language: DisplayLanguage) -> String {
        // Decision 663 (the Mac playtest's A12): what the sights do for the
        // player, not how their stars are counted (CLAUDE.md, the words
        // players read); the rows say what each shop, hotel and train adds.
        language.text(
            "Tourists ride to a sight from a station within 800 m. A souvenir shop, a hotel or a sightseeing train calling nearby raises its stars, and more of them come.",
            "觀光客搭車到景點 800 公尺內的車站。附近開名產店、蓋飯店或有觀光列車停靠，景點的星等提高，來的人更多。"
        )
    }
}

extension GameSession {
    /// Builds the next level of sight `id`'s souvenir shop.
    public func investInSouvenirShop(of id: AttractionID) {
        guard let sight = world.attraction(id: id) else { return }
        perform(.investInSouvenirShop(id)) { _, _, _ in
            language.text(
                "\(sight.englishName) has a souvenir shop of level \(sight.souvenir + 1) for \(Money(Tourism.souvenirCost).moneyText).",
                "\(sight.name)的名產店升到 \(sight.souvenir + 1) 級，花費 \(Money(Tourism.souvenirCost).moneyText)。"
            )
        }
    }
}
