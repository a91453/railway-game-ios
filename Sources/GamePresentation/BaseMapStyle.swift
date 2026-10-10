import Foundation
import GameCore

// The game's own style for the OpenStreetMap base map of real-world maps
// (ARCHITECTURE decision 151): in the app icon's style (decision 84,
// `docs/UI_THEME.md`), for the tiles the app bundles for Taiwan
// (`Resources/BaseMap/taiwan.pmtiles`, made from the same extract as the
// game's water, zones and places by `tools/basemap/build_basemap.py`) and
// for OpenFreeMap's tiles everywhere else. Both follow the OpenMapTiles
// schema, the bundled ones a part of it, so one style draws either.
//
// It leaves out what the game draws itself: buildings (its city, decision
// 126), land use (its zones), points of interest and railways (Taiwan's
// real ones, ``RealRailways``). Road names keep `Ci/`'s guard against the
// labels of military and other sensitive sites
// (`osmSensitiveFacilityLabelFilter`). Its glyphs come with the app
// (`Resources/BaseMap/fonts/`, Noto Sans), so the bundled map needs no
// network at all; MapLibre draws Chinese and Japanese with the device's
// own font.

/// The style MapLibre draws the OpenStreetMap base map in, as a style JSON
/// object.
public enum BaseMapStyle {
    /// Where the map's tiles come from.
    public enum Tiles: Equatable, Sendable {
        /// Taiwan's tiles the app bundles, at this PMTiles file's address.
        case bundled(pmtiles: String)
        /// OpenFreeMap's tiles of the whole world.
        case openFreeMap
    }

    /// OpenFreeMap's TileJSON of the whole world (OpenMapTiles schema).
    public static let openFreeMapTiles = "https://tiles.openfreemap.org/planet"
    /// The vector source every layer draws from.
    static let source = "openmaptiles"
    /// The tiles' layers the style draws, all of them in the bundled tiles.
    public static let sourceLayers: Set<String> = [
        "water", "waterway", "landcover", "park", "boundary", "transportation", "transportation_name", "place",
    ]
    /// The fonts the style asks for, each bundled in every glyph range.
    public static let fonts = ["Noto Sans Regular", "Noto Sans Bold"]

    /// The source's address in a style: MapLibre reads a PMTiles file by
    /// its `pmtiles://` address.
    static func address(of tiles: Tiles) -> String {
        switch tiles {
        case .bundled(let file): "pmtiles://\(file)"
        case .openFreeMap: openFreeMapTiles
        }
    }

    /// The colours of the base map, light or dark (`docs/UI_THEME.md`).
    struct Colors {
        let land: String
        let water: String
        let waterLabel: String
        let wood: String
        let grass: String
        let park: String
        let sand: String
        let wetland: String
        let road: String
        let roadMajor: String
        let motorway: String
        let casing: String
        let motorwayCasing: String
        let boundary: String
        let text: String
        let textMinor: String
        let halo: String

        static let light = Colors(
            land: "#ECEEF6", water: "#C3CEEA", waterLabel: "#344C8A",
            wood: "#D9E7D3", grass: "#E2EDDB", park: "#D2E8C4", sand: "#F1EBD8", wetland: "#D6E0EA",
            road: "#FFFFFF", roadMajor: "#FFFFFF", motorway: "#FFE4B0",
            casing: "#CDD1E4", motorwayCasing: "#E2B866",
            boundary: "#262C57", text: "#262C57", textMinor: "#5B6189", halo: "#ECEEF6"
        )
        static let dark = Colors(
            land: "#262C57", water: "#1A1F45", waterLabel: "#93A7DB",
            wood: "#2B4458", grass: "#2D3F60", park: "#2F4D52", sand: "#3A3B5C", wetland: "#293360",
            road: "#363D72", roadMajor: "#424A84", motorway: "#6E6475",
            casing: "#1E2348", motorwayCasing: "#1E2348",
            boundary: "#ECEEF6", text: "#ECEEF6", textMinor: "#B4B9D9", halo: "#262C57"
        )
    }

