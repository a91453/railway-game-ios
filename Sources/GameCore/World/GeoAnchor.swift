/// Where a real-world game's map lies on the Earth (Stage E2, ARCHITECTURE
/// decision 50): the latitude and longitude of the middle of the map, in
/// ten-millionths of a degree.
///
/// A record for the map's background, nothing more: no rule reads it, and
/// the world stays in world coordinates (1/64 m, x east, y south). How they
/// lie over the Earth, and the map drawn under them, are the presentation's.
/// A world without one is a blank map.
///
/// Whole numbers, as everything GameCore keeps: a save reads back to the
/// same anchor on every platform. A ten-millionth of a degree is about a
/// centimetre.
public struct GeoAnchor: Hashable, Sendable {
    /// North of the equator, in ten-millionths of a degree:
    /// within ±``maximumLatitude``.
    public let latitude: Int64
    /// East of Greenwich, in ten-millionths of a degree: from
    /// −``longitudeLimit`` up to, but not including, ``longitudeLimit``
    /// (180° east is 180° west).
    public let longitude: Int64

    /// 90°: a pole.
    public static let maximumLatitude: Int64 = 900_000_000
    /// 180°.
    public static let longitudeLimit: Int64 = 1_800_000_000

    /// The anchor at `latitude` and `longitude`, or `nil` when either is
    /// out of range.
    public init?(latitude: Int64, longitude: Int64) {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    private static func isValid(latitude: Int64, longitude: Int64) -> Bool {
        (-maximumLatitude...maximumLatitude).contains(latitude)
            && (-longitudeLimit..<longitudeLimit).contains(longitude)
    }
}

extension GeoAnchor: Codable {
    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    /// Decodes an anchor, rejecting a latitude or longitude out of range.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Int64.self, forKey: .latitude)
        let longitude = try container.decode(Int64.self, forKey: .longitude)
        guard let anchor = GeoAnchor(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude, in: container,
                debugDescription: "A latitude is within ±90° and a longitude from −180° up to 180°, in ten-millionths of a degree."
            )
        }
        self = anchor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

extension GameWorld {
    /// Lays the map over the Earth with its middle at `anchor`, or makes it
    /// a blank map again with `nil` (Stage E2). Changes nothing else: the
    /// railway, the stations and the trains stay where they are in the
    /// world. Free.
    public mutating func setGeoAnchor(_ anchor: GeoAnchor?) {
        geoAnchor = anchor
    }
}
