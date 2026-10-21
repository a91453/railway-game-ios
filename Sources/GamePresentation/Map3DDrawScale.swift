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

    /// The pixels a point to draw on a screen of `display`, once lowered or
    /// not: never more than the screen has.
    public static func scale(display: Double, lowered isLowered: Bool) -> Double {
        isLowered ? min(display, lowered) : display
    }

    /// Whether `gpuMilliseconds`, measured `windows` half seconds in a row
    /// over the budget of a frame at `aim` frames a second, says to draw
    /// fewer pixels.
    public static func isOver(gpuMilliseconds: Double, aim: Double) -> Bool {
        aim > 0 && gpuMilliseconds > 1_000 / aim * budget
    }

    public static func shouldLower(windows: Int) -> Bool { windows >= 3 }
}
