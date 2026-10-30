import GameCore

// Decision 477: the map's floating labels kept off the station names and
// off each other. The website's and the promotion's screenshots (runs
// 40805756457 and 40812436549) showed a short-of-materials bubble on the
// name of the station above it, a "+$1.5k" fare on the name of the
// station beside it, the sights' stars on the prices of the map's tiles,
// and the map's place names under the top bar with only their last
// character showing. Each label tries a few places round its point and
// takes the first one clear of the names, the stations' marks and the
// labels placed before it; with none clear, the one that covers least.
// The sizes are estimates (the app draws the text), close enough to keep
// the plates apart. Worked out here, for Linux tests; the app only draws.

/// Where the map's floating labels go.
public enum MapLabelPlacement {
    public typealias Box = MapProblems.Placement.Box

    /// A station on the screen, as the map draws it: its middle, and the
    /// name on a plate under it.
    public struct Station: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let name: String

        public init(x: Double, y: Double, name: String) {
            self.x = x
            self.y = y
            self.name = name
        }
    }

    /// About how wide `text` is in a font of `size` points: a Chinese
    /// character or a wide letter a whole size, a narrow letter, digit or
    /// mark six tenths of it.
    public static func textWidth(_ text: String, size: Double) -> Double {
        text.unicodeScalars.reduce(0) { width, scalar in
            width + (scalar.value >= 0x2E80 ? size : size * 0.6)
        }
    }

    /// The plate of a station's name (``MapArt``'s `drawStationName`): an
    /// 11-point caption from `radius` + 4 under the middle, 2 points wider
    /// each side. Not the row of its lines' badges under it (decision 216),
    /// which a label may lie on sooner than on a name.
    public static func nameBox(of station: Station, radius: Double) -> Box {
        let width = textWidth(station.name, size: 11) + 4
        return Box(x: station.x - width / 2, y: station.y + radius + 4, width: width, height: 15)
    }

    /// A station's mark and the waiting count's pill over it (decision 210).
    public static func markBox(of station: Station, radius: Double) -> Box {
        Box(x: station.x - max(radius, 20), y: station.y - radius - 20, width: max(radius, 20) * 2, height: radius * 2 + 20)
    }

    /// What labels keep off: every station's name, and the marks of all
    /// but the one at `own` (whose own label may lie on its pill).
    public static func obstacles(_ stations: [Station], radius: Double, own: (x: Double, y: Double)? = nil) -> [Box] {
        stations.flatMap { station -> [Box] in
            let isOwn = own.map { abs($0.x - station.x) < 1 && abs($0.y - station.y) < 1 } ?? false
            return isOwn ? [nameBox(of: station, radius: radius)] : [nameBox(of: station, radius: radius), markBox(of: station, radius: radius)]
        }
    }

    /// The first of `candidates` clear of `obstacles` by `gap`, or, with
    /// none clear, the one that covers the least of them.
    public static func choose(_ candidates: [Box], avoiding obstacles: [Box], gap: Double = 2) -> Int {
        precondition(!candidates.isEmpty, "A label needs somewhere to go")
        if let clear = candidates.firstIndex(where: { box in !obstacles.contains { $0.overlaps(box, gap: gap) } }) {
            return clear
        }
        let covered = candidates.map { box in obstacles.reduce(0) { $0 + overlap($1, box) } }
        return covered.indices.min { covered[$0] < covered[$1] } ?? 0
    }

    static func overlap(_ a: Box, _ b: Box) -> Double {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) * max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    // MARK: - Alert bubbles (decision 109)

    /// The places tried for an alert's bubble of `width` by `height` over
    /// a point (decision 210: `lift` over it, above the waiting count's
    /// pill): over it, over and to the right or left, on its own pill,
    /// under its name, and a bubble's height higher.
    public static func bubbleCandidates(x: Double, y: Double, lift: Double, radius: Double, width: Double, height: Double) -> [Box] {
        let top = y - lift - height
        return [
            Box(x: x - width / 2, y: top, width: width, height: height),
            Box(x: x + radius, y: top, width: width, height: height),
            Box(x: x - radius - width, y: top, width: width, height: height),
            Box(x: x - width / 2, y: y - radius - 4 - height, width: width, height: height),
            Box(x: x - width / 2, y: y + radius + 34, width: width, height: height),
            Box(x: x - width / 2, y: top - 46, width: width, height: height),
        ]
    }

    /// An alert's bubble: its text's width and whether it has a second
    /// line (decision 210's reason), as ``MapAlertBubbles`` draws it.
    public struct Bubble: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let text: String
        public let hasReason: Bool

        public init(x: Double, y: Double, text: String, hasReason: Bool) {
            self.x = x
            self.y = y
            self.text = text
            self.hasReason = hasReason
        }

        /// A 20-point glyph, a 12-point caption and the capsule's padding.
        public var width: Double { 4 + 20 + 4 + MapLabelPlacement.textWidth(text, size: 12) + 8 }
        public var height: Double { hasReason ? 40 : 28 }
    }

    /// Where each bubble goes, in order: its box's bottom middle. Each
    /// keeps off the stations' names and marks (but its own station's
    /// mark) and the bubbles placed before it, those by 8 points more
    /// up and down, so their 44-point touch areas do not meet.
    public static func placeBubbles(_ bubbles: [Bubble], stations: [Station], lift: Double, radius: Double) -> [ScreenPoint] {
        var placed: [Box] = []
        return bubbles.map { bubble in
            let candidates = bubbleCandidates(x: bubble.x, y: bubble.y, lift: lift, radius: radius, width: bubble.width, height: bubble.height)
            let around = obstacles(stations, radius: radius, own: (bubble.x, bubble.y))
                + placed.map { Box(x: $0.minX, y: $0.minY - 8, width: $0.maxX - $0.minX, height: $0.maxY - $0.minY + 16) }
            let box = candidates[choose(candidates, avoiding: around)]
            placed.append(box)
            return ScreenPoint(x: (box.minX + box.maxX) / 2, y: box.maxY)
        }
    }

    /// A placed bubble's box, from its bottom middle (``placeBubbles``).
    public static func bubbleBox(_ bubble: Bubble, at point: ScreenPoint) -> Box {
        Box(x: point.x - bubble.width / 2, y: point.y - bubble.height, width: bubble.width, height: bubble.height)
    }

    /// Where a placed bubble takes a touch: its box, at least 44 by 28,
    /// touched over 44 high round its middle (``MapAlertBubbles``'
    /// `TouchTargetButtonStyle`).
    public static func bubbleTouchBox(_ bubble: Bubble, at point: ScreenPoint) -> Box {
        let box = bubbleBox(bubble, at: point)
        let width = max(box.maxX - box.minX, 44), height = max(box.maxY - box.minY, 44)
        return Box(x: point.x - width / 2, y: (box.minY + box.maxY - height) / 2, width: width, height: height)
    }

    // MARK: - The selected station's tag (decisions 119 and 501)

    /// Where the tag of the station at `point` goes, `width` by `height`,
    /// inside `clear`: under the station's mark and name, or over them
    /// where there is no room below.
    public static func stationTag(at point: ScreenPoint, width: Double, height: Double, clear: Box, avoiding bubbles: [Box]) -> Box {
        let clearance = 34.0
        let x = min(max(point.x - width / 2, clear.minX), max(clear.minX, clear.maxX - width))
        var y = point.y + clearance
        if y + height > clear.maxY {
            y = point.y - clearance - height
        }
        y = min(max(y, clear.minY), max(clear.minY, clear.maxY - height))
        return Box(x: x, y: y, width: width, height: height)
    }

    // MARK: - Fares (decision 256)

    /// The places tried for a fare of `width` by `height` at a station:
    /// over it (on its pill, as before), higher, to its right or left,
    /// and under its name.
    public static func fareCandidates(x: Double, y: Double, radius: Double, width: Double, height: Double) -> [Box] {
        [
            Box(x: x - width / 2, y: y - 22 - height / 2, width: width, height: height),
            Box(x: x - width / 2, y: y - 44 - height / 2, width: width, height: height),
            Box(x: x + radius + 4, y: y - height / 2, width: width, height: height),
            Box(x: x - radius - 4 - width, y: y - height / 2, width: width, height: height),
            Box(x: x - width / 2, y: y + radius + 34, width: width, height: height),
        ]
    }

    /// Where each fare ("+$12", a 12-point caption on a capsule) goes, in
    /// order: its middle.
    public static func placeFares(_ fares: [(x: Double, y: Double, text: String)], stations: [Station], radius: Double) -> [ScreenPoint] {
        var placed: [Box] = []
        return fares.map { fare in
            let width = textWidth(fare.text, size: 12) + 12, height = 20.0
            let candidates = fareCandidates(x: fare.x, y: fare.y, radius: radius, width: width, height: height)
            let box = candidates[choose(candidates, avoiding: obstacles(stations, radius: radius, own: (fare.x, fare.y)) + placed)]
            placed.append(box)
            return ScreenPoint(x: (box.minX + box.maxX) / 2, y: (box.minY + box.maxY) / 2)
        }
    }

    // MARK: - The map's tiles for sale (decision 160)

    /// Where a tile's price goes: the middle of the part of `tile` in
    /// `clear` (the map less what floats over its edges), so that it is
    /// not under the top bar or a card; nil when that part is not as tall
    /// as a price of `width` by `height`, or narrower than half of it. A
    /// tile smaller than its price, zoomed out, still shows it.
    public static func tileLabel(tile: Box, clear: Box, width: Double, height: Double) -> Box? {
        let minX = max(tile.minX, clear.minX), maxX = min(tile.maxX, clear.maxX)
        let minY = max(tile.minY, clear.minY), maxY = min(tile.maxY, clear.maxY)
        guard maxY - minY >= min(height, tile.maxY - tile.minY), maxX - minX >= min(width, tile.maxX - tile.minX) / 2 else { return nil }
        return Box(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2, width: width, height: height)
    }

    /// The width of a tile's price as the map draws it (a 12-point bold
    /// caption, and a lock before it on a tile still locked).
    public static func priceWidth(_ price: String, locked: Bool) -> Double {
        textWidth(price, size: 12) + (locked ? 16 : 0)
    }

    /// Whether a sight's mark (decision 174: a star and its rating on a
    /// 22-point capsule, `stars` wide) at a point would cover a price.
    public static func coversPrice(x: Double, y: Double, stars: String, prices: [Box]) -> Bool {
        let width = 6 + 13 + 3 + textWidth(stars, size: 11) + 6
        let mark = Box(x: x - width / 2, y: y - 11, width: width, height: 22)
        return prices.contains { $0.overlaps(mark, gap: 2) }
    }

    // MARK: - The map's place names (decision 97)

    /// The parts of the map under what floats over its edges (``clear``'s
    /// insets of a map `width` by `height`): the bands the base map's own
    /// place names keep out of, as they keep out of the stations' names.
    public static func coveredBands(width: Double, height: Double, top: Double, leading: Double, bottom: Double, trailing: Double) -> [Box] {
        let bands = [
            Box(x: 0, y: 0, width: width, height: top),
            Box(x: 0, y: top, width: leading, height: height - top - bottom),
            Box(x: width - trailing, y: top, width: trailing, height: height - top - bottom),
            Box(x: 0, y: height - bottom, width: width, height: bottom),
        ]
        return bands.filter { $0.maxX - $0.minX >= 1 && $0.maxY - $0.minY >= 1 }
    }
}
