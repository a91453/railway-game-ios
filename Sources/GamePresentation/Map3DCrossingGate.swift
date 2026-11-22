import Foundation
import GameCore

/// Decision 929: a level crossing's warning post and its boom, from the
/// local studio's rebuild of the owner's Meshy model
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/meshy-crossing-warning-2026-11/revision-2`,
/// #303; lessons in `docs/studio/lessons/meshy-crossing-warning.md`), in
/// place of decision 263's boxes: a concrete foot, a post in yellow and
/// black, a lamp box with its two red lamps side by side under hoods, and
/// a boom of eight yellow and black lengths. Yellow and black, not the
/// boxes' red and white: Taiwan's crossings' booms are, and the model was
/// described so. Written in with `tools/train-models/glb_to_swift.py`
/// (``Map3DCrossingGateMesh``).
///
/// The models' own space: metres, +x the way the lowered boom reaches
/// (across the street), +y towards the traffic coming (the lamps' faces),
/// +z up; the post's origin under the middle of its foot, the boom's at
/// its pivot, the boom along +x.
enum Map3DCrossingGate {
    /// The colours of the mesh's palette indices, in the order given to
    /// `glb_to_swift.py`: base, stripeYellow, stripeBlack, signalRed. The
    /// black and the red are the crossings' own of decision 263
    /// (``Map3DScene/Builder/barrierBlack`` and `barrierRed`, a shade off
    /// the studio's `dark` and `lantern`): the look keeps those two as
    /// they are (``Map3DLook/functional``) and would pale the others.
    static let meshPalette: [UInt32] = [
        Map3DPalette.concrete, Map3DScene.Builder.barrierYellow, Map3DScene.Builder.barrierBlack, Map3DScene.Builder.barrierRed,
    ]

    /// The boom's pivot on the post, in the post's space.
    static let pivot = Map3DPoint(0.14, -0.27, 1)

    static func model(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    static let post = model("crossing-warning-post")
    static let arm = model("crossing-warning-arm")

    /// The post with its boom raised (turned about the pivot until its
    /// +x is up), in the post's space; `nil` if either does not decode.
    static let raised: [Map3DVertex]? = {
        guard let post, let arm else { return nil }
        return post.vertices + arm.vertices.map { v in
            Map3DVertex(Map3DPoint(-v.z, v.y, v.x) + pivot, normal: Map3DPoint(-v.nz, v.ny, v.nx), color: v.color, layer: v.layer)
        }
    }()

    /// The gate at `foot` in the scene, its boom raised: the model's +x
    /// along `reach` (across the street, level), its +y along `facing`
    /// (towards the traffic coming, level). `false` if the model does
    /// not decode.
    static func add(to mesh: inout Map3DMesh, at foot: Map3DPoint, reach: Map3DPoint, facing: Map3DPoint) -> Bool {
        guard let raised else { return false }
        let up = Map3DPoint(0, 1, 0)
        for start in stride(from: 0, to: raised.count, by: 3) {
            mesh.appendTriangle(raised[start..<start + 3].map { v in
                Map3DVertex(foot + reach * v.x + facing * v.y + up * v.z, normal: reach * v.nx + facing * v.ny + up * v.nz,
                            color: v.color, layer: v.layer)
            })
        }
        return true
    }
}
