// 2026-10-21 (decision 238's later note): how many pixels a point the 3D
// map draws. The owner's iPhone 17 Pro spent 10–12 ms of GPU a frame on
// Taipei: on a 3× screen with four samples a pixel, the GPU shades every
// one of 3 × 3 pixels a point. A device whose GPU keeps over its budget
// draws two by two instead (0.44 of the pixels); one that keeps within it
// keeps its screen's own, the sharper window grids.

/// When the 3D map draws fewer pixels than the screen has.
public enum Map3DDrawScale {
    /// The fewest pixels a point it lowers to, two by two.
    public static let lowered: Double = 2

    /// The share of a frame's time the GPU may take before it counts as
    /// over: 10 ms of a 60 Hz frame's 16.7.
    public static let budget = 0.6

    /// Decision 460: the most pixels a lowered map draws, whatever its
    /// screen: an iPhone Pro Max's two by two (440 × 956 points), so every
    /// iPhone lowers as before, and an iPad, whose screen is 2× already
    /// and drew as many pixels lowered as not, now draws fewer (12.9-inch:
    /// 1.1 pixels a point; 11-inch Air: 1.3).
    public static let mostLoweredPixels: Double = 1_700_000

    /// The pixels a point to draw on a screen of `display` showing
    /// `points` square points (0: not known), once lowered or not: never
    /// more than the screen has, and lowered to ``mostLoweredPixels`` at
    /// most (after the reference's `tw3d` `main.js`, which caps its pixel
    /// ratio by the window's area), but no fewer than one a point.
    public static func scale(display: Double, lowered isLowered: Bool, points: Double = 0) -> Double {
        guard isLowered else { return display }
        let byArea = points > 0 ? max(1, (mostLoweredPixels / points).squareRoot()) : lowered
        return min(display, lowered, byArea)
    }

    /// Whether `gpuMilliseconds`, measured over a frame at `aim` frames a
    /// second, is over the budget (decision 417: a half second's load,
    /// ``Map3DLoadGovernor/Sample/isHeavy``).
    public static func isOver(gpuMilliseconds: Double, aim: Double) -> Bool {
        aim > 0 && gpuMilliseconds > 1_000 / aim * budget
    }
}
