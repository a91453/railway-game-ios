import GameCore

/// What the economy panel's day-pass card shows (decision 324): whether a
/// pass can be sold, its price, and today's expected sales. Read from the
/// world when the card is drawn; the card's buttons call
/// ``GameSession/setDayPass(_:)``.
public struct DayPassCard: Hashable, Sendable {
    /// The price on sale, or `nil` while none is.
    public let price: Money?
    /// The price the card offers first: the one on sale, else three of the
    /// network's shortest fares.
    public let suggestedPrice: Money
    /// Whether anyone would buy one: the company keeps accounts and has
    /// sights.
    public let isAvailable: Bool
    /// Today's passes as the network reaches the sights now.
    public let today: DayPassDay

    /// The price stepper's step and range: $1 to $500.
    public static let priceStep: Int64 = 100
    public static let priceRange: ClosedRange<Int64> = 100...50_000

    public init(world: GameWorld) {
        price = world.accounts.dayPass
        suggestedPrice = world.accounts.dayPass ?? DayPass.suggestedPrice(for: world.accounts.effectiveFareRules)
        isAvailable = world.accounts.mode == .management && world.tourism != nil
        today = world.dayPassToday()
    }

    public func title(in language: DisplayLanguage) -> String {
        language.text("Day pass", "一日週遊券")
    }

    /// What a pass does for the player, in a sentence.
    public func explanation(in language: DisplayLanguage) -> String {
        language.text(
            "Visitors to your sights can buy one ticket for a day of rides. Holders also ride on to the next sight and drop in at your park, store and hotel near the stations they visit.",
            "來看景點的遊客可以買一張票坐一整天。持票的人會多坐到下一個景點，也會順路去車站附近你的遊樂園、百貨和飯店。"
        )
    }

    /// Why nothing sells, or `nil` when it can.
    public func unavailableText(in language: DisplayLanguage) -> String? {
        guard !isAvailable else { return nil }
        return language.text("Day passes sell once the company keeps accounts and the map has sights.", "公司經營、地圖上有景點時才賣得出週遊券。")
    }

    /// The price on sale, such as "On sale · $ 15.00", or that none is.
    public func statusText(in language: DisplayLanguage) -> String {
        guard let price else { return language.text("Not on sale", "未販售") }
        return language.text("On sale · \(price.centsText)", "販售中 · \(price.centsText)")
    }

    /// Today's expected sales and what they bring against selling none,
    /// such as "Today about 48 sold: -$ 96 against what their trips would
    /// have paid, and 0 extra rides."
    public func todayText(in language: DisplayLanguage) -> String? {
        guard price != nil, isAvailable else { return nil }
        guard today.sold > 0 else {
            return language.text("Nobody buys at this price today.", "今天這個價格沒有人買。")
        }
        let net = LedgerEntry.signedMoneyText(today.net)
        return language.text(
            "Today about \(today.sold) sold: \(net) against what their trips would have paid, and \(today.rides) extra rides.",
            "今天約賣 \(today.sold) 張：比他們原本的車資 \(net)，多坐 \(today.rides) 趟。"
        )
    }

    /// The sell button's label at `price`.
    public static func sellText(_ price: Money, in language: DisplayLanguage) -> String {
        language.text("Sell day passes at \(price.centsText)", "以 \(price.centsText) 販售週遊券")
    }

    public static func stopText(in language: DisplayLanguage) -> String {
        language.text("Stop selling day passes", "停售週遊券")
    }
}
