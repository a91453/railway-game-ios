import GameCore
import GamePresentation

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

/// Decision 137: a new game with a station at each of `points`, joined by
/// straight edges from one to the next (the track running a platform
/// beyond the end stations; each other station's platform starts at its
/// point), a line calling at them and one train of four cars running all
/// day. A line through three points or more must run on without turning at
/// them: two straight edges meet at a kink no train passes.
func newGameLine(through points: [PlanPoint], in start: GameWorld = .newGame()) throws -> GameWorld {
    // Decision 261: the scripts' line, one builder for the tests and them.
    try LineBuilder.line(through: points, in: start)
}
