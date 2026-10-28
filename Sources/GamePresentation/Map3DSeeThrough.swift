import Foundation

/// ARCHITECTURE decision 342: the buildings between the eye and the
/// player's trains are seen through (the art direction's "鏡頭和列車之間的建物
/// 變透明", docs/art/3d-style-2026-10-13/README.md). Round the line from the
/// eye to each of up to ``most`` cars, a cone widening to ``radius`` at the
/// car, whatever of the city stands in front of the car and over its rails
/// is drawn at ``opacity``: the Metal view gives it that alpha with four
/// samples a pixel turned into coverage (alpha to coverage), so it needs no
/// sorting, and the train shows through where the building would hide it.
///
/// The cars chosen are the ones nearest the middle of the view, within
/// ``Map3DTrains/modelReach`` of the eye: those the player looks at, the
/// followed train first, since the follow camera looks at it.
/// `Map3DShaders.metal`'s `map3dSeeThroughFragment` works out
/// ``opacity(at:)`` the same way; change both together.
public struct Map3DSeeThrough: Equatable, Sendable {
    /// At most this many cars a frame (the shader's array).
    public static let most = 16
    /// The cone's radius at the car, in metres: a 20 m car (decision 205)
    /// and a few metres round it.
    public static let radius: Float = 14
    /// How much of a building in the cone still shows (one sample in four
    /// of a pixel's).
    public static let opacity: Float = 0.25
    /// Only what stands this far over the car's rails is seen through, so
    /// the ground, the roads and the track round the car stay as they are.
    public static let clearance: Float = 0.5
    /// Nor what stands within this many metres of the car's middle along
    /// the line from the eye: beside it or behind it, which hides nothing.
    public static let beside: Float = 3
    /// The cone's axis meets the car this high over its rails, the middle
    /// of its body.
    public static let bodyMiddle: Float = Map3DTrains.carHeight / 2

    public let eye: Map3DPoint
    /// The chosen cars' middles on their rails.
    public let cars: [Map3DPoint]

    /// The cars of `cars` (each car's middle on its rails,
    /// ``Map3DTrains/Frame/cars``) seen through `matrix` (the camera's
    /// ``Map3DCamera/viewProjection``) from `eye`: none farther than
    /// ``Map3DTrains/modelReach`` or out of view, at most ``most``, nearest
    /// the middle of the view first.
    public init(eye: Map3DPoint, cars: [Map3DPoint], matrix: Map3DMatrix) {
        self.eye = eye
        var seen: [(car: Map3DPoint, off: Float)] = []
        for car in cars where (car - eye).length <= Map3DTrains.modelReach {
            guard let clip = matrix.project(car + Map3DPoint(0, Self.bodyMiddle, 0)), clip.z >= 0, clip.z <= 1,
                  abs(clip.x) <= 1.2, abs(clip.y) <= 1.2 else { continue }
            seen.append((car, clip.x * clip.x + clip.y * clip.y))
        }
        seen.sort { $0.off < $1.off }
        self.cars = seen.prefix(Self.most).map(\.car)
    }

    /// How much of a building's point `p` shows: ``opacity`` well inside a
    /// cone, 1 outside them all, between at a cone's rim.
    public func opacity(at p: Map3DPoint) -> Float {
        var shown: Float = 1
        let v = p - eye
        for car in cars where p.y > car.y + Self.clearance {
            let d = car + Map3DPoint(0, Self.bodyMiddle, 0) - eye
            let length = d.length
            guard length > Self.beside else { continue }
            let along = v.dot(d) / length
            guard along > 0, along < length - Self.beside else { continue }
            let t = along / length
            let off = (v - d * (along / length)).length / (Self.radius * t)
            let rim = Self.smoothstep(0.7, 1, off)
            shown = min(shown, Self.opacity + (1 - Self.opacity) * rim)
        }
        return shown
    }

