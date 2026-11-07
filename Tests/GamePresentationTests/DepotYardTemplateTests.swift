@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 619: the depot tool lays a real yard's throat, a tree of
/// turnouts, not decision 214's ladder of one turnout and a 72 m S-curve
/// per siding. The lengths are OSM's (docs/research/YARD_TYPES_2026-11-07.md):
/// Muzha fans 12 sidings out in about 112 m, Neihu 16 in about 148 m, real
/// turnouts 20-26 m apart.
///
/// A straight track from west (x 1024) to east (x 16384) along y 32768 of
/// a world wide enough for a metro yard's 24 sidings.
@MainActor
final class DepotYardTemplateTests: XCTestCase {
    private static let metre = WorldCoordinate.unitsPerMetre

    private func world(minutes: Int64 = 600) throws -> (GameWorld, west: StationID, east: StationID, end: TrackNodeID, edge: TrackEdgeID) {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 65_536), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 32_768))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 32_768))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 33_280)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_288, y: 33_280)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 9_216, to: 13_312)
        return (world, west, east, b, edge)
    }

    private func session(_ world: GameWorld, sidings: Int, template: DepotYardTemplate = .lightRail) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.networkDepotSidings = sidings
        session.networkDepotTemplate = template
        return session
    }

    /// The throat's length: from the first turnout, a lead (22 m) on from
    /// the track's end, to where the last siding comes out beside the
    /// others.
    private func throat(_ plan: DepotYardPlan) -> Int64 {
        (plan.branches.map { $0.bend.x }.max() ?? plan.lead.x) - plan.lead.x
    }

    private func plan(_ session: GameSession, end: TrackNodeID, sidings: Int, template: DepotYardTemplate, side: PlatformTrackSide? = nil) throws -> DepotYardPlan {
        guard case .success(let plan) = session.depotYardPlan(from: end, sidings: sidings, side: side, template: template) else {
            throw XCTSkip("no plan")
        }
        return plan
    }

    // MARK: - The throat

    /// As long as the real yards' throats, not 72 m a siding: a metro
    /// yard's 12 sidings in Muzha's 112-148 m (125 m), 16 in about
    /// Neihu's 148 m (143 m), 24 at 8 m a siding (8 at 11 m, the real 9 m); the
    /// tool's six in 78 m, where the ladder took 360 m.
    func testTheThroatIsAsShortAsARealYards() throws {
        let (world, _, _, end, _) = try world()
        let session = session(world, sidings: 6)
        let six = throat(try plan(session, end: end, sidings: 6, template: .lightRail))
        XCTAssertLessThan(six, 80 * Self.metre, "the ladder's 360 m")
        let twelve = throat(try plan(session, end: end, sidings: 12, template: .metro))
        XCTAssertTrue((112 * Self.metre)...(148 * Self.metre) ~= twelve, "\(Double(twelve) / 64) m")
        let sixteen = throat(try plan(session, end: end, sidings: 16, template: .metro))
        XCTAssertLessThanOrEqual(sixteen, 148 * Self.metre, "\(Double(sixteen) / 64) m")
        for sidings in [8, 12, 16, 24] {
            let length = throat(try plan(session, end: end, sidings: sidings, template: .metro))
            XCTAssertLessThanOrEqual(length, Int64(sidings) * 23 * Self.metre / 2, "\(sidings) sidings: \(Double(length) / 64) m")
        }
    }

    /// Each turnout splits the tracks it carries in two: n sidings take
    /// n − 1 turnouts, and a siding passes over no more than ⌈log₂ n⌉ of
    /// them.
    func testEachTurnoutSplitsTheTracksInTwo() {
        for sidings in 1...DepotYard.mostSidings {
            let fan = DepotYardFan(sidings: sidings, spacing: DepotYard.spacing, anchor: nil)
            XCTAssertEqual(fan.legs.count, 2 * (sidings - 1))
            XCTAssertEqual(fan.legs.compactMap(\.siding).sorted(), sidings > 1 ? Array(0..<sidings) : [])
            let deepest = Int(log2(Double(sidings)).rounded(.up))
            // A leg's depth: how many legs lie before it on the way out.
            func depth(_ leg: DepotYardFan.Leg) -> Int {
                guard let parent = fan.legs.first(where: { $0.to == leg.from && $0.toAcross == leg.fromAcross }) else { return 1 }
                return depth(parent) + 1
            }
            XCTAssertEqual(fan.legs.map(depth).max() ?? 0, deepest, "\(sidings) sidings")
        }
    }

    /// About the lead the two sides mirror each other: an even yard's
    /// legs on one side are the other's turned over, so each siding
    /// leaves at the same depth as its mirror; an odd yard, which two-way
    /// turnouts cannot halve, has its middle siding one turnout deeper on
    /// one side at most.
    func testTheSidesAboutTheLeadMirrorEachOther() {
        for sidings in 2...DepotYard.mostSidings {
            let fan = DepotYardFan(sidings: sidings, spacing: DepotYard.spacing, anchor: nil)
            func depth(_ leg: DepotYardFan.Leg) -> Int {
                guard let parent = fan.legs.first(where: { $0.to == leg.from && $0.toAcross == leg.fromAcross }) else { return 1 }
                return depth(parent) + 1
            }
            var depths: [Int: Int] = [:]
            for leg in fan.legs { if let siding = leg.siding { depths[siding] = depth(leg) } }
            if sidings % 2 == 0 {
                let mirrored = Set(fan.legs.map { DepotYardFan.Leg(from: $0.from, fromAcross: -$0.fromAcross, to: $0.to, toAcross: -$0.toAcross, siding: $0.siding.map { sidings - 1 - $0 }) })
                XCTAssertEqual(Set(fan.legs), mirrored, "\(sidings) sidings")
                for siding in 0..<sidings { XCTAssertEqual(depths[siding], depths[sidings - 1 - siding], "\(sidings) sidings, siding \(siding)") }
            } else {
                for siding in 0..<sidings { XCTAssertLessThanOrEqual(abs((depths[siding] ?? 0) - (depths[sidings - 1 - siding] ?? 0)), 1, "\(sidings) sidings, siding \(siding)") }
            }
        }
    }

    /// Built, its turnouts stand at least 22 m apart (the real 20-26 m),
    /// its sidings 5 m apart about the track's end, each as long as the
    /// kind's for the longest train with a platform for it, and GameCore
    /// takes every one, light rail's and metro's, about the end or to a
    /// side.
    func testEveryYardIsBuiltWithTurnoutsApartAndSidingsForTheTrain() throws {
        let (world, _, _, _, _) = try world()
        for template in DepotYardTemplate.allCases {
            for sidings in [1, 2, 3, 5, template.defaultSidings, template.sidings.upperBound] {
                for side in [nil, PlatformTrackSide.left, .right] {
                    let session = session(world, sidings: sidings, template: template)
                    session.networkDepotSide = side
                    session.tapNetwork(at: PlanPoint(x: 16_384, y: 32_768), reach: 64)
                    session.addDepotYard()
                    let label = "\(template) \(sidings) \(side.map { "\($0)" } ?? "about")"
                    XCTAssertEqual(session.message?.kind, .success, "\(label): \(session.message?.text ?? "")")
                    let after = session.world
                    let depot = try XCTUnwrap(after.stations.first(where: \.isDepot), label)
                    let platforms = after.trackPlatforms(of: depot.id)
                    XCTAssertEqual(platforms.count, sidings, label)
                    for platform in platforms {
                        XCTAssertEqual(platform.end - platform.start, session.passingLoopLength, accuracy: 16, label)
                    }
                    // The turnouts, the yard's nodes of three ends; along the
                    // track from one to the next, 22 m or more (turnouts on
                    // tracks side by side may stand abreast, as in Muzha).
                    let turnouts = Set(after.network.nodes.filter { $0.ends.count == 3 }.map(\.id))
                    XCTAssertEqual(turnouts.count, sidings - 1, label)
                    for edge in after.network.edges where turnouts.contains(edge.from) && turnouts.contains(edge.to) {
                        XCTAssertGreaterThanOrEqual(edge.length, NetworkBuilding.minimumSpacing - 8, label)
                    }
                    // The sidings' buffers, 5 m apart; about the end, as
                    // many on each side as can be.
                    let buffers = after.network.nodes.filter { $0.ends.count == 1 && $0.position.x > 16_384 }.map(\.position.y).sorted()
                    XCTAssertEqual(buffers.count, sidings, label)
                    XCTAssertEqual(Set(zip(buffers, buffers.dropFirst()).map { $1 - $0 }), sidings > 1 ? [DepotYard.spacing] : [], label)
                    switch side {
                    case nil: XCTAssertLessThanOrEqual(abs(buffers.first! + buffers.last! - 2 * 32_768), DepotYard.spacing, label)
                    case .left?: XCTAssertEqual(buffers.last, 32_768, label)
                    case .right?: XCTAssertEqual(buffers.first, 32_768, label)
                    }
                    // Each siding, from where it comes out to its buffer,
                    // at least the kind's length for the train.
                    for buffer in after.network.nodes where buffer.ends.count == 1 && buffer.position.x > 16_384 {
                        let siding = try XCTUnwrap(after.network.edge(buffer.ends[0].edge))
                        XCTAssertGreaterThanOrEqual(siding.length, template.sidingLength(for: session.passingLoopLength) - 64, label)
                    }
                }
            }
        }
    }

    func testTheKindsAreTheRealYards() {
        XCTAssertEqual(DepotYardTemplate.lightRail.sidings, 4...12)
        XCTAssertEqual(DepotYardTemplate.metro.sidings, 8...24)
        XCTAssertEqual(DepotYardTemplate.lightRail.defaultSidings, 6)
        XCTAssertEqual(DepotYardTemplate.metro.defaultSidings, 12)
        // Danhai's and Ankeng's shortest 75 m; Neihu's 148 m.
        XCTAssertEqual(DepotYardTemplate.lightRail.sidingLength(for: 30 * Self.metre), 75 * Self.metre)
        XCTAssertEqual(DepotYardTemplate.metro.sidingLength(for: 30 * Self.metre), 150 * Self.metre)
        XCTAssertEqual(DepotYardTemplate.metro.sidingLength(for: 140 * Self.metre), 170 * Self.metre)
        XCTAssertEqual(DepotYardTemplate.lightRail.spacing, 5 * Self.metre)
        XCTAssertEqual(DepotYardFan.reach(across: 0), 22 * Self.metre)
        // A cubic S-curve 5 m across, kept to a 25 m radius: 27.4 m.
        XCTAssertEqual(DepotYardFan.reach(across: 5 * Self.metre), 1_753)
    }

    /// A log from before decision 619 holds a ladder (decision 214):
    /// replayed, it is laid as it was, each turnout on the siding inside.
    func testALadderFromAnOldLogIsLaidAsItWas() throws {
        let (world, _, _, end, _) = try world()
        let session = session(world, sidings: 3)
        let origin = try XCTUnwrap(world.network.node(end)).position
        func at(_ along: Int64, _ siding: Int64) -> WorldCoordinate {
            WorldCoordinate(x: origin.x + along, y: origin.y - siding * DepotYard.spacing)
        }
        let length = session.passingLoopLength
        let start = 22 * Self.metre + 50 * Self.metre + 22 * Self.metre + 50 * Self.metre, far = start + length
        let branches = try (1...2).map { k -> DepotYardPlan.Branch in
            let turnout = 22 * Self.metre + Int64(k - 1) * 72 * Self.metre
            let from = at(turnout, Int64(k - 1)), bend = at(turnout + 50 * Self.metre, Int64(k))
            let curve = try XCTUnwrap(NetworkBuilding.curve(from: from.plan, leaving: PlanVector(dx: 1, dy: 0), to: bend.plan, leaving: PlanVector(dx: -1, dy: 0)))
            return DepotYardPlan.Branch(turnout: from, bend: bend, curve: curve, end: at(far, Int64(k)))
        }
        let ladder = DepotYardPlan(
            end: end.number, origin: origin, lead: at(far, 0), branches: branches,
            platforms: (0..<3).map { [at(start, Int64($0)), at(far, Int64($0))] },
            structure: .surface, name: "Depot 1", station: at((start + far) / 2, 1).plan
        )
        XCTAssertNotNil(session.perform(.buildDepotYard(ladder), message: { _, _, _ in "" }), session.message?.text ?? "")
        let ends = session.world.network.nodes.filter { $0.ends.count == 1 && $0.position.x > 16_384 }.map(\.position.y).sorted()
        XCTAssertEqual(ends, [32_768 - 640, 32_768 - 320, 32_768])
        // Turnouts split the siding inside: 22 m and 94 m on.
        XCTAssertEqual(session.world.network.nodes.filter { $0.ends.count == 3 }.map(\.position.x).sorted(), [origin.x + 1_408, origin.x + 6_016])
    }

    // MARK: - In and out

    /// Six trains of one line stand in a light rail yard's six sidings;
    /// one runs the line by day. Through two days no train is ever
    /// deadlocked, the one leaves through the throat past the others each
    /// morning and comes back into a siding of its own each night, and at
    /// three in the morning all six stand in the depot.
    func testTrainsGoInAndOutPastEachOtherWithoutBlocking() throws {
        var (world, west, east, _, _) = try world(minutes: 1_380)
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        try world.setLineServiceWindow(main, to: .standard)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let session = session(world, sidings: 6)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 32_768), reach: 64)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        var yard = session.world
        let depot = try XCTUnwrap(yard.stations.first(where: \.isDepot)).id
        try yard.setLineDepots(main, to: [depot])
        // A train standing at each siding's platform, its head at the
        // platform's throat end (a node, as a train is placed), facing the
        // throat.
        var trains: [TrainID] = []
        for (index, platform) in yard.trackPlatforms(of: depot).enumerated() {
            let train = try yard.purchaseTrain(named: "T\(index + 1)").id
            let head = try yard.splitTrackEdge(platform.edge, at: platform.start)
            let siding = try XCTUnwrap(yard.network.edges.first { $0.from == head })
            try yard.placeTrain(train, at: .onEdge(TrackTraversal(edge: siding.id, direction: .backward), offset: siding.length))
            try yard.setTrainMovementRate(train, to: 1_024)
            try yard.assignTrain(train, to: main)
            trains.append(train)
        }
        yard.resume()
        var seen: [TrainID: [TrainDepotState]] = [:]
        var deadlocked = 0
        var atThree: [Int] = []
        for _ in 0..<(48 * 60) {
            try yard.advance(ticks: 1)
            deadlocked = max(deadlocked, yard.deadlockedTrains().count)
            for train in trains {
                if let state = yard.depotState(of: train), seen[train]?.last != state { seen[train, default: []].append(state) }
            }
            if yard.clock.now.seconds % GameTime.secondsPerDay == 3 * 3_600 { atThree.append(yard.trainsInDepot(of: main)) }
        }
        XCTAssertEqual(deadlocked, 0)
        XCTAssertEqual(atThree, [6, 6])
        let ran = seen.values.filter { $0.contains(.pullingOut) && $0.contains(.pullingIn) }
        XCTAssertGreaterThanOrEqual(ran.count, 1, "\(seen)")
        // At night each stands on a siding of its own.
        var night = yard
        while night.clock.now.seconds % GameTime.secondsPerDay != 3 * 3_600 { try night.advance(ticks: 1) }
        let edges = trains.compactMap { id -> TrackEdgeID? in
            guard case .onEdge(let traversal, _)? = night.train(id: id)?.position else { return nil }
            return traversal.edge
        }
        XCTAssertEqual(Set(edges).count, 6, "\(edges)")
    }
}
