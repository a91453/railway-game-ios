import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 352: the 3D map's signs, billboards and LED
/// screens (`Web/CityView/src/world/ads.js`'s atlas and quads).
final class Map3DSignTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let city = root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/city")

    private static func area(_ id: String) throws -> CityTileArea {
        let folder = city.appendingPathComponent(id)
        return try CityTileArea(manifest: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) {
            try? Data(contentsOf: folder.appendingPathComponent($0))
        }
    }

    // MARK: - The atlas

    func testTheAtlasHoldsTheToolsWordsInItsOrder() throws {
        let file = Self.root.appendingPathComponent("tools/map3d-signs/words.json")
        let words = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(words["shopWords"] as? [String], Map3DSignAtlas.shopWords)
        // Four to a cell, sixteen cells each way.
        XCTAssertEqual(Map3DSignAtlas.shopWords.count, 64)
        XCTAssertEqual(Set(Map3DSignAtlas.shopWords).count, 64)
        XCTAssertEqual((words["bannerWords"] as? [String])?.count, Map3DSignAtlas.banners)
        // The picture the app loads: a PNG 2,048 pixels square.
        let png = try Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/Map3D/Map3DSigns.png"))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        func big(_ at: Int) -> Int { png[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        XCTAssertEqual(big(16), Map3DSignAtlas.side)
        XCTAssertEqual(big(20), Map3DSignAtlas.side)
        XCTAssertLessThan(png.count, 600_000)
    }

    func testEachPictureHasItsOwnPartOfTheAtlas() {
        let eighth: Float = 1 / 8
        XCTAssertEqual(Map3DSignAtlas.rect(.poster, picture: 9).x, eighth)
        XCTAssertEqual(Map3DSignAtlas.rect(.poster, picture: 9).y, eighth)
        XCTAssertEqual(Map3DSignAtlas.rect(.banner, picture: 0).y, 3 * eighth)
        XCTAssertEqual(Map3DSignAtlas.rect(.banner, picture: 0).width, eighth / 3)
        // Word 5 across: cell 33's second strip; down: cell 49's second
        // column.
        let across = Map3DSignAtlas.rect(.across, picture: 5), down = Map3DSignAtlas.rect(.down, picture: 5)
        XCTAssertEqual(across.x, eighth)
        XCTAssertEqual(across.y, 4 * eighth + eighth / 4)
        XCTAssertEqual(across.width / across.height, 4)
        XCTAssertEqual(down.x, eighth + eighth / 4)
        XCTAssertEqual(down.y, 6 * eighth)
        XCTAssertEqual(down.height / down.width, 4)
        // None reaches past the atlas, nor into another.
        var rects: [(Float, Float, Float, Float)] = []
        for picture in 0..<24 { rects.append(Map3DSignAtlas.rect(.poster, picture: picture)) }
        for picture in 0..<8 { rects.append(Map3DSignAtlas.rect(.banner, picture: picture)) }
        for picture in 0..<64 { rects.append(Map3DSignAtlas.rect(.across, picture: picture)); rects.append(Map3DSignAtlas.rect(.down, picture: picture)) }
        for (index, a) in rects.enumerated() {
            XCTAssertTrue(a.0 >= 0 && a.1 >= 0 && a.0 + a.2 <= 1.0001 && a.1 + a.3 <= 1.0001)
            for b in rects[(index + 1)...] {
                let apart = a.0 + a.2 <= b.0 + 1e-5 || b.0 + b.2 <= a.0 + 1e-5 || a.1 + a.3 <= b.1 + 1e-5 || b.1 + b.3 <= a.1 + 1e-5
                XCTAssertTrue(apart, "\(a) \(b)")
            }
        }
    }

    // MARK: - A sign

    func testAReaderInFrontSeesTheWordsTheRightWayRound() {
        // A board facing south (+z): the reader looks north, east (+x) on
        // their right, as the camera's right is at heading 0.
        let sign = Map3DSign(kind: .across, centre: Map3DPoint(0, 4, 0), facing: Map3DPoint(0, 0, 1), width: 4, height: 1, picture: 0, seed: 0,
                             closes: 600)
        XCTAssertEqual(sign.right, Map3DPoint(2, 0, 0))
        XCTAssertEqual(sign.up, Map3DPoint(0, 0.5, 0))
        XCTAssertEqual(sign.facing, Map3DPoint(0, 0, 1))
        XCTAssertEqual(sign.corners, [Map3DPoint(-2, 3.5, 0), Map3DPoint(2, 3.5, 0), Map3DPoint(-2, 4.5, 0), Map3DPoint(2, 4.5, 0)])
        // `ads.js`: the reader's right is (nz, -nx).
        let west = Map3DSign(kind: .poster, centre: .zero, facing: Map3DPoint(-1, 0, 0), width: 2, height: 2, picture: 0, seed: 0, closes: 0)
        XCTAssertEqual(west.right, Map3DPoint(0, 0, 1))
        // A shop's board built facing +x and placed facing any way faces
        // that way, its words still to the reader's right.
        for forward in [Map3DPoint(0, 0, 1), Map3DPoint(-1, 0, 0), Map3DPoint(0.6, 0, -0.8)] {
            let local = Map3DSign(kind: .across, centre: Map3DPoint(4, 3, 1), facing: Map3DPoint(1, 0, 0), width: 2, height: 1, picture: 0,
                                  seed: 0, closes: 0)
            let placed = local.placed(at: Map3DPoint(10, 0, 10), forward: forward)
            XCTAssertEqual(placed.facing.x, forward.x, accuracy: 1e-5)
            XCTAssertEqual(placed.facing.z, forward.z, accuracy: 1e-5)
            XCTAssertEqual(placed.right.dot(Map3DPoint.up.cross(forward)), 1, accuracy: 1e-5)
        }
    }

    func testTheShaderReadsSixteenFloatsASign() {
        let sign = Map3DSign(kind: .screen, centre: Map3DPoint(1, 2, 3), facing: Map3DPoint(0, 0, 1), width: 2, height: 4, picture: 7, seed: 0.25,
                             board: 0x123456, letters: 0xFFFFFF, closes: 660)
        XCTAssertEqual(sign.floats.count * 4, Map3DSign.stride)
        XCTAssertEqual(sign.floats[3], 1)
        XCTAssertEqual(sign.floats[7], 7)
        XCTAssertEqual(sign.floats[11], 0.25)
        // Red, green and blue in one float, exactly.
        XCTAssertEqual(sign.floats[12], 0x12 + 0x34 * 256 + 0x56 * 65_536)
        XCTAssertEqual(sign.floats[13], 255 * (1 + 256 + 65_536))
        XCTAssertEqual(sign.floats[14], 660)
    }

    // MARK: - Time

    func testAScreenWipesInItsNextPosterEveryFewSeconds() {
        let start = Map3DSign.screen(picture: 3, seed: 0, seconds: 0)
        XCTAssertEqual(start.now, 3)
        XCTAssertEqual(start.next, 4)
        XCTAssertEqual(start.wipe, 0)
        // Most of the time still; the last seventh wiping.
        XCTAssertEqual(Map3DSign.screen(picture: 3, seed: 0, seconds: Map3DSign.screenPeriod * 0.5).wipe, 0)
        XCTAssertEqual(Map3DSign.screen(picture: 3, seed: 0, seconds: Map3DSign.screenPeriod * 0.93).wipe, 0.5, accuracy: 0.01)
        XCTAssertEqual(Map3DSign.screen(picture: 3, seed: 0, seconds: Map3DSign.screenPeriod * 1.01).now, 4)
        // Round the 24 posters.
        XCTAssertEqual(Map3DSign.screen(picture: 23, seed: 0, seconds: Map3DSign.screenPeriod * 1.01).now, 0)
        // With Reduce Motion, no time passes for the screens.
        XCTAssertEqual(Map3DSign.clock(seconds: 1_234, hour: 21, quality: .automatic, reduceMotion: true)[0], 0)
        XCTAssertEqual(Map3DSign.clock(seconds: 1_234, hour: 21, quality: .automatic, reduceMotion: false)[0], 1_234)
        XCTAssertEqual(Map3DSign.clock(seconds: 1_234, hour: 21, quality: .automatic, reduceMotion: false)[1], 540)
        // Saving draws only the nearer signs.
        XCTAssertLessThan(Map3DSign.reach(.saving), Map3DSign.reach(.automatic))
        XCTAssertEqual(Map3DSign.reach(.high), Map3DSign.reach(.automatic))
    }

    func testShopsSignsGoDarkWhenTheyClose() {
        XCTAssertEqual(Map3DSign.minutesAfterNoon(hour: 13), 60)
        XCTAssertEqual(Map3DSign.minutesAfterNoon(hour: 2), 840)
        XCTAssertEqual(Map3DSign.minutesAfterNoon(hour: 0), 720)
        let store = try! XCTUnwrap(Map3DSignAtlas.word("便利商店")), noodles = try! XCTUnwrap(Map3DSignAtlas.word("麵店"))
        let snacks = try! XCTUnwrap(Map3DSignAtlas.word("鹹酥雞")), books = try! XCTUnwrap(Map3DSignAtlas.word("書店"))
        XCTAssertEqual(Map3DSignAtlas.closes(store, share: 0.3), Map3DSign.allNight)
        // The town scene's breakfast shop shuts at 13:00: dark all night.
        XCTAssertEqual(Map3DSignAtlas.closes(try! XCTUnwrap(Map3DSignAtlas.word("早餐店")), share: 0.9), 60)
        for share: Float in [0, 0.5, 1] {
            // Noodles 20:00–24:00, books 19:00–22:00, late snacks 23:00–03:00.
            XCTAssertTrue((480...720).contains(Map3DSignAtlas.closes(noodles, share: share)))
            XCTAssertTrue((420...600).contains(Map3DSignAtlas.closes(books, share: share)))
            XCTAssertTrue((660...900).contains(Map3DSignAtlas.closes(snacks, share: share)))
        }
        let sign = Map3DSign(kind: .across, centre: .zero, facing: Map3DPoint(0, 0, 1), width: 2, height: 1, picture: noodles, seed: 0,
                             closes: Map3DSignAtlas.closes(noodles, share: 0.5))
        XCTAssertTrue(sign.isLit(hour: 19))
        XCTAssertTrue(sign.isLit(hour: 21.9))
        XCTAssertFalse(sign.isLit(hour: 22.1))
        XCTAssertFalse(sign.isLit(hour: 3))
    }

    // MARK: - Words

    func testASignSaysWhatKindOfShopItIsNeverItsName() {
        func word(_ name: String, title: Bool = false) -> String { Map3DSignAtlas.shopWords[Map3DSignAtlas.word(forName: name, title: title)] }
        XCTAssertEqual(word("全家便利商店高雄站前店"), "便利商店")
        XCTAssertEqual(word("老王牛肉麵"), "牛肉麵")
        XCTAssertEqual(word("阿明麵店"), "麵店")
        XCTAssertEqual(word("大同診所"), "診所")
        XCTAssertEqual(word("仁愛牙醫診所"), "牙醫")
        XCTAssertEqual(word("第一銀行"), "銀行")
        XCTAssertEqual(word("Cafe Lumen"), "咖啡")
        XCTAssertEqual(word("長榮商務大樓", title: true), "大樓")
        // A name that tells nothing: an everyday word, the same each time.
        XCTAssertEqual(word("ABC"), word("ABC"))
        XCTAssertTrue(Map3DSignAtlas.everyday.contains(word("ABC")))
        XCTAssertEqual(word("ABC", title: true), "大樓")
        // Every rule's word is one the atlas holds.
        for rule in Map3DSignAtlas.rules { XCTAssertNotNil(Map3DSignAtlas.word(rule.word), rule.word) }
        for word in Map3DSignAtlas.everyday { XCTAssertNotNil(Map3DSignAtlas.word(word), word) }
    }

    // MARK: - Where they hang

    func testTheTilesSignsReadAsThePipelineHungThem() throws {
        // `signs.mjs`'s fascia, blade and title signs; no billboard in the
        // Taiwan tiles (the 3D map hangs its own).
        for (id, counts) in [("kaohsiung", [0: 156, 1: 48, 2: 10]), ("taichung", [0: 362, 1: 157, 2: 56])] {
            let area = try Self.area(id)
            XCTAssertEqual(Dictionary(grouping: area.signs, by: \.style).mapValues(\.count), counts, id)
            XCTAssertTrue(area.signs.allSatisfy { abs($0.x) < 900 && abs($0.z) < 900 && $0.y > 0 && $0.width > 0 }, id)
            XCTAssertTrue(area.signs.allSatisfy { abs($0.nx * $0.nx + $0.nz * $0.nz - 1) < 0.01 }, id)
            XCTAssertTrue(area.signs.allSatisfy { (0..<14).contains($0.colour) }, id)
        }
        // The chains' white boards painted plain (art-style §7).
        XCTAssertEqual(Map3DSignAtlas.plainColour(10), 6)
        XCTAssertEqual(Map3DSignAtlas.plainColour(11), 5)
        XCTAssertEqual(Map3DSignAtlas.plainColour(3), 3)
        XCTAssertEqual(Map3DSignAtlas.plainColour(40), 13)
    }

    func testStationShopsBoardsSayWhatTheySell() {
        for index: Int32 in 0..<24 {
            let shop = Map3DScene.Builder.shop(seed: 77, index: index, lane: Int(index), tall: index == 0)
            XCTAssertEqual(shop.signs.count, index == 0 ? 2 : 1)
            for sign in shop.signs {
                XCTAssertEqual(sign.kind, .across)
                XCTAssertTrue(Map3DScene.Builder.foodWords.contains(sign.picture) || Map3DScene.Builder.retailWords.contains(sign.picture))
                // Facing out of the shop's front, over its sign box.
                XCTAssertEqual(sign.facing, Map3DPoint(1, 0, 0))
                XCTAssertGreaterThan(sign.centre.x, shop.depth / 2 - 1.2)
            }
        }
    }

    func testAKaohsiungMapHangsSignsBillboardsAndScreens() throws {
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6394, longitudeDegrees: 120.3024))
        let world = GameWorld.newGame(anchor: anchor)
        let areas = CityTileArea.areas(in: Self.city)
        let scene = Map3DScene(world: world, baseMap: tiles, cityTiles: areas)
        let signs = scene.chunks.flatMap(\.signs)
        let kinds = Dictionary(grouping: signs, by: \.kind).mapValues(\.count)
        // The tiles' (blades twice, one a side) and `placeAds`' round the station.
        XCTAssertGreaterThan(kinds[.across] ?? 0, 90, "\(kinds)")
        XCTAssertGreaterThan(kinds[.down] ?? 0, 80, "\(kinds)")
        XCTAssertGreaterThan(kinds[.poster] ?? 0, 5, "\(kinds)")
        XCTAssertGreaterThan(kinds[.screen] ?? 0, 1, "\(kinds)")
        XCTAssertGreaterThan(kinds[.banner] ?? 0, 1, "\(kinds)")
        // Every sign inside its chunk's box, so it is drawn while in view.
        for chunk in scene.chunks {
            for corner in chunk.signs.flatMap(\.corners) {
                XCTAssertTrue(corner.x >= chunk.minimum.x && corner.x <= chunk.maximum.x && corner.y >= chunk.minimum.y && corner.y <= chunk.maximum.y
                              && corner.z >= chunk.minimum.z && corner.z <= chunk.maximum.z)
            }
        }
        // Every word one the atlas holds, every board upright and level.
        XCTAssertTrue(signs.allSatisfy { $0.kind.rawValue < 3 || Map3DSignAtlas.shopWords.indices.contains($0.picture) })
        XCTAssertTrue(signs.allSatisfy { abs($0.facing.y) < 1e-4 && $0.up.x == 0 && $0.up.z == 0 && $0.up.y > 0 })
        // The same every time.
        XCTAssertEqual(Map3DScene(world: world, baseMap: tiles, cityTiles: areas).chunks.flatMap(\.signs), signs)
        // What drawing them costs: one draw call a chunk drawn in full that
        // has any, four vertices a sign.
        let withSigns = scene.chunks.filter { !$0.signs.isEmpty }.count
        print("Map3DSignTests: \(signs.count) signs (\(kinds)) in \(withSigns) chunks")
    }

    func testTheGamesOwnCityHangsSignsOnItsShops() {
        let world = GameWorld.newGame()
        let scene = Map3DScene(world: world)
        let signs = scene.chunks.flatMap(\.signs)
        let kinds = Dictionary(grouping: signs, by: \.kind).mapValues(\.count)
        print("Map3DSignTests: the game's own city, \(signs.count) signs (\(kinds)) in \(scene.chunks.filter { !$0.signs.isEmpty }.count) chunks")
        // Blade signs on the shops' row houses, a word on each side.
        XCTAssertGreaterThan(kinds[.down] ?? 0, 0, "\(kinds)")
        XCTAssertEqual((kinds[.down] ?? 0) % 2, 0)
        XCTAssertEqual(Map3DScene(world: world).chunks.flatMap(\.signs), signs)
    }
}
