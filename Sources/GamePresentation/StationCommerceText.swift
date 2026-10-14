import GameCore

// The station panel's shops (ARCHITECTURE decision 222): what the station's
// shops took yesterday, the next level's price and about how much more it
// would make a day, and how many years it takes to pay back, in English or
// Traditional Chinese. The player's text says what the shops do for them,
// not how they are worked out (#600).

extension StationCommerceLevel {
    /// Its name.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .convenienceStore: language.text("Convenience store", "便利商店")
        case .arcade: language.text("Station arcade", "站內商店街")
        case .mall: language.text("Station mall", "車站商場")
        }
    }

    /// Its card's picture in the asset catalog.
    public var cardArt: String {
        switch self {
        case .convenienceStore: "StationCommerceConvenienceStore"
        case .arcade: "StationCommerceArcade"
        case .mall: "StationCommerceMall"
        }
    }
}

/// What the station panel shows of a station's shops (decision 222).
public struct StationCommerceCard: Hashable, Sendable {
    /// The next level to build, with its price and what it would bring.
    public struct Offer: Hashable, Sendable {
        public let level: StationCommerceLevel
        public let price: Money
        /// About how much more a day than now, at yesterday's people.
        public let extraPerDay: Money
        /// About how many years it takes to pay back, in tenths; `nil` when
        /// it would not.
        public let paybackTenths: Int64?
        public let affordable: Bool
    }

    public let station: StationID
    public let level: StationCommerceLevel?
    /// Yesterday's people through the station.
    public let people: Int64
    /// What the shops made yesterday, after their upkeep.
    public let yesterday: Money
    public let offer: Offer?
    /// Whether the station can have shops at all (a depot cannot).
    public let allowed: Bool

    public init?(station id: StationID, in world: GameWorld) {
        guard let station = world.station(id: id) else { return nil }
        self.station = id
        level = station.commerce
        allowed = !station.isDepot
        let day = world.clock.now.seconds / GameTime.secondsPerDay - 1
        let now = world.stationCommerceDay(of: id, onDay: day)
        people = world.stationCommercePeople(of: id, onDay: day)
        yesterday = now.net
        if allowed, let next = station.commerce.map(\.next) ?? .convenienceStore {
            let then = world.stationCommerceDay(of: id, level: next, onDay: day)
            let extra = then.net - now.net
            offer = Offer(
                level: next, price: next.price, extraPerDay: extra,
                paybackTenths: Self.paybackTenths(price: next.price, perDay: extra),
                affordable: world.economy.canAfford(next.price)
            )
        } else {
            offer = nil
        }
    }

    /// Years to make `price` back at `perDay`, in tenths, rounded up; a
    /// game year is 360 days. `nil` when it would not pay back.
    static func paybackTenths(price: Money, perDay: Money) -> Int64? {
        guard perDay > .zero else { return nil }
        let days = (price.amount + perDay.amount - 1) / perDay.amount
        return (days * 10 + 359) / 360
    }

    /// The line under the current level: what it made yesterday.
    public func yesterdayText(in language: DisplayLanguage) -> String {
        let amount = (yesterday < .zero ? "−" : "+") + Money(abs(yesterday.amount)).moneyText
        return language.text("Yesterday \(amount)", "昨天 \(amount)")
    }

    /// The offer's line: about how much more a day, and when it pays back.
    public func offerText(in language: DisplayLanguage) -> String? {
        guard let offer else { return nil }
        guard let tenths = offer.paybackTenths else {
            return language.text(
                "Not enough people pass through yet to pay it back.",
                "這一站經過的人還不夠多，暫時回不了本。"
            )
        }
        let years = "\(tenths / 10).\(tenths % 10)"
        return language.text(
            "About \(offer.extraPerDay.moneyText) more a day · pays back in about \(years) years",
            "每天約多賺 \(offer.extraPerDay.moneyText)・約 \(years) 年回本"
        )
    }

    /// The offer's button.
    public func offerTitle(in language: DisplayLanguage) -> String? {
        guard let offer else { return nil }
        return level == nil
            ? language.text("Build a \(offer.level.title(in: .english).lowercased())", "蓋\(offer.level.title(in: .traditionalChinese))")
            : language.text("Upgrade to a \(offer.level.title(in: .english).lowercased())", "升級成\(offer.level.title(in: .traditionalChinese))")
    }

    /// What the section says before anything is built.
    public static func explanation(in language: DisplayLanguage) -> String {
        language.text(
            "Shops in the station earn from the people who pass through it: the busier the station, the more they make.",
            "在車站裡開店，經過的人越多賺越多。"
        )
    }
}

extension GameSession {
    /// The station panel's shops of station `id` (decision 222).
    public func stationCommerceCard(of id: StationID) -> StationCommerceCard? {
        StationCommerceCard(station: id, in: world)
    }

    /// Builds a convenience store in station `id`, or its shops up a level.
    public func buildNextStationCommerce(at id: StationID) {
        guard let station = world.station(id: id) else { return }
        let next = station.commerce.map(\.next) ?? .convenienceStore
        guard let next else { return }
        let command: PlayerCommand.Edit = station.commerce == nil ? .buildStationCommerce(id) : .upgradeStationCommerce(id)
        perform(.edit(command)) { _, _, _ in
            language.text(
                "\(station.name) has a \(next.title(in: .english).lowercased()) for \(next.price.moneyText).",
                "\(station.name)開了\(next.title(in: .traditionalChinese))，花費 \(next.price.moneyText)。"
            )
        }
    }

    /// Demolishes station `id`'s shops: nothing comes back.
    public func demolishStationCommerce(at id: StationID) {
        guard let station = world.station(id: id) else { return }
        perform(.edit(.demolishStationCommerce(id))) { _, _, _ in
            language.text("\(station.name)'s shops are gone.", "\(station.name)的商店已經拆除。")
        }
    }
}
