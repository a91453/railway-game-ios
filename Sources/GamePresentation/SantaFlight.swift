import Foundation
import GameCore

// Decision 831 (SANTA-FLIGHT): on Christmas Eve, from 18:00 on 24 December
// to 06:00 on 25 December by the device's own clock (the winter event's
// calendar, ``WinterEvent/calendar(in:)``; changing the device's date is
// not guarded against, decision 788), Santa Claus's reindeer sleigh flies
// over the 3D map of a real-world game, as NORAD has tracked it every
// Christmas Eve since 1955, from Rovaniemi Airport, which calls itself
// Santa Claus's official airport. On the Rovaniemi map it takes off from
// that airport's runway (21, OpenStreetMap's, the map pack's
// `airfields.json`); anywhere else it comes from Rovaniemi's way, the
// great circle's bearing, and goes on past.
//
// Each pass flies over the place the camera looked at when it began, so a
// player with the 3D map open sees it: one pass every ``every`` seconds of
// the player's clock, not the game's, which may be paused or running at
// sixty times. It is a picture only: nothing of the game's rules reads it,
// nothing is saved, no random number decides it; the same pass, place and
// moment give the same sleigh. The camera can follow it as it follows an
// aircraft (``Map3DAircraft/FlightID/santa``), and the sleigh's bells ring
// as it passes near (``Sound``). With Reduce Motion nothing flies by
// itself, so it does not fly; nor with the settings' "Festive decorations"
// off.
//
// The model is a stand-in (``Model``): the reindeer and the sleigh are
// the studio's to make (REINDEER, shared with Rovaniemi's reindeer on the
// ground), and their mesh takes this one's name when it comes.

public enum SantaFlight {
    // MARK: - When

    /// It flies from this hour on 24 December to this hour on 25 December.
    public static let firstHour = 18
    public static let lastHour = 6
    /// A pass begins every this many seconds of the night.
    public static let every: Double = 360

