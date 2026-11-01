import Foundation
import GameCore

/// Decision 517 續 (BUILD3D-2, PR 2): a tap on the 3D map while only
/// looking at it does what a tap on the 2D map does to a station (decision
/// 119: tap to look, hold to change): the station under the finger is
/// selected and its tag stands under it, here where it is drawn in 3D.
/// The finger's ground point comes from ``Map3DPick``, and the station is
/// found as the 2D map finds one (``GameSession/holdMap(at:reach:)``):
/// within half the reach first, then the whole reach, the reach being
/// ``NetworkBuilding/touchRadius`` points at the depth the finger landed.
/// Trains, buildings and track are left to the 2D map for now (decision
/// 517 續's later steps): selected in 3D, nothing there would show them.
public enum Map3DTap {
    /// How many world units ``NetworkBuilding/touchRadius`` points cover
    /// at scene point `point` seen by `camera`: the screen's metres per
    /// point at that depth (its distance from the eye along the way the
    /// camera looks), so a station afar is reached as far on the screen as
    /// one near, as on the 2D map.
    public static func reach(at point: Map3DPoint, camera: Map3DCamera) -> Int64 {
        let eye = camera.eye
        let look = (camera.target - eye).normalized ?? Map3DPoint(0, -1, 0)
        let depth = max((point - eye).dot(look), 1)
        let metresPerPoint = 2 * depth * tanf(camera.fieldOfViewTall / 2) / max(camera.viewport.height, 1)
        return Int64((Double(metresPerPoint) * NetworkBuilding.touchRadius * Double(WorldCoordinate.unitsPerMetre)).rounded())
    }

    /// Where a station's tag stands in the scene: over the station's
    /// point, at the ground there up to where track is drawn
    /// (``Map3DScene/railLift``). `nil` for an ID `world` does not have.
    public static func anchor(of id: StationID, in world: GameWorld, space: Map3DPick.Space, ground: Map3DPick.Ground) -> Map3DPoint? {
        guard let station = world.station(id: id) else { return nil }
        var point = space.point(WorldCoordinate(x: station.location.x, y: station.location.y))
        point.y = ground(point.x, point.z) + Map3DScene.railLift
        return point
    }

    /// How far under the station the tag's top stands, in points: clear of
    /// a finger still over the station.
    public static let tagGap: Float = 14
    /// How far the tag keeps from the view's edges, in points.
    public static let tagMargin: Float = 8

    /// Where the top left of a tag `width` × `height` points stands for a
    /// station drawn at (`x`, `y`) in a view `viewport` points, its edges
    /// `clear` points kept free (the controls along them): centred under
    /// the station, or over it when there is no room under; moved in to
    /// stay in the view. `nil` when the station is drawn outside the free
    /// part of the view (the tag would point at nothing).
    public static func tagOrigin(under x: Float, _ y: Float, width: Float, height: Float, viewport: (width: Float, height: Float),
                                 clear: (top: Float, leading: Float, bottom: Float, trailing: Float) = (0, 0, 0, 0)) -> (x: Float, y: Float)? {
        let left = clear.leading + tagMargin, right = viewport.width - clear.trailing - tagMargin
        let top = clear.top + tagMargin, bottom = viewport.height - clear.bottom - tagMargin
        guard x >= left, x <= right, y >= top, y <= bottom else { return nil }
        let originX = min(max(x - width / 2, left), max(right - width, left))
        let under = y + tagGap
        let originY = under + height <= bottom ? under : max(y - tagGap - height, top)
        return (originX, originY)
    }
}

extension GameSession {
    /// A tap on the 3D map that landed on `hit`, reaching `reach` world
    /// units (``Map3DTap/reach(at:camera:)``): selects the station there,
    /// as ``holdMap(at:reach:)`` finds one, and returns it; elsewhere lets
    /// go of what was selected, so the tag goes, and returns `nil`. Only
    /// while looking at the map (the select tool, no tutorial). Never
    /// changes the world.
    @discardableResult
    public func tapMap3D(at hit: Map3DPick.Hit, reach: Int64) -> StationID? {
        guard tool == .select, tutorial == nil else { return nil }
        if let id = holdMap(at: hit.plan, reach: reach) { return id }
        clearSelection()
        return nil
    }
}
