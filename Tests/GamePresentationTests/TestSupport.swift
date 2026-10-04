import GameCore

/// Costs used across tests so expected balances are easy to read.
let testCosts = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

/// A world `width` × `height` world units (128 × 96 m by default).
func makeWorld(
    width: Int64 = 8_192,
    height: Int64 = 6_144,
    balance: Money = 10_000,
    speed: GameSpeed = .paused
) throws -> GameWorld {
    GameWorld(
        bounds: try WorldBounds(width: width, height: height),
        economy: GameEconomy(balance: balance, costs: testCosts),
        clock: GameClock(speed: speed)
    )
}
