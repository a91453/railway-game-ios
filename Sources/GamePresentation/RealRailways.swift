import Foundation
import GameCore

// Taiwan's real railways under a real-world map (after Stage E2, ARCHITECTURE
// decision 50): the lines and stations the owner's `Railway/` site draws
// under its map, ported with its data as it is. The app bundles the site's
// own files and draws them on Apple's map, under the map's labels as the
// site draws them under MapLibre's; the real-world picker lists the
// stations as places to start at. The site is no longer maintained, so
// where its line shapes are off the real track the game redraws them from
// OpenStreetMap (`tools/real-railways/`, three stretches since 2026-10-05).
//
// None of it is the game's: the rules never see a real railway, a save
// keeps nothing of it, and the player builds their own railway over it.
//
// Sources (`Railway/site_archive_clean/`):
// - `data/track_lines.geojson` and `data/track_stations.geojson`: every
//   line's shape and stations. The colours the site draws them in are not
//   read: each line has its official colour (``System``), checked against
//   the operators and TDX (2026-10-05, the author's requests), mixed for
//   each look as the site mixes its own (`index.html` `railMix`);
// - `data/track_style_layers.json`: the casing, line and station widths and
//   the casing colour of each map theme;
// - `i18n/stations.json`: the stations' English names;
// - `index.html`: the systems and their labels, and the track display
//   setting (`trackStyle`: auto, faint, hidden);
// - `rail-discovery.js` `norm`: how a station's name is matched.
//
// The data comes from the Ministry of Transportation and Communications'
// TDX and from OpenStreetMap (``DataSourceCredits``).

