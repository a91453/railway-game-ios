import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// model-look's ninth item (「放到地圖上和背景分不開」) as a check: a
/// building's roof, in the colours the 3D map draws it in, must differ in
/// lightness from what the map draws round it, or carry an edge that does.
/// A white roof on the near-white ground passes every other kit test.
///
/// What is measured (`RoofContrast`): the model seen from straight above,
/// as the game's camera sees it from far off, a cell every 0.25 m. Each
/// cell's colour is the vertex colour after ``Map3DLook`` (which families
/// it makes pale is in `families`), under the look's day light
/// (`Map3DShaders.metal`'s `soft`, the sun's side-to-side part averaged
/// out). Not measured: textures, shadows, fog, night.
///
/// `ROOF_CONTRAST_REPORT=<folder>` writes the whole table
/// (`roof-contrast.tsv`; `recipe-roof` and `recipe-edge` are what a model
/// the look makes pale would measure in its recipe's colours) and each
/// station building and landmark as the map
/// draws it (`models/*.m3dmodel`, for `tools/model-look/shoot.mjs`).
final class Map3DRoofContrastTests: XCTestCase {
    /// The least lightness difference (ΔL*) between a roof and what is
    /// drawn round it. A first proposal; the owner sets the final number
    /// (`docs/art/roof-ground-contrast-2026-11-13/README.md`).
    static let least = 12.0

    /// The models that fail today (2026-11-13: 59 of 141), by the family's
    /// name and the model's; the table is in
    /// `docs/art/roof-ground-contrast-2026-11-13/README.md`.
    /// This round only lists them: none is to be recoloured to pass, and
    /// the threshold is not to be loosened for them. A model fixed later
    /// comes off the list (the test says so when one passes).
    static let known: Set<String> = [
        "station-kit/banqiao", "station-kit/halt-v1", "station-kit/halt-v3", "station-kit/highSpeed-v1",
        "station-kit/highSpeed-v3", "station-kit/highSpeed-v6", "station-kit/hsrHsinchu-v3", "station-kit/hsrTaichung-v0",
        "station-kit/hsrTainan-v4", "station-kit/hsrTaoyuan-v3", "station-kit/hualien", "station-kit/keelung",
        "station-kit/nangang", "station-kit/regional-v1-t1", "station-kit/regional-v1-t2", "station-kit/regional-v1-t3",
        "station-kit/regional-v3-t1", "station-kit/regional-v3-t2", "station-kit/regional-v3-t3", "station-kit/taitung",
        "station-kit/zuoying-v1", "station-kit/zuoying-v4",
        "station-study/b2-tainan", "station-study/hsr-hsinchu", "station-study/hsr-taichung", "station-study/hsr-tainan",
        "station-study/hsr-taoyuan", "station-study/hsr-zuoying", "station-study/tra-banqiao", "station-study/tra-hualien",
        "station-study/tra-taichung",
        "landmark/chiangKaiShekMemorialHall", "landmark/greatHarborBridge", "landmark/gushanFerryTerminal", "landmark/kaohsiung85SkyTower",
        "landmark/kaohsiungMainStation", "landmark/kaohsiungMusicCenter", "landmark/nationalConcertHall", "landmark/nationalTheater",
        "landmark/shinKongLifeTower", "landmark/sunYatSenMemorialHall", "landmark/taipei101",
        "commercial-kit/commercial-cinema", "commercial-kit/commercial-departmentStore", "commercial-kit/commercial-gasStation", "commercial-kit/commercial-metroEntrance",
        "commercial-kit/commercial-supermarket", "commercial-kit/commercial-warehouseStore",
        "civic-kit/civic-clinic", "civic-kit/civic-dayCareCenter", "civic-kit/civic-library", "civic-kit/civic-postOffice",
        "residential-kit/residential-arcadeTownhouse", "residential-kit/residential-cornerHouse", "residential-kit/residential-duplexHouse", "residential-kit/residential-narrowTownhouse",
        "residential-kit/residential-oldNarrowTownhouse", "residential-kit/residential-roofTerraceHouse", "residential-kit/residential-walkupApartment",
    ]