    /// The night `date` falls in, from 18:00 on 24 December to 06:00 on
    /// 25 December in `calendar`'s time zone; `nil` at any other time.
    public static func night(at date: Date, calendar: Calendar = WinterEvent.calendar()) -> (start: Date, end: Date)? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = parts.year, parts.month == 12, let day = parts.day, let hour = parts.hour,
              day == 24 && hour >= firstHour || day == 25 && hour < lastHour,
              let start = calendar.date(from: DateComponents(year: year, month: 12, day: 24, hour: firstHour)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 25, hour: lastHour))
        else { return nil }
        return (start, end)
    }

    /// Where the night stands at a moment: which pass (0 the first, at
    /// 18:00) and how many seconds into it.
    public struct Moment: Hashable, Sendable {
        public let pass: Int
        public let seconds: Double
    }

    /// The moment of the night at `date`; `nil` outside the night, and
    /// with `switchedOn` false (the settings' "Festive decorations").
    public static func moment(at date: Date, switchedOn: Bool = true, calendar: Calendar = WinterEvent.calendar()) -> Moment? {
        guard switchedOn, let night = night(at: date, calendar: calendar) else { return nil }
        let since = date.timeIntervalSince(night.start)
        let pass = Int((since / every).rounded(.down))
        return Moment(pass: pass, seconds: since - Double(pass) * every)
    }

    // MARK: - Where

    /// Rovaniemi Airport (RVN, EFRO): its runway's two ends as the 3D map's
    /// airfields have them (OpenStreetMap, the Rovaniemi pack's
    /// `airfields.json`), the north-east one first: the sleigh takes off
    /// on runway 21, south-west, towards the town and the world.
    public static let runway = (from: (latitude: 66.575540, longitude: 25.850844), to: (latitude: 66.554115, longitude: 25.810009))

    /// How fast it flies, m/s (some 140 km/h); how high over the ground
    /// where the pass is centred, and at the least over any ground under
    /// it, metres; how far before and past that place it is drawn, metres.
    public static let speed: Float = 40
    public static let cruise: Float = 250
    public static let clearance: Float = 120
    public static let reach: Float = 3_600
    /// Off the runway it climbs at 9°, as the aircraft do (``Map3DAircraft``).
    static let climb = Float(tan(9.0 * Double.pi / 180))
    /// From the runway it flies over a place this near only, metres: one
    /// farther takes it more than a pass's time to reach.
    static let farthestFromRunway: Float = 8_000
    /// Nearer the runway than this, it keeps to the runway's way.
    static let nearestFromRunway: Float = 1_000

    /// One pass's way through the scene: where it starts, the level way it
    /// flies, how far, and its height above `start` along it.
    public struct Track: Hashable, Sendable {
        /// Where it is first drawn, on the ground (or the runway) under it.
        public let start: Map3DPoint
        /// Level, a metre long.
        public let forward: Map3DPoint
        public let length: Float
        /// Its height over `start.y` when level.
        public let level: Float
        /// Whether it takes off from the runway at `start` (else it is at
        /// `level` all the way).
        public let fromRunway: Bool

        /// Its height over `start.y` `s` metres along, and its nose's pitch.
        public func height(at s: Float) -> (height: Float, pitch: Float) {
            guard fromRunway else { return (level, 0) }
            let climbed = s * SantaFlight.climb
            return climbed < level ? (climbed, atan(SantaFlight.climb)) : (level, 0)
        }

        /// How long the pass flies, seconds.
        public var seconds: Double { Double(length / SantaFlight.speed) }
    }

    /// The way over `anchor` (on the ground, in the scene) from a map whose
    /// middle is at `latitude`, `longitude`; from `runway` (its two ends in
    /// the scene, on the ground) when Rovaniemi's is on the map. `ground`
    /// is the drawn ground's height at a scene point (x, z): the sleigh
    /// keeps ``clearance`` over it.
    public static func track(over anchor: Map3DPoint, latitude: Double, longitude: Double,
                             runway: (from: Map3DPoint, to: Map3DPoint)? = nil, ground: (Float, Float) -> Float) -> Track {
        if let runway {
            let toward = Map3DPoint(anchor.x - runway.from.x, 0, anchor.z - runway.from.z)
            let along = Map3DPoint(runway.to.x - runway.from.x, 0, runway.to.z - runway.from.z).normalized ?? Map3DPoint(0, 0, 1)
            let away = toward.length
            let forward = away >= nearestFromRunway && away <= farthestFromRunway ? toward.normalized ?? along : along
            let farthest = Float(every - 30) * speed
            let length = min(farthest, (away <= farthestFromRunway ? away : 0) + reach)
            let level = levelHeight(from: runway.from, forward: forward, length: length, over: runway.from.y, ground: ground)
            return Track(start: runway.from, forward: forward, length: length, level: level, fromRunway: true)
        }
        // Coming from Rovaniemi: the way it lies from the map's middle,
        // turned round. The scene's x is east and its z south.
        let bearing = initialBearing(fromLatitude: latitude, longitude: longitude,
                                     toLatitude: SantaFlight.runway.from.latitude, longitude: SantaFlight.runway.from.longitude)
        let forward = Map3DPoint(-Float(sin(bearing)), 0, Float(cos(bearing)))
        let start = Map3DPoint(anchor.x - forward.x * reach, anchor.y, anchor.z - forward.z * reach)
        let level = levelHeight(from: start, forward: forward, length: 2 * reach, over: anchor.y, ground: ground)
        return Track(start: start, forward: forward, length: 2 * reach, level: level, fromRunway: false)
    }

    /// The height over `base` the sleigh flies level at along the way:
    /// ``cruise`` over `base`, and ``clearance`` over the highest ground
    /// under it, looked at every 200 m.
    static func levelHeight(from start: Map3DPoint, forward: Map3DPoint, length: Float, over base: Float, ground: (Float, Float) -> Float) -> Float {
        var highest = base
        var s: Float = 0
        while s <= length {
            highest = max(highest, ground(start.x + forward.x * s, start.z + forward.z * s))
            s += 200
        }
        return max(cruise, highest - base + clearance)
    }

    /// The great circle's initial bearing from one point to another,
    /// radians clockwise from north.
    static func initialBearing(fromLatitude a: Double, longitude b: Double, toLatitude c: Double, longitude d: Double) -> Double {
        let φ1 = a * .pi / 180, φ2 = c * .pi / 180, Δλ = (d - b) * .pi / 180
        return atan2(sin(Δλ) * cos(φ2), cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ))
    }

    /// Rovaniemi's runway's two ends in a world laid by `frame` as far as
    /// `bounds`, in world units; `nil` when either is off the map.
    public static func runwayEnds(frame: RealWorldFrame, bounds: WorldBounds) -> (from: (x: Double, y: Double), to: (x: Double, y: Double))? {
        func place(_ point: (latitude: Double, longitude: Double)) -> (x: Double, y: Double)? {
            let at = frame.worldPosition(latitude: point.latitude, longitude: point.longitude)
            guard at.x >= 0, at.y >= 0, at.x < Double(bounds.width), at.y < Double(bounds.height) else { return nil }
            return at
        }
        guard let from = place(runway.from), let to = place(runway.to) else { return nil }
        return (from, to)
    }

    /// The way of a pass over `anchor` in `scene` of `world`: from
    /// Rovaniemi's runway when it is on the map; `nil` for a blank map.
    public static func track(world: GameWorld, scene: Map3DScene, over anchor: Map3DPoint) -> Track? {
        guard let frame = RealWorldFrame(world: world) else { return nil }
        func ground(_ x: Float, _ z: Float) -> Float { scene.drawnGround.height(x: x, z: z, world: world) }
        func onGround(_ at: (x: Double, y: Double)) -> Map3DPoint {
            let flat = scene.point(worldX: at.x, worldY: at.y, height: 0)
            return Map3DPoint(flat.x, ground(flat.x, flat.z), flat.z)
        }
        let ends = runwayEnds(frame: frame, bounds: world.bounds).map { (onGround($0.from), onGround($0.to)) }
        let below = Map3DPoint(anchor.x, ground(anchor.x, anchor.z), anchor.z)
        return track(over: below, latitude: frame.anchor.latitudeDegrees, longitude: frame.anchor.longitudeDegrees, runway: ends, ground: ground)
    }

    // MARK: - The sleigh drawn

    /// The sleigh of pass `pass` on `track`, `seconds` into it, as an
    /// aircraft is drawn (its ``Map3DAircraft/Drawn/flight`` names the
    /// pass); `nil` before it starts and once it has gone. Its `kind` is
    /// only a placeholder: what reads a Santa flight's asks
    /// ``Map3DAircraft/FlightID/santa`` first. Its phase is
    /// ``Map3DAircraft/Phase/climb`` while it climbs off the runway and
    /// ``Map3DAircraft/Phase/approach`` while it flies level (``stage(of:)``).
    public static func drawn(pass: Int, on track: Track, seconds: Double) -> Map3DAircraft.Drawn? {
        guard seconds >= 0 else { return nil }
        let s = Float(seconds) * speed
        guard s <= track.length else { return nil }
        let (height, pitch) = track.height(at: s)
        let ground = Map3DPoint(track.start.x + track.forward.x * s, track.start.y, track.start.z + track.forward.z * s)
        let climbing = track.fromRunway && height < track.level
        return Map3DAircraft.Drawn(ground: ground, height: height, forward: track.forward, pitch: pitch, kind: .commuter19, livery: 0,
                                   flying: true, flight: Map3DAircraft.FlightID(santa: pass), phase: climbing ? .climb : .approach)
    }

    /// What the sleigh is doing, as the follow bar says it.
    public enum Stage: Hashable, Sendable {
        case takingOff, flying

        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .takingOff: language.text("Taking off from Rovaniemi Airport", "從羅瓦涅米機場起飛")
            case .flying: language.text("Flying over the map", "飛過地圖上空")
            }
        }
    }

    public static func stage(of phase: Map3DAircraft.Phase) -> Stage {
        phase == .climb ? .takingOff : .flying
    }

    /// Where the follow camera looks at the sleigh `drawn` and which way it
    /// faces: at the middle of the team; the seat beside Santa.
    public static func pose(of drawn: Map3DAircraft.Drawn) -> Map3DFollow.Pose {
        let (origin, x, y, z) = Map3DAircraft.axes(of: drawn)
        func at(_ ahead: Float, _ left: Float, _ up: Float) -> Map3DPoint { origin + x * ahead + y * left + z * up }
        let centre = Model.height / 2
        let middle = at(0, 0, centre)
        let seat = at(Model.seat, Model.halfWidth + 0.2, Model.seatHeight) - middle
        let forward = drawn.forward, left = Map3DPoint(forward.z, 0, -forward.x)
        return Map3DFollow.Pose(forward: forward, nose: at(Model.length / 2, 0, centre), rail: middle, middle: middle - Map3DPoint(0, centre, 0),
                                length: Map3DAircraft.sideLength(Model.length), bodyHeight: Model.height,
                                window: .init(across: seat.dot(left), height: seat.y + centre, lookDown: Map3DAircraft.windowLookDown,
                                              ahead: seat.dot(forward)))
    }

    /// The sleigh drawn under the finger at (`x`, `y`) in `camera`'s view,
    /// within `reach` points of its middle or of the line to the leading reindeer's nose.
    public static func followable(_ drawn: Map3DAircraft.Drawn, atX x: Float, y: Float, camera: Map3DCamera, within reach: Float) -> Bool {
        let pose = pose(of: drawn)
        guard let middle = camera.screenPoint(of: pose.rail) else { return false }
        var wide = reach
        if let nose = camera.screenPoint(of: pose.nose) {
            wide = max(reach, ((nose.x - middle.x) * (nose.x - middle.x) + (nose.y - middle.y) * (nose.y - middle.y)).squareRoot())
        }
        return ((middle.x - x) * (middle.x - x) + (middle.y - y) * (middle.y - y)).squareRoot() <= wide
    }

    /// The sleigh `drawn` added to `frame` with `pack`'s model, and at
    /// night (`lit`) the leading reindeer's red nose and the lantern on the sleigh's
    /// front as glows. Drawn at any distance: there is one.
    public static func add(_ drawn: Map3DAircraft.Drawn, to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, lit: Bool) {
        guard let index = pack.index(of: Model.name) else { return }
        frame.instances.append(Map3DAircraft.instance(index, drawn))
        guard lit else { return }
        let (origin, x, y, z) = Map3DAircraft.axes(of: drawn)
        func at(_ point: Map3DPoint) -> Map3DPoint { origin + x * point.x + y * point.y + z * point.z }
        frame.lamps.append(Map3DGlow.Spot(centre: at(Model.nose), radius: 1.6, red: 1, green: Float(0x2B) / 255, blue: Float(0x2B) / 255))
        frame.lamps.append(Map3DGlow.Spot(centre: at(Model.lantern), radius: 1.2, red: 1, green: 0.85, blue: 0.55, strength: 0.8))
    }

    // MARK: - Heard

    /// The bells as heard from the camera: their volume (0–1, before the
    /// player's) and side, −1 the left to 1 the right, in steps (a
    /// decibel; a tenth) as the garbage truck's tune (``Map3DGarbageTruck/Sound``).
    public struct Sound: Equatable, Sendable {
        public let volume: Double
        public let pan: Double

        /// The bells' loop in the app's resources: the winter tune's
        /// `sleigh` voice shaken to the reindeer's gallop
        /// (`tools/audio/make_game_audio.py`, `sleigh_bells()`).
        public static let resource = (name: "sleigh-bells", extension: "caf")
    }

    /// Within this of the ear the bells are at their loudest, metres; they
    /// fall as the reciprocal of the distance past it, and away to nothing
    /// between ``silentFrom`` and ``silentAt``: a sleigh 250 m up is heard
    /// from a camera looking down at its own street.
    static let fullWithin: Float = 120
    static let silentFrom: Float = 1_400
    static let silentAt: Float = 1_800
    /// Quieter than this, in decibels, they are not played.
    static let quietest: Double = -24

    /// The bells of `drawn` heard from `camera`; `nil` when too far.
    public static func sound(of drawn: Map3DAircraft.Drawn?, camera: Map3DCamera) -> Sound? {
        guard let drawn else { return nil }
        let offset = pose(of: drawn).rail - camera.eye
        let distance = offset.length
        var gain = min(fullWithin / max(distance, 1), 1)
        gain *= min(max((silentAt - distance) / (silentAt - silentFrom), 0), 1)
        guard gain > 0 else { return nil }
        let decibels = (20 * log10(Double(gain))).rounded()
        guard decibels >= quietest else { return nil }
        let level = Map3DPoint(offset.x, 0, offset.z)
        let pan = level.length > 1 ? Double(level.normalized.map { $0.dot(camera.right) } ?? 0) : 0
        return Sound(volume: pow(10, decibels / 20), pan: (pan * 0.6 * 10).rounded() / 10)
    }

    // MARK: - The follow bar

    /// The follow bar's text for the sleigh: only what it is and what it
    /// is doing.
    public static func followFacts(of state: Map3DAircraft.State, in language: DisplayLanguage, speed: GameSpeed?) -> AircraftFollowFacts {
        AircraftFollowFacts(state: state, name: language.text("Santa's sleigh", "聖誕老人的雪橇"),
                            directionText: language.text("From Rovaniemi Airport", "從羅瓦涅米機場出發"),
                            stopText: stage(of: state.phase).text(in: language), runningSpeed: speed)
    }

    /// The views of the sleigh: from behind and from beside.
    public static let views: [Map3DFollow.View] = [.back, .side]

    /// The view of the sleigh nearest `view`.
    public static func view(_ view: Map3DFollow.View) -> Map3DFollow.View {
        view == .side ? .side : .back
    }

    /// What a view's button does, for VoiceOver.
    public static func hint(_ view: Map3DFollow.View, in language: DisplayLanguage) -> String {
        view == .side ? language.text("Moves alongside the sleigh, showing all of it and the reindeer.", "在雪橇旁邊一起移動，看得到整個雪橇與馴鹿。")
            : language.text("Follows the sleigh from behind.", "從雪橇後方跟著看。")
    }
}

