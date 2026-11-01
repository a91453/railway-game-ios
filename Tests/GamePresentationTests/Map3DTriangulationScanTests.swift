import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

final class Map3DTriangulationScanTests: XCTestCase {
    func testScanFootprints() throws {
        guard ProcessInfo.processInfo.environment["TRI_SCAN"] != nil else { throw XCTSkip("TRI_SCAN") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tiles = try FootprintTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
        func tx(_ lon: Double) -> Int { Int((lon + 180) / 360 * 65536) }
        func ty(_ lat: Double) -> Int { let r = lat * .pi / 180; return Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * 65536) }
        var buildings = 0, bad = 0, transportBad = 0
        var worst: [(ratio: Double, x: Int, y: Int, use: Int, rings: Int, pts: Int, net: Double)] = []
        let geo = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/track_stations.geojson"))) as! [String: Any]
        var keys = Set<[Int]>()
        for f in geo["features"] as! [[String: Any]] {
            let c = (f["geometry"] as! [String: Any])["coordinates"] as! [Double]
            for dy in -1...1 { for dx in -1...1 { keys.insert([tx(c[0]) + dx, ty(c[1]) + dy]) } }
        }
        print("SCAN tiles", keys.count, "chuoshui", tx(120.704726), ty(23.834496))
        for key in keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let x = key[0], y = key[1]
            do {
                guard let bytes = try? tiles.archive.tile(zoom: 16, x: x, y: y), let decoded = try? Map3DFootprints.decode(bytes) else { continue }
                for b in decoded {
                    buildings += 1
                    let rings = b.rings.map { $0.map { (x: Double($0.x), y: Double($0.y)) } }
                    let pts = rings.flatMap { $0 }
                    func area(_ r: [(x: Double, y: Double)]) -> Double {
                        var s = 0.0; var p = r.last!
                        for q in r { s += p.x * q.y - q.x * p.y; p = q }
                        return s / 2
                    }
                    guard let outer = rings.first, outer.count >= 3 else { continue }
                    let net = abs(area(outer)) - rings.dropFirst().reduce(0) { $0 + abs(area($1)) }
                    let t = Earcut.triangulate(rings)
                    var sum = 0.0
                    for i in stride(from: 0, to: t.count, by: 3) {
                        let a = pts[t[i]], bb = pts[t[i + 1]], c = pts[t[i + 2]]
                        sum += abs((bb.x - a.x) * (c.y - a.y) - (c.x - a.x) * (bb.y - a.y)) / 2
                    }
                    if sum > net * 1.02 + 4 {
                        bad += 1
                        if b.use == 13 { transportBad += 1 }
                        worst.append((sum / max(net, 1), x, y, b.use, rings.count, pts.count, net))
                        if abs(x - tx(120.704726)) <= 1 && abs(y - ty(23.834496)) <= 1 { print("SCAN CHUOSHUI", x, y, b.use, b.storeys, b.rings) }
                    }
                }
            }
        }
        worst.sort { $0.ratio > $1.ratio }
        print("SCAN buildings \(buildings) bad \(bad) transport \(transportBad)")
        for w in worst.prefix(40) { print("SCAN", w) }
    }
}

