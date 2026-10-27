import Foundation

/// Decision 437: the evening garbage truck of the 3D map's streets, and
/// the recycling truck that follows it, as Taiwan's trucks come round
/// playing 〈給愛麗絲〉. Seen only close up, one at a time: like the
/// streets' own vehicles (decision 259) it is scenery, never game state.
/// Whether it is out comes from the game clock (Taipei's collection hours,
/// ``evening``); which street it works that evening from the day and the
/// street; where it is along the street from the clock the streets'
/// vehicles drive by. Nothing is kept: the same moment draws the same.
///
/// Ported from the owner's Taiwan 3D city (`Railway/tw3d-reference-clean/
/// source/js/garbage-truck.js`): an evening truck passing near the player,
/// its tune placed in the world and fading with distance (its `inverse`
/// distance model). The reference's truck is only heard and comes at a
/// random time; here it is also seen, keeps to a street the city has, and
/// its hours, stops and pace are Taipei's own (`docs/decisions/437.md`).
public enum Map3DGarbageTruck {
    // MARK: When

    /// The seconds of the game's day it works: 18:00 to 21:00, the middle
    /// half of the stops of Taipei's garbage trucks (the Environmental
    /// Protection Department's 臺北市垃圾車點位路線資訊: a quarter of its
    /// 4,012 stops before 18:00, a quarter after 21:07).
    public static let evening: ClosedRange<Double> = 18 * 3_600...21 * 3_600

    /// It drives in at the start of the hours and away at their end over
    /// this many seconds of the game's day.
    static let arrival: Double = 600

    /// How much of the truck is drawn at `second` of the game's day, 0–1:
    /// none outside ``evening``, growing in over its first ten minutes
    /// and shrinking away over its last.
    public static func presence(atSecond second: Double) -> Float {
        guard evening.contains(second) else { return 0 }
        let edge = min(second - evening.lowerBound, evening.upperBound - second)
        return Float(min(edge / arrival, 1))
    }

    // MARK: Where

    /// Within this camera distance, metres, the truck is drawn and heard:
    /// the close view the streets' people are drawn in.
    public static let shownFrom: Float = Map3DStreetLife.peopleFrom

    /// The share of the streets a truck works each evening: a third, so
    /// the one nearest the view changes from evening to evening.
    static let servedShare: Float = 1.0 / 3
    /// A street shorter than this, metres, has no room for its stops.
    static let shortestStreet: Float = 60

    /// Its stops, metres apart along the street: 170 m, the median between
    /// two stops of a Taipei truck's round.
    static let stopSpacing: Float = 170
    /// Its pace between stops, metres a second: 2, the median of a Taipei
    /// truck's from one stop to the next. It eases off from one stop and
    /// into the next, so it goes faster in between.
    static let pace: Float = 2
    /// Seconds it waits at a stop while the street brings its bags out.
    /// Taipei's trucks wait four minutes (the median); the game's evening
    /// passes in minutes at its speeds, so here it is half a minute.
    static let waitSeconds: Float = 30

    /// The trucks' length, width and height, metres: a Taiwanese
    /// rear-loading compactor truck and the flatbed recycling truck,
    /// as the generated models were asked for.
    public static let size: (length: Float, width: Float, height: (garbage: Float, recycling: Float)) = (6.5, 2.3, (2.8, 2.6))
    /// How far behind the garbage truck the recycling truck drives, metres
    /// from one's middle to the other's: a truck and a three-metre gap.
    static let followGap: Float = 9.5

    /// Whether a street is one the truck can work: one it collects on
    /// (``Map3DStreetLife/Lane/collects``), long enough, and worked on the
    /// game's `day`.
    static func works(_ lane: Map3DStreetLife.Lane, day: Int64) -> Bool {
        lane.collects && lane.path.length >= shortestStreet
            && map3DRandom(lane.seed.0, lane.seed.1 &+ Int32(truncatingIfNeeded: day), salt: 437) < servedShare
    }

    /// A truck on its round: the way out along the street on its right and
    /// back on the other side, ``stopSpacing`` (or so, a whole number of
    /// them) from stop to stop, at ``pace`` with ``waitSeconds`` at each.
    /// `round` is metres of the way out and back, from 0 to twice the
    /// street's length, at `time` (seconds of the streets' clock); each
    /// street starts its round at its own point.
    static func round(of lane: Map3DStreetLife.Lane, time: Double) -> Float {
        let loop = 2 * lane.path.length
        let legs = max(1, Int((loop / stopSpacing).rounded()))
        let leg = loop / Float(legs)
        let drive = Double(leg / pace), legSeconds = drive + Double(waitSeconds)
        let start = Double(map3DRandom(lane.seed.0, lane.seed.1, salt: 438)) * Double(legs) * legSeconds
        let into = (time + start).truncatingRemainder(dividingBy: Double(legs) * legSeconds)
        let index = Int(into / legSeconds)
        let within = into - Double(index) * legSeconds
        // Eased out of one stop and into the next.
        let share = within < drive ? Float((1 - cos(Double.pi * within / drive)) / 2) : 1
        return (Float(index) + share) * leg
    }