    /// The style JSON object for `tiles`, light or dark, its glyphs at
    /// `glyphs` (a MapLibre glyph address with `{fontstack}` and `{range}`).
    public static func style(tiles: Tiles, dark: Bool, glyphs: String) -> [String: Any] {
        let colors = dark ? Colors.dark : Colors.light
        var vector: [String: Any] = ["type": "vector", "url": address(of: tiles)]
        if tiles == .openFreeMap {
            vector["attribution"] = "OpenFreeMap © OpenMapTiles Data from OpenStreetMap"
        }
        return [
            "version": 8,
            "name": dark ? "Railway game (dark)" : "Railway game",
            "glyphs": glyphs,
            "sources": [source: vector],
            "layers": layers(colors),
        ]
    }

    /// The style as JSON, for a file MapLibre loads.
    public static func json(tiles: Tiles, dark: Bool, glyphs: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: style(tiles: tiles, dark: dark, glyphs: glyphs), options: [.sortedKeys])
    }

    // MARK: - Layers

    static let roadClasses = ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service"]

    static func layers(_ c: Colors) -> [[String: Any]] {
        var layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": c.land]],
            fill("landcover-wood", "landcover", ["==", ["get", "class"], "wood"], c.wood, minzoom: 7),
            fill("landcover-grass", "landcover", ["==", ["get", "class"], "grass"], c.grass, minzoom: 9),
            fill("landcover-sand", "landcover", ["==", ["get", "class"], "sand"], c.sand, minzoom: 9),
            fill("landcover-wetland", "landcover", ["==", ["get", "class"], "wetland"], c.wetland, minzoom: 9),
            fill("park", "park", true, c.park, minzoom: 6),
            fill("water", "water", ["all", ["!=", ["get", "brunnel"], "tunnel"], ["!=", ["get", "class"], "swimming_pool"]], c.water, minzoom: 0),
            [
                "id": "waterway", "type": "line", "source": source, "source-layer": "waterway", "minzoom": 8,
                "filter": ["all", ["match", ["get", "class"], ["river", "canal", "stream"], true, false], ["!=", ["get", "brunnel"], "tunnel"]],
                "layout": ["line-cap": "round", "line-join": "round"],
                "paint": [
                    "line-color": c.water,
                    "line-width": [
                        "interpolate", ["exponential", 1.4], ["zoom"],
                        8, ["match", ["get", "class"], "river", 0.6, 0.2],
                        12, ["match", ["get", "class"], "river", 1.6, "canal", 1, 0.5],
                        18, ["match", ["get", "class"], "river", 8, "canal", 6, 3],
                    ] as [Any],
                ] as [String: Any],
            ],
            [
                "id": "boundary-district", "type": "line", "source": source, "source-layer": "boundary", "minzoom": 10,
                "filter": ["all", ["==", ["get", "admin_level"], 7], ["!=", ["get", "maritime"], 1]],
                "paint": ["line-color": c.boundary, "line-opacity": 0.18, "line-width": 1, "line-dasharray": [3, 2]] as [String: Any],
            ],
            [
                "id": "boundary-county", "type": "line", "source": source, "source-layer": "boundary", "minzoom": 5,
                "filter": ["all", ["<=", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
                "paint": [
                    "line-color": c.boundary, "line-opacity": 0.35, "line-dasharray": [3, 2],
                    "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.6, 12, 1.5],
                ] as [String: Any],
            ],
        ]
        layers += roads(c)
        layers += labels(c)
        return layers
    }

    static func fill(_ id: String, _ layer: String, _ filter: Any, _ color: String, minzoom: Int) -> [String: Any] {
        var out: [String: Any] = [
            "id": id, "type": "fill", "source": source, "source-layer": layer, "minzoom": minzoom,
            "paint": ["fill-color": color, "fill-antialias": true] as [String: Any],
        ]
        if !(filter is Bool) {
            out["filter"] = filter
        }
        return out
    }

    /// A road's width at each zoom, by its class.
    static func roadWidth(casing: Bool) -> [Any] {
        let extra = casing ? 1.5 : 0
        func at(_ widths: [String: Double], other: Double) -> [Any] {
            var match: [Any] = ["match", ["get", "class"]]
            for name in roadClasses {
                if let width = widths[name] {
                    match += [name, width + (width > 0 ? extra : 0)]
                }
            }
            return match + [other]
        }
        return [
            "interpolate", ["exponential", 1.4], ["zoom"],
            5, at(["motorway": 0.5], other: 0),
            8, at(["motorway": 1, "trunk": 0.8, "primary": 0.4], other: 0),
            11, at(["motorway": 2, "trunk": 1.6, "primary": 1.2, "secondary": 0.8, "tertiary": 0.4], other: 0),
            14, at(["motorway": 5, "trunk": 4.5, "primary": 3.5, "secondary": 3, "tertiary": 2.5, "minor": 1.5, "service": 0.6], other: 0),
            18, at(["motorway": 18, "trunk": 16, "primary": 14, "secondary": 12, "tertiary": 10, "minor": 8, "service": 4], other: 0),
        ]
    }

    static func roadColor(_ c: Colors, casing: Bool) -> [Any] {
        if casing {
            return ["match", ["get", "class"], ["motorway", "trunk"], c.motorwayCasing, c.casing]
        }
        return ["match", ["get", "class"], ["motorway", "trunk"], c.motorway, ["primary", "secondary", "tertiary"], c.roadMajor, c.road]
    }

    /// The roads: tunnels faint under everything, then every road's casing
    /// and fill, the larger over the smaller; bridges over them all.
    static func roads(_ c: Colors) -> [[String: Any]] {
        let classes: [Any] = ["match", ["get", "class"], roadClasses, true, false]
        let sortKey: [Any] = ["match", ["get", "class"], "motorway", 7, "trunk", 6, "primary", 5, "secondary", 4, "tertiary", 3, "minor", 2, 1]
        func road(_ id: String, brunnel: Any, casing: Bool, opacity: Double = 1) -> [String: Any] {
            [
                "id": id, "type": "line", "source": source, "source-layer": "transportation", "minzoom": 5,
                "filter": ["all", classes, brunnel],
                "layout": ["line-cap": "round", "line-join": "round", "line-sort-key": sortKey] as [String: Any],
                "paint": [
                    "line-color": roadColor(c, casing: casing),
                    "line-width": roadWidth(casing: casing),
                    "line-opacity": opacity,
                ] as [String: Any],
            ]
        }
        let tunnel: [Any] = ["==", ["get", "brunnel"], "tunnel"]
        let bridge: [Any] = ["==", ["get", "brunnel"], "bridge"]
        let ground: [Any] = ["!", ["match", ["get", "brunnel"], ["tunnel", "bridge"], true, false]]
        return [
            road("road-tunnel", brunnel: tunnel, casing: false, opacity: 0.5),
            road("road-casing", brunnel: ground, casing: true),
            road("road", brunnel: ground, casing: false),
            road("bridge-casing", brunnel: bridge, casing: true),
            road("bridge", brunnel: bridge, casing: false),
        ]
    }

    /// The labels, the least important first: MapLibre places the labels
    /// of higher layers first.
    static func labels(_ c: Colors) -> [[String: Any]] {
        func text(_ id: String, _ layer: String, minzoom: Double, filter: Any, size: Any, color: String, bold: Bool = false, line: Bool = false) -> [String: Any] {
            var layout: [String: Any] = [
                "text-field": ["get", "name"],
                "text-font": [bold ? fonts[1] : fonts[0]],
                "text-size": size,
                "text-max-width": 8,
            ]
            if line {
                layout["symbol-placement"] = "line"
                layout["text-rotation-alignment"] = "map"
                layout["symbol-spacing"] = 350
            }
            return [
                "id": id, "type": "symbol", "source": source, "source-layer": layer, "minzoom": minzoom,
                "filter": filter,
                "layout": layout,
                "paint": ["text-color": color, "text-halo-color": c.halo, "text-halo-width": 1.5, "text-halo-blur": 0.5] as [String: Any],
            ]
        }
        func places(_ classes: [String]) -> [Any] {
            ["match", ["get", "class"], classes, true, false]
        }
        func size(_ low: Int, _ small: Double, _ high: Int, _ large: Double) -> [Any] {
            ["interpolate", ["linear"], ["zoom"], low, small, high, large]
        }
        let named: [Any] = ["has", "name"]
        // Lanes (巷) and alleys crowd the map: their names only close up.
        let minorRoads = ["minor", "service"]
        return [
            text("road-label-minor", "transportation_name", minzoom: 15.5,
                 filter: ["all", named, ["match", ["get", "class"], minorRoads, true, false], sensitiveFacilityLabelFilter()],
                 size: size(15, 10, 18, 12), color: c.textMinor, line: true),
            text("road-label", "transportation_name", minzoom: 10,
                 filter: ["all", named, ["match", ["get", "class"], roadClasses.filter { !minorRoads.contains($0) }, true, false], sensitiveFacilityLabelFilter()],
                 size: size(10, 10, 16, 12), color: c.textMinor, line: true),
            text("waterway-label", "waterway", minzoom: 12,
                 filter: ["all", named, ["match", ["get", "class"], ["river", "canal"], true, false]],
                 size: size(12, 10, 16, 12), color: c.waterLabel, line: true),
            text("place-small", "place", minzoom: 13, filter: ["all", named, places(["neighbourhood", "hamlet"])],
                 size: size(13, 10, 16, 12), color: c.textMinor),
            text("place-village", "place", minzoom: 12, filter: ["all", named, places(["village", "quarter"])],
                 size: size(12, 10, 16, 13), color: c.textMinor),
            text("place-suburb", "place", minzoom: 11, filter: ["all", named, places(["suburb"])],
                 size: size(11, 11, 16, 14), color: c.text),
            text("place-island", "place", minzoom: 8, filter: ["all", named, places(["island", "islet"])],
                 size: size(8, 10, 14, 13), color: c.waterLabel),
            text("place-town", "place", minzoom: 8, filter: ["all", named, places(["town"])],
                 size: size(8, 11, 14, 15), color: c.text),
            text("place-county", "place", minzoom: 7, filter: ["all", named, places(["county"])],
                 size: size(7, 11, 11, 14), color: c.text, bold: true).merging(["maxzoom": 11]) { $1 },
            text("place-city", "place", minzoom: 4, filter: ["all", named, places(["city"])],
                 size: size(6, 12, 12, 17), color: c.text, bold: true),
        ]
    }

    /// `Ci/`'s `osmSensitiveFacilityLabelFilter`: a label is shown only if
    /// none of its kinds is a military, mining or power site.
    public static func sensitiveFacilityLabelFilter() -> [Any] {
        let sensitive = [
            "military", "barracks", "base", "naval_base", "airbase", "checkpoint", "bunker", "danger_area", "range",
            "mine", "mineshaft", "mining", "quarry", "pit", "power", "power_plant", "plant", "generator", "substation",
            "transformer", "converter", "switchgear",
        ]
        let fields = ["class", "subclass", "type", "fclass", "kind", "amenity", "landuse", "man_made", "power", "generator:source"]
        let any: [Any] = ["any"] + fields.map { field -> Any in
            ["in", ["to-string", ["coalesce", ["get", field], ""]], ["literal", sensitive]] as [Any]
        }
        return ["!", any]
    }

    // MARK: - Which tiles

    /// How close Taiwan's land must be to a map's middle for the map to
    /// use the bundled tiles.
    public static let taiwanReach = 2_000.0

    /// Whether a real-world map whose middle is `anchor` draws Taiwan's
    /// bundled tiles: Taiwan's land (the game's water grid, ``WaterGrid``,
    /// where land that is not Taiwan's, such as Xiamen's, is sea) lies within
    /// ``taiwanReach`` of it. Elsewhere, and without the water grid, the
    /// map draws OpenFreeMap's tiles.
    public static func drawsTaiwan(anchor: GeoAnchor, water: WaterGrid?) -> Bool {
        water?.hasLand(nearLatitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees, within: taiwanReach) ?? false
    }
}
