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

    /// The system its lines are (``RealRailways/System/id``, and the key of
    /// its `<key>.json` and `<key>_times.json`).
    public var system: String {
        switch self {
        case .hongKong: "hkmtr"
        }
    }

    /// Its map pack's folder (`MapPacks/hongkong`).
    public var packFolder: String {
        switch self {
        case .hongKong: "hongkong"
        }
    }

    /// Where its map is opened: Hong Kong International Airport's station
    /// on the Airport Express, where the flights will land.
    public var arrival: RealRailways.Coordinate {
        switch self {
        case .hongKong: RealRailways.Coordinate(latitude: 22.315901, longitude: 113.936517)
        }
    }
}

/// A city's map pack: one folder that holds everything of the city the
/// game reads (`pack.json` says what is in it and where each part comes
/// from). It is in the app's bundle today; the owner's plan (2026-11-11) is
/// to download it apart from the app, and a downloaded pack is read the
/// same way, from its folder.
public struct MapPack: Sendable {
    /// The pack's folder.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The contents of the pack's file `name.ext`.
    public func file(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("\(name).\(ext)"))
    }

    /// Decision 712: the pack's base map (`basemap.pmtiles`: OpenStreetMap
    /// in the layers of Taiwan's, `tools/hk-map/build_hk_basemap.py`), or
    /// `nil` for a pack without one.
    public var baseMapFile: URL? {
        let file = root.appendingPathComponent("basemap.pmtiles")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Decision 712: the pack's buildings (`buildings.pmtiles`:
    /// OpenStreetMap's, in the format of Taiwan's footprint tiles,
    /// `tools/hk-map/build_hk_buildings.py`), or `nil` for a pack without
    /// them: its 3D map then has only the towns the game grows.
    public var buildingsFile: URL? {
        let file = root.appendingPathComponent("buildings.pmtiles")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The pack of `city` in the app's bundle (`MapPacks/<folder>`).
    public static func bundled(_ city: OverseasMap) -> MapPack? {
        Bundle.main.resourceURL.map { MapPack(root: $0.appendingPathComponent("MapPacks").appendingPathComponent(city.packFolder)) }
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
        struct Manifest: Decodable {
            let extent: Extent
        }
        return try JSONDecoder().decode(Manifest.self, from: file("pack", "json")).extent
    }
}

/// The ground of a city's map (decision 712): where its world lies, how
/// far it reaches, and the people who live on it.
public struct OverseasGround: Sendable {
    public let city: OverseasMap
    /// The middle of the map.
    public let anchor: GeoAnchor
    /// The world that holds the pack's extent.
    public let bounds: WorldBounds
    /// The city's people, or `nil` for a pack without them: its stations
    /// then get the standard ridership, and no town grows round them.
    public let population: PopulationGrid?
    /// The pack's base map, its file mapped, or `nil` for a pack without
    /// one: its 3D map then has bare ground, and its land no real roads.
    public let baseMap: Data?

    /// The ground `pack` says `city` has. Throws for a pack whose
    /// `pack.json` cannot be read or has no extent that fits a world; a
    /// pack with no `population.json`, or one out of shape, has no people.
    public init(city: OverseasMap, pack: MapPack) throws {
        let extent = try pack.extent()
        guard let anchor = extent.anchor, let bounds = extent.bounds else {
            throw RealRailways.ResourceError.missing("MapPacks/\(city.packFolder)/pack.json: extent")
        }
        self.city = city
        self.anchor = anchor
        self.bounds = bounds
        population = (try? pack.file("population", "json")).flatMap { try? PopulationGrid(data: $0) }
        baseMap = pack.baseMapFile.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
    }

    /// Whether `world` is this city's map: laid over its extent.
    public func holds(_ world: GameWorld) -> Bool {
        world.geoAnchor == anchor && world.bounds == bounds
    }
}

extension GameWorld {
    /// A new game on a city's map (decision 712): ``newGame(anchor:bounds:balance:eventSeed:land:)``
    /// over `ground`, its land read in as it is needed, as the whole of
    /// Taiwan's (``newWholeTaiwanGame(balance:eventSeed:)``).
    public static func newOverseasGame(_ ground: OverseasGround, balance: Money = startingBalance, eventSeed: UInt32 = 1) -> GameWorld {
        var world = newGame(anchor: ground.anchor, bounds: ground.bounds, balance: balance, eventSeed: eventSeed, land: [])
        world.setLandOnDemand()
        return world
    }
}

public enum OverseasMaps {
    /// The cities whose railways and ground the app reads. A player still
    /// reaches a city's map only once an airport's flights opened it
    /// (decision 712, ``AirRoutes``); a city not listed here is not read,
    /// offered or credited at all.
    public static let open: Set<OverseasMap> = [.hongKong]
}

extension RealRailways.System {
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
    ]
}

extension RealBranchLine {
    /// The lines of the cities outside Taiwan that are on sale where their
    /// runs are read (``RealRailways/metroRuns``), as ``urbanLines`` lists
    /// Taiwan's: the MTR's, by `hkmtr.json`'s line ids, with MTR's own
    /// names. The two branches leave their main line at their first
    /// station (Sheung Shui, Tseung Kwan O), as the Xinbeitou Branch Line
    /// does.
    static let overseasLines: [(system: String, network: String, english: String, chinese: String, shares: String?, tier: LineAcquisition.Tier, leavesALine: Bool)] = [
        ("hkmtr", "AEL", "Airport Express", "機場快綫", nil, .metro, false),
        ("hkmtr", "TCL", "Tung Chung Line", "東涌綫", nil, .metro, false),
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
    ]

    /// Decision 712: the lines of the cities outside Taiwan drawn along one
    /// another's track for much of their way, by line id: the Airport
    /// Express and the Tung Chung Line, the same drawing or within 8 m of
    /// it for most of the 28 km from Hong Kong to the airport island. A
    /// line bought is laid on track of its own, 4 m and more from any
    /// other, so whichever of the two came second was refused for its
    /// track, after a minute's trying to lift it clear. A company that
    /// owns one is told it cannot buy the other, at once.
    static let overseasLinesOnOneTrack: [Set<String>] = [["hkmtr:AEL", "hkmtr:TCL"]]

    /// The names of the line whose track this one is drawn along
    /// (``overseasLinesOnOneTrack``) that `owned` says the company has, or
    /// `nil`.
    func lineOnItsTrack(owned: (String) -> Bool) -> (english: String, chinese: String)? {
        for lines in Self.overseasLinesOnOneTrack where lines.contains(id) {
            for other in lines.sorted() where other != id && owned(other) {
                if let found = Self.overseasLines.first(where: { "\($0.system):\($0.network)" == other }) { return (found.english, found.chinese) }
            }
        }
        return nil
    }
}
