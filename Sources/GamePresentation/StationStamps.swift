import Foundation
import GameCore

// Station stamps (decision 348): Taiwan's stations keep a commemorative
// stamp for travellers, and a real station the player's trains served
// yesterday is stamped into a passport kept on the device, beside the
// achievements. The passport's pages and the place of each stamp on its
// page are the reference's (`Ci/reference_snapshot/lib/voyager-passport.js`:
// `paginateStamps`, `stampLayout`, `stampDateLabel`). Nothing here is game
// state: the record is a file beside the saves, and GameCore is untouched.

/// The ink a stamp is printed in, by its railway: a theme colour each, in
/// the hue of the operator's own (TRA's blue, the High Speed Rail's orange,
/// the forest railway's and the light rails' red, the metros' teal).
public enum StationStampInk: Hashable, Sendable {
    case navy, amber, red, teal

    public init(system: String) {
        switch system {
        case "tra_sched": self = .navy
        case "thsr_sched": self = .amber
        case "afr_sched", "ntdlrt", "ntalrt": self = .red
        default: self = .teal
        }
    }
}

/// A stamp in the passport: a real station, and when it was collected.
public struct StationStamp: Codable, Hashable, Sendable, Identifiable {
    /// The place (``RealRailways/stationKey(_:)``): 台北 of TRA, the High
    /// Speed Rail and the metro is one stamp.
    public let key: String
    public let chinese: String
    public let english: String?
    /// The railway it was first collected on (``RealRailways/System/id``).
    public let system: String
    public let earned: Date

    public var id: String { key }

    public init(key: String, chinese: String, english: String?, system: String, earned: Date) {
        self.key = key
        self.chinese = chinese
        self.english = english
        self.system = system
        self.earned = earned
    }

    public func name(in language: DisplayLanguage) -> String {
        language.text(english.map(RealRailways.Station.shown) ?? chinese, chinese)
    }

    public var ink: StationStampInk { StationStampInk(system: system) }
}

/// Which real stations a game's stations are.
public enum StationStamps {
    /// A real station, as a stamp names it.
    public struct RealStation: Hashable, Sendable {
        public let key: String
        public let chinese: String
        public let english: String?
        public let system: String
        /// The game's station that is it (decision 353: where the map
        /// shows a new stamp); `nil` where none was asked.
        public let station: StationID?

        public init(key: String, chinese: String, english: String?, system: String, station: StationID? = nil) {
            self.key = key
            self.chinese = chinese
            self.english = english
            self.system = system
            self.station = station
        }
    }

    /// The stations of `world` passengers got on or off at yesterday: not
    /// depots, not closed.
    public static func served(in world: GameWorld) -> [Station] {
        world.stations.filter { station in
            guard !station.isDepot, station.operationMode != .closed else { return false }
            let flow = world.stationFlowYesterday(station.id)
            return flow.boarded > 0 || flow.alighted > 0
        }
    }

    /// The real stations `stations` of `world` are, each place once, in
    /// their order: a station named as a real one within its transfer
    /// distance (``RealRailways/stations(named:near:)``), the first system
    /// in the site's order naming it. None on a map that is not a real one.
    public static func realStations(of stations: [Station], in world: GameWorld, railways: RealRailways) -> [RealStation] {
        guard let frame = RealWorldFrame(world: world) else { return [] }
        var seen = Set<String>()
        var found: [RealStation] = []
        for station in stations where !station.isDepot {
            let coordinate = frame.coordinate(worldX: Double(station.point.x), worldY: Double(station.point.y))
            let here = RealRailways.Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let real = railways.stations(named: station.name, near: here).first else { continue }
            let key = RealRailways.stationKey(real.chinese)
            guard seen.insert(key).inserted else { continue }
            found.append(RealStation(key: key, chinese: real.chinese, english: real.english, system: real.system.id, station: station.id))
        }
        return found
    }

    /// How many stamps there are to collect: the real places.
    public static func total(in railways: RealRailways) -> Int {
        Set(railways.stations.map { RealRailways.stationKey($0.chinese) }).count
    }
}

/// The stamps collected and when: a small JSON file beside the saves
/// (`station-stamps.data`), not a save, kept as the achievements are
/// (``AchievementRecords``): a file that cannot be read is none collected;
/// a collection reads it again first and adds to what it holds, leaves
/// alone one it still cannot read or one of a newer version, and moves a
/// damaged one aside before writing.
public struct StationStampRecords: Sendable {
    public let file: URL
    /// In the order collected.
    public private(set) var stamps: [StationStamp]

    public static let fileName = "station-stamps.data"

