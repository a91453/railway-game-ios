import Foundation
import GameCore

/// Official station classification for Taiwan Railway (TRA) stations.
public enum TRAStationClass: String, CaseIterable, Codable, Sendable {
    case special = "特等"
    case first = "一等"
    case second = "二等"
    case third = "三等"
    case simple = "簡易"
    case classASimple = "甲簡"
    case classBSimple = "乙簡"
    case halt = "招呼"

    /// The tier level (0 to 4), matching the 5 tiers in `estLenByTier`.
    public var tier: Int {
        switch self {
        case .special: 0
        case .first: 1
        case .second: 2
        case .third: 3
        case .simple, .classASimple, .classBSimple, .halt: 4
        }
    }

    /// Localized name in the specified display language.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .special: language.text("Special Class", "特等站")
        case .first: language.text("First Class", "一等站")
        case .second: language.text("Second Class", "二等站")
        case .third: language.text("Third Class", "三等站")
        case .simple: language.text("Simple Station", "簡易站")
        case .classASimple: language.text("Class A Simple Station", "甲簡站")
        case .classBSimple: language.text("Class B Simple Station", "乙簡站")
        case .halt: language.text("Halt", "招呼站")
        }
    }
}

/// Information and coordinates of a Taiwan Railway (TRA) station from `tra_station_info.json`.
public struct TRAStationInfo: Hashable, Sendable, Codable {
    public let name: String
    public let id: String
    public let address: String
    public let latitude: Double
    public let longitude: Double
    public let feature: String

    enum CodingKeys: String, CodingKey {
        case name, id, address, feature
        case latitude = "lat"
        case longitude = "lon"
    }

    public init(name: String, id: String, address: String, latitude: Double, longitude: Double, feature: String = "") {
        self.name = name
        self.id = id
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.feature = feature
    }
}

/// A Taipei Metro (TRTC) station code (e.g. `BL01`, `R10`) from `trtc_codes.json`.
public struct TRTCStationCode: Hashable, Sendable, Codable {
    public struct Placement: Hashable, Sendable, Codable {
        public let line: String
        public let index: Int

        enum CodingKeys: String, CodingKey {
            case line = "ln"
            case index = "i"
        }

        public init(line: String, index: Int) {
            self.line = line
            self.index = index
        }
    }

    public let code: String
    public let name: String
    public let placements: [Placement]

    public init(code: String, name: String, placements: [Placement]) {
        self.code = code
        self.name = name
        self.placements = placements
    }
}

/// A physical platform endpoint geometry from OpenStreetMap via `tra_platforms.json`.
public struct TRAPlatform: Hashable, Sendable {
    public let stationName: String
    public let start: RealRailways.Coordinate
    public let end: RealRailways.Coordinate
    public let isDerived: Bool

    public init(stationName: String, start: RealRailways.Coordinate, end: RealRailways.Coordinate, isDerived: Bool) {
        self.stationName = stationName
        self.start = start
        self.end = end
        self.isDerived = isDerived
    }

    /// Calculated physical platform length in metres.
    public var lengthMetres: Double {
        start.distance(to: end)
    }
}

/// A track section between two adjacent TRA stations from `tra_track_sections.json`.
public struct TRATrackSection: Hashable, Sendable, Codable {
    public let pair: String
    public let tracks: Int
    public let parallelFrac: Double
    public let lengthM: Double
    public let maxPathM: Double
    public let refs: [String]

    public var isDoubleTrack: Bool {
        tracks >= 2
    }

    public init(pair: String, tracks: Int, parallelFrac: Double, lengthM: Double, maxPathM: Double, refs: [String]) {
        self.pair = pair
        self.tracks = tracks
        self.parallelFrac = parallelFrac
        self.lengthM = lengthM
        self.maxPathM = maxPathM
        self.refs = refs
    }
}

