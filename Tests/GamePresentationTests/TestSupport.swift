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
func newGameLine(through points: [PlanPoint]) throws -> GameWorld {
    var world = GameWorld.newGame()
    let cars = 4
    let platform = Int64(cars) * Train.carLength
    func beyond(_ from: PlanPoint, _ to: PlanPoint) -> WorldCoordinate {
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let span = (dx * dx + dy * dy).squareRoot()
        return WorldCoordinate(x: to.x + Int64(dx / span * Double(platform)), y: to.y + Int64(dy / span * Double(platform)))
    }
    var nodes = [try world.buildTrackNode(at: beyond(points[1], points[0]))]
    for point in points.dropFirst().dropLast() {
        nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: point.x, y: point.y)))
    }
    nodes.append(try world.buildTrackNode(at: beyond(points[points.count - 2], points[points.count - 1])))
    var edges: [TrackEdgeID] = []
    for (from, to) in zip(nodes, nodes.dropFirst()) {
        edges.append(try world.buildTrackEdge(from: from, to: to))
    }
    var stops: [StationID] = []
    for (index, point) in points.enumerated() {
        let station = try world.buildStation(named: "S\(index)", at: point).id
        if index == 0 {
            try world.addTrackPlatform(station, on: edges[0], from: platform / 2, to: platform + platform / 2)
        } else if index == points.count - 1 {
            let length = world.trackEdge(edges[index - 1])?.length ?? 0
            try world.addTrackPlatform(station, on: edges[index - 1], from: length - platform - platform / 2, to: length - platform / 2)
        } else {
            try world.addTrackPlatform(station, on: edges[index], from: 0, to: platform)
        }
        stops.append(station)
    }
    let line = try world.createLine(named: "Line 1", stops: stops).id
    try world.setLineServiceWindow(line, to: .allDay)
    try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
    let train = try world.purchaseTrain(named: "Train 1").id
    try world.setTrainCars(train, to: cars)
    // Its head at the first platform's far end.
    try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edges[0], direction: .forward), offset: platform + platform / 2))
    try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2)
    try world.setTrainMovementRate(train, to: 512)
    try world.assignTrain(train, to: line)
    return world
}
