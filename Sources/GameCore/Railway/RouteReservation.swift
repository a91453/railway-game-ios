// Route reservation (Phase 4.6 Stage T, ARCHITECTURE decision 32). Under
// traffic control a train takes the whole of a route before it starts
// along it: everything its whole length covers from where its tail is to
// where the route ends, as one atomic reservation, or nothing. No two trains
// ever hold the same track: what a train stands on, the junctions it is
// close enough to foul, and what it has reserved. A command that would give
// a train track another train holds is refused (trackReserved), and a
// service or a line whose route is held waits where it is and tries again
// at every step.
//
// The reservation is authoritative state kept on the train. Since Stage U
// (ARCHITECTURE decision 55) it is released behind the train as it goes:
// after every move it keeps only what the train still needs, so track the
// train's tail has left is free for others at once, and all of it is
// released when the route ends. Since Stage U2 (ARCHITECTURE decision 56) a
// service may follow a train ahead of it between calls: it takes the route
// as far as ``GameWorld/followingGap`` short of the track the train ahead
// holds, and the rest as it frees.
// Everything here reads topology and integer chainage only: traversals,
// spans, edge lengths, platforms and where paths end, never geometry.
//
// A leg of 30 to 180 km is thousands of spans, so the questions are asked
// without listing them (NEXT_PRIORITIES 2026-10-12 §2 item 6, every answer
// as before): a route envelope is kept as its stretches, by edge and
// chainage (TrackCover); who holds what is worked out once for the trains
// as they are and looked up by edge (TrackHolders), and kept, with each
// train's movement authority, in a memo for as long as the trains stay as
// they are.

/// A stretch of one edge that a train covers: along
/// `traversal`, from `from` to `to`, both measured the way it is travelled
/// from its start (`0 <= from <= to <=` its length).
struct TrackStretch: Hashable, Sendable {
    let traversal: TrackTraversal
    let from: Int64
    let to: Int64
}

/// A train waiting for its route under traffic control (Stage V4e,
/// decision 64; see ``GameWorld/routeWaits()``).
public struct RouteWait: Hashable, Sendable {
    public let train: TrainID
    /// The train holding its route (see ``GameWorld/trainHoldingRoute(of:)``).
    public let holder: TrainID
    /// The track where the two meet (see
    /// ``GameWorld/contestedResources(of:)``).
    public let contested: [TrackResource]
    /// Whether it is in a deadlock (see ``GameWorld/deadlockedTrains()``).
    public let isDeadlocked: Bool

    public init(train: TrainID, holder: TrainID, contested: [TrackResource], isDeadlocked: Bool) {
        self.train = train
        self.holder = holder
        self.contested = contested
        self.isDeadlocked = isDeadlocked
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The track train `id` has reserved for its route under traffic
    /// control, in resource order (see ``Train/reservation``): everything
    /// its whole length covers from where its tail was when it took the
    /// route to where the route ends, with the junctions it fouls on the
    /// way. Empty when traffic control is off, for a train with no way left
    /// to go, and for an unplaced train or an unknown ID.
    public func reservedResources(of id: TrainID) -> [TrackResource] {
        train(id: id)?.reservation ?? []
    }

    /// The track train `id` holds under traffic control, in resource order:
    /// what it stands on (see ``occupiedResources(of:)``), each junction of
    /// the track network it is close enough to foul (within
    /// ``RailwayNetwork/junctionZone`` of the node, on an edge that meets
    /// another there without joining it), and its reservation. No other
    /// train can take any of it. Empty for an unplaced train or an unknown
    /// ID.
    public func heldResources(of id: TrainID) -> [TrackResource] {
        guard let train = train(id: id) else { return [] }
        return held(train).sorted()
    }

    /// The train that holds track on the route train `id` is waiting to
    /// take under traffic control, or `nil`: the lowest numbered such train.
    ///
    /// A service waits for its route at a stop where its departure is due
    /// (its doors have closed; Stage W2b): from where it would stand
    /// (turned round first where the stop says so), along the path to its
    /// next call. A line's train waits
    /// for its route when it has no service, stands at its service's first
    /// call ready to go, and the line is due to send a train out: along the
    /// first leg of its trip. A service stopped at a passing place (Stage
    /// V2, see ``deadlockedTrains()``) waits for its route on to its call.
    /// `nil` when traffic control is off, for a
    /// train not waiting for a route (not due, without a route, or with its
    /// route free), and for an unknown ID. Derived on every call, never
    /// saved.
    public func trainHoldingRoute(of id: TrainID) -> TrainID? {
        awaitedRoute(of: id)?.holder
    }

    /// Stage V4e (decision 64): where train `id` and the train holding its
    /// route (see ``trainHoldingRoute(of:)``) meet, in resource order: the
    /// track of the route it waits to take that the holder holds or fouls
    /// (see ``RailwayNetwork/fouls(_:_:)``), or, following trains ahead
    /// (Stage U2), still waits for. For a map to show what keeps it. Empty
    /// when it waits for no route, and for a scheduled wait (decision 59),
    /// which keeps it at a station for a train by plan, not for track. Derived
    /// on every call, never saved.
    public func contestedResources(of id: TrainID) -> [TrackResource] {
        awaitedRoute(of: id).map { contested($0, for: id) } ?? []
    }

    /// Every train waiting for its route under traffic control, in
    /// ascending ID order (Stage V4e, decision 64): what
    /// ``trainHoldingRoute(of:)``, ``contestedResources(of:)`` and
    /// ``deadlockedTrains()`` tell of each, worked out together for a map
    /// to draw at once. Empty with traffic control off. Derived on every
    /// call, never saved.
    public func routeWaits() -> [RouteWait] {
        guard isTrafficControlEnabled else { return [] }
        var memo = DirectionMemo()
        let deadlocked = Set(deadlock(memo: &memo).keys)
        return trains.sorted { $0.id < $1.id }.compactMap { train in
            guard let wait = awaitedRoute(of: train.id, memo: &memo) else { return nil }
            return RouteWait(train: train.id, holder: wait.holder, contested: contested(wait, for: train.id), isDeadlocked: deadlocked.contains(train.id))
        }
    }

    /// See ``contestedResources(of:)``.
    private func contested(_ wait: (holder: TrainID, needs: Set<TrackResource>?), for id: TrainID) -> [TrackResource] {
        guard let needs = wait.needs, let holder = train(id: wait.holder) else { return [] }
        var blocking = held(holder)
        if let claim = claim(of: holder), (train(id: id).map(held) ?? []).isDisjoint(with: claim.route) {
            blocking.formUnion(claim.waiting)
        }
        return needs.filter { network.fouls([$0], blocking) }.sorted()
    }

    /// The train holding the route train `id` waits for (see
    /// ``trainHoldingRoute(of:)``), with the track that route needs; `nil`
    /// track for a scheduled wait.
    private func awaitedRoute(of id: TrainID) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        var memo = DirectionMemo()
        return awaitedRoute(of: id, memo: &memo)
    }