    /// One of the trucks drawn: where on the ground it stands, the way it
    /// faces, how big it is drawn (0–1) and which it is.
    public struct Truck: Sendable {
        public let model: Map3DStreetModel
        public let point: Map3DPoint
        public let along: Map3DPoint
        public let size: Float
    }

    /// The trucks of a frame: the garbage truck and, where there is room,
    /// the recycling truck behind it; none at all outside the evening, far
    /// out or with no street to work.
    public struct Frame: Sendable {
        public var trucks: [Truck] = []
        public init() {}

        /// The garbage truck, the one the tune comes from.
        public var leader: Truck? { trucks.first }
        /// The trucks' instances in `models` (``Map3DStreetLife/models``'
        /// pack), and where the streets' own vehicles give way to them.
        public var instances: [Map3DInstance] {
            trucks.compactMap { truck in
                Map3DStreetLife.models[truck.model].map { .prop($0, at: truck.point, forward: truck.along, scale: truck.size, tint: Map3DColor.rgb(0xFFFFFF)) }
            }
        }
        public var clear: [(point: Map3DPoint, along: Map3DPoint)] { trucks.map { ($0.point, $0.along) } }
    }

    /// The trucks at `second` of the game's `day`, round `target` seen from
    /// `distance` away, at `time` on the streets' clock (``Map3DStreetLife``'s:
    /// it drives at a street's pace whatever the game's speed). The street
    /// worked nearest the target has the truck; the recycling truck follows
    /// when `follows` (the streets keep room for it, ``follows(_:of:)``).
    /// When `still` (Reduce Motion) it stands at its first stop.
    public static func frame(lanes: [Map3DStreetLife.Lane], target: Map3DPoint, distance: Float, day: Int64, second: Double, time: Double,
                             still: Bool = false, follows: Bool = true) -> Frame {
        var frame = Frame()
        let presence = presence(atSecond: second)
        guard presence > 0, distance <= shownFrom else { return frame }
        let reach = Map3DStreetLife.vehiclesReach(distance)
        var nearest: (index: Int, away: Float)?
        for (index, lane) in lanes.enumerated() where works(lane, day: day) {
            let away = lane.path.boxDistance(to: target)
            if away < reach, away < (nearest?.away ?? .infinity) { nearest = (index, away) }
        }
        guard let nearest else { return frame }
        let lane = lanes[nearest.index]
        let round = round(of: lane, time: still ? 0 : time)
        let models: [(Map3DStreetModel, Float)] = [(.garbageTruck, 0)] + (follows ? [(.recyclingTruck, followGap)] : [])
        for (model, behind) in models {
            guard let place = place(on: lane, at: round - behind) else { continue }
            let away = Map3DPoint(place.point.x - target.x, 0, place.point.z - target.z).length
            let size = presence * place.ends * Map3DStreetLife.fade(away, reach: reach)
            guard size > 0 else { continue }
            frame.trucks.append(Truck(model: model, point: place.point, along: place.along, size: size))
        }
        return frame
    }

    /// Where a truck `round` metres into its round on `lane` stands, the
    /// way it faces, and how much of it shows at the street's ends (it
    /// comes out of and goes into them as the streets' vehicles do).
    static func place(on lane: Map3DStreetLife.Lane, at round: Float) -> (point: Map3DPoint, along: Map3DPoint, ends: Float)? {
        let length = lane.path.length
        guard length > 0 else { return nil }
        let loop = 2 * length
        var r = round.truncatingRemainder(dividingBy: loop)
        if r < 0 { r += loop }
        let outward = r < length
        let along = outward ? r : loop - r
        let place = lane.path.at(along)
        // Kept to the right, near the kerb, where the street lines up.
        let side = lane.twoWay ? max(lane.half - size.width / 2 - 0.4, 1.2) : 0
        let direction: Float = outward ? 1 : -1
        let ends = min(max(min(along, length - along) / size.length, 0), 1)
        return (place.point + place.right * (side * direction), place.along * direction, ends)
    }