    func testNoRoofIsLostOnTheGroundRoundIt() throws {
        var failing = Set<String>()
        for subject in Self.subjects() {
            let measured = RoofContrast(subject)
            guard let now = measured.now else { continue }
            if !now.passes(Self.least) { failing.insert(subject.id) }
        }
        let new = failing.subtracting(Self.known).sorted(), fixed = Self.known.subtracting(failing).sorted()
        XCTAssertEqual(new, [], "roofs within ΔL* \(Self.least) of the ground round them, with no darker or lighter edge")
        XCTAssertEqual(fixed, [], "these now pass: take them off `known`")
    }

    /// The measure itself: a white slab on the map's ground fails, the same
    /// slab with a dark edge half a metre wide passes, and a grey one
    /// passes without.
    func testAWhiteRoofFailsUntilItHasADarkEdge() throws {
        func slab(roof: UInt32, edge: UInt32?) -> RoofContrast.Subject {
            var builder = StationKitBuilder()
            builder.box(0, 0, 0, 12, 20, 6, Map3DPalette.tileWhite)
            builder.box(0, 6, 0, 12, 20, 0.2, roof)
            if let edge {
                for side: Float in [-1, 1] {
                    builder.box(side * 5.7, 6.2, 0, 0.6, 20, 0.1, edge)
                    builder.box(0, 6.2, side * 9.7, 12, 0.6, 0.1, edge)
                }
            }
            return RoofContrast.Subject(family: "test", name: "slab", mesh: builder.mesh, look: { $0 })
        }
        let white = Map3DColor.rgb(0xFFFDF7), dark = Map3DColor.rgb(0x6F6A64), grey = Map3DColor.rgb(0xB9B4AC)
        let bare = try XCTUnwrap(RoofContrast(slab(roof: white, edge: nil)).now)
        XCTAssertLessThan(bare.roof, Self.least)
        XCTAssertFalse(bare.passes(Self.least))
        let edged = try XCTUnwrap(RoofContrast(slab(roof: white, edge: dark)).now)
        XCTAssertLessThan(edged.roof, Self.least)
        XCTAssertGreaterThan(edged.edge, Self.least)
        XCTAssertTrue(edged.passes(Self.least))
        XCTAssertTrue(try XCTUnwrap(RoofContrast(slab(roof: grey, edge: nil)).now).passes(Self.least))
    }

    /// The look does reach the kit's buildings: a station building's
    /// colours are made pale before the map draws them, so a recipe's dark
    /// roof is not what the check may read.
    func testTheLookMakesTheStationKitsRoofsPaler() {
        let green = Map3DPalette.gymGreen
        XCTAssertNotEqual(Map3DLook.colour(green), green)
        XCTAssertGreaterThan(RoofContrast.lightness(Map3DLook.colour(green), up: 1), RoofContrast.lightness(green, up: 1) + 10)
        // The forecourt and the ground keep theirs.
        XCTAssertEqual(Map3DLook.colour(Map3DPalette.plaza), Map3DPalette.plaza)
        XCTAssertEqual(Map3DLook.colour(Map3DPalette.ground), Map3DPalette.ground)
    }

    func testReport() throws {
        guard let folder = ProcessInfo.processInfo.environment["ROOF_CONTRAST_REPORT"] else {
            throw XCTSkip("set ROOF_CONTRAST_REPORT=<folder> to write the table and the models")
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true), models = directory.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        var rows = ["id\tfamily\tname\tcount\tlook\troofL\tnow-roof\tnow-edge\tnow-around\tnow-pale\tc-roof\tc-edge\tc-around\tc-pale\tground-a\tground-c\tfar-a\tfar-c\tarea\tcell\tfocus\troof-recipe\troof-drawn\trecipe-roof\trecipe-edge\tnote"]
        func text(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "" }
        func hex(_ color: UInt32?) -> String { color.map { String(format: "#%02X%02X%02X", $0 & 0xFF, ($0 >> 8) & 0xFF, ($0 >> 16) & 0xFF) } ?? "" }
        for subject in Self.subjects() {
            let measured = RoofContrast(subject)
            let far = subject.farRoof.map { RoofContrast.lightness($0, up: 1) }
            // What it would measure were it drawn in its recipe's colours, as the studies are.
            var unlooked = subject
            unlooked.look = { $0 }
            let recipe = subject.lookName == "own" ? nil : RoofContrast(unlooked).now
            rows.append([
                subject.id, subject.family, subject.name, String(subject.count), subject.lookName, text(measured.roofLightness),
                text(measured.now?.roof), text(measured.now?.edge), text(measured.now?.around), text(measured.now.map { $0.pale * 100 }),
                text(measured.optionC?.roof), text(measured.optionC?.edge), text(measured.optionC?.around), text(measured.optionC.map { $0.pale * 100 }),
                text(measured.roofLightness.map { abs($0 - RoofContrast.groundNow) }), text(measured.roofLightness.map { abs($0 - RoofContrast.groundC) }),
                text(far.flatMap { far in measured.now.map { abs(far - $0.around) } }), text(far.flatMap { far in measured.optionC.map { abs(far - $0.around) } }),
                text(measured.area), String(format: "%.2f", measured.cell), measured.focus.map { String(format: "%.1f", $0) }.joined(separator: ","), hex(measured.roofColour?.recipe), hex(measured.roofColour?.drawn), text(recipe?.roof), text(recipe?.edge), subject.note,
            ].joined(separator: "\t"))
            guard subject.shoots else { continue }
            try RoofContrast.file(of: subject).write(to: models.appendingPathComponent(subject.id.replacingOccurrences(of: "/", with: "-") + ".m3dmodel"), options: .atomic)
        }
        try (rows.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("roof-contrast.tsv"), atomically: true, encoding: .utf8)
    }

