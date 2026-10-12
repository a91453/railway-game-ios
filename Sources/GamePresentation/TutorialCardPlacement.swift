// Where the tutorial's card goes (Stage C5): the app measures the card and
// the controls on screen, this chooses. It lived in the app's layout until
// a phone on its side (decision 106) put the card over the lines panel at
// the line step, where nothing could be tapped and Next never came: here,
// it is tested off Apple's platforms on that screen too. It has its own
// rectangles: GamePresentation imports no CoreGraphics (decision 45), whose
// `Frame` geometry Foundation does not bring on Apple's platforms.

/// Where the tutorial's card goes: beside the step's first target on
/// screen, clear of every control and panel, leaving the step's own
/// controls and a band of the map free to tap.
///
/// Tries below and above the target, then its sides, then (when the
/// target is the map) the map's top trailing corner, then inside a large
/// target such as the map, then the free map's corners, then the centre
/// and the edges. The first placement that covers no control wins; when
/// every one covers something, the one that covers least, sparing the
/// step's own controls first. No target: the centre.
///
/// Covering the map costs nothing, as long as a band of it at least
/// ``minimumFreeMap`` deep stays free beside the card: on a phone, held on
/// its side, the map between the status pill and the dock can be barely
/// taller than the card, and a card over all of it would leave the player
/// nowhere to tap. Covering the HUD's controls then costs less, and a card
/// too tall for any place (large text) is measured shorter, its
/// explanation scrolling, or narrower, so that band stays free.
///
/// When even then the card covers what the step asks for
/// (``leavesStepFree(_:)``), the app folds it to its title.
public struct TutorialCardPlacement: Sendable {
    /// A rectangle in the screen's points, `Frame`'s geometry for what the
    /// placement needs.
    public struct Frame: Equatable, Sendable, CustomStringConvertible {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var minX: Double { x }
        public var minY: Double { y }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }

        public var description: String {
            "(\(x), \(y), \(width) × \(height))"
        }

        /// Whether the two share some area (touching edges do not).
        public func intersects(_ other: Frame) -> Bool {
            overlap(with: other) > 0
        }

        /// The area the two share.
        func overlap(with other: Frame) -> Double {
            let width = min(maxX, other.maxX) - max(minX, other.minX)
            let height = min(maxY, other.maxY) - max(minY, other.minY)
            return width > 0 && height > 0 ? width * height : 0
        }

        /// Whether `other` lies wholly inside.
        func contains(_ other: Frame) -> Bool {
            other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
        }

        func offsetBy(dx: Double, dy: Double) -> Frame {
            Frame(x: x + dx, y: y + dy, width: width, height: height)
        }

        func insetBy(dx: Double, dy: Double) -> Frame {
            Frame(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
        }
    }

    /// A size in the screen's points.
    public struct Size: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// The first of the step's targets on screen, which the card goes
    /// beside; `nil` puts it in the middle.
    public var target: Frame?
    /// Every control on screen but the map, which can be tapped outside the
    /// card.
    public var controls: [Frame]
    /// A panel beside the map: covering it costs as much as covering the
    /// step's own controls, which it may hold unmarked (its NavigationStack
    /// keeps its controls' marks from the overlay), and a card over it folds.
    public var panels: [Frame]
    /// The details card, whose controls are marked: the card stays off it
    /// where there is room, but covers it rather than any control (a phone
    /// with the largest text, decision 47's notes: covering it as a panel
    /// pushed the card over the tool rail's Done).
    public var backdrops: [Frame]
    /// The step's own controls (not the map), among `controls`.
    public var required: [Frame]
    /// The part of the map that shows (``TutorialTarget/map``).
    public var map: Frame?
    /// The widest the card is laid out.
    public var maxWidth: Double

    /// The card's distance from the screen's edges.
    static let margin: Double = 16
    /// Its distance from its target.
    static let gap: Double = 12
    /// The depth of the band of the map left free beside the card.
    public static let minimumFreeMap: Double = 96
    /// The shortest a card is measured to leave the map free: the step's
    /// title, a few lines of its explanation and its buttons.
    static let minimumCardHeight: Double = 200
    /// The narrowest a card is measured to leave a band of the map free
    /// beside it.
    static let minimumCardWidth: Double = 240
    /// Above covering any ordinary control with the whole card, below
    /// covering a sliver of the step's own controls or of a panel.
    static let mapCoveredCost: Double = 400_000
    /// What a square point of a backdrop costs: covering the whole of one
    /// (some 300 × 270 points) costs less than covering any control.
    static let backdropWeight = 0.01

    /// All in the screen's coordinates, as the app reads them.
    public init(
        target: Frame?, controls: [Frame], panels: [Frame] = [], backdrops: [Frame] = [], required: [Frame], map: Frame?,
        maxWidth: Double = 340
    ) {
        self.target = target
        self.controls = controls
        self.panels = panels
        self.backdrops = backdrops
        self.required = required
        self.map = map
        self.maxWidth = maxWidth
    }