/// Real-world operational station data for Taiwan's railways: station classes,
/// official IDs, addresses, platform geometries, TRTC codes, and track sections.
public struct RealStationData: Sendable {
    public let stationClasses: [String: TRAStationClass]
    public let stationInfos: [String: TRAStationInfo]
    public let stationInfosByID: [String: TRAStationInfo]
    public let trtcCodes: [String: TRTCStationCode]
    public let trtcCodesByStation: [String: [String]]
    public let platforms: [String: TRAPlatform]
    public let estimatedPlatformLengthsByTier: [Double]
    public let trackSections: [String: TRATrackSection]
    /// The tracks trains can wait on to be overtaken at each TRA station
    /// (`tra_overtake_tracks.json`); `nil` without the file.
    public let overtakeTracks: TRAOvertakeTracks?

    // The source spellings each lookup key falls back to, worked out once
    // (the first, sorted, of each key) rather than on every lookup.
    private let classAliases: [String: String]
    private let infoAliases: [String: String]
    private let trtcAliases: [String: String]
    private let platformAliases: [String: String]
    private let sectionAliases: [String: String]

    public init(
        classes classesData: Data,
        infos infosData: Data,
        codes codesData: Data,
        platforms platformsData: Data,
        sections sectionsData: Data,
        overtakeTracks overtakeData: Data? = nil
    ) throws {
        let decoder = JSONDecoder()

        // 1. Station classes
        let rawClasses = try decoder.decode([String: String].self, from: classesData)
        var parsedClasses: [String: TRAStationClass] = [:]
        for (name, raw) in rawClasses {
            if let cls = TRAStationClass(rawValue: raw) {
                parsedClasses[name] = cls
            }
        }
        self.stationClasses = parsedClasses

        // 2. Station infos
        let parsedInfos = try decoder.decode([String: TRAStationInfo].self, from: infosData)
        self.stationInfos = parsedInfos
        var byID: [String: TRAStationInfo] = [:]
        for (_, info) in parsedInfos {
            byID[info.id] = info
        }
        self.stationInfosByID = byID

        // 3. TRTC codes
        struct RawTRTC: Decodable {
            let name: String
            let on: [TRTCStationCode.Placement]
        }
        let rawCodes = try decoder.decode([String: RawTRTC].self, from: codesData)
        var parsedCodes: [String: TRTCStationCode] = [:]
        var codesByName: [String: [String]] = [:]
        for (code, raw) in rawCodes {
            let item = TRTCStationCode(code: code, name: raw.name, placements: raw.on)
            parsedCodes[code] = item
            codesByName[raw.name, default: []].append(code)
        }
        for (name, list) in codesByName {
            codesByName[name] = list.sorted()
        }
        self.trtcCodes = parsedCodes
        self.trtcCodesByStation = codesByName

        // 4. Platforms
        struct RawPlatforms: Decodable {
            let estLenByTier: [Double]
            let stations: [String: [[Double]]]
            let derived: [String: [[Double]]]?
        }
        let rawPlatforms = try decoder.decode(RawPlatforms.self, from: platformsData)
        self.estimatedPlatformLengthsByTier = rawPlatforms.estLenByTier

        var parsedPlatforms: [String: TRAPlatform] = [:]
        for (name, coords) in rawPlatforms.stations {
            guard coords.count == 2, coords[0].count == 2, coords[1].count == 2 else { continue }
            let p1 = RealRailways.Coordinate(latitude: coords[0][0], longitude: coords[0][1])
            let p2 = RealRailways.Coordinate(latitude: coords[1][0], longitude: coords[1][1])
            parsedPlatforms[name] = TRAPlatform(stationName: name, start: p1, end: p2, isDerived: false)
        }
        if let derived = rawPlatforms.derived {
            for (name, coords) in derived {
                guard coords.count == 2, coords[0].count == 2, coords[1].count == 2 else { continue }
                let p1 = RealRailways.Coordinate(latitude: coords[0][0], longitude: coords[0][1])
                let p2 = RealRailways.Coordinate(latitude: coords[1][0], longitude: coords[1][1])
                parsedPlatforms[name] = TRAPlatform(stationName: name, start: p1, end: p2, isDerived: true)
            }
        }
        self.platforms = parsedPlatforms

        // 5. Track sections
        struct RawTrackSections: Decodable {
            struct RawSection: Decodable {
                let tracks: Int
                let parallelFrac: Double
                let lengthM: Double
                let maxPathM: Double
                let refs: [String]
            }
            let pairs: [String: RawSection]
        }
        let rawSections = try decoder.decode(RawTrackSections.self, from: sectionsData)
        var parsedSections: [String: TRATrackSection] = [:]
        for (pair, raw) in rawSections.pairs {
            parsedSections[pair] = TRATrackSection(
                pair: pair,
                tracks: raw.tracks,
                parallelFrac: raw.parallelFrac,
                lengthM: raw.lengthM,
                maxPathM: raw.maxPathM,
                refs: raw.refs
            )
        }
        self.trackSections = parsedSections

        // 6. Overtaking tracks
        self.overtakeTracks = try overtakeData.map(TRAOvertakeTracks.init(data:))

        classAliases = Self.aliases(parsedClasses.keys)
        infoAliases = Self.aliases(parsedInfos.keys)
        trtcAliases = Self.aliases(codesByName.keys)
        platformAliases = Self.aliases(parsedPlatforms.keys)
        var sections: [String: String] = [:]
        for key in parsedSections.keys.sorted() {
            let endpoints = key.split(separator: "|").map { Self.stationKey(String($0)) }.sorted().joined(separator: "|")
            if sections[endpoints] == nil { sections[endpoints] = key }
        }
        sectionAliases = sections
    }