/// Taiwan's railways as the owner's `Railway/` site has them: its lines,
/// the stations along them and the systems they belong to.
public struct RealRailways: Sendable {
    /// A point on the Earth in degrees (WGS-84), as the site's GeoJSON has
    /// it.
    public struct Coordinate: Hashable, Sendable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        /// Distance to another coordinate in metres (Haversine formula).
        public func distance(to other: Coordinate) -> Double {
            let earthRadius = 6_378_137.0
            let lat1 = latitude * .pi / 180
            let lat2 = other.latitude * .pi / 180
            let deltaLat = (other.latitude - latitude) * .pi / 180
            let deltaLon = (other.longitude - longitude) * .pi / 180
            let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
            let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
            return earthRadius * c
        }
    }

    /// A colour as the site writes it, `#RRGGBB`.
    public struct RGB: Hashable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The colour `#RRGGBB`, or `nil` for anything else.
        public init?(hex: String) {
            let digits = Array(hex.utf8)
            guard digits.count == 7, digits[0] == UInt8(ascii: "#") else { return nil }
            var values: [UInt8] = []
            for digit in digits.dropFirst() {
                switch digit {
                case UInt8(ascii: "0") ... UInt8(ascii: "9"): values.append(digit - UInt8(ascii: "0"))
                case UInt8(ascii: "a") ... UInt8(ascii: "f"): values.append(digit - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A") ... UInt8(ascii: "F"): values.append(digit - UInt8(ascii: "A") + 10)
                default: return nil
                }
            }
            self.init(red: values[0] << 4 | values[1], green: values[2] << 4 | values[3], blue: values[4] << 4 | values[5])
        }

        /// The colour `0xRRGGBB`.
        init(_ value: UInt32) {
            self.init(red: UInt8(truncatingIfNeeded: value >> 16), green: UInt8(truncatingIfNeeded: value >> 8), blue: UInt8(truncatingIfNeeded: value))
        }
    }

    /// A railway operator's network, in the site's order (`index.html`'s
    /// systems).
    public struct System: Hashable, Sendable, Identifiable {
        /// The site's key, such as `tra_sched` or `mrt`.
        public let id: String
        let english: String
        let chinese: String
        /// The colour all its lines are drawn in, where they have no line
        /// colours of their own: its operator's. `nil` where each line has
        /// its own (``lineColors``).
        public let operatorColor: RGB?
        /// Each line's official colour, by the site's line key (`lineKey`).
        let lineColors: [String: RGB]

        init(id: String, english: String, chinese: String, operatorColor: RGB? = nil, lineColors: [String: RGB] = [:]) {
            self.id = id
            self.english = english
            self.chinese = chinese
            self.operatorColor = operatorColor
            self.lineColors = lineColors
        }

        /// The site's label, and its English translation
        /// (`i18n/translations.js`).
        public func name(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }

        /// The official colour of its line with the key `lineKey`, or `nil`
        /// where there is none.
        public func color(ofLine lineKey: String) -> RGB? {
            operatorColor ?? lineColors[lineKey]
        }

        // Every colour is an official one, checked on 2026-10-05; none is
        // made up (the author's request). Where an operator's own sources
        // differ by a unit or two, the value the site already had is kept.
        public static let all: [System] = [
            // The operators' colours, for the systems with no line colours:
            // Taiwan Railway's blue as the author gave it (the logo at
            // www.railway.gov.tw is about #00529D), Taiwan High Speed Rail's
            // orange (www.thsrc.com.tw's logo.svg) and the Alishan Forest
            // Railway's red (afrch.forest.gov.tw's logo_ch.svg and favicon,
            // near PANTONE 200 C).
            System(id: "tra_sched", english: "TRA", chinese: "台鐵", operatorColor: RGB(0x005792)),
            System(id: "thsr_sched", english: "High Speed Rail", chinese: "高鐵", operatorColor: RGB(0xDB5009)),
            System(id: "afr_sched", english: "Alishan Forest Railway", chinese: "阿里山林鐵", operatorColor: RGB(0xC41229)),
            // Taipei Metro's own stylesheets: the lines' classes in
            // web.metro.taipei's route widget, and for the two branches the
            // route planner's (`webrouteplan.css` `.BX`, `.QX`) with their
            // station labels.
            System(id: "mrt", english: "Taipei Metro", chinese: "台北捷運", lineColors: [
                "mrt|BR": RGB(0xC48C31), "mrt|R": RGB(0xE3002C), "mrt|R_XBT": RGB(0xF3A5A8),
                "mrt|G": RGB(0x008659), "mrt|G_XBT": RGB(0xDAE11B),
                "mrt|O_XINZHUANG": RGB(0xF8B61C), "mrt|O_LUZHOU": RGB(0xF8B61C),
                "mrt|BL": RGB(0x0070BD), "mrt|Y": RGB(0xFFDB00),
            ]),
            // TDX's `Rail/Metro/Line` `LineColor`, where the operator's own
            // site declares no line colour. The Danhai Light Rail's two
            // services share the one line's.
            System(id: "tymc", english: "Taoyuan Airport MRT", chinese: "桃園機捷", lineColors: ["tymc|A": RGB(0x8246AF)]),
            System(id: "ntdlrt", english: "Danhai Light Rail", chinese: "淡海輕軌", lineColors: ["ntdlrt|V": RGB(0xFF2A00), "ntdlrt|VB": RGB(0xFF2A00)]),
            System(id: "ntalrt", english: "Ankeng Light Rail", chinese: "安坑輕軌", lineColors: ["ntalrt|K": RGB(0x9E925E)]),
            System(id: "sanying", english: "Sanying Line", chinese: "三鶯線", lineColors: ["sanying|LB": RGB(0x47C1E1)]),
            // Kaohsiung Metro's own stylesheets (www.krtc.com.tw `.lineRed`,
            // `.lineOrange`, `.lineLRT`); TDX has no colours for it.
            System(id: "krtc", english: "Kaohsiung Metro", chinese: "高雄捷運", lineColors: [
                "krtc|KR": RGB(0xE30964), "krtc|KO": RGB(0xFF9500), "krtc|C": RGB(0x8FC31F),
            ]),
            // TDX.
            System(id: "tmrt", english: "Taichung Metro", chinese: "台中捷運", lineColors: ["tmrt|TG": RGB(0x84BD00)]),
        ]
    }

    /// How strongly the real railways show (the site's track display,
    /// `trackStyle`): in their colours, faint, or very faint. A view
    /// preference, kept with the app's settings rather than the game.
    public enum TrackStyle: String, CaseIterable, Identifiable, Sendable {
        /// The lines' own colours (the site's default), muted on a dark map.
        case auto
        case faint
        /// Hidden as the site hides them: all but invisible, not gone.
        case hidden

        public var id: Self { self }

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .auto: language.text("Auto", "自動")
            case .faint: language.text("Faint", "淡化")
            case .hidden: language.text("Hide", "隱藏")
            }
        }
    }

    /// The map the railways are drawn on: each has its own colours
    /// (`track_style_layers.json`'s themes).
    public enum MapTheme: Hashable, Sendable {
        case light
        case dark
        /// Satellite imagery, with or without labels.
        case satellite

        /// The casing round each line and the middle of each station.
        public var casing: RGB {
            switch self {
            case .light: RGB(red: 0xF2, green: 0xED, blue: 0xE2)
            case .dark: RGB(red: 0x10, green: 0x14, blue: 0x1C)
            case .satellite: RGB(red: 0x24, green: 0x38, blue: 0x2C)
            }
        }
    }

    /// The colours one line and its stations are drawn in, one for each
    /// track display and map theme.
    ///
    /// The line's official colour (``System/color(ofLine:)``), not the
    /// site's (2026-10-05, the author's requests). The dark, faint and hidden
    /// looks are mixed from it toward the map theme's casing as the site
    /// mixes its own (`index.html` `railMix`, with `RAIL_DIM`,
    /// `FAINT_LIGHT`, `FAINT_GLOW`, `GHOST_LIGHT` and `GHOST_GLOW`).
    public struct Palette: Hashable, Sendable {
        /// The line's own colour: how it looks in the auto display on a
        /// light map and on imagery.
        public let color: RGB

        public init(color: RGB) {
            self.color = color
        }

        /// The colour for `style` on `theme` (the site's `trackLineColor`
        /// and `railDimColor`, as its files have them mixed in advance).
        public func color(_ style: TrackStyle, on theme: MapTheme) -> RGB {
            let keep: Double? = switch (style, theme) {
            case (.auto, .light), (.auto, .satellite): nil
            case (.auto, .dark): 0.40
            case (.faint, .light): 0.35
            case (.faint, .dark), (.faint, .satellite): 0.22
            case (.hidden, .light): 0.18
            case (.hidden, .dark), (.hidden, .satellite): 0.12
            }
            guard let keep else { return color }
            return Self.mix(color, into: theme.casing, keeping: keep)
        }

        /// The site's `railMix`: each channel `round(c · keep + base · (1 −
        /// keep))`.
        public static func mix(_ color: RGB, into base: RGB, keeping keep: Double) -> RGB {
            func channel(_ c: UInt8, _ b: UInt8) -> UInt8 {
                UInt8((Double(c) * keep + Double(b) * (1 - keep)).rounded())
            }
            return RGB(red: channel(color.red, base.red), green: channel(color.green, base.green), blue: channel(color.blue, base.blue))
        }
    }

    /// The widths the site draws with (`track_style_layers.json`), in
    /// points.
    public enum Widths {
        /// The casing under each line.
        public static let casing = 5.6
        public static let line = 3.0
        /// A station is a circle in the casing's colour with a ring in its
        /// line's.
        public static let stationRadius = 2.4
        public static let stationRing = 1.5
        public static let stationRingOpacity = 0.9
        /// Stations show from this zoom level on (MapLibre's, 512-point
        /// tiles: the whole Earth is 512 · 2^z points wide).
        public static let stationsMinimumZoom = 11.0
    }

    /// One piece of a line, as the site's file has it: a line can be in
    /// several pieces.
    public struct Line: Identifiable, Sendable {
        /// Where it is in the site's file.
        public let id: Int
        public let system: System
        /// The site's name, in Chinese.
        public let name: String
        /// Lines with a larger key are drawn over those with a smaller one
        /// where they cross on different levels (the site's `sortKey`).
        public let sortKey: Int
        public let palette: Palette
        public let points: [Coordinate]
        let box: Box
    }

    /// A station as the site draws it: a station on several lines is drawn
    /// once for each, in each line's colour.
    public struct StationMark: Sendable {
        public let system: System
        public let coordinate: Coordinate
        public let palette: Palette
    }

    /// A station a real-world game can start at: the first of each name in
    /// each system, in the site's order.
    public struct Station: Identifiable, Hashable, Sendable {
        public let system: System
        public let chinese: String
        public let english: String?
        public let coordinate: Coordinate
        public let palette: Palette

        /// The system and the name: unique.
        public var id: String { "\(system.id)|\(chinese)" }

        /// Its English name from the site's `i18n/stations.json`; the
        /// Chinese one where the site has none.
        public func name(in language: DisplayLanguage) -> String {
            language.text(english ?? chinese, chinese)
        }

        /// Where a game's map starting at it lies.
        public var anchor: GeoAnchor? {
            GeoAnchor(latitudeDegrees: coordinate.latitude, longitudeDegrees: coordinate.longitude)
        }

        /// Whether `query`, already ``RealRailways/normalized(_:)``, is in
        /// its name, and at the start of it.
        func match(_ query: String) -> (found: Bool, atStart: Bool) {
            var found = false
            for name in [chinese, english].compactMap({ $0 }).map(RealRailways.normalized) {
                if name.hasPrefix(query) { return (true, true) }
                found = found || name.contains(query)
            }
            return (found, false)
        }
    }

    /// Why the files cannot be read.
    public enum LoadError: Error, Hashable {
        case invalidCoordinate
        case unknownSystem(String)
        /// A line with no official colour: none is made up for it.
        case noOfficialColor(lineKey: String)
    }

    public let lines: [Line]
    /// Every station the site draws.
    public let stationMarks: [StationMark]
    /// Every station once in each system, in the site's order.
    public let stations: [Station]
    /// Real station operational metadata (classes, IDs, addresses, platforms, TRTC codes, track sections).
    public let stationData: RealStationData?
    /// Real system and line operational parameters (headways, dwell times, station sequences, timetables).
    public let operations: RealRailwayOperations?

    /// The railways in the site's `track_lines.geojson`,
    /// `track_stations.geojson` and `i18n/stations.json`.
    public init(
        lines linesFile: Data,
        stations stationsFile: Data,
        names namesFile: Data,
        stationData: RealStationData? = nil,
        operations: RealRailwayOperations? = nil
    ) throws {
        let decoder = JSONDecoder()
        let lineFeatures = try decoder.decode(FeatureCollection<LineProperties, LineGeometry>.self, from: linesFile).features
        let stationFeatures = try decoder.decode(FeatureCollection<StationProperties, PointGeometry>.self, from: stationsFile).features
        let names = try decoder.decode(NameFile.self, from: namesFile).systems

        lines = try lineFeatures.enumerated().map { index, feature in
            let points = try feature.geometry.coordinates.map(Self.coordinate)
            guard points.count >= 2 else { throw LoadError.invalidCoordinate }
            let system = try Self.system(feature.properties.sys)
            return Line(
                id: index,
                system: system,
                name: feature.properties.name,
                sortKey: feature.properties.sortKey,
                palette: try Self.palette(feature.properties.lineKey, in: system),
                points: points,
                box: Box(points)
            )
        }
        stationMarks = try stationFeatures.map { feature in
            let system = try Self.system(feature.properties.sys)
            return StationMark(
                system: system,
                coordinate: try Self.coordinate(feature.geometry.coordinates),
                palette: try Self.palette(feature.properties.lineKey, in: system)
            )
        }
        var seen: Set<String> = []
        var stations: [Station] = []
        for (feature, mark) in zip(stationFeatures, stationMarks) {
            let name = feature.properties.name
            guard seen.insert("\(mark.system.id)|\(name)").inserted else { continue }
            stations.append(Station(
                system: mark.system,
                chinese: name,
                english: names[mark.system.id]?[name]?.en,
                coordinate: mark.coordinate,
                palette: mark.palette
            ))
        }
        self.stations = stations
        self.stationData = stationData
        self.operations = operations
    }

    /// The lines that come within `metres` of `anchor`.
    public func lines(near anchor: GeoAnchor, within metres: Double) -> [Line] {
        let around = Box(around: anchor, metres: metres)
        return lines.filter { $0.box.overlaps(around) }
    }

    /// The stations the site draws within `metres` of `anchor`.
    public func stationMarks(near anchor: GeoAnchor, within metres: Double) -> [StationMark] {
        let around = Box(around: anchor, metres: metres)
        return stationMarks.filter { around.contains($0.coordinate) }
    }

    /// The stations whose name, in Chinese or English, has `query` in it:
    /// those it starts first, each in the site's order. Nothing for an
    /// empty query.
    public func stations(matching query: String) -> [Station] {
        let query = Self.normalized(query)
        guard !query.isEmpty else { return [] }
        var first: [Station] = [], then: [Station] = []
        for station in stations {
            let match = station.match(query)
            if match.atStart {
                first.append(station)
            } else if match.found {
                then.append(station)
            }
        }
        return first + then
    }

    /// A name as the site compares names (`rail-discovery.js` `norm`): 臺
    /// read as 台, without spaces, in lower case.
    public static func normalized(_ name: String) -> String {
        String(name.replacingOccurrences(of: "臺", with: "台").filter { !$0.isWhitespace }).lowercased()
    }

    private static func system(_ id: String) throws -> System {
        guard let system = System.all.first(where: { $0.id == id }) else { throw LoadError.unknownSystem(id) }
        return system
    }

    private static func palette(_ lineKey: String, in system: System) throws -> Palette {
        guard let color = system.color(ofLine: lineKey) else { throw LoadError.noOfficialColor(lineKey: lineKey) }
        return Palette(color: color)
    }

    /// GeoJSON's `[longitude, latitude]`.
    private static func coordinate(_ pair: [Double]) throws -> Coordinate {
        guard pair.count == 2, abs(pair[1]) <= 90, abs(pair[0]) <= 180 else { throw LoadError.invalidCoordinate }
        return Coordinate(latitude: pair[1], longitude: pair[0])
    }
}

