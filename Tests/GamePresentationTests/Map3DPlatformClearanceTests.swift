import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 392: the 3D map's platforms stand clear of every track, so a
/// train stopping at a platform or passing one, and the cab view riding
/// it, never runs into a platform (TestFlight 86.1, the owner's iPhone:
/// 「過站的時候會撞到月台」).
final class Map3DPlatformClearanceTests: XCTestCase {
    /// The high-speed demo as a device opens it.
    private static let highSpeed: Result<GameWorld, Error> = Result {
        try HighSpeedDemo.make(in: .traditionalChinese, railways: HighSpeedDemoTests.railways())
    }

    /// How far a platform's body comes over a track: positive where it is
    /// closer to the track's middle than its edge stands from its own
    /// (metres), with where.
    struct Intrusion: CustomStringConvertible {
        let station: String
        let metres: Float
        var description: String { "\(station) \(String(format: "%.2f", metres)) m" }
    }

    /// Every platform of the scene round `focus` against every track
    /// laid there: the deepest a platform's body reaches within its edge's
    /// distance (1.76 m at a high-speed station, else 1.6 m) of a track's
    /// middle, for each station, beyond its ends' last 2 m; and how many
    /// platforms each station has.
    static func intrusions(world: GameWorld, focus: (x: Double, y: Double)) -> (found: [Intrusion], laid: [StationID: Int]) {
        let frame = Map3DScene.frame(world: world, focus: focus)
        var builder = Map3DScene.Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: world)
        let snapshot = world.railwaySnapshot()
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        var deepest: [StationID: Float] = [:]
        let laid = Dictionary(grouping: builder.laidPlatforms, by: \.station).mapValues(\.count)
        for platform in builder.laidPlatforms {
            let edge = world.isHighSpeedStation(platform.station) ? Map3DScene.Builder.highSpeedPlatformEdge : Map3DScene.Builder.platformEdge
            let line = platform.line, across = Map3DMesh.acrossDirections(line)
            let inner = platform.offset - platform.width / 2, outer = platform.offset + platform.width / 2
            var along: [Float] = [0]
            for index in 1..<line.count { along.append(along[index - 1] + (line[index] - line[index - 1]).length) }
            let length = along.last ?? 0
            let minX = line.map(\.x).min()! - 20, maxX = line.map(\.x).max()! + 20
            let minZ = line.map(\.z).min()! - 20, maxZ = line.map(\.z).max()! + 20
            for track in builder.trackLines {
                for point in track.points where point.x > minX && point.x < maxX && point.z > minZ && point.z < maxZ {
                    // The nearest sample of the platform's line, and how
                    // far across it the track's middle lies there.
                    guard let index = line.indices.min(by: { (line[$0] - point).length < (line[$1] - point).length }),
                          along[index] > 2, along[index] < length - 2, (line[index] - point).length < 20,
                          abs(point.y - line[index].y) < 3
                    else { continue }
                    let lateral = (point - line[index]).dot(across[index])
                    let clearance = lateral < inner ? inner - lateral : lateral > outer ? lateral - outer : -min(lateral - inner, outer - lateral)
                    deepest[platform.station] = max(deepest[platform.station] ?? -.infinity, edge - clearance)
                }
            }
        }
        let found = deepest.filter { $0.value > 0.01 }
            .map { Intrusion(station: world.station(id: $0.key)?.name ?? "\($0.key.rawValue)", metres: $0.value) }
            .sorted { $0.station < $1.station }
        return (found, laid)
    }

    func testTheHighSpeedDemosPlatformsStandClearOfEveryTrack() throws {
        let world = try Self.highSpeed.get()
        // A train's body is drawn 2.9 m wide on its track's middle; the
        // platform's edge stands where the real one does from it, 1.76 m
        // on the High Speed Rail. On origin/main every station's platforms
        // reached 2.2 m to 2.5 m past that, over the next track's middle:
        // the through track's and its loop's, 5 m apart and staggered
        // 10 m, were taken for an island 11 m wide.
        // An end (Nangang), the island stations' first (Taipei), a
        // turnback station with second loops (Taichung) and a plain one
        // (Hsinchu); 1.6 m at the depots, which are not high-speed
        // stations.
        var found: [Intrusion] = []
        for station in world.stations where ["南港", "台北", "新竹", "台中", "烏日機廠"].contains(station.name) {
            let scene = Self.intrusions(world: world, focus: (x: Double(station.point.x), y: Double(station.point.y)))
            found += scene.found
            // Its side platforms beside the loops (or the end's platform
            // tracks) are still there.
            if !station.isDepot { XCTAssertGreaterThanOrEqual(scene.laid[station.id] ?? 0, 2, station.name) }
        }
        XCTAssertEqual(found.map(\.description), [], "platforms over a track")
    }
}

extension Map3DPlatformClearanceTests {
    /// A platform's line 100 m along x at z 0, at the rails' height.
    private static let line = stride(from: Float(-50), through: 50, by: 10).map { Map3DPoint($0, Map3DScene.railLift, 0) }

    private static func track(_ z: Float, from: Float = -80, to: Float = 80, y: Float = 0) -> [Map3DPoint] {
        [Map3DPoint(from, y, z), Map3DPoint(to, y, z)]
    }

    func testTheNearestTrackEitherSideIsMeasuredAcrossThePlatformsLine() {
        // Left is across the line's negative side: 5 m one way and 12 m
        // the other, the nearer of two on a side.
        let across = Map3DMesh.acrossDirections(Self.line)[0]
        let left: Float = across.z > 0 ? -1 : 1
        let near = Map3DScene.Builder.nearestTracks(beside: Self.line, others: [
            Self.track(left * 5), Self.track(left * 9), Self.track(-left * 12),
        ])
        XCTAssertEqual(near[0], 5, accuracy: 0.01)
        XCTAssertEqual(near[1], 12, accuracy: 0.01)
    }

    func testTracksBeyondItsEndsAboveOrBelowOrItsOwnAreNotBesideIt() {
        let near = Map3DScene.Builder.nearestTracks(beside: Self.line, others: [
            Self.track(4, from: 60, to: 120),   // beyond its end
            Self.track(-4, y: 8),               // on a viaduct over it
            Self.track(0.5),                    // its own, past a node
            Self.track(20),                     // too far
        ])
        XCTAssertEqual(near, [.infinity, .infinity])
    }
}
