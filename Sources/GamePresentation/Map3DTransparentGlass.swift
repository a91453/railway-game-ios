/// Explicit, opt-in glass for native models. Existing reflective train glass
/// stays opaque until a caller applies this adapter. No model is registered.
public enum Map3DTransparentGlass {
    /// Opacity per surface: a closed pane has an outer and an inner face.
    /// The floor is clearer than the tinted windows. No refraction is implied.
    public struct Style: Equatable, Sendable {
        public let window: Float
        public let floor: Float
        public init(window: Float = 0.14, floor: Float = 0.06) {
            self.window = window.isFinite ? min(1, max(0, window)) : 0.14
            self.floor = floor.isFinite ? min(1, max(0, floor)) : 0.06
        }
    }

    /// Input is a native model (+z up). Only explicitly marked glass changes;
    /// tint/stripe alpha, geometry, frames, seats and steel are untouched.
    /// `u` becomes opacity, `v` retains the pane's baked reflection shade.
    public static func applying(to model: Map3DModelPack.Model, style: Style = Style()) -> Map3DModelPack.Model {
        let vertices = model.vertices.map { original in
            var vertex = original
            guard original.layer == Map3DVertex.trainGlass || original.layer == Map3DVertex.trainGlassLit else { return vertex }
            vertex.layer = original.glows ? Map3DVertex.transparentGlassLit : Map3DVertex.transparentGlass
            vertex.u = abs(original.nz) > 0.8 ? style.floor : style.window
            vertex.v = original.u.isFinite ? min(1, max(0, original.u)) : 0
            return vertex
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// A separate study pack, never appended to `standard` or a runtime map.
    public static func studyPack(_ models: [Map3DModelPack.Model], style: Style = Style()) -> Map3DModelPack {
        Map3DModelPack(models: models.map { applying(to: $0, style: style) })
    }

    /// Cached local triangles. The renderer builds this once with its model
    /// buffers; an ordinary pack has none and does no per-frame glass work.
    public struct Cache: Sendable {
        private let triangles: [Int: [[Map3DVertex]]]
        public var isEmpty: Bool { triangles.isEmpty }
        public init(models: [Map3DModelPack.Model]) {
            var cached: [Int: [[Map3DVertex]]] = [:]
            for (index, model) in models.enumerated() {
                var glass: [[Map3DVertex]] = []
                for first in stride(from: 0, to: model.vertices.count - model.vertices.count % 3, by: 3) {
                    let v = model.vertices[first..<(first + 3)]
                    if v.allSatisfy({ $0.isTransparentGlass && $0.u.isFinite && $0.u > 0 && $0.u <= 1 && $0.v.isFinite }) {
                        glass.append(Array(v))
                    }
                }
                if !glass.isEmpty { cached[index] = glass }
            }
            triangles = cached
        }

        /// Scene-space triangles in view-depth order, far to near, across
        /// every instance (not just a sort of cabin centres). Stable ties.
        /// A conventional painter sort: intersecting translucent polygons can
        /// still require splitting. It is not order-independent transparency.
        public func vertices(instances: [Map3DInstance], eye: Map3DPoint, toward target: Map3DPoint) -> [Map3DVertex] {
            guard !isEmpty, finite(eye), finite(target), let look = (target - eye).normalized else { return [] }
            var sorted: [(depth: Float, order: Int, vertices: [Map3DVertex])] = []
            for instance in instances {
                guard let local = triangles[instance.model] else { continue }
                let t = instance.transform
                guard t.count == 16, t.allSatisfy(\.isFinite), t[3] == 0, t[7] == 0, t[11] == 0, t[15] == 1,
                      instance.stripe.0.isFinite, instance.stripe.1.isFinite, instance.stripe.2.isFinite else { continue }
                for triangle in local {
                    let positions = triangle.map { v in
                        Map3DPoint(t[0] * v.x + t[4] * v.y + t[8] * v.z + t[12],
                                   t[1] * v.x + t[5] * v.y + t[9] * v.z + t[13],
                                   t[2] * v.x + t[6] * v.y + t[10] * v.z + t[14])
                    }
                    guard positions.allSatisfy(finite), let normal = (positions[1] - positions[0]).cross(positions[2] - positions[0]).normalized else { continue }
                    let centre = (positions[0] + positions[1] + positions[2]) * (1 / Float(3))
                    let depth = (centre - eye).dot(look)
                    guard depth.isFinite else { continue }
                    let vertices = zip(triangle, positions).map { v, p in
                        Map3DVertex(p, normal: normal, color: painted(v.color, stripe: instance.stripe),
                                    u: v.u, v: v.v, layer: v.layer)
                    }
                    sorted.append((depth, sorted.count, vertices))
                }
            }
            sorted.sort { $0.depth == $1.depth ? $0.order < $1.order : $0.depth > $1.depth }
            return sorted.flatMap(\.vertices)
        }
    }

    private static func finite(_ p: Map3DPoint) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private static func painted(_ color: UInt32, stripe: (Float, Float, Float)) -> UInt32 {
        // Colour alpha is still line-paint substitution, never glass opacity.
        let alpha = Float(color >> 24) / 255
        let line = [stripe.0, stripe.1, stripe.2]
        var result: UInt32 = 0xff000000
        for i in 0..<3 {
            let shade = Float((color >> (i * 8)) & 255) / 255
            let mixed = min(1, max(0, line[i])) * (1 - alpha) + shade * alpha
            result |= UInt32((mixed * 255).rounded()) << (i * 8)
        }
        return result
    }
}
