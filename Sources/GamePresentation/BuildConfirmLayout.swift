// How wide the map's ✕ and ✓ pill may be, and where it goes across the
// map (decision 107). TestFlight 67.1, a phone held sideways with the track
// card open: a long refusal stood on one line, and the pill ran from the
// tools under the card, its words cut off there. The app measures the pill
// and the map's edges; this keeps the pill within the map's clear band, its
// words wrapping, so it is tested off Apple's platforms too.

/// How wide the map's build pill may be, and where its leading edge goes,
/// in the screen's points.
public enum BuildConfirmLayout {
    /// The gap the pill keeps from what floats over the map's sides.
    public static let margin = 8.0
    /// The narrowest the pill's words are given, so a squeezed map does not
    /// stand them a word to a line.
    public static let minimumWidth = 160.0

    /// The widest the pill may be: the map's width less what floats over
    /// its leading and trailing edges, and a margin beside each.
    public static func maximumWidth(viewportWidth: Double, leading: Double, trailing: Double) -> Double {
        max(minimumWidth, viewportWidth - leading - trailing - 2 * margin)
    }

    /// The pill's leading edge, for a pill `width` wide: centred on
    /// `anchorX`, kept within the clear band; at the band's leading side
    /// when it does not fit.
    public static func originX(anchorX: Double, width: Double, viewportWidth: Double, leading: Double, trailing: Double) -> Double {
        let minX = leading + margin
        let maxX = viewportWidth - trailing - width - margin
        return min(max(anchorX - width / 2, minX), max(minX, maxX))
    }
}

extension BuildConfirmLayout {
    /// The pill at `x`, `y`, `width` by `height`, moved off what it covers
    /// of `obstacles`: to the nearest place that covers none of them, above
    /// or below one, or beside it, within `minX`…`maxX` across and
    /// `highest`…`lowest` down; where no place is clear, the one that
    /// covers least. Decision 384: the new line's station pair drawer is
    /// one of them, which covered its ✓ (TestFlight 85.1). Decision 568:
    /// moved off one, it may land on another (a phone held sideways: up off
    /// the layer's legend, onto the buttons above it), so every place is
    /// checked against them all, not one obstacle after another.
    public static func keepingOff(
        _ obstacles: [ScreenFrame], x: Double, y: Double, width: Double, height: Double,
        minX: Double, maxX: Double, highest: Double, lowest: Double = .infinity
    ) -> (x: Double, y: Double) {
        let solid = obstacles.filter { $0.width > 0 && $0.height > 0 }
        func covered(_ place: (x: Double, y: Double)) -> Double {
            solid.reduce(0) { total, frame in
                guard overlaps(x: place.x, y: place.y, width: width, height: height, frame, by: margin / 2) else { return total }
                let across = min(place.x + width, frame.x + frame.width) - max(place.x, frame.x)
                let down = min(place.y + height, frame.y + frame.height) - max(place.y, frame.y)
                // Within the gap but not over it still counts, a little.
                return total + max(1, max(0, across) * max(0, down))
            }
        }
        func fits(_ place: (x: Double, y: Double)) -> Bool {
            place.x >= minX - 0.5 && place.x <= maxX + 0.5 && place.y >= highest - 0.5 && place.y <= lowest + 0.5
        }
        let start = (x: x, y: y)
        guard covered(start) > 0 else { return start }
        // The places beside each obstacle, then beside each again from
        // there (above one and beside the next, say).
        func moves(from place: (x: Double, y: Double)) -> [(x: Double, y: Double)] {
            solid.flatMap { frame -> [(x: Double, y: Double)] in
                [
                    (place.x, frame.y - margin - height),
                    (place.x, frame.y + frame.height + margin),
                    (frame.x + frame.width + margin, place.y),
                    (frame.x - margin - width, place.y),
                ]
            }
        }
        let first = moves(from: start)
        let candidates = first + first.flatMap { moves(from: $0) }
        let distance: ((x: Double, y: Double)) -> Double = { place in
            (place.x - x) * (place.x - x) + (place.y - y) * (place.y - y)
        }
        let inside = candidates.filter(fits)
        if let clear = inside.filter({ covered($0) == 0 }).min(by: { distance($0) < distance($1) }) {
            return clear
        }
        return ([start] + inside).min { covered($0) < covered($1) || (covered($0) == covered($1) && distance($0) < distance($1)) } ?? start
    }

    /// Whether the pill at `x`, `y` comes within `gap` of `frame`.
    public static func overlaps(x: Double, y: Double, width: Double, height: Double, _ frame: ScreenFrame, by gap: Double = 0) -> Bool {
        x < frame.x + frame.width + gap && x + width > frame.x - gap
            && y < frame.y + frame.height + gap && y + height > frame.y - gap
    }
}

extension BuildConfirmLayout {
    /// How far each side of a track's centre line the pill keeps off,
    /// in points: the line drawn and a little beside it.
    public static let trackHalfWidth = 6.0
    /// The place picked, as a square this many points a side: kept in
    /// sight under the pill (decision 744).
    public static let siteSize = 24.0

    /// Decision 744 (a player's report, 2026-11-14: choosing where a
    /// station goes, the pill with who lives around it and ✓ stood right
    /// over the line, so where the station would go could not be seen):
    /// the place picked and the track around it, `lines` in the screen's
    /// points, as small boxes ``keepingOff(_:x:y:width:height:minX:maxX:highest:lowest:)``
    /// keeps the pill off. Each line is cut into pieces at most `piece`
    /// points long; the `limit` pieces nearest `anchor` within `reach` are
    /// kept, so the search stays quick on a dense network.
    public static func siteObstacles(
        _ lines: [[ScreenPoint]], around anchor: ScreenPoint, reach: Double,
        piece: Double = 48, limit: Int = 16
    ) -> [ScreenFrame] {
        var pieces: [(distance: Double, frame: ScreenFrame)] = []
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = (dx * dx + dy * dy).squareRoot()
                let count = max(1, Int((length / piece).rounded(.up)))
                for index in 0..<count {
                    let t0 = Double(index) / Double(count), t1 = Double(index + 1) / Double(count)
                    let x0 = a.x + dx * t0, y0 = a.y + dy * t0
                    let x1 = a.x + dx * t1, y1 = a.y + dy * t1
                    let mx = (x0 + x1) / 2 - anchor.x, my = (y0 + y1) / 2 - anchor.y
                    let distance = (mx * mx + my * my).squareRoot()
                    guard distance <= reach else { continue }
                    pieces.append((distance, ScreenFrame(
                        x: min(x0, x1) - trackHalfWidth, y: min(y0, y1) - trackHalfWidth,
                        width: abs(x1 - x0) + 2 * trackHalfWidth, height: abs(y1 - y0) + 2 * trackHalfWidth
                    )))
                }
            }
        }
        let site = ScreenFrame(x: anchor.x - siteSize / 2, y: anchor.y - siteSize / 2, width: siteSize, height: siteSize)
        let nearest = pieces.sorted { $0.distance < $1.distance }.prefix(max(0, limit)).map(\.frame)
        return [site] + nearest
    }
}
