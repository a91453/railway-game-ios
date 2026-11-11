import Foundation
import GameCore

// Decision 697: the real railways of cities outside Taiwan. The owner's
// idea (2026-11-11) is that an international airport's flights open an
// overseas city's map, Hong Kong first. This is the data's side of it: the
// city's lines are one self-contained folder, its map pack
// (`Resources/MapPacks/hongkong`, made by `tools/hk-map/`), in the formats
// and under the file names of Taiwan's, and read only for a city that is
// open. None is yet: the rule
// that opens one (the flights) is not written, so ``OverseasMaps/open`` is
// empty and the game reads, lists and sells exactly what it did.

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

    /// The pack of `city` in the app's bundle (`MapPacks/<folder>`).
    public static func bundled(_ city: OverseasMap) -> MapPack? {
        Bundle.main.resourceURL.map { MapPack(root: $0.appendingPathComponent("MapPacks").appendingPathComponent(city.packFolder)) }
    }
}

public enum OverseasMaps {
    /// The cities whose railways the game reads and sells. Empty until the
    /// flights that open one are in the game (decision 697's next step):
    /// with it empty no player can reach an overseas line.
    public static let open: Set<OverseasMap> = []
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
}
