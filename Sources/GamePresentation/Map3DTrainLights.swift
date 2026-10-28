import Foundation

/// Decision 449: every train's lights at night, the same way on every set:
/// the headlamps lit at the train's front, the red tail lamps at its back,
/// the saloon's windows lit, as the city's lights come on
/// (``Map3DLighting/lights``).
///
/// The recipes drew their own lamps lit (``Map3DVertex/glowing``), each set
/// its own way: a cab car's model turned round at a train's back kept its
/// headlamps lit there, and a push-pull set's back power car too. So a
/// running car's model no longer lights its lamps (``unlit(_:)``, as the
/// pack is made, after the shade is baked: a lamp keeps its colour by
/// day); each frame lights the lamps of the train's first car at the end
/// it runs toward and the tail lamps of its last car at the other end
/// (``add(to:pack:lights:)``), wherever a set's cab is and whichever way
/// the train runs. An end with no tail lamps of its own shows its
/// headlamps' lenses red, and one with neither two small lamps.
///
/// The windows: a model of its own for each car's model
/// (``windowModel(of:)``, a lit pane over each window's glass, away from
/// a cab), drawn with the car's own place in the scene; its panes take the
/// colour the instance gives, ``saloon`` times how far the lights are on,
/// so they come up with the city's lights and none are drawn by day.
/// A cab's own windows stay dark, as a driver's are at night.
public enum Map3DTrainLights {
    /// A saloon's light, a little warm of white: the reference's lit
    /// window at its top (`train-lighting.js`, `interior` 1, .93, .76).
    public static let saloon = Map3DColor.rgb(0xFFEDC2)
    /// The window models' names: ``prefix`` and the car's model's.
    public static let prefix = "light-"
    /// How far a lamp's lit copy stands proud of the model's own lens, metres.
    static let proud: Float = 0.006
    /// How far from a lamp end a window is the cab's, metres.
    static let cabReach: Float = 2.8

    /// One car's lights: its lamps at each end, and its windows' model.
    public struct Car: Sendable {
        /// The lamps at its front (+x) and back, model space: the
        /// headlamps lit and the tail lamps lit, three vertices a
        /// triangle, each already glowing.
        public let front: Lamps
        public let back: Lamps
        /// The windows' model in the pack, if it has windows.
        public var windows: Int?

        public func lamps(atFront: Bool) -> Lamps { atFront ? front : back }
    }

    public struct Lamps: Sendable {
        public let head: [Map3DVertex]
        public let tail: [Map3DVertex]
    }

    /// Where a train's first car's headlamps or its last car's tail lamps
    /// are lit: the frame's instance, which end of its model (+x or not),
    /// and which lamps.
    public struct End: Equatable, Sendable {
        public let instance: Int
        public let atFront: Bool
        public let isTail: Bool

        public init(instance: Int, atFront: Bool, isTail: Bool) {
            self.instance = instance
            self.atFront = atFront
            self.isTail = isTail
        }
    }

    // MARK: - Making the pack

    /// Whether model `name` is a running car: a set's (``Map3DTrainSet``)
    /// or a style's cab, middle or pantograph car. The static studies and
    /// formations the game does not run keep their lamps as drawn.
    public static func isRunning(_ name: String) -> Bool {
        if name.hasPrefix("set-") { return true }
        let parts = name.split(separator: "-")
        guard parts.count == 2, ["cab", "car", "panto"].contains(String(parts[1])) else { return false }
        return Map3DTrainStyle.all.contains { $0.name == parts[0] }
    }

    /// `shaded` (the pack's models, decision 439's shade baked into
    /// `recipes`) with each running car's lamps no longer lit of
    /// themselves (their colour as it is), and their lights (``car(_:)``,
    /// from the recipe's colours) by index; each car's windows' model
    /// added at the end, in the cars' order.
    static func split(_ shaded: [Map3DModelPack.Model], recipes: [Map3DModelPack.Model]) -> (models: [Map3DModelPack.Model], cars: [Int: Car]) {
        precondition(shaded.count == recipes.count)
        var out = shaded
        var cars: [Int: Car] = [:]
        var windows: [Map3DModelPack.Model] = []
        for (index, model) in recipes.enumerated() where isRunning(model.name) {
            var car = car(model)
            if let pane = windowModel(of: model) {
                car.windows = recipes.count + windows.count
                windows.append(pane)
            }
            cars[index] = car
            out[index] = unlit(shaded[index])
        }
        return (out + windows, cars)
    }

