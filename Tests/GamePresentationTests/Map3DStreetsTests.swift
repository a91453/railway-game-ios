import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 263: the seeded streets of a map with no base map,
/// the track first, and the row houses along them.
final class Map3DStreetsTests: XCTestCase {
    func testAMainRoadEveryFourToSixLinesAndStreetsAndLanesBetween() {
        for horizontal in [true, false] {
            let kinds = (-60...60).map { Map3DSeededStreets.kind(ofLine: $0, horizontal: horizontal) }
            let mains = kinds.indices.filter { kinds[$0] == .primary }
            let gaps = Set(zip(mains, mains.dropFirst()).map { $1 - $0 })
            XCTAssertEqual(gaps.count, 1, "evenly spaced")
            XCTAssertTrue((4...6).contains(gaps.first ?? 0))
            XCTAssertTrue(kinds.contains(.tertiary))
            XCTAssertTrue(kinds.contains(.minor))
            XCTAssertEqual(kinds, (-60...60).map { Map3DSeededStreets.kind(ofLine: $0, horizontal: horizontal) }, "the same every time")
        }
    }

    func testStreetsRunBesideBuiltLotsAndSomeLotsShareABlock() {
        var built: [Map3DScene.ChunkKey: Int] = [:]
        for row in 0..<12 { for column in 0..<12 { built[Map3DScene.ChunkKey(column: column, row: row)] = 1 } }
        let streets = Map3DSeededStreets(built: built)
        for edge in streets.edges.keys {
            let (a, b) = Map3DSeededStreets.cells(beside: edge)
            XCTAssertTrue(built[a] != nil || built[b] != nil, "\(edge)")
        }
        // 12 × 13 edges each way round 144 lots; some lanes left out.
        XCTAssertLessThan(streets.edges.count, 2 * 12 * 13)
        XCTAssertGreaterThan(streets.edges.count, 2 * 12 * 13 * 3 / 4)
        // Dense lots have no lane beside them: a street at least.
        var dense = built
        for key in dense.keys { dense[key] = 4 }
        XCTAssertFalse(Map3DSeededStreets(built: dense).edges.values.contains(.minor))
        XCTAssertEqual(Map3DSeededStreets(built: dense).edges.count, 2 * 12 * 13)
    }

    func testAStreetGoesOnAcrossTheCellsTheTrackTakes() {
        // Two lots on a row with two cleared cells (the track's) between.
        let built = [Map3DScene.ChunkKey(column: 0, row: 0): 1, Map3DScene.ChunkKey(column: 3, row: 0): 1]
        let streets = Map3DSeededStreets(built: built)
        for line in [0, 1] {
            let edges = (0...3).map { Map3DSeededStreets.Edge(horizontal: true, line: line, along: $0) }
            guard streets.edges[edges[0]] != nil, streets.edges[edges[3]] != nil else { continue }
            // A main road and half the streets go on; lanes end at it.
            let goesOn = Map3DSeededStreets.crossesTrack(line: line, horizontal: true)
            XCTAssertEqual(streets.edges[edges[1]] != nil, goesOn, "line \(line)")
            XCTAssertEqual(streets.edges[edges[2]] != nil, goesOn, "line \(line)")
        }
        // Which lines go on: every main road, no lane, some streets.
        let lines = (-40...40).map { (Map3DSeededStreets.kind(ofLine: $0, horizontal: true), Map3DSeededStreets.crossesTrack(line: $0, horizontal: true)) }
        XCTAssertTrue(lines.allSatisfy { $0.0 != .primary || $0.1 })
        XCTAssertTrue(lines.allSatisfy { $0.0 != .minor || !$0.1 })
        XCTAssertTrue(lines.contains { $0.0 == .tertiary && $0.1 })
        XCTAssertTrue(lines.contains { $0.0 == .tertiary && !$0.1 })
        // Far apart, no.
        let far = Map3DSeededStreets(built: [Map3DScene.ChunkKey(column: 0, row: 0): 1, Map3DScene.ChunkKey(column: 9, row: 0): 1])
        XCTAssertNil(far.edges[Map3DSeededStreets.Edge(horizontal: true, line: 0, along: 4)])
    }