extension RealRailways {
    /// A latitude and longitude box.
    struct Box: Sendable {
        let south: Double
        let north: Double
        let west: Double
        let east: Double

        init(_ points: [Coordinate]) {
            south = points.map(\.latitude).min() ?? 0
            north = points.map(\.latitude).max() ?? 0
            west = points.map(\.longitude).min() ?? 0
            east = points.map(\.longitude).max() ?? 0
        }

        /// The box reaching `metres` each way from `anchor`: a degree of
        /// latitude is 111,320 m, a degree of longitude that times the
        /// cosine of the latitude. Not across 180°: Taiwan is far from it.
        init(around anchor: GeoAnchor, metres: Double) {
            let metresPerDegree = 111_320.0
            let latitude = anchor.latitudeDegrees, longitude = anchor.longitudeDegrees
            let across = metres / metresPerDegree
            let along = metres / (metresPerDegree * max(cos(latitude * .pi / 180), 0.01))
            south = latitude - across
            north = latitude + across
            west = longitude - along
            east = longitude + along
        }

        func overlaps(_ other: Box) -> Bool {
            south <= other.north && other.south <= north && west <= other.east && other.west <= east
        }

        func contains(_ point: Coordinate) -> Bool {
            (south ... north).contains(point.latitude) && (west ... east).contains(point.longitude)
        }
    }

