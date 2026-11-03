import Foundation
import GameCore

// What near a new station on a real-world map it can be named after,
// besides the places of decision 159 (decision 569): the universities, senior
// high schools, hospitals, large parks, night markets and shopping
// districts, malls and department stores round it, the road it is on and
// the crossing of two roads, which Taiwan's metro and light rail name as
// 南京復興 (南京東路 × 復興北路) and 凱旋中華 (凱旋四路 × 中華五路).
//
// `tools/station-landmarks/build_station_landmarks.py` reads them once from
// the same OpenStreetMap extract as the place names (ODbL 1.0); the app
// bundles them as `Resources/RealWorld/taiwan_station_landmarks.json`, and
// ``PlaceNames/landmarks`` carries them. Only the presentation reads them:
// a name is only a suggestion the player can change.

/// Landmarks, roads and crossings of Taiwan, from OpenStreetMap.
public struct StationLandmarks: Sendable {
    /// What a landmark is.
    public enum Kind: Int, Sendable, CaseIterable {
        case university, school, hospital, park, market, mall
    }

    /// A named place a station can be named after.
    public struct Landmark: Sendable {
        public let name: PlaceNames.Name
        public let kind: Kind
        public let coordinate: RealRailways.Coordinate
        /// Its area in m² (0 for a night market drawn as a point).
        public let area: Double
    }

    /// One found thing and how far it is.
    public struct Found<Thing: Sendable>: Sendable {
        public let thing: Thing
        public let metres: Double
    }

    struct Line: Sendable {
        let road: Int
        let points: [RealRailways.Coordinate]
        let south, north, west, east: Double
    }

    struct Crossing: Sendable {
        let coordinate: RealRailways.Coordinate
        let first: Int
        let second: Int
    }

    /// By latitude, so a search looks only at a band.
    let landmarks: [Landmark]
    /// The roads' names, without their section (南京東路, "Nanjing East
    /// Road"), longest road first.
    let roads: [PlaceNames.Name]
    let lines: [Line]
    /// By latitude.
    let crossings: [Crossing]

