#if DEBUG
import GameCore
import GamePresentation

/// A small prebuilt layout for looking at the map by eye, opened only by
/// Debug builds launched with ``launchArgument``.
///
/// Not a shortcut: it starts from a normal new game and builds everything
/// with ordinary `GameWorld` commands that charge their usual costs. Its
/// train is bought, placed, given a rate and sent the way a player would, so
/// the layout shows the train tool and a train the game loop is moving.
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
        let session = GameSession(world: world, language: .app)
        sendTrain(in: session)
        return session
    }

    /// A loop of continuous track east of the grid lines (Phase 4.5 Stage
    /// S3): four nodes around a circle of three tiles' radius, joined by
    /// cubic quarter curves that leave and arrive along the circle, so each
    /// joins the next. Harbor, which has a platform on the grid, gets a
    /// second one on the loop's north-west curve, and North Gate one on its
    /// north-east curve; line Circle (Stage S5) sends a three-car train back
    /// and forth between them, turning round at each end.
    private static func buildLoop(in world: inout GameWorld) throws(GameError) {
        let radius: Int64 = 3 * 1_024
        // Bézier handles of 0.5523 × the radius make a close quarter circle.
        let handle: Int64 = radius * 5_523 / 10_000
        let (cx, cy): (Int64, Int64) = (17 * 1_024, 7 * 1_024)
        let top = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy - radius))
        let right = try world.buildTrackNode(at: WorldCoordinate(x: cx + radius, y: cy))
        let bottom = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy + radius))
        let left = try world.buildTrackNode(at: WorldCoordinate(x: cx - radius, y: cy))
        let quarters = [
            try world.buildTrackEdge(from: top, to: right, curve: .cubic(PlanPoint(x: cx + handle, y: cy - radius), PlanPoint(x: cx + radius, y: cy - handle))),
            try world.buildTrackEdge(from: right, to: bottom, curve: .cubic(PlanPoint(x: cx + radius, y: cy + handle), PlanPoint(x: cx + handle, y: cy + radius))),
            try world.buildTrackEdge(from: bottom, to: left, curve: .cubic(PlanPoint(x: cx - handle, y: cy + radius), PlanPoint(x: cx - radius, y: cy + handle))),
            try world.buildTrackEdge(from: left, to: top, curve: .cubic(PlanPoint(x: cx - radius, y: cy - handle), PlanPoint(x: cx - handle, y: cy - radius))),
        ]
        // Each quarter is 4830 long; the platforms are 2560 of it.
        guard let harbor = world.station(at: GridPosition(x: 11, y: 6)) else { preconditionFailure("Harbor is built first") }
        let northGate = try world.buildStation(named: "North Gate", at: GridPosition(x: 20, y: 4))
        try world.addTrackPlatform(harbor.id, on: quarters[3], from: 512, to: 3_072)
        try world.addTrackPlatform(northGate.id, on: quarters[0], from: 1_024, to: 3_584)
        // The train stands at Harbor going clockwise, its head at the
        // platform's far end, and the line sends it out.
        let train = try world.purchaseTrain(named: "Loop")
        try world.setTrainCars(train.id, to: 3)
        try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: quarters[3], direction: .forward), offset: 3_072))
        try world.setTrainContinuation(train.id, along: [], stoppingAt: 3_072)
        try world.setTrainMovementRate(train.id, to: 512)
        let circle = try world.createLine(named: "Circle", stops: [harbor.id, northGate.id]).id
        try world.setLineServiceWindow(circle, to: .allDay)
        try world.setLineRate(circle, to: 512)
        try world.setLineTrainsInService(circle, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(train.id, to: circle)
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

        try buildLoop(in: &world)
        try buildStructures(in: &world)
        try buildLocal(in: &world)
    }

    /// Traffic control (Phase 4.6 Stage T): Local stands at Hill's platform
    /// facing south, due to leave for Central at minute 1 and back every
    /// hour. The train sent along the main line (see ``sendTrain(in:)``)
    /// takes its whole route, the four-way junction included, until it
    /// reaches the buffer stop, so Local waits for it to clear the route and
    /// its panel says which train it waits for.
    private static func buildLocal(in world: inout GameWorld) throws(GameError) {
        guard let hill = world.station(at: GridPosition(x: 5, y: 1)), let central = world.station(at: GridPosition(x: 1, y: 3)) else {
            preconditionFailure("Hill and Central are built first")
        }
        let local = try world.purchaseTrain(named: "Local")
        try world.placeTrain(local.id, at: .atNode(GridPosition(x: 5, y: 2), heading: .south))
        try world.setTrainMovementRate(local.id, to: 256)
        try world.setTrainTimetable(local.id, to: [
            ScheduledStop(station: hill.id, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: central.id, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 25), reverses: true),
            ScheduledStop(station: hill.id, arrival: GameTime(minutes: 45), departure: GameTime(minutes: 50), reverses: true),
        ], repeatingEvery: 60 * GameTime.secondsPerMinute)
        try world.startTrainService(local.id)
    }

    /// Track off the ground (Phase 4.5 Stage S4): a viaduct 512 up (8 m)
    /// across the loop, and in the south a line that runs from the ground
    /// through a portal into a tunnel falling at 1 in 25 to 512 down, with
    /// surface track crossing over the deep part. The new game's cash buys
    /// three trains, so the tunnel has none: the third is Local, which shows
    /// traffic control (see ``buildLocal(in:)``).
    private static func buildStructures(in world: inout GameWorld) throws(GameError) {
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 12 * 1_024, y: 7_680, z: 512))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 22 * 1_024, y: 7_680, z: 512))
        try world.buildTrackEdge(from: west, to: east, structure: .elevated)

        let start = try world.buildTrackNode(at: WorldCoordinate(x: 2 * 1_024, y: 16 * 1_024))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 8 * 1_024, y: 16 * 1_024))
        let deep = try world.buildTrackNode(at: WorldCoordinate(x: 8 * 1_024 + 12_800, y: 16 * 1_024, z: -512))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 28 * 1_024 + 512, y: 16 * 1_024, z: -512))
        try world.buildTrackEdge(from: start, to: portal)
        try world.buildTrackEdge(from: portal, to: deep, structure: .tunnel)
        try world.buildTrackEdge(from: deep, to: end, structure: .tunnel)
        let north = try world.buildTrackNode(at: WorldCoordinate(x: 25 * 1_024, y: 13 * 1_024))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: 25 * 1_024, y: 20 * 1_024))
        try world.buildTrackEdge(from: north, to: south)
    }
}
#endif
