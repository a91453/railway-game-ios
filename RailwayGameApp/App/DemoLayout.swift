#if DEBUG
import GameCore
import GamePresentation

/// A small prebuilt layout for Simulator screenshots, opened only by Debug
/// builds launched with ``launchArgument`` (see visual-smoke.yml).
///
/// Not a shortcut: it starts from a normal new game and builds everything
/// with ordinary `GameWorld` commands that charge their usual costs. Its
/// train is bought, placed, given a rate and sent the way a player would, so
/// the screenshots show the train tool and a train the game loop is moving.
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
        sendTrain(in: session)
        return session
    }

    /// Buys a train, places it at the west end of the main line facing east,
    /// and sends it to the buffer stop south of the junction, through the
    /// same session methods as the train tool.
    @MainActor
    private static func sendTrain(in session: GameSession) {
        session.selectTool(.train)
        session.purchaseTrain()
        session.setPlacementHeading(.east)
        session.select(GridPosition(x: 2, y: 3))
        session.applyTool()
        session.setSelectedTrainRate(128)
        session.select(GridPosition(x: 9, y: 8))
        session.applyTool()
        guard session.selectedTrain?.movement.remainingContinuation.isEmpty == false else {
            preconditionFailure("The demo train was not sent: \(session.message?.text ?? "no message")")
        }
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
