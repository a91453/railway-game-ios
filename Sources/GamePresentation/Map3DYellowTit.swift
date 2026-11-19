import Foundation

/// Decision 889: the station master's bird in 3D. Now and then by day a
/// Taiwan yellow tit (黃山雀, *Machlolophus holsti*, the 2D station master
/// of decision 122) flies along the platform the camera is looking at,
/// lands on it for a few seconds and flies on: one bird at a time, never
/// at night, underground or with Reduce Motion on.
///
/// The local studio modelled it from photographs in four poses, perched,
/// wings up, wings down and gliding, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/yellow-tit-2026-11/revision-3`), at a real
/// bird's 13 cm; ``encoded`` holds them six times larger
/// (`tools/train-models/glb_to_swift.py --scale 6`), about a pigeon's
/// size, since a real tit is under a pixel from the game's cameras.
public enum Map3DYellowTit {
    /// The models: perched, and three of its undulating flight.
    public enum Pose: String, CaseIterable, Sendable {
        case perch = "tw-yellow-tit-perch"
        case wingsUp = "tw-yellow-tit-wings-up"
        case wingsDown = "tw-yellow-tit-wings-down"
        case glide = "tw-yellow-tit-glide"
    }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names titYellow, titBelly, titNavy, titWhite, titDark. The game's
    /// own colours (the brief's table): the player's warm yellow, its
    /// paler roof for the belly, its navy rim for the cap, crest and wings
    /// (decision 889 keeps the navy over the photographs' brighter blue),
    /// the pavement's white and the dark of beak, eyes and feet.
    static let meshPalette: [UInt32] = [
        Map3DPalette.player, Map3DPalette.playerRoof, Map3DPalette.playerRim, Map3DPalette.sidewalk, Map3DPalette.dark,
    ]

    /// `pose`'s model, its beak along +x, its feet (perched) or its body's
    /// middle (flying) at the origin; `nil` if its mesh does not decode.
    public static func model(_ pose: Pose) -> Map3DModelPack.Model? {
        guard let text = encoded[pose.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
        else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: pose.rawValue, palette: meshPalette)
    }

    /// The four poses, after Finland's street furniture and before the
    /// route bus. Only near models: the bird is drawn only close up.
    static var drawn: [Map3DModelPack.Model] { Pose.allCases.compactMap(model) }

    // MARK: When and where

    /// A visit may begin every `every` seconds, by the device's clock; two
    /// in three do (``visits(_:)``), so the bird comes about every two
    /// minutes and not like clockwork.
    public static let every: Double = 80
    /// A visit: flying in, perched, flying on, seconds.
    static let flyIn: Double = 3.5
    static let perched: Double = 4
    static let flyOut: Double = 3.5
    static var visit: Double { flyIn + perched + flyOut }
    /// How far before (and after) its spot it flies in (and on), metres,
    /// and how high it starts (and ends) above the platform.
    static let approach: Float = 18
    static let height: Float = 6
    /// The flying models' middles stand this high over their feet when
    /// perched (the studio's 3.6 cm, six times), metres.
    static let body: Float = 0.216
    /// Its undulating flight: three flaps (wings up, then down, each
    /// ``beat`` long), then a glide, ``bout`` in all, seconds.
    static let beat: Double = 0.07
    static let bout: Double = 0.62

    /// Seen only when the camera looks from within this, metres, at a
    /// platform this near what it looks at.
    public static let cameraReach: Float = 220
    public static let platformReach: Float = 60

    /// Whether visit number `number` happens.
    static func visits(_ number: Int64) -> Bool {
        var x = UInt64(bitPattern: number) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 31
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 29
        return x % 3 != 0
    }

    /// Whether the bird is visiting at `seconds`, wherever the camera is:
    /// a check cheap enough for every frame before the platforms are
    /// looked at.
    public static func isVisiting(at seconds: Double) -> Bool {
        let number = Int64((seconds / every).rounded(.down))
        return seconds - Double(number) * every < visit && visits(number)
    }