    private func awaitedRoute(of id: TrainID, memo: inout DirectionMemo) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil else { return nil }
        if let wait = currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo) { return (wait.other, nil) }
        if isFollowing(train, memo: &memo) {
            // Stage U2: a train following others waits for the rest of its
            // route.
            let needs = routeEnvelope(of: train).resources
            return holder(of: needs, except: id, memo: &memo).map { ($0, needs) }
        }
        guard let departing = departureRequest(of: train, memo: &memo) else { return nil }
        if case .granted(let granted) = reservingDeparture(departing, memo: &memo), !isFollowing(granted, memo: &memo) { return nil }
        let needs = routeEnvelope(of: departing).resources
        return holder(of: needs, except: id, memo: &memo).map { ($0, needs) }
    }

    // MARK: - What a train needs

    /// `candidate`, a train about to be given a place or a route, with the
    /// reservation traffic control gives it, or the lowest numbered other
    /// train that holds track it needs. With traffic control off, the
    /// candidate as it is.
    enum Reserving {
        case granted(Train)
        case held(by: TrainID)
    }

    /// See ``Reserving``. A service's departure (`following`, Stage U2)
    /// whose route another train holds may instead follow the trains
    /// ahead, taking its route only part of the way (see
    /// ``followingAuthority(of:route:memo:)``).
    func reserving(_ candidate: Train, following: Bool = false) -> Reserving {
        var memo = DirectionMemo()
        return reserving(candidate, following: following, memo: &memo)
    }

    /// ``reserving(_:following:)`` with the trains' holders kept in `memo`.
    func reserving(_ candidate: Train, following: Bool = false, memo: inout DirectionMemo) -> Reserving {
        guard isTrafficControlEnabled else { return .granted(candidate) }
        // Its route envelope (see ``routeEnvelope(of:)``), asked a resource
        // at a time, and gathered only to be taken.
        let route = routeStretches(of: candidate)
        let envelope = cover(of: bodyStretches(of: candidate) + route.stretches)
        if let holder = holder(of: envelope, except: candidate.id, holders: trackHolders(memo: &memo)) {
            if following, route.moves, let train = followingAuthority(of: candidate, route: envelope, memo: &memo) {
                return .granted(train)
            }
            return .held(by: holder)
        }
        var train = candidate
        train.reservation = route.moves ? Set(envelope.resources).sorted() : []
        return .granted(train)
    }

    /// Decision 57: a service's departure takes its default route whole,
    /// or follows the trains ahead on it (Stage U2) where it may; failing
    /// both, it takes the shortest unblocked route to any berth of the same
    /// station whole (see ``alternativeRoute(of:to:avoiding:memo:)``);
    /// failing that, it waits. Manual commands keep using `reserving`
    /// directly. No route or reservation is committed until the final
    /// candidate has been admitted.
    func reservingDeparture(_ candidate: Train) -> Reserving {
        var memo = DirectionMemo()
        return reservingDeparture(candidate, memo: &memo)
    }

    func reservingDeparture(_ candidate: Train, memo: inout DirectionMemo) -> Reserving {
        let planned = reserving(candidate, following: true, memo: &memo)
        guard isTrafficControlEnabled, case .held = planned,
              case .travellingToStop(let stop, let cycle)? = candidate.execution,
              let alternative = alternativeRoute(of: candidate, to: candidate.timetable[stop].station,
                                                 avoiding: blockedTrack(except: candidate.id, holders: trackHolders(memo: &memo)), memo: &memo)
        else { return planned }
        var rerouted = candidate
        follow(alternative, &rerouted)
        let previousStop = stop == 0 ? candidate.timetable.count - 1 : stop - 1
        let previousCycle = stop == 0 ? cycle - 1 : cycle
        let scheduled = candidate.scheduledArrival(of: stop, cycle: cycle).seconds
            - candidate.scheduledDeparture(of: previousStop, cycle: previousCycle).seconds
        let reroutedRun = run(of: rerouted, length: alternative.distance, scheduled: scheduled)
        rerouted.times?.run = reroutedRun
        if case .granted(let granted) = reserving(rerouted, memo: &memo) { return .granted(granted) }
        return planned
    }

    /// How much longer than a service's default route an alternative
    /// route (decision 57) or a way through a passing place (Stage V2) may
    /// be: 25,600 units, 400 m, the Railway reference's `BLOCK_GAP_KM`.
    /// Going to another platform of a station, or into a passing loop,
    /// adds only the turnouts' few metres; a route that leaves the line for
    /// another adds kilometres, and is not taken.
    public static let detourAllowance: Int64 = 25_600

    /// Decision 57: the shortest route for `candidate`, a service about to
    /// set off along its default route (see
    /// ``path(from:toStation:length:)``), to a berth of `station` that
    /// avoids `blocked` (see ``path(from:toStation:length:avoiding:forbidden:)``),
    /// that never borrows track against another train's planned direction
    /// (see ``opposingServiceTraversals(for:memo:)``), and that is at most
    /// ``detourAllowance`` longer than the default route; or `nil`.
    func alternativeRoute(of candidate: Train, to station: StationID, avoiding blocked: BlockedTrack, memo: inout DirectionMemo) -> TrainPath? {
        guard let position = candidate.position else { return nil }
        let (limit, overflow) = routeLength(of: candidate).addingReportingOverflow(Self.detourAllowance)
        // Without the other trains' directions first: with them the
        // shortest way can only be as long or longer, or none, so where
        // there is no way short enough without them there is none with
        // them, and they need not be worked out.
        guard let free = path(from: position, toStation: station, length: candidate.length, avoiding: blocked),
              overflow || free.distance <= limit,
              let path = path(from: position, toStation: station, length: candidate.length,
                              avoiding: blocked, forbidden: opposingServiceTraversals(for: candidate, memo: &memo))
        else { return nil }
        return overflow || path.distance <= limit ? path : nil
    }

    /// The lowest numbered train other than `id` that holds any of
    /// `resources` (see ``held(_:)``), or track that fouls any of them
    /// (Stage F2b, see ``RailwayNetwork/fouls(_:_:)``), or that follows
    /// another (Stage U2) and still needs some of them, unless train `id`
    /// already holds track that one needs (see ``claim(of:)``); or `nil`.
    func holder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        var memo = DirectionMemo()
        return holder(of: resources, except: id, memo: &memo)
    }

    /// ``holder(of:except:)`` from the trains' holders kept in `memo` (see
    /// ``trackHolders(memo:)``).
    func holder(of resources: Set<TrackResource>, except id: TrainID, memo: inout DirectionMemo) -> TrainID? {
        holder(of: resources, except: id, holders: trackHolders(memo: &memo))
    }

    /// Everything the trains other than `id` keep it from, together (see
    /// ``holder(of:except:)``): track fouling any of it has a holder. For
    /// trying many stretches against the same trains.
    func blockedTrack(except id: TrainID) -> Set<TrackResource> {
        var memo = DirectionMemo()
        return blockedTrack(except: id, memo: &memo)
    }

    /// ``blockedTrack(except:)`` from the trains' holders kept in `memo`.
    func blockedTrack(except id: TrainID, memo: inout DirectionMemo) -> Set<TrackResource> {
        blockedTrack(except: id, holders: trackHolders(memo: &memo)).resources
    }

    /// A train's reservation (see ``Train/reservation``), to ask whether it
    /// holds a resource: by halving while it is in resource order, as the
    /// game keeps it, else through a set of it. A set of a reservation some
    /// hundreds long, built for every question, was much of the time
    /// traffic control took. In resource order the spans of each edge come
    /// together, in order along it, so they are found by their edge first.
    struct ReservedTrack {
        private let ordered: [TrackResource]
        private let unordered: Set<TrackResource>?
        /// In resource order: where the spans of each edge lie.
        let runs: EdgeTable<Range<Int>>
        /// In resource order: how many nodes come first.
        let nodeCount: Int
        /// The longest of its spans (0 without any).
        let longest: Int64

        init(_ reservation: [TrackResource]) {
            ordered = reservation
            var runs = EdgeTable<Range<Int>>()
            var nodeCount = 0
            var isOrdered = true
            var runStart = 0
            var runEdge: TrackEdgeID?
            var longest: Int64 = 0
            for index in reservation.indices {
                if index > 0, !(reservation[index - 1] < reservation[index]) {
                    isOrdered = false
                    break
                }
                switch reservation[index] {
                case .node:
                    nodeCount = index + 1
                case .span(let span):
                    longest = max(longest, span.length)
                    if span.edge != runEdge {
                        if let runEdge { runs.append(runEdge, runStart..<index) }
                        runEdge = span.edge
                        runStart = index
                    }
                }
            }
            if isOrdered, let runEdge { runs.append(runEdge, runStart..<reservation.count) }
            unordered = isOrdered ? nil : Set(reservation)
            self.runs = isOrdered ? runs : EdgeTable()
            self.nodeCount = isOrdered ? nodeCount : 0
            self.longest = longest
        }

        /// Whether it holds every span of `spans` (an edge's, in order
        /// along it) that shares a point with chainage `low` to `high` of an
        /// edge `length` long (see ``TrackCover``): walked along beside its
        /// own spans of the edge, and found by halving where they part.
        func containsAll(_ spans: [TrackSpan], from low: Int64, to high: Int64, length: Int64) -> Bool {
            // The edge's spans are in order and end in order.
            var (lower, upper) = (0, spans.count)
            while lower < upper {
                let middle = (lower + upper) / 2
                if spans[middle].end < low {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            var next: Int?
            for span in spans[lower...] {
                guard span.start <= high else { break }
                guard TrackCover.covers(low, high, span, length: length) else { continue }
                if let index = next, index < ordered.count, ordered[index] == .span(span) {
                    next = index + 1
                    continue
                }
                guard let index = index(of: .span(span)) else { return false }
                next = index + 1
            }
            return true
        }

        /// Where `resource` is in it, or `nil`; out of order, the end
        /// index if it holds it.
        private func index(of resource: TrackResource) -> Int? {
            if let unordered { return unordered.contains(resource) ? ordered.count : nil }
            let range: Range<Int>
            switch resource {
            case .node: range = 0..<nodeCount
            case .span(let span):
                guard let run = runs[span.edge] else { return nil }
                range = run
            }
            var (low, high) = (range.lowerBound, range.upperBound)
            while low < high {
                let middle = (low + high) / 2
                if ordered[middle] < resource {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low < range.upperBound && ordered[low] == resource ? low : nil
        }

        /// The spans of edge `edge`, in order, that may share a point with
        /// chainage `low` to `high` of it (the rest cannot): in resource
        /// order, from the first that starts no more than its longest span
        /// before `low`, to the last that starts at `high` or before; `nil`
        /// out of order.
        func spans(of edge: TrackEdgeID, from low: Int64, to high: Int64) -> ArraySlice<TrackResource>? {
            guard isOrdered else { return nil }
            guard let run = runs[edge] else { return [] }
            func first(startingAfter limit: Int64, orAt: Bool) -> Int {
                var (lower, upper) = (run.lowerBound, run.upperBound)
                while lower < upper {
                    let middle = (lower + upper) / 2
                    guard case .span(let span) = ordered[middle] else { preconditionFailure("a run holds spans") }
                    if span.start < limit || (orAt && span.start == limit) {
                        lower = middle + 1
                    } else {
                        upper = middle
                    }
                }
                return lower
            }
            let from = first(startingAfter: low - longest, orAt: false)
            let to = first(startingAfter: high, orAt: true)
            return from < to ? ordered[from..<to] : []
        }

        /// Whether the reservation is in resource order, without repeats.
        var isOrdered: Bool { unordered == nil }

        func contains(_ resource: TrackResource) -> Bool {
            index(of: resource) != nil
        }
    }

    /// The track a train holds (see ``held(_:)``), to ask a resource at a
    /// time.
    struct HeldTrack {
        /// What it stands on and the junctions its body fouls.
        let body: Set<TrackResource>
        let reservation: [TrackResource]
        let reserved: ReservedTrack

        func contains(_ resource: TrackResource) -> Bool {
            body.contains(resource) || reserved.contains(resource)
        }

        /// All of it, some perhaps twice.
        var resources: [TrackResource] { Array(body) + reservation }
    }

    func heldTrack(_ train: Train) -> HeldTrack {
        let body = bodyStretches(of: train)
        var standing = Set(resources(covering: body))
        standing.formUnion(foulingNodes(covering: body))
        return HeldTrack(body: standing, reservation: train.reservation, reserved: ReservedTrack(train.reservation))
    }

    /// What following a train ahead claims (see ``claim(of:)``): its whole
    /// route envelope, and of that what no other train holds, which it
    /// waits for (see ``TrackHolders/waits(_:for:)``). The route is kept as
    /// its stretches (see ``TrackCover``), rather than all the thousands of
    /// spans of a long leg gathered into a set.
    struct Claim {
        /// The train that follows.
        let train: TrainID
        /// Its route envelope.
        let cover: TrackCover
        /// The spans it waits for that foul spans of other edges (see
        /// ``RailwayNetwork/foulingSpans``).
        fileprivate var foulingWaiting: [TrackSpan] = []

        /// Whether `resource` is on its route.
        func routeContains(_ resource: TrackResource) -> Bool {
            cover.contains(resource)
        }

        /// Every resource of its route, gathered.
        var route: Set<TrackResource> {
            Set(cover.resources)
        }
    }

    /// What every train holds (see ``held(_:)``) and, following another,
    /// claims (see ``claim(of:)``), worked out once to ask
    /// ``holder(of:except:holders:)`` and
    /// ``blockedTrack(except:holders:)`` of many trains of one world:
    /// who holds each resource is found from where it is, not by asking
    /// every train.
    struct TrackHolders {
        /// The trains' IDs, in the world's order.
        let ids: [TrainID]
        let held: [TrainID: HeldTrack]
        let claims: [TrainID: Claim]
        /// By a train's place in ``ids``: what it holds, and, when it is
        /// placed, the spans of that which foul others.
        fileprivate let tracks: [HeldTrack?]
        fileprivate let fouling: [[TrackSpan]]
        /// The placed trains holding each resource of their bodies, and
        /// each node, and each resource of a reservation out of order, by
        /// place, in order (perhaps twice).
        fileprivate let owners: [TrackResource: [Int]]
        /// The placed trains whose reservation, in order, holds spans of
        /// each edge, by place, in order.
        fileprivate let runs: [TrackEdgeID: [Int]]
        /// The spans of each edge that foul spans of others, in order.
        fileprivate let foulingByEdge: [TrackEdgeID: [TrackSpan]]
        /// The spans of each edge the placed trains stand on, with their
        /// places.
        fileprivate let bodies: [TrackEdgeID: [(place: Int, span: TrackSpan)]]
        /// The places of placed trains whose reservation is out of order.
        fileprivate let unordered: [Int]

        /// Whether the train at `place` is placed, is not `id` and, given
        /// `among`, is one of those.
        private func isOther(_ place: Int, _ id: TrainID, _ among: Set<TrainID>?) -> Bool {
            tracks[place] != nil && ids[place] != id && among?.contains(ids[place]) != false
        }

        /// The first place of a placed train other than `id` (of `among`,
        /// given) that holds track `cover` covers (see ``TrackCover``), or
        /// holds track fouling it, if `fouling`.
        fileprivate func firstHolding(_ cover: TrackCover, except id: TrainID, among: Set<TrainID>?, fouling: Bool, in network: RailwayNetwork) -> Int? {
            var first = ids.count
            for node in cover.nodes {
                for place in owners[node] ?? [] where place < first && isOther(place, id, among) {
                    first = place
                }
            }
            // A reservation out of order.
            for place in unordered where place < first && isOther(place, id, among) {
                if tracks[place]!.reservation.contains(where: cover.contains) {
                    first = place
                    break
                }
            }
            // What they stand on, and reservations in order, by the edges
            // the cover lies on.
            for edge in cover.edges {
                for body in bodies[edge] ?? [] where body.place < first && isOther(body.place, id, among) && cover.contains(.span(body.span)) {
                    first = body.place
                }
                guard let holding = runs[edge], let bounds = cover.bounds(on: edge) else { continue }
                for place in holding where place < first && isOther(place, id, among) {
                    if tracks[place]!.reserved.spans(of: edge, from: bounds.low, to: bounds.high)!.contains(where: cover.contains) {
                        first = place
                        break
                    }
                }
            }
            if fouling {
                for place in 0..<first where isOther(place, id, among) {
                    if self.fouling[place].contains(where: { network.foulingSpans[$0]!.contains { cover.contains(.span($0)) } }) {
                        first = place
                        break
                    }
                }
            }
            return first < ids.count ? first : nil
        }

        /// Whether `claim`'s train waits for track `cover` covers.
        fileprivate func waits(_ claim: Claim, forAnyIn cover: TrackCover) -> Bool {
            if cover.nodes.contains(where: { waits(claim, for: $0) }) { return true }
            for edge in cover.edges {
                guard let ours = cover.bounds(on: edge), let theirs = claim.cover.bounds(on: edge) else { continue }
                // A span both cover starts by the lower of their ends and
                // ends by the higher of their starts.
                if cover.anySpan(of: edge, from: max(ours.low, theirs.low), to: min(ours.high, theirs.high), where: { waits(claim, for: .span($0)) }) {
                    return true
                }
            }
            return false
        }

        /// The first train other than `id` holding, fouling or waiting for
        /// track `cover` covers, as ``holder(of:except:holders:)`` asks.
        func firstHolder(of cover: TrackCover, except id: TrainID, in network: RailwayNetwork) -> TrainID? {
            var first = firstHolding(cover, except: id, among: nil, fouling: true, in: network) ?? ids.count
            for place in 0..<first where isOther(place, id, nil) {
                guard let claim = claims[ids[place]], !holdsAny(of: claim, id) else { continue }
                if waits(claim, forAnyIn: cover)
                    || claim.foulingWaiting.contains(where: { network.foulingSpans[$0]!.contains { cover.contains(.span($0)) } }) {
                    first = place
                    break
                }
            }
            return first < ids.count ? ids[first] : nil
        }

        /// Whether train `id` holds any of `claim`'s route, which keeps it
        /// from waiting for that claim (see ``holder(of:except:)``).
        func holdsAny(of claim: Claim, _ id: TrainID) -> Bool {
            guard let own = held[id] else { return false }
            return own.body.contains(where: claim.routeContains) || own.reservation.contains(where: claim.routeContains)
        }

        /// Whether `claim`'s train waits for `resource`: it is on its route
        /// and no other placed train holds it.
        func waits(_ claim: Claim, for resource: TrackResource) -> Bool {
            claim.routeContains(resource) && !isHeld(resource, except: claim.train, among: nil)
        }

        /// What train `id`, following another, waits for (see ``claim(of:)``),
        /// gathered; `nil` when it follows no train.
        func waiting(of id: TrainID) -> Set<TrackResource>? {
            claims[id].map { claim in claim.route.filter { !isHeld($0, except: id, among: nil) } }
        }

        /// Whether track `claim`'s train waits for is any of `resources`, or
        /// fouls any of them (see ``RailwayNetwork/fouls(_:_:)``).
        func waits(_ claim: Claim, forAnyOf resources: Set<TrackResource>, in network: RailwayNetwork) -> Bool {
            if resources.contains(where: { waits(claim, for: $0) }) { return true }
            return claim.foulingWaiting.contains { network.foulingSpans[$0]!.contains { resources.contains(.span($0)) } }
        }

        /// Whether a placed train other than `id` (and, given `among`, one
        /// of those) holds `resource`.
        fileprivate func isHeld(_ resource: TrackResource, except id: TrainID, among: Set<TrainID>?) -> Bool {
            func other(_ place: Int) -> Bool {
                ids[place] != id && among?.contains(ids[place]) != false
            }
            if owners[resource]?.contains(where: other) == true { return true }
            guard case .span(let span) = resource, let holding = runs[span.edge] else { return false }
            return holding.contains { other($0) && tracks[$0]!.reserved.contains(resource) }
        }

        /// The first place, below `limit`, of a placed train other than
        /// `id` holding `resource`.
        fileprivate func firstHolder(of resource: TrackResource, except id: TrainID, below limit: Int) -> Int? {
            var first: Int?
            for place in owners[resource] ?? [] where place < (first ?? limit) && ids[place] != id {
                first = place
            }
            if case .span(let span) = resource, let holding = runs[span.edge] {
                for place in holding where place < (first ?? limit) && ids[place] != id && tracks[place]!.reserved.contains(resource) {
                    first = place
                    break
                }
            }
            return first
        }
    }

    func trackHolders() -> TrackHolders {
        trackHolders(authorities: trains.map(authority))
    }

    /// The world's track holders (see ``trackHolders()``), kept in `memo`
    /// for as long as the trains stay as they are: worked out again once
    /// any train is not the same. Within one memo the network and traffic
    /// control do not change (a memo lives for one ``advance(ticks:)`` or
    /// one question), and a train's holding depends on nothing else. The
    /// last two sets of trains asked about are kept: a passing place is
    /// tried in a world with one train moved (see ``replacing(_:)``),
    /// between questions of the world itself.
    func trackHolders(memo: inout DirectionMemo) -> TrackHolders {
        if let index = memo.holders.firstIndex(where: { $0.trains == trains }) {
            if index != 0 { memo.holders.insert(memo.holders.remove(at: index), at: 0) }
            return memo.holders[0].holders
        }
        var authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?] = []
        for train in trains {
            authorities.append(authority(of: train, memo: &memo))
        }
        let holders = trackHolders(authorities: authorities)
        memo.holders.insert((trains, holders), at: 0)
        if memo.holders.count > 2 { memo.holders.removeLast() }
        return holders
    }

    /// The spans of each edge that foul spans of others (see
    /// ``RailwayNetwork/foulingSpans``), in order.
    private func foulingSpansByEdge() -> [TrackEdgeID: [TrackSpan]] {
        var byEdge: [TrackEdgeID: [TrackSpan]] = [:]
        for span in network.foulingSpans.keys {
            byEdge[span.edge, default: []].append(span)
        }
        return byEdge.mapValues { $0.sorted() }
    }

    /// ``trackHolders()`` knowing ``authority(of:)`` of every train, in
    /// order.
    func trackHolders(authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?]) -> TrackHolders {
        var held: [TrainID: HeldTrack] = [:]
        var tracks: [HeldTrack?] = []
        var fouling: [[TrackSpan]] = []
        var owners: [TrackResource: [Int]] = [:]
        var runs: [TrackEdgeID: [Int]] = [:]
        var bodies: [TrackEdgeID: [(place: Int, span: TrackSpan)]] = [:]
        var unordered: [Int] = []
        let foulingByEdge = network.foulingSpans.isEmpty ? [:] : foulingSpansByEdge()
        for (place, train) in trains.enumerated() {
            let track = heldTrack(train)
            held[train.id] = track
            guard train.position != nil else {
                tracks.append(nil)
                fouling.append([])
                continue
            }
            tracks.append(track)
            for resource in track.body {
                owners[resource, default: []].append(place)
                if case .span(let span) = resource { bodies[span.edge, default: []].append((place, span)) }
            }
            var foulingHeld = track.body.compactMap { resource -> TrackSpan? in
                guard case .span(let span) = resource, network.foulingSpans[span] != nil else { return nil }
                return span
            }
            if track.reserved.isOrdered {
                for resource in track.reservation[..<track.reserved.nodeCount] {
                    owners[resource, default: []].append(place)
                }
                for edge in track.reserved.runs.edges {
                    runs[edge, default: []].append(place)
                    for span in foulingByEdge[edge] ?? [] where track.reserved.contains(.span(span)) {
                        foulingHeld.append(span)
                    }
                }
            } else {
                unordered.append(place)
                for resource in Set(track.reservation) {
                    owners[resource, default: []].append(place)
                    if case .span(let span) = resource, network.foulingSpans[span] != nil { foulingHeld.append(span) }
                }
            }
            fouling.append(foulingHeld)
        }
        var holders = TrackHolders(
            ids: trains.map(\.id), held: held, claims: [:], tracks: tracks, fouling: fouling, owners: owners, runs: runs, foulingByEdge: foulingByEdge,
            bodies: bodies, unordered: unordered
        )
        var claims: [TrainID: Claim] = [:]
        for (train, authority) in zip(trains, authorities) {
            // A following train's route envelope (see ``routeEnvelope(of:)``)
            // is the base and the track of every stretch; it waits for
            // the track of its route no other placed train holds.
            guard let envelopes = authority?.envelopes else { continue }
            var claim = Claim(train: train.id, cover: cover(of: bodyStretches(of: train) + envelopes.stretches))
            if !network.foulingSpans.isEmpty {
                for edge in claim.cover.edges {
                    for span in foulingByEdge[edge] ?? [] where holders.waits(claim, for: .span(span)) {
                        claim.foulingWaiting.append(span)
                    }
                }
            }
            claims[train.id] = claim
        }
        holders = TrackHolders(
            ids: holders.ids, held: held, claims: claims, tracks: tracks, fouling: fouling, owners: owners, runs: runs, foulingByEdge: foulingByEdge,
            bodies: bodies, unordered: unordered
        )
        return holders
    }

    /// ``holder(of:except:)`` of the track `cover` covers (see
    /// ``TrackCover``), from `holders`, the world's.
    func holder(of cover: TrackCover, except id: TrainID, holders: TrackHolders) -> TrainID? {
        holders.firstHolder(of: cover, except: id, in: network)
    }

    /// ``holder(of:except:)`` from `holders`, the world's (see
    /// ``trackHolders()``): of the trains that hold any of `resources`,
    /// foul them or wait for them, the first.
    func holder(of resources: Set<TrackResource>, except id: TrainID, holders: TrackHolders) -> TrainID? {
        var first = holders.ids.count
        for resource in resources {
            if let place = holders.firstHolder(of: resource, except: id, below: first) { first = place }
        }
        // Track a placed train holds that fouls any of them.
        for place in 0..<first where holders.ids[place] != id && holders.tracks[place] != nil {
            if holders.fouling[place].contains(where: { network.foulingSpans[$0]!.contains { resources.contains(.span($0)) } }) {
                first = place
                break
            }
        }
        // Track a following train waits for.
        for place in 0..<first where holders.ids[place] != id && holders.tracks[place] != nil {
            guard let claim = holders.claims[holders.ids[place]], !holders.holdsAny(of: claim, id) else { continue }
            if holders.waits(claim, forAnyOf: resources, in: network) {
                first = place
                break
            }
        }
        return first < holders.ids.count ? holders.ids[first] : nil
    }

    /// ``blockedTrack(except:)``, to ask a resource at a time: what the
    /// placed trains other than `id` (of `among`, if given) hold, and what
    /// those that follow trains ahead wait for, unless train `id` holds
    /// track of their route.
    struct BlockedTrack {
        fileprivate let holders: TrackHolders
        fileprivate let id: TrainID
        fileprivate let among: Set<TrainID>?
        fileprivate let waiting: [Claim]

        func contains(_ resource: TrackResource) -> Bool {
            holders.isHeld(resource, except: id, among: among) || waiting.contains { holders.waits($0, for: resource) }
        }

        /// Whether no train keeps it from anything (asking nothing then is
        /// only quicker: every answer would be no).
        var isEmpty: Bool {
            waiting.isEmpty && !holders.ids.indices.contains { place in
                holders.tracks[place] != nil && holders.ids[place] != id && among?.contains(holders.ids[place]) != false
            }
        }

        /// Whether any of the track `cover` covers is blocked, or fouls
        /// track that is (see ``RailwayNetwork/fouls(_:_:)``).
        func blocks(_ cover: TrackCover, in network: RailwayNetwork) -> Bool {
            if holders.firstHolding(cover, except: id, among: among, fouling: false, in: network) != nil { return true }
            if waiting.contains(where: { holders.waits($0, forAnyIn: cover) }) { return true }
            // Its spans that foul others'.
            for edge in cover.edges {
                for span in holders.foulingByEdge[edge] ?? [] where cover.contains(.span(span)) {
                    if network.foulingSpans[span]!.contains(where: { contains(.span($0)) }) { return true }
                }
            }
            return false
        }

        /// All of it, gathered (see ``blockedTrack(except:)``).
        var resources: Set<TrackResource> {
            var resources: Set<TrackResource> = []
            for place in holders.ids.indices where holders.ids[place] != id && among?.contains(holders.ids[place]) != false {
                guard let track = holders.tracks[place] else { continue }
                resources.formUnion(track.body)
                resources.formUnion(track.reservation)
            }
            for claim in waiting {
                resources.formUnion(holders.waiting(of: claim.train)!)
            }
            return resources
        }
    }

    /// ``blockedTrack(except:)`` from `holders`, the world's (see
    /// ``trackHolders()``), of the trains `among` when given.
    func blockedTrack(except id: TrainID, among: Set<TrainID>? = nil, holders: TrackHolders) -> BlockedTrack {
        var waiting: [Claim] = []
        for (place, other) in holders.ids.enumerated() where other != id && holders.tracks[place] != nil && among?.contains(other) != false {
            if let claim = holders.claims[other], !holders.holdsAny(of: claim, id) {
                waiting.append(claim)
            }
        }
        return BlockedTrack(holders: holders, id: id, among: among, waiting: waiting)
    }

    /// The track `train` holds: what it stands on, the junctions its body
    /// fouls, and its reservation.
    func held(_ train: Train) -> Set<TrackResource> {
        // What it stands on (see ``occupied(_:)``) is what its body covers.
        let body = bodyStretches(of: train)
        var resources = Set(self.resources(covering: body))
        resources.formUnion(foulingNodes(covering: body))
        resources.formUnion(train.reservation)
        return resources
    }

    /// The track `train` needs for the rest of its route: everything its
    /// whole length covers from where its tail is now to where the route
    /// ends (what it stands on, and what its head passes over on the way;
    /// see ``routeStretches(of:)``), and every junction that stretch comes
    /// close enough to foul. `moves` is whether the route has any distance
    /// left, so that the train needs a reservation at all; a train that
    /// stands needs only its place. The resources are those of every moment
    /// of the journey together, by the same rule as occupancy.
    func routeEnvelope(of train: Train) -> (resources: Set<TrackResource>, moves: Bool) {
        guard train.position != nil else { return ([], false) }
        let body = bodyStretches(of: train)
        let route = routeStretches(of: train)
        var resources = Set(self.resources(covering: body))
        resources.formUnion(self.resources(covering: route.stretches))
        resources.formUnion(foulingNodes(covering: body + route.stretches))
        return (resources, route.moves)
    }

    /// The stretches `train`'s head still covers by itself, in order, and
    /// whether there is any distance in them: its route (see
    /// ``pathAhead(of:)``) as far as it can ever follow it: the rest of its
    /// edge, then the edges ahead it can enter, the last up to where the path
    /// ends (``TrainMovement/end``) or, with no path, or a path broken by a
    /// removed edge, to the end of the last edge it reaches: an edge that was
    /// removed never comes back.
    func routeStretches(of train: Train) -> (stretches: [TrackStretch], moves: Bool) {
        guard let position = train.position else { return ([], false) }
        let ahead = pathAhead(of: train)
        switch position {
        case .onEdge(let traversal, let offset):
            guard let length = network.edge(traversal.edge)?.length else { return ([], false) }
            // The path's own end holds only when the train can follow the
            // path to its last edge.
            let followed = ahead.count == train.movement.remainingEdges.count
            let lastStop = { (edgeLength: Int64) in followed ? (train.movement.end ?? edgeLength) : edgeLength }
            guard let last = ahead.last else {
                let stop = lastStop(length)
                return ([TrackStretch(traversal: traversal, from: offset, to: max(offset, stop))], stop > offset)
            }
            var stretches = [TrackStretch(traversal: traversal, from: offset, to: length)]
            for next in ahead.dropLast() {
                stretches.append(TrackStretch(traversal: next, from: 0, to: network.edge(next.edge)!.length))
            }
            stretches.append(TrackStretch(traversal: last, from: 0, to: lastStop(network.edge(last.edge)!.length)))
            return (stretches, true)
        }
    }

    /// The stretches a train covers from its head back to its tail: the
    /// head's edge, then its body's, nearest first. Empty for an unplaced
    /// train.
    func bodyStretches(of train: Train) -> [TrackStretch] {
        guard case .onEdge(let traversal, let offset)? = train.position, network.edge(traversal.edge) != nil else { return [] }
        var stretches = [TrackStretch(traversal: traversal, from: max(0, offset - train.length), to: offset)]
        var remaining = train.length - offset
        for behind in trailTraversals(behind: traversal, trail: train.trailEdges) ?? [] where remaining > 0 {
            let length = network.edge(behind.edge)!.length
            stretches.append(TrackStretch(traversal: behind, from: max(0, length - remaining), to: length))
            remaining -= length
        }
        return stretches
    }

    // MARK: - Following (Stage U2)

    /// How far short of the track the trains ahead hold a following train's
    /// authority ends (Stage U2): 25,600 units, 400 m, the Railway
    /// reference's `BLOCK_GAP_KM` (`index.html`), the distance it keeps a
    /// following train behind the one ahead on the same line.
    public static let followingGap: Int64 = 25_600

    /// The track `train` needs to go on `distance` along its route from
    /// where its head is (see ``routeStretches(of:)``): what it stands on,
    /// what its head passes over in that distance, and every junction all
    /// that comes close enough to foul. The whole route's is its route
    /// envelope (see ``routeEnvelope(of:)``).
    func authorityEnvelope(of train: Train, to distance: Int64) -> Set<TrackResource> {
        authorityEnvelope(authorityEnvelopes(of: train), to: distance)
    }

    /// ``authorityEnvelope(of:to:)`` of one train, to be asked at many
    /// distances: what does not depend on the distance is worked out once.
    /// The envelope to a distance is the base, the track of the stretches
    /// before the one it ends in whole (what each covers and the junctions
    /// it fouls), and that one as far as it goes.
    struct AuthorityEnvelopes {
        /// The train's route stretches (see ``routeStretches(of:)``).
        let stretches: [TrackStretch]
        /// How far from the head each stretch ends (saturating).
        let ends: [Int64]
        /// What the train stands on and the junctions its body fouls (a
        /// resource may be listed twice).
        let base: [TrackResource]

        /// The length of the route (see ``GameWorld/routeLength(of:)``).
        var length: Int64 { ends.last ?? 0 }
    }

    func authorityEnvelopes(of train: Train) -> AuthorityEnvelopes {
        authorityEnvelopes(of: train, along: routeStretches(of: train).stretches)
    }

    /// ``authorityEnvelopes(of:)`` with `train`'s route stretches already
    /// worked out.
    private func authorityEnvelopes(of train: Train, along stretches: [TrackStretch]) -> AuthorityEnvelopes {
        let body = bodyStretches(of: train)
        let base = resources(covering: body) + foulingNodes(covering: body)
        var ends: [Int64] = []
        var end: Int64 = 0
        for stretch in stretches {
            let (sum, overflow) = end.addingReportingOverflow(stretch.to - stretch.from)
            end = overflow ? .max : sum
            ends.append(end)
        }
        return AuthorityEnvelopes(stretches: stretches, ends: ends, base: base)
    }

    /// The stretch the envelope to `distance` ends in (see
    /// ``authorityEnvelope(_:to:)``), its index, and how far into it the
    /// envelope goes: the first stretch always, even for no distance.
    /// - Precondition: `envelopes` has a stretch.
    private func authorityEnd(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> (index: Int, part: TrackStretch) {
        let index = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
        let stretch = envelopes.stretches[index]
        let start = index == 0 ? 0 : envelopes.ends[index - 1]
        let length = min(stretch.to - stretch.from, max(distance - start, 0))
        return (index, TrackStretch(traversal: stretch.traversal, from: stretch.from, to: stretch.from + length))
    }

    /// ``authorityEnvelope(of:to:)`` from `envelopes`: the stretches before
    /// the one `distance` ends in whole, and that one as far as it goes
    /// (the first always, even for no distance).
    func authorityEnvelope(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> Set<TrackResource> {
        var resources = Set(envelopes.base)
        guard !envelopes.stretches.isEmpty else { return resources }
        let end = authorityEnd(envelopes, to: distance)
        let stretches = Array(envelopes.stretches[..<end.index]) + [end.part]
        resources.formUnion(self.resources(covering: stretches))
        resources.formUnion(foulingNodes(covering: stretches))
        return resources
    }

    /// Whether the envelope to `distance` (see ``authorityEnvelope(_:to:)``)
    /// is clear, as ``longestAuthority(_:from:clearBase:clear:)`` asks it.
    func isAuthority(_ envelopes: AuthorityEnvelopes, to distance: Int64, clearBase: Bool, clear: (TrackStretch) -> Bool) -> Bool {
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        return envelopes.stretches[..<end.index].allSatisfy(clear) && clear(end.part)
    }

    /// ``isAuthority(_:to:clearBase:clear:)``, knowing how many of the first
    /// stretches are clear whole.
    private func isAuthority(
        _ envelopes: AuthorityEnvelopes, to distance: Int64, clear: (TrackStretch) -> Bool, clearBase: Bool, leading: Int
    ) -> Bool {
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        guard end.index <= leading else { return false }
        return clear(end.part)
    }

    /// The longest distance from `low` to the end of the route whose
    /// envelope (see ``authorityEnvelope(_:to:)``) is clear, found by
    /// halving: `low` when no longer one is. `clearBase` is whether the
    /// base is clear, and `clear` whether the track of a stretch is (what
    /// it covers and the junctions it fouls). Being clear must hold of a set
    /// of track exactly when it holds of each part of it (as "held by the
    /// reservation" and "fouling nothing blocked" do), so each envelope is
    /// tried a part at a time (the base, the whole stretches before its
    /// end, and the part of the last), and never gathered.
    func longestAuthority(_ envelopes: AuthorityEnvelopes, from low: Int64, clearBase: Bool, clear: (TrackStretch) -> Bool) -> Int64 {
        // The stretches from the first that are clear whole.
        var leading = 0
        while clearBase, leading < envelopes.stretches.count, clear(envelopes.stretches[leading]) {
            leading += 1
        }
        var (low, high) = (low, envelopes.length)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if isAuthority(envelopes, to: middle, clear: clear, clearBase: clearBase, leading: leading) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// Whether `reservation` holds all the track of `stretch` (see
    /// ``resources(covering:)`` and ``foulingNodes(covering:)``), asked of
    /// the stretch on its edge rather than of each of its spans listed.
    func reserves(_ reservation: ReservedTrack, all stretch: TrackStretch) -> Bool {
        guard let edge = stretchFacts(of: stretch.traversal.edge) else { return true }
        let forward = stretch.traversal.direction == .forward
        if stretch.from == 0, !reservation.contains(.node(forward ? edge.from : edge.to)) { return false }
        if stretch.to == edge.length, !reservation.contains(.node(forward ? edge.to : edge.from)) { return false }
        guard foulingNodes(covering: [stretch]).allSatisfy(reservation.contains) else { return false }
        let (low, high) = forward ? (stretch.from, stretch.to) : (edge.length - stretch.to, edge.length - stretch.from)
        return reservation.containsAll(edge.spans, from: low, to: high, length: edge.length)
    }

    /// The reservation-held test of a stretch for a following train (see
    /// ``authority(of:)``) and the blocked test for one that would take
    /// more (see ``blockedTrack(except:)``): each asks a stretch whole.
    func clearOfBlocked(_ blocked: BlockedTrack) -> (base: ([TrackResource]) -> Bool, stretch: (TrackStretch) -> Bool) {
        ({ !network.fouls($0, blocked.contains) }, { !blocked.blocks(cover(of: [$0]), in: network) })
    }

    /// How far along its route `train` has world units of its route
    /// envelope's length (see ``routeStretches(of:)``).
    func routeLength(of train: Train) -> Int64 {
        var left: Int64 = 0
        for stretch in routeStretches(of: train).stretches {
            let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
            left = overflow ? .max : sum
        }
        return left
    }

    /// How far `train`'s head may go on along its route under traffic
    /// control (its movement authority, Stage U2), or `nil` when it may go
    /// all the way: its reservation holds its whole route envelope, or
    /// traffic control is off, or it has no route. A train that follows
    /// another holds its route only part of the way: as far as the track
    /// its reservation holds it to (see ``authorityEnvelope(of:to:)``).
    /// Derived from the reservation, never saved.
    func authorityLeft(of train: Train) -> Int64? {
        authority(of: train)?.left
    }

    /// ``authorityLeft(of:)`` of a train that follows another, with the
    /// envelopes it was found from (see ``authorityEnvelopes(of:)``); `nil`
    /// for any other train.
    func authority(of train: Train) -> (left: Int64, envelopes: AuthorityEnvelopes)? {
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        let reservation = ReservedTrack(train.reservation)
        let route = routeStretches(of: train)
        // A reservation that holds where the route ends holds all of it: a
        // following train's ends at least ``followingGap`` short of that.
        guard let last = route.stretches.last,
              !resources(covering: [TrackStretch(traversal: last.traversal, from: last.to, to: last.to)]).allSatisfy(reservation.contains),
              route.moves
        else { return nil }
        // Its route envelope (see ``routeEnvelope(of:)``) is the base and
        // the track of every stretch together: a reservation holding all of
        // them holds the whole route.
        let envelopes = authorityEnvelopes(of: train, along: route.stretches)
        let holdsBase = envelopes.base.allSatisfy(reservation.contains)
        let holds = { (stretch: TrackStretch) in reserves(reservation, all: stretch) }
        guard !holdsBase || !envelopes.stretches.allSatisfy(holds) else { return nil }
        // The longest distance whose track the reservation holds.
        return (longestAuthority(envelopes, from: 0, clearBase: holdsBase, clear: holds), envelopes)
    }

    /// Whether `train` follows another (Stage U2): under traffic control
    /// its reservation holds its route only part of the way. Only a
    /// service's departure takes a route part of the way, but a train
    /// whose service is stopped on the way keeps its path and its
    /// reservation, and so goes on following.
    func isFollowing(_ train: Train) -> Bool {
        authorityLeft(of: train) != nil
    }

    /// ``authority(of:)`` kept in `memo`, by the train as it is: it depends
    /// on nothing else but the network and traffic control, which do not
    /// change within one memo. A few of each train's last values are kept
    /// (the steps of an advance ask of the trains as they would have moved
    /// on, between questions of the trains as they are).
    func authority(of train: Train, memo: inout DirectionMemo) -> (left: Int64, envelopes: AuthorityEnvelopes)? {
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        if let known = memo.authorities[train.id]?.first(where: { $0.train == train }) { return known.authority }
        let authority = authority(of: train)
        var known = memo.authorities[train.id] ?? []
        known.insert((train, authority), at: 0)
        if known.count > 4 { known.removeLast() }
        memo.authorities[train.id] = known
        return authority
    }

    /// ``isFollowing(_:)`` kept in `memo` (see ``authority(of:memo:)``).
    func isFollowing(_ train: Train, memo: inout DirectionMemo) -> Bool {
        authority(of: train, memo: &memo) != nil
    }

    /// What following `train` (Stage U2) still needs and does not hold:
    /// `route` is its whole route envelope, `waiting` the part of it no
    /// train holds (see ``held(_:)``). No other train may take track it
    /// waits for, unless that train holds track of its route itself: one
    /// of the trains ahead, which it follows. `nil` for a train that does
    /// not follow another.
    func claim(of train: Train) -> (route: Set<TrackResource>, waiting: Set<TrackResource>)? {
        guard isFollowing(train) else { return nil }
        let route = routeEnvelope(of: train).resources
        var waiting = route
        for other in trains where other.id != train.id && other.position != nil {
            waiting.subtract(held(other))
        }
        return (route, waiting)
    }

    /// `candidate`, a service about to set off along a route other trains
    /// hold some of, following them (Stage U2): with a reservation of its
    /// route as far as ``followingGap`` short of the first track another
    /// train holds (see ``holder(of:except:)``), or `nil` if it may not
    /// follow them, or that leaves it no way to go.
    ///
    /// It may follow only trains it can be sure leave its route, or go on
    /// from it without turning back: every train that holds track of its
    /// `route` (or fouls it, or waits for it) must be a service travelling
    /// to a call with its whole route held (it waits for nobody), and the
    /// call it travels to is off `route`, or it goes on from there to a
    /// call after it without turning round. A train standing, turning
    /// round, ending its service or following another itself, it waits for
    /// whole, as before.
    ///
    /// `route` is asked a resource at a time (see ``TrackCover``), and
    /// `memo` keeps the trains' holders.
    func followingAuthority(of candidate: Train, route: TrackCover, memo: inout DirectionMemo) -> Train? {
        let holders = trackHolders(memo: &memo)
        for other in trains where other.id != candidate.id && other.position != nil {
            guard holder(of: route, except: candidate.id, among: other, holders: holders) else { continue }
            guard isLeading(other, onto: route, for: candidate) else { return nil }
        }
        // The longest distance whose track no other train holds.
        let blocked = blockedTrack(except: candidate.id, holders: holders)
        let envelopes = authorityEnvelopes(of: candidate)
        let clear = clearOfBlocked(blocked)
        let free = longestAuthority(envelopes, from: 0, clearBase: clear.base(envelopes.base), clear: clear.stretch)
        let authority = free - Self.followingGap
        guard authority >= 1 else { return nil }
        var train = candidate
        train.reservation = authorityEnvelope(envelopes, to: authority).sorted()
        return train
    }

    /// Whether train `other` holds, fouls or waits for any of `resources`,
    /// as ``holder(of:except:)`` asks of each train for train `id`.
    private func holder(of route: TrackCover, except id: TrainID, among other: Train, holders: TrackHolders) -> Bool {
        // What it holds, by the edges the route lies on, or that fouls it.
        if holders.firstHolding(route, except: id, among: [other.id], fouling: true, in: network) != nil { return true }
        guard let claim = holders.claims[other.id], !holders.holdsAny(of: claim, id) else { return false }
        return holders.waits(claim, forAnyIn: route)
            || claim.foulingWaiting.contains { network.foulingSpans[$0]!.contains { route.contains(.span($0)) } }
    }

    /// Whether `train` leads the way along `route`, the route envelope of
    /// `follower`, a train that would follow it (see
    /// ``followingAuthority(of:route:memo:)``). A train that runs along any edge
    /// of the follower's way the other way round comes towards it and is
    /// never followed.
    func isLeading(_ train: Train, onto route: TrackCover, for follower: Train) -> Bool {
        guard case .travellingToStop(let stop, let cycle)? = train.execution, train.movement.rate > 0,
              routeEnvelope(of: train).moves, !isFollowing(train)
        else { return false }
        let ways = Set((bodyStretches(of: follower) + routeStretches(of: follower).stretches).map(\.traversal))
        for stretch in bodyStretches(of: train) + routeStretches(of: train).stretches where ways.contains(stretch.traversal.reversed) {
            return false
        }
        // Where it stops for its call.
        var arrived = train
        let end = travelling(arrived, distance: routeLength(of: train))
        arrived.position = end.position
        arrived.movement.cursor = end.cursor
        var standing = Set(occupied(arrived))
        standing.formUnion(foulingNodes(covering: bodyStretches(of: arrived)))
        guard !standing.contains(where: route.contains) else {
            return !train.timetable[stop].reverses && train.call(after: stop, cycle: cycle) != nil
        }
        return true
    }

    // MARK: - The resources of a stretch

    /// The end nodes, length and resource spans of edge `id`, from its
    /// `from` node, or `nil` if it does not exist.
    private func stretchFacts(of id: TrackEdgeID) -> (from: TrackNodeID, to: TrackNodeID, length: Int64, spans: [TrackSpan])? {
        guard let edge = network.edge(id) else { return nil }
        return (edge.from, edge.to, edge.length, network.spans(of: id, length: edge.length))
    }

    /// The track `stretches` cover (see ``resources(covering:)`` and
    /// ``foulingNodes(covering:)``), kept as the stretches are: by edge,
    /// the parts of its chainage they cover. Whether a resource is of it is
    /// asked of the stretches on its edge by the same rule, and never by
    /// listing the spans: a stretch of a long leg covers thousands.
    struct TrackCover {
        /// The nodes it covers: where stretches reach an end of their edge,
        /// and the junctions they foul.
        fileprivate let nodes: Set<TrackResource>
        /// For each edge a stretch lies on: its length, its spans, and the
        /// stretches in its own chainage, from its `from` node.
        fileprivate let parts: EdgeTable<(length: Int64, spans: [TrackSpan], windows: [(low: Int64, high: Int64)])>

        /// The edges it lies on, in order.
        var edges: [TrackEdgeID] {
            parts.edges
        }

        /// Whether a span shares a point with a stretch from `low` to
        /// `high` lying strictly between the edge's ends (the rule of
        /// ``resources(covering:)``).
        static func covers(_ low: Int64, _ high: Int64, _ span: TrackSpan, length: Int64) -> Bool {
            let a = max(low, span.start)
            let b = min(high, span.end)
            return a < b || (a == b && a > 0 && a < length)
        }

        func contains(_ resource: TrackResource) -> Bool {
            switch resource {
            case .node:
                return nodes.contains(resource)
            case .span(let span):
                guard let part = parts[span.edge],
                      part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) })
                else { return false }
                // One of the edge's own spans, found by halving.
                var (low, high) = (0, part.spans.count)
                while low < high {
                    let middle = (low + high) / 2
                    if part.spans[middle] < span {
                        low = middle + 1
                    } else {
                        high = middle
                    }
                }
                return low < part.spans.count && part.spans[low] == span
            }
        }

        /// The least and most chainage of edge `edge` it covers, or `nil`.
        func bounds(on edge: TrackEdgeID) -> (low: Int64, high: Int64)? {
            guard let part = parts[edge] else { return nil }
            return (part.windows.map(\.low).min()!, part.windows.map(\.high).max()!)
        }

        /// Calls `each` with every span of edge `edge` it covers, in order,
        /// that starts at `high` or before and ends at `low` or after, until
        /// it returns `true`; returns whether it did.
        func anySpan(of edge: TrackEdgeID, from low: Int64, to high: Int64, where each: (TrackSpan) -> Bool) -> Bool {
            guard let part = parts[edge] else { return false }
            // The edge's spans are in order and end in order.
            var (lower, upper) = (0, part.spans.count)
            while lower < upper {
                let middle = (lower + upper) / 2
                if part.spans[middle].end < low {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            for span in part.spans[lower...] {
                guard span.start <= high else { break }
                if part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) }), each(span) { return true }
            }
            return false
        }

        /// Everything it covers, listed (as ``resources(covering:)`` and
        /// ``foulingNodes(covering:)`` list it, some perhaps twice).
        var resources: [TrackResource] {
            var resources = Array(nodes)
            for part in parts.allValues {
                for span in part.spans where part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) }) {
                    resources.append(.span(span))
                }
            }
            return resources
        }
    }

    /// `train`'s route envelope (see ``routeEnvelope(of:)``), asked a
    /// resource at a time.
    func envelopeCover(of train: Train) -> TrackCover {
        cover(of: bodyStretches(of: train) + routeStretches(of: train).stretches)
    }

    /// See ``TrackCover``.
    func cover(of stretches: [TrackStretch]) -> TrackCover {
        var nodes = Set(foulingNodes(covering: stretches))
        var parts: [TrackEdgeID: (length: Int64, spans: [TrackSpan], windows: [(low: Int64, high: Int64)])] = [:]
        for stretch in stretches {
            guard let edge = stretchFacts(of: stretch.traversal.edge) else { continue }
            let forward = stretch.traversal.direction == .forward
            if stretch.from == 0 { nodes.insert(.node(forward ? edge.from : edge.to)) }
            if stretch.to == edge.length { nodes.insert(.node(forward ? edge.to : edge.from)) }
            let window = forward ? (low: stretch.from, high: stretch.to) : (low: edge.length - stretch.to, high: edge.length - stretch.from)
            if parts[stretch.traversal.edge] == nil {
                parts[stretch.traversal.edge] = (edge.length, edge.spans, [window])
            } else {
                parts[stretch.traversal.edge]!.windows.append(window)
            }
        }
        return TrackCover(nodes: nodes, parts: EdgeTable(parts))
    }

    /// The track `stretches` cover, the one rule for occupancy and
    /// reservation alike (Stage S3A; ARCHITECTURE decision 32): every node a
    /// stretch reaches, and every span that shares a point with a stretch
    /// lying strictly between the edge's ends, so a train touching the
    /// boundary between two spans holds both. The rule is point by point,
    /// so the track of two stretches that meet is the track of the two
    /// together.
    func resources(covering stretches: [TrackStretch]) -> [TrackResource] {
        var resources: [TrackResource] = []
        for stretch in stretches {
            guard let edge = stretchFacts(of: stretch.traversal.edge) else { continue }
            let forward = stretch.traversal.direction == .forward
            if stretch.from == 0 { resources.append(.node(forward ? edge.from : edge.to)) }
            if stretch.to == edge.length { resources.append(.node(forward ? edge.to : edge.from)) }
            // The stretch in the edge's own chainage, from its `from` node.
            let (low, high) = forward ? (stretch.from, stretch.to) : (edge.length - stretch.to, edge.length - stretch.from)
            for span in edge.spans {
                let a = max(low, span.start)
                let b = min(high, span.end)
                // Some point of both, strictly between the edge's ends.
                if a < b || (a == b && a > 0 && a < edge.length) { resources.append(.span(span)) }
            }
        }
        return resources
    }

    /// The junctions of the track network `stretches` come close enough to
    /// foul (ARCHITECTURE decision 32, point 5): the node at an end of a
    /// stretch's edge when some point of the stretch lies less than
    /// ``RailwayNetwork/junctionZone`` from it along the edge, and the
    /// edge's end there is a fouling end (see ``isFoulingEnd(of:at:)``).
    /// Within that distance of a node two edges that end there may lie side
    /// by side (Stage S4 does not check their clearance there), so a train
    /// there takes the node as well.
    func foulingNodes(covering stretches: [TrackStretch]) -> [TrackResource] {
        var nodes: [TrackResource] = []
        for stretch in stretches {
            guard let edge = network.edge(stretch.traversal.edge) else { continue }
            let (low, high) = stretch.traversal.direction == .forward
                ? (stretch.from, stretch.to)
                : (edge.length - stretch.to, edge.length - stretch.from)
            if low < RailwayNetwork.junctionZone, isFoulingEnd(of: edge.id, at: edge.from) { nodes.append(.node(edge.from)) }
            if edge.length - high < RailwayNetwork.junctionZone, isFoulingEnd(of: edge.id, at: edge.to) { nodes.append(.node(edge.to)) }
        }
        return nodes
    }

    /// Whether a train holding `resource` holds track at or within
    /// ``RailwayNetwork/junctionZone`` of node `node` of the track network:
    /// the node itself, or a span of an edge ending there that reaches
    /// closer to it than that. Such track is where a new edge at the node
    /// could change who fouls the junction.
    func isWithinJunctionZone(_ resource: TrackResource, of node: TrackNodeID) -> Bool {
        switch resource {
        case .node(let held):
            return held == node
        case .span(let span):
            guard let edge = network.edge(span.edge) else { return false }
            return (edge.from == node && span.start < RailwayNetwork.junctionZone)
                || (edge.to == node && edge.length - span.end < RailwayNetwork.junctionZone)
        }
    }

    /// Whether edge `edge`'s end at node `node` is a fouling end: another
    /// edge ends there that it does not join (they do not leave the node in
    /// opposite directions), as a turnout's branches, a crossing's lines or
    /// two edges meeting at an angle do. A plain node, a dead end and a
    /// turnout's stem are not.
    func isFoulingEnd(of edge: TrackEdgeID, at node: TrackNodeID) -> Bool {
        guard let junction = network.node(node), let end = junction.end(of: edge) else { return false }
        return junction.ends.contains { $0.edge != edge && !end.exits.contains($0.edge) }
    }
}