    // MARK: - What is measured

    /// Every building the check reads, each with the colours the map
    /// draws it in:
    /// - the station kit's buildings (`house`), one of each profile, roof
    ///   variant and tier: in the chunk's near mesh, so in the look's
    ///   `city` strength;
    /// - the real stations' exterior studies (decision 625): their own
    ///   colours, added after the look;
    /// - the landmarks (decisions 370 and 457): their own colours, kept;
    /// - the temples (decision 331) and the commercial, civic and
    ///   residential kits' buildings: in the close mesh, the look's
    ///   `close`. The kits' parts are read as their recipes alone on the
    ///   ground: the map draws only some of them, in layouts. Not the
    ///   estate kit, whose roofs take the player's colour when placed.
    static func subjects() -> [RoofContrast.Subject] {
        var all: [RoofContrast.Subject] = []
        let city: @Sendable (UInt32) -> UInt32 = { Map3DLook.colour($0) }
        let close: @Sendable (UInt32) -> UInt32 = { Map3DLook.colour($0, strength: Map3DLook.close) }
        let own: @Sendable (UInt32) -> UInt32 = { $0 }
        // Station kit: the building depends on the profile, the seed's
        // variant and, for the regional ones, the tier.
        var houses: [String: (station: Map3DStationKit.Station, count: Int)] = [:], order: [String] = []
        for station in Map3DStationKit.stations where Map3DStationKit.hasHouse(station.profile) {
            let varies: Set<Map3DStationKit.Profile> = [.hsinchu, .tainan, .chiayi, .heritage, .timber, .regional, .halt, .zuoying, .hsrTaichung, .hsrTaoyuan, .hsrHsinchu, .hsrTainan, .highSpeed]
            let key = station.profile.rawValue + (varies.contains(station.profile) ? "-v\(station.seed % 7)" : "") + (station.profile == .regional ? "-t\(station.tier)" : "")
            if houses[key] == nil { order.append(key) }
            houses[key] = (houses[key]?.station ?? station, (houses[key]?.count ?? 0) + 1)
        }
        for key in order.sorted() {
            let (station, count) = houses[key]!
            var builder = StationKitBuilder()
            builder.house(station)
            all.append(.init(family: "station-kit", name: key, mesh: builder.mesh, look: city, lookName: "city", count: count,
                             farRoof: Map3DLook.colour(Map3DStationKit.farColours(station.profile).roof), note: "例：" + station.name, shoots: true))
        }
        for study in Map3DExteriorStudy.allCases {
            // Its outlines' edges in the ground's colour stay the ground's.
            all.append(.init(family: "station-study", name: study.rawValue, mesh: study.sceneMesh(detail: .near), look: own, lookName: "own", shoots: true))
        }
        for landmark in Map3DTaipeiLandmark.allCases {
            let mesh = landmark.model(full: true).placed(origin: .zero, ground: 0, rotation: 0)
            all.append(.init(family: "landmark", name: "\(landmark)", mesh: mesh, look: own, lookName: "own", shoots: true))
        }
        for (size, name) in [(RealTemples.Size.large, "large"), (.temple, "temple"), (.small, "small")] {
            guard let temple = Map3DScene.Builder.templeModels[size] else { continue }
            all.append(.init(family: "temple", name: name, mesh: temple.mesh, look: close, lookName: "close",
                             farRoof: Map3DLook.colour(Map3DPalette.templeRoof), shoots: true))
        }
        func kit(_ family: String, _ models: [Map3DModelPack.Model]) {
            for model in models {
                var builder = StationKitBuilder()
                builder.add(model, at: .zero)
                all.append(.init(family: family, name: model.name, mesh: builder.mesh, look: close, lookName: "close"))
            }
        }
        kit("commercial-kit", Map3DCommercialKit.Part.allCases.filter { $0.category == .building }.map(Map3DCommercialKit.model(for:)))
        kit("civic-kit", Map3DCivicKit.Part.allCases.filter { $0.category == .building }.map { Map3DCivicKit.model(for: $0) })
        kit("residential-kit", Map3DResidentialKit.Part.allCases.filter { $0.category == .home }.map { Map3DResidentialKit.model(for: $0) })
        return all
    }
}

