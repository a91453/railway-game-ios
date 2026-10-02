import Foundation
import GameCore
import XCTest

/// Turnouts, crossings and track resources (Stage S1, decision 26) under
/// generated command sequences: networks whose junctions are often turnouts
/// (stem drawn at random) or crossings, trains placed, sent and moving
/// through them, and turnouts, crossings and plain track built and removed
/// as they go; some commands invalid on purpose (turnouts with too few
/// exits or a stem that is not an exit).
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, whose turning rule is a table of allowed (in, out)
///   pairs and whose routes are relaxed distances; all state must match
///   after every step (the kernel campaign's comparison: positions,
///   continuations, routes taken, platforms and stops). After every step
///   the Stage S1 queries must match too: each train's occupied track, the
///   conflicts, the exits from every track tile each way, the sections
///   (the reference's come from a union-find of links) and the parallel
///   tracks between every pair of stations (depth-first augmenting paths).
/// - **Section facts.** Every link belongs to exactly one section, and the
///   inner tiles of a section are plain pieces joined to exactly two.
/// - **Invariants and saves.** Every world reached keeps them; the world
///   each case ends in loads back equal and saves to the same bytes.
///
/// `PROPERTY_REPLAY=track.resources@<seed>@<case>` runs one case.
final class TrackResourcePropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        var setup = KernelDifferentialTests.makeSetup(shapes: [.grid, .grid, .loopWithTails, .ladder, .ladder, .random, .line], using: &c.random)
        setup.seconds = 60 * (c.random.int64(in: 0...10_000))
        setup.extraBalance = 1_000_000
        // Junctions become turnouts or crossings.
        setup.specs = setup.specs.map { spec in
            guard case .track(let connections) = spec.kind else { return spec }
            let exits = connections.directions
            if exits.count == 4, c.random.chance(1, in: 3) {
                return TileSpec(position: spec.position, kind: .crossing)
            }
            if exits.count >= 3, c.random.chance(2, in: 3) {
                return TileSpec(position: spec.position, kind: .turnout(connections, stem: c.random.element(of: exits)))
            }
            return spec
        }
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        // A few trains on the track, moving.
        for index in 0..<(2 + c.random.below(4)) {
            run(.purchase("R\(index + 1)"))
            guard let id = world.trains.last?.id, let position = PositionGenerator.validPosition(in: world, using: &c.random) else { continue }
            run(.place(id, position))
            run(.setRate(id, c.random.element(of: [512, 1024, 1024, 2048, 3000])))
        }
        while operations.count < count {
            switch c.random.below(10) {
            case 0:
                run(nextPieceOperation(in: world, using: &c.random))
            case 1, 2, 3:
                // Mostly toward a turnout or crossing, to pass through it.
                let special = world.tracks.filter { $0.layout != .open }.map(\.position)
                let tracks = world.tracks.map(\.position)
                guard let train = world.trains.isEmpty ? nil : c.random.element(of: world.trains), !tracks.isEmpty else {
                    run(.advance(5))
                    continue
                }
                run(.sendToTile(train.id, !special.isEmpty && c.random.chance(1, in: 2) ? c.random.element(of: special) : c.random.element(of: tracks)))
            case 4, 5:
                run(.advance(1 + c.random.below(8)))
            default:
                run(KernelDifferentialTests.nextOperation(in: world, using: &c.random))
            }
        }
        return (setup, operations)
    }

    /// A turnout or crossing built somewhere, mostly beside the network,
    /// sometimes invalid; or a piece removed.
    static func nextPieceOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let tile = GridPosition(x: random.below(world.map.width + 2) - 1, y: random.below(world.map.height + 2) - 1)
        switch random.below(4) {
        case 0:
            return .buildCrossing(tile)
        case 1:
            let special = world.tracks.filter { $0.layout != .open }.map(\.position)
            return .removeTrack(special.isEmpty ? tile : random.element(of: special))
        default:
            let mask: UInt8 = random.chance(1, in: 6) ? random.element(of: [0, 3, 5, 16, 31]) : random.element(of: [7, 11, 13, 14, 15])
            let exits = TrackDirection.allCases.filter { mask & (1 << TrackDirection.allCases.firstIndex(of: $0)!) != 0 }
            let stem = !exits.isEmpty && random.chance(9, in: 10) ? random.element(of: exits) : random.element(of: TrackDirection.allCases)
            return .buildTurnout(tile, mask, stem)
        }
    }

    /// Every difference between GameCore's and the reference's answers to
    /// the Stage S1 queries.
    static func resourceDifferences(_ world: GameWorld, _ model: ReferenceWorld) -> [String] {
        var found: [String] = []
        for raw in world.trains.map(\.id.rawValue) + [0, Int.max] {
            let id = TrainID(rawValue: raw)
            if world.occupiedResources(of: id) != model.occupiedResources(of: id) {
                found.append("occupied by \(raw): \(world.occupiedResources(of: id)) vs \(model.occupiedResources(of: id))")
            }
        }
        if world.occupancyConflicts() != model.occupancyConflicts() {
            found.append("conflicts \(world.occupancyConflicts()) vs \(model.occupancyConflicts())")
        }
        for y in -1...world.map.height {
            for x in -1...world.map.width {
                let p = GridPosition(x: x, y: y)
                for heading in TrackDirection.allCases {
                    let expected = model.neighbors(of: p).filter { model.mayTurn(at: p, facing: heading, to: stepDirection(from: p, to: $0)!) }
                    if world.exits(from: p, facing: heading) != expected {
                        found.append("exits from \(p) facing \(heading): \(world.exits(from: p, facing: heading)) vs \(expected)")
                    }
                }
            }
        }
        let sections = world.trackSections()
        if sections != model.trackSections() {
            found.append("sections \(sections.map(\.nodes)) vs \(model.trackSections().map(\.nodes))")
        }
        let stations = world.stations.map(\.id) + [StationID(rawValue: 0)]
        for a in stations {
            for b in stations where world.parallelTracks(between: a, and: b) != model.parallelTracks(between: a, and: b) {
                found.append("parallel tracks \(a.rawValue)-\(b.rawValue): \(world.parallelTracks(between: a, and: b)) vs \(model.parallelTracks(between: a, and: b))")
            }
        }
        return found
    }

    /// Facts every section list must have: each link in exactly one
    /// section, inner tiles plain and joined to exactly two.
    static func sectionProblems(_ world: GameWorld) -> [String] {
        var found: [String] = []
        var seen: [TrackResource: Int] = [:]
        for section in world.trackSections() {
            for link in section.links { seen[link, default: 0] += 1 }
            for inner in section.nodes.dropFirst().dropLast() where world.track(at: inner)?.layout != .open || world.connectedNeighbors(of: inner).count != 2 {
                found.append("inner tile \(inner) of \(section.nodes) is a branch point")
            }
        }
        for track in world.tracks {
            for neighbor in world.connectedNeighbors(of: track.position) {
                let link = TrackResource.link(between: track.position, and: neighbor)
                if seen[link] != 1 { found.append("link \(link) is in \(seen[link] ?? 0) sections") }
            }
        }
        return found
    }

    func testTrackResourcesMatchTheReference() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("track.resources", cases: 16) { c in
            let (setup, operations) = try Self.generate(&c, operations: 70)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles")

            if let failure = KernelDifferentialTests.firstProblem(setup, operations, lineAnswers: false) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations, lineAnswers: false)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var (world, model) = try setup.build()
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                _ = KernelDifferentialTests.apply(operation, to: &model)
                let at = "step \(index) \(operation)"
                switch operation {
                case .buildTurnout, .buildCrossing:
                    let name = "\(operation)".dropFirst().prefix { $0 != "(" }
                    counts[error.map { String("\($0)".prefix { $0 != "(" }) } ?? "ok \(name)", default: 0] += 1
                case .advance:
                    // A train that moved on from a turnout or crossing, or
                    // is now on a link from or to one.
                    let special = { (tile: GridPosition) in world.track(at: tile).map { $0.layout != .open } ?? false }
                    for train in world.trains where train.position != before.train(id: train.id)?.position {
                        switch (before.train(id: train.id)?.position, train.position) {
                        case (.atNode(let tile, _)?, _) where special(tile):
                            counts["left a turnout or crossing", default: 0] += 1
                        case (_, .onLink(let from, let to, _)?) where special(from) || special(to):
                            counts["left a turnout or crossing", default: 0] += 1
                        default:
                            break
                        }
                    }
                default:
                    break
                }
                let problems = Self.resourceDifferences(world, model) + Self.sectionProblems(world) + WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems.prefix(5))")
                if !problems.isEmpty { return }
                if !world.occupancyConflicts().isEmpty { counts["conflict", default: 0] += 1 }
                if world.trackSections().contains(where: \.isLoop) { counts["ring", default: 0] += 1 }
                let stations = world.stations.map(\.id)
                if stations.count >= 2, world.parallelTracks(between: stations[0], and: stations[1]) >= 2 { counts["double track", default: 0] += 1 }
            }
            counts["turnouts", default: 0] += world.tracks.count { if case .turnout = $0.layout { true } else { false } }
            counts["crossings", default: 0] += world.tracks.count { $0.layout == .crossing }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with turnouts and crossings did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] track.resources \(digest.hex) (\(summary))")
        assertVolume(ran == 16 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("ok buildTurnout", 5), ("invalidTrackConnections", 3), ("ok buildCrossing", 3), ("turnouts", 20), ("crossings", 5),
            ("left a turnout or crossing", 20), ("conflict", 5), ("double track", 5),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