// MARK: - The sky over the map

extension SantaFlight {
    /// The pass flying over the 3D map now: worked out at the pass's first
    /// frame over the camera's target, then kept until the pass is over
    /// (the camera moving does not move the sleigh) or the scene moves.
    public struct Sky: Sendable {
        struct Flying: Sendable {
            let pass: Int
            let origin: (x: Double, y: Double)
            let track: Track
        }

        private(set) var flying: Flying?

        public init() {}

        /// The sleigh at `date`, on the way `track` gives when its pass
        /// begins now (``SantaFlight/track(world:scene:over:)`` over the
        /// camera's target) or the scene moved (to `origin`, its
        /// ``Map3DScene/originX`` and ``Map3DScene/originY``); `nil` off
        /// the night, between passes, with `switchedOn` false, with `still`
        /// (Reduce Motion) and when `track` gives none (a blank map).
        public mutating func sleigh(at date: Date, origin: (x: Double, y: Double), switchedOn: Bool, still: Bool,
                                    calendar: Calendar = WinterEvent.calendar(), track: () -> Track?) -> Map3DAircraft.Drawn? {
            guard !still, let moment = moment(at: date, switchedOn: switchedOn, calendar: calendar) else {
                flying = nil
                return nil
            }
            if flying?.pass != moment.pass || flying?.origin.x != origin.x || flying?.origin.y != origin.y {
                guard let laid = track() else {
                    flying = nil
                    return nil
                }
                flying = Flying(pass: moment.pass, origin: origin, track: laid)
            }
            return flying.flatMap { drawn(pass: $0.pass, on: $0.track, seconds: moment.seconds) }
        }