/// A building's roof against what the map draws round it, from above.
struct RoofContrast {
    struct Subject {
        var family: String
        var name: String
        /// Scene axes: x and z on the ground, y up, metres.
        var mesh: Map3DMesh
        /// A vertex colour as the map draws it.
        var look: @Sendable (UInt32) -> UInt32
        var lookName = "own"
        /// How many of the game's stations draw this building.
        var count = 1
        /// The far box's roof, already in the look.
        var farRoof: UInt32?
        var note = ""
        /// Whether the report writes it for the look sheet.
        var shoots = false

        var id: String { family + "/" + name }
    }

    /// Against one ground: the roof's median lightness against the
    /// median of what is drawn within `reach` of it (`around` is that
    /// lightness), the same for the roof's outer `rim`, and the share of
    /// the roof within `Map3DRoofContrastTests.least` of the ground.
    struct Against {
        var roof: Double
        var edge: Double
        var around: Double
        var pale: Double

        /// The roof stands apart, or its edge does.
        func passes(_ least: Double) -> Bool { roof >= least || edge >= least }
    }

    /// A cell's side (larger for a model too big for `most` cells of it),
    /// the least height of a roof over the model's foot, and in metres how
    /// far round the roof its surroundings are read and how wide the
    /// roof's rim is.
    static let cell: Float = 0.25, most: Float = 120_000, roofHeight: Float = 2, reach: Float = 3, rim: Float = 0.75

    /// The ground now (``Map3DPalette/ground``, which the look keeps) and
    /// the paving the preview's option C lays within 7 m of a building
    /// (`docs/art/map3d-liveliness-2026-11-13`, not in the game).
    static let groundNow = lightness(Map3DLook.colour(Map3DPalette.ground), up: 1)
    static let groundC = lightness(Map3DColor.rgb(0xE4E3DF), up: 1)

    /// The roof's median lightness, nil when nothing stands `roofHeight` up.
    var roofLightness: Double?
    var now: Against?
    var optionC: Against?
    /// The roof's area from above, in square metres.
    var area: Double = 0
    /// The cell it was read at.
    var cell: Float = 0
    /// The largest roof's box for the look sheet's `--focus`: its centre
    /// and half sizes in native metres (x front, y left, z up).
    var focus: [Float] = []
    /// The recipe's colour most of the roof has, and that colour as drawn.
    var roofColour: (recipe: UInt32, drawn: UInt32)?

    /// L* of `color` on a face whose normal's upward part is `up`, in the
    /// look's day light at 14:00 (`light = 0.85 + 0.02 up + 0.15 sun`, the
    /// sun 0.843 up; its tint between sky and sun), applied to the stored
    /// bytes as the shader does.
    static func lightness(_ color: UInt32, up: Float) -> Double {
        let sun = Double(max(up, 0)) * 0.843, light = 0.85 + 0.02 * Double(max(up, 0)) + 0.15 * sun
        let tint = [0.94 + 0.06 * sun, 0.96 + 0.03 * sun, 1.0 - 0.03 * sun]
        var luminance = 0.0
        for (index, weight) in [0.2126, 0.7152, 0.0722].enumerated() {
            let stored = min(Double((color >> UInt32(index * 8)) & 0xFF) / 255 * light * tint[index], 1)
            luminance += weight * (stored <= 0.04045 ? stored / 12.92 : pow((stored + 0.055) / 1.055, 2.4))
        }
        return luminance > 0.008856 ? 116 * cbrt(luminance) - 16 : 903.3 * luminance
    }

