import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// What each map's 3D scene costs, counted without a screen: how long it
/// takes to build and which steps, what each layer adds in triangles, what
/// it holds in buffers, and what a frame draws of it (draw calls and
/// triangles, as ``Map3DMetalView/draw`` shares them out) from near to the
/// farthest view. A report, not a check: only with `MAP3D_LOAD_MAP`.
///
///     MAP3D_LOAD_MAP=hongkong MAP3D_LOAD_BUY=all \
///         swift test -c release -Xswiftc -enable-testing --filter Map3DMapLoadReportTests
///
/// `MAP3D_LOAD_MAP`: `taiwan`, `hongkong`, `rovaniemi`, `fukuoka`, or `save`
/// with `MAP3D_LOAD_SAVE` naming a player's save file.
/// `MAP3D_LOAD_BUY`: `all`, or the ids' prefixes to buy (`trtc:,tymc:`).
/// `MAP3D_LOAD_AT`: `name:latitude:longitude;…` instead of the map's own
/// places. `MAP3D_LOAD_RUNS`: how many times each scene is built.
@MainActor
final class Map3DMapLoadReportTests: XCTestCase {
    func testReport() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let map = environment["MAP3D_LOAD_MAP"] else { throw XCTSkip("set MAP3D_LOAD_MAP") }
        let clock = ContinuousClock()
        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        }
        let session: GameSession
        var places: [(name: String, latitude: Double, longitude: Double)]
        switch map {
        case "hongkong":
            session = try TimetableCheckupAllBoughtTests.hongKong(rules: .realistic)
            places = [("Central", 22.2819, 114.1582), ("Mong Kok", 22.3193, 114.1694), ("Tsing Yi", 22.3585, 114.1077),
                      ("Tsing Ma Bridge", 22.3513, 114.0742), ("Tung Chung", 22.2893, 113.9414)]
        case "rovaniemi":
            session = try TimetableCheckupAllBoughtTests.rovaniemi(rules: .realistic)
            places = [("Rovaniemi station", 66.4977, 25.7143)]
        case "fukuoka":
            session = try FukuokaRailwaysTests.fukuoka()
            places = [("Tenjin", 33.5914, 130.3989), ("Hakata", 33.5897, 130.4207)]
        case "save":
            // A player's own save (never in the repository), round its
            // busiest station: the one with the most others within 3 km.
            struct File: Decodable { let game: SavedGame }
            let path = try XCTUnwrap(environment["MAP3D_LOAD_SAVE"], "MAP3D_LOAD_SAVE names the save")
            let world = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path))).game.world
            session = GameSession(world: world, language: .traditionalChinese)
            session.railways = try BundledRealData.railways()
            session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
            let frame = try XCTUnwrap(RealWorldFrame(world: world)), near = 3_000 * Double(WorldCoordinate.unitsPerMetre)
            let stations = world.stations.map { (x: Double($0.point.x), y: Double($0.point.y)) }
            let busiest = try XCTUnwrap(stations.max { a, b in
                stations.filter { abs($0.x - a.x) < near && abs($0.y - a.y) < near }.count
                    < stations.filter { abs($0.x - b.x) < near && abs($0.y - b.y) < near }.count
            })
            let at = frame.coordinate(worldX: busiest.x, worldY: busiest.y)
            places = [("the busiest station", at.latitude, at.longitude)]
        default:
            session = try TimetableCheckupAllBoughtTests.wholeTaiwan(rules: .realistic)
            places = [("Taipei Main Station", 25.0478, 121.5170), ("Banqiao", 25.0143, 121.4627), ("Kaohsiung", 22.6394, 120.3024),
                      ("Miaoli", 24.5701, 120.8224)]
        }
        if let given = environment["MAP3D_LOAD_AT"] {
            places = given.split(separator: ";").compactMap { part in
                let fields = part.split(separator: ":")
                guard fields.count == 3, let latitude = Double(fields[1]), let longitude = Double(fields[2]) else { return nil }
                return (String(fields[0]), latitude, longitude)
            }
        }
        if let buy = environment["MAP3D_LOAD_BUY"] {
            let prefixes = buy == "all" ? nil : buy.split(separator: ",").map(String.init)
            let began = clock.now
            var bought: [String] = []
            var refused: Set<String> = []
            while let next = session.buyableRealLines.sorted(by: { $0.id < $1.id }).first(where: { line in
                !refused.contains(line.id) && (prefixes?.contains { line.id.hasPrefix($0) } ?? true)
            }) {
                if session.acquireRealLine(session.realLineOffer(for: next)) { bought.append(next.id) } else { refused.insert(next.id) }
            }
            print("MAP3D-LOAD bought \(bought.count) lines in \(String(format: "%.1f", seconds(clock.now - began))) s: \(bought.joined(separator: " "))"
                + (refused.isEmpty ? "" : "; refused \(refused.sorted().joined(separator: " "))"))
        }
        let world = session.world

        // What the app reads (`Map3DSceneCache.task`), from the same files.
        let resources = Map3DRealTrainsTests.resources, base = resources.appendingPathComponent("BaseMap")
        let overseas = OverseasMap.allCases.filter { OverseasMaps.open.contains($0) || $0.packFolder == map }
        let cities = overseas.compactMap { city in HongKongRailwaysTests.pack(city).map { (city, $0) } }
        let packs = cities.map(\.1)
        let grounds = cities.compactMap { try? OverseasGround(city: $0.0, pack: $0.1) }
        let ground = grounds.first { $0.holds(world) }
        let tiles = try BaseMapTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped),
                                     cities: grounds.compactMap(\.baseMap))
        let city = CityTileArea.areas(in: base.appendingPathComponent("city"))
        let footprints = try FootprintTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped),
                                            cities: packs.compactMap(\.buildingsFile).compactMap { try? Data(contentsOf: $0, options: .alwaysMapped) })
        let heights = try session.heights ?? ground?.heights ?? HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let landCover = try ground?.landCover ?? LandCoverGrid(data: RealWorldDataLoadTests.file("taiwan_landcover", "dat"))
        let temples = try RealTemples(data: Data(contentsOf: base.appendingPathComponent("taiwan_temples.json")))
        var land = try RealNoBuildLand(data: RealWorldDataLoadTests.file("taiwan_no_build", "json"))
        land.airfields = try RealAirfields(data: Data(contentsOf: base.appendingPathComponent("taiwan_airfields.json")))
        for pack in packs {
            if let own = pack.noBuildLand(airfields: true) { land = land.adding(own) }
        }
        let railways = session.railways
        let snapshot = world.railwaySnapshot(), skyline = CitySkyline(world: world)
        let bands = Map3DLineBands(world: world, palette: .standard)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let pack = Map3DModelPack.standard
        print("MAP3D-LOAD \(map): \(world.stations.count) stations, \(world.network.edges.count) edges, \(world.trains.count) trains")
        let runs = max(1, Int(environment["MAP3D_LOAD_RUNS"] ?? "") ?? 1)
        let metre = Double(WorldCoordinate.unitsPerMetre)

        for place in places {
            let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
            let focus = (x: at.x, y: at.y)
            var scene: Map3DScene!
            var times: [Double] = []
            for _ in 1...runs {
                let began = clock.now
                scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: focus, baseMap: tiles, cityTiles: city,
                                   footprints: footprints, heights: heights, landCover: landCover, lineBands: bands, railways: railways,
                                   temples: temples, noBuild: land)
                times.append(seconds(clock.now - began))
            }
            print("MAP3D-LOAD == \(place.name): \(scene.chunks.count) chunks, \(scene.triangleCount) triangles, built in "
                + times.map { String(format: "%.2f", $0) }.joined(separator: " / ") + " s")
            var summed: [(step: String, seconds: Double)] = []
            for (step, time) in scene.steps {
                if let index = summed.firstIndex(where: { $0.step == step }) { summed[index].seconds += time } else { summed.append((step, time)) }
            }
            let took = times.last ?? 1
            for (step, time) in summed.sorted(by: { $0.seconds > $1.seconds }).prefix(10) where time >= 0.01 {
                print("MAP3D-LOAD   step \(String(format: "%6.2f", time)) s \(String(format: "%4.1f", 100 * time / took)) %  \(step)")
            }
            for layer in scene.layers.sorted(by: { $0.base + $0.near + $0.far + $0.boxes + $0.close + $0.shadows
                    > $1.base + $1.near + $1.far + $1.boxes + $1.close + $1.shadows }) {
                print("MAP3D-LOAD   layer \(layer.layer): base \(layer.base) near \(layer.near) far \(layer.far) boxes \(layer.boxes) "
                    + "close \(layer.close) shadows \(layer.shadows)")
            }

            // What it holds: the buffers the Metal view makes of it.
            var bytes = (mesh: 0, far: 0, boxes: 0, close: 0, standIn: 0, shadows: 0, facade: 0, props: 0, signs: 0)
            var buffers = 0, slack = 0, full = 0
            func buffer(_ length: Int) -> Int {
                guard length > 0 else { return 0 }
                buffers += 1
                // A buffer takes whole pages (16 KB on an iPhone).
                slack += (length + 16_383) / 16_384 * 16_384 - length
                return length
            }
            let stride = MemoryLayout<Map3DVertex>.stride
            for chunk in scene.chunks {
                if !chunk.coarse { full += 1 }
                bytes.mesh += buffer(chunk.mesh.vertices.count * stride) + buffer(chunk.mesh.indices.count * 4)
                bytes.far += buffer(chunk.far.vertices.count * stride) + buffer(chunk.far.indices.count * 4)
                bytes.boxes += buffer(chunk.farBoxes.count * 88)
                bytes.close += buffer(chunk.close.vertices.count * stride) + buffer(chunk.close.indices.count * 4)
                bytes.standIn += buffer(chunk.standIn.vertices.count * stride) + buffer(chunk.standIn.indices.count * 4)
                bytes.shadows += buffer(chunk.shadows.vertices.count * stride) + buffer(chunk.shadows.indices.count * 4)
                bytes.facade += chunk.facade.vertices.count * stride + chunk.facade.indices.count * 4
                bytes.props += buffer(chunk.props.count * 80)
                bytes.signs += buffer(chunk.signs.count * 64)
            }
            let held = bytes.mesh + bytes.far + bytes.boxes + bytes.close + bytes.standIn + bytes.shadows + bytes.props + bytes.signs
            func megabytes(_ bytes: Int) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }
            print("MAP3D-LOAD   holds \(megabytes(held)) MB in \(buffers) buffers (\(megabytes(slack)) MB of their last pages unused), "
                + "\(full) of \(scene.chunks.count) chunks in full: mesh \(megabytes(bytes.mesh)) far \(megabytes(bytes.far)) "
                + "boxes \(megabytes(bytes.boxes)) close \(megabytes(bytes.close)) standIn \(megabytes(bytes.standIn)) "
                + "shadows \(megabytes(bytes.shadows)) props \(megabytes(bytes.props)) signs \(megabytes(bytes.signs)); "
                + "street fronts (made when close) \(megabytes(bytes.facade)) MB")
            var vertices = 0, indices = 0, unshared = 0
            for chunk in scene.chunks {
                vertices += chunk.mesh.vertices.count
                indices += chunk.mesh.indices.count
                unshared += Set(chunk.mesh.vertices).count
            }
            print("MAP3D-LOAD   full meshes: \(vertices) vertices for \(indices) indices (\(String(format: "%.2f", Double(indices) / Double(max(vertices, 1)))) "
                + "an index a vertex), \(unshared) of the vertices differ")

            for distance in [120, 300, 800, 1_800, 4_000, 8_000, 12_000] as [Float] {
                for tier in [Map3DDeviceTier.higher] {
                    let camera = Map3DCamera(target: .zero, distance: distance, viewport: (874, 402))
                    let load = Map3DMapLoad.frame(of: scene.chunks, camera: camera, pack: pack, tier: tier)
                    print("MAP3D-LOAD   \(Int(distance)) m: \(load)")
                }
            }

            print("MAP3D-LOAD   digest of the scene \(Map3DMapLoad.digest(scene.chunks))")

            // A block built ahead, as the camera moving builds it: one
            // chunk, and the five by five the streaming asks for at once.
            let streaming = Map3DStreaming(originX: scene.originX, originY: scene.originY, map: WorldRegion(bounds: world.bounds))
            for (name, offset, side) in [("one chunk under the camera", Float(0), 1), ("one chunk 2 km east", 2_000, 1),
                                         ("5 x 5 chunks 3 km east", 3_000, 5), ("5 x 5 chunks 3 km north", -3_000, 5)] {
                let at = side == 5 && offset < 0 ? Map3DPoint(0, 0, offset) : Map3DPoint(abs(offset), 0, 0)
                let middle = streaming.key(of: at)
                let half = side / 2
                let keys = (-half...half).flatMap { row in
                    (-half...half).map { Map3DStreaming.Key(column: middle.column + $0, row: middle.row + row) }
                }
                var blockTimes: [Double] = []
                var built: [Map3DScene.Chunk] = []
                for _ in 1...max(runs, 2) {
                    let began = clock.now
                    built = Map3DScene.chunks(keys, of: streaming, world: world, snapshot: snapshot, skyline: skyline, baseMap: tiles, cityTiles: city,
                                              footprints: footprints, heights: heights, landCover: landCover, lineBands: bands, railways: railways,
                                              temples: temples, noBuild: land, trackCover: scene.trackCover, detail: at)
                    blockTimes.append(seconds(clock.now - began))
                }
                print("MAP3D-LOAD   \(name): " + blockTimes.map { String(format: "%.3f", $0) }.joined(separator: " / ") + " s, "
                    + "\(built.count) chunks, \(built.reduce(0) { $0 + $1.mesh.triangleCount }) triangles in full, digest \(Map3DMapLoad.digest(built))")
                // Where the time goes: the same region built as `chunks` builds it.
                if let box = streaming.region(of: keys) {
                    let apron = Map3DStreaming.apron * metre, map = streaming.map
                    let region = WorldRegion(minX: max(map.minX, box.minX - apron), minY: max(map.minY, box.minY - apron),
                                             maxX: min(map.maxX, box.maxX + apron), maxY: min(map.maxY, box.maxY + apron))
                    let block = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, frame: (region, streaming.originX, streaming.originY),
                                           baseMap: tiles, cityTiles: city, footprints: footprints, heights: heights, landCover: landCover,
                                           lineBands: bands, railways: railways, temples: temples, noBuild: land, trackCover: scene.trackCover,
                                           detail: at, studies: map)
                    var steps: [(step: String, seconds: Double)] = []
                    for (step, time) in block.steps {
                        if let index = steps.firstIndex(where: { $0.step == step }) { steps[index].seconds += time } else { steps.append((step, time)) }
                    }
                    let all = steps.reduce(0) { $0 + $1.seconds }
                    for (step, time) in steps.sorted(by: { $0.seconds > $1.seconds }).prefix(8) where time >= 0.001 {
                        print("MAP3D-LOAD     step \(String(format: "%6.3f", time)) s \(String(format: "%4.1f", 100 * time / max(all, 0.000_001))) %  \(step)")
                    }
                }
            }
        }
    }
}

