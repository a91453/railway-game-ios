import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// TRACKCOUNT-STUDY (docs/research/URBAN_TRACK_LAYOUT_2026-11-05.md): buys
/// each light rail and metro on sale and prints, station by station, how
/// many platform tracks the game laid and how many switches lie nearest
/// it, to set beside the real layout. Run only when asked
/// (`URBAN_TRACK_REPORT=1`; `URBAN_TRACK_ONLY=<id>` for one line).
@MainActor
final class UrbanTrackLayoutReportTests: XCTestCase {
    func testTheUrbanLinesTracks() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["URBAN_TRACK_REPORT"] != nil else {
            throw XCTSkip("Set URBAN_TRACK_REPORT=1 to count the urban lines' tracks.")
        }
        let ids = ["ntdlrt:V", "ntdlrt:VB", "ntalrt:K", "trtc:R_XBT", "trtc:G_XBT", "sanying:LB", "trtc:BR", "tymc:A"]
        for id in ids where environment["URBAN_TRACK_ONLY"].map({ $0 == id }) ?? true {
            let world = try DepotReturnReportTests.bought(id, side: id == "tymc:A" ? 1 << 22 : 1 << 21)
            let stations = world.stations
            func distance(_ a: PlanPoint, _ b: WorldCoordinate) -> Double {
                let dx = Double(a.x) - Double(b.x), dy = Double(a.y) - Double(b.y)
                return (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
            }
            // Each switch (a node three or more edges meet at) to the
            // nearest station or depot.
            var switches: [StationID: Int] = [:]
            for node in world.network.nodes where node.ends.count >= 3 {
                guard let nearest = stations.min(by: { distance($0.location, node.position) < distance($1.location, node.position) }) else { continue }
                switches[nearest.id, default: 0] += 1
            }
            var lines: [String] = []
            for station in stations {
                let platforms = world.network.platforms(of: station.id)
                lines.append("URBAN_TRACK \(id) \(station.name)\(station.isDepot ? " [depot]" : "") platforms=\(platforms.count) edges=\(Set(platforms.map(\.edge)).count) switches=\(switches[station.id] ?? 0)")
            }
            let total = world.network.nodes.filter { $0.ends.count >= 3 }.count
            lines.append("URBAN_TRACK \(id) total switches=\(total) trains=\(world.trains.count)")
            FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }
}
