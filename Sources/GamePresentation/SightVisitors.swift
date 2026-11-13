import Foundation
import GameCore

// Decision 724: how many visitors Taiwan's sights had in a year by the
// Tourism Administration's count (data.gov.tw dataset 8116, Open Government
// Data License 1.0), shown on a sight's card in the sights panel. Only
// shown: the rules (stars, tourists) do not read it. The app bundles it as
// `Resources/RealWorld/taiwan_sight_visitors.json`, written by
// `tools/tourism-spots/build_official_visitors.py` from the CSV and the
// hand-checked table `tools/tourism-spots/official_names.json`.

public struct SightVisitors: Sendable, Equatable {
    /// One sight's year, by the official count.
    public struct Count: Sendable, Equatable {
        /// The year's visitors.
        public let visitors: Int64
        /// January to December.
        public let months: [Int64]
    }

    /// The year counted.
    public let year: Int
    /// By ``AttractionCatalog/Spot/id``.
    public let sights: [String: Count]

    private struct File: Decodable {
        struct Sight: Decodable {
            let id: String
            let visitors: Int64
            let months: [Int64]
        }

        let year: Int
        let sights: [Sight]
    }

    enum ReadError: Error, Equatable {
        case notTwelveMonths(String)
        case monthsDoNotAddUp(String)
        case notASight(String)
        case twice(String)
    }

    /// Reads the bundled file, throwing when a sight is not one of the
    /// catalog's, is there twice, or its twelve months do not add up to its
    /// year.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        let known = Set(AttractionCatalog.spots.map(\.id))
        var sights: [String: Count] = [:]
        for sight in file.sights {
            guard known.contains(sight.id) else { throw ReadError.notASight(sight.id) }
            guard sight.months.count == 12 else { throw ReadError.notTwelveMonths(sight.id) }
            guard sight.months.reduce(0, +) == sight.visitors else { throw ReadError.monthsDoNotAddUp(sight.id) }
            guard sights[sight.id] == nil else { throw ReadError.twice(sight.id) }
            sights[sight.id] = Count(visitors: sight.visitors, months: sight.months)
        }
        year = file.year
        self.sights = sights
    }

    init(year: Int, sights: [String: Count]) {
        self.year = year
        self.sights = sights
    }

    /// The catalog's spots by their names, to find a world's sight among
    /// them: a sight keeps the catalog's names and kind but not its id.
    private static let spotsByName: [String: AttractionCatalog.Spot] = Dictionary(
        AttractionCatalog.spots.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// `sight`'s year, when it is one of the catalog's sights (same names
    /// and kind) with an official count; `nil` for any other (a lesson's,
    /// the company's museum).
    public func count(of sight: Attraction) -> Count? {
        guard let spot = Self.spotsByName[sight.name], spot.englishName == sight.englishName, spot.kind == sight.kind else { return nil }
        return sights[spot.id]
    }

    /// The line on `sight`'s card: "About 2.9 million visitors a year (2024,
    /// Tourism Administration)", or `nil` without an official count.
    public func text(of sight: Attraction, in language: DisplayLanguage) -> String? {
        count(of: sight).map { Self.text(visitors: $0.visitors, year: year, in: language) }
    }

    /// "About 2.9 million visitors a year (2024, Tourism Administration)" /
    /// 「一年約 287 萬人次（2024，交通部觀光署）」.
    static func text(visitors: Int64, year: Int, in language: DisplayLanguage) -> String {
        let amount = chineseAmount(visitors)
        // "287 萬人次", but "9,600 人次".
        let chinese = amount.hasSuffix("萬") ? "\(amount)人次" : "\(amount) 人次"
        return language.text(
            "About \(englishAmount(visitors)) visitors a year (\(year), Tourism Administration)",
            "一年約 \(chinese)（\(year)，交通部觀光署）"
        )
    }

    /// 2,870,420 → "2.9 million"; 54,499 → "54,000"; 960 → "960".
    static func englishAmount(_ visitors: Int64) -> String {
        if visitors >= 1_000_000 {
            let tenths = (visitors + 50_000) / 100_000
            return tenths % 10 == 0 ? "\(tenths / 10) million" : "\(tenths / 10).\(tenths % 10) million"
        }
        if visitors >= 10_000 {
            let thousands = (visitors + 500) / 1_000
            return thousands >= 1_000 ? "1 million" : "\(thousands),000"
        }
        return visitors.groupedText
    }

    /// 2,870,420 → "287 萬"; 54,499 → "5.4 萬"; 9,600 → "9,600".
    static func chineseAmount(_ visitors: Int64) -> String {
        if visitors >= 100_000 {
            return "\((visitors + 5_000) / 10_000) 萬"
        }
        if visitors >= 10_000 {
            let tenths = (visitors + 500) / 1_000
            return tenths % 10 == 0 ? "\(tenths / 10) 萬" : "\(tenths / 10).\(tenths % 10) 萬"
        }
        return visitors.groupedText
    }
}