/// What the Metal view's pass draws of chunks (``Map3DMetalView/draw``):
/// its draw calls and triangles, by what they are.
enum Map3DMapLoad {
    /// A number of everything `chunks` hold, the same for the same
    /// chunks whatever their order (FNV-1a over their meshes' bytes and
    /// the rest as text): two builds that print the same number built
    /// the same.
    static func digest(_ chunks: [Map3DScene.Chunk]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func add(_ word: UInt64) { hash = (hash ^ word) &* 0x100_0000_01b3 }
        func add(_ text: String) { for byte in text.utf8 { add(UInt64(byte)) } }
        func add(_ mesh: Map3DMesh) {
            add(UInt64(mesh.vertices.count))
            add(UInt64(mesh.indices.count))
            mesh.vertices.withUnsafeBytes { bytes in
                for word in bytes.bindMemory(to: UInt32.self) { add(UInt64(word)) }
            }
            for index in mesh.indices { add(UInt64(index)) }
        }
        for chunk in chunks.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            add("\(chunk.column) \(chunk.row) \(chunk.baseIndexCount) \(chunk.coarse) \(chunk.minimum) \(chunk.maximum) \(chunk.cityTops)")
            for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows, chunk.facade] { add(mesh) }
            add("\(chunk.farBoxes)")
            add("\(chunk.props)")
            add("\(chunk.signs)")
            add("\(chunk.baseSteps.counts) \(chunk.farSteps.counts) \(chunk.farBoxSteps.counts) \(chunk.shadowSteps.counts)")
        }
        return String(hash, radix: 16)
    }

    struct Frame: CustomStringConvertible {
        var chunks = 0, detailed = 0, closeUp = 0, simplified = 0, groundOnly = 0, notDrawn = 0
        var draws = (base: 0, far: 0, boxes: 0, close: 0, standIn: 0, shadows: 0, facade: 0, props: 0, signs: 0)
        var triangles = (base: 0, city: 0, far: 0, boxes: 0, close: 0, standIn: 0, shadows: 0, facade: 0, props: 0, signs: 0)
        var allDraws: Int { draws.base + draws.far + draws.boxes + draws.close + draws.standIn + draws.shadows + draws.facade + draws.props + draws.signs }
        var allTriangles: Int {
            triangles.base + triangles.city + triangles.far + triangles.boxes + triangles.close + triangles.standIn + triangles.shadows
                + triangles.facade + triangles.props + triangles.signs
        }
        var description: String {
            "\(chunks) chunks (\(detailed) in full, \(closeUp) close up; budget: \(simplified) simplified, \(groundOnly) ground only, \(notDrawn) not drawn) "
                + "\(allDraws) draws \(allTriangles) triangles | draws \(draws) | triangles \(triangles)"
        }
    }

    static func frame(of chunks: [Map3DScene.Chunk], camera: Map3DCamera, pack: Map3DModelPack, tier: Map3DDeviceTier?) -> Frame {
        let matrix = camera.viewProjection
        let level = Map3DFarDetail.level(distance: camera.distance, was: 0)
        struct Seen {
            let chunk: Map3DScene.Chunk
            var detailed: Bool
            var closeUp: Bool
            var fronts: Bool
            let runs: [Map3DPropRuns.Run]
            var share = Map3DSceneBudget.Share.whole
        }
        var seen: [Seen] = []
        for chunk in chunks {
            let detailed = !chunk.coarse && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false)
            let close = !chunk.close.isEmpty
                && camera.drawsClose(minimum: chunk.minimum, maximum: chunk.maximum, detailed: detailed, coarse: chunk.coarse, wasClose: false)
            let fronts = !chunk.facade.isEmpty
                && camera.drawsClose(minimum: chunk.minimum, maximum: chunk.maximum, detailed: detailed, coarse: chunk.coarse, wasClose: false)
            guard Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) else { continue }
            seen.append(Seen(chunk: chunk, detailed: detailed, closeUp: close, fronts: fronts, runs: Map3DPropRuns(chunk.props).runs))
        }
        func cost(_ entry: Seen) -> Map3DSceneBudget.Cost {
            let chunk = entry.chunk, afar = chunk.farLevels[level]
            let ground = afar.base / 3
            let simplified = ground + (chunk.far.isEmpty ? 0 : afar.far / 3) + (chunk.farBoxes.isEmpty ? 0 : afar.boxTriangles)
                + (chunk.shadows.isEmpty ? 0 : afar.shadows / 3)
            guard entry.detailed else { return Map3DSceneBudget.Cost(whole: simplified, simplified: simplified, ground: ground) }
            var whole = chunk.mesh.triangleCount + chunk.standIn.triangleCount + chunk.shadows.triangleCount + 2 * chunk.signs.count
            for run in entry.runs where run.model < pack.models.count { whole += pack.models[run.model].triangleCount * run.count }
            return Map3DSceneBudget.Cost(whole: whole, simplified: simplified, ground: ground)
        }
        let nearestFirst = seen.indices.map { place in
            (place: place, distance: Map3DStreaming.distance(of: Map3DStreaming.Key(column: seen[place].chunk.column, row: seen[place].chunk.row),
                                                             to: camera.target))
        }.sorted { $0.distance < $1.distance }
        let shares = Map3DSceneBudget.shares(of: nearestFirst.map { cost(seen[$0.place]) }, within: Map3DSceneBudget.triangles(tier: tier))
        for (entry, share) in zip(nearestFirst, shares) where share != .whole {
            seen[entry.place].share = share
            seen[entry.place].detailed = false
            seen[entry.place].closeUp = false
            seen[entry.place].fronts = false
        }
        var frame = Frame()
        for entry in seen {
            if entry.share == .nothing { frame.notDrawn += 1; continue }
            if entry.share == .simplified { frame.simplified += 1 }
            if entry.share == .ground { frame.groundOnly += 1 }
            let chunk = entry.chunk, afar = chunk.farLevels[level]
            frame.chunks += 1
            let count = entry.detailed ? chunk.mesh.indices.count : afar.base
            if count > 0 {
                frame.draws.base += 1
                frame.triangles.base += min(count, chunk.baseIndexCount) / 3
                frame.triangles.city += max(0, count - chunk.baseIndexCount) / 3
            }
            if entry.detailed { frame.detailed += 1 }
            if entry.closeUp {
                frame.closeUp += 1
                frame.draws.close += 1
                frame.triangles.close += chunk.close.triangleCount
            }
            if entry.fronts {
                frame.draws.facade += 1
                frame.triangles.facade += chunk.facade.triangleCount
            }
            if entry.detailed, !entry.closeUp, !chunk.standIn.isEmpty {
                frame.draws.standIn += 1
                frame.triangles.standIn += chunk.standIn.triangleCount
            }
            if !entry.detailed, entry.share < .ground, !chunk.far.isEmpty, afar.far > 0 {
                frame.draws.far += 1
                frame.triangles.far += afar.far / 3
            }
            if !entry.detailed, entry.share < .ground, !chunk.farBoxes.isEmpty, afar.boxes > 0 {
                frame.draws.boxes += 1
                frame.triangles.boxes += afar.boxTriangles
            }
            if entry.detailed {
                for run in entry.runs where run.model < pack.models.count {
                    frame.draws.props += 1
                    frame.triangles.props += pack.models[run.model].triangleCount * run.count
                }
                if !chunk.signs.isEmpty {
                    frame.draws.signs += 1
                    frame.triangles.signs += 2 * chunk.signs.count
                }
            }
            if entry.share < .ground, !chunk.shadows.isEmpty {
                let shadows = entry.detailed ? chunk.shadows.indices.count : afar.shadows
                if shadows > 0 {
                    frame.draws.shadows += 1
                    frame.triangles.shadows += shadows / 3
                }
            }
        }
        return frame
    }
}
