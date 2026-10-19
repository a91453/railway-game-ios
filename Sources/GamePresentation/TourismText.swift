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
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .ok: language.text("Tourists are coming", "觀光客會來")
        case .noStation: language.text("No station within 800 m with a train", "800 公尺內沒有車站（或沒有列車停靠）")
        case .noSource: language.text("No route from where tourists come", "沒有客源路線")
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
        let rows: [AttractionRow] = tourism.attractions.map { sight in
            let status = attractionStatus(of: sight.id)
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
                sightseeingTrainText: hasSightseeingTrain(near: sight) ? Self.sightseeingTrainText(in: language) : nil,
                status: status, statusText: status.title(in: language),
                stationName: attractionStation(of: sight.id).flatMap { station(id: $0)?.name }, today: today,
                yesterday: sight.yesterday, thisYear: sight.thisYear, lastYear: sight.lastYear, nextShop: offer, point: sight.point
            )
        }
        return rows.sorted { $0.stars != $1.stars ? $0.stars > $1.stars : $0.id < $1.id }
    }

    /// What the panel says of a sight a sightseeing train calls near.
    static func sightseeingTrainText(in language: DisplayLanguage) -> String {
        let stars = StationMasterAdvice.starsText(Tourism.starsPerSightseeingTrain)
        return language.text("A sightseeing train calls here (+\(stars))", "有觀光列車停靠（+\(stars)）")
    }

    /// What the train catalog says under a sightseeing type (decision 286),
    /// in a world with sights; `nil` for any other type or world.
    public func sightseeingNote(for type: TrainType?, in language: DisplayLanguage) -> String? {
        guard hasTourism, type?.isSightseeing == true else { return nil }
        let stars = StationMasterAdvice.starsText(Tourism.starsPerSightseeingTrain).dropLast()
        return language.text(
            "Sightseeing train: calling at a station within 800 m of a sight adds \(stars) stars to it, so more tourists come.",
            "觀光列車：停靠景點 800 公尺內的車站時，景點加 \(stars) 星，觀光客會變多。"
        )
    }

    /// The sightseeing train types (decision 286), by name: "Hai-Feng
    /// sightseeing train, Blue Train sightseeing train".
    static func sightseeingTrainNames(in language: DisplayLanguage) -> String {
        TrainType.offered.filter(\.isSightseeing).map { $0.title(in: language) }.joined(separator: language.text(", ", "、"))
    }

    /// The year's tourists at every sight, for the panel's heading.
    public var touristsThisYear: Int64 {
        tourism?.attractions.reduce(0) { $0 + $1.thisYear } ?? 0
    }

    /// The tourism panel's help text.
    public func tourismHelp(in language: DisplayLanguage) -> String {
        language.text(
            "Tourists come to a sight from the outside connections and the busiest towns, more at weekends and holidays, by season and in fine weather, and ride to the station within 800 m. A souvenir shop adds a quarter star a level and earns \(Tourism.spendPerLevel / 100) dollars a tourist a level. A hotel within 800 m adds a quarter star too (two count) and takes in \(Tourism.hotelStayPermille / 10)% of the tourists as guests. A sightseeing train (\(Self.sightseeingTrainNames(in: language))) calling at a station within 800 m adds \(StationMasterAdvice.starsText(Tourism.starsPerSightseeingTrain).dropLast()) stars.",
            "觀光客從外部連接站和最大的城鎮出發，週末與連假更多，看季節與天氣，搭車到 800 公尺內的車站。名產店每級加 0.25 星，每位觀光客每級在店裡花 \(Tourism.spendPerLevel / 100) 元。800 公尺內的飯店也各加 0.25 星（算兩家），並接待 \(Tourism.hotelStayPermille / 10)% 的觀光客住宿。觀光列車（\(Self.sightseeingTrainNames(in: language))）停靠 800 公尺內的車站時，景點加 \(StationMasterAdvice.starsText(Tourism.starsPerSightseeingTrain).dropLast()) 星。"
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
