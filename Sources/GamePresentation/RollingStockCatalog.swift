import GameCore

// Decision 224, option 2A: the train types as a showroom, one at a time on
// a platform, grouped by family; the cars stepped on the train itself, the
// price of the whole train beside it. The figures are the type menu's
// (decision 180, ``TrainTypeCard``) and the world's prices.

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
        public var id: TrainType { type }
    }

    public let entries: [Entry]

    /// The types offered in `world`, family by family in the menu's order.
    public init(world: GameWorld) {
        let offered = world.offeredTrainTypes
        entries = Family.allCases.flatMap { family in
            offered.filter { Family($0) == family }.map {
                Entry(type: $0, family: family, card: world.trainTypeCard($0), doorsPerCar: $0.doorsPerCar)
            }
        }
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

    /// A train of `type` with `cars` cars: what it carries, costs and costs
    /// a day, in `world`.
    public static func train(_ type: TrainType, cars: Int, in world: GameWorld) -> (riders: Int64, price: Money, daily: Money) {
        let cars = min(max(cars, Train.minimumCars), Train.maximumCars)
        return (type.ratedCapacityPerCar * Int64(cars), world.purchaseCost(of: type, cars: cars), world.dailyRunningCost(of: type, cars: cars))
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