    private struct Stored: Codable {
        var version: Int
        var stamps: [StationStamp]
    }

    private static let version = 1

    public init(file: URL) {
        self.file = file
        let stored = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        stamps = stored.flatMap { $0.version <= Self.version ? $0.stamps : nil } ?? []
    }

    public var count: Int { stamps.count }

    /// When each stamp was collected, by its key (decision 353: the
    /// station panel's line).
    public var dates: [String: Date] {
        Dictionary(stamps.map { ($0.key, $0.earned) }, uniquingKeysWith: min)
    }

    public func contains(_ key: String) -> Bool {
        stamps.contains { $0.key == key }
    }

    /// Stamps `stations` not in the passport yet, writes the file and
    /// returns the new stamps, in `stations`' order.
    public mutating func collect(_ stations: [StationStamps.RealStation], at date: Date = Date()) -> [StationStamp] {
        var new: [StationStamp] = []
        for station in stations where !contains(station.key) && !new.contains(where: { $0.key == station.key }) {
            new.append(StationStamp(key: station.key, chinese: station.chinese, english: station.english, system: station.system, earned: date))
        }
        guard !new.isEmpty else { return [] }
        stamps += new
        save()
        return new
    }

    /// Writes the file, after adding what it holds now (its own stamp,
    /// the earlier, where both have one).
    private mutating func save() {
        let manager = FileManager.default
        if manager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file) else { return }
            if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
                guard stored.version <= Self.version else { return }
                var merged = stamps
                for theirs in stored.stamps {
                    if let index = merged.firstIndex(where: { $0.key == theirs.key }) {
                        if theirs.earned < merged[index].earned { merged[index] = theirs }
                    } else {
                        merged.append(theirs)
                    }
                }
                stamps = merged.enumerated()
                    .sorted { ($0.element.earned, $0.offset) < ($1.element.earned, $1.offset) }
                    .map(\.element)
            } else {
                let damaged = file.appendingPathExtension("damaged")
                try? manager.removeItem(at: damaged)
                guard (try? manager.moveItem(at: file, to: damaged)) != nil else { return }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(Stored(version: Self.version, stamps: stamps)).write(to: file, options: .atomic)
    }
}

/// The passport's pages, after the reference's (`voyager-passport.js`).
public enum StationStampPassport {
    /// The reference's `paginateStamps`: eight stamps a page.
    public static let stampsPerPage = 8

    public static func pages(_ stamps: [StationStamp]) -> [[StationStamp]] {
        stride(from: 0, to: stamps.count, by: stampsPerPage).map { Array(stamps[$0..<min($0 + stampsPerPage, stamps.count)]) }
    }

    /// Where a stamp lies on its page, in percent of the page's width (`x`,
    /// `width`, `halfWidth`) and height (`y`, `halfHeight`), turned by
    /// `angle` degrees; `x` and `y` are its middle. A page is 0.73 as wide
    /// as it is tall (the reference's page), and a stamp is square.
    public struct Placement: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let angle: Double
        /// Half the width and height the turned stamp takes up.
        public let halfWidth: Double
        public let halfHeight: Double
    }

    /// The reference's `stampLayout`: each stamp of a page placed at random
    /// where it overlaps none placed before it, from a generator seeded by
    /// the stamps' IDs (FNV-1a, then a linear congruential generator), so a
    /// page always looks the same. Up to 350 tries a stamp; where one finds
    /// no room the page starts again, and every 30 tries the stamps shrink
    /// by 4%.
    public static func layout(_ ids: [String]) -> [Placement] {
        guard !ids.isEmpty else { return [] }
        var seed: UInt32 = 2_166_136_261
        for scalar in ids.joined(separator: "|").unicodeScalars {
            // JavaScript's `charCodeAt(0)` of each code point: its first
            // UTF-16 unit.
            seed = (seed ^ UInt32(scalar.utf16[0])) &* 16_777_619
        }
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
        var pass = 0
        while true {
            var placed: [Placement] = []
            let shrink = pow(0.96, Double(pass / 30))
            for _ in ids {
                let width = (28 + random() * 5) * shrink
                let angle = random() * 28 - 14
                let radians = abs(angle) * Double.pi / 180
                let halfWidth = width * (cos(radians) + sin(radians)) / 2
                let halfHeight = halfWidth * 0.73
                var found: Placement?
                for _ in 0..<350 {
                    let x = 3 + halfWidth + random() * (94 - 2 * halfWidth)
                    let y = 13 + halfHeight + random() * (75 - 2 * halfHeight)
                    if placed.allSatisfy({ abs(x - $0.x) > halfWidth + $0.halfWidth + 1.5 || abs(y - $0.y) > halfHeight + $0.halfHeight + 1.5 }) {
                        found = Placement(x: x, y: y, width: width, angle: angle, halfWidth: halfWidth, halfHeight: halfHeight)
                        break
                    }
                }
                guard let found else { break }
                placed.append(found)
            }
            if placed.count == ids.count { return placed }
            pass += 1
        }
    }

    /// The date under a stamp, as the reference writes it (`2026.10.22`),
    /// in Taiwan time.
    public static func dateLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The passport's title: how many collected, of how many when the
    /// real railways are read.
    public static func summary(count: Int, total: Int?, in language: DisplayLanguage) -> String {
        let shown = total.map { "\(count)/\($0)" } ?? "\(count)"
        return language.text("Station stamps \(shown)", "車站紀念章 \(shown)")
    }

    /// What the passport says under its pages.
    public static func footer(in language: DisplayLanguage) -> String {
        language.text(
            "A real station your trains carried passengers at gets its stamp the next day. Kept on this device.",
            "列車載客停靠過的真實車站，第二天蓋上它的紀念章。記錄在這台裝置上。"
        )
    }

    /// How the passport lists its stamps (decision 353, the reference's
    /// two tabs, `时间` and `城市`, in `voyager-collection.js`): pages in
    /// the order collected, or a list by county or city.
    public enum Arrangement: String, CaseIterable, Hashable, Sendable {
        case date, county

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .date: language.text("By date", "依時間")
            case .county: language.text("By county", "依縣市")
            }
        }
    }

    /// What an empty passport says.
    public static func empty(in language: DisplayLanguage) -> String {
        language.text(
            "No stamps yet: on a real-world map, run trains that carry passengers to real stations.",
            "還沒有紀念章：在實景地圖上讓列車載客停靠真實車站。"
        )
    }
}

