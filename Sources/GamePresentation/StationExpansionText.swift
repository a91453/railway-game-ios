import GameCore

// The station panel's expansion (decision 506): how many can wait at the
// station, and the next expansion's price, the people a day it needs and
// whether the station was full lately,
// in English or Traditional Chinese. The player's text says what an
// expansion does for them, not how it is worked out (#600).

extension StationExpansion {
    /// Its name.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .concourse: language.text("Bigger concourse", "擴大站廳")
        case .hall: language.text("Grand station hall", "大型車站")
        }
    }
}

/// What the station panel shows of a station's room to wait (decision 506).
public struct StationExpansionCard: Hashable, Sendable {
    /// The next expansion, its price and whether it is open yet.
    public struct Offer: Hashable, Sendable {
        public let expansion: StationExpansion
        public let price: Money
        /// The people a day it needs.
        public let threshold: Int64
        /// Whether yesterday's people reached the threshold.
        public let open: Bool
        /// Whether the station turned anyone away for want of room
        /// yesterday or today.
        public let full: Bool
        public let affordable: Bool
    }

    public let station: StationID
    public let expansion: StationExpansion?
    /// How many may wait there now.
    public let capacity: Int64
    /// How many wait there now.
    public let waiting: Int64
    /// Yesterday's people through the station.
    public let people: Int64
    public let offer: Offer?

    public init?(station id: StationID, in world: GameWorld) {
        guard let station = world.station(id: id), !station.isDepot else { return nil }
        self.station = id
        expansion = station.expansion
        capacity = station.capacity
        waiting = world.passengers.first { $0.station == id }?.waitingCount ?? 0
        let people = world.stationExpansionPeople(of: id)
        self.people = people
        if let next = world.nextStationExpansion(of: id) {
            offer = Offer(expansion: next, price: next.price, threshold: next.threshold,
                          open: people >= next.threshold, full: world.stationWasFullLately(id),
                          affordable: world.economy.canAfford(next.price))
        } else {
            offer = nil
        }
    }

    /// The section's first line: how many can wait, and how many do.
    public func capacityText(in language: DisplayLanguage) -> String {
        language.text(
            "Room for \(capacity.groupedText) waiting · \(waiting.groupedText) waiting now",
            "可容納 \(capacity.groupedText) 人候車・目前 \(waiting.groupedText) 人"
        )
    }

    /// The offer's line: what it gives, or how busy the station must get.
    public func offerText(in language: DisplayLanguage) -> String? {
        guard let offer else {
            return language.text("The station is at its largest.", "車站已經擴建到最大。")
        }
        guard offer.open else {
            return language.text(
                "Opens once \(offer.threshold.groupedText) people a day pass through (yesterday \(people.groupedText)).",
                "每日進出達 \(offer.threshold.groupedText) 人次才能擴建（昨天 \(people.groupedText)）。"
            )
        }
        guard offer.full else {
            return language.text(
                "Opens once the station fills and turns people away. It was not full yesterday.",
                "車站客滿、有旅客進不來時才能擴建。昨天沒有客滿。"
            )
        }
        return language.text(
            "Room for \(offer.expansion.capacity.groupedText) waiting, so fewer are turned away when it fills.",
            "可容納 \(offer.expansion.capacity.groupedText) 人候車，客滿時少流失一些旅客。"
        )
    }

    /// The offer's button.
    public func offerTitle(in language: DisplayLanguage) -> String? {
        guard let offer else { return nil }
        return language.text(
            "Expand: \(offer.expansion.title(in: .english).lowercased())",
            "擴建：\(offer.expansion.title(in: .traditionalChinese))"
        )
    }

    /// The offer's price, on a line of its own under the button's title so
    /// a narrow panel never breaks the amount.
    public var offerPriceText: String? {
        offer?.price.moneyText
    }

    /// Whether the button can be pressed.
    public var canExpand: Bool {
        offer.map { $0.open && $0.full && $0.affordable } ?? false
    }

    /// What the section says of itself.
    public static func explanation(in language: DisplayLanguage) -> String {
        language.text(
            "When the station is full, those who come are turned away. A busy station that fills up can be expanded to hold more.",
            "車站客滿時，再來的旅客會離開。人多又會客滿的車站可以擴建，容納更多人候車。"
        )
    }
}

extension GameSession {
    /// The station panel's expansion of station `id` (decision 506).
    public func stationExpansionCard(of id: StationID) -> StationExpansionCard? {
        StationExpansionCard(station: id, in: world)
    }

    /// Expands station `id` a step.
    public func expandStation(at id: StationID) {
        guard let station = world.station(id: id), let next = world.nextStationExpansion(of: id) else { return }
        perform(.edit(.expandStation(id))) { _, _, _ in
            language.text(
                "\(station.name) now holds \(next.capacity.groupedText) waiting, for \(next.price.moneyText).",
                "\(station.name)擴建完成，可容納 \(next.capacity.groupedText) 人候車，花費 \(next.price.moneyText)。"
            )
        }
    }
}
