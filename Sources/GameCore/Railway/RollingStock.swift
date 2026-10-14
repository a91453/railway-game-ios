// What a train costs by its type (decision 180).
//
// The references have no price list for rolling stock: the Ci reference
// buys every car from one quota (`metro.cars`) and the A-Train series, the
// game this one aims at, prices each type and car on its own and buys one
// back at 70 % of its book value. The prices and the running-cost weights
// are this project's (gap); the 70 % sale and the 30 % refit are the series'
// shape.
//
// With ``GameWorld/rollingStockEconomics`` on, a train is bought at its
// type's price, a car added costs the type's car price, a change of type
// pays a refit, a train sold brings back 70 % of its book value, and the
// running costs of a train weigh its cars and its type. Off, as in every
// world before it, one price and one weight for every train.

/// What one type of train costs to buy and to run (decision 180). Money is
/// in cents, as everywhere in GameCore.
public struct RollingStockPricing: Hashable, Sendable {
    /// A new train of the type, with its first car.
    public let firstCar: Money
    /// Each car added to it.
    public let eachCar: Money
    /// How much a car of the type costs to run next to the standard
    /// car's 1,000, in thousandths: it multiplies the train's share of
    /// the staff, energy and maintenance, and its kilometres' cost.
    public let operatingPermille: Int64

    init(firstDollars: Int64, carDollars: Int64, operatingPermille: Int64) {
        firstCar = Money(firstDollars * 100)
        eachCar = Money(carDollars * 100)
        self.operatingPermille = operatingPermille
    }
}

extension TrainType {
    /// This type's prices and running-cost weight (decision 180), from its
    /// row of the catalog (decision 225).
    public var pricing: RollingStockPricing { spec.pricing }
}

/// The rules of decision 180 as plain functions of a type and a car count.
public enum RollingStock {
    /// The standard car, for a train without a type: A's prices and weight.
    public static let standard = RollingStockPricing(firstDollars: 150_000, carDollars: 40_000, operatingPermille: 1_000)

    /// A train sold brings back this share of what is left of its cost on
    /// the books.
    public static let salePercent: Int64 = 70

    public static func pricing(of type: TrainType?) -> RollingStockPricing {
        type?.pricing ?? standard
    }

    /// A new train of `type` with `cars` cars, at the type's prices.
    public static func price(of type: TrainType?, cars: Int) -> Money {
        let pricing = pricing(of: type)
        return Money(pricing.firstCar.amount + pricing.eachCar.amount * Int64(max(0, cars - 1)))
    }

    /// What changing a train to a type whose whole train costs `price`
    /// costs when the old train is worth `tradeIn` on the sale rule
    /// (``salePrice(bookValue:)``): the same as selling the old train and
    /// buying the new, at least nothing (decision 180, the owner's rule, so
    /// that buying a cheap type, adding cars and changing the type is never
    /// cheaper than buying the type outright).
    public static func refitFee(price: Money, tradeIn: Money) -> Money {
        Money(max(0, price.amount - tradeIn.amount))
    }

    /// What selling a train brings in: ``salePercent`` of `bookValue`,
    /// rounded down.
    public static func salePrice(bookValue: Money) -> Money {
        Money(max(0, bookValue.amount) * salePercent / 100)
    }

    /// How many standard trains' running costs a train of `cars` cars of
    /// `type` weighs, in thousandths: a standard single car is 1,000.
    public static func weight(of type: TrainType?, cars: Int) -> Int64 {
        pricing(of: type).operatingPermille * Int64(max(1, cars))
    }
}

extension RollingStock {
    /// A standard train's fixed cost a day, in dollars: staff 480, energy
    /// 360 and the maintenance 8 an hour that ``Operations`` settles (the
    /// part of its running cost that does not depend on the kilometres it
    /// runs).
    public static let standardDailyDollars: Int64 = 480 + 360 + 8 * 24
}

extension GameWorld {
    /// What the fixed daily cost of a train of `type` with `cars` cars is
    /// when it is on a line (decision 180): ``RollingStock/standardDailyDollars``
    /// by its weight, rounded to a dollar; one standard train's whatever the
    /// train, without ``rollingStockEconomics``.
    public func dailyRunningCost(of type: TrainType?, cars: Int) -> Money {
        let weight = rollingStockEconomics ? RollingStock.weight(of: type, cars: cars) : 1_000
        return Money((RollingStock.standardDailyDollars * weight + 500) / 1_000 * 100)
    }

    /// What buying a train of `type` with `cars` cars costs now (decision
    /// 180): the type's prices, or without ``rollingStockEconomics`` the one
    /// price and each car's.
    public func purchaseCost(of type: TrainType?, cars: Int) -> Money {
        guard !rollingStockEconomics else { return RollingStock.price(of: type, cars: cars) }
        return Money(economy.costs.train.amount + economy.costs.car.amount * Int64(max(0, cars - 1)))
    }

    /// Turns rolling-stock economics on or off (decision 180): trains priced
    /// and weighed by type and cars, and sold back. A new game turns it on;
    /// worlds from before it, the demos, the challenges and the tutorial keep
    /// it off. It changes no train, only what the next purchase, refit and
    /// settlement cost.
    public mutating func setRollingStockEconomics(_ enabled: Bool) {
        rollingStockEconomics = enabled
    }
}

extension GameWorld {
    /// Whether train `id` can be sold now (decision 180): it is off the
    /// track, on no line and running no service. `false` for a train that
    /// does not exist.
    public func canSellTrain(_ id: TrainID) -> Bool {
        guard let train = train(id: id) else { return false }
        return train.position == nil && train.execution == nil && assignedLine(of: id) == nil
    }

    /// What selling train `id` would bring in now (decision 180):
    /// ``RollingStock/salePercent`` of the books of the train and of its
    /// cars, each rounded down; nothing for a train that does not exist, and
    /// in free play, which keeps no books.
    public func trainSaleQuote(_ id: TrainID) -> Money {
        guard train(id: id) != nil, accounts.mode == .management else { return .zero }
        let owner = id.rawValue
        return RollingStock.salePrice(bookValue: bookValue(.train, owner: owner)) + RollingStock.salePrice(bookValue: bookValue(.cars, owner: owner))
    }

    func bookValue(_ kind: AssetRecord.Kind, owner: Int) -> Money {
        accounts.assets.reduce(Money.zero) { $1.kind == kind && $1.owner == owner ? $0 + $1.bookValue : $0 }
    }
}

extension GameWorld {
    /// What changing train `id` to `type` would cost now (decision 180):
    /// the new type's price for the cars it has, less what selling it
    /// would bring (``trainSaleQuote(_:)``), at least nothing; nothing
    /// without ``rollingStockEconomics``, for the type it already is, and
    /// for a train that does not exist.
    public func refitCost(of id: TrainID, to type: TrainType?) -> Money {
        guard rollingStockEconomics, let train = train(id: id), train.type != type else { return .zero }
        return RollingStock.refitFee(price: RollingStock.price(of: type, cars: train.cars), tradeIn: trainSaleQuote(id))
    }
}
