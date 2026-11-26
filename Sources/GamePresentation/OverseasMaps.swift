import Foundation
import GameCore

// Decision 697: the real railways of cities outside Taiwan. The owner's
// idea (2026-11-11) is that an international airport's flights open an
// overseas city's map, Hong Kong first. This is the data's side of it: the
// city's lines are one self-contained folder, its map pack
// (`Resources/MapPacks/hongkong`, made by `tools/hk-map/`), in the formats
// and under the file names of Taiwan's, and read only for a city that is
// open (``OverseasMaps/open``; Hong Kong since decision 712's third pull
// request). The flights that let a player onto its map are ``AirRoutes``.

/// A city outside Taiwan whose real railways the app bundles.
public enum OverseasMap: String, CaseIterable, Sendable, Hashable {
    /// Hong Kong: the MTR's ten heavy-rail lines.
    case hongKong
    /// Decision 789: Rovaniemi in Finnish Lapland, from Muurola to
    /// Kemijärvi: VR's Kemijärvi line and the main line's end on the map,
    /// with Fintraffic's real timetables. Decision 818: open, and offered
    /// from the start, with no flights to open it.
    case rovaniemi
    /// Decision 854: Fukuoka, Japan's first map: the Fukuoka City Subway's
    /// three lines, with headways estimated (no published timetable).
    /// Open since FUKUOKA-OPEN, reached by flights to Fukuoka Airport as
    /// Hong Kong is (``AirRoutes``).
    case fukuoka

    /// The system its lines are (``RealRailways/System/id``, and the key of
    /// its `<key>.json` and `<key>_times.json`).
    public var system: String {
        switch self {
        case .hongKong: "hkmtr"
        case .rovaniemi: "vr"
        case .fukuoka: "fksubway"
        }
    }

    /// SHINKANSEN-SALE (decision 975): every system whose lines are on its
    /// map, ``system`` first: Japan's map has the Fukuoka City Subway's and
    /// the Kyushu Shinkansen's (`kyushushinkansen.json`), another
    /// company's, on another gauge.
    public var systems: [String] {
        switch self {
        case .hongKong, .rovaniemi: [system]
        case .fukuoka: [system, "kyushushinkansen"]
        }
    }

    /// The map the lines of the system `id` are on, or `nil` for one of
    /// Taiwan's.
    public static func map(ofSystem id: String) -> OverseasMap? {
        allCases.first { $0.systems.contains(id) }
    }

    /// Its map pack's folder (`MapPacks/hongkong`).
    public var packFolder: String {
        switch self {
        case .hongKong: "hongkong"
        case .rovaniemi: "rovaniemi"
        case .fukuoka: "fukuoka"
        }
    }

    /// Decision 818: whether flights open its map (decision 712), or the
    /// map picker offers it from the start: Hong Kong is opened by an
    /// airport's flights; Rovaniemi, the winter event's map, is not.
    public var opensByFlights: Bool {
        switch self {
        case .hongKong: true
        case .rovaniemi: false
        // Decision 854: Fukuoka Airport's station is on the Kuko Line.
        case .fukuoka: true
        }
    }

    /// Decision 845: whether its stations' own names are written in Latin
    /// letters, so their English name is the one on their signs: Finnish
    /// in Rovaniemi; Hong Kong's are Chinese and English.
    public var namesInLatin: Bool {
        switch self {
        case .hongKong: false
        case .rovaniemi: true
        // Its names are Japanese, in kanji: the second name is English.
        case .fukuoka: false
        }
    }

    /// Where its map is opened: Hong Kong International Airport's station
    /// on the Airport Express, where the flights will land.
    public var arrival: RealRailways.Coordinate {
        switch self {
        case .hongKong: RealRailways.Coordinate(latitude: 22.315901, longitude: 113.936517)
        // Rovaniemi's station, where the Kemijärvi line and the main line
        // meet (the airport has no railway).
        case .rovaniemi: RealRailways.Coordinate(latitude: 66.498045, longitude: 25.705274)
        // Fukuoka Airport's station on the Kuko Line, where the flights
        // will land (the pack's own point).
        case .fukuoka: RealRailways.Coordinate(latitude: 33.597347, longitude: 130.448069)
        }
    }
}

/// A city's map pack: one folder that holds everything of the city the
/// game reads (`pack.json` says what is in it and where each part comes
/// from). It is in the app's bundle today; the owner's plan (2026-11-11) is
/// to download it apart from the app, and a downloaded pack is read the
/// same way, from its folder.
public struct MapPack: Sendable {
    /// The pack's folder: the one its `pack.json` is in.
    public let root: URL

    /// Decision 819: where a file of the pack lies when it is not in
    /// ``root`` (a downloaded asset pack hands out a URL per file), by its
    /// name in `pack.json`.
    private let located: [String: URL]

    public init(root: URL) {
        self.init(root: root, files: [:])
    }

    /// Decision 819: a pack whose files lie at `files` (by their names in
    /// `pack.json`); a file not among them is looked for in `root`.
    public init(root: URL, files: [String: URL]) {
        self.root = root
        located = files
    }