/// Stamps just collected, for the map (decision 353): each lands over the
/// game's station that is it, as a trip's stamp does (decision 276).
public struct StationStampPulse: Hashable, Sendable {
    /// One stamp over its station.
    public struct Mark: Hashable, Sendable, Identifiable {
        public let stamp: StationStamp
        public let station: StationID
        public let location: PlanPoint

        public var id: String { stamp.key }
    }

    /// The most stamps one pulse shows: a first day can collect a whole
    /// line, and the status line and the news name them all.
    public static let maximum = 4
    /// How long a stamp stays, in seconds: decision 253's `pop` in, a
    /// hold long enough to read a station's name, its `cardOut` out; a
    /// second longer than a trip's stamp (decision 276), which has two
    /// words.
    public static let lifetime = 3.0
    public static var hold: Double {
        lifetime - MotionRule.pop.seconds - MotionRule.cardOut.seconds
    }

    public let marks: [Mark]
    /// Counts up with each pulse.
    public let serial: Int
}

/// Whether a station's stamp is in the passport (decision 353), for the
/// station panel.
public enum StationStampStatus: Hashable, Sendable {
    case collected(Date)
    case notYet

    public var isCollected: Bool {
        if case .collected = self { true } else { false }
    }

    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .collected(let date):
            let day = StationStampPassport.dateLabel(date)
            return language.text("Station stamp: collected \(day)", "紀念章：\(day) 已收集")
        case .notYet:
            return language.text(
                "Station stamp: not yet. Carry passengers here and it is stamped the next day.",
                "紀念章：還沒收集。列車在這裡載客，第二天就蓋上。"
            )
        }
    }
}

/// The passport by county or city (decision 353, the reference's
/// `cityGroups` in `voyager-collection.js`): how many of each one's real
/// stations are collected.
public enum StationStampCounties {
    /// Taiwan's counties and cities in the government's order, with their
    /// English names.
    public static let names: [(chinese: String, english: String)] = [
        ("臺北市", "Taipei City"), ("新北市", "New Taipei City"), ("基隆市", "Keelung City"),
        ("桃園市", "Taoyuan City"), ("新竹市", "Hsinchu City"), ("新竹縣", "Hsinchu County"),
        ("苗栗縣", "Miaoli County"), ("臺中市", "Taichung City"), ("彰化縣", "Changhua County"),
        ("南投縣", "Nantou County"), ("雲林縣", "Yunlin County"), ("嘉義市", "Chiayi City"),
        ("嘉義縣", "Chiayi County"), ("臺南市", "Tainan City"), ("高雄市", "Kaohsiung City"),
        ("屏東縣", "Pingtung County"), ("宜蘭縣", "Yilan County"), ("花蓮縣", "Hualien County"),
        ("臺東縣", "Taitung County"), ("澎湖縣", "Penghu County"), ("金門縣", "Kinmen County"),
        ("連江縣", "Lienchiang County"),
    ]

