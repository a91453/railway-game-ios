import Foundation
import GameCore

/// Decision 1042: a ground station in Japan (decision 802's
/// ``Map3DRegionLook/Buildings/japan``) from the owner's earlier version's
/// general ground station: its three station buildings, its 20 m
/// platform canopies and its platform-end railing. The local studio
/// turned them into the game's palette at half their old size (the old
/// version drew its buildings larger than life; `a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1`,
/// #662), and `tools/old-models/old_ground_station.py` made them the
/// game's own (owner, 2026-11-28: like the old ones, not the same): the
/// small station's hip roof in the station green with a dark edge, a
/// name board in the sign blue on each building, the middle one's
/// entrance canopy green, the canopies' roofs the game's canopy blue and
/// the railing its platform-edge yellow (``meshPalette``).
///
/// Which building: a station of one platform keeps the wooden station
/// (decision 922), two take the small one (`s`), three or more or a
/// bigger concourse the middle one (`m`), a big station the big one
/// (`l`); a halt keeps its shelter (``building(profile:tier:expansion:)``).
///
/// The models' own space is the generic station's (decision 899):
/// metres, +x along the platforms, +y towards them (the back), +z up,
/// the ground at z 0. The canopies' +y is the track side, their posts at
/// x 0.40 of a unit 20 m long from x 0; the railing stands at x −0.30,
/// the platform's end at x 0 and the platform towards −x.
enum Map3DOldGroundStation {
    enum Building: String, CaseIterable, Sendable { case s, m, l }

