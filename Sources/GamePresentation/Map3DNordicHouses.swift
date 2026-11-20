import Foundation

/// NORDIC-HOUSES: Finland's wooden houses and blocks of flats, as the
/// local studio modelled them in Blender from photographs (Rovaniemi,
/// Oulu and Helsinki; `a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/nordic-houses-2026-11/revision-3`), one
/// material a colour the game gives each building, written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``):
///
/// - `nordic-house-a`: a house of a floor and a half under a pitched roof,
///   an attic window in each gable, a small porch at one end
///   (9.0 × 7.5 m, the ridge 6.8 m);
/// - `nordic-house-b`: a long house of one floor, a gabled porch on its
///   front (12.0 × 7.0 m, 5.2 m);
/// - `nordic-house-c`: a square house of two floors under a gentler roof,
///   a flat porch with a balcony over it (8.5 × 8.0 m, 8.0 m);
/// - `nordic-block-3` and `nordic-block-5`: blocks of flats of three and
///   five floors, flat-roofed, a row of windows to each floor, the stair
///   windows half a floor up and a stack of balconies at each end
///   (24 × 11 m, 10 m; 30 × 12 m, 16 m).
///
/// Boards or plaster in one colour, white corner boards and window frames,
/// a concrete plinth, a dark door. A building of the map
/// (``Map3DScene/Builder/addRealBuilding(_:ground:height:storeys:kind:)``)
/// whose outline one of them fits within a fifth either way is drawn as
/// it, near, in its own wall and roof colours (decision 802's); afar, and
/// any other, as the box it was.
enum Map3DNordicHouses {
    /// The models, by their names in ``encoded``, and their bodies' size
    /// (along x and y, without the porches and balconies), metres.
    enum Unit: String, CaseIterable, Sendable {
        case houseA = "nordic-house-a"
        case houseB = "nordic-house-b"
        case houseC = "nordic-house-c"
        case block3 = "nordic-block-3"
        case block5 = "nordic-block-5"

        var body: (length: Float, width: Float) {
            switch self {
            case .houseA: (9.0, 7.5)
            case .houseB: (12.0, 7.0)
            case .houseC: (8.5, 8.0)
            case .block3: (24.0, 11.0)
            case .block5: (30.0, 12.0)
            }
        }

        var isBlock: Bool { self == .block3 || self == .block5 }
    }

    /// The studio's materials, in the order `glb_to_swift.py --materials`
    /// gave them: wall, roof, trim, glass, door, plinth, chimney, balcony,
    /// panel. A model is decoded with each triangle's colour its material's
    /// index here, and given its building's colours when it is laid.
    enum Material: Int, CaseIterable {
        case wall, roof, trim, glass, door, plinth, chimney, balcony, panel
    }

    /// How far a model is stretched to an outline, either way: a fifth.
    static let stretch: ClosedRange<Float> = 0.8...1.2

    /// Each model, its triangles' colours their materials' indices (+x
    /// along its length, +y its back, +z up, its body's middle at the
    /// origin, the ground at z 0); `nil` if its mesh does not decode.
    static let models: [Unit: Map3DModelPack.Model] = {
        var models: [Unit: Map3DModelPack.Model] = [:]
        let indices = Material.allCases.map { UInt32($0.rawValue) }
        for unit in Unit.allCases {
            guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
                  let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: indices)
            else { continue }
            models[unit] = model
        }
        return models
    }()

    /// The model a building of `kind` and `storeys` whose outline's box is
    /// `length` by `width` metres is drawn as, if one fits it: a house of
    /// one or two floors under a pitched roof (`pitched`) the house of its
    /// floors whose body is nearest its box, a block of flats of three or
    /// four floors the three-floor block, of five or six the five-floor
    /// one; each only within ``stretch`` of its box both ways.
    static func unit(kind: Map3DScene.Builder.RealKind, storeys: Int, pitched: Bool, length: Float, width: Float) -> Unit? {
        let candidates: [Unit]
        switch kind {
        case .house where pitched, .shophouse where pitched:
            candidates = storeys >= 2 ? [.houseC, .houseA] : [.houseB, .houseA]
        case .flats where (3...4).contains(storeys):
            candidates = [.block3]
        case .flats where (5...6).contains(storeys):
            candidates = [.block5]
        default:
            return nil
        }
        func misfit(_ unit: Unit) -> Float {
            max(abs(length / unit.body.length - 1), abs(width / unit.body.width - 1))
        }
        guard let best = candidates.min(by: { misfit($0) < misfit($1) }),
              stretch.contains(length / best.body.length), stretch.contains(width / best.body.width)
        else { return nil }
        return best
    }

    /// The colours of `unit`'s materials for a building of `wall` and
    /// `roof`: a white wall's trim, balconies and plinth a step deeper
    /// (``Map3DNordic/trim``), so its corner boards and window frames
    /// still show.
    static func colours(wall: UInt32, roof: UInt32) -> [UInt32] {
        let white = Map3DNordic.houseWalls[3]
        let shown = Map3DLook.colour(wall)
        let pale = shown & 0xFF >= 0xE0 && shown >> 8 & 0xFF >= 0xE0 && shown >> 16 & 0xFF >= 0xE0
        let trim = pale ? Map3DNordic.trim : white
        return [wall, roof, trim, Map3DPalette.glazing, Map3DPalette.dark, Map3DNordic.trim, Map3DNordic.blockWalls[5], trim,
                Map3DNordic.blockWalls[3]]
    }
}

extension Map3DMesh {
    /// NORDIC-HOUSES: `model` (``Map3DNordicHouses/models``) stood on
    /// `base`, its length along level `forward`, stretched `scale` along
    /// and across, each triangle in `colours`' colour of its material, its
    /// back (+y) toward `forward`'s left when `backLeft`, its right when
    /// not.
    mutating func appendNordic(_ model: Map3DModelPack.Model, at base: Map3DPoint, forward: Map3DPoint,
                               scale: (along: Float, across: Float), colours: [UInt32], backLeft: Bool) {
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(1, 0, 0)
        let turn: Float = backLeft ? 1 : -1
        // A rotation (x along, y across, z up), so each face keeps its outward side.
        let x = along * turn, y = Map3DPoint.up.cross(along) * turn
        for start in stride(from: 0, to: model.vertices.count - 2, by: 3) {
            let corners = (start..<start + 3).map { index -> Map3DVertex in
                let v = model.vertices[index]
                let at = base + x * (v.x * scale.along) + y * (v.y * scale.across) + Map3DPoint(0, v.z, 0)
                let normal = (x * (v.nx / scale.along) + y * (v.ny / scale.across) + Map3DPoint(0, v.nz, 0)).normalized ?? .up
                let colour = Int(v.color) < colours.count ? colours[Int(v.color)] : colours[0]
                return Map3DVertex(at, normal: normal, color: colour, u: 0, v: 0, layer: Map3DVertex.plain)
            }
            appendTriangle(corners)
        }
    }
}
