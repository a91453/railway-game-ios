import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 827: the Tamsui-Xinyi line's elevated station shells.
final class Map3DTaipeiMRTStationsTests: XCTestCase {
    typealias Station = Map3DTaipeiMRTStation

    /// Points of a triangle the tests look at: its corners, the middles of
    /// its sides and its middle.
    private static func samples(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint) -> [Map3DPoint] {
        [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) * (1 / 3)]
    }

    /// Each of the four models, close by and from afar, decodes, within
    /// the studio's budget, the far one at most half the near one.
    func testEachModelDecodesWithinItsBudget() {
        let budget: [Station.Kind: Int] = [.standard: 4_000, .jiantan: 6_000, .beitou: 5_000, .xinbeitou: 3_500]
        for kind in [Station.Kind.standard, .jiantan, .beitou, .xinbeitou] {
            let near = Station.model(kind, near: true), far = Station.model(kind, near: false)
            XCTAssertGreaterThan(near.count, 1_000, "\(kind)")
            XCTAssertLessThanOrEqual(near.count, budget[kind]!, "\(kind)")
            XCTAssertLessThanOrEqual(far.count * 2, near.count, "\(kind)")
        }
    }

    /// Nothing of any model in the room the game's track, platforms and
    /// trains need: within the room's half either side of the middle, from
    /// 1.2 m under the rails to 3.9 m over them, along its whole length
    /// (Xinbeitou's up to its end wall).
    func testNoModelComesIntoTheRoom() {
        for kind in [Station.Kind.standard, .jiantan, .beitou, .xinbeitou] {
            let half = Station.roomHalf(kind) - 0.01
            let low = Station.modelRails - Station.roomBelow + 0.01, high = Station.modelRails + Station.roomAbove - 0.01
            for near in [true, false] {
                let inside = Station.model(kind, near: near).flatMap { Self.samples($0.0, $0.1, $0.2) }
                    .filter { abs($0.z) < half && $0.y > low && $0.y < high && $0.x < Station.roomEnd(kind) - 0.01 }
                XCTAssertEqual(inside.count, 0, "\(kind) near \(near): \(inside.prefix(3))")
            }
        }
    }

    /// Two tracks 4 m apart on a viaduct 10 m up, running north-east.
    private static func twoTracks(rails: Float = 10, bend: Float = 0) -> [[Map3DPoint]] {
        let along = Map3DPoint(cos(0.6), 0, -sin(0.6)), right = along.cross(.up)
        return [-2, 2].map { (side: Float) in
            stride(from: Float(-60), through: 60, by: 10).map { t in
                let sag = bend * (1 - (t / 60) * (t / 60))
                return Map3DPoint(100, rails, 50) + along * t + right * (side + sag)
            }
        }
    }

    /// The shell stands between the two tracks, along them, its rails at
    /// theirs and its foot on the ground; none of it within 3.2 m either
    /// side of either track from 1.2 m under the rails to 3.9 m over them
    /// (what the game's trains and platforms need: cut there would show).
    func testItStandsAlongTheGamesTrackClearOfIt() throws {
        let tracks = Self.twoTracks()
        for kind in [Station.Kind.standard, .jiantan, .beitou, .xinbeitou] {
            let placement = try XCTUnwrap(Station.placement(of: kind, platforms: tracks))
            XCTAssertEqual(placement.rails.x, 100, accuracy: 0.01)
            XCTAssertEqual(placement.rails.z, 50, accuracy: 0.01)
            XCTAssertEqual(placement.rails.y, 10, accuracy: 0.01)
            XCTAssertGreaterThan(placement.along.x, 0)
            let along = Map3DPoint(cos(0.6), 0, -sin(0.6))
            XCTAssertEqual(placement.along.dot(along), 1, accuracy: 1e-4, "\(kind) turned")
            let mesh = Station.sceneMesh(kind, near: true, at: placement, ground: 0)
            XCTAssertEqual(mesh.vertices.map(\.y).min() ?? -1, 0, accuracy: 0.05, "\(kind) foot")
            var cut = 0
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let p = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])].position }
                for s in Self.samples(p[0], p[1], p[2]) {
                    for track in tracks {
                        let a = track.first!, ab = track.last! - a, ap = s - a
                        let share = ab.dot(ap) / ab.dot(ab)
                        guard share > 0, share < 1 else { continue }
                        let off = ap - ab * share
                        if Map3DPoint(off.x, 0, off.z).length < 3.2, s.y > 10 - 1.2 + 0.01, s.y < 10 + 3.9 - 0.01 { cut += 1 }
                    }
                }
            }
            XCTAssertEqual(cut, 0, "\(kind): points in the trains' room")
        }
    }

    /// A platform bent off its chord by more than a metre carries no shell
    /// (the kit's station stands there instead).
    func testABentStationHasNone() {
        XCTAssertNil(Station.placement(of: .standard, platforms: Self.twoTracks(bend: 3)))
        XCTAssertNotNil(Station.placement(of: .standard, platforms: Self.twoTracks(bend: 0.5)))
    }

    /// Xinbeitou's end wall stands a metre past the platforms' east end:
    /// the nearest of it in the room's height over the track.
    func testTheTerminusEndsPastThePlatforms() throws {
        let tracks = Self.twoTracks()
        let placement = try XCTUnwrap(Station.placement(of: .xinbeitou, platforms: tracks))
        let end = tracks.flatMap { $0 }.map { ($0 - placement.rails).dot(placement.along) }.max()!
        let mesh = Station.sceneMesh(.xinbeitou, near: true, at: placement, ground: 0)
        let right = placement.along.cross(.up)
        let wall = stride(from: 0, to: mesh.indices.count, by: 3).flatMap { start in
            let p = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])].position }
            return Self.samples(p[0], p[1], p[2])
        }.filter {
            abs(($0 - placement.rails).dot(right)) < 2 && $0.y > 10 - 1.2 && $0.y < 10 + 3.9
        }.map { ($0 - placement.rails).dot(placement.along) }.filter { $0 > 0 }.min()!
        XCTAssertEqual(wall - end, 1, accuracy: 0.05)
    }

    /// The model's rails go to the game's rails; its foot to the ground
    /// however high the viaduct stands.
    func testTheRailsAndTheFoot() throws {
        for rails: Float in [7, 9, 12] {
            let placement = try XCTUnwrap(Station.placement(of: .standard, platforms: Self.twoTracks(rails: rails)))
            XCTAssertEqual(Station.scenePoint(Map3DPoint(0, 9, 0), placement, ground: 1).y, rails, accuracy: 1e-4)
            XCTAssertEqual(Station.scenePoint(Map3DPoint(0, 0, 0), placement, ground: 1).y, 1, accuracy: 1e-4)
            XCTAssertEqual(Station.scenePoint(Map3DPoint(0, 13, 0), placement, ground: 1).y, rails + 4, accuracy: 1e-4)
        }
    }

    /// REVIEW-L27 P3-2 (ELEVATED-SHELL-CHUNK): a block of chunks that lays
    /// one of a station's two raised platforms places its shell by both,
    /// as the whole scene does; a station with only its ground platforms
    /// laid here, or none, gets no lines, and tunnel and ground platforms
    /// are never among them.
    func testTheShellIsPlacedByAllTheStationsRaisedPlatforms() {
        typealias Laid = Map3DScene.Builder.LaidPlatform
        let a = StationID(rawValue: 1), b = StationID(rawValue: 2), c = StationID(rawValue: 3)
        func line(_ y: Int64) -> [WorldCoordinate] { [WorldCoordinate(x: 0, y: y), WorldCoordinate(x: 10_000, y: y)] }
        let network: [(station: StationID, structure: TrackStructure, points: [WorldCoordinate])] = [
            (a, .elevated, line(0)), (a, .elevated, line(400)), (a, .tunnel, line(800)),
            (b, .surface, line(2_000)), (b, .bridge, line(2_400)),
            (c, .elevated, line(4_000)),
        ]
        func lift(_ point: WorldCoordinate) -> Map3DPoint { Map3DPoint(Float(point.x) / 100, 10, Float(point.y) / 100) }
        // Only a's first platform and b's ground one are laid in this block.
        let laid = [
            Laid(station: a, line: line(0).map(lift), offset: 2, width: 4, structure: .elevated),
            Laid(station: b, line: line(2_000).map(lift), offset: 2, width: 4, structure: .surface),
        ]
        let lines = Map3DScene.Builder.shellLines(laid: laid, network: network, lift: lift)
        XCTAssertEqual(Set(lines.keys), [a])
        XCTAssertEqual(lines[a], [line(0).map(lift), line(400).map(lift)])
        // The whole scene, every platform laid: the same lines for a.
        let whole = network.filter { $0.structure != .tunnel }.map {
            Laid(station: $0.station, line: $0.points.map(lift), offset: 2, width: 4, structure: $0.structure)
        }
        let all = Map3DScene.Builder.shellLines(laid: whole, network: network, lift: lift)
        XCTAssertEqual(all[a], lines[a])
        XCTAssertEqual(all[b], [line(2_400).map(lift)])
        XCTAssertEqual(all[c], [line(4_000).map(lift)])
    }
}
