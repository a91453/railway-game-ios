/// A Mapbox Vector Tile 2.1 (https://github.com/mapbox/vector-tile-spec/tree/master/2.1):
/// the base map's tiles, decoded for the 3D map (decision 234).
///
/// Decoded as the reference's location modeler does (`RKVT.decode` in
/// `Railway/location_modeler_reference_clean/source/js/app.js`): a minimal
/// protobuf reader, MoveTo, LineTo and ClosePath with zigzag deltas, and the
/// layers asked for only.
struct VectorTile: Sendable {
    struct Layer: Sendable {
        let name: String
        /// Tile units across the tile (4,096 in the base map).
        let extent: Int
        let features: [Feature]
    }

    enum Kind: Int, Sendable {
        case unknown = 0, point, line, polygon
    }

    enum Value: Hashable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
    }

    struct Point: Hashable, Sendable {
        let x: Int32, y: Int32
    }

    struct Feature: Sendable {
        let kind: Kind
        let properties: [String: Value]
        /// The points of each part, in tile units: a point's, a line's, or a
        /// polygon's rings (closed: the first point is not repeated).
        let parts: [[Point]]

        func string(_ key: String) -> String? {
            if case .string(let value) = properties[key] { return value }
            return nil
        }

        /// A polygon's parts as polygons: each exterior ring (clockwise as
        /// drawn, y down: a positive area) with the interior rings after it.
        var polygons: [[[Point]]] {
            var polygons: [[[Point]]] = []
            for ring in parts where ring.count >= 3 {
                let area = Self.signedArea(ring)
                if area > 0 || polygons.isEmpty {
                    guard area != 0 else { continue }
                    polygons.append([ring])
                } else if area < 0 {
                    polygons[polygons.count - 1].append(ring)
                }
            }
            return polygons
        }

        /// The surveyor's formula, y down: positive for a ring clockwise on
        /// the screen.
        static func signedArea(_ ring: [Point]) -> Int64 {
            var sum: Int64 = 0
            var previous = ring[ring.count - 1]
            for point in ring {
                sum += Int64(previous.x) * Int64(point.y) - Int64(point.x) * Int64(previous.y)
                previous = point
            }
            return sum
        }
    }

    enum Failure: Error, Equatable {
        case malformed
    }

    let layers: [String: Layer]

    /// The layers of `bytes` named in `wanted` (every layer when `nil`).
    init(_ bytes: [UInt8], layers wanted: Set<String>? = nil) throws(Failure) {
        var layers: [String: Layer] = [:]
        var reader = Reader(bytes: bytes[...])
        while let (field, wire) = try reader.key() {
            guard field == 3, wire == 2 else { try reader.skip(wire); continue }
            let layer = try Self.layer(try reader.field(), wanted: wanted)
            if let layer { layers[layer.name] = layer }
        }
        self.layers = layers
    }

    private static func layer(_ bytes: ArraySlice<UInt8>, wanted: Set<String>?) throws(Failure) -> Layer? {
        var reader = Reader(bytes: bytes)
        var name = "", extent = 4096
        var features: [ArraySlice<UInt8>] = [], keys: [String] = [], values: [Value] = []
        while let (field, wire) = try reader.key() {
            switch (field, wire) {
            case (1, 2):
                name = String(decoding: try reader.field(), as: UTF8.self)
                if let wanted, !wanted.contains(name) { return nil }
            case (2, 2): features.append(try reader.field())
            case (3, 2): keys.append(String(decoding: try reader.field(), as: UTF8.self))
            case (4, 2): values.append(try value(try reader.field()))
            case (5, 0): extent = Int(try reader.varint())
            default: try reader.skip(wire)
            }
        }
        var decoded: [Feature] = []
        decoded.reserveCapacity(features.count)
        for bytes in features {
            decoded.append(try feature(bytes, keys: keys, values: values))
        }
        return Layer(name: name, extent: extent, features: decoded)
    }

    private static func value(_ bytes: ArraySlice<UInt8>) throws(Failure) -> Value {
        var reader = Reader(bytes: bytes)
        var value = Value.string("")
        while let (field, wire) = try reader.key() {
            switch (field, wire) {
            case (1, 2): value = .string(String(decoding: try reader.field(), as: UTF8.self))
            case (2, 5): value = .number(Double(Float(bitPattern: try reader.fixed32())))
            case (3, 1): value = .number(Double(bitPattern: try reader.fixed64()))
            case (4, 0): value = .number(Double(Int64(bitPattern: try reader.varint())))
            case (5, 0): value = .number(Double(try reader.varint()))
            case (6, 0):
                let raw = try reader.varint()
                value = .number(Double(Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1)))
            case (7, 0): value = .bool(try reader.varint() != 0)
            default: try reader.skip(wire)
            }
        }
        return value
    }

    private static func feature(_ bytes: ArraySlice<UInt8>, keys: [String], values: [Value]) throws(Failure) -> Feature {
        var reader = Reader(bytes: bytes)
        var tags: [Int] = [], kind = Kind.unknown, geometry: [UInt32] = []
        while let (field, wire) = try reader.key() {
            switch (field, wire) {
            case (2, 2):
                var packed = Reader(bytes: try reader.field())
                while !packed.isAtEnd { tags.append(Int(try packed.varint())) }
            case (3, 0): kind = Kind(rawValue: Int(try reader.varint())) ?? .unknown
            case (4, 2):
                var packed = Reader(bytes: try reader.field())
                while !packed.isAtEnd { geometry.append(UInt32(truncatingIfNeeded: try packed.varint())) }
            default: try reader.skip(wire)
            }
        }
        var properties: [String: Value] = [:]
        var index = 0
        while index + 1 < tags.count {
            guard tags[index] < keys.count, tags[index + 1] < values.count else { throw .malformed }
            properties[keys[tags[index]]] = values[tags[index + 1]]
            index += 2
        }
        return Feature(kind: kind, properties: properties, parts: try parts(geometry))
    }

    private static func parts(_ commands: [UInt32]) throws(Failure) -> [[Point]] {
        var parts: [[Point]] = [], part: [Point] = []
        var x: Int32 = 0, y: Int32 = 0, at = 0
        func zigzag(_ value: UInt32) -> Int32 { Int32(bitPattern: value >> 1) ^ -Int32(bitPattern: value & 1) }
        while at < commands.count {
            let id = commands[at] & 7, count = Int(commands[at] >> 3)
            at += 1
            switch id {
            case 1, 2:  // MoveTo, LineTo
                guard at + 2 * count <= commands.count else { throw .malformed }
                if id == 1, !part.isEmpty {
                    parts.append(part)
                    part = []
                }
                for _ in 0..<count {
                    x &+= zigzag(commands[at])
                    y &+= zigzag(commands[at + 1])
                    at += 2
                    part.append(Point(x: x, y: y))
                }
            case 7:  // ClosePath
                if !part.isEmpty {
                    parts.append(part)
                    part = []
                }
            default:
                throw .malformed
            }
        }
        if !part.isEmpty { parts.append(part) }
        return parts
    }

    /// Protocol buffers' wire format, as much of it as a tile uses.
    private struct Reader {
        let bytes: ArraySlice<UInt8>
        var at: Int

        init(bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            at = bytes.startIndex
        }

        var isAtEnd: Bool { at >= bytes.endIndex }

        mutating func varint() throws(Failure) -> UInt64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while true {
                guard at < bytes.endIndex, shift < 64 else { throw .malformed }
                let byte = bytes[at]
                at += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }

        mutating func key() throws(Failure) -> (field: Int, wire: Int)? {
            guard !isAtEnd else { return nil }
            let key = try varint()
            return (Int(key >> 3), Int(key & 7))
        }

        mutating func field() throws(Failure) -> ArraySlice<UInt8> {
            let length = Int(try varint())
            guard length >= 0, at + length <= bytes.endIndex else { throw .malformed }
            defer { at += length }
            return bytes[at..<(at + length)]
        }

        mutating func fixed32() throws(Failure) -> UInt32 {
            guard at + 4 <= bytes.endIndex else { throw .malformed }
            defer { at += 4 }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
        }

        mutating func fixed64() throws(Failure) -> UInt64 {
            guard at + 8 <= bytes.endIndex else { throw .malformed }
            defer { at += 8 }
            return (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[at + $1]) << (8 * UInt64($1)) }
        }

        mutating func skip(_ wire: Int) throws(Failure) {
            switch wire {
            case 0: _ = try varint()
            case 1: guard at + 8 <= bytes.endIndex else { throw .malformed }; at += 8
            case 2: _ = try field()
            case 5: guard at + 4 <= bytes.endIndex else { throw .malformed }; at += 4
            default: throw .malformed
            }
        }
    }
}
