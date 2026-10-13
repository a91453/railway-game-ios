import Foundation
@testable import GameCore
import XCTest

/// Route reservation made faster for long legs (NEXT_PRIORITIES 2026-10-12
/// §2 item 6, speed-ups only), shown to answer exactly as the long way it
/// replaced, which is kept here as it was (main 77dc286):
///
/// - who holds track a train needs (`holder(of:except:)`), the track the
///   other trains keep a train from (`blockedTrack(except:)`, and among
///   some of them for a deadlock, `blockedTrack(except:among:)`) and what a
///   following train waits for (its claim), from the trains' holders worked
///   out once (`trackHolders`) rather than every train's track gathered
///   again for every question;
/// - the holders and the trains' movement authorities kept in a memo while
///   the trains stay as they are, and worked out again once one changes.
///
/// The worlds asked about are the states of the long-leg replay
/// (`ReplayFixtures/long-leg-traffic.json`: long legs, following, head-on
/// meets and a deadlock), of the traffic-control campaign's layouts
/// (junctions, crossings, flyovers, fouling tracks, trains off the track,
/// traffic control off) and of the following campaign's long line. One memo is carried through the states of a
/// sequence while its network stays the same, as within an advance, so a
/// memo that kept an answer for trains that have changed is caught.
final class ReservationShortcutTests: XCTestCase {
    /// Every state of the long-leg replay, command by command, with the
    /// trains of each as they are half way through its advance too.
    private func longLegStates() throws -> [GameWorld] {
        var world = try LongLegReplayTests.world()
        var states = [world]
        for operation in LongLegReplayTests.operations() {
            if case .advance(let ticks) = operation, ticks > 1 {
                var half = world
                _ = KernelDifferentialTests.apply(.advance(ticks / 2), to: &half)
                states.append(half)
            }
            _ = KernelDifferentialTests.apply(operation, to: &world)
            states.append(world)
        }
        return states
    }

    /// States of the traffic-control campaign's layouts: each case's world
    /// after every one of its first operations.
    private func campaignStates(cases: Int, operations: Int) throws -> [[GameWorld]] {
        var sequences: [[GameWorld]] = []
        for index in 0..<cases {
            var testCase = PropertyCase(suite: "traffic.shortcuts", seed: 0x5EED_A001, index: index)
            var states: [GameWorld] = []
            var world = try TrafficControlPropertyTests.generateWorld(&testCase, operations: 0)
            states.append(world)
            for _ in 0..<operations {
                _ = TrafficControlPropertyTests.apply(TrafficControlPropertyTests.operation(in: world, using: &testCase.random), to: &world)
                states.append(world)
            }
            sequences.append(states)
        }
        return sequences
    }

    /// States of the following campaign's long line (`traffic.following`,
    /// Stage U2): trains setting off behind others and following them,
    /// each case's world after every one of its first operations.
    private func followingStates(cases: Int, operations: Int) throws -> [[GameWorld]] {
        var sequences: [[GameWorld]] = []
        for index in 0..<cases {
            var testCase = PropertyCase(suite: "traffic.shortcutsFollowing", seed: 0x5EED_A001, index: index)
            var world = try TrafficControlPropertyTests.beginFollowing(&testCase).world
            var states = [world]
            for _ in 0..<operations {
                _ = TrafficControlPropertyTests.apply(TrafficControlPropertyTests.followingOperation(in: world, using: &testCase.random), to: &world)
                states.append(world)
            }
            sequences.append(states)
        }
        return sequences
    }

    /// The track asked about in `world`, as stretches: each train's route
    /// envelope and its body, each platform, each edge whole either way,
    /// and every node (a stretch of no length at each end of each edge).
    private func questions(in world: GameWorld, edges: Bool) -> [[TrackStretch]] {
        var asked: [[TrackStretch]] = []
        for train in world.trains where train.position != nil {
            asked.append(world.bodyStretches(of: train) + world.routeStretches(of: train).stretches)
            asked.append(world.bodyStretches(of: train))
        }
        for platform in world.network.platforms {
            asked.append([TrackStretch(traversal: TrackTraversal(edge: platform.edge, direction: .forward), from: platform.start, to: platform.end)])
        }
        for edge in world.network.edges where edges {
            asked.append([TrackStretch(traversal: TrackTraversal(edge: edge.id, direction: .backward), from: 0, to: edge.length)])
        }
        asked.append(world.network.edges.flatMap { edge in
            [TrackStretch(traversal: TrackTraversal(edge: edge.id, direction: .forward), from: 0, to: 0),
             TrackStretch(traversal: TrackTraversal(edge: edge.id, direction: .forward), from: edge.length, to: edge.length)]
        })
        return asked
    }

