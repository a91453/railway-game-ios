import Foundation

// Decision 331: Taiwan's temples, where the 3D map puts its temple models
// on a real-world map. From the owner's geo-scene reference
// (`Railway/geo-scene-reference-clean/source/public/religion/temples.pmtiles`:
// the Ministry of the Interior's temple registry, OpenStreetMap's places of
// worship under the ODbL and the Bureau of Cultural Heritage's monuments),
// read once by `tools/temples/build_temples.py` into the app's
// `Resources/BaseMap/taiwan_temples.json`. Only a place and a size each.

/// The temples of Taiwan, Penghu, Kinmen and Matsu.
public struct RealTemples: Sendable {
    /// How big a temple is drawn.
    public enum Size: Int, Comparable, Sendable {
        /// A Tudigong shrine.
        case small = 0
        case temple = 1
        /// One of the hundred religious events' temples, or a listed
        /// monument.
        case large = 2

        public static func < (a: Size, b: Size) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Temple: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let size: Size
    }

    public let temples: [Temple]

    public init(temples: [Temple]) {
        self.temples = temples
    }

    private struct File: Decodable {
        /// Each temple's latitude and longitude in 1e-5 degrees, then its
        /// size.
        let temples: [Int]
    }

    /// Reads the app's temples file (`build_temples.py`). Throws for a
    /// file out of shape.
    public init(data: Data) throws {
        let numbers = try JSONDecoder().decode(File.self, from: data).temples
        guard numbers.count.isMultiple(of: 3) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A temple is three numbers."))
        }
        temples = try stride(from: 0, to: numbers.count, by: 3).map { i in
            guard let size = Size(rawValue: numbers[i + 2]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A temple's size is 0, 1 or 2."))
            }
            return Temple(latitude: Double(numbers[i]) / 1e5, longitude: Double(numbers[i + 1]) / 1e5, size: size)
        }
    }
}
