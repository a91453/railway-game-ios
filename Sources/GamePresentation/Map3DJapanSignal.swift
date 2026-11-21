import Foundation

/// Decision 921: Japan's traffic signal on Fukuoka's map, in place of
/// Taiwan's (``Map3DProp/signalGo``) that stood there with no model of its
/// own. The owner's own model from the earlier version (its list's
/// 「三灯式信号」), written here by `tools/fukuoka-map/japan_signal.py`
/// (``encoded``) in the game's colours: a galvanised post at the left kerb
/// (Japan keeps left), an arm reaching right over the lanes, and a pale grey
/// horizontal head of three lights, green next to the post, amber, red at
/// the arm's end, each under its hood, the lights the game's own
/// (``Map3DProp/signalLights``). One model a light it shows; Japan has no
/// red and amber together, so that light shows red.
public enum Map3DJapanSignal {
    /// The models, by their names in ``Map3DModelPack``.
    public enum Unit: String, CaseIterable, Sendable {
        case red = "jp-signal-red"
        case amber = "jp-signal-amber"
        case green = "jp-signal-green"
    }

    /// The colours of the mesh's palette indices, in the tool's order:
    /// steel, tankSteel, dark, red_lit, red_unlit, amber_lit, amber_unlit,
    /// green_lit, green_unlit. All the game's own: the post's galvanised
    /// grey (``Map3DPalette/steel``), the head's pale grey
    /// (``Map3DPalette/tankSteel``), the signals' housing for the lenses'
    /// rings (``Map3DProp/signalHousing``) and the signals' lights.
    static let meshPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.tankSteel, Map3DProp.signalHousing,
        Map3DProp.signalLights[0].lit, Map3DProp.signalLights[0].unlit,
        Map3DProp.signalLights[1].lit, Map3DProp.signalLights[1].unlit,
        Map3DProp.signalLights[2].lit, Map3DProp.signalLights[2].unlit,
    ]

    /// The colours that glow: a lit light.
    static let lit: Set<UInt32> = [Map3DProp.signalLights[0].lit, Map3DProp.signalLights[1].lit, Map3DProp.signalLights[2].lit]

    /// The model showing `light`'s lamp lit.
    static func modelName(_ light: Map3DSignalTiming.Light) -> String {
        switch light {
        case .red, .redAmber: Unit.red.rawValue
        case .amber: Unit.amber.rawValue
        case .green: Unit.green.rawValue
        }
    }

    /// The model a signal of `road` is placed with (as
    /// ``Map3DHongKongSignal/placedName(_:)``).
    static func placedName(_ road: Map3DSignalTiming.Road) -> String {
        modelName(Map3DSignalTiming.steady(road))
    }

    /// The three models, for ``Map3DModelPack``: after the yellow tit and
    /// before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Unit.allCases.compactMap { model($0) }.map(Map3DLook.restyle)
    }

    /// `unit`'s model, looking toward −x (the traffic it faces comes from
    /// −x, as ``Map3DProp/signalGo``'s) with its arm toward −y, the
    /// traffic's right; `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        let name = unit.rawValue
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
        else { return nil }
        let vertices = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            if lit.contains(vertex.color) { vertex.layer = Map3DVertex.glowing }
            return vertex
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }
}