    /// The bird drawn now: its pose, where (its feet perched, its middle
    /// flying) and the way its beak faces.
    public struct Drawn: Equatable, Sendable {
        public let pose: Pose
        public let point: Map3DPoint
        public let forward: Map3DPoint
    }

    /// The bird at `seconds` (the device's clock) on the platform nearest
    /// `target` among `platforms` (``Map3DStreetLife/Spot`` of kind
    /// platform: a line on its top), for a camera at `eye`; `nil` at
    /// night (`daytime` false), with Reduce Motion on (`still`), between
    /// visits, with the camera far away, no platform near `target`, or the
    /// platform `underground`.
    public static func drawn(at seconds: Double, platforms: [Map3DStreetLife.Path], target: Map3DPoint, eye: Map3DPoint,
                             daytime: Bool, still: Bool, underground: (Map3DPoint) -> Bool = { _ in false }) -> Drawn? {
        guard daytime, !still, (eye - target).length <= cameraReach, isVisiting(at: seconds) else { return nil }
        let number = Int64((seconds / every).rounded(.down))
        let t = seconds - Double(number) * every
        // The platform whose line passes nearest the camera's target.
        var best: (path: Map3DStreetLife.Path, along: Float, away: Float)?
        for path in platforms where path.length >= 6 {
            let found = nearest(on: path, to: target)
            if found.away < platformReach, found.away < best?.away ?? .infinity { best = (path, found.along, found.away) }
        }
        guard let best else { return nil }
        let at = best.path.at(min(max(best.along, 2), best.path.length - 2))
        guard !underground(at.point) else { return nil }
        // Which way it flies, by the visit.
        let way: Float = number % 2 == 0 ? 1 : -1
        let forward = at.along * way
        if t < flyIn {
            let e = Float(t / flyIn), left = 1 - e
            // Slowing and dropping as it comes in to land.
            let point = at.point - forward * (approach * left * left) + Map3DPoint(0, body + height * left * left, 0)
            let pose: Pose = t > flyIn - 0.45 ? .wingsUp : flight(at: t)
            return Drawn(pose: pose, point: point, forward: forward)
        }
        if t < flyIn + perched { return Drawn(pose: .perch, point: at.point, forward: forward) }
        let e = Float((t - flyIn - perched) / flyOut)
        let point = at.point + forward * (approach * e * e) + Map3DPoint(0, body + height * e * e, 0)
        return Drawn(pose: flight(at: t - flyIn - perched), point: point, forward: forward)
    }

    /// The flying pose `t` seconds into a flight: three flaps, a glide.
    static func flight(at t: Double) -> Pose {
        let inBout = t.truncatingRemainder(dividingBy: bout)
        let flap = Int(inBout / beat)
        guard flap < 6 else { return .glide }
        return flap % 2 == 0 ? .wingsDown : .wingsUp
    }

    /// How far along `path` its point nearest `target` is, and how far
    /// away on the level.
    static func nearest(on path: Map3DStreetLife.Path, to target: Map3DPoint) -> (along: Float, away: Float) {
        var best: (along: Float, away: Float) = (0, .infinity)
        var walked: Float = 0
        for (a, b) in zip(path.points, path.points.dropFirst()) {
            let dx = b.x - a.x, dz = b.z - a.z
            let span = (dx * dx + dz * dz).squareRoot()
            let t = span > 0 ? min(max(((target.x - a.x) * dx + (target.z - a.z) * dz) / (span * span), 0), 1) : 0
            let px = a.x + dx * t - target.x, pz = a.z + dz * t - target.z
            let away = (px * px + pz * pz).squareRoot()
            if away < best.away { best = (walked + span * t, away) }
            walked += span
        }
        return best
    }

    /// Adds `drawn` to `frame`; nothing when the pack lacks the model.
    public static func add(_ drawn: Drawn, to frame: inout Map3DTrains.Frame, pack: Map3DModelPack) {
        guard let index = pack.index(of: drawn.pose.rawValue) else { return }
        frame.instances.append(.prop(index, at: drawn.point, forward: drawn.forward, scale: 1, tint: 0xFFFFFF))
    }
}
