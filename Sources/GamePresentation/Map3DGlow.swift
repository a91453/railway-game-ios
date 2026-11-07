import Foundation

// Decision 617 (NIGHT-GLOW, NEXT_PRIORITIES §24.6 13a): a soft glow round
// each light the 3D map already lights at night, drawn as a small square
// facing the eye and added to what is behind it (no render target, no
// pass over the whole picture, decision 349's finish untouched).
//
// What glows is what the models already light (``Map3DVertex/glowing``):
// a street light's head, the lit light of a road signal (red, amber or
// green, whichever the clock shows, decision 429), a pedestrian signal's
// figure, a scooter's or a car's lamps, and a train's headlamps and tail
// lamps (``Map3DTrainLights``). Each model's lit triangles are gathered
// into a few spots (``spots(of:)``) once, as the models are put on the
// GPU; the renderer draws a model's spots over the same instances it
// draws the model with, so the glows of the city cost no buffer a frame.
// Only a train's lamps are placed each frame (``trainSpots(of:pack:)``),
// in one of the three rotating buffers (``Map3DFrameBuffers``, decision
// 608 續二). The signs' glow and the lit windows' are worked out in their
// own shaders from what they already draw.

/// Decision 617: the glows round the 3D map's lights at night.
public enum Map3DGlow {
    /// One glow: its middle in its model's space (or the scene's, for a
    /// train's lamps), its radius in metres and its colour, brightest
    /// channel 1.
    public struct Spot: Equatable, Sendable {
        public var centre: Map3DPoint
        public var radius: Float
        public var red: Float
        public var green: Float
        public var blue: Float
        /// How bright it is beside the others, 0 to 1.
        public var strength: Float

        public init(centre: Map3DPoint, radius: Float, red: Float, green: Float, blue: Float, strength: Float = 1) {
            self.centre = centre
            self.radius = radius
            self.red = red
            self.green = green
            self.blue = blue
            self.strength = strength
        }

        /// The 8 floats the shader reads (`Map3DGlowSpot`): middle and
        /// radius, colour and strength.
        public var floats: [Float] { [centre.x, centre.y, centre.z, radius, red, green, blue, strength] }
    }

    /// The floats a spot takes in a buffer.
    public static let floatsASpot = 8
    /// The vertices the shader makes for a spot: two triangles.
    public static let verticesASpot = 6

    // MARK: - Which lights glow

    /// How far apart two lit triangles may be and still be one light, metres.
    static let join: Float = 0.15
    /// A lit part wider than this is a panel (a destination board, a lit
    /// band), not a lamp: it gets no glow.
    static let widest: Float = 3.0
    /// The most spots a model has.
    static let mostAModel = 16

    /// The radius of the glow round a light `size` metres across: a
    /// little over twice it, between ``smallest`` and ``largest``.
    public static func radius(across size: Float) -> Float {
        min(max(size * 2.2 + 0.25, smallest), largest)
    }

    static let smallest: Float = 0.35
    static let largest: Float = 2.4

    /// The spots of `model`'s lit triangles (``Map3DVertex/glowing`` only:
    /// not its lit glass); none for a train's windows' model
    /// (``Map3DTrainLights/prefix``), whose panes are a car's whole side.
    public static func spots(of model: Map3DModelPack.Model) -> [Spot] {
        guard !model.name.hasPrefix(Map3DTrainLights.prefix) else { return [] }
        return spots(in: model.vertices) { $0.layer == Map3DVertex.glowing }
    }