    /// Each lookup key of `names`, to the first of its spellings in sorted
    /// order: stable even if a source has more than one spelling of the
    /// same station.
    fileprivate static func aliases(_ names: some Collection<String>) -> [String: String] {
        var result: [String: String] = [:]
        for name in names.sorted() {
            let key = stationKey(name)
            if result[key] == nil { result[key] = name }
        }
        return result
    }

    /// A lookup key only: source names and station identities remain intact.
    /// The reference uses the discovery names 新城 (太魯閣) and 左營(舊城)
    /// alongside the official metadata names 新城 and 左營.
    private static func stationKey(_ name: String) -> String {
        let key = RealRailways.normalized(name)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        switch key {
        case "新城(太魯閣)": return "新城"
        case "左營(舊城)": return "左營"
        default: return key
        }
    }

    private static func lookup<Value>(_ name: String, in values: [String: Value], aliases: [String: String]) -> Value? {
        if let direct = values[name] { return direct }
        // The site's own fallback (`index.html`: `clsMap[name] ||
        // clsMap[name.replace(/台/g, '臺')]`).
        if let official = values[name.replacingOccurrences(of: "台", with: "臺")] { return official }
        // Exact spellings take precedence; then the reference aliases.
        guard let key = aliases[stationKey(name)] else { return nil }
        return values[key]
    }

    /// Looks up the TRA station classification, accepting reference aliases.
    public func stationClass(forStation name: String) -> TRAStationClass? {
        Self.lookup(name, in: stationClasses, aliases: classAliases)
    }

    /// Looks up TRA station information for `name`.
    public func stationInfo(forStation name: String) -> TRAStationInfo? {
        Self.lookup(name, in: stationInfos, aliases: infoAliases)
    }

    /// Looks up TRA station information by station code (e.g. `"0900"`).
    public func stationInfo(id: String) -> TRAStationInfo? {
        stationInfosByID[id]
    }

    /// Returns TRTC station codes for station `name` (e.g. "台北車站" -> `["BL12", "R10"]`).
    public func trtcCodes(forStation name: String) -> [String] {
        Self.lookup(name, in: trtcCodesByStation, aliases: trtcAliases) ?? []
    }

    /// Returns TRTC station info for `code` (e.g. `"BL01"`).
    public func trtcStation(code: String) -> TRTCStationCode? {
        trtcCodes[code]
    }