    private func builder(track: [Map3DPoint], kind: TrackSectionKind, platform: Bool = false) -> Map3DScene.Builder {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: world)
        if platform { builder.platformLines = [track] } else { builder.trackLines = [(track, kind)] }
        return builder
    }

    func testTheTrackComesFirst() {
        let road = (Map3DPoint(0, 0, 0), Map3DPoint(64, 0, 0))
        func meeting(_ track: [Map3DPoint], _ kind: TrackSectionKind, platform: Bool = false) -> Map3DScene.Builder.TrackMeeting {
            let b = builder(track: track, kind: kind, platform: platform)
            let (segments, index) = b.trackSegments()
            return b.trackMeeting(from: road.0, to: road.1, half: 7.5, segments: segments, index: index)
        }
        let across = [Map3DPoint(30, 1, -40), Map3DPoint(30, 1, 40)]
        let along = [Map3DPoint(-10, 1, 6), Map3DPoint(80, 1, 6)]
        // On the ground, across it: a level crossing at the rails' height.
        let north = Map3DPoint(0, 0, 1)
        XCTAssertEqual(meeting(across, .surface), .crossing(Map3DPoint(30, 1, 0), way: north, spread: 0))
        // Decision 267: a double track (4 m apart): one crossing over both,
        // in the middle between them.
        var double = builder(track: across, kind: .surface)
        double.trackLines.append(([Map3DPoint(34, 1, -40), Map3DPoint(34, 1, 40)], .surface))
        let (doubleSegments, doubleIndex) = double.trackSegments()
        XCTAssertEqual(double.trackMeeting(from: road.0, to: road.1, half: 7.5, segments: doubleSegments, index: doubleIndex),
                       .crossing(Map3DPoint(32, 1, 0), way: north, spread: 4))
        // Two tracks far apart are not one crossing.
        var apart = builder(track: across, kind: .surface)
        apart.trackLines.append(([Map3DPoint(50, 1, -40), Map3DPoint(50, 1, 40)], .surface))
        let (apartSegments, apartIndex) = apart.trackSegments()
        XCTAssertEqual(apart.trackMeeting(from: road.0, to: road.1, half: 7.5, segments: apartSegments, index: apartIndex), .blocked)
        // Over a viaduct or a tunnel, the street runs on under or over.
        XCTAssertEqual(meeting(across, .viaduct), .clear, "under a viaduct where no pier stands")
        var piered = builder(track: across, kind: .viaduct)
        piered.piers = [Map3DPoint(30, 0, 2)]
        let (segments, index) = piered.trackSegments()
        XCTAssertEqual(piered.trackMeeting(from: road.0, to: road.1, half: 7.5, segments: segments, index: index), .blocked, "a pier in the street")
        // A track of short pieces still crosses once, at a level crossing.
        let pieces = stride(from: Float(-40), through: 40, by: 16).map { Map3DPoint(30, 1, $0) }
        XCTAssertEqual(meeting(pieces, .surface), .crossing(Map3DPoint(30, 1, 0), way: north, spread: 0))
        XCTAssertEqual(meeting(across, .tunnel), .clear)
        XCTAssertEqual(meeting(along, .tunnel), .clear)
        // Along the track, a bank or a cutting, or a platform: none.
        XCTAssertEqual(meeting(along, .surface), .blocked)
        XCTAssertEqual(meeting(across, .embankment), .blocked)
        XCTAssertEqual(meeting(across, .surface, platform: true), .blocked)
        // Track and its platform crossing the street at one place: a station.
        var station = builder(track: across, kind: .surface)
        station.platformLines = [across]
        let (stationSegments, stationIndex) = station.trackSegments()
        XCTAssertEqual(station.trackMeeting(from: road.0, to: road.1, half: 7.5, segments: stationSegments, index: stationIndex), .blocked)
        // Far off: nothing.
        XCTAssertEqual(meeting([Map3DPoint(-10, 1, 40), Map3DPoint(80, 1, 40)], .surface), .clear)
        // At a slant of under 30°, it runs along it.
        XCTAssertEqual(meeting([Map3DPoint(-20, 1, -8), Map3DPoint(90, 1, 10)], .surface), .blocked)
    }

    func testALevelCrossingLiftsItsStreetOverTheRails() {
        let crossing = Map3DLevelCrossing(point: Map3DPoint(0, 1.2, 0), along: Map3DPoint(1, 0, 0), kind: .tertiary)
        XCTAssertEqual(crossing.rise(x: 0, z: 1, road: 0.3), 1.2 + Map3DLevelCrossing.deckRise - 0.3, accuracy: 1e-5)
        XCTAssertEqual(crossing.rise(x: (crossing.deckHalfLength + crossing.rampEnd) / 2, z: 0, road: 0.3),
                       (1.2 + Map3DLevelCrossing.deckRise - 0.3) / 2, accuracy: 1e-4, "half way down the ramp")
        XCTAssertEqual(crossing.rise(x: 14, z: 0, road: 0.3), 0)
        XCTAssertEqual(crossing.rise(x: 0, z: 30, road: 0.3), 0, "beside the street")
    }

    /// Decision 267 (#712–#754's review): at a slant, the deck still covers
    /// the bed, and the barriers stand clear of it.
    func testASlantingCrossingCoversTheBedAndKeepsItsBarriersOffIt() {
        let bedHalf = Map3DScene.Builder.bedBottom / 2
        for degrees: Float in [48, 60, 90, 120, 138] {
            let angle = degrees * .pi / 180
            let track = Map3DPoint(cosf(angle), 0, sinf(angle))
            for spread: Float in [0, 4] {
                let crossing = Map3DLevelCrossing(point: .zero, along: Map3DPoint(1, 0, 0), kind: .tertiary, trackWay: track, spread: spread)
                let normal = Map3DPoint(-track.z, 0, track.x)
                // The deck reaches past the bed (and every track) across the
                // track.
                XCTAssertGreaterThanOrEqual(crossing.deckHalfLength * crossing.crossingSine, bedHalf + spread / 2 * crossing.crossingSine - 0.01,
                                            "\(degrees)°")
                for end: Float in [-1, 1] {
                    let edge = -end * (Map3DBaseMap.RoadKind.tertiary.width(ramp: false) / 2 + 0.6)
                    let foot = crossing.spot(end: end, fromTrack: Map3DLevelCrossing.barrier, fromMiddle: edge)
                    // On the road's edge line, and clear of the bed.
                    XCTAssertEqual(foot.dot(Map3DPoint(0, 0, 1)), edge, accuracy: 1e-3, "\(degrees)°")
                    XCTAssertGreaterThan(abs(foot.dot(normal)), bedHalf + spread / 2 + 1, "\(degrees)° end \(end)")
                }
            }
        }
    }

    // MARK: - Two towns and a line

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    func testATownsStreetsKeepOffTheTrackButWhereTheyCrossIt() throws {
        let world = try lineBetweenTwoTowns()
        let scene = Map3DScene(world: world)
        let navy = Set([Map3DBaseMap.RoadKind.primary, .tertiary, .minor].map(Map3DPalette.road))
        let roads = scene.chunks.flatMap(\.mesh.vertices).filter { navy.contains($0.color) }
        XCTAssertGreaterThan(roads.count, 1_000)
        // No street within a few metres of the track's middle, but on a
        // level crossing's deck, which stands over the rails.
        var rails: [Map3DPoint] = []
        for alignment in world.railwaySnapshot().edges {
            let length = alignment.geometry.length
            for step in stride(from: 0, through: length, by: 8 * Int(WorldCoordinate.unitsPerMetre)) {
                rails.append(scene.point(alignment.geometry.location(at: step).position))
            }
        }
        XCTAssertFalse(scene.levelCrossings.isEmpty, "the line crosses a town's streets")
        // None at a station: its platforms keep the streets off.
        for platform in world.railwaySnapshot().platforms where platform.points.count > 1 {
            let middle = scene.point(platform.points[platform.points.count / 2])
            XCTAssertFalse(scene.levelCrossings.contains { abs($0.point.x - middle.x) < 40 && abs($0.point.z - middle.z) < 40 }, "a crossing at a station")
        }
        // Only the decks and their ramps themselves are let off.
        func onCrossing(_ vertex: Map3DVertex) -> Bool {
            scene.levelCrossings.contains { crossing in
                let dx = vertex.x - crossing.point.x, dz = vertex.z - crossing.point.z
                let along = abs(dx * crossing.along.x + dz * crossing.along.z), side = abs(dx * crossing.along.z - dz * crossing.along.x)
                return along <= crossing.rampEnd + 0.5 && side <= crossing.halfWidth + 0.5
            }
        }
        for vertex in roads where !onCrossing(vertex) {
            XCTAssertFalse(rails.contains { abs($0.x - vertex.x) < 2 && abs($0.z - vertex.z) < 2 && abs($0.y - vertex.y) < 3 },
                           "a street on the track at \(vertex.x), \(vertex.z)")
        }
        // The same every time.
        XCTAssertEqual(Map3DScene(world: world).chunks.map(\.mesh.vertices), scene.chunks.map(\.mesh.vertices))
    }

    /// On a map not of the real world, no seeded street runs under a
    /// station's building; it ends at the building's ground.
    func testNoStreetRunsUnderAStationsBuilding() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        // Lines along a row (or a column) of cells, through a town, some
        // metres off its edge, so a street runs where the building would
        // stand, and a slanting line between two towns.
        let metre = WorldCoordinate.unitsPerMetre, cell = Land.cellLength
        let row = (towns[0].y / cell) * cell, column = (towns[0].x / cell) * cell
        var lines: [[PlanPoint]] = [[towns[0], towns[1]]]
        for off in [Int64(-10), 6, 22] {
            lines.append([PlanPoint(x: towns[0].x - 150 * metre, y: row + off * metre), PlanPoint(x: towns[0].x + 150 * metre, y: row + off * metre)])
        }
        lines.append([PlanPoint(x: column - 10 * metre, y: towns[0].y - 150 * metre), PlanPoint(x: column - 10 * metre, y: towns[0].y + 150 * metre)])
        for points in lines {
            let world = try newGameLine(through: points)
            let scene = Map3DScene(world: world)
            // Where the buildings stand: their placing reads only the
            // ground, the track and the platforms.
            var builder = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: world, heights: nil)
            let snapshot = world.railwaySnapshot()
            builder.addGround()
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            _ = builder.addStations(snapshot, frame: nil)
            XCTAssertFalse(builder.houseFootprints.isEmpty, "the stations have buildings")
            let navy = Set([Map3DBaseMap.RoadKind.primary, .tertiary, .minor].map(Map3DPalette.road))
            let roads = scene.chunks.flatMap(\.mesh.vertices).filter { navy.contains($0.color) }
            XCTAssertGreaterThan(roads.count, 1_000)
            for corners in builder.houseFootprints {
                let middle = corners.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * 0.25
                let forward = try XCTUnwrap((corners[1] - corners[0]).normalized), side = try XCTUnwrap((corners[3] - corners[0]).normalized)
                let depth = (corners[1] - corners[0]).length / 2, wide = (corners[3] - corners[0]).length / 2
                let under = roads.filter { vertex in
                    let d = Map3DPoint(vertex.x - middle.x, 0, vertex.z - middle.z)
                    return abs(d.dot(forward)) < depth && abs(d.dot(side)) < wide
                }
                XCTAssertTrue(under.isEmpty, "\(under.count) street vertices under the building at \(middle.x), \(middle.z)")
            }
        }
    }

    func testRowHousesFaceTheirStreets() {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        XCTAssertNil(builder.streetFronts(column: 0, row: 0), "no seeded streets: as before")
        builder.streetEdges = [Map3DSeededStreets.Edge(horizontal: true, line: 0, along: 0): .primary,
                               Map3DSeededStreets.Edge(horizontal: false, line: 1, along: 0): .minor]
        let fronts = builder.streetFronts(column: 0, row: 0)
        // North on a main road: its pavement reaches 4.5 + 3 m from the
        // line; the south has no street.
        XCTAssertEqual(fronts?.north ?? 0, 32 - 7.5 - 0.3, accuracy: 1e-4)
        XCTAssertNil(fronts?.south)
        XCTAssertEqual(fronts?.east ?? 0, 32 - 2.5 - 0.3, accuracy: 1e-4, "a lane's half width")
        XCTAssertEqual(fronts?.west ?? 0, -32 + 2, accuracy: 1e-4)
    }
}
