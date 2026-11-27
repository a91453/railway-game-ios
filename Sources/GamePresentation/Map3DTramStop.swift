import Foundation
import GameCore

/// Decision 1033: the local studio's unroofed street-tram stop
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tram-stop-unroofed-2026-11/revision-2`;
/// lessons in `docs/studio/lessons/tram-stop-unroofed.md`), a generic
/// one, not any real stop: a low island 20 m long and 0.35 m high, a
/// 3 m ramp at each end, the yellow strip along the rail side, a railing
/// along the street side, a bench and a sign post; no roof. Written here
/// by `tools/landmarks/glb_to_swift.py` (``encoded``): +X along the
/// track, +Y away from it (the rail side's edge at 0), z 0 the rails.
///
/// It stands in place of the game's platform and canopy where a street
/// tram stops (``stands(track:structure:length:island:)``): beside
/// embedded track on the ground, on a side platform no longer than one
/// stop holds. A longer platform (a light rail's of 34 m sets, which
/// have canopies, as Kaohsiung's and Danhai's do) stays as it was.
enum Map3DTramStop {
    /// Its materials' colours, in `glb_to_swift.py --materials` order:
    /// platform, platformEdge, arcade, steel, white, timber, dark.
    static let palette: [UInt32] = [
        Map3DPalette.platform, Map3DPalette.platformEdge, Map3DPalette.arcade, Map3DPalette.steel,
        Map3DPalette.tileWhite, Map3DPalette.timber, Map3DPalette.dark,
    ]
    /// Its top over the rails, metres: a low-floor tram's floor.
    static let top: Float = 0.35
    /// How far it reaches back from the rail side's edge, metres.
    static let width: Float = 2.4
    /// Its length over the ramps, and the longest platform drawn as it.
    static let length: Float = 26
    static let longest: Float = 30

    /// Whether a platform of `length` metres beside track of `track`'s
    /// kind laid as `structure` is a tram stop: embedded track on the
    /// ground, a side platform (not half an `island`) one stop long.
    static func stands(track: Map3DTrackKind?, structure: TrackStructure, length: Float, island: Bool) -> Bool {
        track == .embedded && structure == .surface && !island && length <= longest
    }

    /// The model in full close by, or its far model; empty if it does not
    /// decode (`Map3DTramStopTests` keeps that from happening).
    static func model(full: Bool) -> LandmarkMesh {
        let name = full ? "tram-stop-unroofed" : "tram-stop-unroofed-far"
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let mesh = LandmarkMesh.decodedLandmark(Array(data), full: full, palette: palette, glass: [])
        else { return LandmarkMesh(full: full) }
        return mesh
    }

    /// The model placed with the middle of its rail side's edge at
    /// `edge` (its foot at `edge`'s height), reaching back towards
    /// `back` (level, a unit vector) from the track running along
    /// `along`.
    static func placed(full: Bool, edge: Map3DPoint, along: Map3DPoint, back: Map3DPoint) -> Map3DMesh {
        // The model's +Y is to the left of its +X seen from above: in the
        // scene (z south) the left of (x, z) is (z, −x).
        let left = Map3DPoint(along.z, 0, -along.x)
        let forward = left.dot(back) >= 0 ? along : along * -1
        let rotation = atan2(-forward.z, forward.x) * 180 / .pi
        return model(full: full).placed(origin: Map3DPoint(edge.x, 0, edge.z), ground: edge.y, rotation: rotation)
    }
}
