import Foundation
import GameCore

/// Decision 929: a level crossing's warning post and its boom, from the
/// local studio's rebuild of the owner's Meshy model
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/meshy-crossing-warning-2026-11/revision-2`,
/// #303; lessons in `docs/studio/lessons/meshy-crossing-warning.md`), in
/// place of decision 263's boxes: a concrete foot, a post in yellow and
/// black, a lamp box with its two red lamps side by side under hoods, and
/// a boom of eight yellow and black lengths. Yellow and black, not the
/// boxes' red and white: Taiwan's crossings' booms are, and the model was
/// described so. Written in with `tools/train-models/glb_to_swift.py`
/// (``Map3DCrossingGateMesh``).
///
/// The models' own space: metres, +x the way the lowered boom reaches
/// (across the street), +y towards the traffic coming (the lamps' faces),
/// +z up; the post's origin under the middle of its foot, the boom's at
/// its pivot, the boom along +x.
enum Map3DCrossingGate {
    /// The colours of the mesh's palette indices, in the order given to
    /// `glb_to_swift.py`: base, stripeYellow, stripeBlack, signalRed. The
    /// black and the red are the crossings' own of decision 263
    /// (``Map3DScene/Builder/barrierBlack`` and `barrierRed`, a shade off
    /// the studio's `dark` and `lantern`): the look keeps those two as
    /// they are (``Map3DLook/functional``) and would pale the others.
    static let meshPalette: [UInt32] = [
        Map3DPalette.concrete, Map3DScene.Builder.barrierYellow, Map3DScene.Builder.barrierBlack, Map3DScene.Builder.barrierRed,
    ]

    /// The boom's pivot on the post, in the post's space.
    static let pivot = Map3DPoint(0.14, -0.27, 1)

    static func model(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    static let post = model("crossing-warning-post")
    static let arm = model("crossing-warning-arm")

    /// The post with its boom raised (turned about the pivot until its
    /// +x is up), in the post's space; `nil` if either does not decode.
    static let raised: [Map3DVertex]? = {
        guard let post, let arm else { return nil }
        return post.vertices + arm.vertices.map { v in
            Map3DVertex(Map3DPoint(-v.z, v.y, v.x) + pivot, normal: Map3DPoint(-v.nz, v.ny, v.nx), color: v.color, layer: v.layer)
        }
    }()

    /// The gate at `foot` in the scene: the model's +x along `reach`
    /// (across the street, level), its +y along `facing` (towards the
    /// traffic coming, level). Decision 941: the post alone when `boom`
    /// is `false`, its boom then drawn each frame where the trains put it
    /// (``Map3DCrossingBooms``); with its boom raised otherwise. `false`
    /// if the model does not decode.
    static func add(to mesh: inout Map3DMesh, at foot: Map3DPoint, reach: Map3DPoint, facing: Map3DPoint, boom: Bool = true) -> Bool {
        guard let vertices = boom ? raised : post?.vertices else { return false }
        let up = Map3DPoint(0, 1, 0)
        for start in stride(from: 0, to: vertices.count, by: 3) {
            mesh.appendTriangle(vertices[start..<start + 3].map { v in
                Map3DVertex(foot + reach * v.x + facing * v.y + up * v.z, normal: reach * v.nx + facing * v.ny + up * v.nz,
                            color: v.color, layer: v.layer)
            })
        }
        return true
    }

    /// Decision 941: the boom's model in the pack, in the look of the city
    /// round it (``Map3DLook/restyle(_:)``, which keeps its black and red).
    static let boomName = "crossing-warning-arm"
    static var drawn: [Map3DModelPack.Model] { arm.map { [Map3DLook.restyle($0)] } ?? [] }

    /// The boom's transform, column by column (the shader's), at `foot`
    /// with the post's `reach` and `facing`, `closed` from 0 (raised,
    /// upright) to 1 (lowered, level across the street), drawn `stretch`
    /// times its own length.
    static func boomTransform(at foot: Map3DPoint, reach: Map3DPoint, facing: Map3DPoint, closed: Float, stretch: Float = 1) -> [Float] {
        let up = Map3DPoint(0, 1, 0), angle = (1 - min(max(closed, 0), 1)) * Float.pi / 2
        let x = (reach * cos(angle) + up * sin(angle)) * stretch, z = up * cos(angle) - reach * sin(angle)
        let origin = foot + reach * pivot.x + facing * pivot.y + up * pivot.z
        return [x.x, x.y, x.z, 0, facing.x, facing.y, facing.z, 0, z.x, z.y, z.z, 0, origin.x, origin.y, origin.z, 1]
    }
}

/// Decision 941: when a level crossing's booms come down and go up, from
/// the reference's `crossingState` (`a91453/railway-reference-private`
/// `Railway/rail-reference/regions/taiwan/source/rail-3d/garage-scenes/crossing-cycle.js`):
/// the bells start 6 s before the train's front is 3.5 m from the road,
/// the booms come down over the next 2 s from 4 s before, so they are
/// down 2 s before it arrives, and stay down until its last car is 3.5 m
/// past, then 0.8 s more, and rise over 2.2 s. Seconds as the map shows
/// the trains moving, metres in the scene.
enum Map3DCrossingCycle {
    static let margin: Float = 3.5
    static let bells: Float = 6
    static let lowers: Float = 4
    static let lowering: Float = 2
    static let holds: Float = 0.8
    static let raises: Float = 3
    /// The least speed a train is taken at, metres a second: one standing
    /// on the crossing holds the booms down, one standing off it does not
    /// (the reference's trains never stand).
    static let slowest: Float = 0.5

    struct State: Equatable, Sendable {
        /// Seconds since the front came within ``margin`` of the road
        /// (below 0: until it does), and since the last car got
        /// ``margin`` past it.
        let arrival: Float
        let clear: Float
        /// The booms, 0 up, 1 down.
        let closed: Float
        let bells: Bool
        let occupied: Bool
    }

    /// The reference's `smooth`: smoothstep on 0...1.
    static func smooth(_ x: Float) -> Float {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// A train whose middle is `centre` metres past the crossing (below 0:
    /// short of it), `length` metres long, at `speed` metres a second.
    static func state(centre: Float, length: Float, speed: Float) -> State {
        let speed = max(speed, slowest)
        let arrival = (centre + length / 2 + margin) / speed, clear = (centre - length / 2 - margin) / speed
        var closed: Float = 0
        if arrival >= -lowers, clear <= holds {
            closed = smooth((arrival + lowers) / lowering)
        } else if clear > holds, clear < raises {
            closed = 1 - smooth((clear - holds) / (raises - holds))
        }
        return State(arrival: arrival, clear: clear, closed: closed, bells: arrival >= -bells && clear < raises,
                     occupied: arrival >= 0 && clear <= 0)
    }
}

/// Decision 941: each level crossing's two booms near the camera, as the
/// trains near it put them (``Map3DCrossingCycle``), drawn with the
/// trains (``Map3DTrains/Frame/instances``).
enum Map3DCrossingBooms {
    /// How far from the eye booms are drawn, metres: as far as the
    /// crossing's barriers are (``Map3DScene/Builder/Target/near``).
    static let reach: Float = 700
    /// A train is on a crossing's track when its middle is within this of
    /// the track's line across it (past its outermost tracks), metres,
    /// level with it within ``height``, and running along it.
    static let beside: Float = 3
    static let height: Float = 3
    static let along: Float = 0.8

    /// The boom's length over `crossing`'s street, metres: the reference's
    /// `Math.max(3, 2 * hw)`, the carriageway's width, so lowered it
    /// closes the whole street, not one lane (the studio's boom is 4 m).
    static func boomLength(_ crossing: Map3DLevelCrossing) -> Float {
        max(3, crossing.kind.width(ramp: false))
    }

    /// How far down `crossing`'s booms are for `heads`: the most any
    /// train on its track puts them.
    static func closed(_ crossing: Map3DLevelCrossing, heads: [Map3DTrains.Head]) -> Float {
        heads.reduce(0) { most, head in
            guard let middle = head.middle, abs(middle.y - crossing.point.y - Map3DScene.railLift) < height || abs(middle.y - crossing.point.y) < height,
                  let way = Map3DPoint(head.forward.x, 0, head.forward.z).normalized,
                  abs(way.dot(crossing.trackWay)) >= along else { return most }
            let offset = Map3DPoint(middle.x - crossing.point.x, 0, middle.z - crossing.point.z)
            let side = abs(offset.x * way.z - offset.z * way.x)
            guard side <= crossing.spread / 2 + beside else { return most }
            return max(most, Map3DCrossingCycle.state(centre: offset.dot(way), length: head.length, speed: head.speed).closed)
        }
    }

    /// The booms of `crossings` within ``reach`` of `eye` as `heads` put
    /// them, as instances of `pack`'s boom.
    static func instances(_ crossings: [Map3DLevelCrossing], heads: [Map3DTrains.Head], pack: Map3DModelPack, eye: Map3DPoint) -> [Map3DInstance] {
        guard !crossings.isEmpty, let model = pack.index(of: Map3DCrossingGate.boomName), pack.models[model].maximum.x > 0 else { return [] }
        let own = pack.models[model].maximum.x
        var placed: [Map3DInstance] = []
        for crossing in crossings where (crossing.point - eye).length < reach + crossing.rampEnd {
            let closed = closed(crossing, heads: heads)
            for (end, foot) in crossing.gateFeet {
                let transform = Map3DCrossingGate.boomTransform(at: foot, reach: crossing.across * end, facing: crossing.along * end, closed: closed,
                                                                stretch: boomLength(crossing) / own)
                placed.append(Map3DInstance(model: model, transform: transform, stripe: (0, 0, 0)))
            }
        }
        return placed
    }
}