    /// Where the pack's file `name` (its name in `pack.json`) lies.
    public func url(of name: String) -> URL {
        located[name] ?? Self.place(of: name, root: root)
    }

    /// Decision 991: where the file `name` of the pack in `root` lies in
    /// its folders: in `root`, or, for a name with a folder in it
    /// (`fukuoka-kumamoto/basemap.pmtiles`), in that folder beside `root`,
    /// a part of the map downloaded apart (``OverseasMap/partFolders``).
    public static func place(of name: String, root: URL) -> URL {
        name.contains("/") ? root.deletingLastPathComponent().appendingPathComponent(name) : root.appendingPathComponent(name)
    }

    /// Decision 991: the names of the files the pack's `pack.json` lists,
    /// sorted; none when it cannot be read.
    public var listedFiles: [String] {
        struct Manifest: Decodable {
            let files: [String: FileEntry]
            struct FileEntry: Decodable {}
        }
        guard let data = try? file("pack", "json"), let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.files.keys.sorted()
    }

    /// Decision 991: the files named `name` of the pack and of its parts
    /// (``place(of:root:)``) that are there: the pack's own first, then its
    /// parts' in the order of their names.
    func files(named name: String) -> [URL] {
        let parts = listedFiles.filter { $0.contains("/") && ($0 as NSString).lastPathComponent == name }
        return ([name] + parts).map(url(of:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The contents of the pack's file `name.ext`.
    public func file(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: url(of: "\(name).\(ext)"))
    }

    /// Decision 712: the pack's base map (`basemap.pmtiles`: OpenStreetMap
    /// in the layers of Taiwan's, `tools/hk-map/build_hk_basemap.py`), or
    /// `nil` for a pack without one.
    public var baseMapFile: URL? {
        let file = url(of: "basemap.pmtiles")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Decision 991: the base maps of the pack and of its parts, its own
    /// first: each holds tiles none of the others does, so a tile is read
    /// from the first that has it.
    public var baseMapFiles: [URL] {
        files(named: "basemap.pmtiles")
    }

    /// Decision 712: the pack's buildings (`buildings.pmtiles`:
    /// OpenStreetMap's, in the format of Taiwan's footprint tiles,
    /// `tools/hk-map/build_hk_buildings.py`), or `nil` for a pack without
    /// them: its 3D map then has only the towns the game grows.
    public var buildingsFile: URL? {
        let file = url(of: "buildings.pmtiles")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Decision 991: the buildings of the pack and of its parts, its own
    /// first, as ``baseMapFiles``.
    public var buildingsFiles: [URL] {
        files(named: "buildings.pmtiles")
    }

    /// Decision 726: the pack's hill shading for its 2D map
    /// (`terrain.pmtiles`: its heights as Terrarium tiles, as Taiwan's
    /// `taiwan_terrain.pmtiles`, `tools/hk-map/build_hk_ground_grids.py`),
    /// or `nil` for a pack without it: its map is then not shaded.
    public var terrainFile: URL? {
        let file = url(of: "terrain.pmtiles")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Decision 733: the pack's land no town is built on and no one lives
    /// on, its airports' buildings among it (`no_build.json`, in the form
    /// of Taiwan's `taiwan_no_build.json`), with its airports' runways,
    /// taxiways, aprons and stands (`airfields.json`, as Taiwan's
    /// `taiwan_airfields.json`) when `airfields` is true and it has them;
    /// `nil` for a pack without the land, or with it out of shape.
    public func noBuildLand(airfields: Bool = true) -> RealNoBuildLand? {
        guard var land = (try? file("no_build", "json")).flatMap({ try? RealNoBuildLand(data: $0) }) else { return nil }
        if airfields { land.airfields = self.airfields() }
        return land
    }

    /// Decision 733: the pack's airfields (`airfields.json`), `nil` for a
    /// pack without them, or with them out of shape.
    public func airfields() -> RealAirfields? {
        (try? file("airfields", "json")).flatMap { try? RealAirfields(data: $0) }
    }

    /// The pack of `city` in the app's bundle (`MapPacks/<folder>`), `nil`
    /// when the app does not carry it. Decision 858: the app people
    /// install carries only each city's `pack.json`
    /// (``carriedManifest(_:)``), its files come as a download
    /// (``MapPackDownloads``); the Debug app, which the Simulator and the
    /// UI tests run and which cannot download, carries the whole pack.
    public static func bundled(_ city: OverseasMap) -> MapPack? {
        carried[city]
    }

    /// Decision 858: the app's own copy of the city's `pack.json`, which
    /// says what its pack holds and how far its map reaches; `nil` in an
    /// app without it.
    public static func carriedManifest(_ city: OverseasMap) -> Data? {
        carriedFolder(city).flatMap { try? Data(contentsOf: $0.appendingPathComponent("pack.json")) }
    }

    private static func carriedFolder(_ city: OverseasMap) -> URL? {
        Bundle.main.resourceURL.map { $0.appendingPathComponent("MapPacks").appendingPathComponent(city.packFolder) }
    }

    /// The packs the app carries whole, looked at once: the bundle does
    /// not change while the app runs.
    private static let carried: [OverseasMap: MapPack] = Dictionary(uniqueKeysWithValues: OverseasMap.allCases.compactMap { city in
        guard let folder = carriedFolder(city), isWhole(folder) else { return nil }
        return (city, MapPack(root: folder))
    })

    /// Decision 858: whether `folder` holds a pack with its files, not
    /// its `pack.json` alone: every file the `pack.json` lists is there.
    static func isWhole(_ folder: URL) -> Bool {
        struct Manifest: Decodable {
            let files: [String: FileEntry]
            struct FileEntry: Decodable {}
        }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("pack.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), !manifest.files.isEmpty
        else { return false }
        return manifest.files.keys.allSatisfy { FileManager.default.fileExists(atPath: place(of: $0, root: folder).path) }
    }
}

// Decision 712: a city's map is as large as its pack says (`pack.json`'s
// `extent`), not the 16 km square of any other place outside Taiwan: Hong
// Kong's railways reach 35 km by 32 km, and the Airport Express alone 25 km.
// Its land is the pack's people (`population.json`, WorldPop's grid in the
// format of Taiwan's), read in round each station as the whole of Taiwan's
// is (decision 88).

extension MapPack {
    /// How far the city's map reaches, in degrees (`pack.json`'s `extent`).
    public struct Extent: Decodable, Hashable, Sendable {
        public let north: Double
        public let south: Double
        public let west: Double
        public let east: Double

        public init(north: Double, south: Double, west: Double, east: Double) {
            self.north = north
            self.south = south
            self.west = west
            self.east = east
        }

        /// The middle of the box, as ``WholeTaiwan/anchor`` works its own
        /// out: halfway in longitude, and at the latitude halfway between
        /// its edges in Web Mercator. `nil` for a box that is not on the
        /// Earth the right way up.
        public var anchor: GeoAnchor? {
            guard north > south, east > west, north < 85, south > -85, west >= -180, east <= 180 else { return nil }
            let y = (RealWorldFrame.mercatorY(north) + RealWorldFrame.mercatorY(south)) / 2
            let latitude = asin(tanh((0.5 - y / RealWorldFrame.worldPoints) * 2 * Double.pi)) * 180 / .pi
            return GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: (west + east) / 2)
        }

        /// The world round ``anchor`` that holds the box, as
        /// ``WholeTaiwan/bounds``: `nil` for a box larger than a world.
        public var bounds: WorldBounds? {
            guard let anchor else { return nil }
            let frame = RealWorldFrame(anchor: anchor, bounds: .standard)
            let corners = [(north, west), (south, east)].map { frame.worldPosition(latitude: $0.0, longitude: $0.1) }
            let halfWidth = corners.map { abs($0.x - frame.middleX) }.max() ?? 0
            let halfHeight = corners.map { abs($0.y - frame.middleY) }.max() ?? 0
            return try? WorldBounds(width: Int64((2 * halfWidth).rounded(.up)), height: Int64((2 * halfHeight).rounded(.up)))
        }

        /// Whether the place lies in the box.
        public func holds(latitude: Double, longitude: Double) -> Bool {
            south <= latitude && latitude <= north && west <= longitude && longitude <= east
        }
    }

    /// The pack's `extent`.
    public func extent() throws -> Extent {
        try Self.extent(ofManifest: file("pack", "json"))
    }

    /// The `extent` a `pack.json` (`manifest`) gives.
    public static func extent(ofManifest manifest: Data) throws -> Extent {
        try extents(ofManifest: manifest).extent
    }

    /// Decision 969: the `extent` a `pack.json` (`manifest`) gives and,
    /// oldest first, the extents its map had before it grew (`earlier`;
    /// none for a map that never did). A map grows to the south and the
    /// east only: each earlier extent has the map's north and west edges
    /// and lies within the one after it, so a world laid over one keeps
    /// its north-west corner, and everything in it its place, as the map
    /// grows. Throws for an `earlier` that does not.
    public static func extents(ofManifest manifest: Data) throws -> (extent: Extent, earlier: [Extent]) {
        let read = try JSONDecoder().decode(Manifest.self, from: manifest)
        try checkGrowth(read.earlier ?? [], to: read.extent)
        return (read.extent, read.earlier ?? [])
    }

    /// Decision 991: what a `pack.json` says of where its map lies.
    struct Manifest: Decodable {
        let extent: Extent
        let earlier: [Extent]?
        /// Where a new game may begin, the first unless the player picks
        /// another: it owns the 2 × 2 tiles round it.
        let starts: [Start]?
        /// The maps it was before its north or west edge moved, each with
        /// its own `earlier`.
        let older: [Older]?

        struct Start: Decodable {
            let name: String
            let english: String
            let latitude: Double
            let longitude: Double
        }

        struct Older: Decodable {
            let extent: Extent
            let earlier: [Extent]?
        }
    }

    /// Throws unless each of `earlier` is the north-west part of the next,
    /// the last of `extent` (decision 969).
    static func checkGrowth(_ earlier: [Extent], to extent: Extent) throws {
        let stages = earlier + [extent]
        for (before, after) in zip(stages, stages.dropFirst()) {
            guard before.north == after.north, before.west == after.west, before.south >= after.south, before.east <= after.east,
                  before != after
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "pack.json: an earlier extent is not the map's north-west part"))
            }
        }
    }
}

/// Decision 858: where an open city's map lies, known from the app's own
/// `pack.json` of it while its pack is not on the device: enough to tell
/// that a saved game is on that map, so it is not played on another's
/// ground.
public struct OverseasPlace: Equatable, Sendable {
    public let city: OverseasMap
    /// Decision 969: how its map lies, now and before it grew.
    public let layout: MapPack.Layout
    public var anchor: GeoAnchor { layout.anchor }
    public var bounds: WorldBounds { layout.bounds }

    /// The place `manifest`, the city's `pack.json`, gives; `nil` when it
    /// has no extent that fits a world.
    public init?(city: OverseasMap, manifest: Data) {
        guard let layout = MapPack.Layout(manifest: manifest) else { return nil }
        self.city = city
        self.layout = layout
    }

    /// Whether `world` is this city's map (``OverseasGround/holds(_:)``):
    /// as it is now or as it was before it grew (decision 969).
    public func holds(_ world: GameWorld) -> Bool {
        layout.holds(world)
    }
}

/// The ground of a city's map (decision 712): where its world lies, how
/// far it reaches, and the people who live on it.
public struct OverseasGround: Sendable {
    public let city: OverseasMap
    /// Decision 969: how its map lies, now and before it grew.
    public let layout: MapPack.Layout
    /// Where the map lies: the middle of the part of the world that holds
    /// the pack's first extent (``MapPack/Layout/anchor``).
    public var anchor: GeoAnchor { layout.anchor }
    /// The world that holds the pack's extent.
    public var bounds: WorldBounds { layout.bounds }
    /// The city's people, or `nil` for a pack without them: its stations
    /// then get the standard ridership, and no town grows round them.
    public let population: PopulationGrid?
    /// The pack's base map, its file mapped, or `nil` for a pack without
    /// one: its 3D map then has bare ground, and its land no real roads.
    public var baseMap: Data? { baseMaps.first }
    /// Decision 991: the base maps of the pack and of its parts
    /// (``MapPack/baseMapFiles``), their files mapped, the pack's own
    /// first; none for a pack without one.
    public let baseMaps: [Data]
    /// Decision 726: the city's water, the sea, rivers and lakes, and its
    /// steep slopes (`water.json`, in the form of Taiwan's
    /// `taiwan_water.json`), or `nil` for a pack without it, or one out of
    /// shape: its sea is then land to the rules.
    public let water: WaterGrid?
    /// Decision 726: the city's ground heights (`heights.dat`, in the form
    /// of Taiwan's `taiwan_heights.dat`), or `nil` for a pack without
    /// them, or out of shape: its map is then flat.
    public let heights: HeightGrid?
    /// Decision 835: what covers the city's ground (`landcover.dat`, in
    /// the form of Taiwan's `taiwan_landcover.dat`), or `nil` for a pack
    /// without it, or one out of shape: its 3D map's countryside is then
    /// plain.
    public let landCover: LandCoverGrid?

    /// The ground `pack` says `city` has. Throws for a pack whose
    /// `pack.json` cannot be read or has no extent that fits a world; a
    /// pack with no `population.json`, or one out of shape, has no people;
    /// likewise its water and heights (decision 726) and land cover
    /// (decision 835).
    public init(city: OverseasMap, pack: MapPack) throws {
        let manifest = try pack.file("pack", "json")
        _ = try MapPack.extents(ofManifest: manifest)
        guard let layout = MapPack.Layout(manifest: manifest) else {
            throw RealRailways.ResourceError.missing("MapPacks/\(city.packFolder)/pack.json: extent")
        }
        self.city = city
        self.layout = layout
        population = (try? pack.file("population", "json")).flatMap { try? PopulationGrid(data: $0) }
        baseMaps = pack.baseMapFiles.compactMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
        water = (try? pack.file("water", "json")).flatMap { try? WaterGrid(data: $0) }
        heights = (try? pack.file("heights", "dat")).flatMap { try? HeightGrid(data: $0) }
        landCover = (try? pack.file("landcover", "dat")).flatMap { try? LandCoverGrid(data: $0) }
    }

    /// Whether `world` is this city's map: laid over its extent, or over
    /// one it had before it grew (decision 969), which ``grown(_:)`` makes
    /// the map it is now.
    public func holds(_ world: GameWorld) -> Bool {
        layout.holds(world)
    }

    /// Decision 969: `world`, on this map as it was before it grew, grown
    /// to the map as it is now (``GameWorld/growMap(to:)``): everything in
    /// it where it was, over the same places. Its company owns the tiles
    /// that hold the map's first extent (``MapPack/Layout/startTiles``),
    /// given, and buys the rest as on a map of Taiwan bought tile by tile
    /// (decision 160), each asking the riders the people of the tiles
    /// given call for (``RealWorldExpansion/ridersStep(forResidents:)``);
    /// a game that buys its map already keeps what it owns. `nil` for a
    /// world this map does not hold, or holds as it is now: a game goes on
    /// as it was.
    public func grown(_ world: GameWorld) -> GameWorld? {
        // Decision 991: a game laid over one of the map's older layouts
        // grows on it, its north-west corner where it was.
        guard let layout = layout.layout(holding: world), world.bounds != layout.bounds else { return nil }
        var grown = world
        do throws(GameError) {
            try grown.growMap(to: layout.bounds)
            // Decision 992: a map opened whole stays whole.
            if grown.mapExpansion == nil, !grown.wholeMapOpen {
                let tiles = layout.startTiles
                try grown.enableMapExpansion(owning: tiles, townSeed: nil, ridersStep: ridersStep(owning: tiles, in: grown))
            }
        } catch {
            // A world this map holds grows to it, and what it built lies
            // in the part it was, which the tiles given hold.
            return nil
        }
        return grown
    }

    /// The riders each tile bought beyond `tiles` asks of `world`: from
    /// the people of `tiles` in the pack's `population.json`
    /// (``RealWorldExpansion/ridersStep(forResidents:)``), the standard
    /// step for a pack without people.
    func ridersStep(owning tiles: [MapTile], in world: GameWorld) -> Int64 {
        guard let population, let frame = RealWorldFrame(world: world) else { return MapExpansion.standardRidersStep }
        let length = Double(MapExpansion.tileLength)
        let rows = tiles.map(\.row), columns = tiles.map(\.column)
        guard let top = rows.min(), let bottom = rows.max(), let left = columns.min(), let right = columns.max() else {
            return MapExpansion.standardRidersStep
        }
        let northWest = frame.coordinate(worldX: Double(left) * length, worldY: Double(top) * length)
        let southEast = frame.coordinate(
            worldX: min(Double(right + 1) * length, Double(world.bounds.width)), worldY: min(Double(bottom + 1) * length, Double(world.bounds.height))
        )
        let cells = population.cells(north: northWest.latitude, south: southEast.latitude, west: northWest.longitude, east: southEast.longitude)
        let residents = cells.reduce(Int64(0)) { sum, cell in
            let inside = (southEast.latitude...northWest.latitude).contains(cell.centerLatitude)
                && (northWest.longitude...southEast.longitude).contains(cell.centerLongitude)
            return inside ? sum + Int64(cell.count) : sum
        }
        return RealWorldExpansion.ridersStep(forResidents: residents)
    }
}

extension MapPack {
    /// Decision 969: how a city's map lies over the Earth, as it is now and
    /// as it was before it grew (`pack.json`'s `earlier`).
    ///
    /// A map that never grew lies as it always did: its world holds the
    /// extent round the extent's middle (``Extent/anchor``,
    /// ``Extent/bounds``). One that grew keeps the anchor and the world of
    /// its first extent, where its first games were laid, and reaches from
    /// that world's north-west corner to each later extent's south-east
    /// corner, rounded up to the next whole world unit: a game laid over
    /// the first stays over the same places as it grows.
    ///
    /// Decision 991: a map whose north or west edge moved is laid anew
    /// round its new extent (no `earlier`), a new game owning the tiles
    /// round its `start`; the games laid over it before stay as they were
    /// laid, each on an ``older`` layout that grows only to the south and
    /// the east, and only as far as the map now reaches.
    public struct Layout: Equatable, Sendable {
        /// Where the map lies: the middle of the world of its first extent.
        public let anchor: GeoAnchor
        /// The world that holds the extent now.
        public let bounds: WorldBounds
        /// The worlds of the extents it had before, oldest first: empty for
        /// a map that never grew.
        public let earlier: [WorldBounds]
        /// Decision 991: where a new game may begin (``startTiles(at:)``),
        /// the first unless the player picks another; empty for a map
        /// whose games begin where its first extent lay.
        public let starts: [Start]
        /// Decision 991: how the map lay before its north or west edge
        /// moved, for the games laid over it then; empty for a map whose
        /// edges never did.
        public let older: [Layout]

        /// Decision 991: a place a new game may begin round, by the name
        /// of its city.
        public struct Start: Equatable, Sendable {
            public let name: String
            public let englishName: String
            public let coordinate: RealRailways.Coordinate

            public init(name: String, englishName: String, coordinate: RealRailways.Coordinate) {
                self.name = name
                self.englishName = englishName
                self.coordinate = coordinate
            }
        }

        /// Where a new game begins unless the player picks another place.
        public var start: RealRailways.Coordinate? { starts.first?.coordinate }

        /// The part of the world the anchor is the middle of
        /// (``GameWorld/geoAnchorBounds``): the world of the first extent,
        /// `nil` for a map that never grew.
        public var anchorBounds: WorldBounds? { earlier.first }

        /// The layout of a map of `extent` that had the `earlier` extents
        /// before (``MapPack/extents(ofManifest:)``); `nil` when the first
        /// has no world (``Extent/bounds``) or a later one reaches too far.
        /// Decision 991: a new game begins round one of `starts` when they
        /// are given, and the games laid over the `older` layouts stay on
        /// them.
        public init?(extent: Extent, earlier extents: [Extent], starts: [Start] = [], older: [Layout] = []) {
            self.starts = starts
            self.older = older
            guard let first = extents.first else {
                guard let anchor = extent.anchor, let bounds = extent.bounds else { return nil }
                (self.anchor, self.bounds, earlier) = (anchor, bounds, [])
                return
            }
            guard let anchor = first.anchor, let start = first.bounds else { return nil }
            let frame = RealWorldFrame(anchor: anchor, bounds: start)
            var worlds = [start]
            for stage in extents.dropFirst() + [extent] {
                let corner = frame.worldPosition(latitude: stage.south, longitude: stage.east)
                guard corner.x.isFinite, corner.y.isFinite, corner.x < Double(Int64.max), corner.y < Double(Int64.max),
                      let last = worlds.last,
                      let grown = try? WorldBounds(
                          width: max(last.width, Int64(corner.x.rounded(.up))), height: max(last.height, Int64(corner.y.rounded(.up)))
                      )
                else { return nil }
                worlds.append(grown)
            }
            self.anchor = anchor
            bounds = worlds.removeLast()
            earlier = worlds
        }

        /// The layout `manifest`, a `pack.json`, gives; `nil` when it
        /// cannot be read or has no extent that fits a world.
        public init?(manifest: Data) {
            guard let read = try? JSONDecoder().decode(MapPack.Manifest.self, from: manifest),
                  (try? MapPack.checkGrowth(read.earlier ?? [], to: read.extent)) != nil
            else { return nil }
            var older: [Layout] = []
            for stage in read.older ?? [] {
                guard (try? MapPack.checkGrowth(stage.earlier ?? [], to: stage.extent)) != nil,
                      let layout = Layout(extent: stage.extent, earlier: stage.earlier ?? [])
                else { return nil }
                older.append(layout)
            }
            self.init(
                extent: read.extent, earlier: read.earlier ?? [],
                starts: (read.starts ?? []).map {
                    Start(name: $0.name, englishName: $0.english, coordinate: RealRailways.Coordinate(latitude: $0.latitude, longitude: $0.longitude))
                },
                older: older
            )
        }

        /// Whether `world` is laid over this map: as it is now, or as it was
        /// at an earlier extent (its world that size, its anchor the middle
        /// of the whole of it at the first, of the first's world after), or
        /// over one of its ``older`` layouts (decision 991).
        public func holds(_ world: GameWorld) -> Bool {
            layout(holding: world) != nil
        }

        /// Decision 991: the layout `world` is laid over: this one, one of
        /// its ``older`` ones, or `nil` for a world laid over neither.
        public func layout(holding world: GameWorld) -> Layout? {
            if world.geoAnchor == anchor {
                if world.bounds == bounds, world.geoAnchorBounds == anchorBounds { return self }
                if earlier.indices.contains(where: { index in
                    world.bounds == earlier[index] && world.geoAnchorBounds == (index == 0 ? nil : anchorBounds)
                }) { return self }
            }
            return older.lazy.compactMap { $0.layout(holding: world) }.first
        }

        /// The tiles of the map (decision 160) that hold the world of its
        /// first extent, by row and then column: those a game laid over it
        /// owns as the map grows, and a new game owns from the start. The
        /// tile of the world's north-west corner alone for a map that never
        /// grew (unused there). Decision 991: on a map with ``starts``,
        /// the 2 × 2 tiles that meet nearest the first.
        public var startTiles: [MapTile] { startTiles(at: 0) }

        /// ``startTiles`` round the `index`th of ``starts`` (decision 991),
        /// the first's for an index it does not have.
        public func startTiles(at index: Int) -> [MapTile] {
            let length = MapExpansion.tileLength
            if let start = (starts.indices.contains(index) ? starts[index] : starts.first)?.coordinate {
                let frame = RealWorldFrame(anchor: anchor, bounds: bounds)
                let point = frame.worldPosition(latitude: start.latitude, longitude: start.longitude)
                let rows = Int((bounds.height + length - 1) / length), columns = Int((bounds.width + length - 1) / length)
                func first(_ at: Double, of count: Int) -> Int {
                    min(max(Int((at / Double(length)).rounded()) - 1, 0), max(count - 2, 0))
                }
                let row = first(point.y, of: rows), column = first(point.x, of: columns)
                return (row..<min(row + 2, rows)).flatMap { row in (column..<min(column + 2, columns)).map { MapTile(row: row, column: $0) } }
            }
            let start = anchorBounds ?? bounds
            let rows = Int((start.height + length - 1) / length), columns = Int((start.width + length - 1) / length)
            return (0..<max(rows, 1)).flatMap { row in (0..<max(columns, 1)).map { MapTile(row: row, column: $0) } }
        }
    }
}

extension GameWorld {
    /// A new game on a city's map (decision 712): ``newGame(anchor:bounds:balance:eventSeed:land:)``
    /// over `ground`, its land read in as it is needed, as the whole of
    /// Taiwan's (``newWholeTaiwanGame(balance:eventSeed:)``). Decision
    /// 828: with far demand on, so a city's far stations draw less of its
    /// trips than its near ones.
    ///
    /// Decision 969: on a map that grew, the game is laid over its first
    /// extent and grown as a game played there before is
    /// (``OverseasGround/grown(_:)``), so a new game and an old one own
    /// the same tiles and buy the rest alike.
    /// Decision 991: on a map with places to begin round
    /// (``MapPack/Layout/starts``), round the `start`th of them.
    public static func newOverseasGame(_ ground: OverseasGround, balance: Money = startingBalance, eventSeed: UInt32 = 1, start: Int = 0) -> GameWorld {
        var world = newGame(
            anchor: ground.anchor, bounds: ground.layout.anchorBounds ?? ground.bounds, balance: balance, eventSeed: eventSeed, land: []
        )
        world.setLandOnDemand()
        world.setFarDemand(true)
        if let grown = ground.grown(world) { return grown }
        // Decision 991: a map laid anew round its new extent begins round
        // the place picked, the rest bought tile by tile.
        if !ground.layout.starts.isEmpty {
            let tiles = ground.layout.startTiles(at: start)
            try? world.enableMapExpansion(owning: tiles, townSeed: nil, ridersStep: ground.ridersStep(owning: tiles, in: world))
        }
        return world
    }
}

public enum OverseasMaps {
    /// The cities whose railways and ground the app reads. A player still
    /// reaches Hong Kong's map only once an airport's flights opened it
    /// (decision 712, ``AirRoutes``); Rovaniemi's is offered from the start
    /// (decision 818, ``OverseasMap/opensByFlights``); Fukuoka's by flights,
    /// as Hong Kong's (decision 854). A city not listed here is not
    /// read, offered or credited at all.
    public static let open: Set<OverseasMap> = [.hongKong, .rovaniemi, .fukuoka]
}

extension RealRailways.System {
    /// Decision 845: whether its stations' own names are written in Latin
    /// letters (``OverseasMap/namesInLatin``); Taiwan's are not.
    var namesInLatin: Bool {
        OverseasMap.map(ofSystem: id)?.namesInLatin ?? false
    }

    /// The systems of the cities outside Taiwan, which ``all`` (Taiwan's,
    /// what the pickers and the credits list) does not hold.
    public static let overseas: [OverseasMap: RealRailways.System] = [
        // MTR's line colours, as OpenStreetMap's route relations carry them
        // (`colour`; `tools/hk-map/build_hk_mtr.py` checks each against the
        // extract). The branches are their lines' colour.
        .hongKong: RealRailways.System(id: "hkmtr", english: "MTR", chinese: "港鐵", lineColors: [
            "hkmtr|AEL": RealRailways.RGB(0x00888A), "hkmtr|TCL": RealRailways.RGB(0xF7943E),
            "hkmtr|TML": RealRailways.RGB(0x923011), "hkmtr|EAL": RealRailways.RGB(0x53B7E8),
            "hkmtr|EAL_LMC": RealRailways.RGB(0x53B7E8), "hkmtr|TWL": RealRailways.RGB(0xED1D24),
            "hkmtr|ISL": RealRailways.RGB(0x007DC5), "hkmtr|KTL": RealRailways.RGB(0x00AB4E),
            "hkmtr|TKL": RealRailways.RGB(0x7D499D), "hkmtr|TKL_LHP": RealRailways.RGB(0x7D499D),
            "hkmtr|SIL": RealRailways.RGB(0xB6BD00), "hkmtr|DRL": RealRailways.RGB(0xF173AC),
        ]),
        // Decision 789: the colours are this project's
        // (`tools/rovaniemi-map/build_rovaniemi_rail.py`), OpenStreetMap's
        // relation having none.
        .rovaniemi: RealRailways.System(id: "vr", english: "VR", chinese: "芬蘭國鐵", lineColors: [
            "vr|KJA": RealRailways.RGB(0x3FA535), "vr|MUL": RealRailways.RGB(0x1E6B3A),
        ]),
        // Decision 854: OpenStreetMap's route relations' colours
        // (`tools/fukuoka-map/build_fukuoka_rail.py` checks each against
        // the extract).
        .fukuoka: RealRailways.System(id: "fksubway", english: "Fukuoka City Subway", chinese: "福岡市地鐵", lineColors: [
            "fksubway|K": RealRailways.RGB(0xFF4500), "fksubway|H": RealRailways.RGB(0x0077CC),
            "fksubway|N": RealRailways.RGB(0x008000),
        ]),
    ]

    /// SHINKANSEN-SALE (decision 975): the systems of a map that has more
    /// than one (``OverseasMap/systems``), after its first: JR Kyushu's
    /// Kyushu Shinkansen on Japan's map. The colour is this project's
    /// (`tools/fukuoka-map/build_kyushu_shinkansen.py`'s `COLOUR`;
    /// OpenStreetMap's relation has none).
    public static let overseasOthers: [RealRailways.System] = [
        RealRailways.System(id: "kyushushinkansen", english: "JR Kyushu", chinese: "JR九州", lineColors: [
            "kyushushinkansen|KS": RealRailways.RGB(0xC8102E),
        ]),
    ]

    /// Every system of the cities outside Taiwan.
    public static var everyOverseas: [RealRailways.System] {
        OverseasMap.allCases.compactMap { overseas[$0] } + overseasOthers
    }
}

extension RealBranchLine {
    /// The lines of the cities outside Taiwan that are on sale where their
    /// runs are read (``RealRailways/metroRuns``), as ``urbanLines`` lists
    /// Taiwan's: the MTR's, by `hkmtr.json`'s line ids, with MTR's own
    /// names. The two branches leave their main line at their first
    /// station (Sheung Shui, Tseung Kwan O), as the Xinbeitou Branch Line
    /// does.
    static let overseasLines: [(system: String, network: String, english: String, chinese: String, shares: String?, tier: LineAcquisition.Tier, leavesALine: Bool)] = [
        // LANE-SHARED-ISLAND (decision 753, later): the Tung Chung Line
        // first, so the three sold together (decision 862) lay its depot
        // at Siu Ho Wan before the Airport Express, now on its north side,
        // runs past the depot's leads (laid first, it left the depot no
        // way across it).
        ("hkmtr", "TCL", "Tung Chung Line", "東涌綫", nil, .metro, false),
        ("hkmtr", "AEL", "Airport Express", "機場快綫", nil, .metro, false),
        ("hkmtr", "TML", "Tuen Ma Line", "屯馬綫", nil, .metro, false),
        ("hkmtr", "EAL", "East Rail Line", "東鐵綫", nil, .metro, false),
        ("hkmtr", "EAL_LMC", "East Rail Line (Lok Ma Chau)", "東鐵綫（落馬洲）", nil, .metro, true),
        ("hkmtr", "TWL", "Tsuen Wan Line", "荃灣綫", nil, .metro, false),
        ("hkmtr", "ISL", "Island Line", "港島綫", nil, .metro, false),
        ("hkmtr", "KTL", "Kwun Tong Line", "觀塘綫", nil, .metro, false),
        ("hkmtr", "TKL", "Tseung Kwan O Line", "將軍澳綫", nil, .metro, false),
        ("hkmtr", "TKL_LHP", "Tseung Kwan O Line (LOHAS Park)", "將軍澳綫（康城）", nil, .metro, true),
        ("hkmtr", "SIL", "South Island Line", "南港島綫", nil, .metro, false),
        ("hkmtr", "DRL", "Disneyland Resort Line", "迪士尼綫", nil, .metro, false),
        // Decision 789: Rovaniemi's two lines, bought as a TRA branch line
        // is (a few long trains a day, not a metro's many short ones).
        ("vr", "KJA", "Kemijärvi Line", "凱米耶爾維線", nil, .branch, false),
        ("vr", "MUL", "Rovaniemi–Muurola", "羅瓦涅米—穆羅拉", nil, .branch, false),
        // Decision 854: the Fukuoka City Subway's three lines, bought as
        // a metro. Each runs its own stretch (the Hakozaki Line's trains
        // on to Meinohama are left out).
        ("fksubway", "K", "Kuko Line", "空港線", nil, .metro, false),
        ("fksubway", "H", "Hakozaki Line", "箱崎線", nil, .metro, false),
        ("fksubway", "N", "Nanakuma Line", "七隈線", nil, .metro, false),
        // SHINKANSEN-SALE (decision 975): the Kyushu Shinkansen, Hakata to
        // Kumamoto (the map's south edge is just past Kumamoto), every
        // train calling at every station (`build_kyushu_shinkansen.py`).
        // Another system than the subway's, so sold on its own
        // (``RealLineBundle/groups(of:)``).
        ("kyushushinkansen", "KS", "Kyushu Shinkansen", "九州新幹線", nil, .metro, false),
    ]

    /// Decision 753: the lines of the cities outside Taiwan drawn along
    /// another's track, by line id, and the line whose drawing each keeps
    /// to one side of, at least `offset` metres off it (positive on its
    /// right going up the line, as a loop's offset), wherever the two lie
    /// within ``RealLineLaying/laneReach`` of each other: the Airport
    /// Express on the right of the Tung Chung Line from Hong Kong to the
    /// airport island (the same drawing or within 8 m of it for most of
    /// the 28 km, crossing it before Tsing Yi and at Tung Chung), the
    /// Disneyland Resort Line on its left at Sunny Bay, the side it comes
    /// in from. The Tung Chung Line stays on its drawing.
    /// LANE-SHARED-ISLAND (decision 753, later): the Airport Express on
    /// the right, as above (it was laid on the left, -25, till then): at
    /// Sunny Bay it ran between the Tung Chung
    /// Line and the Disneyland Resort Line, which could then not come up
    /// to the Tung Chung Line's track across one island (the real Airport
    /// Express passes through the middle of the station, not on the
    /// Disneyland side). At the stations two lines both call at, each is
    /// held an island's width off the other (``RealLineLaying/laneIsland(at:of:runs:beside:besideLine:besideRuns:side:)``). Each is laid so
    /// whichever is bought first: decision 712 refused the second of the
    /// Airport Express and the Tung Chung Line, and both after the
    /// Disneyland Resort Line, which lay on their track at Sunny Bay.
    static let overseasLanes: [String: (beside: String, offset: Double)] = [
        "hkmtr:AEL": ("hkmtr:TCL", 25),
        "hkmtr:DRL": ("hkmtr:TCL", -45),
    ]

    /// Whether it is laid in a lane beside another's drawing, or another
    /// is laid beside its own (``overseasLanes``).
    var sharesALane: Bool {
        Self.overseasLanes[id] != nil || Self.overseasLanes.values.contains { $0.beside == id }
    }
}