    /// The spots of the triangles of `vertices` (three to a triangle) whose
    /// first corner `lit` says: those that touch (within ``join``) one
    /// light, its middle the middle of their box, its colour theirs (by
    /// area) at full brightness. Decision 439 shades a lamp's faces by the way
    /// each turns, the side faces toward grey: a light glows in the colour of
    /// its most saturated face (a signal's lit lens, its own red, amber or
    /// green), the others' only when it has none. A light wider than ``widest`` has none;
    /// at most ``mostAModel``, the largest, in the order first met.
    public static func spots(in vertices: [Map3DVertex], strength: Float = 1, where lit: (Map3DVertex) -> Bool) -> [Spot] {
        struct Light {
            var low: Map3DPoint
            var high: Map3DPoint
            var red: Float = 0, green: Float = 0, blue: Float = 0, weight: Float = 0
            /// Its most saturated face's colour and how saturated.
            var vivid: (colour: UInt32, saturation: Float) = (0, -1)

            func touches(_ other: Light) -> Bool {
                let join = Map3DGlow.join
                return other.low.x <= high.x + join && other.high.x >= low.x - join
                    && other.low.y <= high.y + join && other.high.y >= low.y - join
                    && other.low.z <= high.z + join && other.high.z >= low.z - join
            }

            mutating func take(_ other: Light) {
                low = Map3DPoint(min(low.x, other.low.x), min(low.y, other.low.y), min(low.z, other.low.z))
                high = Map3DPoint(max(high.x, other.high.x), max(high.y, other.high.y), max(high.z, other.high.z))
                red += other.red
                green += other.green
                blue += other.blue
                weight += other.weight
                if other.vivid.saturation > vivid.saturation { vivid = other.vivid }
            }
        }
        var lights: [Light] = []
        for start in stride(from: 0, to: vertices.count - 2, by: 3) where lit(vertices[start]) {
            let a = vertices[start].position, b = vertices[start + 1].position, c = vertices[start + 2].position
            let weight = max((b - a).cross(c - a).length / 2, 1e-4)
            let colour = vertices[start].color
            var light = Light(low: Map3DPoint(min(a.x, b.x, c.x), min(a.y, b.y, c.y), min(a.z, b.z, c.z)),
                              high: Map3DPoint(max(a.x, b.x, c.x), max(a.y, b.y, c.y), max(a.z, b.z, c.z)))
            light.red = Float(colour & 0xFF) * weight
            light.green = Float((colour >> 8) & 0xFF) * weight
            light.blue = Float((colour >> 16) & 0xFF) * weight
            light.weight = weight
            light.vivid = (colour, saturation(colour))
            if var at = lights.firstIndex(where: { $0.touches(light) }) {
                lights[at].take(light)
                // A light grown into another takes it in.
                while let other = lights.indices.first(where: { $0 != at && lights[$0].touches(lights[at]) }) {
                    lights[at].take(lights[other])
                    lights.remove(at: other)
                    if other < at { at -= 1 }
                }
            } else {
                lights.append(light)
            }
        }
        var made: [(order: Int, size: Float, spot: Spot)] = []
        for (order, light) in lights.enumerated() {
            let extent = light.high - light.low
            let size = max(extent.x, extent.y, extent.z)
            guard size <= widest, light.weight > 0 else { continue }
            let r = light.red / light.weight, g = light.green / light.weight, b = light.blue / light.weight
            let brightest = max(r, g, b)
            guard brightest > 0 else { continue }
            var colour = (r / brightest, g / brightest, b / brightest)
            if light.vivid.saturation >= vivid {
                let c = light.vivid.colour
                let vr = Float(c & 0xFF), vg = Float((c >> 8) & 0xFF), vb = Float((c >> 16) & 0xFF), top = max(vr, vg, vb, 1)
                colour = (vr / top, vg / top, vb / top)
            }
            let spot = Spot(centre: (light.low + light.high) * 0.5, radius: radius(across: size),
                            red: colour.0, green: colour.1, blue: colour.2, strength: strength)
            made.append((order, size, spot))
        }
        if made.count > mostAModel {
            made = Array(made.sorted { $0.size != $1.size ? $0.size > $1.size : $0.order < $1.order }.prefix(mostAModel))
                .sorted { $0.order < $1.order }
        }
        return made.map(\.spot)
    }

    /// Every model's spots, as one buffer's floats: a model's from
    /// `first[model]` (in spots), `count[model]` of them. Made once, with
    /// the models' vertices, before they are let go of (decision 608).
    /// How saturated a face must be for the light to glow in its colour
    /// rather than all its faces' (a white lamp's faces are all near grey).
    static let vivid: Float = 0.3

    /// `colour`'s saturation, 0 (grey) to 1.
    static func saturation(_ colour: UInt32) -> Float {
        let r = Float(colour & 0xFF), g = Float((colour >> 8) & 0xFF), b = Float((colour >> 16) & 0xFF)
        let top = max(r, g, b)
        return top > 0 ? (top - min(r, g, b)) / top : 0
    }

    public struct Table: Sendable {
        public let first: [Int]
        public let count: [Int]
        public let floats: [Float]

        public init(models: [Map3DModelPack.Model]) {
            var first: [Int] = [], count: [Int] = [], floats: [Float] = []
            for model in models {
                let spots = Map3DGlow.spots(of: model)
                first.append(floats.count / floatsASpot)
                count.append(spots.count)
                floats += spots.flatMap(\.floats)
            }
            self.first = first
            self.count = count
            self.floats = floats
        }

        /// How many spots the table holds.
        public var spots: Int { floats.count / floatsASpot }

        /// The spots `model` has (0 for one the table does not have).
        public func spots(of model: Int) -> Int { count.indices.contains(model) ? count[model] : 0 }
    }

    // MARK: - A train's lamps, each frame

    /// A tail lamp's glow beside a headlamp's: a red lamp is dimmer.
    static let tailStrength: Float = 0.8
    /// The most train lamps glowing in a frame.
    public static let mostTrainSpots = 256