    /// Platform geometry for `name`.
    public func platform(forStation name: String) -> TRAPlatform? {
        Self.lookup(name, in: platforms, aliases: platformAliases)
    }

    /// Estimated platform length for a class tier (0 to 4).
    public func estimatedPlatformLength(forTier tier: Int) -> Double? {
        guard tier >= 0, tier < estimatedPlatformLengthsByTier.count else { return nil }
        return estimatedPlatformLengthsByTier[tier]
    }

    /// Estimated platform length for a given station class.
    public func estimatedPlatformLength(for stationClass: TRAStationClass) -> Double? {
        estimatedPlatformLength(forTier: stationClass.tier)
    }

    /// The site's `traSectionKey(a, b)`: both names with 台 written 臺,
    /// in sorted order, joined by `|`, the key of `tra_track_sections.json`.
    public static func sectionKey(_ stationA: String, _ stationB: String) -> String {
        [stationA, stationB].map { $0.replacingOccurrences(of: "台", with: "臺") }.sorted().joined(separator: "|")
    }

    /// Track section between two stations. Order of station names does not matter.
    public func trackSection(between stationA: String, and stationB: String) -> TRATrackSection? {
        if let found = trackSections[Self.sectionKey(stationA, stationB)] { return found }
        let key1 = "\(stationA)|\(stationB)"
        let key2 = "\(stationB)|\(stationA)"
        if let found = trackSections[key1] ?? trackSections[key2] { return found }
        let endpoints = [Self.stationKey(stationA), Self.stationKey(stationB)].sorted().joined(separator: "|")
        return sectionAliases[endpoints].flatMap { trackSections[$0] }
    }

    /// Number of tracks between two stations (1 for single track, 2 for double track).
    public func tracksBetween(stationA: String, stationB: String) -> Int? {
        trackSection(between: stationA, and: stationB)?.tracks
    }

    /// Whether the section between two stations is double track; `nil`
    /// where the data has no such section (unknown, not single track).
    public func isDoubleTrack(between stationA: String, and stationB: String) -> Bool? {
        trackSection(between: stationA, and: stationB)?.isDoubleTrack
    }

    /// The overtaking tracks of TRA station `name`, accepting the same
    /// spellings as the other lookups.
    public func overtakeStation(forStation name: String) -> TRAOvertakeTracks.Station? {
        guard let stations = overtakeTracks?.stations else { return nil }
        return Self.lookup(name, in: stations, aliases: overtakeTracks?.aliases ?? [:])
    }
}

/// `tra_overtake_tracks.json`: the site's own reading of each TRA
/// station's routes (`index.html` `planSameDirectionOvertakes`).
/// `stations[name].moves["from>to|s"]` (or `|p`) are the routes a
/// movement uses at the station (`s` stopping or starting, `p` passing);
/// `dirs["from>to"]` the tracks a train passing that way can wait on, each
/// with the routes that block it.
public struct TRAOvertakeTracks: Hashable, Sendable {
    public struct Station: Hashable, Sendable, Decodable {
        public let moves: [String: [Int]]
        public let dirs: [String: [[Int]]]

        /// How many tracks a train passing each way can wait on, by the
        /// way (`"八堵>百福"`), in sorted order.
        public var waitingTracks: [(direction: String, tracks: Int)] {
            dirs.keys.sorted().map { ($0, dirs[$0]!.count) }
        }
    }

    public let version: Int
    /// Half a platform's length the site allows round a stopping point, in
    /// metres (`halfM`).
    public let halfMetres: Double
    public let stations: [String: Station]
    /// Each lookup key to its spelling here, worked out once.
    let aliases: [String: String]

    public init(data: Data) throws {
        struct Raw: Decodable {
            let version: Int
            let halfM: Double
            let stations: [String: Station]
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        version = raw.version
        halfMetres = raw.halfM
        stations = raw.stations
        aliases = RealStationData.aliases(raw.stations.keys)
    }
}
