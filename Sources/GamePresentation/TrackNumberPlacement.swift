import Foundation

// Decision 631 (author's screenshot review, 2026-11-07): the tracks'
// numbers ("#14") covered the switches and the stations' names beside
// them. Each number now picks a place along its track where its plate
// covers neither a switch, a name nor a number already placed; when the
// middle will not do it tries other places along the track, then a
// smaller plate, and when none is free it is left out.

/// Where the tracks' numbers stand on the map, in screen points. Pure
/// geometry, so the placement is tested on Linux; the map measures the
/// plates and draws them.
public enum TrackNumberPlacement {
    /// A box on the screen.
    public struct Box: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public init(center: ScreenPoint, width: Double, height: Double) {
            self.init(minX: center.x - width / 2, minY: center.y - height / 2,
                      maxX: center.x + width / 2, maxY: center.y + height / 2)
        }

        /// Whether the two share any area (boxes that only touch do not).
        public func intersects(_ other: Box) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }
    }

    /// A number to place.
    public struct Candidate: Equatable, Sendable {
        public let id: Int
        /// The places it may stand, the best first.
        public let positions: [ScreenPoint]
        /// The plate's size at full scale.
        public let width: Double
        public let height: Double

        public init(id: Int, positions: [ScreenPoint], width: Double, height: Double) {
            self.id = id
            self.positions = positions
            self.width = width
            self.height = height
        }
    }

    public struct Placed: Equatable, Sendable {
        public let id: Int
        public let center: ScreenPoint
        /// 1 for the full plate, less for a smaller one.
        public let scale: Double
        public let box: Box
    }

    /// The sizes a plate may take, the largest first. Under the least a
    /// number would not be readable, so it is left out.
    public static let scales: [Double] = [1, 0.8, 0.65]

    /// Where along a track of `points` a number may stand, as fractions of
    /// its length: the middle, then either side of it.
    public static let fractions: [Double] = [0.5, 0.35, 0.65, 0.22, 0.78]

    /// The places along `points`, `beside` points to the left of the track
    /// (the middle first), for a number; none for a track of no length.
    public static func positions(along points: [ScreenPoint], beside: Double) -> [ScreenPoint] {
        let length = PolylineMarks.length(of: points)
        guard length > 0 else { return [] }
        return fractions.compactMap { fraction in
            PolylineMarks.mark(along: points, at: length * fraction).map {
                PolylineMarks.shifted($0, by: beside).point
            }
        }
    }

    /// What a switch keeps clear: a square `radius` points round the
    /// node.
    public static func switchBox(at point: ScreenPoint, radius: Double) -> Box {
        Box(center: point, width: radius * 2, height: radius * 2)
    }

    /// What a station keeps clear: its name's plate, `nameTop` points
    /// below the station, `nameWidth` wide and `height` tall (the badges
    /// of its lines and the shops' squares included).
    public static func nameBox(station: ScreenPoint, nameTop: Double, nameWidth: Double, height: Double) -> Box {
        Box(minX: station.x - nameWidth / 2, minY: station.y + nameTop,
            maxX: station.x + nameWidth / 2, maxY: station.y + nameTop + height)
    }

    /// Places `candidates` in order (the ones that matter most first),
    /// each at the first of its positions, at the largest scale, where its
    /// plate (with `margin` round it) lies in `view` and covers none of
    /// `obstacles` and none placed before, `taken` included. At most
    /// `limit` in all.
    public static func place(
        _ candidates: [Candidate], obstacles: [Box], taken: [Box] = [], view: Box, limit: Int, margin: Double = 2
    ) -> [Placed] {
        var blocked = obstacles + taken
        var placed: [Placed] = []
        for candidate in candidates {
            guard placed.count < limit else { break }
            if let found = fit(candidate, blocked: blocked, view: view, margin: margin) {
                blocked.append(found.box)
                placed.append(found)
            }
        }
        return placed
    }

    static func fit(_ candidate: Candidate, blocked: [Box], view: Box, margin: Double) -> Placed? {
        for scale in scales {
            for position in candidate.positions {
                let box = Box(center: position, width: candidate.width * scale + 2 * margin,
                              height: candidate.height * scale + 2 * margin)
                guard box.intersects(view), !blocked.contains(where: { $0.intersects(box) }) else { continue }
                return Placed(id: candidate.id, center: position, scale: scale, box: box)
            }
        }
        return nil
    }
}