    /// Whether the recycling truck comes too: when the streets keep at
    /// least half the vehicles their device draws in full (`limits` of
    /// `full`, ``Map3DMotionBudget``); under more load, only the garbage
    /// truck.
    public static func follows(_ limits: Map3DStreetLimits, of full: Map3DStreetLimits) -> Bool {
        limits.vehicles * 2 >= full.vehicles
    }

    // MARK: Heard

    /// The tune as heard from the camera: its volume (0–1, before the
    /// player's) and where it comes from, −1 the left to 1 the right.
    /// Both in steps (a decibel; a tenth), so the app is told only when it
    /// moves a step and fades between them, as the running sound is
    /// (decision 343).
    public struct Sound: Equatable, Sendable {
        public let volume: Double
        public let pan: Double

        /// The tune's file in the app's resources.
        public static let resource = (name: "garbage-truck", extension: "caf")
    }

    /// Within this many metres of the ear the tune is at its loudest; it
    /// falls as the reciprocal of the distance past it (the reference's
    /// `inverse` model, its roll-off 1), and away to nothing between
    /// ``silentFrom`` and ``silentAt``.
    static let fullWithin: Float = 80
    static let silentFrom: Float = 500
    static let silentAt: Float = 700
    /// Quieter than this, in decibels, it is not played at all.
    static let quietest: Double = -30

    /// The tune of `frame`'s garbage truck heard from `camera`'s eye, `nil`
    /// when there is none or it is too far to hear.
    public static func sound(of frame: Frame, camera: Map3DCamera) -> Sound? {
        guard let truck = frame.leader else { return nil }
        let eye = camera.eye
        // From the truck's loudspeaker, about its roof.
        let offset = truck.point + Map3DPoint(0, 2.5, 0) - eye
        let distance = offset.length
        var gain = min(fullWithin / max(distance, 1), 1)
        gain *= min(max((silentAt - distance) / (silentAt - silentFrom), 0), 1)
        gain *= truck.size
        guard gain > 0 else { return nil }
        let decibels = (20 * log10(Double(gain))).rounded()
        guard decibels >= quietest else { return nil }
        let level = Map3DPoint(offset.x, 0, offset.z)
        let pan = level.length > 1 ? Double(level.normalized.map { $0.dot(camera.right) } ?? 0) : 0
        // Never wholly to one side: both ears hear a street's loudspeaker.
        return Sound(volume: pow(10, decibels / 20), pan: (pan * 0.6 * 10).rounded() / 10)
    }
}

extension Map3DGarbageTruck {
    // MARK: The models

    /// The models' files in the app's resources: the owner's Meshy models
    /// (`Railway/meshy-batch-2026-10/`, converted by
    /// `tools/glb-to-m3dmodel/`).
    public static let fileNames: [Map3DStreetModel: String] = [.garbageTruck: "garbage-truck", .recyclingTruck: "recycling-truck"]
    public static let fileExtension = "m3dmodel"

