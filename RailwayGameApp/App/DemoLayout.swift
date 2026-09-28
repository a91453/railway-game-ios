#if DEBUG
import GameCore
import GamePresentation

/// A small prebuilt layout for Simulator screenshots, opened only by Debug
/// builds launched with ``launchArgument`` (see visual-smoke.yml).
///
/// Not a shortcut: it starts from a normal new game and builds everything
/// with ordinary `GameWorld` commands that charge their usual costs.
enum DemoLayout {
    static let launchArgument = "-demo-layout"

    @MainActor
    static func makeSession() -> GameSession {
        var world = GameWorld.newGame()
        do {
            try build(in: &world)
        } catch {
            preconditionFailure("The demo layout no longer builds: \(error)")
        }
        let session = GameSession(world: world)
        session.select(GridPosition(x: 5, y: 7))
        session.selectTool(.buildTrack)
        session.selectTrackPiece(.curve)
        return session
    }

    private static func build(in world: inout GameWorld) throws(GameError) {
        // A line from Central east to a curve, then south through a junction
        // with a branch to Harbor, ending at a buffer stop.
        try world.buildStation(named: "Central", at: GridPosition(x: 1, y: 3))
        for x in 2...8 where x != 5 {
            try world.buildTrack(at: GridPosition(x: x, y: 3), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 9, y: 3), connections: [.west, .south])
        for y in 4...5 {
            try world.buildTrack(at: GridPosition(x: 9, y: y), connections: [.north, .south])
        }
        try world.buildTrack(at: GridPosition(x: 9, y: 6), connections: [.north, .east, .south])
        try world.buildTrack(at: GridPosition(x: 10, y: 6), connections: [.east, .west])
        try world.buildStation(named: "Harbor", at: GridPosition(x: 11, y: 6))
        try world.buildTrack(at: GridPosition(x: 9, y: 7), connections: [.north, .south])
        try world.buildTrack(at: GridPosition(x: 9, y: 8), connections: .north)

        // A four-way junction where a north–south line meets the main line.
        try world.buildTrack(at: GridPosition(x: 5, y: 3), connections: [.north, .east, .south, .west])
        try world.buildTrack(at: GridPosition(x: 5, y: 2), connections: [.south, .north])
        try world.buildStation(named: "Hill", at: GridPosition(x: 5, y: 1))
        try world.buildTrack(at: GridPosition(x: 5, y: 4), connections: [.north, .south])
        try world.buildTrack(at: GridPosition(x: 5, y: 5), connections: [.north, .west])
    }
}
#endif