        /// The sleigh of flight `id` at `date`, as ``sleigh(at:origin:switchedOn:still:calendar:track:)``
        /// last laid its pass; `nil` once that pass is over or another
        /// began.
        public func sleigh(of id: Map3DAircraft.FlightID, at date: Date, switchedOn: Bool, still: Bool,
                           calendar: Calendar = WinterEvent.calendar()) -> Map3DAircraft.Drawn? {
            guard !still, let pass = id.santa, let flying, flying.pass == pass,
                  let moment = moment(at: date, switchedOn: switchedOn, calendar: calendar), moment.pass == pass
            else { return nil }
            return drawn(pass: pass, on: flying.track, seconds: moment.seconds)
        }

        /// The sleigh of flight `id` as the follow camera has it, while it
        /// flies.
        public func followed(_ id: Map3DAircraft.FlightID, at date: Date, switchedOn: Bool, still: Bool,
                             calendar: Calendar = WinterEvent.calendar()) -> Map3DAircraft.Followed? {
            sleigh(of: id, at: date, switchedOn: switchedOn, still: still, calendar: calendar)
                .map { Map3DAircraft.Followed(flight: id, drawn: $0, airport: nil) }
        }

        /// The sleigh flying now when it is under the finger at (`x`, `y`)
        /// in `camera`'s view (``SantaFlight/followable(_:atX:y:camera:within:)``).
        public func followable(atX x: Float, y: Float, camera: Map3DCamera, at date: Date, switchedOn: Bool, still: Bool, within reach: Float,
                               calendar: Calendar = WinterEvent.calendar()) -> Map3DAircraft.Followed? {
            guard let pass = flying?.pass,
                  let found = followed(Map3DAircraft.FlightID(santa: pass), at: date, switchedOn: switchedOn, still: still, calendar: calendar),
                  SantaFlight.followable(found.drawn, atX: x, y: y, camera: camera, within: reach)
            else { return nil }
            return found
        }
    }
}

