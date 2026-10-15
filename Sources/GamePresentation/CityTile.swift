import Foundation

// Decision 239: the 3D city preview's tiles round Kaohsiung and Taichung
// Stations (`Web/CityView`, decisions 152 and 163: Overture Maps'
// buildings with their storeys and use), read for the native 3D map. A
// port of the reader in `Web/CityView/src/shared/tileformat.js`
// (`decodeTile`, format 7), keeping only the buildings: the rest of a tile
// (road surfaces, street furniture, wires, signs) is read past.

/// One area of the city tiles: a square round a station, in metres east
/// (x) and south (z) of its origin, the tiles' own local projection
/// (`Web/CityView/src/shared/geo.js`, `makeProjection`).
public struct CityTileArea: Sendable {
    public struct Building: Sendable, Equatable {
        /// PLATEAU's usage code, as `tools/pipeline/taiwan.mjs` maps
        /// Overture's: 401/404 commercial, 413/414 homes, 421 civic, 422
        /// schools and hospitals, 431 transport, 441 industry, 454 temples.
        public var usage: Int
        public var storeys: Int
        /// The ground and the roof, in metres above sea level.
        public var base: Float
        public var height: Float
        /// The polygons, each its outline then its holes, open rings of
        /// (x, z) metres; outlines counter-clockwise seen from above.
        public var polygons: [[[CityTileArea.Point]]]
    }

    public struct Point: Sendable, Equatable {
        public var x: Float
        public var z: Float
    }

    public enum ReadError: Error {
        case notATile
        case version(Int)
        case truncated
        case manifest
    }

    /// The area's key (`kaohsiung`, `taichung`).
    public let id: String
    public let longitude: Double
    public let latitude: Double
    /// The square the tiles cover, in metres from the origin.
    public let minX: Float, maxX: Float, minZ: Float, maxZ: Float
    public let buildings: [Building]

    /// The format `tileformat.js` writes (`VERSION`).
    static let version = 7

    /// The area whose `manifest.json` is `manifest`, each of its tiles
    /// read by `tile` from the file name the manifest gives. A tile that
    /// is missing or does not read is left out.
    public init(manifest: Data, tile: (String) -> Data?) throws {
        struct Manifest: Decodable {
            struct Origin: Decodable { let lon: Double; let lat: Double }
            struct Bounds: Decodable { let minX: Float; let maxX: Float; let minZ: Float; let maxZ: Float }
            struct Tile: Decodable { let file: String; let buildings: Int }
            let format: Int
            let area: String
            let origin: Origin
            let bounds: Bounds
            let tiles: [Tile]
        }
        guard let read = try? JSONDecoder().decode(Manifest.self, from: manifest) else { throw ReadError.manifest }
        guard read.format == Self.version else { throw ReadError.version(read.format) }
        id = read.area
        longitude = read.origin.lon
        latitude = read.origin.lat
        (minX, maxX, minZ, maxZ) = (read.bounds.minX, read.bounds.maxX, read.bounds.minZ, read.bounds.maxZ)
        var buildings: [Building] = []
        for entry in read.tiles where entry.buildings > 0 {
            guard let bytes = tile(entry.file), let read = try? Self.buildings(in: [UInt8](bytes)) else { continue }
            buildings += read
        }
        self.buildings = buildings
    }

    /// Every area in `folder` (the app's `BaseMap/city`): those its
    /// `areas.json` lists, each in the folder of its key. An area that
    /// does not read is left out.
    public static func areas(in folder: URL) -> [CityTileArea] {
        struct Listed: Decodable { let id: String }
        guard let list = try? Data(contentsOf: folder.appendingPathComponent("areas.json")),
              let listed = try? JSONDecoder().decode([Listed].self, from: list) else { return [] }
        return listed.compactMap { entry in
            let area = folder.appendingPathComponent(entry.id, isDirectory: true)
            guard let manifest = try? Data(contentsOf: area.appendingPathComponent("manifest.json")) else { return nil }
            return try? CityTileArea(manifest: manifest) { try? Data(contentsOf: area.appendingPathComponent($0), options: .alwaysMapped) }
        }
    }

    init(id: String, longitude: Double, latitude: Double, minX: Float, maxX: Float, minZ: Float, maxZ: Float, buildings: [Building]) {
        self.id = id
        self.longitude = longitude
        self.latitude = latitude
        (self.minX, self.maxX, self.minZ, self.maxZ) = (minX, maxX, minZ, maxZ)
        self.buildings = buildings
    }

    /// The buildings of one tile's bytes.
    static func buildings(in bytes: [UInt8]) throws -> [Building] {
        var reader = Reader(bytes: bytes)
        guard try reader.u32() == 0x3159_4B54 else { throw ReadError.notATile } // 'TKY1'
        let version = Int(try reader.u16())
        guard version == Self.version else { throw ReadError.version(version) }
        _ = try reader.u16()
        _ = try reader.u32() // tx
        _ = try reader.u32() // tz
        let count = Int(try reader.u32())
        try reader.skip(5 * 4) // the areas, props, wires, walls and signs
        var buildings: [Building] = []
        buildings.reserveCapacity(count)
        for _ in 0..<count {
            let usage = Int(try reader.u16()), storeys = Int(try reader.u8())
            _ = try reader.u8() // flags
            let base = try reader.f32(), height = try reader.f32()
            _ = try reader.f32() // measured height
            _ = try reader.u32() // hint
            let polygons = try reader.polygons()
            // PLATEAU's LOD2 shells: none in Taiwan's areas, read past.
            for _ in 0..<Int(try reader.u16()) {
                let bits = try reader.u8()
                for _ in 0..<Int(try reader.u8()) {
                    let points = Int(try reader.u16())
                    try reader.skip(points * 12 + (bits & 2 != 0 ? points * 4 : 0))
                }
            }
            buildings.append(Building(usage: usage, storeys: storeys, base: base, height: height, polygons: polygons))
        }
        return buildings
    }

    /// Little-endian numbers off the front of a tile.
    struct Reader {
        let bytes: [UInt8]
        var at = 0

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, at + count <= bytes.count else { throw ReadError.truncated }
            defer { at += count }
            return bytes[at..<(at + count)]
        }

        mutating func skip(_ count: Int) throws { _ = try take(count) }

        mutating func u8() throws -> UInt8 { try take(1).first ?? 0 }

        mutating func u16() throws -> UInt16 {
            try take(2).reversed().reduce(0) { $0 << 8 | UInt16($1) }
        }

        mutating func u32() throws -> UInt32 {
            try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

        mutating func polygons() throws -> [[[Point]]] {
            try (0..<Int(u16())).map { _ in
                try (0..<Int(u16())).map { _ in
                    try (0..<Int(u32())).map { _ in Point(x: try f32(), z: try f32()) }
                }
            }
        }
    }
}