extension Map3DTriangulationScanTests {
    func testScanSceneAtChuoshui() throws {
        guard ProcessInfo.processInfo.environment["TRI_SCAN"] != nil else { throw XCTSkip("TRI_SCAN") }
        let resources = Map3DRealTrainsTests.resources
        let world = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, land: [])
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city"))
        let temples = try RealTemples(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_temples.json")))
        let railways = try XCTUnwrap(Map3DRealTrainsTests.railways)
        let at = frame.worldPosition(latitude: 23.834496, longitude: 120.704726)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let half = Map3DScene.reach * Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: origin.x - half, minY: origin.y - half, maxX: origin.x + half, maxY: origin.y + half)
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), frame: (region, origin.x, origin.y),
                               baseMap: tiles, cityTiles: city, footprints: footprints, heights: heights, lineBands: nil, railways: railways, temples: temples)
        var byColor: [UInt32: (count: Int, longest: Float, at: Map3DPoint)] = [:]
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.farWithBoxes, chunk.close, chunk.standIn, chunk.shadows] {
                let v = mesh.vertices
                for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                    let a = v[Int(mesh.indices[i])], b = v[Int(mesh.indices[i + 1])], c = v[Int(mesh.indices[i + 2])]
                    let pa = a.position, pb = b.position, pc = c.position
                    let longest = max((pb - pa).length, (pc - pb).length, (pa - pc).length)
                    guard longest > 40 else { continue }
                    let mid = Map3DPoint((pa.x + pb.x + pc.x) / 3, (pa.y + pb.y + pc.y) / 3, (pa.z + pb.z + pc.z) / 3)
                    let triArea = (pb - pa).cross(pc - pa).length / 2
                    if [0xffbcbfc0, 0xffc2cbcf, 0xffc6c9cb].contains(a.color) && longest > 60 { print(triArea, "NEAR", String(a.color, radix: 16), a.layer, pa, pb, pc, "chunk", chunk.column, chunk.row) }
                    let old = byColor[a.color]
                    if old == nil || longest > old!.longest { byColor[a.color] = ((old?.count ?? 0) + 1, longest, mid) } else { byColor[a.color]!.count += 1 }
                }
            }
        }
        for (color, e) in byColor.sorted(by: { $0.value.longest > $1.value.longest }) {
            print("SCENE", String(color, radix: 16), e.count, e.longest, e.at)
        }
    }
}

extension Map3DTriangulationScanTests {
    @MainActor
    func testScanDemoAtChuoshui() async throws {
        guard ProcessInfo.processInfo.environment["TRI_SCAN"] != nil else { throw XCTSkip("TRI_SCAN") }
        let name = ProcessInfo.processInfo.environment["TRI_STATION"] ?? "濁水"
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let tra = try BundledRealData.station(name, in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        try world.mapGround()
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        let heights = try HeightGrid(data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat")))
        session.heights = heights
        session.railways = try BundledRealData.railways()
        session.news.isDemo = true
        let centre = try BundledRealData.point(tra.coordinate, in: world)
        let x = Double(centre.x), y = Double(centre.y), reach = Double(ProcessInfo.processInfo.environment["TRI_REACH"] ?? "5000")! * metre
        let skip = ProcessInfo.processInfo.environment["TRI_EMPTY"] != nil
        let laid = skip ? nil : await session.layDemoRealLines(in: WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach))
        print("LAID", laid as Any, session.message as Any, session.world.network.edges.count, session.world.network.platforms.count)
        let resources = Map3DRealTrainsTests.resources
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let scene = Map3DScene(world: session.world, focus: (x, y), baseMap: tiles, footprints: footprints, heights: heights, railways: session.railways)
        print("ORIGIN", scene.originX - x, scene.originY - y)
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.farWithBoxes, chunk.close, chunk.standIn, chunk.shadows] {
                let v = mesh.vertices
                for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                    let a = v[Int(mesh.indices[i])], b = v[Int(mesh.indices[i + 1])], c = v[Int(mesh.indices[i + 2])]
                    let pa = a.position, pb = b.position, pc = c.position
                    let longest = max((pb - pa).length, (pc - pb).length, (pa - pc).length)
                    let mid = Map3DPoint((pa.x + pb.x + pc.x) / 3, (pa.y + pb.y + pc.y) / 3, (pa.z + pb.z + pc.z) / 3)
                    guard longest > 50 else { continue }
                    print("DEMO", String(a.color, radix: 16), a.layer, Int(longest), Int(mid.x / 50) * 50, Int(mid.z / 50) * 50, pa, pb, pc)
                }
            }
        }
    }
}

