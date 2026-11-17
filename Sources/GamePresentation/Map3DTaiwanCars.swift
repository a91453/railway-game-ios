import Foundation

// Decision 838: the cars of Taiwan's streets. Decision 259's were a box
// with a glass wedge on it (110 triangles), its wheels inside the body.
// These are four Kenney Car Kit models (CC0) from the owner's reference
// repository (`Railway/town-scene-reference-clean`), reshaped by
// `tools/tw-cars/reshape.mjs`: each face in the game's colour for its part,
// ten-sided wheels, the cabin's sides in glass, stretched to a real car's
// size (a Corolla Altis, a Corolla Cross, a Town Ace van; the taxi the
// saloon with its roof sign), about a thousand triangles each, half Hong
// Kong's taxi. The app bundles them; where a file cannot be read, the
// box-built one stands in (``Map3DStreetModel``).

/// Decision 838: Taiwan's saloon, SUV, van and yellow taxi.
public enum Map3DTaiwanCars {
    /// The four, the saloon and the van in their old places in the pack
    /// (decision 259's), the SUV and the taxi after the winter
    /// decorations and Santa's sleigh, before the route bus.
    public static let models: [Map3DStreetModel] = [.car, .van, .suv, .yellowTaxi]
    /// The two the pack had no place for.
    static let added: [Map3DStreetModel] = [.suv, .yellowTaxi]

    /// Their files' names in the app's resources.
    public static let fileNames: [Map3DStreetModel: String] = [.car: "tw-sedan", .van: "tw-van", .suv: "tw-suv", .yellowTaxi: "tw-taxi"]
    public static let fileExtension = "m3dmodel"

    /// Their sizes, metres, as `reshape.mjs` makes them: a Corolla Altis
    /// (4.63 × 1.78 × 1.44 m), a Corolla Cross (4.46 × 1.83 × 1.62), a
    /// Town Ace or short Hiace van (4.7 × 1.75 × 1.95), the taxi the
    /// saloon with its sign on top.
    public static func size(_ model: Map3DStreetModel) -> (length: Float, width: Float, height: Float) {
        switch model {
        case .suv: (4.46, 1.83, 1.62)
        case .van: (4.7, 1.75, 1.95)
        case .yellowTaxi: (4.63, 1.78, 1.66)
        default: (4.63, 1.78, 1.44)
        }
    }

    /// The colour `reshape.mjs` paints the body (the street cars' white,
    /// ``Map3DStreetLife/carPaints``' first): the instance's paint.
    static let filePaint = Map3DColor.rgb(0xF2F3F1)

    /// Which car a draw `share` from 0 to 1 is, among the cars of a
    /// Taiwanese street: saloons 45 %, SUVs 40 % (most new cars sold in
    /// Taiwan this decade are crossovers), vans 15 %.
    static func streetModel(_ share: Float) -> Map3DStreetModel {
        share < 0.45 ? .car : share < 0.85 ? .suv : .van
    }

    /// The box-built stand-ins of ``added``, for the pack.
    static var drawn: [Map3DModelPack.Model] { added.map { $0.model() } }

    /// `pack` with the cars read from `files` in place of the box-built
    /// ones, each where its file can be read.
    public static func pack(_ pack: Map3DModelPack, files: [Map3DStreetModel: URL]) -> Map3DModelPack {
        var pack = pack
        for model in models {
            guard let url = files[model], let name = fileNames[model], let data = try? Data(contentsOf: url),
                  let file = try? Map3DModelFile(decoding: data, named: name), Map3DCityBus.canFit(file.model) else { continue }
            pack = pack.replacing(self.model(model, from: file))
        }
        return pack
    }

    /// `model` from `file` (the converter has put its middle at the origin
    /// and its wheels on the ground, in metres), named as `model`, its
    /// body in the instance's colour.
    public static func model(_ model: Map3DStreetModel, from file: Map3DModelFile) -> Map3DModelPack.Model {
        let source = file.model
        let vertices = source.vertices.map { vertex in
            var vertex = vertex
            if vertex.color == filePaint { vertex.color &= 0x00FF_FFFF }
            return vertex
        }
        return Map3DModelPack.Model(name: model.modelName, vertices: vertices, minimum: source.minimum, maximum: source.maximum)
    }
}