    /// One county or city: its real stations, and the stamps of them
    /// collected, in the order collected.
    public struct Group: Hashable, Sendable, Identifiable {
        /// Its Chinese name; empty for the stamps no county holds.
        public let county: String
        public let total: Int
        public let collected: [StationStamp]

        public var id: String { county }

        public func name(in language: DisplayLanguage) -> String {
            guard !county.isEmpty else { return language.text("Elsewhere", "其他") }
            let english = StationStampCounties.names.first { $0.chinese == county }?.english ?? county
            return language.text(english, county)
        }

        /// "臺北市 5/40".
        public func title(in language: DisplayLanguage) -> String {
            total > 0 ? "\(name(in: language)) \(collected.count)/\(total)" : "\(name(in: language)) \(collected.count)"
        }
    }

    /// The county or city of each real place (``RealRailways/stationKey(_:)``),
    /// where its first station in the site's order lies.
    public static func counties(of railways: RealRailways, in places: PlaceNames) -> [String: String] {
        var found: [String: String] = [:]
        var seen = Set<String>()
        for station in railways.stations {
            let key = RealRailways.stationKey(station.chinese)
            guard seen.insert(key).inserted else { continue }
            if let county = places.county(containing: station.coordinate) { found[key] = county }
        }
        return found
    }

    /// The groups of `stamps`: every county or city with a real station,
    /// in the government's order, then the stamps of a place no county
    /// holds (a station the railways no longer list), if any.
    public static func groups(of stamps: [StationStamp], counties: [String: String]) -> [Group] {
        var totals: [String: Int] = [:]
        for county in counties.values { totals[county, default: 0] += 1 }
        var collected: [String: [StationStamp]] = [:]
        for stamp in stamps { collected[counties[stamp.key] ?? "", default: []].append(stamp) }
        let known = names.map(\.chinese)
        let others = totals.keys.filter { !known.contains($0) }.sorted()
        var groups = (known + others).compactMap { county in
            totals[county].map { Group(county: county, total: $0, collected: collected[county] ?? []) }
        }
        if let elsewhere = collected[""] { groups.append(Group(county: "", total: 0, collected: elsewhere)) }
        return groups
    }
}

extension GameSession {
    /// Says that `stamps` were collected (decision 348): an item each in
    /// the news log, and the status line; and (decision 353) lands up to
    /// ``StationStampPulse/maximum`` of them over the game's stations
    /// `found` says they are.
    public func noteStationStamps(_ stamps: [StationStamp], at found: [StationStamps.RealStation] = []) {
        guard let first = stamps.first else { return }
        for stamp in stamps {
            collectedStamps[stamp.key] = min(collectedStamps[stamp.key] ?? stamp.earned, stamp.earned)
            news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
                language.text("Station stamp collected: \(stamp.name(in: language))", "收集到紀念章：\(stamp.name(in: language))")
            }
        }
        let marks: [StationStampPulse.Mark] = stamps.compactMap { stamp in
            guard let id = found.first(where: { $0.key == stamp.key })?.station, let station = world.station(id: id) else { return nil }
            return StationStampPulse.Mark(stamp: stamp, station: id, location: station.point)
        }
        if !marks.isEmpty {
            stationStampPulse = StationStampPulse(
                marks: Array(marks.prefix(StationStampPulse.maximum)), serial: (stationStampPulse?.serial ?? 0) + 1
            )
        }
        let more = stamps.count - 1
        isMessageKeptOutOfNews = true
        message = StatusMessage(kind: .success, text: more > 0
            ? language.text(
                "Station stamps collected: \(first.name(in: language)) and \(more) more",
                "收集到紀念章：\(first.name(in: language))等 \(stamps.count) 站"
            )
            : language.text("Station stamp collected: \(first.name(in: language))", "收集到紀念章：\(first.name(in: language))"))
        isMessageKeptOutOfNews = false
    }

    /// Whether the stamp of station `id` is in the passport (decision
    /// 353), or `nil` where the station is not a real one (or the real
    /// railways are not read yet).
    public func stationStampStatus(of id: StationID) -> StationStampStatus? {
        guard let railways, let station = world.station(id: id),
              let real = StationStamps.realStations(of: [station], in: world, railways: railways).first else { return nil }
        return collectedStamps[real.key].map(StationStampStatus.collected) ?? .notYet
    }
}