    /// Reads the app's landmarks file (`build_station_landmarks.py`).
    /// Throws for a file out of shape.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.scale > 0 else { throw Self.corrupt("Landmarks need a positive scale.") }
        let scale = Double(file.scale)
        func coordinate(_ latitude: Int, _ longitude: Int) -> RealRailways.Coordinate {
            RealRailways.Coordinate(latitude: Double(latitude) / scale, longitude: Double(longitude) / scale)
        }
        roads = file.roads.map { PlaceNames.Name(chinese: $0.chinese, english: $0.english) }
        landmarks = try file.landmarks.map { row in
            guard let kind = Kind(rawValue: row.kind) else { throw Self.corrupt("Unknown landmark kind \(row.kind).") }
            return Landmark(
                name: PlaceNames.Name(chinese: row.chinese, english: row.english), kind: kind,
                coordinate: coordinate(row.latitude, row.longitude), area: Double(row.hundredsOfSquareMetres) * 100
            )
        }
        .sorted { $0.coordinate.latitude < $1.coordinate.latitude }
        let roadCount = roads.count
        lines = try file.ways.map { row in
            guard row.count >= 5, row.count.isMultiple(of: 2) == false, (0..<roadCount).contains(row[0]) else {
                throw Self.corrupt("A road line is its road and at least two points.")
            }
            var latitude = 0, longitude = 0
            let points = stride(from: 1, to: row.count, by: 2).map { i in
                latitude += row[i]
                longitude += row[i + 1]
                return coordinate(latitude, longitude)
            }
            return Line(
                road: row[0], points: points,
                south: points.map(\.latitude).min() ?? 0, north: points.map(\.latitude).max() ?? 0,
                west: points.map(\.longitude).min() ?? 0, east: points.map(\.longitude).max() ?? 0
            )
        }
        crossings = try file.crossings.map { row in
            guard row.count == 4, (0..<roadCount).contains(row[2]), (0..<roadCount).contains(row[3]) else {
                throw Self.corrupt("A crossing is a point and two roads.")
            }
            return Crossing(coordinate: coordinate(row[0], row[1]), first: row[2], second: row[3])
        }
        .sorted { $0.coordinate.latitude < $1.coordinate.latitude }
    }

    private static func corrupt(_ text: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: text))
    }

    /// The landmarks within `metres` of `coordinate`, nearest first.
    public func landmarks(near coordinate: RealRailways.Coordinate, within metres: Double) -> [Found<Landmark>] {
        Self.band(of: landmarks, \.coordinate, round: coordinate, within: metres)
            .map { Found(thing: $0, metres: RealStationTransfers.distanceMetres(coordinate, $0.coordinate)) }
            .filter { $0.metres <= metres }
            .sorted { $0.metres != $1.metres ? $0.metres < $1.metres : $0.thing.name.chinese < $1.thing.name.chinese }
    }

    /// The road nearest `coordinate`, if one is within `metres`.
    public func road(near coordinate: RealRailways.Coordinate, within metres: Double) -> Found<PlaceNames.Name>? {
        let latitudeReach = metres / 110_500
        let longitudeReach = metres / (111_320 * cos(coordinate.latitude * .pi / 180))
        var best: (road: Int, metres: Double)?
        for line in lines {
            guard line.south - latitudeReach <= coordinate.latitude, coordinate.latitude <= line.north + latitudeReach,
                  line.west - longitudeReach <= coordinate.longitude, coordinate.longitude <= line.east + longitudeReach
            else { continue }
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let d = Self.metres(from: coordinate, toSegment: a, b)
                if d <= metres, best.map({ d < $0.metres }) ?? true { best = (line.road, d) }
            }
        }
        return best.map { Found(thing: roads[$0.road], metres: $0.metres) }
    }

    /// The crossings within `metres` of `coordinate` that make a name
    /// (``crossingName(_:_:)``), nearest first, each name once.
    public func crossings(near coordinate: RealRailways.Coordinate, within metres: Double) -> [Found<PlaceNames.Name>] {
        var seen = Set<String>()
        return Self.band(of: crossings, \.coordinate, round: coordinate, within: metres)
            .map { (crossing: $0, metres: RealStationTransfers.distanceMetres(coordinate, $0.coordinate)) }
            .filter { $0.metres <= metres }
            .sorted { $0.metres < $1.metres }
            .compactMap { found -> Found<PlaceNames.Name>? in
                let first = roads[found.crossing.first], second = roads[found.crossing.second]
                guard let chinese = Self.crossingName(first.chinese, second.chinese), seen.insert(chinese).inserted else { return nil }
                let english = first.english.flatMap { a in second.english.flatMap { b in Self.crossingName(english: a, b) } }
                return Found(thing: PlaceNames.Name(chinese: chinese, english: english), metres: found.metres)
            }
    }

    // MARK: - Names

    private static let numerals: Set<Character> = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    private static let sides: Set<Character> = ["東", "西", "南", "北"]

    /// A road's name as a crossing uses it: without its section (段), its
    /// kind (路, 街, 大道), its number (凱旋四路) and its side (南京東路):
    /// 南京東路三段 → 南京, 凱旋四路 → 凱旋. `nil` where less than two
    /// characters are left (中一路, 北路) or it is no road.
    public static func roadStem(_ road: String) -> String? {
        var name = Substring(road)
        if name.hasSuffix("段") {
            var cut = name.dropLast()
            while let last = cut.last, numerals.contains(last) { cut = cut.dropLast() }
            if cut.count < name.count - 1 { name = cut }
        }
        guard let kind = ["大道", "路", "街"].first(where: { name.hasSuffix($0) }) else { return nil }
        name = name.dropLast(kind.count)
        while let last = name.last, numerals.contains(last), name.count > 2 { name = name.dropLast() }
        if let last = name.last, sides.contains(last), name.count > 2 { name = name.dropLast() }
        return name.count >= 2 ? String(name) : nil
    }

    /// The name Taiwan's metro and light rail give the crossing of two
    /// roads: their stems (``roadStem(_:)``) one after the other, the
    /// longer road first (南京東路 × 復興北路 → 南京復興; 凱旋四路 ×
    /// 中華五路 → 凱旋中華). `nil` where a stem is missing or the two are
    /// the same road (南京東路 × 南京西路).
    public static func crossingName(_ first: String, _ second: String) -> String? {
        guard let a = roadStem(first), let b = roadStem(second), a != b,
              !a.hasPrefix(b), !b.hasPrefix(a) else { return nil }
        return a + b
    }

    private static let englishKinds: Set<String> = [
        "road", "rd", "street", "st", "boulevard", "blvd", "avenue", "ave", "section", "sec",
    ]
    private static let englishSides: Set<String> = ["east", "west", "south", "north", "e", "w", "s", "n"]

    /// A road's English name as a crossing uses it ("Nanjing East Road"
    /// → "Nanjing", "Kaixuan 4th Road" → "Kaixuan"), or `nil`.
    public static func roadStem(english road: String) -> String? {
        let words = road.split(whereSeparator: { $0 == " " || $0 == "," }).filter { word in
            let plain = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if plain.isEmpty || englishKinds.contains(plain) || englishSides.contains(plain) { return false }
            if plain.first?.isNumber == true { return false }
            return true
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// The English name of a crossing ("Nanjing Fuxing"), or `nil`.
    public static func crossingName(english first: String, _ second: String) -> String? {
        guard let a = roadStem(english: first), let b = roadStem(english: second),
              a.lowercased() != b.lowercased() else { return nil }
        return "\(a) \(b)"
    }

    // MARK: - Searching

    /// The things of `sorted` (by latitude) whose latitude is within
    /// `metres` of `coordinate`'s.
    private static func band<Thing>(
        of sorted: [Thing], _ at: (Thing) -> RealRailways.Coordinate, round coordinate: RealRailways.Coordinate, within metres: Double
    ) -> ArraySlice<Thing> {
        // A degree of latitude is at least 110.5 km.
        let reach = metres / 110_500
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if at(sorted[middle]).latitude < coordinate.latitude - reach { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < sorted.count, at(sorted[end]).latitude <= coordinate.latitude + reach { end += 1 }
        return sorted[low..<end]
    }

    /// How far `point` is from the segment `a`–`b`, on a plane round
    /// `point` (the segments are short).
    static func metres(from point: RealRailways.Coordinate, toSegment a: RealRailways.Coordinate, _ b: RealRailways.Coordinate) -> Double {
        let ky = 110_540.0, kx = 111_320 * cos(point.latitude * .pi / 180)
        let ax = (a.longitude - point.longitude) * kx, ay = (a.latitude - point.latitude) * ky
        let bx = (b.longitude - point.longitude) * kx, by = (b.latitude - point.latitude) * ky
        let dx = bx - ax, dy = by - ay
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(1, max(0, -(ax * dx + ay * dy) / length))
        let x = ax + t * dx, y = ay + t * dy
        return (x * x + y * y).squareRoot()
    }

    // MARK: - File

    private struct File: Decodable {
        struct LandmarkRow: Decodable {
            let latitude, longitude, kind, hundredsOfSquareMetres: Int
            let chinese: String
            let english: String?

            init(from decoder: Decoder) throws {
                var row = try decoder.unkeyedContainer()
                latitude = try row.decode(Int.self)
                longitude = try row.decode(Int.self)
                kind = try row.decode(Int.self)
                hundredsOfSquareMetres = try row.decode(Int.self)
                chinese = try row.decode(String.self)
                english = row.isAtEnd ? nil : try row.decode(String.self)
            }
        }

        struct RoadRow: Decodable {
            let chinese: String
            let english: String?

            init(from decoder: Decoder) throws {
                var row = try decoder.unkeyedContainer()
                chinese = try row.decode(String.self)
                english = row.isAtEnd ? nil : try row.decode(String.self)
            }
        }

        let scale: Int
        let landmarks: [LandmarkRow]
        let roads: [RoadRow]
        let ways: [[Int]]
        let crossings: [[Int]]
    }
}
