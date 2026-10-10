import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The game's own base map (ARCHITECTURE decision 151): its style, the
/// tiles it draws in and out of Taiwan, and the tiles and glyphs the app
/// bundles.
final class BaseMapStyleTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources")
    private static let glyphs = "file:///app/BaseMap/fonts/{fontstack}/{range}.pbf"

    private static let water: WaterGrid = {
        do {
            return try WaterGrid(data: Data(contentsOf: resources.appendingPathComponent("RealWorld/taiwan_water.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static func layers(_ tiles: BaseMapStyle.Tiles = .openFreeMap, dark: Bool = false) throws -> [[String: Any]] {
        let style = BaseMapStyle.style(tiles: tiles, dark: dark, glyphs: glyphs)
        return try XCTUnwrap(style["layers"] as? [[String: Any]])
    }

    // MARK: - The style

    func testTheStyleDrawsTheBundledTilesOrOpenFreeMaps() throws {
        let bundled = BaseMapStyle.style(tiles: .bundled(pmtiles: "file:///app/BaseMap/taiwan.pmtiles"), dark: false, glyphs: Self.glyphs)
        let sources = try XCTUnwrap(bundled["sources"] as? [String: [String: Any]])
        XCTAssertEqual(sources.keys.sorted(), ["openmaptiles"])
        XCTAssertEqual(sources["openmaptiles"]?["type"] as? String, "vector")
        XCTAssertEqual(sources["openmaptiles"]?["url"] as? String, "pmtiles://file:///app/BaseMap/taiwan.pmtiles")
        XCTAssertEqual(bundled["glyphs"] as? String, Self.glyphs)
        XCTAssertEqual(bundled["version"] as? Int, 8)

        let world = BaseMapStyle.style(tiles: .openFreeMap, dark: true, glyphs: Self.glyphs)
        let worldSources = try XCTUnwrap(world["sources"] as? [String: [String: Any]])
        XCTAssertEqual(worldSources["openmaptiles"]?["url"] as? String, "https://tiles.openfreemap.org/planet")
        XCTAssertEqual(worldSources["openmaptiles"]?["attribution"] as? String, "OpenFreeMap © OpenMapTiles Data from OpenStreetMap")
    }

    /// MapLibre reads the style as JSON; the same object comes back.
    func testTheStyleIsJSON() throws {
        for dark in [false, true] {
            let data = try BaseMapStyle.json(tiles: .openFreeMap, dark: dark, glyphs: Self.glyphs)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual((object["layers"] as? [Any])?.count, try Self.layers(dark: dark).count)
        }
    }

    /// Every layer but the background draws one of the tiles' layers, all of
    /// them in the bundled tiles (`tools/basemap/build_basemap.py`), and the
    /// layers' names are their own.
    func testEveryLayerDrawsALayerOfTheTiles() throws {
        let layers = try Self.layers()
        XCTAssertEqual(layers.first?["type"] as? String, "background")
        XCTAssertEqual(Set(layers.compactMap { $0["id"] as? String }).count, layers.count)
        for layer in layers.dropFirst() {
            XCTAssertEqual(layer["source"] as? String, "openmaptiles", "\(layer["id"] ?? "")")
            let sourceLayer = try XCTUnwrap(layer["source-layer"] as? String)
            XCTAssertTrue(BaseMapStyle.sourceLayers.contains(sourceLayer), sourceLayer)
        }
        XCTAssertEqual(Set(layers.compactMap { $0["source-layer"] as? String }), BaseMapStyle.sourceLayers)
    }

    /// The game draws its own city, zones and railways: the map has no
    /// buildings, land use, points of interest or railways, and no
    /// railway class among its roads.
    func testTheMapLeavesOutWhatTheGameDraws() throws {
        let layers = try Self.layers()
        for left in ["building", "landuse", "poi", "aeroway", "housenumber", "mountain_peak"] {
            XCTAssertFalse(layers.contains { $0["source-layer"] as? String == left }, left)
        }
        let text = String(decoding: try BaseMapStyle.json(tiles: .openFreeMap, dark: false, glyphs: Self.glyphs), as: UTF8.self)
        for railway in ["\"rail\"", "\"transit\"", "\"ferry\""] {
            XCTAssertFalse(text.contains(railway), railway)
        }
    }

    /// Light and dark: the land is the game's own (`Palette.land`), the
    /// labels its ink on a halo of the land.
    func testTheLandIsTheGamesInLightAndDark() throws {
        for (dark, land, ink) in [(false, "#ECEEF6", "#262C57"), (true, "#262C57", "#ECEEF6")] {
            let layers = try Self.layers(dark: dark)
            XCTAssertEqual((layers.first?["paint"] as? [String: Any])?["background-color"] as? String, land)
            let city = try XCTUnwrap(layers.first { $0["id"] as? String == "place-city" })
            XCTAssertEqual((city["paint"] as? [String: Any])?["text-color"] as? String, ink)
            XCTAssertEqual((city["paint"] as? [String: Any])?["text-halo-color"] as? String, land)
        }
    }

    /// Every label is a name the app puts in the player's language
    /// (``OpenStreetMapBase/labelText(in:)``), in a bundled font; the most
    /// important labels are the highest layers, placed first.
    func testLabelsAreNamesInTheBundledFonts() throws {
        let labels = try Self.layers().filter { $0["type"] as? String == "symbol" }
        XCTAssertFalse(labels.isEmpty)
        for label in labels {
            let layout = try XCTUnwrap(label["layout"] as? [String: Any])
            XCTAssertTrue(OpenStreetMapBase.showsName(layout["text-field"] as Any), "\(label["id"] ?? "")")
            let fonts = try XCTUnwrap(layout["text-font"] as? [String])
            XCTAssertTrue(fonts.allSatisfy(BaseMapStyle.fonts.contains), "\(fonts)")
        }
        XCTAssertEqual(labels.last?["id"] as? String, "place-city")
        // The style's labels after its other layers: the railways go under
        // the first of them, over the roads.
        let all = try Self.layers()
        let firstLabel = try XCTUnwrap(all.firstIndex { $0["type"] as? String == "symbol" })
        XCTAssertTrue(all[firstLabel...].allSatisfy { $0["type"] as? String == "symbol" })
    }

    /// `Ci/`'s `osmSensitiveFacilityLabelFilter`, on road names.
    func testRoadNamesHideSensitiveSites() throws {
        let filter = BaseMapStyle.sensitiveFacilityLabelFilter()
        let text = String(decoding: try JSONSerialization.data(withJSONObject: filter), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix(#"["!",["any",["in",["to-string",["coalesce",["get","class"],""]],["literal",["military","barracks""#))
        for field in ["subclass", "amenity", "landuse", "man_made", "power", "generator:source"] {
            XCTAssertTrue(text.contains(#"["get","\#(field)"]"#), field)
        }
        for id in ["road-label", "road-label-minor"] {
            let label = try XCTUnwrap(try Self.layers().first { $0["id"] as? String == id })
            let filterText = String(decoding: try JSONSerialization.data(withJSONObject: label["filter"] as Any), as: UTF8.self)
            XCTAssertTrue(filterText.contains(text), id)
        }
    }

    // MARK: - Which tiles

    /// Taiwan's tiles where Taiwan's land is within 2 km of the map's
    /// middle: the main island, Penghu, Kinmen and Matsu, even a middle on
    /// a river; not Xiamen, though Kinmen is in sight, nor the open strait
    /// or elsewhere; OpenFreeMap's without the water grid.
    func testOnlyMapsInTaiwanDrawTheBundledTiles() throws {
        func draws(_ latitude: Double, _ longitude: Double, water: WaterGrid? = BaseMapStyleTests.water) throws -> Bool {
            BaseMapStyle.drawsTaiwan(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)), water: water)
        }
        XCTAssertTrue(try draws(25.047_9, 121.517_0), "Taipei")
        XCTAssertTrue(try draws(25.068_0, 121.497_0), "the Tamsui river at Taipei")
        XCTAssertTrue(try draws(25.025_7, 121.737_7), "Pingxi")
        XCTAssertTrue(try draws(23.569_0, 119.579_0), "Penghu")
        XCTAssertTrue(try draws(24.432_0, 118.317_0), "Kinmen")
        XCTAssertTrue(try draws(26.160_0, 119.950_0), "Matsu")
        XCTAssertTrue(try draws(22.639_5, 120.302_5), "Kaohsiung")
        XCTAssertFalse(try draws(24.479_8, 118.081_9), "Xiamen")
        XCTAssertFalse(try draws(24.000_0, 119.500_0), "the strait")
        XCTAssertFalse(try draws(35.681_2, 139.767_1), "Tokyo")
        XCTAssertFalse(try draws(25.047_9, 121.517_0, water: nil), "no water grid")
    }

    // MARK: - The bundled files

    /// The tiles the app bundles: a PMTiles v3 archive of gzipped vector
    /// tiles, zooms 0–14, round all of Taiwan's land.
    func testTheBundledTilesAreTaiwans() throws {
        let file = Self.resources.appendingPathComponent("BaseMap/taiwan.pmtiles")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try XCTUnwrap(try handle.read(upToCount: 127))
        XCTAssertEqual(header.count, 127)
        XCTAssertEqual(String(decoding: header.prefix(7), as: UTF8.self), "PMTiles")
        let bytes = [UInt8](header)
        func int32(_ at: Int) -> Double {
            let raw = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            return Double(Int32(bitPattern: raw)) / 10_000_000
        }
        XCTAssertEqual(bytes[7], 3, "version")
        XCTAssertEqual(bytes[97], 2, "gzipped directories")
        XCTAssertEqual(bytes[98], 2, "gzipped tiles")
        XCTAssertEqual(bytes[99], 1, "vector tiles")
        XCTAssertEqual(bytes[100], 0, "first zoom")
        XCTAssertEqual(bytes[101], 14, "last zoom")
        let (west, south, east, north) = (int32(102), int32(106), int32(110), int32(114))
        XCTAssertLessThan(west, 118.1, "Kinmen")
        XCTAssertGreaterThan(east, 122.1, "the east coast")
        XCTAssertLessThan(south, 21.8, "Orchid Island")
        XCTAssertGreaterThan(north, 26.4, "Matsu")
    }

    /// Every font the style asks for has the ranges of Latin and of
    /// punctuation with glyphs in them; a range of only Chinese, which
    /// MapLibre draws with the device's font, has no file.
    func testTheBundledGlyphsHaveLatinAndPunctuation() throws {
        let fonts = Self.resources.appendingPathComponent("BaseMap/fonts")
        for font in BaseMapStyle.fonts {
            for range in ["0-255", "256-511", "8192-8447"] {
                let file = fonts.appendingPathComponent(font).appendingPathComponent("\(range).pbf")
                let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
                XCTAssertGreaterThan(size, 10_000, "\(font) \(range)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fonts.appendingPathComponent(font).appendingPathComponent("19968-20223.pbf").path))
            // An unexpected script finds a file, even an empty one.
            XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.appendingPathComponent(font).appendingPathComponent("1024-1279.pbf").path))
        }
    }
}
