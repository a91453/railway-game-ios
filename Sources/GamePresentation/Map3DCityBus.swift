import Foundation

/// The city buses of the 3D map's streets (decision 259's traffic): the
/// owner's Meshy model (`docs/art/meshy-city-bus-2026-10-18/`, converted by
/// `tools/glb-to-m3dmodel/`), which the app bundles as
/// `Resources/Models/city-bus.m3dmodel` and reads once
/// (`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`). It takes the
/// place of ``Map3DStreetModel/bus``'s box-built bus in the model pack, at
/// the same index; where the file cannot be read, the box-built one stays.
public enum Map3DCityBus {
    /// The file's name and extension in the app's resources.
    public static let fileName = "city-bus"
    public static let fileExtension = "m3dmodel"

    /// A Taiwanese low-floor city bus's size, metres: the model comes 12 m
    /// long but 3.0 m wide and 3.7 m tall, wider than a lane allows, so it
    /// is drawn at these.
    public static let length: Float = 12
    public static let width: Float = 2.5
    public static let height: Float = 3.3

    /// The model pack with the bus read from `url`, or the standard pack,
    /// with its box-built bus, when there is no file, it cannot be read or
    /// it cannot be fitted (see ``canFit(_:)``).
    public static func pack(file url: URL?) -> Map3DModelPack {
        guard let url, let data = try? Data(contentsOf: url), let file = try? Map3DModelFile(decoding: data, named: fileName),
              canFit(file.model) else {
            return .standard
        }
        return Map3DModelPack.standard.replacing(model(from: file))
    }

    /// Whether `model` has some size along every axis, so
    /// ``model(from:)`` can stretch it to the bus's: a flat one would be
    /// stretched by an infinite scale (B6 of the #911–#944 review).
    static func canFit(_ model: Map3DModelPack.Model) -> Bool {
        let size = model.maximum - model.minimum
        return !model.vertices.isEmpty && size.x > 0 && size.y > 0 && size.z > 0
    }

    /// The bus from `file`: its middle at the origin, its wheels on the
    /// ground, fitted to ``length``, ``width`` and ``height``, with the
    /// lamps that light at night (the generated model has none of its own),
    /// named as ``Map3DStreetModel/bus``.
    public static func model(from file: Map3DModelFile) -> Map3DModelPack.Model {
        let source = file.model
        let size = source.maximum - source.minimum
        let scale = Map3DPoint(length / size.x, width / size.y, height / size.z)
        let middle = Map3DPoint((source.minimum.x + source.maximum.x) / 2, (source.minimum.y + source.maximum.y) / 2, source.minimum.z)
        var vertices = source.vertices.map { vertex in
            let p = vertex.position - middle
            // A stretched surface's normal leans the other way.
            let normal = Map3DPoint(vertex.nx / scale.x, vertex.ny / scale.y, vertex.nz / scale.z).normalized ?? Map3DPoint(0, 0, 1)
            return Map3DVertex(Map3DPoint(p.x * scale.x, p.y * scale.y, p.z * scale.z), normal: normal, color: vertex.color, layer: vertex.layer)
        }
        var lamps = Map3DMesh()
        addLamps(to: &lamps)
        vertices += Map3DModelPack.Model.flat(named: "", from: lamps).vertices
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        return Map3DModelPack.Model(name: Map3DStreetModel.bus.modelName, vertices: vertices, minimum: low, maximum: high)
    }

    /// The bus's headlamps, tail lamps and the destination board over the
    /// windscreen (the reference street scene's bus: an amber LED board,
    /// HANDOFF §4.3), all lit at night, in the scene's axes (x the front,
    /// y up, −z the left).
    static func addLamps(to mesh: inout Map3DMesh) {
        func lamp(_ x: Float, _ y: Float, _ z: Float, _ width: Float, _ height: Float, _ colour: UInt32) {
            let first = mesh.vertices.count
            mesh.addBox(base: Map3DPoint(x, y, z), forward: Map3DPoint(1, 0, 0), length: 0.1, width: width, height: height, top: colour, side: colour)
            mesh.makeGlowing(from: first)
        }
        let front = length / 2, back = -length / 2
        for side: Float in [-1, 1] {
            lamp(front, 0.65, side * 0.9, 0.36, 0.2, Map3DStreetModel.headlamp)
            lamp(back, 0.8, side * 0.95, 0.3, 0.3, Map3DStreetModel.tailLamp)
        }
        lamp(front, 2.75, 0, 1.6, 0.3, destinationBoard)
    }

    static let destinationBoard = Map3DColor.rgb(0xF0A93C)
}

extension Map3DModelPack {
    /// This pack with `model` in place of the one of the same name, at its
    /// index; unchanged when it has none of that name. The trains keep their
    /// indices, so their lamps and windows (decision 449) come along.
    public func replacing(_ model: Model) -> Map3DModelPack {
        guard let index = index(of: model.name) else { return self }
        var models = models
        models[index] = model
        var pack = Map3DModelPack(models: models, lights: lights)
        pack.locked = locked
        return pack
    }
}
