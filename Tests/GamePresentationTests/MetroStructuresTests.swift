import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The metros' and light rails' bridges, viaducts and tunnels (decision
/// 279, later): what tracing along each of their real lines carries, set
/// against what `rail_structures.json` says of the line.
final class MetroStructuresTests: XCTestCase {
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private let metre = RealWorldDemo.metre

    /// Along a line, every ``bin`` of it: what the file's structures beside
    /// it (``RealRailStructures/reach``) make it, nothing for the ground,
    /// and what tracing along it carries it on.
    struct Bins {
        var truth: [RealRailStructures.Kind?]
        /// Where the file has both kinds beside it: two lines of a system
        /// one over the other, which it does not say which is this one's.
        var both: [Bool]
        var carried: [RealRailStructures.Kind?]
    }

    private static let bin = 16.0 * RealWorldDemo.metre

    private func bins(_ line: RealRailways.Line, _ structures: RealRailStructures, _ frame: RealWorldFrame) -> Bins {
        let path = WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
        let count = max(1, Int((path.length / Self.bin).rounded(.up)))
        var kinds = [Set<RealRailStructures.Kind>](repeating: [], count: count)
        for structure in structures.structures where structure.system == line.system.id {
            let points = structure.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            for (a, b) in zip(points, points.dropFirst()) where (b - a).length > 0 {
                let way = (b - a) * (1 / (b - a).length)
                let steps = max(1, Int(((b - a).length / (Self.bin / 2)).rounded(.up)))
                for step in 0...steps {
                    let nearest = path.nearest(a + (b - a) * (Double(step) / Double(steps)))
                    // Not another line's that crosses this one (the metro
                    // and the light rail of a city share a system).
                    let tangent = path.tangent(at: nearest.along)
                    guard nearest.away <= RealRailStructures.reach, abs(way.x * tangent.x + way.y * tangent.y) >= 0.9 else { continue }
                    kinds[min(count - 1, Int(nearest.along / Self.bin))].insert(structure.kind)
                }
            }
        }
        let stretches = structures.stretches(along: path, frame: frame, system: line.system.id)
        let carried = (0..<count).map { index -> RealRailStructures.Kind? in
            let middle = (Double(index) + 0.5) * Self.bin
            return stretches.first { $0.range.contains(middle) }?.kind
        }
        return Bins(truth: kinds.map { $0.count == 1 ? $0.first : nil }, both: kinds.map { $0.count > 1 }, carried: carried)
    }

    /// What a share of a line is: by length, how much of what the file
    /// makes a tunnel tracing carries as a tunnel, of its bridges and
    /// viaducts as one, of its ground as either, and how long tracing's
    /// structures are for the file's.
    struct Shares {
        var tunnel = 0.0, tunnelKept = 0.0
        var bridge = 0.0, bridgeKept = 0.0
        var ground = 0.0, groundCarried = 0.0
        var carried = 0.0
        var overlap = 0.0

        init() {}

        init(_ bins: Bins) {
            for ((truth, carried), both) in zip(zip(bins.truth, bins.carried), bins.both) {
                guard !both else { overlap += 1; continue }
                switch truth {
                case .tunnel?: tunnel += 1; if carried == .tunnel { tunnelKept += 1 }
                case .bridge?: bridge += 1; if carried == .bridge { bridgeKept += 1 }
                case nil: ground += 1; if carried != nil { groundCarried += 1 }
                }
                if carried != nil { self.carried += 1 }
            }
        }

        static func + (a: Shares, b: Shares) -> Shares {
            var sum = a
            sum.tunnel += b.tunnel; sum.tunnelKept += b.tunnelKept
            sum.bridge += b.bridge; sum.bridgeKept += b.bridgeKept
            sum.ground += b.ground; sum.groundCarried += b.groundCarried
            sum.carried += b.carried
            sum.overlap += b.overlap
            return sum
        }

        var kilometres: Double { (tunnel + bridge + ground) * MetroStructuresTests.bin / RealWorldDemo.metre / 1_000 }
        var tunnelShare: Double? { tunnel > 0 ? tunnelKept / tunnel : nil }
        var bridgeShare: Double? { bridge > 0 ? bridgeKept / bridge : nil }
        var groundShare: Double? { ground > 0 ? groundCarried / ground : nil }
        var lengthShare: Double? { tunnel + bridge > 0 ? carried / (tunnel + bridge) : nil }
    }

    /// The bundled lines of the metros and light rails, each with its
    /// shares, and its stations of the same system within 60 m of it: the
    /// file's kind where each stands, and tracing's.
    private func metros() throws -> [(line: RealRailways.Line, shares: Shares, stations: [(name: String, truth: RealRailStructures.Kind?, carried: RealRailStructures.Kind?)])] {
        let railways = try RealRailways(
            lines: Self.bundledFile("track_lines.geojson"), stations: Self.bundledFile("track_stations.geojson"),
            names: Self.bundledFile("station_names.json"), structures: RealRailStructures(data: Self.bundledFile("rail_structures.json"))
        )
        let structures = try XCTUnwrap(railways.structures)
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        return railways.lines.filter { Self.systems.contains($0.system.id) }.map { line in
            let found = bins(line, structures, frame)
            let path = WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
            let stations = railways.stations.filter { $0.system.id == line.system.id }.compactMap { station -> (String, RealRailStructures.Kind?, RealRailStructures.Kind?)? in
                let nearest = path.nearest(WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)))
                guard nearest.away <= 60 * metre else { return nil }
                // A platform's length about it: the kind most of it is, and
                // whether tracing carries any of it.
                let middle = Int(nearest.along / Self.bin)
                let indices = max(0, middle - 4)...min(found.truth.count - 1, middle + 4)
                let kinds = indices.map { found.truth[$0] }
                let truth = [RealRailStructures.Kind.tunnel, .bridge].first { kind in kinds.filter { $0 == kind }.count * 2 > kinds.count }
                return (station.chinese, truth, indices.lazy.compactMap { found.carried[$0] }.first)
            }
            return (line, Shares(found), stations)
        }
    }

    static let systems: Set<String> = ["mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt"]

    /// Line by line and in all (by length): of the file's tunnels at least
    /// 85% carried as tunnels, of its bridges and viaducts 85% as them, of
    /// its ground at most 4% as either (decision 315's three), and the
    /// structures tracing carries 90 to 110% as long as the file's. And
    /// every station the file puts on a structure stays on it.
    func testTheMetrosAreCarriedAsTheyAre() throws {
        let found = try metros()
        var total = Shares()
        func percent(_ share: Double?) -> String { share.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }
        for (line, shares, stations) in found {
            total = total + shares
            let pulled = stations.filter { $0.truth != nil && $0.carried == nil }
            print("METRO \(line.system.id) \(line.name) \(String(format: "%.1f", shares.kilometres)) km: tunnel \(percent(shares.tunnelShare)) bridge \(percent(shares.bridgeShare)) ground carried \(percent(shares.groundShare)) length \(percent(shares.lengthShare)) overlap \(String(format: "%.2f", shares.overlap * Self.bin / metre / 1_000)) km | stations \(stations.count), underground \(stations.filter { $0.truth == .tunnel }.count), elevated \(stations.filter { $0.truth == .bridge }.count), on the ground in tracing \(pulled.map(\.name))")
            let name = "\(line.system.id) \(line.name)"
            // Lines of less than a kilometre are the joins between lines.
            guard shares.kilometres >= 1 else { continue }
            if shares.tunnel * Self.bin >= 500 * metre { XCTAssertGreaterThanOrEqual(try XCTUnwrap(shares.tunnelShare), 0.85, name) }
            if shares.bridge * Self.bin >= 500 * metre { XCTAssertGreaterThanOrEqual(try XCTUnwrap(shares.bridgeShare), 0.85, name) }
            if let ground = shares.groundShare { XCTAssertLessThanOrEqual(ground, 0.04, name) }
            if let length = shares.lengthShare, shares.tunnel + shares.bridge > 0 { XCTAssertTrue((0.9...1.1).contains(length), "\(name): \(length)") }
            XCTAssertEqual(pulled.map(\.name), [], name)
        }
        print("METRO all \(String(format: "%.1f", total.kilometres)) km: tunnel \(percent(total.tunnelShare)) bridge \(percent(total.bridgeShare)) ground carried \(percent(total.groundShare)) length \(percent(total.lengthShare)) overlap \(String(format: "%.2f", total.overlap * Self.bin / metre / 1_000)) km")
    }
}
