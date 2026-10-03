import Foundation
import GameCore
import XCTest

/// The track network's sections and parallel tracks (Stage F3c) under
/// generated command sequences: the kernel campaign's networks (lines,
/// rings with tails, ladders of crossovers, crossings, balloon loops) and
/// its commands, so track and platforms are built and removed as trains
/// move.
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``; every command must be refused alike, and after
///   every step the sections must be the same (the reference's come from a
///   union-find of edges, then are laid out and sorted) and so must the
///   parallel tracks between every pair of stations (depth-first
///   augmenting paths over named stretches).
/// - **Section facts.** Every edge belongs to exactly one section, each
///   traversal starts where the one before it ends, and the inner nodes of
///   a section are plain: exactly two edges end there, and they join.
///
/// `PROPERTY_REPLAY=network.sections@<seed>@<case>` runs one case.
final class NetworkSectionPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static let shapes: [KernelNetwork.Shape] = [.line, .loopWithTails, .loopWithTails, .ladder, .ladder, .crossings, .twoLines, .balloons, .balloons]

    /// Every difference between GameCore's sections and parallel tracks and
    /// the reference's.
    static func differences(_ world: GameWorld, _ model: ReferenceWorld) -> [String] {
        var found: [String] = []
        let sections = world.networkSections()
        let expected = model.networkSections()
        if sections != expected {
            found.append("sections \(sections.map(describe)) vs \(expected.map(describe))")
        }
        let stations = world.stations.map(\.id) + [StationID(rawValue: 0)]
        for a in stations {
            for b in stations where world.parallelTracks(between: a, and: b) != model.parallelTracks(between: a, and: b) {
                found.append("parallel tracks \(a.rawValue)-\(b.rawValue): \(world.parallelTracks(between: a, and: b)) vs \(model.parallelTracks(between: a, and: b))")
            }
        }
        return found
    }

    static func describe(_ section: NetworkSection) -> String {
        let steps = section.traversals.map { traversal in
            let number = if case .edge(let number) = traversal.edge { number } else { 0 }
            return "\(number)\(traversal.direction == .forward ? "+" : "-")"
        }
        return "[\(steps.joined(separator: " "))]\(section.isLoop ? " loop" : "")"
    }

    /// Facts every section list must have.
    static func sectionProblems(_ world: GameWorld) -> [String] {
        var found: [String] = []
        var seen: [TrackEdgeID: Int] = [:]
        let network = world.network
        func isPlain(_ id: TrackNodeID) -> Bool {
            guard let node = network.node(id) else { return false }
            return node.ends.count == 2 && node.ends[0].exits == [node.ends[1].edge] && node.ends[1].exits == [node.ends[0].edge]
        }
        for section in world.networkSections() {
            for traversal in section.traversals { seen[traversal.edge, default: 0] += 1 }
            let starts = section.traversals.compactMap { network.edge($0.edge)?.start(of: $0.direction) }
            let ends = section.traversals.compactMap { network.edge($0.edge)?.end(of: $0.direction) }
            let expectedNodes = section.isLoop ? starts : starts + ends.suffix(1)
            if section.nodes != expectedNodes || zip(ends, starts.dropFirst()).contains(where: { $0 != $1 }) {
                found.append("section \(describe(section)) does not run on from node to node: \(section.nodes)")
            }
            if section.isLoop, ends.last != starts.first {
                found.append("loop \(describe(section)) does not close")
            }
            let inner = section.isLoop ? section.nodes : Array(section.nodes.dropFirst().dropLast())
            for node in inner where !isPlain(node) {
                found.append("inner node \(node) of \(describe(section)) is a branch point")
            }
            if !section.isLoop, let first = section.nodes.first, let last = section.nodes.last, isPlain(first) || isPlain(last) {
                found.append("section \(describe(section)) ends at a plain node")
            }
        }
        for edge in network.edges where seen[edge.id] != 1 {
            found.append("edge \(edge.id) is in \(seen[edge.id] ?? 0) sections")
        }
        return found
    }

    func testNetworkSectionsAndParallelTracksMatchTheReference() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let ran = try runCampaign("network.sections", cases: 16) { c in
            let setup = KernelDifferentialTests.makeNetworkSetup(shapes: Self.shapes, using: &c.random)
            c.note("setup: \(setup.summary)")
            var (world, model) = try setup.build()
            var answers: [String] = []
            for index in 0..<60 {
                let operation = KernelDifferentialTests.nextOperation(in: world, using: &c.random)
                let error = KernelDifferentialTests.apply(operation, to: &world)
                let expectedError = KernelDifferentialTests.apply(operation, to: &model)
                let at = "step \(index) \(operation)"
                c.expect(error == expectedError, "\(at): GameCore \(String(describing: error)), reference \(String(describing: expectedError))")
                if error != expectedError { return }
                let problems = Self.differences(world, model) + Self.sectionProblems(world)
                c.expect(problems.isEmpty, "\(at): \(problems.prefix(5))")
                if !problems.isEmpty { return }

                let sections = world.networkSections()
                answers.append(sections.map(Self.describe).joined(separator: ","))
                if sections.contains(where: \.isLoop) { counts["ring", default: 0] += 1 }
                if sections.contains(where: { !$0.isLoop && $0.nodes.first == $0.nodes.last }) { counts["back to its branch point", default: 0] += 1 }
                if sections.contains(where: { $0.traversals.count >= 3 }) { counts["three edges or more", default: 0] += 1 }
                if sections.contains(where: { $0.traversals.contains { $0.direction == .backward } }) { counts["against an edge", default: 0] += 1 }
                let stations = world.stations.map(\.id)
                var most = 0
                for a in stations {
                    for b in stations where b != a {
                        let tracks = world.parallelTracks(between: a, and: b)
                        answers.append("\(a.rawValue)-\(b.rawValue):\(tracks)")
                        most = max(most, tracks)
                        if tracks == 1 { counts["single track", default: 0] += 1 }
                    }
                }
                if most >= 2 { counts["double track", default: 0] += 1 }
                if most >= 3 { counts["three tracks or more", default: 0] += 1 }
                if case .buildEdge = operation, error == nil { counts["ok buildEdge", default: 0] += 1 }
                if case .removeEdge = operation, error == nil { counts["ok removeEdge", default: 0] += 1 }
                if case .addPlatform = operation, error == nil { counts["ok addPlatform", default: 0] += 1 }
            }
            digest.add(answers.joined(separator: "\n"))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] network.sections \(digest.hex) (\(summary))")
        assertVolume(ran == 16 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("back to its branch point", 300), ("three edges or more", 1_500), ("against an edge", 700), ("ring", 5),
            ("single track", 25_000), ("double track", 700), ("three tracks or more", 15),
            ("ok buildEdge", 13), ("ok removeEdge", 15), ("ok addPlatform", 6),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