    /// The glows of `frame`'s trains' lamps, in the scene: each train's
    /// first car's headlamps and last car's tail lamps
    /// (``Map3DTrains/Frame/ends``), placed as ``Map3DTrainLights/add(to:pack:lights:)``
    /// places the lamps; at most ``mostTrainSpots``.
    public static func trainSpots(of frame: Map3DTrains.Frame, pack: Map3DModelPack) -> [Spot] {
        var spots: [Spot] = []
        for end in frame.ends where frame.instances.indices.contains(end.instance) {
            let instance = frame.instances[end.instance]
            guard let car = pack.lights[instance.model], instance.transform.count == 16 else { continue }
            let lamps = car.lamps(atFront: end.atFront)
            let t = instance.transform
            let x = Map3DPoint(t[0], t[1], t[2]), y = Map3DPoint(t[4], t[5], t[6]), z = Map3DPoint(t[8], t[9], t[10])
            let origin = Map3DPoint(t[12], t[13], t[14])
            for var spot in end.isTail ? lamps.tailGlows : lamps.headGlows {
                guard spots.count < mostTrainSpots else { return spots }
                let c = spot.centre
                spot.centre = origin + x * c.x + y * c.y + z * c.z
                spots.append(spot)
            }
        }
        return spots
    }

    // MARK: - Drawing

    /// Whether the map draws glows: as the real buildings' street fronts
    /// are drawn (decision 460's two axes): not when it draws fewer pixels
    /// (Battery Saver, Low Power Mode or a hot phone) nor on the lowest
    /// tier's rungs, nor while the frames run over budget and the map
    /// draws fewer pixels for it (`overBudget`). Reduce Motion does not
    /// touch them: nothing moves.
    public static func draws(quality: Map3DQuality, lowPower: Bool, heat: Map3DQuality.Heat, tier: Map3DDeviceTier?,
                             overBudget: Bool = false) -> Bool {
        !overBudget && Map3DRealFacade.draws(quality: quality, lowPower: lowPower, heat: heat, tier: tier)
    }

    /// Whether a frame with the city's lights on `lights` (``Map3DLighting/lights``)
    /// has glows to draw: none by day.
    public static func shows(lights: Float) -> Bool { lights > 0.02 }

    /// The narrowest a glow is drawn, as an angle from the eye (radians):
    /// some 2 pixels on a phone, so a far light stays a point of light.
    public static let narrowest: Float = 0.0025
    /// How far from the eye glows are drawn, metres; they fade out over
    /// the last 40 %.
    public static let reach: Float = 2_400
    /// The glow's brightness at its middle, at full strength.
    public static let peak: Float = 0.45

    /// The radius a glow of `radius` is drawn with `distance` metres from
    /// the eye: never narrower than ``narrowest``.
    public static func drawnRadius(_ radius: Float, distance: Float) -> Float {
        max(radius, distance * narrowest)
    }

    /// How strong a glow of `radius` is `distance` metres from the eye, 0
    /// to 1: dimmer as it is drawn wider than it is (a far light), none
    /// within a few radii of the eye (the eye in its own light, a cab
    /// behind its headlamps) and none past ``reach``.
    public static func strength(radius: Float, distance: Float) -> Float {
        let drawn = drawnRadius(radius, distance: distance)
        let near = smoothstep(radius * 1.2, radius * 3, distance)
        let far = 1 - smoothstep(reach * 0.6, reach, distance)
        return radius / drawn * near * far
    }

    /// How bright a glow is `along` its radius (0 its middle, 1 its edge):
    /// a soft bell, nothing at the edge.
    public static func falloff(_ along: Float) -> Float {
        let q = min(max(along, 0), 1)
        let edge = exp(-4.5 as Float)
        return max(0, (exp(-4.5 * q * q) - edge) / (1 - edge)) + 0.35 * exp(-30 * q * q)
    }

    /// The 8 floats the glows' shader reads beside the uniforms: the eye's
    /// right and up (the way a glow's square faces), the city's lights
    /// times whether glows are drawn, and the lit windows' glow
    /// (``windowGlow``).
    public static func axes(eye: Map3DPoint, target: Map3DPoint, lights: Float) -> [Float] {
        let forward = (target - eye).normalized ?? Map3DPoint(0, 0, -1)
        let right = forward.cross(.up).normalized ?? Map3DPoint(1, 0, 0)
        let up = right.cross(forward).normalized ?? .up
        return [right.x, right.y, right.z, peak * min(max(lights, 0), 1), up.x, up.y, up.z, 0]
    }

    /// How much of a lit window's light falls on the wall round it, at
    /// the room's middle (`map3dShade`, the uniforms' `shade.z`).
    public static let windowGlow: Float = 0.16

    static func smoothstep(_ low: Float, _ high: Float, _ x: Float) -> Float {
        guard high > low else { return x < low ? 0 : 1 }
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
