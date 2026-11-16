import GameCore

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

// Decision 800 (BUILD-CARD-PHONE, the owner's report from 0.6.0 (134), a
// phone held sideways): a stretch of track refused, the pill with its two
// height fixes and ✕ ✓ stood over the construction HUD's line that says
// why, and over the stretch itself; and both fixes said "NT$ 0".
extension BuildConfirmLayout {
    /// How the pill's words (a refusal, a note, the fixes) and its ✕ ✓
    /// stand.
    public enum Arrangement: Hashable, Sendable {
        /// The words over the buttons.
        case stacked
        /// The words beside the buttons: half as tall, for a screen with
        /// little height (a phone held sideways).
        case beside
        /// Decision 803, continued: a refusal with fixes on a short
        /// screen. Why across the top, as wide as the pill; under it one
        /// row of the fixes, each as wide as the other, and ✕ ✓.
        case strip
    }

    /// The pill's arrangement: ``Arrangement/beside`` where the screen is
    /// short (`compactHeight`) and the pill has words to say; a pill of
    /// only ✕ ✓ stays as it is. Decision 803: every build's pill (a
    /// platform's place, a building, a road, a bus or ferry route), not a
    /// stretch of track's alone; but the new line's (`ridesWithDrawer`),
    /// which carries its station pair drawer beside its words already
    /// (decision 384).
    public static func arrangement(
        compactHeight: Bool, hasWords: Bool, ridesWithDrawer: Bool = false, hasFixes: Bool = false
    ) -> Arrangement {
        guard compactHeight, hasWords, !ridesWithDrawer else { return .stacked }
        return hasFixes ? .strip : .beside
    }

    /// How tall the pill's buttons are, in points: 48, and 44 (a finger's
    /// least) in ``Arrangement/strip``, so the pill with its one line of
    /// why stands some 82 points tall and finds room above or below a
    /// stretch drawn across the middle of a phone held sideways (the 195
    /// points or so between the controls along its top and bottom,
    /// decision 803's leftover).
    public static func buttonHeight(_ arrangement: Arrangement) -> Double {
        arrangement == .strip ? 44 : 48
    }

    /// Decision 803, continued: how wide the pill's column is. Each child
    /// has the width it would take on one line (`ideal`), and words that
    /// may wrap a width they wrap at (`cap`; `nil` for buttons, which do
    /// not): the widest of them, within `limit`. Every child is then
    /// given that width, so why a stretch is refused runs as wide as the
    /// pill and the fixes line up under it.
    public static func columnWidth(_ children: [(ideal: Double, cap: Double?)], limit: Double?) -> Double {
        let widest = children.map { child in child.cap.map { min(child.ideal, $0) } ?? child.ideal }.max() ?? 0
        return min(widest, limit ?? .infinity)
    }

    /// Decision 803, continued: the fixes as cells of one width (#2302's
    /// screenshots: the bridge narrower than the tunnel, their edges out
    /// of line). Side by side where `available` holds them at the widest
    /// one's width (`nil`: as wide as they like), filling it; else one
    /// over another, each as wide as `available` or the widest. Half a
    /// point short still counts as holding them: a row offered the very
    /// width it asked for may come back a rounding short.
    public static func equalCells(ideal: [Double], available: Double?, spacing: Double) -> (cell: Double, stacked: Bool) {
        let widest = ideal.max() ?? 0
        let count = Double(ideal.count)
        guard count > 0 else { return (0, false) }
        guard let available, available.isFinite else { return (widest, false) }
        let across = (available - spacing * (count - 1)) / count
        if across >= widest - 0.5 { return (max(across, widest), false) }
        return (max(widest, available), count > 1)
    }

    /// The widest a stretch's refusal wraps at, in points: some three
    /// lines of the caption, so the pill covers no more of the map than
    /// its buttons need.
    public static let wordsWidth = 340.0

    /// Decision 803: whether the ✕ ✓ pill is on the map. Not while a
    /// finger draws the stretch: it stood under the finger, which hid it
    /// and the stretch's end; it comes once the finger lets go.
    public static func pillShows(fingerDraws: Bool) -> Bool {
        !fingerDraws
    }

