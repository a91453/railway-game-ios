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

        public init(key: String, chinese: String, english: String?, system: String) {
            self.key = key
            self.chinese = chinese
            self.english = english
            self.system = system
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
            found.append(RealStation(key: key, chinese: real.chinese, english: real.english, system: real.system.id))
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

    /// What an empty passport says.
    public static func empty(in language: DisplayLanguage) -> String {
        language.text(
            "No stamps yet: on a real-world map, run trains that carry passengers to real stations.",
            "還沒有紀念章：在實景地圖上讓列車載客停靠真實車站。"
        )
    }
}

extension GameSession {
    /// Says that `stamps` were collected (decision 348): an item each in
    /// the news log, and the status line.
    public func noteStationStamps(_ stamps: [StationStamp]) {
        guard let first = stamps.first else { return }
        for stamp in stamps {
            news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
                language.text("Station stamp collected: \(stamp.name(in: language))", "收集到紀念章：\(stamp.name(in: language))")
            }
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
}
