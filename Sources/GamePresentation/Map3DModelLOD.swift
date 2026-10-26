import Foundation

/// Decision 420: which of a model's levels is drawn how far from the eye.
///
/// Each model of the pack gets lighter versions from
/// ``Map3DMeshSimplifier`` (``shares`` of its triangles), the box past
/// ``Map3DTrains/modelReach`` as before. The distances are a phone's at
/// the middle quality; `reach` stretches them: below 1 a lighter level
/// comes nearer (low quality, or a frame running late), above 1 farther (a
/// device with room to spare). A hand-made far model (decisions 408, 410)
/// stands in for the levels it is at least as light as.
public enum Map3DModelLOD {
    /// The share of a model's triangles each level keeps, whole first.
    public static let shares: [Double] = [1, 0.5, 0.25, 0.1]

    /// How far, metres, each level is drawn at `reach` 1: the whole model
    /// within the first, the next level within the second and so on, the
    /// last level to ``Map3DTrains/modelReach``.
    public static let distances: [Float] = [150, 300, 500]

    /// The level (an index into ``shares``) of a model `distance` metres
    /// from the eye, `nil` past ``Map3DTrains/modelReach``·`reach` (a box).
    public static func level(at distance: Float, reach: Float = 1) -> Int? {
        let scale = max(reach, 0.1)
        guard distance < Map3DTrains.modelReach * max(scale, 1) else { return nil }
        return distances.firstIndex { distance < $0 * scale } ?? distances.count
    }

    /// The levels after the whole of `model`, one for each of ``shares``
    /// past the first.
    public static func levels(of model: Map3DModelPack.Model) -> [Map3DModelPack.Model] {
        model.simplified(to: Array(shares.dropFirst()))
    }
}