    /// Asks `world` everything, with `memo` and without, against the long
    /// way; returns how many answers were compared, or fails.
    @discardableResult
    private func compare(_ world: GameWorld, memo: inout GameWorld.DirectionMemo, edges: Bool = true, paths: Bool = true, _ label: String) -> Int {
        var compared = 0
        let ids = world.trains.map(\.id) + [TrainID(rawValue: 999)]
        let questions = questions(in: world, edges: edges)
        for id in ids {
            let blocked = world.longBlockedTrack(except: id)
            XCTAssertEqual(world.blockedTrack(except: id), blocked, "\(label): blocked for \(id)")
            XCTAssertEqual(world.blockedTrack(except: id, memo: &memo), blocked, "\(label): blocked for \(id), kept")
            let holders = world.trackHolders(memo: &memo)
            for stretches in questions {
                let resources = Set(world.resources(covering: stretches) + world.foulingNodes(covering: stretches))
                let holder = world.longHolder(of: resources, except: id)
                XCTAssertEqual(world.holder(of: resources, except: id), holder, "\(label): holder for \(id)")
                XCTAssertEqual(world.holder(of: resources, except: id, memo: &memo), holder, "\(label): holder for \(id), kept")
                XCTAssertEqual(world.holder(of: world.cover(of: stretches), except: id, holders: holders), holder, "\(label): holder of a cover for \(id)")
                compared += 1
            }
            // Deadlock's question: of the trains with an even ID, and of all.
            for among in [Set(world.trains.map(\.id).filter { $0.rawValue % 2 == 0 }), Set(world.trains.map(\.id))] {
                let long = world.longBlockedTrack(except: id, among: among)
                XCTAssertEqual(world.blockedTrack(except: id, among: among), long, "\(label): blocked among for \(id)")
                XCTAssertEqual(world.blockedTrack(except: id, among: among, memo: &memo), long, "\(label): blocked among for \(id), kept")
                let blocked = world.blockedTrack(except: id, among: among, holders: holders)
                for stretches in questions {
                    let resources = Set(world.resources(covering: stretches) + world.foulingNodes(covering: stretches))
                    XCTAssertEqual(blocked.blocks(world.cover(of: stretches), in: world.network), world.network.fouls(resources, long),
                                   "\(label): \(id) blocked among \(among.map(\.rawValue).sorted())")
                }
                compared += 1
            }
        }
        // The shortest unblocked way of every placed train to every station,
        // avoiding what the others keep it from (decision 57).
        if paths {
            let holders = world.trackHolders(memo: &memo)
            for train in world.trains {
                guard let position = train.position else { continue }
                let blocked = world.blockedTrack(except: train.id, holders: holders)
                let long = world.longBlockedTrack(except: train.id)
                for station in world.stations {
                    XCTAssertEqual(world.path(from: position, toStation: station.id, length: train.length, avoiding: blocked),
                                   world.path(from: position, toStation: station.id, length: train.length, avoiding: long),
                                   "\(label): way of \(train.id) to \(station.id)")
                    compared += 1
                }
            }
        }
        // Each train setting off along its route following the trains
        // ahead (Stage U2), as a departure asks it.
        for train in world.trains where train.position != nil && world.isTrafficControlEnabled {
            XCTAssertEqual(world.followingAuthority(of: train, route: world.envelopeCover(of: train), memo: &memo), world.longFollowingAuthority(of: train),
                           "\(label): \(train.id) following")
            compared += 1
        }
        let holders = world.trackHolders(memo: &memo)
        let fresh = world.trackHolders()
        for train in world.trains {
            let claim = world.longClaim(of: train)
            XCTAssertEqual(holders.claims[train.id]?.route, claim?.route, "\(label): claim route of \(train.id)")
            XCTAssertEqual(holders.waiting(of: train.id), claim?.waiting, "\(label): claim of \(train.id)")
            XCTAssertEqual(fresh.waiting(of: train.id), claim?.waiting, "\(label): claim of \(train.id), fresh")
            for resource in claim?.route ?? [] {
                XCTAssertEqual(holders.waits(holders.claims[train.id]!, for: resource), claim!.waiting.contains(resource), "\(label): \(train.id) waits for \(resource)")
            }
            XCTAssertEqual(Set(holders.held[train.id]!.resources), world.held(train), "\(label): held by \(train.id)")
            let authority = world.authority(of: train)
            let kept = world.authority(of: train, memo: &memo)
            XCTAssertEqual(kept?.left, authority?.left, "\(label): authority of \(train.id)")
            XCTAssertEqual(kept?.envelopes.stretches, authority?.envelopes.stretches, "\(label): envelopes of \(train.id)")
            XCTAssertEqual(kept?.left, world.longAuthorityLeft(of: train), "\(label): authority of \(train.id), the long way")
            XCTAssertEqual(world.isFollowing(train, memo: &memo), world.isFollowing(train), "\(label): following \(train.id)")
            let held = world.heldTrack(train), keptHeld = world.heldTrack(train, memo: &memo)
            XCTAssertEqual(keptHeld.body, held.body, "\(label): body of \(train.id), kept")
            XCTAssertEqual(keptHeld.reservation, held.reservation, "\(label): reservation of \(train.id), kept")
            compared += 1
        }
        compared += compareReservationShortcuts(world, memo: &memo, label)
        return compared
    }