/// A few values by edge, in edge order, found by halving: asked of every
/// resource of a route, where hashing the edge took much of the time.
struct EdgeTable<Value> {
    /// The edges, in order.
    private(set) var edges: [TrackEdgeID] = []
    private var values: [Value] = []

    init() {}

    init(_ dictionary: [TrackEdgeID: Value]) {
        edges = dictionary.keys.sorted()
        values = edges.map { dictionary[$0]! }
    }

    /// Adds `value` for `edge`, which comes after every edge it has.
    mutating func append(_ edge: TrackEdgeID, _ value: Value) {
        precondition(edges.last.map { $0 < edge } ?? true, "edges are added in order")
        edges.append(edge)
        values.append(value)
    }

    subscript(edge: TrackEdgeID) -> Value? {
        var (low, high) = (0, edges.count)
        while low < high {
            let middle = (low + high) / 2
            if edges[middle] < edge {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < edges.count && edges[low] == edge ? values[low] : nil
    }

    /// Every value, in edge order.
    var allValues: [Value] { values }
}

extension TrackResource {
    /// Whether this is a span of edge `edge`.
    func isSpan(of edge: TrackEdgeID) -> Bool {
        if case .span(let span) = self { span.edge == edge } else { false }
    }
}

extension RailwayNetwork {
    /// ``fouls(_:_:)`` with `b` asked a resource at a time.
    func fouls(_ a: Set<TrackResource>, _ b: (TrackResource) -> Bool) -> Bool {
        for resource in a {
            if b(resource) { return true }
            guard case .span(let x) = resource, let partners = foulingSpans[x] else { continue }
            if partners.contains(where: { b(.span($0)) }) { return true }
        }
        return false
    }
}
