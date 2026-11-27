import Foundation

// Decision 1031: the houses Taiwan's real-price registry (實價登錄) has sold
// where the bundled buildings (Overture's, decision 389) have none: a door
// number of a house sold from 2021 on with no building drawn within some
// 10 m of it (25 m for a block of flats), its storeys (總樓層數) and its
// kind (透天厝, 公寓, 華廈, 住宅大樓). `Resources/RealWorld/taiwan_registry_houses.dat`
// by `tools/real-land-price/build_registry_houses.py`. The 3D map's houses
// along the roads (decision 385), which stand only where no real building
// does, take a sold house's storeys and kind near one, in place of their
// hash's: so a gap in Overture's buildings is filled with the town that
// stands there, not a made-up one, and a building a later Overture draws
// keeps the house off as it keeps any.

/// The houses the real-price registry knows where the bundled buildings
/// have none (decision 1031).
public struct RegistryHouses: Sendable {
    /// What a house is.
    public enum Kind: UInt8, CaseIterable, Sendable {
        /// 透天厝, a shop house or a farmhouse.
        case terrace
        /// 公寓: a walk-up of up to five floors.
        case walkUp
        /// 華廈: flats with a lift, up to ten floors.
        case midRise
        /// 住宅大樓: a tower of flats or offices.
        case tower

        /// Whether it is a block of flats, as the game draws them.
        public var isFlats: Bool { self != .terrace }
    }

    public struct House: Equatable, Sendable {
        /// Degrees.
        public let latitude: Double
        public let longitude: Double
        public let storeys: Int
        public let kind: Kind
    }

    /// By latitude then longitude.
    public let houses: [House]

    public init(houses: [House]) {
        self.houses = houses.sorted { ($0.latitude, $0.longitude) < ($1.latitude, $1.longitude) }
    }

    /// Reads the app's file: `TWRH`, version 1, a count, then each house's
    /// longitude and latitude in millionths of a degree (Int32 each), its
    /// storeys and kind (a byte each), little-endian. Throws for a file
    /// out of shape.
    public init(data: Data) throws {
        let bytes = [UInt8](data)
        func word(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        guard bytes.count >= 12, bytes[0..<4].elementsEqual("TWRH".utf8), word(4) == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a registry houses file."))
        }
        let count = Int(word(8))
        guard bytes.count == 12 + count * 10 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The file holds \(count) houses."))
        }
        var houses: [House] = []
        houses.reserveCapacity(count)
        for index in 0..<count {
            let at = 12 + index * 10
            guard let kind = Kind(rawValue: bytes[at + 9]), bytes[at + 8] > 0 else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A house has storeys and a kind."))
            }
            let longitude = Double(Int32(bitPattern: word(at))) / 1e6, latitude = Double(Int32(bitPattern: word(at + 4))) / 1e6
            houses.append(House(latitude: latitude, longitude: longitude, storeys: Int(bytes[at + 8]), kind: kind))
        }
        // The tool writes them by latitude; a file that is not is sorted.
        let ordered = zip(houses, houses.dropFirst()).allSatisfy { ($0.latitude, $0.longitude) <= ($1.latitude, $1.longitude) }
        self.houses = ordered ? houses : houses.sorted { ($0.latitude, $0.longitude) < ($1.latitude, $1.longitude) }
    }

    /// The houses from `south` to `north` and `west` to `east`, degrees.
    public func houses(south: Double, north: Double, west: Double, east: Double) -> ArraySlice<House> {
        let first = houses.partitioningIndex { $0.latitude >= south }
        let last = houses[first...].partitioningIndex { $0.latitude > north }
        return houses[first..<last].filter { $0.longitude >= west && $0.longitude <= east }[...]
    }
}

extension RandomAccessCollection {
    /// The first index whose element `belongs`, all before it not, by
    /// halving (the elements ordered so).
    fileprivate func partitioningIndex(where belongs: (Element) -> Bool) -> Index {
        var low = startIndex, count = self.count
        while count > 0 {
            let half = count / 2, middle = index(low, offsetBy: half)
            if belongs(self[middle]) {
                count = half
            } else {
                low = index(after: middle)
                count -= half + 1
            }
        }
        return low
    }
}
