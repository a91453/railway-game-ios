import Foundation

/// Decision 846's later note: Finland's own street furniture, in place of
/// the Hong Kong signals, Taiwan's pedestrian faces with no countdown,
/// Taiwan's street light and Taiwan's bus stop that decision 846 stood on
/// Rovaniemi's streets until these were made. Modelled by the local studio
/// from photographs (Commons; Helsinki, Kuopio and Rovaniemi), one palette
/// colour a triangle, and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``):
///
/// - the traffic signal: a round galvanised post 3.6 m tall at the kerb, a
///   black upright head of three 30 cm lights, each under its hood, red
///   over amber over green, one model a light it shows (red, red and
///   amber, amber, green; the lights' heights are Hong Kong's, so the
///   clock and the places are decision 732's);
/// - the pedestrian signal: a black head of two lights, a red figure
///   standing over a green one walking, still and with no countdown, and
///   a push button on its post;
/// - the street light: a tapered galvanised pole 10 m tall, one arm
///   slanting up, a flat head lit underneath;
/// - the bus stop: a blue plate with a white bus on a galvanised post;
/// - the pedestrian crossing's sign: a blue square, a white triangle and
///   a dark figure walking, on a short post.
///
/// No word, crest or operator's mark is drawn.
public enum Map3DFinlandStreet {
    /// The models, by their names in ``Map3DModelPack``.
    public enum Unit: String, CaseIterable, Sendable {
        case signalRed = "fi-signal-red"
        case signalRedAmber = "fi-signal-red-amber"
        case signalAmber = "fi-signal-amber"
        case signalGreen = "fi-signal-green"
        case walkStop = "fi-walk-stop"
        case walkDark = "fi-walk-dark"
        case walkWalk = "fi-walk-walk"
        case lamp = "fi-lamp"
        case busStop = "fi-bus-stop"
        case crossingSign = "fi-crossing-sign"

        /// A pedestrian signal's face.
        var isWalk: Bool { self == .walkStop || self == .walkDark || self == .walkWalk }
    }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names steel, tankSteel, dark, red_lit, red_unlit, amber_lit,
    /// amber_unlit, green_lit, green_unlit, lamp_lit, signBlue, signWhite.
    /// All the game's own colours: the galvanised steel
    /// (``Map3DPalette/steel``, brighter ``Map3DPalette/tankSteel``), the
    /// signals' housing and lights (``Map3DProp/signalHousing``,
    /// ``Map3DProp/signalLights``), the street lights' warm white
    /// (``Map3DProp/lampLight``), the signs' blue (``Map3DPalette/canopy``)
    /// and white (``Map3DPalette/sidewalk``).
    static let meshPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.tankSteel, Map3DProp.signalHousing,
        Map3DProp.signalLights[0].lit, Map3DProp.signalLights[0].unlit,
        Map3DProp.signalLights[1].lit, Map3DProp.signalLights[1].unlit,
        Map3DProp.signalLights[2].lit, Map3DProp.signalLights[2].unlit,
        Map3DProp.lampLight, Map3DPalette.canopy, Map3DPalette.sidewalk,
    ]

    /// The colours that glow: a signal's lit lights, the street light's
    /// head and the push button's lit strip.
    static let lit: Set<UInt32> = [
        Map3DProp.signalLights[0].lit, Map3DProp.signalLights[1].lit, Map3DProp.signalLights[2].lit, Map3DProp.lampLight,
    ]

    /// The model showing `light`'s lamps lit.
    static func modelName(_ light: Map3DSignalTiming.Light) -> String {
        switch light {
        case .red: Unit.signalRed.rawValue
        case .redAmber: Unit.signalRedAmber.rawValue
        case .amber: Unit.signalAmber.rawValue
        case .green: Unit.signalGreen.rawValue
        }
    }

    /// The model a signal of `road` is placed with (as
    /// ``Map3DHongKongSignal/placedName(_:)``).
    static func placedName(_ road: Map3DSignalTiming.Road) -> String {
        modelName(Map3DSignalTiming.steady(road))
    }

    /// The ten models, for ``Map3DModelPack``: after the pedestrian signals
    /// with no countdown and before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Unit.allCases.compactMap { model($0) }.map(Map3DLook.restyle)
    }

    /// `unit`'s model as the others of its kind stand: a traffic signal
    /// and the crossing's sign look toward −x (the traffic they face
    /// comes from −x, as ``Map3DHongKongSignal``'s), the street light's
    /// arm and the bus stop's plate are toward the model's left (the road,
    /// as ``Map3DProp/lamp``'s), and a pedestrian signal looks toward its
    /// left (as ``Map3DPedestrianSignal``'s; the studio drew it looking
    /// toward −x, so it is turned a quarter here, by swapping its axes: no
    /// sine, the same to the bit on Linux and on a Mac). `nil` if its
    /// mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        let name = unit.rawValue
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
        else { return nil }
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        let vertices = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            if lit.contains(vertex.color) { vertex.layer = Map3DVertex.glowing }
            if unit.isWalk {
                (vertex.x, vertex.y) = (vertex.y, -vertex.x)
                (vertex.nx, vertex.ny) = (vertex.ny, -vertex.nx)
            }
            low = Map3DPoint(min(low.x, vertex.x), min(low.y, vertex.y), min(low.z, vertex.z))
            high = Map3DPoint(max(high.x, vertex.x), max(high.y, vertex.y), max(high.z, vertex.z))
            return vertex
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }
}