    /// The second round's shortcuts (NEXT_PRIORITIES 2026-10-12 §0 item 4)
    /// against what they replaced: what a train's envelope keeps of a
    /// reservation as it moves on, a following train's reservation as it
    /// takes more of its route, and the paths kept in a memo.
    private func compareReservationShortcuts(_ world: GameWorld, memo: inout GameWorld.DirectionMemo, _ label: String) -> Int {
        var compared = 0
        let placed = world.trains.filter { $0.position != nil }
        for train in placed {
            let cover = world.envelopeCover(of: train)
            // Its own reservation, every other's, and one out of order.
            for other in placed {
                for reservation in [other.reservation, other.reservation.reversed()] {
                    XCTAssertEqual(cover.kept(of: reservation), reservation.filter(cover.contains), "\(label): \(train.id) keeps of \(other.id)'s")
                    compared += 1
                }
            }
            if let (held, envelopes) = world.authority(of: train) {
                let length = envelopes.length
                for distance in Set([held + 1, held + 1_024, held + GameWorld.followingGap, (held + length) / 2, length - 1, length]) where distance > held && distance <= length {
                    XCTAssertEqual(world.reservation(train.reservation, extending: envelopes, from: held, to: distance),
                                   Set(train.reservation).union(world.authorityEnvelope(envelopes, to: distance)).sorted(),
                                   "\(label): \(train.id) extended to \(distance) from \(held)")
                    compared += 1
                }
            }
            for station in world.stations {
                XCTAssertEqual(world.path(from: train.position!, toStation: station.id, length: train.length, memo: &memo.paths),
                               world.path(from: train.position!, toStation: station.id, length: train.length), "\(label): way of \(train.id) to \(station.id), kept")
                compared += 1
            }
        }
        return compared
    }

    func testTheLongLegReplayAnswersAsTheLongWay() throws {
        let states = try longLegStates()
        var memo = GameWorld.DirectionMemo()
        var compared = 0, following = 0, waiting = 0
        // Every third state (the long way takes long on long legs), and
        // every one where a train follows another.
        for (index, world) in states.enumerated() where index % 3 == 0 || world.trains.contains(where: world.isFollowing) {
            compared += compare(world, memo: &memo, edges: false, paths: index % 12 == 0, "long leg \(index)")
            following += world.trains.count { world.isFollowing($0) }
            waiting += world.trains.count { world.longClaim(of: $0)?.waiting.isEmpty == false }
            // A world with one train moved, asked with the same memo in
            // between, as a passing place is tried.
            if index % 6 == 0, let train = world.trains.first(where: { $0.position != nil && $0.movement.rate > 0 }) {
                var moved = train
                moved.position = world.travelling(train, distance: 1_024).position
                compare(world.replacing(moved), memo: &memo, edges: false, paths: false, "long leg \(index), one train moved")
                compare(world, memo: &memo, edges: false, paths: false, "long leg \(index), again")
            }
        }
        XCTAssertGreaterThan(compared, 500)
        XCTAssertGreaterThan(following, 2, "trains follow others")
        XCTAssertGreaterThan(waiting, 0, "following trains wait for track")
    }