    /// The card's frame in `bounds`, which may have its origin elsewhere
    /// than the screen's coordinates (a layout's bounds), given how it
    /// measures: its size for a proposed size.
    public func frame(in bounds: Frame, measure: (Size) -> Size) -> Frame {
        let margin = Self.margin
        let available = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        let width = min(maxWidth, available.width)
        var size = measure(Size(width: width, height: available.height))
        var best = placement(of: size, in: bounds, available: available)
        // With large text a card can be too tall to leave the map, or the
        // step's controls, free anywhere: measure it shorter, so its
        // explanation scrolls, and place it again if that does better.
        let free = map.map { max(Self.minimumCardHeight, $0.height - Self.minimumFreeMap - Self.gap) }
        if best.cost >= Self.mapCoveredCost, let free, free < size.height {
            let shorter = measure(Size(width: width, height: free))
            let retry = placement(of: shorter, in: bounds, available: available)
            if retry.cost < best.cost {
                size = shorter
                best = retry
            }
        }
        // A phone on its side (decision 106): the map between the status
        // pill, the dock and the details card is wide but short, and a card
        // of the full width can cover all of it. Narrower, 20 points at a
        // time, until a band of the map stays free beside it; tall, or
        // measured shorter as above.
        if best.cost >= Self.mapCoveredCost, let free {
            let heights = [available.height, free]
            var narrow = width - 20
            while narrow >= Self.minimumCardWidth, best.cost >= Self.mapCoveredCost {
                for height in heights {
                    let narrower = measure(Size(width: narrow, height: height))
                    let retry = placement(of: narrower, in: bounds, available: available)
                    if retry.cost < best.cost {
                        size = narrower
                        best = retry
                    }
                }
                narrow -= 20
            }
        }
        return Frame(x: best.origin.x, y: best.origin.y, width: size.width, height: size.height)
    }

    /// Whether a card at `frame`, in the screen's coordinates, leaves the
    /// step's own controls and the panels uncovered and a band of the map
    /// free to tap.
    public func leavesStepFree(_ frame: Frame) -> Bool {
        !(required + panels).contains { $0.intersects(frame) } && Self.leavesMapFree(frame, map: map)
    }

    /// Whether a band of `map` at least ``minimumFreeMap`` deep stays free
    /// above, below or beside `frame`.
    static func leavesMapFree(_ frame: Frame, map: Frame?) -> Bool {
        guard let map, frame.intersects(map) else { return true }
        let bands = [frame.minY - map.minY, map.maxY - frame.maxY, frame.minX - map.minX, map.maxX - frame.maxX]
        return (bands.max() ?? 0) >= minimumFreeMap
    }

    /// A top-leading corner.
    private struct Point {
        let x: Double
        let y: Double
    }

    /// Where a card of `size` goes, and what it costs there.
    private func placement(of size: Size, in bounds: Frame, available: Frame) -> (origin: Point, cost: Double) {
        let centred = Point(x: available.midX - size.width / 2, y: available.midY - size.height / 2)
        // The frames are in the screen's coordinates. A layout's bounds can
        // have a nonzero origin, so put them in that same coordinate space
        // before comparing candidates.
        guard let target = target?.offsetBy(dx: bounds.minX, dy: bounds.minY) else { return (centred, 0) }
        let obstacles = controls.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        let required = (self.required + panels).map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        let backdrops = self.backdrops.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        let map = self.map?.offsetBy(dx: bounds.minX, dy: bounds.minY)
        let gap = Self.gap
        let x = max(available.minX, min(target.midX - size.width / 2, available.maxX - size.width))
        let y = max(available.minY, min(target.midY - size.height / 2, available.maxY - size.height))
        var candidates = [
            Point(x: x, y: target.maxY + gap),
            Point(x: x, y: target.minY - gap - size.height),
            Point(x: target.maxX + gap, y: y),
            Point(x: target.minX - gap - size.width, y: y),
        ]
        // A step that has the player tap the map (its target is the map):
        // first the map's top trailing corner, below the status pill and
        // above the zoom buttons. Along the map's bottom, as below, the card
        // stood over the middle of a phone's map, where the camera opens on
        // the town to build in (TestFlight 54.1).
        if let map, target == map {
            candidates.append(Point(x: min(map.maxX - gap - size.width, available.maxX - size.width), y: map.minY + gap))
        }
        candidates += [
            // Inside a target as large as the map, along its bottom or
            // top: the rest of it stays free to tap.
            Point(x: x, y: target.maxY - gap - size.height),
            Point(x: x, y: target.minY + gap),
        ]
        // The free map's corners: beside every control, where a card that
        // fits covers none of them.
        if let map {
            candidates += [
                Point(x: map.minX + gap, y: map.minY + gap),
                Point(x: map.maxX - gap - size.width, y: map.minY + gap),
                Point(x: map.minX + gap, y: map.maxY - gap - size.height),
                Point(x: map.maxX - gap - size.width, y: map.maxY - gap - size.height),
            ]
        }
        candidates += [
            centred,
            Point(x: available.minX, y: centred.y),
            Point(x: available.maxX - size.width, y: centred.y),
            Point(x: centred.x, y: available.minY),
            Point(x: centred.x, y: available.maxY - size.height),
            Point(x: available.minX, y: available.minY),
            Point(x: available.maxX - size.width, y: available.minY),
            Point(x: available.minX, y: available.maxY - size.height),
            Point(x: available.maxX - size.width, y: available.maxY - size.height),
        ]
        func covered(_ rects: [Frame], by frame: Frame) -> Double {
            rects.reduce(0) { $0 + $1.overlap(with: frame) }
        }
        func cost(_ frame: Frame) -> Double {
            covered(required, by: frame) * 1_000 + covered(obstacles, by: frame)
                + covered(backdrops, by: frame) * Self.backdropWeight
                + (Self.leavesMapFree(frame, map: map) ? 0 : Self.mapCoveredCost)
        }
        // `min` keeps the first of equals, so the first placement that
        // covers nothing wins, as the order above intends.
        let cheapest = candidates
            .map { Frame(x: $0.x, y: $0.y, width: size.width, height: size.height) }
            .filter { available.contains($0) }
            .min { cost($0) < cost($1) }
        guard let cheapest else { return (centred, .infinity) }
        return (Point(x: cheapest.x, y: cheapest.y), cost(cheapest))
    }
}