    /// The colours of the mesh's palette indices, in the order of the
    /// tool's `MATERIALS`: the studio's 13 (revision-1 README §4), the
    /// canopy roof and the railing the game's own canopy and platform
    /// edge, then the game's sign blue and station green.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.cityOfficeWalls[3], Map3DPalette.concrete, Map3DPalette.stone,
        Map3DPalette.canopy, Map3DPalette.steel, Map3DPalette.roofSlate, Map3DPalette.timberSiding,
        Map3DPalette.shopColours[6], Map3DPalette.shadedGlass, Map3DPalette.tinAwnings[3], Map3DPalette.dark,
        Map3DPalette.platformEdge, Map3DPalette.canopy, Map3DPalette.gymGreen,
    ]

    /// The canopy unit's length along the platform, metres.
    static let canopyUnit: Float = 20
    /// The side canopy's roof across (y −1.54 to 1.34) and the island
    /// one's (6.0 m); the side one's post stands 1.20 m behind its
    /// middle line, its roof's underside 3.96 m up (the island's 3.80).
    static let sideCanopyWidth: Float = 2.88, islandCanopyWidth: Float = 6
    static let sideCanopyUnderside: Float = 3.96, islandCanopyUnderside: Float = 3.80
    /// The canopies' top, metres above the platform.
    static let canopyTop: Float = 4.40

    /// The heights a platform's lamps hang and its signs' tops stand
    /// under these canopies, metres over the platform: the lamps just
    /// under the roof over the edge half (4.1 m and more there), the
    /// signs under the beam by the posts (the island one's 3.56 m).
    static let lampHeight: Float = 3.85
    static let signTop: Float = 3.5

    /// The canopy units over a platform `length` long, the canopy over its
    /// middle `share` (``Map3DStationKit/canopyShare(_:)``): units of
    /// about ``canopyUnit``, `count` of them, each `step` long from
    /// `from`, drawn `stretch` times the unit's length (a little longer,
    /// so the pieces meet on a curve).
    static func units(length: Float, share: Float) -> (from: Float, step: Float, count: Int, stretch: Float) {
        let span = length * share, from = length * (1 - share) / 2
        let count = max(1, Int((span / canopyUnit).rounded())), step = span / Float(count)
        return (from, step, count, (step + 0.3) / canopyUnit)
    }

    /// Where the canopies' posts stand along a platform `length` long
    /// (``units(length:share:)``): one at the start of each unit and the
    /// last unit's closing one at its end.
    static func posts(length: Float, share: Float) -> [Float] {
        let units = units(length: length, share: share)
        guard units.step > 0 else { return [] }
        let inset = (canopyUnit / 2 - 0.4) * units.stretch
        return (0..<units.count).map { units.from + (Float($0) + 0.5) * units.step - inset }
            + [units.from + (Float(units.count) - 0.5) * units.step + inset]
    }

    /// A canopy unit's model-space triangles (`island` or side), with the
    /// last unit's closing post (its post and brace again, 19.2 m on) when
    /// `last`.
    static func canopyUnit(island: Bool, last: Bool) -> [Map3DVertex] {
        let unit = last ? (island ? lastIslandUnit : lastSideUnit) : (island ? islandUnit : sideUnit)
        return unit
    }
    private static let sideUnit = model("canopy-side")?.vertices ?? []
    private static let islandUnit = model("canopy-island")?.vertices ?? []
    private static let lastSideUnit = withClosingPost(sideUnit)
    private static let lastIslandUnit = withClosingPost(islandUnit)
    /// The railing's model-space triangles.
    static let railing = model("end-side")?.vertices ?? []

    private static func withClosingPost(_ unit: [Map3DVertex]) -> [Map3DVertex] {
        var post: [Map3DVertex] = []
        for start in stride(from: 0, to: unit.count, by: 3) where unit[start..<start + 3].allSatisfy({ $0.x <= 0.6 }) {
            post += unit[start..<start + 3].map { var v = $0; v.x += canopyUnit - 0.8; return v }
        }
        return unit + post
    }

    /// Model-space triangles `vertices` in a platform's frame (x along, y
    /// up, z to the right, as ``Map3DMesh/append(_:at:forward:)`` takes
    /// it): moved `alongShift` and `acrossShift` (model metres), then
    /// stretched `along` times along and `across` times across, the
    /// model's +x along the platform (`forward`) or against it, its +y
    /// (the track side) to the platform's left (`trackLeft`) or right.
    static func placed(_ vertices: [Map3DVertex], alongShift: Float = 0, acrossShift: Float = 0, along: Float, across: Float,
                       forward: Bool = true, trackLeft: Bool) -> Map3DMesh {
        let fa: Float = forward ? 1 : -1, fc: Float = trackLeft ? 1 : -1
        let mirrored = fa * fc < 0
        var mesh = Map3DMesh()
        for start in stride(from: 0, to: vertices.count, by: 3) {
            var corners = vertices[start..<start + 3].map { v in
                let normal = Map3DPoint(fa * v.nx / along, v.nz, -fc * v.ny / across)
                return Map3DVertex(Map3DPoint(fa * along * (v.x + alongShift), v.z, -fc * across * (v.y + acrossShift)),
                                   normal: normal.normalized ?? normal, color: v.color, layer: v.layer)
            }
            if mirrored { corners.swapAt(1, 2) }
            mesh.appendTriangle(corners)
        }
        return mesh
    }

    /// The model `name` (a building's raw value, `canopy-side`,
    /// `canopy-island`, `end-side`), near or `far` (the buildings alone
    /// have far versions); `nil` if its mesh does not decode.
    static func model(_ name: String, far: Bool = false) -> Map3DModelPack.Model? {
        let key = name + (far && Building(rawValue: name) != nil ? "-far" : "")
        guard let text = encoded[key], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: "old-port-station-ground-" + key, palette: meshPalette)
    }

    /// The building a station of `profile`, `tier` (the kit's class, 0
    /// the busiest: four less the platforms) and `expansion` takes in
    /// Japan, or `nil` for the wooden station (one platform) or the
    /// halt's shelter.
    static func building(profile: Map3DStationKit.Profile, tier: Int, expansion: StationExpansion?) -> Building? {
        guard profile == .regional else { return nil }
        switch expansion {
        case .hall: return .l
        case .concourse: return .m
        case nil: return tier <= 1 ? .m : tier == 2 ? .s : nil
        }
    }
}

extension StationKitBuilder {
    /// Decision 1042: the old ground station's `building` with its back
    /// (+y) at x `back`, towards −x, the kit's platform side, as
    /// ``japanStation(back:far:)`` lays the wooden one.
    mutating func oldGroundStation(_ building: Map3DOldGroundStation.Building, back: Float, far: Bool = false) {
        guard let model = Map3DOldGroundStation.model(building.rawValue, far: far) else { return }
        add(model, at: Map3DPoint(back + model.maximum.y, 0.25, 0), angle: -Float.pi / 2)
    }
}