    func testFollowingTrainsAnswerAsTheLongWay() throws {
        var compared = 0, following = 0, waiting = 0
        for (index, states) in try followingStates(cases: 16, operations: 30).enumerated() {
            var memo = GameWorld.DirectionMemo()
            var network = states[0].network
            for (step, world) in states.enumerated() {
                if world.network != network {
                    memo = GameWorld.DirectionMemo()
                    network = world.network
                }
                compared += compare(world, memo: &memo, "following case \(index) step \(step)")
                following += world.trains.count { world.isFollowing($0) }
                waiting += world.trains.count { world.longClaim(of: $0)?.waiting.isEmpty == false }
            }
        }
        XCTAssertGreaterThan(compared, 5_000)
        XCTAssertGreaterThan(following, 50, "trains follow others")
        XCTAssertGreaterThan(waiting, 20, "following trains wait for track")
    }

    /// A train setting off from a loop or platform ahead of a train that
    /// follows another, whose way joins the track that one waits for, as
    /// well as from behind: on the long-leg replay's states where a train
    /// follows, a new train put beside each platform it can stand at, setting
    /// off for every other station.
    func testDeparturesBesideFollowingTrainsAnswerAsTheLongWay() throws {
        var compared = 0, joining = 0
        for world in try longLegStates() where world.trains.contains(where: world.isFollowing) {
            for platform in world.network.platforms {
                var placed = world
                let id: TrainID
                do throws(GameError) {
                    id = try placed.purchaseTrain(named: "C").id
                    try placed.setTrainCars(id, to: 4)
                    guard let length = placed.trackEdge(platform.edge)?.length else { continue }
                    let position = TrainPosition.onEdge(TrackTraversal(edge: platform.edge, direction: .forward), offset: platform.end)
                    try placed.placeTrain(id, at: position)
                    try placed.setTrainContinuation(id, along: [], stoppingAt: platform.end < length ? platform.end : nil)
                } catch {
                    continue
                }
                let standing = try XCTUnwrap(placed.train(id: id))
                for station in placed.stations {
                    guard let way = placed.path(from: standing.position!, toStation: station.id, length: standing.length), way.distance > 0 else { continue }
                    var candidate = standing
                    placed.follow(way, &candidate)
                    let holders = placed.trackHolders()
                    let route = placed.envelopeCover(of: candidate)
                    if placed.trains.contains(where: { other in
                        guard let claim = holders.claims[other.id] else { return false }
                        return holders.binds(claim, id) && placed.longClaim(of: other)!.waiting.contains(where: route.contains)
                    }) {
                        joining += 1
                    }
                    var memo = GameWorld.DirectionMemo()
                    XCTAssertEqual(placed.followingAuthority(of: candidate, route: route, memo: &memo), placed.longFollowingAuthority(of: candidate),
                                   "from \(platform) to \(station.id)")
                    XCTAssertEqual(placed.holder(of: route, except: id, holders: holders),
                                   placed.longHolder(of: placed.routeEnvelope(of: candidate).resources, except: id), "holder from \(platform) to \(station.id)")
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 20)
        XCTAssertGreaterThan(joining, 0, "a way joins the track a following train waits for")
    }

    func testCampaignLayoutsAnswerAsTheLongWay() throws {
        var compared = 0, trafficControlled = 0, fouling = 0
        for (index, states) in try campaignStates(cases: 12, operations: 30).enumerated() {
            var memo = GameWorld.DirectionMemo()
            var network = states[0].network
            for (step, world) in states.enumerated() {
                // A memo lives while the network stays as it is (one
                // advance, or one question).
                if world.network != network {
                    memo = GameWorld.DirectionMemo()
                    network = world.network
                }
                compared += compare(world, memo: &memo, "case \(index) step \(step)")
                if world.isTrafficControlEnabled { trafficControlled += 1 }
                // Trains holding track that fouls other track.
                fouling += world.trains.count { train in
                    world.held(train).contains { resource in
                        if case .span(let span) = resource { world.network.foulingSpans[span] != nil } else { false }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 10_000)
        XCTAssertGreaterThan(trafficControlled, 100)
        XCTAssertGreaterThan(fouling, 10, "trains hold track that fouls other track")
    }
}

extension ReservationShortcutTests {
    /// The memo kept from one call of `advance(ticks:)` to the next
    /// (`GameWorld.RouteMemo`) changes nothing: the long-leg replay a tick
    /// at a time, and the traffic-control and following campaigns'
    /// operations (whose commands change the network, the lines and the
    /// trains between the calls), each run beside a world whose kept memo is
    /// dropped before every operation, leave the two the same after each.
    func testTheMemoKeptBetweenAdvancesChangesNothing() throws {
        var kept = try LongLegReplayTests.world()
        var fresh = kept
        var lent = 0
        for operation in LongLegReplayTests.operations() {
            var parts = [operation]
            if case .advance(let ticks) = operation { parts = Array(repeating: .advance(1), count: ticks) }
            for part in parts {
                if !kept.routeMemo.isEmpty, case .advance = part { lent += 1 }
                fresh.routeMemo = GameWorld.RouteMemo()
                XCTAssertEqual(KernelDifferentialTests.apply(part, to: &kept), KernelDifferentialTests.apply(part, to: &fresh), "long leg: \(part)")
            }
            XCTAssertTrue(kept == fresh && SavedGame(world: kept) == SavedGame(world: fresh), "long leg after \(operation)")
        }
        XCTAssertGreaterThan(lent, 100, "advances lent a kept memo")
        for index in 0..<12 {
            var testCase = PropertyCase(suite: "traffic.routeMemo", seed: 0x5EED_A001, index: index)
            var kept = try index % 2 == 0
                ? TrafficControlPropertyTests.generateWorld(&testCase, operations: 0)
                : TrafficControlPropertyTests.beginFollowing(&testCase).world
            var fresh = kept
            for step in 0..<40 {
                let operation = index % 2 == 0
                    ? TrafficControlPropertyTests.operation(in: kept, using: &testCase.random)
                    : TrafficControlPropertyTests.followingOperation(in: kept, using: &testCase.random)
                fresh.routeMemo = GameWorld.RouteMemo()
                XCTAssertEqual(TrafficControlPropertyTests.apply(operation, to: &kept), TrafficControlPropertyTests.apply(operation, to: &fresh),
                               "case \(index) step \(step): \(operation)")
                XCTAssertTrue(SavedGame(world: kept) == SavedGame(world: fresh), "case \(index) step \(step) after \(operation)")
            }
        }
    }

    /// A ``GameWorld/TrackCover`` answers as the resources its stretches
    /// list (`resources(covering:)` and `foulingNodes(covering:)`), and so
    /// does whether a reservation holds all of a stretch: for
    /// every node and span of the network, and spans that are none of an
    /// edge's own (a reservation of an older network may hold them), of
    /// random stretches either way along random edges, from and to the
    /// ends, span boundaries and points between, several at once.
    func testATrackCoverAnswersAsTheResourcesItsStretchesList() throws {
        var checked = 0, covered = 0
        for (index, states) in try campaignStates(cases: 8, operations: 6).enumerated() {
            let world = states[states.count - 1]
            var random = SplitMix64(seed: UInt64(index) + 1)
            let edges = world.network.edges
            guard !edges.isEmpty else { continue }
            var resources = world.network.nodes.map { TrackResource.node($0.id) }
            for edge in edges {
                let spans = world.network.spans(of: edge.id, length: edge.length)
                resources += spans.map { .span($0) }
                // Not its own: across a boundary, and a part of one.
                if spans.count > 1 { resources.append(.span(TrackSpan(edge: edge.id, start: spans[0].start + 1, end: spans[1].end))) }
                resources.append(.span(TrackSpan(edge: edge.id, start: spans[0].start, end: spans[0].end - 1)))
            }
            for _ in 0..<60 {
                var stretches: [TrackStretch] = []
                for _ in 0..<(1 + random.below(3)) {
                    let edge = random.element(of: edges)
                    let spans = world.network.spans(of: edge.id, length: edge.length)
                    // Ends, boundaries and points between.
                    let points = [0, edge.length] + spans.map(\.start) + spans.map { $0.start + 1 } + [random.int64(in: 0...edge.length)]
                    let a = random.element(of: points), b = random.element(of: points)
                    stretches.append(TrackStretch(traversal: TrackTraversal(edge: edge.id, direction: random.chance(1, in: 2) ? .forward : .backward),
                                                  from: min(a, b), to: max(a, b)))
                }
                let listed = Set(world.resources(covering: stretches) + world.foulingNodes(covering: stretches))
                let cover = world.cover(of: stretches)
                // A reservation holding all of a stretch, or most of it,
                // with spans that are no edge's own, in order or not.
                for stretch in stretches {
                    let track = world.resources(covering: [stretch]) + world.foulingNodes(covering: [stretch])
                    var held = Set(track)
                    if !track.isEmpty, random.chance(1, in: 2) { held.remove(random.element(of: track)) }
                    for _ in 0..<random.below(4) { held.insert(random.element(of: resources)) }
                    let ordered = held.sorted()
                    for reservation in [ordered, ordered.reversed()] {
                        XCTAssertEqual(world.reserves(GameWorld.ReservedTrack(reservation), all: stretch), track.allSatisfy(held.contains), "\(stretch) of \(reservation)")
                        XCTAssertEqual(cover.kept(of: reservation), reservation.filter(cover.contains), "\(stretches) keeps of \(reservation)")
                        checked += 1
                    }
                }
                XCTAssertEqual(Set(cover.resources), listed, "\(stretches)")
                for resource in resources {
                    XCTAssertEqual(cover.contains(resource), listed.contains(resource), "\(resource) of \(stretches)")
                    checked += 1
                }
                covered += listed.count
            }
        }
        XCTAssertGreaterThan(checked, 10_000)
        XCTAssertGreaterThan(covered, 1_000)
    }
}

// MARK: - The long way, as it was

extension GameWorld {
    /// `holder(of:except:)` as it was: every other train's track gathered,
    /// and every following train's claim worked out, for each question.
    func longHolder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        let own = train(id: id).map(held) ?? []
        return trains.first { other in
            guard other.id != id, other.position != nil else { return false }
            if network.fouls(held(other), resources) { return true }
            guard let claim = longClaim(of: other), own.isDisjoint(with: claim.route), !longGoesFirst(id, before: other) else { return false }
            return network.fouls(claim.waiting, resources)
        }?.id
    }

    /// Whether train `id` goes before `other`, both following a train,
    /// where their routes meet: the lower ID goes first (decision 56,
    /// point 6, as amended), so `other`'s claim does not keep it.
    func longGoesFirst(_ id: TrainID, before other: Train) -> Bool {
        (train(id: id).map { isFollowing($0) } ?? false) && id < other.id
    }

    /// `blockedTrack(except:)` as it was.
    func longBlockedTrack(except id: TrainID) -> Set<TrackResource> {
        let own = train(id: id).map(held) ?? []
        var blocked: Set<TrackResource> = []
        for other in trains where other.id != id && other.position != nil {
            blocked.formUnion(held(other))
            if let claim = longClaim(of: other), own.isDisjoint(with: claim.route), !longGoesFirst(id, before: other) {
                blocked.formUnion(claim.waiting)
            }
        }
        return blocked
    }

    /// `blockedTrack(except:among:)` as it was.
    func longBlockedTrack(except id: TrainID, among ids: Set<TrainID>) -> Set<TrackResource> {
        let own = train(id: id).map(held) ?? []
        var blocked: Set<TrackResource> = []
        for other in trains where other.id != id && other.position != nil && ids.contains(other.id) {
            blocked.formUnion(held(other))
            if let claim = longClaim(of: other), own.isDisjoint(with: claim.route), !longGoesFirst(id, before: other) {
                blocked.formUnion(claim.waiting)
            }
        }
        return blocked
    }

    /// How far a following train may go (`authorityLeft(of:)`), as it was
    /// worked out: every stretch's track listed, each asked of the
    /// reservation, and the longest distance found by halving.
    func longAuthorityLeft(of train: Train) -> Int64? {
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        let reservation = Set(train.reservation)
        let route = routeStretches(of: train)
        guard let last = route.stretches.last,
              !resources(covering: [TrackStretch(traversal: last.traversal, from: last.to, to: last.to)]).allSatisfy(reservation.contains),
              route.moves
        else { return nil }
        let body = bodyStretches(of: train)
        let base = resources(covering: body) + foulingNodes(covering: body)
        let pieces = route.stretches.map { resources(covering: [$0]) + foulingNodes(covering: [$0]) }
        let holds = { (piece: [TrackResource]) in piece.allSatisfy(reservation.contains) }
        guard !holds(base) || !pieces.allSatisfy(holds) else { return nil }
        // The longest distance whose envelope the reservation holds.
        var ends: [Int64] = []
        var end: Int64 = 0
        for stretch in route.stretches {
            let (sum, overflow) = end.addingReportingOverflow(stretch.to - stretch.from)
            end = overflow ? .max : sum
            ends.append(end)
        }
        func isHeld(to distance: Int64) -> Bool {
            guard holds(base) else { return false }
            let index = ends.firstIndex { distance <= $0 } ?? route.stretches.count - 1
            let stretch = route.stretches[index]
            let start = index == 0 ? 0 : ends[index - 1]
            let part = TrackStretch(traversal: stretch.traversal, from: stretch.from, to: stretch.from + min(stretch.to - stretch.from, max(distance - start, 0)))
            return pieces[..<index].allSatisfy(holds) && holds(resources(covering: [part]) + foulingNodes(covering: [part]))
        }
        var (low, high) = (Int64(0), ends.last ?? 0)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if isHeld(to: middle) { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// `followingAuthority(of:route:)` as it was: every other train's
    /// track and claim gathered for each, the blocked track gathered, and
    /// each stretch's track listed.
    func longFollowingAuthority(of candidate: Train) -> Train? {
        let route = routeEnvelope(of: candidate).resources
        let own = train(id: candidate.id).map(held) ?? []
        for other in trains where other.id != candidate.id && other.position != nil {
            var holds = network.fouls(held(other), route)
            if !holds, let claim = longClaim(of: other), own.isDisjoint(with: claim.route), !longGoesFirst(candidate.id, before: other) {
                holds = network.fouls(claim.waiting, route)
            }
            guard holds else { continue }
            guard isLeading(other, onto: envelopeCover(of: candidate), for: candidate) else { return nil }
        }
        let blocked = longBlockedTrack(except: candidate.id)
        let envelopes = authorityEnvelopes(of: candidate)
        let clear = { (piece: [TrackResource]) in !self.network.fouls(piece, blocked.contains) }
        let clearBase = clear(envelopes.base)
        func isClear(to distance: Int64) -> Bool {
            guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
            let index = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
            let stretch = envelopes.stretches[index]
            let start = index == 0 ? 0 : envelopes.ends[index - 1]
            let part = TrackStretch(traversal: stretch.traversal, from: stretch.from, to: stretch.from + min(stretch.to - stretch.from, max(distance - start, 0)))
            return envelopes.stretches[..<index].allSatisfy { clear(resources(covering: [$0]) + foulingNodes(covering: [$0])) }
                && clear(resources(covering: [part]) + foulingNodes(covering: [part]))
        }
        var (low, high) = (Int64(0), envelopes.length)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if isClear(to: middle) { low = middle } else { high = middle - 1 }
        }
        let authority = low - Self.followingGap
        guard authority >= 1 else { return nil }
        var train = candidate
        train.reservation = authorityEnvelope(envelopes, to: authority).sorted()
        return train
    }

    /// `claim(of:)` as it was.
    func longClaim(of train: Train) -> (route: Set<TrackResource>, waiting: Set<TrackResource>)? {
        guard isFollowing(train) else { return nil }
        let route = routeEnvelope(of: train).resources
        var waiting = route
        for other in trains where other.id != train.id && other.position != nil {
            waiting.subtract(held(other))
        }
        return (route, waiting)
    }
}
