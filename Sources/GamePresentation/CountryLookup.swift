import Foundation
import GameCore

// Which country a real-world map lies in (ARCHITECTURE decision 154), so
// that its game keeps that country's public holidays (GameCore's
// ``HolidayCalendar``). The borders are Natural Earth's (public domain),
// simplified to about a kilometre (``encodedBorders``, written by
// `tools/country-borders/`); looking a point up needs no network and gives
// the same answer on every device. The answer is worked out once, when the
// game begins, and kept in the save (``GameWorld/disruptions``).

/// The country of a point on the Earth, among those whose holidays the game
/// has.
public enum CountryLookup {
    /// How far off a coast a point may be and still count as the nearest
    /// country's, in thousandths of a degree: about 30 km, so that a map
    /// centred on a harbour or a bay is not taken for the open sea.
    static let coastReach: Int64 = 300

    /// Islands the simplified borders leave out, as boxes in thousandths of
    /// a degree (west, south, east, north): Taiwan's Kinmen and Matsu, which
    /// lie off China's coast, so that they are not taken for it.
    static let islands: [(country: String, box: (Int64, Int64, Int64, Int64))] = [
        ("TW", (118_200, 24_380, 118_480, 24_530)),
        ("TW", (119_850, 25_930, 120_520, 26_400)),
    ]

    /// Each country's rings of (longitude, latitude), decoded once.
    static let borders: [(country: String, rings: [[(Int64, Int64)]])] = encodedBorders.keys.sorted().map { code in
        (code, decode(encodedBorders[code]!))
    }

    /// The country `anchor` lies in, or the nearest within ``coastReach``
    /// of it; ``HolidayCalendar/home`` when it is none of them.
    public static func country(at anchor: GeoAnchor) -> String {
        // Ten-millionths of a degree to thousandths.
        let point = (anchor.longitude / 10_000, anchor.latitude / 10_000)
        for island in islands where (island.box.0...island.box.2).contains(point.0) && (island.box.1...island.box.3).contains(point.1) {
            return island.country
        }
        for border in borders where contains(border.rings, point) {
            return border.country
        }
        var nearest: (country: String, distance: Int64)?
        for border in borders {
            for ring in border.rings {
                for corner in ring {
                    let dx = corner.0 - point.0, dy = corner.1 - point.1
                    let distance = dx * dx + dy * dy
                    if distance <= coastReach * coastReach, distance < nearest?.distance ?? .max {
                        nearest = (border.country, distance)
                    }
                }
            }
        }
        return nearest?.country ?? HolidayCalendar.home
    }

    /// Whether `point` is inside `rings` by the even-odd rule, so that a
    /// lake or an enclave is a hole.
    static func contains(_ rings: [[(Int64, Int64)]], _ point: (Int64, Int64)) -> Bool {
        var inside = false
        for ring in rings {
            var previous = ring[ring.count - 1]
            for corner in ring {
                // The edge crosses the point's latitude, and its crossing
                // lies east of the point.
                if (corner.1 > point.1) != (previous.1 > point.1) {
                    let lhs = (point.0 - corner.0) * (previous.1 - corner.1)
                    let rhs = (previous.0 - corner.0) * (point.1 - corner.1)
                    if previous.1 > corner.1 ? lhs < rhs : lhs > rhs {
                        inside.toggle()
                    }
                }
                previous = corner
            }
        }
        return inside
    }

    /// The rings of one country's ``encodedBorders``.
    static func decode(_ text: String) -> [[(Int64, Int64)]] {
        let bytes = [UInt8](Data(base64Encoded: text)!)
        var index = 0
        func next() -> Int64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while true {
                let byte = bytes[index]
                index += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return Int64(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
        }
        return (0..<next()).map { _ in
            var last: (Int64, Int64) = (0, 0)
            return (0..<next()).map { _ in
                last = (last.0 + next(), last.1 + next())
                return last
            }
        }
    }
}
