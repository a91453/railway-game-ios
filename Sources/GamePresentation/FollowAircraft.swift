import Foundation
import GameCore

// Decision 702 (FOLLOW-AIR, 2026-11-12): the 3D map's camera following an
// aircraft that lands, leaves or taxis, after following a ferry boat
// (decision 585 PR-4, `FollowFerry.swift`) and a cable car cabin (decision
// 583). Aircraft are not GameCore things, nor the session's: where each is
// follows from the airfields laid in the scene, the day's flights and the
// clock (``Map3DAircraft/Laid``), which only the 3D map has. So the session
// keeps the flight's ID (``Map3DAircraft/FlightID``) and what the 3D map
// last told it of the aircraft (``GameSession/noteFollowedAircraft(_:)``),
// and lets go when the 3D map says it can no longer be followed.
// Presentation only: nothing here changes the world, the save or a golden
// value.

extension Map3DAircraft {
    /// An aircraft the camera can follow: its flight, how it is drawn,
    /// and the game's airport it lands at or leaves (its place in
    /// ``GameWorld/airports``).
    public struct Followed: Sendable {
        public let flight: FlightID
        public let drawn: Drawn
        public let airport: Int?

        /// What the bar reads of it; the same while nothing it shows
        /// changes.
        public var state: State {
            State(flight: flight, kind: drawn.kind, phase: drawn.phase ?? .parked, airport: airport)
        }
    }

    /// What the follow bar shows of an aircraft followed.
    public struct State: Hashable, Sendable {
        public let flight: FlightID
        public let kind: Kind
        public let phase: Phase
        public let airport: Int?

        public init(flight: FlightID, kind: Kind, phase: Phase, airport: Int?) {
            self.flight = flight
            self.kind = kind
            self.phase = phase
            self.airport = airport
        }
    }

    /// How far out a leaving aircraft is followed, metres from where it
    /// left the ground: as far as an aircraft is drawn from the eye
    /// (``farReach``), so the camera that stays behind sees it go until it
    /// is no longer drawn.
    public static let followedOut = Double(farReach)

    /// Whether the camera follows an aircraft drawn as `drawn`: one of a
    /// flight, moving (landing, on the runway, taxiing, pushed back), and
    /// climbing away no higher than ``followedOut`` out takes it. Not one
    /// standing at its stand.
    public static func canFollow(_ drawn: Drawn) -> Bool {
        guard drawn.flight != nil, drawn.flying, let phase = drawn.phase else { return false }
        return phase != .climb || Double(drawn.height) < followedOut * climb
    }

    /// Where `aircraft` is and which way it faces, as the follow camera
    /// reads it: the camera looks at the middle of its body; its window
    /// seat is on the left, ahead of the wing of a jet and of the
    /// propellers of the others, at its cabin windows' height.
    public static func pose(of aircraft: Drawn) -> Map3DFollow.Pose {
        let size = Map3DAircraftStudies.dimensions(aircraft.kind), shape = Map3DAircraftStudies.shape(aircraft.kind)
        let (origin, x, y, z) = axes(of: aircraft)
        func at(_ behindNose: Float, _ left: Float, _ up: Float) -> Map3DPoint {
            origin + x * (size.length / 2 - behindNose) + y * left + z * up
        }
        let middle = at(size.length / 2, 0, shape.centre)
        // The seat: by a window (the cabin's band, in half-heights over
        // the body's middle line), just outside the body's side there.
        let over = shape.halfHeight * (shape.cabin.low + shape.cabin.high) / 2
        // A jet's seat is just ahead of its wing, which fills the view's
        // rear; a propeller aircraft's wing is over the cabin, so its seat
        // is behind the wing, clear of the propeller's blades.
        let behind = Map3DAircraftStudies.isJet(aircraft.kind) ? shape.wing[0].s - 1.5 : shape.wing[0].s + shape.wing[0].chord + 1.2
        let seat = at(min(max(shape.cabin.from, behind), shape.cabin.to), shape.sideY(over) + 0.12, shape.centre + over) - middle
        let forward = aircraft.forward
        let left = Map3DPoint(forward.z, 0, -forward.x)
        return Map3DFollow.Pose(forward: forward, nose: at(0, 0, shape.centre), rail: middle,
                                middle: middle - Map3DPoint(0, shape.centre, 0), length: sideLength(size.length), ground: nil, inTunnel: false,
                                bodyHeight: 2 * shape.centre,
                                window: .init(across: seat.dot(left), height: seat.y + shape.centre, lookDown: windowLookDown, ahead: seat.dot(forward)))
    }

