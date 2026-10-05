import Foundation
import GameCore

// Taiwan's real railways under a real-world map (after Stage E2, ARCHITECTURE
// decision 50): the lines and stations the owner's `Railway/` site draws
// under its map, ported with its data as it is. The app bundles the site's
// own files and draws them on Apple's map, under the map's labels as the
// site draws them under MapLibre's; the real-world picker lists the
// stations as places to start at.
//
// None of it is the game's: the rules never see a real railway, a save
// keeps nothing of it, and the player builds their own railway over it.
//
// Sources (`Railway/site_archive_clean/`):
// - `data/track_lines.geojson` and `data/track_stations.geojson`: every
//   line's shape and stations, with the colours the site draws them in
//   (`railMix` mixed in advance for each look);
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
    }

    /// A railway operator's network, in the site's order (`index.html`'s
    /// systems).
    public struct System: Hashable, Sendable, Identifiable {
        /// The site's key, such as `tra_sched` or `mrt`.
        public let id: String
        let english: String
        let chinese: String

        /// The site's label, and its English translation
        /// (`i18n/translations.js`).
        public func name(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }

        public static let all: [System] = [
            System(id: "tra_sched", english: "TRA", chinese: "台鐵"),
            System(id: "thsr_sched", english: "High Speed Rail", chinese: "高鐵"),
            System(id: "afr_sched", english: "Alishan Forest Railway", chinese: "阿里山林鐵"),
            System(id: "mrt", english: "Taipei Metro", chinese: "台北捷運"),
            System(id: "tymc", english: "Taoyuan Airport MRT", chinese: "桃園機捷"),
            System(id: "ntdlrt", english: "Danhai Light Rail", chinese: "淡海輕軌"),
            System(id: "ntalrt", english: "Ankeng Light Rail", chinese: "安坑輕軌"),
            System(id: "sanying", english: "Sanying Line", chinese: "三鶯線"),
            System(id: "krtc", english: "Kaohsiung Metro", chinese: "高雄捷運"),
            System(id: "tmrt", english: "Taichung Metro", chinese: "台中捷運"),
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

    /// The colours the site draws one line or station in, one for each
    /// track display and map theme.
    public struct Palette: Hashable, Sendable {
        let color: RGB
        let colorDark: RGB
        let colorFaintLight: RGB
        let colorFaintDark: RGB
        let colorFaintSat: RGB
        let colorHiddenLight: RGB
        let colorHiddenDark: RGB
        let colorHiddenSat: RGB

        /// The colour for `style` on `theme` (`track_style_layers.json`'s
        /// states).
        public func color(_ style: TrackStyle, on theme: MapTheme) -> RGB {
            switch (style, theme) {
            case (.auto, .light), (.auto, .satellite): color
            case (.auto, .dark): colorDark
            case (.faint, .light): colorFaintLight
            case (.faint, .dark): colorFaintDark
            case (.faint, .satellite): colorFaintSat
            case (.hidden, .light): colorHiddenLight
            case (.hidden, .dark): colorHiddenDark
            case (.hidden, .satellite): colorHiddenSat
            }
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
        let chinese: String
        let english: String?
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
        case invalidColor(String)
        case invalidCoordinate
        case unknownSystem(String)
    }

    public let lines: [Line]
    /// Every station the site draws.
    public let stationMarks: [StationMark]
    /// Every station once in each system, in the site's order.
    public let stations: [Station]

    /// The railways in the site's `track_lines.geojson`,
    /// `track_stations.geojson` and `i18n/stations.json`.
    public init(lines linesFile: Data, stations stationsFile: Data, names namesFile: Data) throws {
        let decoder = JSONDecoder()
        let lineFeatures = try decoder.decode(FeatureCollection<LineProperties, LineGeometry>.self, from: linesFile).features
        let stationFeatures = try decoder.decode(FeatureCollection<StationProperties, PointGeometry>.self, from: stationsFile).features
        let names = try decoder.decode(NameFile.self, from: namesFile).systems

        lines = try lineFeatures.enumerated().map { index, feature in
            let points = try feature.geometry.coordinates.map(Self.coordinate)
            guard points.count >= 2 else { throw LoadError.invalidCoordinate }
            return Line(
                id: index,
                system: try Self.system(feature.properties.sys),
                name: feature.properties.name,
                sortKey: feature.properties.sortKey,
                palette: try feature.properties.palette.read(),
                points: points,
                box: Box(points)
            )
        }
        stationMarks = try stationFeatures.map { feature in
            StationMark(
                system: try Self.system(feature.properties.sys),
                coordinate: try Self.coordinate(feature.geometry.coordinates),
                palette: try feature.properties.palette.read()
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

    /// The colours every feature carries.
    private struct PaletteProperties: Decodable {
        let color: String
        let colorDark: String
        let colorFaintLight: String
        let colorFaintDark: String
        let colorFaintSat: String
        let colorHiddenLight: String
        let colorHiddenDark: String
        let colorHiddenSat: String

        func read() throws -> Palette {
            func rgb(_ hex: String) throws -> RGB {
                guard let rgb = RGB(hex: hex) else { throw LoadError.invalidColor(hex) }
                return rgb
            }
            return Palette(
                color: try rgb(color),
                colorDark: try rgb(colorDark),
                colorFaintLight: try rgb(colorFaintLight),
                colorFaintDark: try rgb(colorFaintDark),
                colorFaintSat: try rgb(colorFaintSat),
                colorHiddenLight: try rgb(colorHiddenLight),
                colorHiddenDark: try rgb(colorHiddenDark),
                colorHiddenSat: try rgb(colorHiddenSat)
            )
        }
    }

    private struct LineProperties: Decodable {
        let sys: String
        let name: String
        let sortKey: Int
        let palette: PaletteProperties

        enum CodingKeys: String, CodingKey {
            case sys, name, sortKey
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sys = try container.decode(String.self, forKey: .sys)
            name = try container.decode(String.self, forKey: .name)
            sortKey = try container.decode(Int.self, forKey: .sortKey)
            palette = try PaletteProperties(from: decoder)
        }
    }

    private struct StationProperties: Decodable {
        let sys: String
        let name: String
        let palette: PaletteProperties

        enum CodingKeys: String, CodingKey {
            case sys, name
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sys = try container.decode(String.self, forKey: .sys)
            name = try container.decode(String.self, forKey: .name)
            palette = try PaletteProperties(from: decoder)
        }
    }

    /// `i18n/stations.json`: each system's stations by their Chinese name.
    private struct NameFile: Decodable {
        struct Name: Decodable {
            let en: String?
        }

        let systems: [String: [String: Name]]
    }
}
