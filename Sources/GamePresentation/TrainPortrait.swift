import Foundation
import GameCore

/// A train type's picture for the train types and the train's card: the
/// 3D map's own model of it (its head car, then its coaches or middle
/// cars) seen from three quarters front, flat-shaded as the map draws it,
/// painted with a depth buffer into pixels the app shows as an image. The
/// same models the 3D map runs (``Map3DTrainSet``, ``Map3DTrainStyle``),
/// not a drawing of its own, so the picture is the train the player will
/// see; a type with neither (maglev, monorail and the other boxes) has no
/// picture, and the app draws its stand-in.
public struct TrainPortrait: Sendable, Equatable {
    /// Its pixels, row by row from the top, red, green, blue and alpha
    /// (alpha premultiplied); clear round the train.
    public let rgba: [UInt8]
    public let width: Int
    public let height: Int

    /// How many pixels wide a picture is.
    public static let pixelWidth = 720

    /// The key the 3D map draws a train of `type` running as `performance`
    /// by (``Map3DTrainSet/key(type:performance:)``): a train with no type
    /// looks like its performance's train, as on the map.
    public static func key(type: TrainType?, performance: TrainPerformance) -> String {
        Map3DTrainSet.key(type: type, performance: performance)
    }

    /// The key of a type in the train types: its own code.
    public static func key(of type: TrainType) -> String {
        type.spec.code
    }

    /// The picture of a train drawn as `key` with `cars` cars shown (the
    /// head and at most `cars - 1` behind it), its line colour `lineRGB`
    /// where the model takes the line's colour; `nil` when the 3D map has
    /// no model of it. `locked`, the sets the train pack still hides
    /// (``TrainPack``), drawn as the map draws them.
    public static func make(key: String, cars: Int, lineRGB: UInt32 = 0x26A69A, locked: Set<String> = []) -> TrainPortrait? {
        // Made each time asked: the app keeps the images it shows.
        guard let models = models(key: key, cars: max(cars, 1), locked: locked) else { return nil }
        let portrait = paint(models, lineRGB: lineRGB, width: pixelWidth)
        return portrait.width > 0 ? portrait : nil
    }

    // MARK: The models

    /// The models from the front: the head car, its tender, then the cars
    /// behind it.
    static func models(key: String, cars: Int, locked: Set<String>) -> [Map3DModelPack.Model]? {
        if let found = Map3DTrainSet.set(forKey: key, count: max(cars, 2), locked: locked) {
            // The lighter model the map draws far off, where it has one:
            // the same train at a size the page cannot tell apart.
            let set = found.far.flatMap { Map3DTrainSet.byKey[$0] } ?? found
            let models = set.models()
            func named(_ name: String) -> Map3DModelPack.Model? { models.first { $0.name == name } }
            var head = named(set.headName)
            if head == nil, let owner = set.headOf.flatMap({ Map3DTrainSet.byKey[$0] }) {
                head = owner.models().first { $0.name == set.headName }
            }
            guard let head, !head.vertices.isEmpty else { return nil }
            var list = [head]
            if let tender = named(set.tenderName) { list.append(tender) }
            if let middle = named(set.middleName) ?? named(set.tailName) {
                list += Array(repeating: middle, count: max(0, cars - list.count))
            }
            return list
        }
        guard let styleName = Map3DModelPack.styleByType[key],
              let style = Map3DTrainStyle.all.first(where: { $0.name == styleName }) else { return nil }
        let cab = Map3DTrainShell(style: style, cab: true).model(named: style.name + "-cab")
        let car = Map3DTrainShell(style: style, cab: false).model(named: style.name + "-car")
        return [cab] + Array(repeating: car, count: max(0, cars - 1))
    }

    // MARK: The page

    /// The camera's bearing round the train from its right side toward
    /// its front, and how far it looks down, in radians.
    static let bearing: Float = 0.42
    static let lookDown: Float = 0.22