    /// The length the view from beside an aircraft `length` metres long
    /// stands off for (``Map3DFollow/sideScale(length:viewport:)``): its
    /// own and a fifth more, and no less than the reference's one car;
    /// over ``Map3DFollow/aircraftScale(length:)``, which the camera's
    /// distance from a small aircraft is already less by.
    static func sideLength(_ length: Float) -> Float {
        max(Map3DFollow.sideTrainLength, length) * 1.2 / Map3DFollow.aircraftScale(length: length)
    }

    /// The window view looks a little down, at the ground going by.
    public static let windowLookDown: Float = 6 * .pi / 180

    // MARK: - Lamps

    /// The lamps of a moving `aircraft` at night, as glows in the scene:
    /// the red lamp on its left wing tip, the green on its right, the
    /// white on its tail; a red beacon over and under its body that
    /// flashes once a second; white strobes on its wing tips that flash
    /// twice; and on the runway and in the air its landing lights, at its
    /// nose wheel and its wing roots (taxiing, only the one at its nose
    /// wheel, dimmer). `blink` is the clock the flashes go by, seconds;
    /// `nil` (Reduce Motion: nothing flashes by itself) leaves the beacon
    /// lit and the strobes off. None for one standing at its stand.
    public static func lamps(of aircraft: Drawn, blink: Double?) -> [Map3DGlow.Spot] {
        guard aircraft.flying, let phase = aircraft.phase, phase != .parked else { return [] }
        let size = Map3DAircraftStudies.dimensions(aircraft.kind), shape = Map3DAircraftStudies.shape(aircraft.kind)
        let (origin, x, y, z) = axes(of: aircraft)
        func at(_ behindNose: Float, _ left: Float, _ up: Float) -> Map3DPoint {
            origin + x * (size.length / 2 - behindNose) + y * left + z * up
        }
        // Bigger aircraft carry bigger lamps: a wide-bodied jet's twice a
        // nineteen-seater's.
        let scale = 0.8 + size.length / 55
        func spot(_ centre: Map3DPoint, _ radius: Float, _ colour: (Float, Float, Float), _ strength: Float = 1) -> Map3DGlow.Spot {
            Map3DGlow.Spot(centre: centre, radius: radius * scale, red: colour.0, green: colour.1, blue: colour.2, strength: strength)
        }
        let tip: (s: Float, y: Float, z: Float) = shape.winglet.last.map { ($0.s, $0.y, $0.z) } ?? shape.wing.last.map { ($0.s, $0.y, $0.z) } ?? (0, 0, 0)
        let top = shape.centre + shape.halfHeight
        var spots = [
            spot(at(tip.s, tip.y, tip.z), 0.8, navigationRed),
            spot(at(tip.s, -tip.y, tip.z), 0.8, navigationGreen),
            spot(at(size.length, 0, shape.centre + shape.halfHeight * (shape.hull.last?.top ?? 0)), 0.7, lampWhite, 0.8),
        ]
        // Each flight's flashes start at its own moment.
        let offset = Double((aircraft.flight?.index ?? 0) * 37 % 100) / 100 + Double(aircraft.livery) * 0.13
        let beat = blink.map { ($0 + offset).truncatingRemainder(dividingBy: beaconEvery) }
        if beat.map({ $0 < flash }) ?? true {
            spots.append(spot(at(size.length * 0.42, 0, top + 0.2), 1.3, navigationRed))
            spots.append(spot(at(size.length * 0.46, 0, shape.centre - shape.halfHeight - 0.15), 1.3, navigationRed))
        }
        // The strobes: two short flashes, off the ground and on the runway.
        if let beat, phase.landingLights, beat > 0.5, beat < 0.5 + flash / 2 || (beat > 0.5 + flash && beat < 0.5 + flash * 1.5) {
            spots.append(spot(at(tip.s, tip.y, tip.z), 1.8, lampWhite))
            spots.append(spot(at(tip.s, -tip.y, tip.z), 1.8, lampWhite))
        }
        let nose = at(shape.noseGear.s - 0.6, 0, shape.centre - shape.halfHeight * 0.75)
        if phase.landingLights {
            spots.append(spot(nose, 2.6, lampWhite))
            for side: Float in [-1, 1] {
                spots.append(spot(at(shape.wing[0].s - 0.3, side * (shape.halfWidth + 0.9), shape.wing[0].z), 2.2, lampWhite))
            }
        } else {
            spots.append(spot(nose, 1.5, lampWhite, 0.7))
        }
        return spots
    }

