import Foundation

// Where the tutorial's card goes (Stage C5): the app measures the card and
// the controls on screen, this chooses. It lived in the app's layout until
// a phone on its side (decision 106) put the card over the lines panel at
// the line step, where nothing could be tapped and Next never came: here,
// it is tested off Apple's platforms on that screen too.

/// Where the tutorial's card goes: beside the step's first target on
/// screen, clear of every control and panel, leaving the step's own
/// controls and a band of the map free to tap.
///
/// Tries below and above the target, then its sides, then inside a large
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
    /// The first of the step's targets on screen, which the card goes
    /// beside; `nil` puts it in the middle.
    public var target: CGRect?
    /// Every control and panel on screen but the map, which can be tapped
    /// outside the card.
    public var controls: [CGRect]
    /// The step's own controls (not the map), among `controls`.
    public var required: [CGRect]
    /// The part of the map that shows (``TutorialTarget/map``).
    public var map: CGRect?
    /// The widest the card is laid out.
    public var maxWidth: CGFloat

    /// The card's distance from the screen's edges.
    static let margin: CGFloat = 16
    /// Its distance from its target.
    static let gap: CGFloat = 12
    /// The depth of the band of the map left free beside the card.
    public static let minimumFreeMap: CGFloat = 96
    /// The shortest a card is measured to leave the map free: the step's
    /// title, a few lines of its explanation and its buttons.
    static let minimumCardHeight: CGFloat = 200
    /// The narrowest a card is measured to leave a band of the map free
    /// beside it.
    static let minimumCardWidth: CGFloat = 240
    /// Above covering any ordinary control or panel with the whole card,
    /// below covering a sliver of the step's own controls.
    static let mapCoveredCost: CGFloat = 400_000

    /// All in the screen's coordinates, as the app reads them.
    public init(target: CGRect?, controls: [CGRect], required: [CGRect], map: CGRect?, maxWidth: CGFloat = 340) {
        self.target = target
        self.controls = controls
        self.required = required
        self.map = map
        self.maxWidth = maxWidth
    }

    /// The card's frame in `bounds`, which may have its origin elsewhere
    /// than the screen's coordinates (a layout's bounds), given how it
    /// measures: its size for a proposed size.
    public func frame(in bounds: CGRect, measure: (CGSize) -> CGSize) -> CGRect {
        let margin = Self.margin
        let available = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        let width = min(maxWidth, available.width)
        var size = measure(CGSize(width: width, height: available.height))
        var best = placement(of: size, in: bounds, available: available)
        // With large text a card can be too tall to leave the map, or the
        // step's controls, free anywhere: measure it shorter, so its
        // explanation scrolls, and place it again if that does better.
        let free = map.map { max(Self.minimumCardHeight, $0.height - Self.minimumFreeMap - Self.gap) }
        if best.cost >= Self.mapCoveredCost, let free, free < size.height {
            let shorter = measure(CGSize(width: width, height: free))
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
                    let narrower = measure(CGSize(width: narrow, height: height))
                    let retry = placement(of: narrower, in: bounds, available: available)
                    if retry.cost < best.cost {
                        size = narrower
                        best = retry
                    }
                }
                narrow -= 20
            }
        }
        return CGRect(origin: best.origin, size: size)
    }

    /// Whether a card at `frame`, in the screen's coordinates, leaves the
    /// step's own controls uncovered and a band of the map free to tap.
    public func leavesStepFree(_ frame: CGRect) -> Bool {
        !required.contains { $0.intersects(frame) } && Self.leavesMapFree(frame, map: map)
    }

    /// Whether a band of `map` at least ``minimumFreeMap`` deep stays free
    /// above, below or beside `frame`.
    static func leavesMapFree(_ frame: CGRect, map: CGRect?) -> Bool {
        guard let map, frame.intersects(map) else { return true }
        let bands = [frame.minY - map.minY, map.maxY - frame.maxY, frame.minX - map.minX, map.maxX - frame.maxX]
        return (bands.max() ?? 0) >= minimumFreeMap
    }

    /// Where a card of `size` goes, and what it costs there.
    private func placement(of size: CGSize, in bounds: CGRect, available: CGRect) -> (origin: CGPoint, cost: CGFloat) {
        let centred = CGPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2)
        // The frames are in the screen's coordinates. A layout's bounds can
        // have a nonzero origin, so put them in that same coordinate space
        // before comparing candidates.
        guard let target = target?.offsetBy(dx: bounds.minX, dy: bounds.minY) else { return (centred, 0) }
        let obstacles = controls.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        let required = self.required.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        let map = self.map?.offsetBy(dx: bounds.minX, dy: bounds.minY)
        let gap = Self.gap
        let x = max(available.minX, min(target.midX - size.width / 2, available.maxX - size.width))
        let y = max(available.minY, min(target.midY - size.height / 2, available.maxY - size.height))
        var candidates = [
            CGPoint(x: x, y: target.maxY + gap),
            CGPoint(x: x, y: target.minY - gap - size.height),
            CGPoint(x: target.maxX + gap, y: y),
            CGPoint(x: target.minX - gap - size.width, y: y),
            // Inside a target as large as the map, along its bottom or
            // top: the rest of it stays free to tap.
            CGPoint(x: x, y: target.maxY - gap - size.height),
            CGPoint(x: x, y: target.minY + gap),
        ]
        // The free map's corners: beside every control, where a card that
        // fits covers none of them.
        if let map {
            candidates += [
                CGPoint(x: map.minX + gap, y: map.minY + gap),
                CGPoint(x: map.maxX - gap - size.width, y: map.minY + gap),
                CGPoint(x: map.minX + gap, y: map.maxY - gap - size.height),
                CGPoint(x: map.maxX - gap - size.width, y: map.maxY - gap - size.height),
            ]
        }
        candidates += [
            centred,
            CGPoint(x: available.minX, y: centred.y),
            CGPoint(x: available.maxX - size.width, y: centred.y),
            CGPoint(x: centred.x, y: available.minY),
            CGPoint(x: centred.x, y: available.maxY - size.height),
            CGPoint(x: available.minX, y: available.minY),
            CGPoint(x: available.maxX - size.width, y: available.minY),
            CGPoint(x: available.minX, y: available.maxY - size.height),
            CGPoint(x: available.maxX - size.width, y: available.maxY - size.height),
        ]
        func covered(_ rects: [CGRect], by frame: CGRect) -> CGFloat {
            rects.reduce(0) { sum, rect in
                let common = rect.intersection(frame)
                return common.isNull ? sum : sum + common.width * common.height
            }
        }
        func cost(_ frame: CGRect) -> CGFloat {
            covered(required, by: frame) * 1_000 + covered(obstacles, by: frame)
                + (Self.leavesMapFree(frame, map: map) ? 0 : Self.mapCoveredCost)
        }
        // `min` keeps the first of equals, so the first placement that
        // covers nothing wins, as the order above intends.
        let cheapest = candidates
            .map { CGRect(origin: $0, size: size) }
            .filter { available.contains($0) }
            .min { cost($0) < cost($1) }
        guard let cheapest else { return (centred, .infinity) }
        return (cheapest.origin, cost(cheapest))
    }
}
