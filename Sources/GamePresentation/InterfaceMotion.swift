import Foundation

/// Decision 253: how the interface moves, in one place. Each kind of
/// motion has one rule (how long, which curve, whether it moves or only
/// fades), and Reduce Motion has one answer for all of them: nothing
/// slides, scales, springs or shakes; what fades still fades, in half the
/// time or less; what only moved happens at once. Before, each view chose
/// its own (0.2 s here, a spring with half a bounce there), and the status
/// banner bumped even with Reduce Motion on.
///
/// The durations and curves follow LottieFiles' motion-design skill
/// (MIT, `.claude/skills/motion/`): what comes in decelerates and takes
/// longer than what goes, which accelerates; a small thing pops with a
/// little overshoot, a card or panel none; a refusal shakes sideways a few
/// times, smaller each time, and ends where it began. The app turns a rule
/// into a SwiftUI animation (`Theme.swift`).
public struct MotionRule: Hashable, Sendable {
    /// How the motion runs from start to end.
    public enum Curve: Hashable, Sendable {
        /// Fast at first, landing gently: something coming in.
        case decelerate
        /// Gentle at first, leaving fast: something going away.
        case accelerate
        /// Smooth at both ends: something changing where it is.
        case standard
        /// A spring that passes its mark by `bounce` (0 to 1) and settles.
        case spring(bounce: Double)
    }

    /// How long it takes, in seconds.
    public let seconds: Double
    public let curve: Curve
    /// Whether it slides, scales or shakes something.
    public let moves: Bool
    /// Whether it fades something in or out.
    public let fades: Bool

    public init(seconds: Double, curve: Curve, moves: Bool, fades: Bool) {
        self.seconds = seconds
        self.curve = curve
        self.moves = moves
        self.fades = fades
    }

    /// The rule with Reduce Motion on: only its fade, in half the time,
    /// without a spring; `nil` (happens at once) when it only moved.
    public var reduced: MotionRule? {
        guard fades else { return nil }
        return MotionRule(seconds: seconds / 2, curve: .decelerate, moves: false, fades: true)
    }

    /// The rule as it runs: ``reduced`` with Reduce Motion on.
    public func running(reduceMotion: Bool) -> MotionRule? {
        reduceMotion ? reduced : self
    }
}

extension MotionRule {
    /// A button pressed down or let go.
    public static let press = MotionRule(seconds: 0.15, curve: .decelerate, moves: true, fades: true)
    /// Something changing where it is: a fold, a fade, a layout giving
    /// room to a card or panel.
    public static let change = MotionRule(seconds: 0.2, curve: .standard, moves: true, fades: true)
    /// A card or panel coming in from the edge it stands at (the details
    /// card, a panel beside the map, the follow bar).
    public static let cardIn = MotionRule(seconds: 0.28, curve: .decelerate, moves: true, fades: true)
    /// The same card or panel going: shorter, as the player looks away.
    public static let cardOut = MotionRule(seconds: 0.2, curve: .accelerate, moves: true, fades: true)
    /// A small thing that pops up where the finger is: the station's tag,
    /// the ✓ ✕ beside what is being built, the tutorial card opening or
    /// folding.
    public static let pop = MotionRule(seconds: 0.25, curve: .spring(bounce: 0.2), moves: true, fades: true)
    /// A message that went well, bumped as it comes (the status banner).
    public static let confirm = MotionRule(seconds: 0.25, curve: .spring(bounce: 0.2), moves: true, fades: false)
    /// A refusal: the status banner shakes (``RefusalShake``).
    public static let refuse = MotionRule(seconds: 0.36, curve: .standard, moves: true, fades: false)
    /// The ring that spreads where something was put up (decision 117).
    public static let builtRing = MotionRule(seconds: 0.9, curve: .decelerate, moves: true, fades: true)

    /// The 3D map turning back to north when its compass is tapped
    /// (decision 269, later): 240 ms, decelerating, as the reference's map
    /// does (`resetMapNorth` in `main-reference.js`). It only moves, so
    /// with Reduce Motion the map faces north at once.
    public static let turnNorth = MotionRule(seconds: 0.24, curve: .decelerate, moves: true, fades: false)

    /// Decision 333: the 3D map's camera flying to a train it starts to
    /// follow (and decision 334, to a train at its platform): 1.2 s,
    /// smooth at both ends, as the reference's map animates its camera
    /// (`cameraMotion` in `rail-3d/integration/camera-motion.js`,
    /// ``Map3DFlight``). A camera, not a card: longer than a card, as a
    /// whole view moves. It only moves, so with Reduce Motion the camera
    /// is there at once.
    public static let cameraFlight = MotionRule(seconds: 1.2, curve: .standard, moves: true, fades: false)

    /// The loading screen of a real-world map fading in (decision 307):
    /// 0.7 s, decelerating, as the geographic dashboard's boot screen does
    /// (`boot-fade-in`, geo-scene `bootScreen.css`). It only fades.
    public static let loadingIn = MotionRule(seconds: 0.7, curve: .decelerate, moves: false, fades: true)
    /// The same screen fading away over the game once it is ready: 0.45 s,
    /// the boot screen's `fadeMs`, leaving fast.
    public static let loadingOut = MotionRule(seconds: 0.45, curve: .accelerate, moves: false, fades: true)

    /// Decision 414: the idle mode cutting from one shot to the next
    /// through a dark veil, each way: 0.7 s, smooth at both ends, as the
    /// owner's rail site's `#veil` (`transition: opacity .7s ease`,
    /// `fadeSwitch`). It only fades, so with Reduce Motion it still fades,
    /// in half the time.
    public static let ambientCut = MotionRule(seconds: 0.7, curve: .standard, moves: false, fades: true)

    /// Every rule, for the tests.
    public static let all: [MotionRule] = [.press, .change, .cardIn, .cardOut, .pop, .confirm, .refuse, .builtRing, .turnNorth, .cameraFlight, .loadingIn, .loadingOut, .ambientCut]
}

/// Decision 253: a refusal shakes sideways three times, each smaller,
/// and ends where it began, without passing its mark at the end. Firm,
/// not playful: no spring.
public enum RefusalShake {
    /// The first swing, in points.
    public static let amplitude = 6.0
    /// How many times it swings back and forth.
    public static let swings = 3

    /// The sideways offset, in points, `progress` (0 to 1) of the way
    /// through.
    public static func offset(at progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return amplitude * (1 - t) * sin(2 * Double.pi * Double(swings) * t)
    }
}