    /// `model` with no triangle lit of itself (decision 450's lit glass
    /// glass still, ``Map3DVertex/trainGlass``).
    public static func unlit(_ model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        guard model.vertices.contains(where: \.glows) else { return model }
        let vertices = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            // Decision 450's lit glass stays glass, its reflection kept.
            if vertex.glows { vertex.layer = vertex.layer == Map3DVertex.trainGlassLit ? Map3DVertex.trainGlass : Map3DVertex.plain }
            return vertex
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// The lamp lenses' colours a recipe draws unlit (``Map3DTrainShell``'s
    /// dimmed lenses, decision 408's N700S-G lenses).
    static let lensColours: Set<UInt32> = [
        Map3DTrainStyle.headlamp, Map3DColor.shaded(Map3DTrainStyle.headlamp, 0.72),
        Map3DPalette.lantern, Map3DColor.shaded(Map3DPalette.lantern, 0.6), Map3DPalette.tunnelLamp,
    ]

    /// Whether `colour` is a tail lamp's red rather than a headlamp's white.
    static func isRed(_ colour: UInt32) -> Bool {
        let r = Float(colour & 0xFF), g = Float((colour >> 8) & 0xFF), b = Float((colour >> 16) & 0xFF)
        return r > 90 && r > 1.6 * g && r > 1.6 * b
    }

    /// `model`'s lamps at each end: its lit triangles and its lenses (in
    /// the outer 30 % of its length at either end), white the
    /// headlamps', red the tail lamps'. An end with only one kind shows
    /// those lenses in the other's colour too; one with none, two small
    /// lamps on its face (``madeLamps(of:atFront:)``).
    public static func car(_ model: Map3DModelPack.Model) -> Car {
        var head: [Bool: [Map3DVertex]] = [:], tail: [Bool: [Map3DVertex]] = [:]
        let reach = model.length * 0.3
        for start in stride(from: 0, to: model.vertices.count - 2, by: 3) {
            let corners = Array(model.vertices[start ..< start + 3])
            guard corners[0].glows || lensColours.contains(corners[0].color) else { continue }
            let x = (corners[0].x + corners[1].x + corners[2].x) / 3
            let front = x > 0
            guard front ? x > model.maximum.x - reach : x < model.minimum.x + reach else { continue }
            let red = isRed(corners[0].color)
            let lit = corners.map { vertex -> Map3DVertex in
                var lit = vertex
                lit.x += vertex.nx * proud
                lit.y += vertex.ny * proud
                lit.z += vertex.nz * proud
                // A dimmed lens lit as the lamp is.
                if !vertex.glows { lit.color = red ? Map3DPalette.lantern : Map3DTrainStyle.headlamp }
                lit.layer = Map3DVertex.glowing
                return lit
            }
            if red { tail[front, default: []] += lit } else { head[front, default: []] += lit }
        }
        func lamps(_ front: Bool) -> Lamps {
            var heads = head[front] ?? [], tails = tail[front] ?? []
            if heads.isEmpty && tails.isEmpty { heads = madeLamps(of: model, atFront: front) }
            if tails.isEmpty { tails = heads.map { recoloured($0, Map3DPalette.lantern) } }
            if heads.isEmpty { heads = tails.map { recoloured($0, Map3DTrainStyle.headlamp) } }
            return Lamps(head: heads, tail: tails)
        }
        return Car(front: lamps(true), back: lamps(false), windows: nil)
    }

    static func recoloured(_ vertex: Map3DVertex, _ colour: UInt32) -> Map3DVertex {
        var vertex = vertex
        vertex.color = colour
        return vertex
    }

    /// Two small square lamps, ``madeLampSize`` across, ``madeLampProud``
    /// in front of the face of `model`'s end (+x when `atFront`) at
    /// ``madeLampHeight``, ``madeLampAcross`` either side of the middle
    /// (the reference's lamps, `train-lighting.js` `createTrainLamps`), where nothing of a lamp is drawn: a
    /// coach's end or a car with no lamps of its own. None when nothing
    /// of the model is there.
    static func madeLamps(of model: Map3DModelPack.Model, atFront: Bool) -> [Map3DVertex] {
        let way: Float = atFront ? 1 : -1
        let height = max(madeLampHeight, model.maximum.z * 0.3)
        var face: Float?
        for vertex in model.vertices where abs(abs(vertex.y) - madeLampAcross) <= 0.3 && abs(vertex.z - height) <= 0.2 {
            face = max(face ?? vertex.x * way, vertex.x * way)
        }
        guard let face else { return [] }
        var vertices: [Map3DVertex] = []
        let x = (face + madeLampProud) * way, half = madeLampSize / 2, normal = Map3DPoint(way, 0, 0)
        for across in [-madeLampAcross, madeLampAcross] {
            // Counter-clockwise seen from in front of the end.
            let corners = [Map3DPoint(x, (across - half) * way, height - half), Map3DPoint(x, (across + half) * way, height - half),
                           Map3DPoint(x, (across + half) * way, height + half), Map3DPoint(x, (across - half) * way, height + half)]
            for index in [0, 1, 2, 0, 2, 3] {
                vertices.append(Map3DVertex(corners[index], normal: normal, color: Map3DTrainStyle.headlamp, layer: Map3DVertex.glowing))
            }
        }
        return vertices
    }

    static let madeLampHeight: Float = 1.25
    static let madeLampAcross: Float = 0.82
    static let madeLampProud: Float = 0.04
    static let madeLampSize: Float = 0.2

    /// `model`'s windows lit: a copy of each triangle of its sides' glass
    /// (``isGlass(_:)``, facing sideways as the reference's side glass does,
    /// `train-lighting.js` `prepareWindowLighting`; its middle between 30 % and 92 %
    /// of the car's height, wholly beyond ``cabReach`` of an end with
    /// lamps, a cab's), ``paneProud`` outside it, its colour the
    /// instance's (alpha 0) and lit from within: the windows' own shapes,
    /// the pillars and frames between them as they are. `nil` for a car
    /// with no windows, and for a locomotive: a car with no glass in the
    /// middle 40 % of its length, whose windows are its cabs' (the E500's
    /// back cab has no lamps drawn).
    public static func windowModel(of model: Map3DModelPack.Model) -> Map3DModelPack.Model? {
        // An end with lamps, lit or not, is a cab's.
        let lamps = model.vertices.filter { $0.glows || lensColours.contains($0.color) }
        let frontCab = lamps.contains { $0.x > model.maximum.x - model.length * 0.3 }
        let backCab = lamps.contains { $0.x < model.minimum.x + model.length * 0.3 }
        let middle = (model.minimum.x + model.maximum.x) / 2
        var saloon = false
        let bottom = model.maximum.z * 0.3, top = model.maximum.z * 0.92
        var vertices: [Map3DVertex] = []
        for start in stride(from: 0, to: model.vertices.count - 2, by: 3) {
            let first = model.vertices[start]
            guard !first.glows, abs(first.ny) >= 0.75, isGlass(first.color) else { continue }
            let corners = model.vertices[start ..< start + 3]
            // By the triangle's extremes, which both halves of a pane share.
            let xs = corners.map(\.x), zs = corners.map(\.z)
            let z = (zs.min()! + zs.max()!) / 2
            guard z >= bottom, z <= top else { continue }
            if frontCab, xs.max()! > model.maximum.x - cabReach { continue }
            if backCab, xs.min()! < model.minimum.x + cabReach { continue }
            if abs((xs.min()! + xs.max()!) / 2 - middle) < model.length * 0.2 { saloon = true }
            for vertex in corners {
                var pane = vertex
                pane.x += vertex.nx * paneProud
                pane.y += vertex.ny * paneProud
                pane.z += vertex.nz * paneProud
                pane.color = 0
                pane.layer = Map3DVertex.glowing
                vertices.append(pane)
            }
        }
        guard saloon else { return nil }
        return Map3DModelPack.Model(name: prefix + model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// How far a lit window stands outside its glass, metres: under the
    /// 2 cm a window's frame stands proud (rolling-stock §4).
    static let paneProud: Float = 0.005

    /// Whether `colour` is a window's glass: a shade (as a recipe shades a
    /// face by the way it turns) of the trains' glass
    /// (``Map3DTrainStyle/glass``), the TEMU1000's and TEMU2000's
    /// passenger glass, or the city's glazing (``Map3DPalette/glazing``,
    /// darkened as each recipe darkens it); not a navy body, nor the
    /// EMU800's and EMU900's black rubber round the windows.
    static func isGlass(_ colour: UInt32) -> Bool {
        guard colour >> 24 == 0xFF else { return false }
        func channel(_ c: UInt32, _ shift: UInt32) -> Float { Float((c >> shift) & 0xFF) }
        return glassShades.contains { shade in
            let share = channel(colour, 16) / channel(shade.base, 16)
            return shade.shares.contains(share) && [0, 8].allSatisfy { (shift: UInt32) in
                abs(channel(colour, shift) - share * channel(shade.base, shift)) <= 6
            }
        }
    }

    /// The glass colours and how far each is shaded.
    static let glassShades: [(base: UInt32, shares: ClosedRange<Float>)] = [
        (Map3DPalette.glazing, 0.3...0.75),
        (Map3DTrainStyle.glass, 0.6...1.1),
        (Map3DColor.rgb(0x405560), 0.6...1.1),
    ]

    // MARK: - Each frame

    /// The lights of `frame`'s trains, `lights` the share the city's are on
    /// (``Map3DLighting/lights``), none by day: each car's windows' model
    /// as an instance of its own, its colour ``saloon`` times `lights`; each
    /// train's first car's headlamps and last car's tail lamps
    /// (``Map3DTrains/Frame/ends``) added to its boxes, lit.
    public static func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, lights: Float) {
        guard lights > 0, !pack.lights.isEmpty else { return }
        let r = Float(saloon & 0xFF) / 255, g = Float((saloon >> 8) & 0xFF) / 255, b = Float((saloon >> 16) & 0xFF) / 255
        let share = min(lights, 1)
        for instance in frame.instances {
            guard let windows = pack.lights[instance.model]?.windows else { continue }
            frame.instances.append(Map3DInstance(model: windows, transform: instance.transform, stripe: (r * share, g * share, b * share)))
        }
        for end in frame.ends where frame.instances.indices.contains(end.instance) {
            let instance = frame.instances[end.instance]
            guard let car = pack.lights[instance.model], instance.transform.count == 16 else { continue }
            let lamps = car.lamps(atFront: end.atFront)
            let t = instance.transform
            let x = Map3DPoint(t[0], t[1], t[2]), y = Map3DPoint(t[4], t[5], t[6]), z = Map3DPoint(t[8], t[9], t[10])
            let origin = Map3DPoint(t[12], t[13], t[14])
            let along = x.normalized ?? x
            let triangles = end.isTail ? lamps.tail : lamps.head
            for start in stride(from: 0, to: triangles.count - 2, by: 3) {
                frame.boxes.appendTriangle(triangles[start ..< start + 3].map { vertex in
                    let normal = along * vertex.nx + y * vertex.ny + z * vertex.nz
                    return Map3DVertex(origin + x * vertex.x + y * vertex.y + z * vertex.z, normal: normal.normalized ?? normal,
                                       color: vertex.color, layer: Map3DVertex.glowing)
                })
            }
        }
    }
}