// MARK: - The model

extension SantaFlight {
    /// The studio's reindeer and sleigh (decision 840, REINDEER): nine
    /// reindeer in four pairs and one leading, the sleigh behind them with
    /// Santa and his sack (``Map3DReindeer/Unit/sleigh``). The model's frame
    /// is the aircraft's (x forward, y left, z up, metres), its origin under
    /// the middle of the team; ``length``, ``seat`` and the lamps are
    /// measured on it.
    public enum Model {
        public static let name = Map3DReindeer.Unit.sleigh.rawValue
        /// From the back of the sleigh to the leading reindeer's nose, metres.
        public static let length: Float = 16.66
        static let halfWidth: Float = 0.98
        static let height: Float = 2.68
        /// Santa's seat: how far ahead of the middle, and the height of his
        /// eyes (the follow camera's window beside him).
        static let seat: Float = -6.95
        static let seatHeight: Float = 1.7
        /// The leading reindeer's red nose and the sleigh's lantern, the
        /// middles of their lenses.
        static let nose = Map3DPoint(8.28, 0, 1.70)
        static let lantern = Map3DPoint(-5.25, 0.64, 1.42)

        /// The model in the pack, after the winter decorations; an empty
        /// one should its mesh not decode (the tests see that it does).
        public static var model: Map3DModelPack.Model {
            Map3DReindeer.model(.sleigh) ?? Map3DModelPack.Model(name: name, vertices: [], minimum: .zero, maximum: .zero)
        }
    }
}
