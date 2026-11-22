import Foundation
import GameCore

/// Decision 929: the high-speed stations of Miaoli, Changhua, Yunlin and
/// Chiayi, each the local studio's own model of it
/// (`a91453/railway-assets-private-2` `game-art-previews/docs/art/`
/// `tw-hsr-stations-miaoli-changhua-2026-11/revision-2`, #283, and
/// `tw-hsr-stations-yunlin-chiayi-2026-11/revision-2`, #284; lessons in
/// `docs/studio/lessons/tw-hsr-miaoli-changhua.md` and
/// `tw-hsr-yunlin-chiayi.md`), where the four shared the kit's one vaulted
/// box: Miaoli's grey hall on thin white columns under its wide louvred
/// roof, Changhua's blue glass hall, Yunlin's long low front with its
/// leaning struts and fins, Chiayi's glass hall under the curved roof
/// with the spiral skylight; each with its platform roof along the
/// viaduct. Written in with `tools/train-models/glb_to_swift.py
/// --centimetres` (``Map3DHSRStudioStationMesh``).
///
/// They stand as decision 625's studies do (``Map3DExteriorStudy/studio(_:)``):
/// where the real station is, turned as it is, every part in the room of
/// the game's trains and platforms left out.
///
/// The models' own space: metres, +x along the track, +y towards the
/// viaduct, −y the forecourt, +z up, the ground at z 0. The studio had
/// each station's outline but not where the track runs past it, and put
/// the viaduct from 8 to 18 m off (Chiayi's on the other side): so each
/// model's place is given by its ``origin`` and ``bearing`` such that its
/// own gap for the viaduct (``viaduct``) lies on OpenStreetMap's tracks,
/// its hall as far along them as the real one. The hall then stands up to
/// 18 m nearer the track than the real one does.
enum Map3DHSRStudioStation: String, CaseIterable, Sendable {
    case miaoli, changhua, yunlin, chiayi

    /// The catalog's station (``Map3DStationKit/stations``).
    var stationID: String {
        switch self {
        case .miaoli: "station-thsr_sched-05d76b99"
        case .changhua: "station-thsr_sched-ae29d34f"
        case .yunlin: "station-thsr_sched-94389daf"
        case .chiayi: "station-thsr_sched-f19347cc"
        }
    }

    /// Where the model's origin stands (degrees north, east): the middle
    /// of OpenStreetMap's outline of the hall (ways 393303365, 407489848,
    /// 580143150, 286901503, read 2026-11-22; © OpenStreetMap
    /// contributors, ODbL), moved across the track until ``viaduct`` is
    /// on the middle of OpenStreetMap's tracks there.
    var origin: (latitude: Double, longitude: Double) {
        switch self {
        case .miaoli: (24.605436, 120.825565)
        case .changhua: (23.874256, 120.574796)
        case .yunlin: (23.736341, 120.416328)
        case .chiayi: (23.459199, 120.323273)
        }
    }

    /// The compass bearing of the model's +x, degrees: the long side of
    /// OpenStreetMap's outline, the way that puts +y on the viaduct.
    var bearing: Float {
        switch self {
        case .miaoli: 64.3
        case .changhua: 236.4
        case .yunlin: 20
        case .chiayi: 184
        }
    }

    /// The model's y of the middle of its gap for the viaduct.
    var viaduct: Float {
        switch self {
        case .miaoli: 7.8
        case .changhua: 30.9
        case .yunlin: 22.45
        case .chiayi: 52
        }
    }

    /// The hall's and the platform roof's rectangles in the model's own
    /// metres (x from, to; y from, to), as the studio's notes give them.
    var rectangles: [(x0: Float, x1: Float, y0: Float, y1: Float)] {
        switch self {
        case .miaoli: [(-44.3, 44.3, -44.3, 44.3), (-243.3, 209.5, -11.85, 27.45)]
        case .changhua: [(-68.6, 68.6, -21.75, 21.75), (-192.3, 136.5, 6.05, 55.75)]
        case .yunlin: [(-66, 66, -48.9, -4), (-187.35, 187.35, -4, 48.9)]
        case .chiayi: [(-56.1, 56.1, -29.2, 29.2), (-150, 150, 33, 71)]
        }
    }

    /// The materials given to `glb_to_swift.py`, in its order: window,
    /// wall, roof, stone, hall_lit, column, louvre, mullion, glass,
    /// column2, glassDark, ground, fin, strut, roofEdge, skylight.
    private static let lit = 4

    /// The colours of those materials for this station (the models'
    /// colour tables, each the game's own slot; a material a station has
    /// none of is its neighbour's). Two stations give one name two
    /// colours (`roof`, `glass`, `column`, `mullion`).
    var meshPalette: [UInt32] {
        let charcoal = Map3DPalette.mtrCharcoal, silver = Map3DPalette.mtrSilver, granite = Map3DPalette.granite
        let lamp = Map3DPalette.tunnelLamp, mast = Map3DPalette.mastSteel, white = Map3DPalette.tileWhite
        switch self {
        case .miaoli, .changhua:
            return [charcoal, Map3DPalette.portal, Map3DPalette.tankSteel, granite, lamp, white, mast, charcoal,
                    Map3DPalette.trimBlue, silver, charcoal, granite, silver, silver, white, Map3DPalette.tankSteel]
        case .yunlin, .chiayi:
            return [charcoal, Map3DPalette.portal, Map3DPalette.roof, granite, lamp, mast, mast, Map3DPalette.portal,
                    Map3DPalette.gymGreen, silver, charcoal, granite, silver, Map3DPalette.mtrFrontSilver, white, Map3DPalette.bridge]
        }
    }

    /// The model in its own space, near or `far`; `nil` if its mesh does
    /// not decode. Its hall's lamp band glows.
    func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = "station-hsr-" + rawValue + (far ? "-far" : "")
        guard let text = Self.encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, lamps: [Self.lit], perMetre: 100)
    }

    /// The model's (x, y) as metres east and north of ``origin``.
    func ground(_ x: Float, _ y: Float) -> (east: Float, north: Float) {
        let angle = bearing * .pi / 180, s = sinf(angle), c = cosf(angle)
        return (x * s - y * c, x * c + y * s)
    }

    /// ``rectangles``, metres east and north of ``origin``.
    var outlines: [[(Float, Float)]] {
        rectangles.map { r in
            [(r.x0, r.y0), (r.x1, r.y0), (r.x1, r.y1), (r.x0, r.y1)].map { let p = ground($0.0, $0.1); return (p.east, p.north) }
        }
    }

    /// The model turned to ``bearing`` as a study's mesh is kept
    /// (``Map3DExteriorStudy/mesh(detail:)``): x east, y up, z north, each
    /// triangle's turn the other way round, for
    /// ``Map3DExteriorStudy/sceneMesh(detail:)`` to mirror.
    func mesh(far: Bool) -> Map3DMesh {
        guard let model = model(far: far) else { return Map3DMesh() }
        let angle = bearing * .pi / 180, s = sinf(angle), c = cosf(angle)
        let vertices = model.vertices.map { v in
            Map3DVertex(Map3DPoint(v.x * s - v.y * c, v.z, v.x * c + v.y * s),
                        normal: Map3DPoint(v.nx * s - v.ny * c, v.nz, v.nx * c + v.ny * s), color: v.color, layer: v.layer)
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(vertices.count)
        for start in stride(from: 0, to: vertices.count, by: 3) {
            indices += [UInt32(start), UInt32(start + 2), UInt32(start + 1)]
        }
        return Map3DMesh(vertices: vertices, indices: indices)
    }
}