    // MARK: - The site's files

    private struct FeatureCollection<Properties: Decodable, Geometry: Decodable>: Decodable {
        struct Feature: Decodable {
            let properties: Properties
            let geometry: Geometry
        }

        let features: [Feature]
    }

    private struct LineGeometry: Decodable {
        let coordinates: [[Double]]
    }

    private struct PointGeometry: Decodable {
        let coordinates: [Double]
    }

    /// A line's piece: its system, name, drawing order and key (the system
    /// and the line, shared by its pieces and its stations).
    private struct LineProperties: Decodable {
        let sys: String
        let name: String
        let sortKey: Int
        let lineKey: String
    }

    /// A station on a line.
    private struct StationProperties: Decodable {
        let sys: String
        let name: String
        let lineKey: String
    }

    /// `i18n/stations.json`: each system's stations by their Chinese name.
    private struct NameFile: Decodable {
        struct Name: Decodable {
            let en: String?
        }

        let systems: [String: [String: Name]]
    }
}

extension RealRailways {
    /// The station nearest to `coordinate`, if one lies within `maximumDistanceMetres`.
    public func nearestStation(to coordinate: Coordinate, maximumDistanceMetres: Double? = nil) -> (station: Station, distanceMetres: Double)? {
        var best: (station: Station, distanceMetres: Double)?
        for s in stations {
            let dist = coordinate.distance(to: s.coordinate)
            if let maxDist = maximumDistanceMetres, dist > maxDist { continue }
            if best == nil || dist < best!.distanceMetres {
                best = (s, dist)
            }
        }
        return best
    }

    /// The stations near `coordinate`, sorted from nearest to furthest.
    public func nearbyStations(to coordinate: Coordinate, maximumDistanceMetres: Double? = nil) -> [(station: Station, distanceMetres: Double)] {
        var result: [(station: Station, distanceMetres: Double)] = []
        for s in stations {
            let dist = coordinate.distance(to: s.coordinate)
            if let maxDist = maximumDistanceMetres, dist > maxDist { continue }
            result.append((s, dist))
        }
        result.sort { $0.distanceMetres < $1.distanceMetres }
        return result
    }
}