    init(_ subject: Subject) {
        let vertices = subject.mesh.vertices, indices = subject.mesh.indices
        guard !vertices.isEmpty else { return }
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        let cell = max(Self.cell, (((high.x - low.x) * (high.z - low.z) / Self.most).squareRoot() / Self.cell).rounded(.up) * Self.cell)
        let reach = Int((Self.reach / cell).rounded(.up)), rim = max(Int((Self.rim / cell).rounded()), 1), margin = reach + 1
        let columns = Int(((high.x - low.x) / cell).rounded(.up)) + 2 * margin, rows = Int(((high.z - low.z) / cell).rounded(.up)) + 2 * margin
        let originX = low.x - Float(margin) * cell, originZ = low.z - Float(margin) * cell
        var height = [Float](repeating: -.infinity, count: columns * rows), light = [Float](repeating: 0, count: columns * rows)
        var recipe = [UInt32](repeating: 0, count: columns * rows)
        var looked: [UInt32: UInt32] = [:]
        for start in stride(from: 0, to: indices.count, by: 3) {
            let a = vertices[Int(indices[start])], b = vertices[Int(indices[start + 1])], c = vertices[Int(indices[start + 2])]
            // Seen from above: the faces that look up, whichever way they are wound.
            let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z, vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z
            let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
            let length = (nx * nx + ny * ny + nz * nz).squareRoot()
            guard length > 0 else { continue }
            let up = max(a.ny, b.ny, c.ny) > 0.05 ? abs(ny) / length : 0
            guard up > 0.05 else { continue }
            let area = (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
            guard abs(area) > 1e-9 else { continue }
            let color = looked[a.color] ?? subject.look(a.color)
            looked[a.color] = color
            let value = Float(Self.lightness(color, up: up))
            let c0 = max(Int(((min(a.x, b.x, c.x) - originX) / cell).rounded(.down)), 0), c1 = min(Int(((max(a.x, b.x, c.x) - originX) / cell).rounded(.down)), columns - 1)
            let r0 = max(Int(((min(a.z, b.z, c.z) - originZ) / cell).rounded(.down)), 0), r1 = min(Int(((max(a.z, b.z, c.z) - originZ) / cell).rounded(.down)), rows - 1)
            guard c0 <= c1, r0 <= r1 else { continue }
            for row in r0...r1 {
                let z = originZ + (Float(row) + 0.5) * cell
                for column in c0...c1 {
                    let x = originX + (Float(column) + 0.5) * cell
                    let wa = ((b.x - x) * (c.z - z) - (c.x - x) * (b.z - z)) / area, wb = ((c.x - x) * (a.z - z) - (a.x - x) * (c.z - z)) / area
                    let wc = 1 - wa - wb
                    guard wa >= -0.001, wb >= -0.001, wc >= -0.001 else { continue }
                    let y = wa * a.y + wb * b.y + wc * c.y
                    if y > height[row * columns + column] {
                        height[row * columns + column] = y
                        light[row * columns + column] = value
                        recipe[row * columns + column] = a.color
                    }
                }
            }
        }
        let floor = low.y + Self.roofHeight
        let isRoof = height.map { $0 >= floor }
        var roof: [Double] = [], edge: [Double] = [], aroundNow: [Double] = [], aroundC: [Double] = []
        // How many cells each cell is from the roof's edge, inside and outside.
        var inside = isRoof.map { $0 ? Int.max / 2 : 0 }, outside = isRoof.map { $0 ? 0 : Int.max / 2 }
        func sweep(_ distance: inout [Int]) {
            for row in 0..<rows { for column in 0..<columns {
                let at = row * columns + column
                if column > 0 { distance[at] = min(distance[at], distance[at - 1] + 1) }
                if row > 0 { distance[at] = min(distance[at], distance[at - columns] + 1) }
            } }
            for row in (0..<rows).reversed() { for column in (0..<columns).reversed() {
                let at = row * columns + column
                if column < columns - 1 { distance[at] = min(distance[at], distance[at + 1] + 1) }
                if row < rows - 1 { distance[at] = min(distance[at], distance[at + columns] + 1) }
            } }
        }
        sweep(&inside)
        sweep(&outside)
        for at in 0..<(columns * rows) {
            if isRoof[at] {
                roof.append(Double(light[at]))
                if inside[at] <= rim { edge.append(Double(light[at])) }
            } else if outside[at] <= reach {
                // What the model itself lays there (a forecourt, a platform), else the map's ground.
                let own = height[at] > -.infinity ? Double(light[at]) : nil
                aroundNow.append(own ?? Self.groundNow)
                aroundC.append(own ?? Self.groundC)
            }
        }
        guard !roof.isEmpty, !aroundNow.isEmpty else { return }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let roofMedian = median(roof), rimMedian = median(edge)
        roofLightness = roofMedian
        area = Double(roof.count) * Double(cell * cell)
        self.cell = cell
        var shares: [UInt32: Int] = [:]
        for at in 0..<(columns * rows) where isRoof[at] { shares[recipe[at], default: 0] += 1 }
        if let most = shares.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key { roofColour = (most, looked[most] ?? most) }
        // The largest roof in one piece.
        var seen = [Bool](repeating: false, count: columns * rows), best: (count: Int, box: [Int]) = (0, [])
        for start in 0..<(columns * rows) where isRoof[start] && !seen[start] {
            var stack = [start], count = 0, box = [Int.max, Int.max, Int.min, Int.min]
            seen[start] = true
            while let at = stack.popLast() {
                let row = at / columns, column = at % columns
                count += 1
                box = [min(box[0], column), min(box[1], row), max(box[2], column), max(box[3], row)]
                for next in [at - 1, at + 1, at - columns, at + columns] where next >= 0 && next < columns * rows && isRoof[next] && !seen[next] {
                    seen[next] = true
                    stack.append(next)
                }
            }
            if count > best.count { best = (count, box) }
        }
        if best.count > 0 {
            var top = floor
            for row in best.box[1]...best.box[3] { for column in best.box[0]...best.box[2] { top = max(top, height[row * columns + column]) } }
            let x0 = originX + Float(best.box[0]) * cell, x1 = originX + Float(best.box[2] + 1) * cell
            let z0 = originZ + Float(best.box[1]) * cell, z1 = originZ + Float(best.box[3] + 1) * cell
            focus = [(x0 + x1) / 2, -(z0 + z1) / 2, (low.y + top) / 2, (x1 - x0) / 2, (z1 - z0) / 2, (top - low.y) / 2]
        }
        func against(_ around: [Double]) -> Against {
            let ground = median(around)
            return Against(roof: abs(roofMedian - ground), edge: abs(rimMedian - ground), around: ground,
                           pale: Double(roof.filter { abs($0 - ground) < Map3DRoofContrastTests.least }.count) / Double(roof.count))
        }
        now = against(aroundNow)
        optionC = against(aroundC)
    }

    /// `subject` as a native model file in the colours the map draws
    /// (`tools/model-look/export-station.swift`'s writing).
    static func file(of subject: Subject) -> Data {
        let model = Map3DModelPack.Model.flat(named: subject.id, from: subject.mesh)
        let text = try! JSONSerialization.data(withJSONObject: ["extras": ["assetId": subject.id, "coordinateSystem": "metres; x front, y left, z up", "colours": "as the 3D map draws them (Map3DLook: \(subject.lookName))"]], options: [.sortedKeys])
        var data = Data("M3DM".utf8)
        func put16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
        func put32(_ n: UInt32) { for shift: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> shift) & 255)) } }
        put16(1); put16(0); put32(UInt32(model.vertices.count / 3)); put32(UInt32(text.count)); data.append(text)
        data.append(contentsOf: [UInt8](repeating: 0, count: (4 - text.count % 4) % 4))
        for start in stride(from: 0, to: model.vertices.count, by: 3) {
            let triangle = model.vertices[start..<start + 3]
            put32(triangle.contains { $0.glows } ? 1 : 0)
            for v in triangle { put32(v.x.bitPattern); put32(v.y.bitPattern); put32(v.z.bitPattern); put32(subject.look(v.color) | 0xFF00_0000) }
        }
        return data
    }
}
