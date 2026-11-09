import GameCore

/// Decision 672: the light of a followed train's headlamps on the track
/// ahead of it in a tunnel, the cheap way: a band over the bed, its colour
/// fading from the lamps' warm white at the nose to the ballast's own
/// ``reach`` ahead, lit from within at night (``Map3DVertex/glowing``). No
/// light source and no shader of its own; drawn with the trains' boxes.
///
/// The reference's `train-lighting.js` (`tunnelAmount`) turns the lamps'
/// light up inside a tunnel; it lights the scene with a spot light, which
/// the game's one-pass vertex-colour look does not have, so here the light
/// is painted on the track it would fall on (gap: the reference has no
/// painted pool).
public enum Map3DHeadlamp {
    /// How far ahead of the nose the light reaches, and the step of the
    /// band, metres.
    public static let reach: Float = 40
    static let step: Float = 4
    /// The band's width at the nose and at its far end: within the bed's
    /// top (``Map3DScene/Builder/bedTop``, 3.4 m).
    static let nearWidth: Float = 2.2
    static let farWidth: Float = 3.2
    /// Over the bed's top, under the rails.
    static let lift: Float = 0.03
    /// The lamps' light, the palette's tunnel lamp a little whiter.
    static let colour = Map3DColor.rgb(0xFFF1CF)

    /// The rails' middle ahead of `nose` (on the rails, facing `forward`),
    /// every ``step`` to ``reach``: along `ahead` (the track ahead, seen
    /// from above; its heights are not read) as far as it goes past the
    /// nose, then straight on; each at the height of the track `cover`
    /// finds under it, or of the point before where it finds none.
    static func path(nose: Map3DPoint, forward: Map3DPoint, ahead: [Map3DPoint], cover: Map3DTrackCover) -> [Map3DPoint] {
        guard let way = Map3DPoint(forward.x, 0, forward.z).normalized else { return [] }
        var line = [Map3DPoint(nose.x, 0, nose.z)]
        for point in ahead {
            let level = Map3DPoint(point.x, 0, point.z), last = line[line.count - 1]
            guard (level - line[0]).dot(way) > 0.5, (level - last).length > 0.1 else { continue }
            line.append(level)
        }
        var travelled: [Float] = [0]
        for index in line.indices.dropFirst() { travelled.append(travelled[index - 1] + (line[index] - line[index - 1]).length) }
        if let total = travelled.last, total < reach {
            let on = line.count > 1 ? (line[line.count - 1] - line[line.count - 2]).normalized ?? way : way
            line.append(line[line.count - 1] + on * (reach - total))
            travelled.append(reach)
        }
        var path: [Map3DPoint] = []
        var height = nose.y, segment = 1
        for distance in stride(from: Float(0), through: reach, by: step) {
            while segment < line.count - 1, travelled[segment] < distance { segment += 1 }
            let span = travelled[segment] - travelled[segment - 1]
            let share = span > 0 ? min(max((distance - travelled[segment - 1]) / span, 0), 1) : 0
            let level = line[segment - 1] + (line[segment] - line[segment - 1]) * share
            height = cover.railHeight(near: Map3DPoint(level.x, height, level.z), rise: 3) ?? height
            path.append(Map3DPoint(level.x, height, level.z))
        }
        return path
    }
}

extension Map3DMesh {
    /// Decision 672: the headlamps' light along `path` (the rails' middle,
    /// from the nose out, as ``Map3DHeadlamp/path(nose:forward:ahead:cover:)``
    /// lays it) on the bed's top.
    public mutating func addHeadlamp(along path: [Map3DPoint]) {
        guard path.count > 1 else { return }
        let start = vertices.count
        let across = Self.acrossDirections(path)
        let lift = Map3DPoint(0, Map3DHeadlamp.lift - Map3DScene.Builder.bedDrop, 0)
        func row(_ index: Int) -> (left: Map3DVertex, right: Map3DVertex) {
            let share = Float(index) / Float(path.count - 1)
            let half = (Map3DHeadlamp.nearWidth + (Map3DHeadlamp.farWidth - Map3DHeadlamp.nearWidth) * share) / 2
            // Bright near the lamps, falling off faster than linearly.
            let colour = Map3DHeadlamp.mix(Map3DHeadlamp.colour, Map3DPalette.ballast, share.squareRoot())
            let middle = path[index] + lift
            return (Map3DVertex(middle - across[index] * half, normal: .up, color: colour),
                    Map3DVertex(middle + across[index] * half, normal: .up, color: colour))
        }
        var before = row(0)
        for index in 1..<path.count {
            let next = row(index)
            appendTriangle([before.left, next.left, next.right])
            appendTriangle([before.left, next.right, before.right])
            before = next
        }
        makeGlowing(from: start)
    }
}

extension Map3DHeadlamp {
    /// `from` turned `share` (0–1) of the way to `to`, both opaque.
    static func mix(_ from: UInt32, _ to: UInt32, _ share: Float) -> UInt32 {
        let t = min(max(share, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Float((from >> shift) & 0xFF), b = Float((to >> shift) & 0xFF)
            return UInt32((a + (b - a) * t).rounded()) << shift
        }
        return channel(0) | channel(8) | channel(16) | 0xFF00_0000
    }
}

extension Map3DTrackCover {
    /// Decision 672: the rails' height of the piece of track nearest
    /// `point` seen from above, within ``reach`` of it across and `rise`
    /// up or down; `nil` where there is none.
    func railHeight(near point: Map3DPoint, rise: Float) -> Float? {
        guard let near = cells[Self.key(x: point.x, z: point.z)] else { return nil }
        var best: (distance: Float, height: Float)?
        for index in near {
            let piece = pieces[index]
            let along = Map3DPoint(piece.b.x - piece.a.x, 0, piece.b.z - piece.a.z)
            let squared = along.dot(along)
            guard squared > 0 else { continue }
            let share = min(max(Map3DPoint(point.x - piece.a.x, 0, point.z - piece.a.z).dot(along) / squared, 0), 1)
            let on = piece.a + (piece.b - piece.a) * share
            let distance = Map3DPoint(point.x - on.x, 0, point.z - on.z).length
            guard distance <= 2 * Self.reach, abs(point.y - on.y) <= rise else { continue }
            if best.map({ distance < $0.distance }) ?? true { best = (distance, on.y) }
        }
        return best?.height
    }
}
