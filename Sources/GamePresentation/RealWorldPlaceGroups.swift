import Foundation
import GameCore

// Decision 262: the real-world map's list of places by country where a
// country has many, and by region for the rest, the largest city first;
// and the places whose names match what the player types.

/// One group of the real-world map's list: a country with at least
/// ``RealWorldPlace/countryGroupMinimum`` places, or the rest of a region.
public struct RealWorldPlaceGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// An ISO 3166-1 alpha-2 code.
        case country(String)
        /// The region's places whose country has no group of its own.
        case region(RealWorldPlace.Region)
    }

    public let kind: Kind
    public let places: [RealWorldPlace]
    /// Whether some country of a region's group has a group of its own,
    /// so the group holds the region's other places.
    let isRest: Bool

    public var id: String {
        switch kind {
        case .country(let code): "country-\(code)"
        case .region(let region): "region-\(region)"
        }
    }

    /// The group's name: a country's, or a region's ("Other Asia" when
    /// some of Asia's countries have groups of their own).
    public func name(in language: DisplayLanguage) -> String {
        switch kind {
        case .country(let code):
            if let name = Self.countryNames[code] { return language.text(name.english, name.chinese) }
            return code
        case .region(let region):
            guard isRest else { return region.name(in: language) }
            switch region {
            case .asia: return language.text("Other Asia", "其他亞洲")
            case .europe: return language.text("Other Europe", "其他歐洲")
            case .americas: return language.text("Other Americas", "其他美洲")
            case .oceaniaAndAfrica: return language.text("Other Oceania and Africa", "其他大洋洲與非洲")
            }
        }
    }

    /// The names of the countries that have a group.
    static let countryNames: [String: (english: String, chinese: String)] = [
        "TW": ("Taiwan", "台灣"),
        "JP": ("Japan", "日本"),
        "KR": ("South Korea", "韓國"),
        "CN": ("China", "中國"),
        "US": ("United States", "美國"),
        "IN": ("India", "印度"),
        "PK": ("Pakistan", "巴基斯坦"),
        "BR": ("Brazil", "巴西"),
    ]
}

extension RealWorldPlace {
    /// How many places a country needs for a group of its own.
    public static let countryGroupMinimum = 4

    /// The countries whose groups come first, in this order; any other
    /// country with a group follows them, the one with the most places
    /// first.
    static let leadingCountries = ["TW", "JP", "KR", "CN", "US"]

    /// The list's groups. Taiwan's places keep their order, north to south
    /// and round the east; every other group's run from the largest city
    /// (``population``) to the smallest, and places of one city in the
    /// order of ``all``.
    public static let groups: [RealWorldPlaceGroup] = {
        var counts: [String: Int] = [:]
        for place in all { counts[place.country, default: 0] += 1 }
        let own = Set(counts.filter { $0.value >= countryGroupMinimum }.keys)
        let others = own.subtracting(leadingCountries).sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
        let order = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })
        func largestFirst(_ places: [RealWorldPlace]) -> [RealWorldPlace] {
            places.sorted { ($0.population, order[$1.id]!) > ($1.population, order[$0.id]!) }
        }
        var groups: [RealWorldPlaceGroup] = []
        for country in leadingCountries.filter(own.contains) + others {
            let places = all.filter { $0.country == country }
            groups.append(RealWorldPlaceGroup(kind: .country(country), places: country == "TW" ? places : largestFirst(places), isRest: false))
        }
        for region in Region.allCases {
            let places = all.filter { $0.region == region && !own.contains($0.country) }
            guard !places.isEmpty else { continue }
            let isRest = all.contains { $0.region == region && own.contains($0.country) }
            groups.append(RealWorldPlaceGroup(kind: .region(region), places: largestFirst(places), isRest: isRest))
        }
        return groups
    }()

    /// The places whose English or Chinese name holds `query`, ignoring
    /// case, accents, spaces and 臺/台; those whose name starts with it
    /// first, each part in the list's order. Empty for an empty query.
    public static func matching(_ query: String) -> [RealWorldPlace] {
        let query = searchKey(query)
        guard !query.isEmpty else { return [] }
        var first: [RealWorldPlace] = [], then: [RealWorldPlace] = []
        for place in groups.flatMap(\.places) {
            let names = [place.english, place.chinese].map(searchKey)
            if names.contains(where: { $0.hasPrefix(query) }) {
                first.append(place)
            } else if names.contains(where: { $0.contains(query) }) {
                then.append(place)
            }
        }
        return first + then
    }

    static func searchKey(_ text: String) -> String {
        RealRailways.normalized(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
