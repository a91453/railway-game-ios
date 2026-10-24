/// Decision 394: whether the cab view is deep in a tunnel, where nothing
/// on the ground can be seen, so the 3D map draws only what is under it:
/// each chunk's ground, track and roads (``Map3DScene/Chunk/baseIndexCount``,
/// where the tunnels' bores and portals are), the trains and their
/// shadows; not the city, its far and closest detail, the street
/// furniture, signs, street life, the sun's shadow map, the ground's
/// shadows, rain or sky. Nothing is let go: the city's meshes stay, so
/// the frame it is drawn again it is all there.
///
/// Only view state, worked out a frame at a time from the last frame's
/// answer, so it does not flicker at the edge: it starts leaving the
/// ground out only when every opening is farther and further out of
/// view than it must be to draw it all again (``hideMargin``).
public struct Map3DUnderground: Equatable, Sendable {
    /// Whether this frame leaves out what is on the ground.
    public private(set) var isUnderground = false

    public init() {}

    /// How near an opening, any way round, the eye draws everything, in
    /// metres: a train at 300 km/h runs it in 3 s, and the bore may bend
    /// so an opening behind a curve shows only at the last moment.
    public static let near: Float = 300
    /// How far past ``near``, and past the view's edges, an opening must
    /// be for the cab to start leaving the ground out, as a share.
    public static let hideMargin: Float = 1.25
    /// The box round an opening that counts as seeing it, in metres
    /// either side of it and up from the rails: the portal's head wall
    /// (``Map3DScene/Builder/portalShoulder`` past a 3.2 m bore, the
    /// crown 6 m and 1.3 m over it) and the daylight past it.
    static let openingHalfWidth: Float = 12
    static let openingHeight: Float = 12

    /// The answer for this frame: the camera follows `head`'s train from
    /// `view` (`nil`: no train followed), `flying` while it moves into or
    /// out of that view, seeing `camera`; `openings` are where the tunnels
    /// open (``Map3DTrackCover/openings``).
    public mutating func update(view: Map3DFollow.View?, head: Map3DTrains.Head?, flying: Bool,
                                camera: Map3DCamera, openings: [Map3DPoint]) {
        guard view == .cab, !flying, let head, head.inTunnel else {
            isUnderground = false
            return
        }
        // Already underground: back on the ground as soon as an opening is
        // in reach; on the ground: under it only when all are well out.
        let margin: Float = isUnderground ? 1 : Self.hideMargin
        isUnderground = !Self.seesOpening(camera: camera, openings: openings, margin: margin)
    }

    /// Whether an opening is within ``near`` (times `margin`) of `camera`'s
    /// eye, or in its view (its box grown by `margin`) as far as it draws.
    static func seesOpening(camera: Map3DCamera, openings: [Map3DPoint], margin: Float) -> Bool {
        let eye = camera.eye
        let near = Self.near * margin, sight = camera.depthRange.far * margin
        let matrix = camera.viewProjection
        let half = Self.openingHalfWidth * margin, height = Self.openingHeight * margin
        for opening in openings {
            let distance = (opening - eye).length
            if distance <= near { return true }
            guard distance <= sight else { continue }
            if Map3DCamera.sees(minimum: opening - Map3DPoint(half, half, half), maximum: opening + Map3DPoint(half, height, half), through: matrix) {
                return true
            }
        }
        return false
    }
}