    /// Decision 803, continued: whether a finger still draws what the
    /// pill would confirm. A stretch of track was decision 803's; a road
    /// drawn and a building moved kept the pill under the finger.
    public static func fingerDraws(track: Bool, road: Bool, building: Bool, tool: ConstructionTool, roadsMode: Bool) -> Bool {
        switch tool {
        case .network: track
        case .bus: roadsMode && road
        case .building: building
        case .select, .train: false
        }
    }

    /// Why a stretch is refused, as the pill writes it and as VoiceOver
    /// reads it (decision 803, continued): the one short line where there
    /// is one, the whole sentence aloud.
    public static func refusal(of preview: NetworkPreview) -> (shown: String, spoken: String)? {
        preview.problem.map { (preview.problemBrief ?? $0, $0) }
    }

    /// The one small mark the construction HUD's row carries after the
    /// length and the height (decision 803: the row says nothing else).
    public enum HUDMark: Hashable, Sendable {
        case none
        /// The stretch joins track that is there.
        case joins
        /// The stretch is refused, and the pill is not there to say why (a
        /// finger still draws): a warning sign, the words kept for the
        /// pill.
        case refused
    }

    /// The HUD's mark: a refusal the pill says beside its ✓ is not marked
    /// here too.
    public static func hudMark(refused: Bool, pillSaysProblem: Bool, joins: Bool) -> HUDMark {
        if refused { return pillSaysProblem ? .none : .refused }
        return joins ? .joins : .none
    }

    /// What a stretch's pill says over its buttons, a line each, or `nil`
    /// for nothing. Decision 803: only what it offers besides (`offer`: a
    /// real line for sale along it); its notes (the first stretch is
    /// straight, the crossovers a double track adds) are the details
    /// card's. Continued: refused too, where they stood under the reason.
    public static func stretchCaption(offer: [String?]) -> String? {
        let lines = offer.compactMap(\.self).filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// A price as the pill writes it, or `nil` for none: nothing is
    /// written for a build that costs nothing (with unlimited funds every
    /// price is NT$ 0; the roads, bus routes and ferries already wrote
    /// none).
    public static func priceText(of cost: Money?, in language: DisplayLanguage) -> String? {
        guard let cost, cost > .zero else { return nil }
        return cost.compactText(in: language)
    }

    /// A flag's frame over its `point` (28 points across, standing above
    /// the point so it stays in sight).
    public static func flagFrame(at point: ScreenPoint) -> ScreenFrame {
        ScreenFrame(x: point.x - 14, y: point.y - 36, width: 28, height: 28)
    }

    /// What the pill keeps off while a stretch of track is drawn: its end
    /// (`anchor`), the flags at its ends (`flags`, the points they stand
    /// over) and the pieces of `line`, the stretch in the screen's points,
    /// nearest the end. A long line (a trace along a real railway) is
    /// thinned to some `samples` points first.
    public static func stretchObstacles(
        _ line: [ScreenPoint], flags: [ScreenPoint], around anchor: ScreenPoint, reach: Double, samples: Int = 128
    ) -> [ScreenFrame] {
        var thinned = line
        if samples > 1, line.count > samples {
            let step = (line.count + samples - 2) / (samples - 1)
            thinned = stride(from: 0, to: line.count, by: step).map { line[$0] }
            if let last = line.last, thinned.last != last { thinned.append(last) }
        }
        let site = siteObstacles([thinned], around: anchor, reach: reach)
        return [site[0]] + flags.map(flagFrame(at:)) + site.dropFirst()
    }
}

extension GameSession {
    /// Whether a finger still draws what the map's ✕ ✓ pill would confirm
    /// (``BuildConfirmLayout/fingerDraws(track:road:building:tool:roadsMode:)``).
    public var buildFingerDraws: Bool {
        BuildConfirmLayout.fingerDraws(
            track: networkDragFinger != nil, road: roadDragStart != nil, building: buildingDragSiteBefore != nil,
            tool: tool, roadsMode: busMode == .roads
        )
    }
}