    /// Whether chunk (`column`, `row`) may hold city a cone sees
    /// through, by its ``Map3DScene/Chunk/cityTops``: some cone passes
    /// over a square whose top stands over the car's rails and reaches up
    /// into the cone. The Metal view draws such a chunk's city with the
    /// see-through pipeline, and every other chunk as before.
    public func cuts(column: Int, row: Int, tops: [Float]) -> Bool {
        guard !cars.isEmpty, tops.count == Self.cells * Self.cells else { return false }
        let side = Map3DScene.chunkSize, square = side / Float(Self.cells)
        let west = Float(column) * side, north = Float(row) * side
        let highest = tops.max() ?? -.infinity
        for car in cars where highest > car.y + Self.clearance {
            let middle = car + Map3DPoint(0, Self.bodyMiddle, 0)
            let grow = Map3DPoint(Self.radius, Self.radius, Self.radius)
            guard Self.segment(from: eye, to: middle, meets: Map3DPoint(west, -.infinity, north) - grow,
                               Map3DPoint(west + side, highest, north + side) + grow) else { continue }
            let length = (middle - eye).length
            guard length > Self.beside else { continue }
            let end = length - Self.beside
            // Along the line every ``step`` metres, each square the cone
            // may reach there (half a step more each way).
            var along: Float = 0
            while along < end + Self.step {
                let at = min(along, end)
                let p = eye + (middle - eye) * (at / length)
                let reach = Self.radius * at / length + Self.step / 2
                let low = Int(((p.x - reach - west) / square).rounded(.down)), high = Int(((p.x + reach - west) / square).rounded(.down))
                let top = Int(((p.z - reach - north) / square).rounded(.down)), bottom = Int(((p.z + reach - north) / square).rounded(.down))
                if low < Self.cells, high >= 0, top < Self.cells, bottom >= 0 {
                    for row in max(top, 0)...min(bottom, Self.cells - 1) {
                        for column in max(low, 0)...min(high, Self.cells - 1) {
                            let stands = tops[row * Self.cells + column]
                            if stands > car.y + Self.clearance, stands > p.y - reach { return true }
                        }
                    }
                }
                along += Self.step
            }
        }
        return false
    }

    /// A chunk's city tops are kept in this many squares a side (64 m,
    /// the city's lots).
    public static let cells = 8
    /// How far apart along a cone ``cuts(column:row:tops:)`` looks.
    static let step: Float = 16

    /// The highest point of the triangles of each mesh from its index
    /// given on, and of `boxes` (decision 455), in each square of chunk
    /// (`column`, `row`) (``Map3DScene/Chunk/cityTops``).
    static func tops(column: Int, row: Int, of meshes: [(mesh: Map3DMesh, first: Int)], boxes: [Map3DBoxInstance] = []) -> [Float] {
        var tops = [Float](repeating: -.infinity, count: cells * cells)
        let side = Map3DScene.chunkSize, square = side / Float(cells)
        let west = Float(column) * side, north = Float(row) * side
        for (mesh, first) in meshes where first < mesh.indices.count {
            for index in mesh.indices[first...] {
                let vertex = mesh.vertices[Int(index)]
                let x = min(max(Int(((vertex.x - west) / square).rounded(.down)), 0), cells - 1)
                let z = min(max(Int(((vertex.z - north) / square).rounded(.down)), 0), cells - 1)
                tops[z * cells + x] = max(tops[z * cells + x], vertex.y)
            }
        }
        for box in boxes {
            for corner in box.topCorners {
                let x = min(max(Int(((corner.x - west) / square).rounded(.down)), 0), cells - 1)
                let z = min(max(Int(((corner.z - north) / square).rounded(.down)), 0), cells - 1)
                tops[z * cells + x] = max(tops[z * cells + x], corner.y)
            }
        }
        return tops
    }

    /// The floats the see-through fragment shader reads
    /// (`Map3DSeeThroughCars` in `Map3DShaders.metal`): ``most`` rows of
    /// a car's middle on its rails, then how many cars, ``radius``,
    /// ``opacity`` and ``clearance``, then ``beside`` and ``bodyMiddle``.
    public var floats: [Float] {
        var rows: [Float] = []
        for index in 0..<Self.most {
            let car = index < cars.count ? cars[index] : .zero
            rows += [car.x, car.y, car.z, 0]
        }
        return rows + [Float(cars.count), Self.radius, Self.opacity, Self.clearance, Self.beside, Self.bodyMiddle, 0, 0]
    }

    static func smoothstep(_ low: Float, _ high: Float, _ x: Float) -> Float {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Whether the segment from `a` to `b` meets the box from `low` to
    /// `high` (the slab test).
    static func segment(from a: Map3DPoint, to b: Map3DPoint, meets low: Map3DPoint, _ high: Map3DPoint) -> Bool {
        var enter: Float = 0, leave: Float = 1
        for (start, end, low, high) in [(a.x, b.x, low.x, high.x), (a.y, b.y, low.y, high.y), (a.z, b.z, low.z, high.z)] {
            let step = end - start
            if abs(step) < 1e-6 {
                if start < low || start > high { return false }
                continue
            }
            var t0 = (low - start) / step, t1 = (high - start) / step
            if t0 > t1 { swap(&t0, &t1) }
            enter = max(enter, t0)
            leave = min(leave, t1)
            if enter > leave { return false }
        }
        return true
    }
}
