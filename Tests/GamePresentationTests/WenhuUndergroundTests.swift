import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 678: the Wenhu Line's real tunnel, from north of Zhongshan
/// Junior High School under Songshan Airport and the Keelung River to
/// south of Jiannan Road (3.8 km, `rail_structures.json`), with Songshan
/// Airport and Dazhi stations in it. Bought on the Taipei opening (which
/// reads the water and the heights, as a player's game does), both
/// stations were laid on the ground and the river crossed on a bridge 5 m
/// over the water, below the banks either side: a trench across the river
/// in the 3D map (the owner's screenshot of 2026-11-09, decision 672's
/// next step).
@MainActor
final class WenhuUndergroundTests: XCTestCase {
    struct Laid {
        let world: GameWorld
        let path: WorldPath
        let carried: [TrackRise.Carried]
        /// The main track's points (not the depots'), each with its
        /// section's kind.
        let points: [(point: WorldVector, z: Double, kind: TrackSectionKind)]
        let heights: HeightGrid?
    }

    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The line bought on the Taipei opening, built on a pricing copy as
    /// ``LineHeightReportTests`` builds it.
    ///
    /// `centred`: on a map with its middle on the line instead (the
    /// screenshot scene's, ``ScreenshotScene/wenhu``): the same ground and
    /// water sampled from another origin, where the first fix still left
    /// Songshan Airport in a cutting and 80 m open on the river's bank.
    static func laid(centred: Bool = false) throws -> Laid {
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let world: GameWorld
        if centred {
            world = try XCTUnwrap(data.water.map { ScreenshotScene.wenhu.make(in: .traditionalChinese, water: $0) })
        } else {
            let city = try XCTUnwrap(AcquisitionReportTests.cities.first { $0.name == "Taipei" })
            let start = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
            world = GameLauncher.newWorld(at: start, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
            ))
        }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.coverage = data.coverage
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "on sale")
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        var built = session.world.pricingCopy()
        _ = try session.buildStepByStep(acquisition, in: &built, recording: false)
        let frame = try XCTUnwrap(RealWorldFrame(world: built))
        let path = WorldPath(acquisition.pieces[0].nodes.map { WorldVector(x: Double($0.x), y: Double($0.y)) })
        let carried = try XCTUnwrap(railways.structures).stretches(along: path, frame: frame, system: line.system)
        let depotIDs = Set(built.stations.filter(\.isDepot).map(\.id))
        let depotEdges = Set(built.network.platforms.filter { depotIDs.contains($0.station) }.map(\.edge))
        var points: [(point: WorldVector, z: Double, kind: TrackSectionKind)] = []
        for edge in built.network.edges where !depotEdges.contains(edge.id) {
            let geometry = try XCTUnwrap(built.trackGeometry(of: edge.id))
            for span in edge.sectionSpans where span.end > span.start {
                for point in geometry.points(from: span.start, to: span.end) {
                    points.append((WorldVector(x: Double(point.x), y: Double(point.y)), Double(point.z), span.kind))
                }
            }
        }
        return Laid(world: built, path: path, carried: carried, points: points, heights: data.heights)
    }

    func testTheRealTunnelIsATunnelAndItsStationsAreUnderground() throws {
        try theRealTunnelIsATunnel(try Self.laid())
    }

    func testTheRealTunnelIsATunnelOnAMapCentredOnTheLine() throws {
        try theRealTunnelIsATunnel(try Self.laid(centred: true))
    }

    private func theRealTunnelIsATunnel(_ laid: Laid) throws {
        let world = laid.world, metre = Self.metre
        func ground(at point: WorldVector) -> Double {
            Double(world.groundHeight(at: PlanPoint(x: Int64(point.x.rounded()), y: Int64(point.y.rounded()))) ?? 0)
        }
        // The real tunnel: one, some 3.8 km long.
        let tunnel = try XCTUnwrap(laid.carried.first { $0.kind == .tunnel && $0.length > 3_000 * metre }, "the real tunnel under the airport")

        // Both stations in it: every platform in a tunnel, under the ground.
        var between: [Double] = []
        for name in ["松山機場", "大直"] {
            let station = try XCTUnwrap(world.stations.first { $0.name == name }, name)
            let at = laid.path.nearest(WorldVector(station.location)).along
            XCTAssertTrue(tunnel.range.contains(at), "\(name) is in the real tunnel")
            between.append(at)
            let platforms = world.network.platforms(of: station.id)
            XCTAssertFalse(platforms.isEmpty, name)
            for platform in platforms {
                let edge = try XCTUnwrap(world.network.edge(platform.edge))
                let geometry = try XCTUnwrap(world.trackGeometry(of: platform.edge))
                let middle = (platform.start + platform.end) / 2
                let kind = edge.sectionSpans.first { $0.start <= middle && middle <= $0.end }?.kind
                let point = try XCTUnwrap(geometry.points(from: middle, to: min(middle + 1, geometry.length)).first)
                let over = (Double(point.z) - ground(at: WorldVector(x: Double(point.x), y: Double(point.y)))) / metre
                XCTAssertEqual(kind, .tunnel, "\(name)'s platform is \(kind?.rawValue ?? "?"), \(over) m from the ground")
                XCTAssertLessThan(over, -11, "\(name)'s platform")
            }
        }

        // The track: a tunnel from one station to the other, under the
        // river; and nowhere along the real tunnel a bridge or a viaduct.
        func kind(at distance: Double) throws -> (kind: TrackSectionKind, over: Double) {
            let point = laid.path.point(at: distance)
            let nearest = try XCTUnwrap(laid.points.min { ($0.point - point).length < ($1.point - point).length })
            return (nearest.kind, (nearest.z - ground(at: nearest.point)) / metre)
        }
        var open: [String] = [], over: [String] = [], inTunnel = 0, samples = 0
        for distance in stride(from: tunnel.range.lowerBound, through: tunnel.range.upperBound, by: 32 * metre) {
            let here = try kind(at: distance)
            samples += 1
            if here.kind == .tunnel { inTunnel += 1 }
            let label = "\(Int(distance / metre)) m \(here.kind.rawValue) \(String(format: "%.1f", here.over))"
            if (between[0]...between[1]).contains(distance), here.kind != .tunnel { open.append(label) }
            if here.kind == .bridge || here.kind == .viaduct { over.append(label) }
        }
        XCTAssertEqual(open, [], "open to the sky between Songshan Airport and Dazhi")
        XCTAssertEqual(over, [], "over the ground along the real tunnel")
        // The rest is the two ramps down from the viaducts, a cutting
        // until the game's tunnels begin 11 m down.
        XCTAssertGreaterThan(Double(inTunnel) / Double(samples), 0.8, "\(inTunnel) of \(samples) samples of the real tunnel in a tunnel")
    }

    /// In the 3D map: from Songshan Airport to Dazhi the ground (the
    /// river's bed with it) covers the bore, so nothing is cut away along
    /// it (decisions 375 and 672 cut the ground over a trench and over a
    /// bore it does not cover: the trench across the river); and the two
    /// stations' platforms are the underground ones seeing underground
    /// draws (decision 672).
    func testThe3DMapCutsNoTrenchOverTheTunnel() throws {
        let laid = try Self.laid()
        let world = laid.world
        let stations = try ["松山機場", "大直"].map { name in try XCTUnwrap(world.stations.first { $0.name == name }, name) }
        let ends = stations.map { laid.path.nearest(WorldVector($0.location)).along }
        let middle = laid.path.point(at: (ends[0] + ends[1]) / 2)
        let snapshot = world.railwaySnapshot()
        let scene = Map3DScene(world: world, snapshot: snapshot, focus: (middle.x, middle.y), heights: laid.heights)

        var checked = 0
        for sample in laid.points {
            let along = laid.path.nearest(sample.point)
            guard along.away < 20 * Self.metre, (ends[0]...ends[1]).contains(along.along) else { continue }
            let rail = scene.point(worldX: sample.point.x, worldY: sample.point.y, height: sample.z) + Map3DScene.Builder.lifted
            let ground = try XCTUnwrap(scene.trackCover.ground(at: rail), "\(Int(along.along / Self.metre)) m")
            XCTAssertTrue(ground.inTunnel, "\(Int(along.along / Self.metre)) m")
            XCTAssertGreaterThanOrEqual(
                ground.height - rail.y, Map3DScene.Builder.boreCrown + Map3DScene.Builder.coverThickness,
                "the ground covers the bore \(Int(along.along / Self.metre)) m along"
            )
            XCTAssertNil(
                scene.trackCover.trenches.piece(at: Map3DBaseMap.Point(x: Double(rail.x), z: Double(rail.z))),
                "the ground is cut away \(Int(along.along / Self.metre)) m along"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)

        let platforms = Map3DXRay.platforms(snapshot, in: scene)
        for station in stations {
            let own = platforms.filter { $0.station == station.id }
            XCTAssertFalse(own.isEmpty, "\(station.name)'s underground platforms")
            for platform in own {
                let at = platform.line[platform.line.count / 2]
                let ground = try XCTUnwrap(scene.trackCover.ground(at: at), station.name)
                XCTAssertGreaterThan(ground.height - at.y, 0, station.name)
                XCTAssertLessThanOrEqual(ground.height - at.y, Map3DXRay.deepest, station.name)
            }
        }
    }
}
