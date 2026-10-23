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

    /// A train of `type` with `cars` cars: what it carries, costs, costs a
    /// day and costs an hour on a line (decision 301), in `world`.
    public static func train(_ type: TrainType, cars: Int, in world: GameWorld) -> (riders: Int64, price: Money, daily: Money, hourly: Money) {
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        let daily = world.dailyRunningCost(of: type, cars: cars)
        return (type.ratedCapacityPerCar * Int64(cars), world.purchaseCost(of: type, cars: cars), daily, hourlyCost(daily: daily))
    }

    /// What a train whose fixed running cost on a line is `daily` a day
    /// costs an hour (decision 301, the City Transport Manager study's
    /// 4.11): the day's cost over its 24 hours, to the nearest dollar, half
    /// up. Its departures and kilometres are paid on top as it runs.
    public static func hourlyCost(daily: Money) -> Money {
        Money((max(0, daily.amount) + 1_200) / 2_400 * 100)
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
