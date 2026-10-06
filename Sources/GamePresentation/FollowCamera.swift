import Foundation
import GameCore

/// Where the camera looks while it follows a train: the `Ci/` reference's
/// `_trackCenterLng`/`_trackCenterLat` in `_setPosAndAngle`, ported:
///
///     if (center == null || |lng − center.lng| > 0.05 || |lat − center.lat| > 0.05)
///         center = train                       // snap
///     else
///         s = 1 − 0.75 ^ (min(dt, 0.1) × 60)   // ease
///         center += (train − center) × s
///
/// The reference measures in degrees; here the world is in world units, so
/// its 0.05° becomes 0.05 × 111,320 m (one degree of latitude) on either
/// axis, ``snapDistance``. Only view state: the map view keeps one, and
/// nothing here touches the world. The elapsed time is passed in, so the
/// same steps always give the same centres (the map view passes the game
/// loop's tick interval, the time between two worlds it is shown).
public struct FollowCamera: Equatable, Sendable {
    /// The reference's 0.05° snap threshold, per axis, in world units
    /// (0.05 × 111,320 m × 64 units a metre = 356,224).
    public static let snapDistance = 0.05 * 111_320 * Double(WorldCoordinate.unitsPerMetre)

    /// The reference caps a frame's time at 0.1 s before easing.
    public static let maximumElapsed = 0.1

    /// The real time between two worlds the game loop shows, in seconds
    /// (``GameSession/tickInterval``): what the map view passes for each
    /// step, so the easing is the same on every device.
    public static var tickSeconds: Double {
        let parts = GameSession.tickInterval.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// The part of the way to the train the camera moves in `elapsed`
    /// seconds: `1 − 0.75^(min(dt, 0.1) × 60)`. A tenth of a second (one
    /// tick) moves it about 82 % of the way.
    public static func easing(elapsed seconds: Double) -> Double {
        let dt = min(max(seconds.isFinite ? seconds : 0, 0), maximumElapsed)
        return 1 - pow(0.75, dt * 60)
    }

    /// The centre the camera looks at, or `nil` before the first step
    /// (the next step then snaps to the train).
    public private(set) var centerX: Double?
    public private(set) var centerY: Double?

    public init() {}

    /// One step towards the train at (`x`, `y`) after `elapsed` seconds:
    /// snaps when there is no centre yet or the train is more than
    /// ``snapDistance`` away on either axis, otherwise eases. Returns the
    /// new centre.
    @discardableResult
    public mutating func step(towardX x: Double, y: Double, elapsed seconds: Double) -> (x: Double, y: Double) {
        if let cx = centerX, let cy = centerY, abs(x - cx) <= Self.snapDistance, abs(y - cy) <= Self.snapDistance {
            let s = Self.easing(elapsed: seconds)
            centerX = cx + (x - cx) * s
            centerY = cy + (y - cy) * s
        } else {
            centerX = x
            centerY = y
        }
        return (centerX ?? x, centerY ?? y)
    }

    /// Forgets the centre (the reference sets it to `null` whenever follow
    /// stops), so the next follow snaps to its train.
    public mutating func reset() {
        centerX = nil
        centerY = nil
    }
}