    /// `pack` with the trucks read from `files` in place of the box-built
    /// ones (``Map3DStreetModel/garbageTruck``,
    /// ``Map3DStreetModel/recyclingTruck``), each where its file can be
    /// read; the box-built one stays where it cannot.
    public static func pack(_ pack: Map3DModelPack, files: [Map3DStreetModel: URL]) -> Map3DModelPack {
        var pack = pack
        for (model, url) in files.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let name = fileNames[model], let data = try? Data(contentsOf: url),
                  let file = try? Map3DModelFile(decoding: data, named: name), Map3DCityBus.canFit(file.model) else { continue }
            pack = pack.replacing(self.model(model, from: file))
        }
        return pack
    }

    /// The truck `model` from `file`: fitted to ``size``, its middle at the
    /// origin and its wheels on the ground; its colours the game's own
    /// (``colour(_:of:)``); with the lamps that light at night (the
    /// generated models have none) and, on the garbage truck, its amber
    /// beacon. Named as `model`.
    public static func model(_ model: Map3DStreetModel, from file: Map3DModelFile) -> Map3DModelPack.Model {
        let source = file.model
        let extent = source.maximum - source.minimum
        let height = model == .garbageTruck ? size.height.garbage : size.height.recycling
        let scale = Map3DPoint(size.length / extent.x, size.width / extent.y, height / extent.z)
        let middle = Map3DPoint((source.minimum.x + source.maximum.x) / 2, (source.minimum.y + source.maximum.y) / 2, source.minimum.z)
        var vertices = source.vertices.map { vertex in
            let p = vertex.position - middle
            let normal = Map3DPoint(vertex.nx / scale.x, vertex.ny / scale.y, vertex.nz / scale.z).normalized ?? Map3DPoint(0, 0, 1)
            return Map3DVertex(Map3DPoint(p.x * scale.x, p.y * scale.y, p.z * scale.z), normal: normal, color: colour(vertex.color, of: model),
                               layer: vertex.layer)
        }
        var lamps = Map3DMesh()
        addLamps(to: &lamps, of: model)
        vertices += Map3DModelPack.Model.flat(named: "", from: lamps).vertices
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        return Map3DModelPack.Model(name: model.modelName, vertices: vertices, minimum: low, maximum: high)
    }

    /// The colours the trucks are drawn in: the game's, not the generated
    /// model's (the art style's rule for what comes from a reference). The
    /// garbage truck's yellow is the platform edge's; the recycling truck's
    /// cab is the parks' green.
    static let yellow = Map3DColor.rgb(0xF2C94C)
    static let green = Map3DColor.rgb(0x8DC27A)
    static let beacon = Map3DColor.rgb(0xF0A93C)

    /// A generated colour as the game draws it, by what it is (its hue and
    /// lightness): the tyres and the chassis dark, a grey bed or trim the
    /// game's steel or trim, the windows the vehicles' glass, the body
    /// the truck's own colour.
    static func colour(_ color: UInt32, of model: Map3DStreetModel) -> UInt32 {
        let r = Float(color & 0xFF) / 255, g = Float((color >> 8) & 0xFF) / 255, b = Float((color >> 16) & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), lightness = (high + low) / 2
        let chroma = high - low
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        var hue: Float = 0
        if chroma > 0 {
            hue = high == r ? (g - b) / chroma : high == g ? 2 + (b - r) / chroma : 4 + (r - g) / chroma
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        if lightness < 0.16 { return Map3DStreetModel.tyre }
        if saturation < 0.15 { return lightness < 0.3 ? Map3DStreetModel.trim : Map3DStreetModel.steel }
        if hue >= 160, hue < 230, lightness > 0.4 { return Map3DStreetModel.glass }
        if hue >= 30, hue < 65 { return lightness >= 0.2 ? yellow : Map3DStreetModel.trim }
        if hue >= 65, hue < 160 { return green }
        return Map3DStreetModel.trim
    }

    /// The trucks' headlamps and tail lamps, lit at night, and the garbage
    /// truck's beacon on its cab, in the scene's axes (x the front, y up,
    /// −z the left).
    static func addLamps(to mesh: inout Map3DMesh, of model: Map3DStreetModel) {
        func lamp(_ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float, _ colour: UInt32) {
            let first = mesh.vertices.count
            mesh.addBox(base: Map3DPoint(x, y, z), forward: Map3DPoint(1, 0, 0), length: length, width: width, height: height, top: colour,
                        side: colour)
            mesh.makeGlowing(from: first)
        }
        let front = size.length / 2, back = -size.length / 2
        for side: Float in [-1, 1] {
            lamp(front, 0.55, side * 0.85, 0.08, 0.3, 0.16, Map3DStreetModel.headlamp)
            lamp(back, 0.6, side * 0.95, 0.08, 0.22, 0.26, Map3DStreetModel.tailLamp)
        }
        if model == .garbageTruck {
            // The amber beacon over the cab, about 1.2 m back from its front.
            lamp(front - 1.2, size.height.garbage * 0.9, 0, 0.3, 0.3, 0.22, beacon)
        }
    }
}

extension Map3DGarbageTruck {
    // MARK: In the 3D map

    /// The trucks of the streets of `life` as the 3D map draws them now:
    /// at `clock`'s second of the game day (gliding between ticks when
    /// `glides`), along the streets at `now` (seconds of the streets'
    /// clock), round `camera`'s target; none where the device draws no
    /// street life (`budget`'s tier, decision 417), and the recycling
    /// truck only while the streets keep room for it.
    public static func frame(in life: Map3DStreetLife, camera: Map3DCamera, clock: RealTrainClock?, glides: Bool, now: Double,
                             still: Bool, budget: Map3DMotionBudget) -> Frame {
        guard let clock, let tier = budget.tier, tier.streetDetail != .off else { return Frame() }
        return frame(lanes: life.lanes, target: camera.target, distance: camera.distance, day: clock.day,
                     second: clock.second(at: now, glides: glides), time: now.truncatingRemainder(dividingBy: 86_400), still: still,
                     follows: follows(budget.limits(), of: tier.streetLimits))
    }
}

extension Map3DBuses.Frame {
    /// These buses and `trucks` (decision 437): drawn with them, counted
    /// with them in the device's budget (``Map3DMotionBudget``), and given
    /// way to by the streets' vehicles as they are.
    public func adding(_ trucks: Map3DGarbageTruck.Frame) -> Self {
        var frame = self
        frame.instances += trucks.instances
        frame.clear += trucks.clear
        return frame
    }
}
