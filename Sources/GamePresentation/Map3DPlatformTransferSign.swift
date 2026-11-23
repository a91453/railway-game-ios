import Foundation
import GameCore

/// Decision 936: the sign on an island platform whose two tracks' lines
/// change across it (decision 912's "across the platform"): an arrow and
/// a block in the line's colour for each side, hung under the canopy's
/// end or on a post past it. The local studio's two models
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/platform-transfer-sign-2026-11/revision-2`,
/// #269; lessons in `docs/studio/lessons/platform-transfer-sign.md`),
/// written in with `tools/train-models/glb_to_swift.py` (``encoded``).
/// No words on it: the blocks' colours say which line.
///
/// The models' own space: metres, +x across the island from one track to
/// the other, +y along the platform (its two faces look along it), +z
/// up; the origin on the platform under the sign's middle. The block and
/// arrow of its -x half show on both faces and are the -x track's.
enum Map3DPlatformTransferSign {
    /// The colours of the mesh's palette indices, in the order given to
    /// `glb_to_swift.py`: frame, face, arrow, badge. The badge's is only
    /// a place holder (the studio's, the canopy's blue), which the game
    /// changes for each line's colour.
    static let meshPalette: [UInt32] = [Map3DPalette.dark, Map3DPalette.tileWhite, Map3DPalette.dark, placeholder]
    static let placeholder = Map3DPalette.canopy

    static func model(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    static let hung = model("platform-transfer-sign-hung")
    static let post = model("platform-transfer-sign-post")

    /// How far a side's second block stands from its first, towards the
    /// sign's middle (the studio's `slots.json`: `badge_2`).
    static let secondBlockHung: Float = 0.32
    static let secondBlockPost: Float = 0.26

    /// The narrowest island (its two halves together) a hung sign fits
    /// (2.4 m and 0.3 m to each edge), and a sign on a post (1.7 m).
    static let hungIsland: Float = 3
    static let postIsland: Float = 2.3
    /// A hung sign's middle inside the canopy's end (its outer face
    /// within 0.3 m of the end, where the game's camera still sees it
    /// under the roof), and a post's past it.
    static let hungInset: Float = 0.2
    static let postGap: Float = 1.2

    /// A sign `along` an island platform, hung or on a post.
    struct Place: Equatable, Sendable {
        let along: Float
        let hung: Bool
    }

    /// Where the signs stand along an island `length` long and `width`
    /// wide whose canopy covers `roof` (`nil`: no canopy of its own): one
    /// hung just inside each end of the canopy, facing out, or on a post
    /// past it where the island is too narrow to hang one or that place
    /// is `taken`; with no canopy, a post a fifth in from each end. None
    /// where what is `taken` (a footbridge's tower, a name board, a
    /// bench) leaves no room, or on an island under ``postIsland`` wide.
    static func places(length: Float, width: Float, roof: ClosedRange<Float>?, taken: [ClosedRange<Float>]) -> [Place] {
        guard width >= postIsland, length >= 10 else { return [] }
        func clear(_ at: Float) -> Bool {
            at >= 0.5 && at <= length - 0.5 && taken.allSatisfy { $0.upperBound < at - 0.3 || $0.lowerBound > at + 0.3 }
        }
        guard let roof else {
            return [length * 0.2, length * 0.8].filter(clear).map { Place(along: $0, hung: false) }
        }
        var places: [Place] = []
        for (end, out) in [(roof.lowerBound, Float(-1)), (roof.upperBound, Float(1))] {
            let hung = end - out * hungInset, post = end + out * postGap
            if width >= hungIsland, clear(hung) {
                places.append(Place(along: hung, hung: true))
            } else if clear(post) {
                places.append(Place(along: post, hung: false))
            }
        }
        return places
    }

    /// The sign in the scene: its origin at `foot` on the platform, its
    /// +x along level `across` (from the track whose lines are `near`
    /// towards the one whose are `far`), each side's block in its first
    /// line's colour and a second block beside it for a second line.
    /// `false` if the model does not decode.
    static func add(to mesh: inout Map3DMesh, at foot: Map3DPoint, across: Map3DPoint, hung: Bool, near: [UInt32], far: [UInt32]) -> Bool {
        guard let model = hung ? Self.hung : post, let nearFirst = near.first, let farFirst = far.first else { return false }
        let along = Map3DPoint.up.cross(across)
        let second = hung ? secondBlockHung : secondBlockPost
        func append(_ corners: ArraySlice<Map3DVertex>, colour: UInt32?, shift: Float = 0) {
            mesh.appendTriangle(corners.map { v in
                Map3DVertex(foot + across * (v.x + shift) + along * v.y + Map3DPoint.up * v.z,
                            normal: across * v.nx + along * v.ny + Map3DPoint.up * v.nz, color: colour ?? v.color, layer: v.layer)
            })
        }
        let vertices = model.vertices
        for start in stride(from: 0, to: vertices.count - 2, by: 3) {
            let corners = vertices[start..<start + 3]
            guard corners.allSatisfy({ $0.color == placeholder }) else {
                append(corners, colour: nil)
                continue
            }
            let isNear = corners.reduce(0) { $0 + $1.x } < 0
            append(corners, colour: isNear ? nearFirst : farFirst)
            let others = isNear ? near : far
            if others.count > 1 { append(corners, colour: others[1], shift: isNear ? second : -second) }
        }
        return true
    }
}
