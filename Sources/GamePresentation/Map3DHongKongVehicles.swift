import Foundation

// Decision 738: Hong Kong's street traffic on its map. Taiwan's streets
// are scooters, cars and single-deck buses; Hong Kong's buses are
// double-deckers, its minibuses (小巴) are cream with a red or green roof,
// and a large part of its traffic is taxis, red in the urban area, green
// in the New Territories and blue on Lantau, with few motorcycles. The
// three come from the owner's Causeway Bay street scene
// (`Railway/street_scene_reference_clean/source/models/street-agents.glb`:
// `bus`, `minibus`, `car`), converted by `tools/glb-to-m3dmodel/bridge.mjs`
// (`tools/hk-vehicles/`), which the app bundles; where a file cannot be
// read, a box-built one of the same size stands in (``Map3DStreetModel``).

/// Decision 738: Hong Kong's double-decker, minibus and taxi.
public enum Map3DHongKongVehicles {
    /// The three, in the model pack's order (after Hong Kong's signals,
    /// before the route bus).
    public static let models: [Map3DStreetModel] = [.doubleDecker, .minibus, .taxi]

    /// Their files' names in the app's resources.
    public static let fileNames: [Map3DStreetModel: String] = [.doubleDecker: "hk-double-decker", .minibus: "hk-minibus", .taxi: "hk-taxi"]
    public static let fileExtension = "m3dmodel"

    /// Their sizes, metres: a 12 m three-axle double-decker 4.4 m tall, a
    /// 7 m minibus (a Toyota Coaster's size), a 4.4 m saloon (a Toyota
    /// Comfort's); as the reference's models are.
    public static func size(_ model: Map3DStreetModel) -> (length: Float, width: Float, height: Float) {
        switch model {
        case .doubleDecker: (12.1, 2.5, 4.4)
        case .minibus: (7.0, 2.1, 2.75)
        default: (4.4, 1.84, 1.45)
        }
    }

    /// The box-built stand-ins (the pack's own), for ``drawn``.
    static var drawn: [Map3DModelPack.Model] { models.map { $0.model() } }

    /// `pack` with the vehicles read from `files` in place of the
    /// box-built ones, each where its file can be read.
    public static func pack(_ pack: Map3DModelPack, files: [Map3DStreetModel: URL]) -> Map3DModelPack {
        var pack = pack
        for model in models {
            guard let url = files[model], let name = fileNames[model], let data = try? Data(contentsOf: url),
                  let file = try? Map3DModelFile(decoding: data, named: name), Map3DCityBus.canFit(file.model) else { continue }
            pack = pack.replacing(self.model(model, from: file))
        }
        return pack
    }

    /// `model` from `file`: fitted to its ``size(_:)``, its middle at the
    /// origin and its wheels on the ground, named as `model`. The
    /// double-decker's and the taxi's white paint is the instance's
    /// colour (as the converter marks it); the minibus's white roof is
    /// (its red or green), its cream body its own (the converter leaves
    /// its colours as they are); the taxi's roof stays
    /// silver, with its roof sign.
    public static func model(_ model: Map3DStreetModel, from file: Map3DModelFile) -> Map3DModelPack.Model {
        let source = file.model
        let extent = source.maximum - source.minimum
        let size = size(model)
        let scale = Map3DPoint(size.length / extent.x, size.width / extent.y, size.height / extent.z)
        let middle = Map3DPoint((source.minimum.x + source.maximum.x) / 2, (source.minimum.y + source.maximum.y) / 2, source.minimum.z)
        var vertices = source.vertices.map { vertex in
            let p = vertex.position - middle
            let normal = Map3DPoint(vertex.nx / scale.x, vertex.ny / scale.y, vertex.nz / scale.z).normalized ?? Map3DPoint(0, 0, 1)
            let point = Map3DPoint(p.x * scale.x, p.y * scale.y, p.z * scale.z)
            var colour = vertex.color
            switch model {
            // The minibus's roof, white in the reference (which paints it
            // as it runs), and nothing else of it white above its windows.
            case .minibus where colour & 0x00FF_FFFF == 0x00FF_FFFF && point.z > size.height - 0.5: colour &= 0x00FF_FFFF
            case .taxi where colour >> 24 == 0 && normal.z > 0.8 && point.z > size.height - 0.2: colour = roofSilver
            default: break
            }
            return Map3DVertex(point, normal: normal, color: colour, layer: vertex.layer)
        }
        if model == .taxi {
            var sign = Map3DMesh()
            addRoofSign(to: &sign, height: size.height)
            vertices += Map3DModelPack.Model.flat(named: "", from: sign).vertices
        }
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        return Map3DModelPack.Model(name: model.modelName, vertices: vertices, minimum: low, maximum: high)
    }

    /// The taxi's lit roof sign, white, on a roof `height` up, in the
    /// scene's axes (x the front, y up, −z the left).
    static func addRoofSign(to mesh: inout Map3DMesh, height: Float) {
        let first = mesh.vertices.count
        mesh.addBox(base: Map3DPoint(-0.25, height - 0.02, 0), forward: Map3DPoint(1, 0, 0), length: 0.24, width: 0.5, height: 0.16,
                    top: roofSign, side: roofSign)
        mesh.makeGlowing(from: first)
    }

    /// The taxis' paint: red (the urban taxis), green (the New
    /// Territories') and blue (Lantau's), about as many as are licensed
    /// (some 15,250, 2,840 and 75: the Transport Department's figures).
    public static let taxiPaints: [(paint: UInt32, share: Float)] = [
        (Map3DColor.rgb(0xC8302C), 0.84), (Map3DColor.rgb(0x3E9A4A), 0.996), (Map3DColor.rgb(0x3B7CC4), 1),
    ]
    /// The minibuses' roofs: red (no fixed route) and green (a fixed one).
    public static let minibusRoofs: [UInt32] = [0xC8302C, 0x2E8B57].map(Map3DColor.rgb)
    /// The double-deckers' paint: silver-grey and red (the largest
    /// operator's two liveries) and yellow (the other's).
    public static let busPaints: [UInt32] = [0xD7D9DC, 0xC63A33, 0xF2B230].map(Map3DColor.rgb)

    static let roofSilver = Map3DColor.rgb(0xC9CDD2)
    static let roofSign = Map3DColor.rgb(0xF4F1E6)
    static let cream = Map3DColor.rgb(0xEFE3C2)

    /// Hong Kong's vehicle `kind` (a draw from 0 to 1) on a lane where
    /// motorcycles may ride: few motorcycles; taxis a quarter of the
    /// traffic, minibuses one in twenty.
    static func streetModel(_ kind: Float, scooters: Bool) -> Map3DStreetModel {
        if scooters, kind < 0.03 { return .scooter }
        return kind < 0.55 ? .car : kind < 0.8 ? .taxi : kind < 0.85 ? .minibus : .van
    }

    /// The paint of a Hong Kong `model` by a draw `pick` from 0 to 1, or
    /// `nil` for a model whose paint is Taiwan's.
    static func paint(_ model: Map3DStreetModel, pick: Float) -> UInt32? {
        switch model {
        case .taxi: return taxiPaints.first { pick < $0.share }?.paint ?? taxiPaints[0].paint
        case .minibus: return minibusRoofs[min(Int(pick * Float(minibusRoofs.count)), minibusRoofs.count - 1)]
        case .doubleDecker: return busPaints[min(Int(pick * Float(busPaints.count)), busPaints.count - 1)]
        default: return nil
        }
    }
}
