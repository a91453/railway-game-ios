import GameCore

/// Costs used across tests so expected balances are easy to read.
let testCosts = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

func makeWorld(
    width: Int = 8,
    height: Int = 6,
    balance: Money = 10_000,
    speed: GameSpeed = .paused
) throws -> GameWorld {
    try GameWorld(
        width: width,
        height: height,
        economy: GameEconomy(balance: balance, costs: testCosts),
        clock: GameClock(speed: speed)
    )
}