    /// The lamps' colours and the strobes' flash (half of ``flash``, 0.08 s)
    /// are the owner's Taiwan 3D city reference's jet's
    /// (`tw3d-reference-clean/source/js/controllers.js`: port 0xff2b2b,
    /// starboard 0x22ff66, a white strobe lit 0.08 s); the beacon, the
    /// landing lights and where each lamp sits on the four types are this
    /// project's own.
    static let navigationRed: (Float, Float, Float) = (1, Float(0x2B) / 255, Float(0x2B) / 255)
    static let navigationGreen: (Float, Float, Float) = (Float(0x22) / 255, 1, Float(0x66) / 255)
    static let lampWhite: (Float, Float, Float) = (1, 0.97, 0.9)
    /// The beacon flashes once in this long, for this long, seconds.
    static let beaconEvery = 1.1
    static let flash = 0.16
}

extension Map3DAircraft.Laid {
    /// Decision 702: flight `id`'s aircraft at game second `second` while
    /// the camera can follow it (``Map3DAircraft/canFollow(_:)``) and it
    /// is over the map; `nil` once it stands at its stand, has climbed
    /// away, has gone, is past the map's edge, or with `still` (Reduce
    /// Motion: none moves).
    public func followed(_ id: Map3DAircraft.FlightID, second: Double, traffic: Map3DAircraft.Traffic?, still: Bool = false) -> Map3DAircraft.Followed? {
        guard let drawn = aircraft(of: id, second: second, traffic: traffic, still: still), Map3DAircraft.canFollow(drawn), isOverMap(drawn.ground)
        else { return nil }
        return Map3DAircraft.Followed(flight: id, drawn: drawn, airport: airport(of: id))
    }

    func isOverMap(_ point: Map3DPoint) -> Bool {
        guard let edges else { return true }
        return edges.x.contains(point.x) && edges.z.contains(point.z)
    }

    /// Decision 702: the aircraft that can be followed drawn nearest the
    /// finger at (`x`, `y`) in `camera`'s view, within `reach` points (a
    /// near one's body is wider than that: within its length on the
    /// screen too), at `second`; only those drawn (``Map3DAircraft/farReach``
    /// of the eye).
    public func followable(atX x: Float, y: Float, camera: Map3DCamera, second: Double, traffic: Map3DAircraft.Traffic?, still: Bool = false,
                           within reach: Float) -> Map3DAircraft.Followed? {
        guard !still, traffic != nil else { return nil }
        var best: (away: Float, drawn: Map3DAircraft.Drawn)?
        let eye = camera.eye
        for drawn in aircraft(second: second, traffic: traffic, still: still) where Map3DAircraft.canFollow(drawn) && isOverMap(drawn.ground) {
            let pose = Map3DAircraft.pose(of: drawn)
            guard (pose.rail - eye).length < Map3DAircraft.farReach, let screen = camera.screenPoint(of: pose.rail) else { continue }
            var wide = reach
            if let nose = camera.screenPoint(of: pose.nose) {
                wide = max(reach, ((nose.x - screen.x) * (nose.x - screen.x) + (nose.y - screen.y) * (nose.y - screen.y)).squareRoot())
            }
            let away = ((screen.x - x) * (screen.x - x) + (screen.y - y) * (screen.y - y)).squareRoot()
            if away <= wide, best.map({ away < $0.away }) ?? true { best = (away, drawn) }
        }
        guard let drawn = best?.drawn, let flight = drawn.flight else { return nil }
        return Map3DAircraft.Followed(flight: flight, drawn: drawn, airport: airport(of: flight))
    }

    /// Decision 702: the aircraft that can be followed nearest `point`
    /// (level) at `second`, for a screenshot's camera.
    public func followable(nearest point: Map3DPoint, second: Double, traffic: Map3DAircraft.Traffic?) -> Map3DAircraft.Followed? {
        func away(_ drawn: Map3DAircraft.Drawn) -> Float { Map3DPoint(drawn.ground.x - point.x, 0, drawn.ground.z - point.z).length }
        let found = aircraft(second: second, traffic: traffic).filter { Map3DAircraft.canFollow($0) && isOverMap($0.ground) }
            .min { away($0) < away($1) }
        guard let found, let flight = found.flight else { return nil }
        return Map3DAircraft.Followed(flight: flight, drawn: found, airport: airport(of: flight))
    }
}

/// What the follow bar shows of the aircraft followed, read through
/// ``GameSession/aircraftFollowBar``.
public struct AircraftFollowFacts: Equatable, Sendable {
    public var state: Map3DAircraft.State
    /// "Narrow-body jet".
    public var name: String
    /// "Landing at Taipei Songshan Airport".
    public var directionText: String
    /// "On approach", "Taxiing to its stand".
    public var stopText: String
    public var runningSpeed: GameSpeed?
}