    /// The models painted `width` pixels wide, sampled twice over each
    /// way for smooth edges.
    static func paint(_ models: [Map3DModelPack.Model], lineRGB: UInt32, width: Int) -> TrainPortrait {
        // The camera sits off the train's right side (−y), turned toward
        // its front (+x) and a little above; the front comes out on the
        // page's right.
        let toCamera = normalized((sin(bearing) * cos(lookDown), -cos(bearing) * cos(lookDown), sin(lookDown)))
        let forward = (-toCamera.0, -toCamera.1, -toCamera.2)
        let right = normalized(cross(forward, (0, 0, 1)))
        let up = cross(right, forward)
        let light = normalized((0.35, -0.6, 0.75))

        // Each face facing the camera, on the page: x right, y down, its
        // depth into the page.
        var corners: [(Float, Float, Float)] = []
        var colours: [UInt32] = []
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        // Each car laid behind the one before, its own length apart.
        var front: Float = 0
        for (index, model) in models.enumerated() {
            let offset = index == 0 ? 0 : front - model.maximum.x - 0.6
            front = offset + model.minimum.x
            let vertices = model.vertices
            var at = 0
            while at + 2 < vertices.count {
                let a = vertices[at], b = vertices[at + 1], c = vertices[at + 2]
                at += 3
                // The face's own normal, from its corners, turned the way
                // its vertices' normals say it faces.
                var normal = normalized(cross((b.x - a.x, b.y - a.y, b.z - a.z), (c.x - a.x, c.y - a.y, c.z - a.z)))
                if dot(normal, (a.nx + b.nx + c.nx, a.ny + b.ny + c.ny, a.nz + b.nz + c.nz)) < 0 {
                    normal = (-normal.0, -normal.1, -normal.2)
                }
                // Its back to the camera: hidden by the faces in front.
                guard dot(normal, toCamera) > 0.01 else { continue }
                for v in [a, b, c] {
                    let p = (v.x + offset, v.y, v.z)
                    let x = dot(p, right), y = -dot(p, up)
                    corners.append((x, y, dot(p, forward)))
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
                let lit = 0.72 + 0.28 * max(0, dot(normal, light))
                // Glass the map shows the inside through: dark, as a
                // window seen from outside by day.
                colours.append(a.isTransparentGlass ? glass(a.color) : shaded(a.color, lineRGB: lineRGB, by: lit))
            }
        }
        guard !colours.isEmpty, maxX > minX, maxY > minY else { return TrainPortrait(rgba: [], width: 0, height: 0) }
        let height = max(1, Int((Float(width) * (maxY - minY) / (maxX - minX)).rounded(.up)))
        // Twice over each way, then each four averaged.
        let w = width * 2, h = height * 2
        let scale = Float(w - 1) / (maxX - minX)
        var depth = [Float](repeating: .greatestFiniteMagnitude, count: w * h)
        var colour = [UInt32](repeating: 0, count: w * h)
        var covered = [Bool](repeating: false, count: w * h)
        for face in colours.indices {
            let p = (0..<3).map { k -> (Float, Float, Float) in
                let c = corners[face * 3 + k]
                return ((c.0 - minX) * scale, (c.1 - minY) * scale, c.2)
            }
            let area = edge(p[0], p[1], p[2].0, p[2].1)
            guard abs(area) > 1e-9 else { continue }
            let x0 = max(0, Int(min(p[0].0, p[1].0, p[2].0))), x1 = min(w - 1, Int(max(p[0].0, p[1].0, p[2].0).rounded(.up)))
            let y0 = max(0, Int(min(p[0].1, p[1].1, p[2].1))), y1 = min(h - 1, Int(max(p[0].1, p[1].1, p[2].1).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                let py = Float(y) + 0.5
                for x in x0...x1 {
                    let px = Float(x) + 0.5
                    let w0 = edge(p[1], p[2], px, py) / area
                    let w1 = edge(p[2], p[0], px, py) / area
                    let w2 = 1 - w0 - w1
                    guard w0 >= -1e-4, w1 >= -1e-4, w2 >= -1e-4 else { continue }
                    let z = w0 * p[0].2 + w1 * p[1].2 + w2 * p[2].2
                    let at = y * w + x
                    if z < depth[at] {
                        depth[at] = z
                        colour[at] = colours[face]
                        covered[at] = true
                    }
                }
            }
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 0
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let at = (y * 2 + dy) * w + x * 2 + dx
                    guard covered[at] else { continue }
                    let c = colour[at]
                    r += (c >> 16) & 0xFF; g += (c >> 8) & 0xFF; b += c & 0xFF; a += 255
                }
                let out = (y * width + x) * 4
                rgba[out] = UInt8(r / 4); rgba[out + 1] = UInt8(g / 4); rgba[out + 2] = UInt8(b / 4); rgba[out + 3] = UInt8(a / 4)
            }
        }
        return TrainPortrait(rgba: rgba, width: width, height: height)
    }

    private static func edge(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ px: Float, _ py: Float) -> Float {
        (b.0 - a.0) * (py - a.1) - (b.1 - a.1) * (px - a.0)
    }

    /// A vertex's colour (red in the low byte; alpha below 1 the line's
    /// colour in that share) lit by `lit`.
    static func shaded(_ color: UInt32, lineRGB: UInt32, by lit: Float) -> UInt32 {
        let alpha = Float((color >> 24) & 0xFF) / 255
        func channel(_ own: UInt32, _ line: UInt32) -> UInt32 {
            let mixed = Float(own) * alpha + Float(line) * (1 - alpha)
            return UInt32(min(255, max(0, (mixed * lit).rounded())))
        }
        let r = channel(color & 0xFF, (lineRGB >> 16) & 0xFF)
        let g = channel((color >> 8) & 0xFF, (lineRGB >> 8) & 0xFF)
        let b = channel((color >> 16) & 0xFF, lineRGB & 0xFF)
        return (r << 16) | (g << 8) | b
    }

    /// A window's glass: its own tint over a dark blue-grey.
    static func glass(_ color: UInt32) -> UInt32 {
        func channel(_ own: UInt32, _ dark: UInt32) -> UInt32 { (own * 35 + dark * 65) / 100 }
        return (channel(color & 0xFF, 0x2C) << 16) | (channel((color >> 8) & 0xFF, 0x38) << 8) | channel((color >> 16) & 0xFF, 0x4A)
    }

    private static func dot(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> Float {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    private static func cross(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> (Float, Float, Float) {
        (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
    }

    private static func normalized(_ a: (Float, Float, Float)) -> (Float, Float, Float) {
        let length = max(1e-6, dot(a, a).squareRoot())
        return (a.0 / length, a.1 / length, a.2 / length)
    }
}