extension Map3DTriangulationScanTests {
    @MainActor
    func testScanBoughtJiji() throws {
        guard ProcessInfo.processInfo.environment["TRI_SCAN"] != nil else { throw XCTSkip("TRI_SCAN") }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let resources = Map3DRealTrainsTests.resources
        let baseMap = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
        var world = try HighSpeedDemo.make(in: .traditionalChinese, railways: railways, population: data.population, places: data.places,
                                           water: data.water, coverage: data.coverage, heights: data.heights)
        world = GameLauncher.readingRoads(of: world, baseMap: baseMap)
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population; session.places = data.places; session.water = data.water
        session.heights = data.heights; session.coverage = data.coverage; session.baseMap = baseMap; session.railways = railways
        session.readLandRoundStations()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == "JIJI" }, "\(session.buyableRealLines.map(\.network))")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let bought = session.world
        print("BOUGHT", bought.network.edges.count, bought.network.platforms.count, bought.stations.count)
        let name = ProcessInfo.processInfo.environment["TRI_STATION"] ?? "濁水"
        let station = try BundledRealData.station(name, in: "tra_sched")
        let centre = try BundledRealData.point(station.coordinate, in: bought)
        let x = Double(centre.x), y = Double(centre.y)
        let scene = Map3DScene(world: bought, snapshot: bought.railwaySnapshot(), skyline: CitySkyline(world: bought), focus: (x, y), baseMap: baseMap,
                               footprints: footprints, heights: data.heights, railways: railways)
        print("ORIGIN", scene.originX - x, scene.originY - y)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var onTrack = Set<[Int]>()
        for edge in bought.railwaySnapshot().edges {
            for p in edge.geometry.points {
                let sx = (Double(p.x) - scene.originX) / metre, sz = (Double(p.y) - scene.originY) / metre
                guard abs(sx) < 2000, abs(sz) < 2000 else { continue }
                onTrack.insert([Int((sx / 4).rounded()), Int((sz / 4).rounded())])
            }
        }
        func near(_ p: Map3DPoint) -> Bool {
            let cx = Int((p.x / 4).rounded()), cz = Int((p.z / 4).rounded())
            for dx in -3...3 { for dz in -3...3 where onTrack.contains([cx + dx, cz + dz]) { return true } }
            return false
        }
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.farWithBoxes, chunk.close, chunk.standIn] {
                let v = mesh.vertices
                for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                    let ps = [v[Int(mesh.indices[i])].position, v[Int(mesh.indices[i + 1])].position, v[Int(mesh.indices[i + 2])].position]
                    let nears = ps.map(near)
                    guard nears.contains(true), nears.contains(false) else { continue }
                    let longest = max((ps[1] - ps[0]).length, (ps[2] - ps[1]).length, (ps[0] - ps[2]).length)
                    guard longest > 40 else { continue }
                    let a = v[Int(mesh.indices[i])]
                    print("SPIKE", String(a.color, radix: 16), a.layer, Int(longest), ps[0], ps[1], ps[2])
                }
            }
        }
        for chunk in [Map3DScene.Chunk]() {
            for mesh in [chunk.mesh] {
                let v = mesh.vertices
                for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                    let a = v[Int(mesh.indices[i])], b = v[Int(mesh.indices[i + 1])], c = v[Int(mesh.indices[i + 2])]
                    let pa = a.position, pb = b.position, pc = c.position
                    let longest = max((pb - pa).length, (pc - pb).length, (pa - pc).length)
                    let mid = Map3DPoint((pa.x + pb.x + pc.x) / 3, (pa.y + pb.y + pc.y) / 3, (pa.z + pb.z + pc.z) / 3)
                    guard longest > 40, abs(mid.x) < 1500, abs(mid.z) < 1500 else { continue }
                    print("JIJI", String(a.color, radix: 16), a.layer, Int(longest), pa, pb, pc)
                }
            }
        }
    }
}