extension Map3DAircraft.Kind {
    /// The type's name on the follow bar: its size, no maker's or
    /// airline's name.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .commuter19: language.text("19-seat propeller plane", "十九座螺旋槳機")
        case .regional70: language.text("70-seat propeller plane", "七十座螺旋槳機")
        case .narrowJet: language.text("Narrow-body jet", "窄體客機")
        case .wideJet: language.text("Wide-body jet", "廣體客機")
        }
    }
}

extension Map3DAircraft.Phase {
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .approach: language.text("On approach", "進場中")
        case .landingRoll: language.text("Slowing down on the runway", "落地，在跑道上減速")
        case .taxiIn: language.text("Taxiing to its stand", "滑行到機位")
        case .parked: language.text("At its stand", "停在機位")
        case .pushBack: language.text("Pushing back from its stand", "從機位後推")
        case .taxiOut: language.text("Taxiing to the runway", "滑行到跑道")
        case .lineUp: language.text("Waiting to take off", "在跑道頭等待起飛")
        case .takeOffRoll: language.text("Taking off", "起飛滾行")
        case .climb: language.text("Climbing away", "爬升離場")
        }
    }
}

extension GameWorld {
    /// The text for the bar of an aircraft followed.
    func aircraftFollowFacts(of state: Map3DAircraft.State, in language: DisplayLanguage) -> AircraftFollowFacts {
        let airport = state.airport.flatMap { airports.indices.contains($0) ? airports[$0].title(in: language) : nil }
        let direction: String
        if let airport {
            direction = state.flight.landing ? language.text("Landing at \(airport)", "降落\(airport)") : language.text("Leaving \(airport)", "從\(airport)起飛")
        } else {
            direction = state.flight.landing ? language.text("Landing", "降落") : language.text("Leaving", "起飛")
        }
        return AircraftFollowFacts(state: state, name: state.kind.text(in: language), directionText: direction, stopText: state.phase.text(in: language),
                                   runningSpeed: clock.isPaused ? nil : clock.speed)
    }
}

extension Map3DFollow.View {
    /// Decision 702: the button's name on an aircraft's follow bar
    /// (``Map3DFollow/aircraftViews``).
    public func aircraftText(in language: DisplayLanguage) -> String {
        switch self {
        case .window: language.text("Window", "機艙窗")
        default: text(in: language)
        }
    }

    /// What an aircraft's button does, for VoiceOver.
    public func aircraftHint(in language: DisplayLanguage) -> String {
        switch self {
        case .window: language.text("Sits in the cabin and looks out of the window.", "坐在機艙裡看窗外。")
        case .side: language.text("Moves alongside the aircraft, showing all of it.", "在飛機旁邊一起移動，看得到整架飛機。")
        default: language.text("Follows the aircraft from behind.", "從飛機後方跟著看。")
        }
    }
}

extension GameSession {
    public var isFollowingAircraft: Bool { followedAircraftID != nil }

    /// Starts following the aircraft the 3D map found (a tap on it);
    /// never changes the world.
    public func followAircraft(_ state: Map3DAircraft.State) {
        followedTrainID = nil
        followedBusID = nil
        followedCabinID = nil
        followedFerryBoatID = nil
        followedAircraftID = state.flight
        aircraftFollowBar = world.aircraftFollowFacts(of: state, in: language)
        updateFollowSounds()
    }

    /// The 3D map tells what the aircraft followed is doing now, each
    /// time it changes; `nil` when it can no longer be followed (it
    /// stands at its stand, has climbed away, its flight is over, or
    /// Reduce Motion was turned on): it is let go, and the camera stays
    /// where it is. `flight` is the one the 3D map speaks of: another
    /// followed since is left alone.
    public func noteFollowedAircraft(_ state: Map3DAircraft.State?, of flight: Map3DAircraft.FlightID) {
        guard followedAircraftID == flight else { return }
        guard let state else {
            followedAircraftID = nil
            updateFollowSounds()
            return
        }
        let facts = world.aircraftFollowFacts(of: state, in: language)
        if facts != aircraftFollowBar { aircraftFollowBar = facts }
    }

    /// After a step: the bar's speed kept up to date.
    func keepFollowingAircraft() {
        guard followedAircraftID != nil, let state = aircraftFollowBar?.state else { return }
        let facts = world.aircraftFollowFacts(of: state, in: language)
        if facts != aircraftFollowBar { aircraftFollowBar = facts }
    }
}
