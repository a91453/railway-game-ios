import GameCore

// What a train type costs, as the player reads it (decision 180): a card for
// each type in the type menu and the staffing section, and the price of a
// car for the train that is selected.

/// One type's card: what a car carries, what a train of one car and each
/// car added cost, what a train of one car costs a day on a line, and how
/// fast it runs.
public struct TrainTypeCard: Equatable, Sendable {
    public let type: TrainType?
    public let capacityPerCar: Int64
    public let firstCarPrice: Money
    public let carPrice: Money
    /// A one-car train's fixed running cost a day on a line.
    public let dailyCost: Money
    /// The top speed it runs at, km/h: its own performance's, or the
    /// standard one's.
    public let topSpeed: Int64

    /// "Capacity 310 a car · $ 150,000 + $ 40,000 a car · $ 1,032 a day ·
    /// 110 km/h".
    public func text(in language: DisplayLanguage) -> String {
        language.text(
            "\(capacityPerCar) a car · \(firstCarPrice.moneyText) + \(carPrice.moneyText) a car · \(dailyCost.moneyText) a day · \(topSpeed) km/h",
            "每節 \(capacityPerCar) 人 · \(firstCarPrice.moneyText) ＋每節 \(carPrice.moneyText) · 每日 \(dailyCost.moneyText) · 最高 \(topSpeed) km/h"
        )
    }
}

extension GameWorld {
    /// The card of `type` (`nil`: the standard car) at this world's prices.
    public func trainTypeCard(_ type: TrainType?) -> TrainTypeCard {
        TrainTypeCard(
            type: type,
            capacityPerCar: type?.ratedCapacityPerCar ?? Train.ratedCapacityPerCar,
            firstCarPrice: purchaseCost(of: type, cars: 1),
            carPrice: rollingStockEconomics ? RollingStock.pricing(of: type).eachCar : economy.costs.car,
            dailyCost: dailyRunningCost(of: type, cars: 1),
            topSpeed: (type?.performance ?? .standard).topSpeed
        )
    }

    /// For a train of `type`: what each car added costs and what a change of
    /// type costs, when rolling-stock economics is on (decision 180);
    /// otherwise the plain price of a car, as ``carPriceText(in:)``.
    public func carPriceText(for type: TrainType?, in language: DisplayLanguage) -> String? {
        guard rollingStockEconomics else { return carPriceText(in: language) }
        let price = RollingStock.pricing(of: type).eachCar
        return language.text(
            "Each car added costs \(price.moneyText); a change of type costs \(RollingStock.refitPercent) % of the new type's price; taking cars off refunds nothing.",
            "每加一節車廂 \(price.moneyText)；改車種要付新車種價格的 \(RollingStock.refitPercent) %；減少車廂不退費。"
        )
    }
}
