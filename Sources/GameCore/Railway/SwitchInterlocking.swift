// Switches take time to throw (SWITCH-THROW, decision 756). Under traffic
// control a train already takes its whole route before it starts along it,
// no other train can take a switch it holds, and the track behind it frees
// as it goes (decisions 32, 55): the interlocking the owner's desktop game
// has. What it did not have was the switch itself: a train could go either
// way through a junction at once, as if every switch already lay the way
// it wanted.
//
// With ``GameWorld/switchInterlocking`` on, a switch lies the way the last
// train went through it, and a service leaving a stop whose route goes
// through a switch that lies the other way waits ``GameWorld/switchThrowSeconds``
// before it moves: the switches of its route are thrown together, as power
// points are, so one throw or several is the same wait. A switch no train
// has gone through yet lies the way the first train wants. The train holds
// its whole route while it waits, so nobody else can take it and nobody
// waits for half a route (design `SWITCH_LOCK_DESIGN_2026-11-13.md` §4).
//
// The wait is the run setting off later (``ServiceRun/delayed(by:)``), as
// a train of real runs waits for its platform with traffic control off
// (decision 228), so the train stands at the platform with its doors
// closed and its route set until the switches lie. Only a departure from
// a stop waits: a train already moving whose route reaches on (a train
// following another, decision 56; block sections, decision 212) passes
// switches set as it goes, as the measurements' prototype did.

/// The way a switch lies (decision 756): the two edges the last train
/// went through it between, the lower numbered first.
public struct SwitchLie: Hashable, Sendable {
    public let low: TrackEdgeID
    public let high: TrackEdgeID

    /// The lie of a train going between `a` and `b`, in either order.
    init(_ a: TrackEdgeID, _ b: TrackEdgeID) {
        (low, high) = a < b ? (a, b) : (b, a)
    }
}

/// A switch's lie as a save keeps it: `{"node": n, "edges": [a, b]}`, the
/// edges ascending.
struct SavedSwitchLie: Codable {
    let node: Int
    let edges: [Int]
}

extension GameWorld {
    /// How long the switches of a route take to throw (decision 756), in
    /// game seconds. Power points take 3 to 6 seconds; the owner's desktop
    /// game has 8. Measured on 14 maps (SWITCH-THROW-MEASURE, 2026-11-14):
    /// 6 put the Airport MRT's mean wait for a route up by 68 % and 8
    /// trebled its trains that never left, so the game takes 4, the low
    /// end of real ones, which costs least.
    public static let switchThrowSeconds: Int64 = 4

    /// Turns switch interlocking on or off (decision 756). It acts only
    /// with traffic control on. Turned off, every switch forgets how it
    /// lies; turned on again, each lies the way the next train wants.
    public mutating func setSwitchInterlocking(_ enabled: Bool) {
        guard enabled != switchInterlocking else { return }
        switchInterlocking = enabled
        if !enabled { switchLies = [:] }
    }

    /// When train `id`, a service's that has left a stop, may start
    /// along its route because the switches of it are being thrown
    /// (decision 756); `nil` when it is not waiting for them. Derived on
    /// every call: the run's start is already saved.
    public func switchesThrownUntil(of id: TrainID) -> GameTime? {
        guard switchInterlocking, isTrafficControlEnabled, let train = train(id: id),
              case .travellingToStop? = train.execution, let run = train.times?.run, run.start > clock.now
        else { return nil }
        return run.start
    }

    /// Whether `node` is a switch: a train arriving along one of its edges
    /// could leave by two or more.
    func isSwitch(_ node: TrackNodeID) -> Bool {
        network.node(node)?.ends.contains { $0.exits.count > 1 } ?? false
    }

    /// The switches a train on `traversal` goes through as it enters
    /// `edges` in turn, each with the way it goes through it, in order.
    /// Stops at an edge that is not on the network or does not join.
    func switchesPassed(from traversal: TrackTraversal, entering edges: some Sequence<TrackEdgeID>) -> [(node: TrackNodeID, lie: SwitchLie)] {
        guard var node = network.edge(traversal.edge)?.end(of: traversal.direction) else { return [] }
        var previous = traversal.edge
        var passed: [(node: TrackNodeID, lie: SwitchLie)] = []
        for edge in edges {
            guard let entered = network.edge(edge), let on = entered.traversal(leaving: node) else { break }
            if isSwitch(node) { passed.append((node, SwitchLie(previous, edge))) }
            node = entered.end(of: on.direction)
            previous = edge
        }
        return passed
    }

    /// Decision 756: the switches a train went through as it moved from
    /// `traversal` into `edges` now lie the way it went.
    mutating func noteSwitches(from traversal: TrackTraversal, entering edges: ArraySlice<TrackEdgeID>) {
        guard switchInterlocking, isTrafficControlEnabled, !edges.isEmpty else { return }
        for (node, lie) in switchesPassed(from: traversal, entering: edges) {
            switchLies[node] = lie
        }
    }

    /// Decision 756: the run of `train`, which has just set off from a
    /// stop, started ``switchThrowSeconds`` later, when a switch it holds
    /// on its route lies the other way; `nil` when it need not wait. A
    /// switch no train has gone through lies the way it wants.
    func runAfterThrowingSwitches(of train: Train) -> ServiceRun? {
        guard switchInterlocking, isTrafficControlEnabled,
              case .travellingToStop? = train.execution, let run = train.times?.run,
              case .onEdge(let traversal, _)? = train.position
        else { return nil }
        var held: Set<TrackNodeID> = []
        for resource in train.reservation {
            if case .node(let node) = resource { held.insert(node) }
        }
        guard !held.isEmpty else { return nil }
        let thrown = switchesPassed(from: traversal, entering: train.movement.remainingEdges).contains { node, lie in
            held.contains(node) && switchLies[node].map { $0 != lie } == true
        }
        return thrown ? run.delayed(by: Self.switchThrowSeconds) : nil
    }

    /// The switches' lies as a save keeps them, by node.
    var savedSwitchLies: [SavedSwitchLie] {
        switchLies.sorted { $0.key < $1.key }.compactMap { node, lie in
            guard let number = node.networkNumber, let low = lie.low.networkNumber, let high = lie.high.networkNumber else { return nil }
            return SavedSwitchLie(node: number, edges: [low, high])
        }
    }

    /// The lies of `saved`, or `nil` when they are not ordered by node,
    /// one each, with two ascending edges, every number from 1.
    static func switchLies(of saved: [SavedSwitchLie]) -> [TrackNodeID: SwitchLie]? {
        guard zip(saved, saved.dropFirst()).allSatisfy({ $0.node < $1.node }) else { return nil }
        var lies: [TrackNodeID: SwitchLie] = [:]
        for lie in saved {
            guard lie.node >= 1, lie.edges.count == 2, lie.edges[0] >= 1, lie.edges[0] < lie.edges[1] else { return nil }
            lies[.node(lie.node)] = SwitchLie(.edge(lie.edges[0]), .edge(lie.edges[1]))
        }
        return lies
    }
}
