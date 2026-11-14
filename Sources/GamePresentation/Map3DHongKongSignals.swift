import Foundation

// Decision 732: Hong Kong's traffic signals. Taiwan's (decision 355) hang a
// level head over the lanes from an arm at the right-hand kerb; Hong Kong
// drives on the left and stands its signals at the kerb on short posts, the
// head upright, red over amber over green, and before green shows red and
// amber together (the Transport Department's Road Users' Code, chapter 8,
// "Traffic lights for drivers and riders"). This project's own low-poly
// shape in decision 355's colours: a square post 3.6 m tall and a head of three
// 30 cm lights in a dark housing, one model a light it shows (red, red and
// amber, amber, green), as decision 429's three.

/// Decision 732: Hong Kong's traffic signals' models.
public enum Map3DHongKongSignal {
    /// The model showing `light`'s lamps lit.
    static func modelName(_ light: Map3DSignalTiming.Light) -> String {
        switch light {
        case .red: "hk-signal-red"
        case .redAmber: "hk-signal-red-amber"
        case .amber: "hk-signal-amber"
        case .green: "hk-signal-green"
        }
    }

    /// The model a signal of `road` is placed with: as decision 429's, the
    /// main road's green, the crossing road's red (what they show while
    /// the lights do not change).
    static func placedName(_ road: Map3DSignalTiming.Road) -> String {
        modelName(Map3DSignalTiming.steady(road))
    }

    /// The four models, for ``Map3DModelPack``: after the coaches and
    /// before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Map3DSignalTiming.Light.allCases.map { Map3DLook.restyle(model($0)) }
    }

    /// The post's height, and the lights' middles from the top down (red,
    /// amber, green), metres.
    static let postHeight: Float = 3.6
    static let lightHeights: [Float] = [3.25, 2.9, 2.55]
    static let lens: Float = 0.3

    /// The signal showing `light`, its lights toward −x (the traffic it
    /// faces comes from −x, as decision 355's model), the post at the
    /// origin.
    static func model(_ light: Map3DSignalTiming.Light) -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        let steel = Map3DColor.rgb(0x8A9099), dark = Map3DProp.signalHousing, toward = Map3DPoint(-1, 0, 0)
        // A square post: boxes only, no sine, so the model is the same to
        // the bit on Linux and on a Mac (`hashes.lock.json`).
        mesh.addBox(base: .zero, forward: toward, length: 0.13, width: 0.13, height: postHeight, top: steel, side: steel)
        // The housing, the post up its back.
        mesh.addBox(base: Map3DPoint(-0.14, 2.35, 0), forward: toward, length: 0.22, width: 0.42, height: 1.1, top: dark, side: dark)
        let lit: Set<Int>
        switch light {
        case .red: lit = [0]
        case .redAmber: lit = [0, 1]
        case .amber: lit = [1]
        case .green: lit = [2]
        }
        for (index, height) in lightHeights.enumerated() {
            let colours = Map3DProp.signalLights[index]
            let on = lit.contains(index)
            let colour = on ? colours.lit : colours.unlit
            let start = mesh.vertices.count
            mesh.addBox(base: Map3DPoint(-0.26, height - lens / 2, 0), forward: toward, length: 0.04, width: lens, height: lens,
                        top: colour, side: colour)
            if on { mesh.makeGlowing(from: start) }
            // A hood over each light.
            mesh.addBox(base: Map3DPoint(-0.31, height + lens / 2, 0), forward: toward, length: 0.12, width: lens + 0.04, height: 0.03,
                        top: dark, side: dark)
        }
        return Map3DModelPack.Model.flat(named: modelName(light), from: mesh)
    }
}
