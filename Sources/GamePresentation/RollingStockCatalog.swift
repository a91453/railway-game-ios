import GameCore

// Decision 224, option 2A: the train types as a showroom, one at a time on
// a platform, grouped by family; the cars stepped on the train itself, the
// price of the whole train beside it. The figures are the type menu's
// (decision 180, ``TrainTypeCard``) and the world's prices. Decision 374:
// in a lesson, the types a later lesson opens are listed too, with that
// lesson, and cannot be chosen yet.

/// The types a company can buy, as the showroom shows them.
public struct RollingStockCatalog: Equatable, Sendable {
    /// A family of types: the showroom's tabs, and the colour of the
    /// stripe along the cars.
    /// Each type's is its row of the catalog (decision 225).
    public typealias Family = TrainFamily

    /// One type.
    public struct Entry: Equatable, Sendable, Identifiable {
        public let type: TrainType
        public let family: Family
        public let card: TrainTypeCard
        public let doorsPerCar: Int64
        /// The lesson that opens it, while it is shut (decision 374), or
        /// `nil` when it can be chosen.
        public let opensInLesson: Int?
        public var id: TrainType { type }

        /// Whether it can be chosen now.
        public var isOpen: Bool { opensInLesson == nil }
    }

    public let entries: [Entry]

    /// The types offered in `world`, family by family in the menu's order.
    public init(world: GameWorld) {
        let offered = world.offeredTrainTypes
        entries = Family.allCases.flatMap { family in
            offered.filter { Family($0) == family }.map {
                Entry(
                    type: $0, family: family, card: world.trainTypeCard($0), doorsPerCar: $0.doorsPerCar,
                    opensInLesson: world.lessonUnlocking($0)
                )
            }
        }
    }

    /// The first type that can be chosen, the showroom's first one shown.
    public var firstOpen: TrainType? {
        (entries.first(where: \.isOpen) ?? entries.first)?.type
    }

    /// The families that have a type to show.
    public var families: [Family] {
        Family.allCases.filter { family in entries.contains { $0.family == family } }
    }

    public func entries(of family: Family) -> [Entry] {
        entries.filter { $0.family == family }
    }

    /// The type after `type` in its family, round to the first; and before.
    public func next(after type: TrainType) -> TrainType? {
        step(from: type, by: 1)
    }

    public func previous(before type: TrainType) -> TrainType? {
        step(from: type, by: -1)
    }

    private func step(from type: TrainType, by offset: Int) -> TrainType? {
        let family = entries(of: Family(type))
        guard let index = family.firstIndex(where: { $0.type == type }), family.count > 1 else { return nil }
        return family[(index + offset + family.count) % family.count].type
    }

    /// Decision 915: how the full-screen catalog's list is ordered.
    public enum Order: String, CaseIterable, Sendable {
        /// Family by family, in the menu's order.
        case family
        /// The whole train's price, cheapest first.
        case price
        /// What a car carries, most first.
        case capacity
        /// Top speed, fastest first.
        case speed
        /// What the train costs an hour on a line, cheapest first.
        case hourlyCost

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .family: language.text("Family", "類別")
            case .price: language.text("Price", "價格")
            case .capacity: language.text("Riders a car", "每節人數")
            case .speed: language.text("Top speed", "最高速度")
            case .hourlyCost: language.text("Cost an hour", "每小時成本")
            }
        }
    }

    /// Decision 915: the types the catalog's list shows: those of `family`
    /// (every family when `nil`), in `order` for trains of `cars` cars in
    /// `world`, ties kept in the menu's order; with `affordableOnly`, only
    /// those whose whole train the company can pay for now.
    public func listed(family: Family?, order: Order, cars: Int, affordableOnly: Bool, in world: GameWorld) -> [Entry] {
        let shown = entries.enumerated().filter { family == nil || $0.element.family == family }
        let trains = Dictionary(uniqueKeysWithValues: shown.map { ($0.element.type, Self.train($0.element.type, cars: cars, in: world)) })
        let kept = shown.filter { !affordableOnly || world.economy.canAfford(trains[$0.element.type]!.price) }
        func key(_ entry: Entry) -> Int64 {
            let train = trains[entry.type]!
            switch order {
            case .family: return 0
            case .price: return train.price.amount
            case .capacity: return -entry.card.capacityPerCar
            case .speed: return -entry.card.topSpeed
            case .hourlyCost: return train.hourly.amount
            }
        }
        return kept.sorted { lhs, rhs in
            let (l, r) = (key(lhs.element), key(rhs.element))
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The type after `type` in `list`, round to the first; and before:
    /// the detail's arrows over what the list shows (decision 915).
    public static func step(in list: [Entry], from type: TrainType, by offset: Int) -> TrainType? {
        guard let index = list.firstIndex(where: { $0.type == type }), list.count > 1 else { return nil }
        return list[(index + offset + list.count) % list.count].type
    }

    /// A train of `type` with `cars` cars: what it carries, costs, costs a
    /// day and costs an hour on a line (decision 301), in `world`.
    public static func train(_ type: TrainType, cars: Int, in world: GameWorld) -> (riders: Int64, price: Money, daily: Money, hourly: Money) {
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        let daily = world.dailyRunningCost(of: type, cars: cars)
        return (type.ratedCapacityPerCar * Int64(cars), world.purchaseCost(of: type, cars: cars), daily, hourlyCost(daily: daily))
    }

    /// What a train whose fixed running cost on a line is `daily` a day
    /// costs an hour (decision 301): the day's cost over its 24 hours, to the nearest dollar, half
    /// up. Its departures and kilometres are paid on top as it runs.
    public static func hourlyCost(daily: Money) -> Money {
        Money((max(0, daily.amount) + 1_200) / 2_400 * 100)
    }

    /// How many windows the showroom draws along a car `width` long and
    /// `height` tall: as many as fit at 0.7 of its height each, one at
    /// least. A car with no size yet (a layout pass that gives it none, as
    /// when a sheet first comes up) has one, rather than a division by
    /// zero to turn into a count (BH8 P2-1).
    public static func sideWindows(width: Double, height: Double) -> Int {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 1 }
        let fits = width / (height * 0.7)
        guard fits.isFinite else { return 1 }
        return max(1, Int(min(fits, 100)))
    }
}

extension TrainFamily {
    /// The family of `type`: its row of the catalog says which.
    public init(_ type: TrainType) {
        self = type.family
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .metro: language.text("Metro", "捷運")
        case .railway: language.text("Railway", "鐵路")
        case .highSpeed: language.text("High speed", "高鐵")
        case .special: language.text("Special", "特殊")
        }
    }
}
