import Foundation

/// Decision 410: the trains made in code (decision 230's styles, the scene
/// kit's cab and middle cars of decision 318's multiple units and their
/// coaches), built the way #1201's 700T and decision 408's N700S-G are:
///
/// - the section a superellipse (`refreshHighSpeed`'s `surface`), the
///   nose's top, width and bottom read off measured tables along it rather
///   than three ease curves (``NoseShape``);
/// - the livery cut into the shell's own triangles at its edges (the 700T's
///   `clip`), so the skirt, the band, the thin line and the roof meet in a
///   sharp edge that runs round the ends and dives down a long nose;
/// - windows and doors rounded, a frame round a pane (the 700T's
///   `refreshRoundedOutline`), standing on the curved flank;
/// - the windscreen, the lamps and a cab's face cut along every facet of
///   the nose they lie on, so they follow its curve;
/// - lamps that are lamps: a housing and two lenses, the headlamp lit
///   white at the front, the tail lamp red at the back;
/// - the bogies where the body's skirt and the underframe leave room for
///   them, as the N700S-G's stand in its skirt's openings;
/// - every triangle one flat colour from the palette (the miniature look).
///
/// Built in a frame with y up (x the front, z the right) and turned into
/// the model's frame at the end (``Map3DModelPack/Model/flat(named:from:)``).
struct Map3DTrainShell {
    /// ``near`` within ``Map3DTrains/modelReach``; ``far`` decision 408's
    /// light car between a set's reach and that (fewer segments, a window
    /// strip, plain bogies).
    enum Detail: Sendable { case near, far }

    /// A cab's face, in shares of the body's height and half width.
    struct Front {
        /// The windscreen's bottom and top (shares of the height on a flat
        /// front; on a sloping nose, where along the nose, 0 to 1).
        var screen: ClosedRange<Float>
        var screenWidth: Float
        /// A panel of its own colour round the windscreen (the Puyuma's red
        /// face), its bottom and top shares.
        var face: (colour: UInt32, low: Float, high: Float)? = nil
        /// The lamps' height share and how far out they stand.
        var lampShare: Float
        var lampAcross: Float = 0.66
        /// Whether its lit lamps are the tail's (red) rather than the head's.
        var tail = false
        /// A centre pillar or through door splitting the windscreen.
        var pillar = false
        /// Whether the windscreen lies along a sloping nose's top (its
        /// ``screen`` then where along the nose) rather than square on its
        /// front.
        var onSlope = false
        /// A coupler under the face.
        var coupler = true
        /// The line's colour low across the face.
        var lowBand = false
        /// The body's colour over the nose, if the face has its own.
        var noseColour: UInt32? = nil
    }

    let style: Map3DTrainStyle
    let cab: Bool
    var pantograph = false
    var detail = Detail.near
    var front: Front

    private var builder = StationKitBuilder()
    /// The shell's triangles, outward, before the livery cuts them: what the
    /// windscreen and lamps are cut along.
    private var shell: [[Map3DPoint]] = []

    init(style: Map3DTrainStyle, cab: Bool, pantograph: Bool = false, detail: Detail = .near, front: Front? = nil) {
        self.style = style
        self.cab = cab
        self.pantograph = pantograph
        self.detail = detail
        self.front = front ?? Self.front(of: style)
    }

    /// A style's own face: on a flat front its windscreen above
    /// ``Map3DTrainStyle/screenDown``, on a sloping one between
    /// ``Map3DTrainStyle/screenFrom`` and ``Map3DTrainStyle/screenTo``.
    static func front(of style: Map3DTrainStyle) -> Front {
        if style.noseShape.slopes {
            return Front(screen: style.screenFrom...style.screenTo, screenWidth: 0.78 * style.screenAcross, lampShare: style.lampShare,
                         lampAcross: 0.62, onSlope: true, coupler: style.nose < 6)
        }
        return Front(screen: style.screenDown...0.86, screenWidth: 0.80 * style.screenAcross, lampShare: 0.27,
                     pillar: style.nose < 1.5)
    }

    // MARK: The section

    static func ease(_ x: Float) -> Float {
        let v = min(1, max(0, x))
        return v * v * (3 - 2 * v)
    }

    var height: Float { style.roof - style.floor }
    var half: Float { style.length / 2 }
    /// Where the nose starts (the body's length at the back of it).
    var noseStart: Float { half - (cab ? style.nose : 0) }

    /// How far along the nose `x` is, 0 at the body and 1 at the tip.
    func along(_ x: Float) -> Float { cab && style.nose > 0 ? min(1, max(0, (x - noseStart) / style.nose)) : 0 }

    /// The section at `x`: its bottom, its top and its half width.
    func section(_ x: Float) -> (bottom: Float, top: Float, half: Float) {
        let t = along(x), shape = style.noseShape
        var bottom = style.floor + style.lift * shape.lift(t), top = style.roof - style.drop * shape.drop(t)
        var width = style.halfWidth * (1 - style.tuck * shape.tuck(t))
        if style.cap > 0, t > 0.86 {
            // The tip rounds over: the last rings close in on its middle.
            let close = 1 - style.cap * Self.ease((t - 0.86) / 0.14) * shape.capShare
            let middle = (bottom + top) / 2
            bottom = middle - (middle - bottom) * close
            top = middle + (top - middle) * close
            width *= 0.4 + 0.6 * close
        }
        return (bottom, top, width)
    }

    /// The superellipse's point at `x`, `angle` round from the right side
    /// (0 the right, π/2 the top).
    func point(_ x: Float, _ angle: Float) -> Map3DPoint {
        let s = section(x), c = cosf(angle), n = sinf(angle)
        let z = s.half * (c < 0 ? -1 : 1) * powf(abs(c), style.sideRound)
        let y = s.bottom + (s.top - s.bottom) * (0.5 + 0.5 * (n < 0 ? -1 : 1) * powf(abs(n), style.topRound))
        return Map3DPoint(x, y, z)
    }

    /// The body's right flank at height `y` (on the body, behind the nose).
    func flank(_ y: Float) -> Float {
        let share = 2 * (y - style.floor) / height - 1
        let n = powf(min(1, abs(share)), 1 / style.topRound), c = (1 - n * n).squareRoot()
        return style.halfWidth * powf(c, style.sideRound)
    }

    var segments: Int { detail == .near ? 32 : 16 }

    /// The rings along the car, back to front: the body's two ends and,
    /// on a cab, its nose's, closer together toward the tip.
    var rings: [Float] {
        let back = -half + Self.gangway
        let frontEnd = cab ? half : half - Self.gangway
        guard cab, style.nose > 0 else { return [back, frontEnd] }
        let count = max(3, (detail == .near ? style.noseShape.rings : (style.noseShape.rings + 1) / 2))
        return [back, noseStart] + (1...count).map { i in
            let u = Float(i) / Float(count)
            return noseStart + style.nose * (1 - powf(1 - u, 1.5))
        }
    }

    /// The gangway's depth at a car's end that is not a cab.
    static let gangway: Float = 0.12

    // MARK: The paint

    /// The livery's field at `p`: its height's share of the section, raised
    /// by the dive toward a long nose's tip, so a band edge is where it is a
    /// constant.
    func level(_ p: Map3DPoint) -> Float {
        (p.y - style.floor) / height + style.dive * Self.ease(along(p.x))
    }

    /// The livery's edges, low to high, and the colour between each pair.
    var edges: [Float] {
        var cuts = [style.skirtTop, style.band.lowerBound, style.band.upperBound]
        if let line = style.line { cuts += [line.lowerBound, line.upperBound] }
        cuts.append(0.9)
        return Array(Set(cuts)).sorted()
    }

    func colour(between low: Float, _ high: Float, at x: Float) -> UInt32 {
        let middle = (low + high) / 2
        if middle < style.skirtTop { return style.skirt }
        if style.band.contains(middle) { return Map3DTrainBuilder.lineColour }
        if let line = style.line, line.contains(middle) { return style.lineColour }
        // The roof's grey over the top, but over a diving nose (its body
        // colour sweeps to the tip).
        if middle > 0.9, style.dive == 0 || along(x) == 0 { return Map3DTrainStyle.roofColour }
        if cab, let nose = front.noseColour, along(x) > 0 { return nose }
        return style.body
    }

    /// `triangle` cut at every livery edge, each piece in its colour. The
    /// field is carried along each cut edge (as the 700T's
    /// `nosePaintParts`), its ends taken in one order, so the triangle on
    /// the other side of an edge cuts it at the same point.
    mutating func paint(_ triangle: [Map3DPoint], inside: Map3DPoint) {
        typealias Corner = (point: Map3DPoint, level: Float)
        var rest: [Corner] = triangle.map { ($0, level($0)) }
        var low = -Float.infinity
        func cut(_ polygon: [Corner], at value: Float, above: Bool) -> [Corner] {
            var out: [Corner] = []
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let inA = above ? a.level >= value : a.level < value, inB = above ? b.level >= value : b.level < value
                if inA { out.append(a) }
                if inA != inB {
                    let first = (a.point.x, a.point.y, a.point.z) < (b.point.x, b.point.y, b.point.z)
                    let p = first ? a : b, q = first ? b : a
                    let t = (value - p.level) / (q.level - p.level)
                    out.append((p.point + (q.point - p.point) * t, value))
                }
            }
            return out
        }
        for edge in edges {
            let below = cut(rest, at: edge, above: false)
            if below.count >= 3 { emit(below.map(\.point), colour: colour(between: low, edge, at: centre(below.map(\.point)).x), inside: inside) }
            rest = cut(rest, at: edge, above: true)
            low = edge
            if rest.count < 3 { return }
        }
        emit(rest.map(\.point), colour: colour(between: low, 2, at: centre(rest.map(\.point)).x), inside: inside)
    }

    private mutating func emit(_ polygon: [Map3DPoint], colour: UInt32, inside: Map3DPoint) {
        // Drop the slivers a cut leaves at a corner.
        var points: [Map3DPoint] = []
        for p in polygon where points.last.map({ ($0 - p).length > 1e-5 }) ?? true { points.append(p) }
        if let first = points.first, let last = points.last, points.count > 1, (first - last).length <= 1e-5 { points.removeLast() }
        guard points.count >= 3 else { return }
        builder.face(points, inside: inside, color: colour)
    }

    func centre(_ points: [Map3DPoint]) -> Map3DPoint {
        points.reduce(Map3DPoint.zero) { $0 + $1 * (1 / Float(points.count)) }
    }

    // MARK: The shell

    mutating func addShell() {
        let xs = rings, count = segments
        let sections = xs.map { x in (0..<count).map { point(x, 2 * Float.pi * Float($0) / Float(count)) } }
        for k in 0..<(xs.count - 1) {
            let s = section((xs[k] + xs[k + 1]) / 2)
            let inside = Map3DPoint((xs[k] + xs[k + 1]) / 2, (s.bottom + s.top) / 2, 0)
            for i in 0..<count {
                let j = (i + 1) % count
                for triangle in [[sections[k][i], sections[k][j], sections[k + 1][j]], [sections[k][i], sections[k + 1][j], sections[k + 1][i]]] {
                    addShellTriangle(triangle, inside: inside)
                }
            }
        }
        // The two ends, each a fan round its middle.
        for (index, outward) in [(0, Float(-1)), (xs.count - 1, Float(1))] {
            let ring = sections[index], middle = centre(ring)
            let inside = middle - Map3DPoint(outward, 0, 0)
            for i in 0..<count {
                addShellTriangle([middle, ring[i], ring[(i + 1) % count]], inside: inside)
            }
        }
    }

    private mutating func addShellTriangle(_ triangle: [Map3DPoint], inside: Map3DPoint) {
        guard let normal = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized else { return }
        let outward = normal.dot(centre(triangle) - inside) >= 0
        shell.append(outward ? triangle : [triangle[0], triangle[2], triangle[1]])
        paint(triangle, inside: inside)
    }

    // MARK: Windows and doors

    /// A rounded rectangle of twelve corners (the 700T's
    /// `refreshRoundedOutline`), in (along, up).
    static func rounded(x: Float, y: Float, width: Float, height: Float, radius: Float) -> [(Float, Float)] {
        let r = min(radius, min(width, height) / 2)
        let corners: [(Float, Float, Float)] = [(x + width / 2 - r, y + height / 2 - r, 0), (x - width / 2 + r, y + height / 2 - r, 90),
                                                (x - width / 2 + r, y - height / 2 + r, 180), (x + width / 2 - r, y - height / 2 + r, 270)]
        var result: [(Float, Float)] = []
        for (cx, cy, start) in corners {
            for i in 0...2 {
                let a = (start + Float(i) * 45) * Float.pi / 180
                result.append((cx + cosf(a) * r, cy + sinf(a) * r))
            }
        }
        return result
    }

    /// `outline` (along, up) laid on both flanks, `proud` off the body; one
    /// reaching below the windows (a door) is cut into strips a hand's
    /// breadth tall, so it follows where the flank curves in rather than
    /// sinking into it.
    mutating func addOnFlanks(_ outline: [(Float, Float)], proud: Float, colour: UInt32) {
        let lows = outline.map(\.1)
        guard let bottom = lows.min(), let top = lows.max() else { return }
        let strips = bottom < y(style.windows.lowerBound) - 0.05 ? max(1, Int(((top - bottom) / 0.22).rounded(.up))) : 1
        for strip in 0..<strips {
            let from = bottom + (top - bottom) * Float(strip) / Float(strips), to = bottom + (top - bottom) * Float(strip + 1) / Float(strips)
            var piece = outline
            for (level, keepAbove) in [(from, true), (to, false)] {
                var next: [(Float, Float)] = []
                for i in piece.indices {
                    let a = piece[i], b = piece[(i + 1) % piece.count]
                    let inA = keepAbove ? a.1 >= level : a.1 <= level, inB = keepAbove ? b.1 >= level : b.1 <= level
                    if inA { next.append(a) }
                    if inA != inB { next.append((a.0 + (b.0 - a.0) * (level - a.1) / (b.1 - a.1), level)) }
                }
                piece = next
            }
            guard piece.count >= 3 else { continue }
            for sign: Float in [-1, 1] {
                let points = piece.map { Map3DPoint($0.0, $0.1, sign * (flank($0.1) + proud)) }
                let middle = centre(points)
                builder.face(points, inside: Map3DPoint(middle.x, middle.y, 0), color: colour)
            }
        }
    }

    func y(_ share: Float) -> Float { style.floor + share * height }

    /// The doors' middles along the car.
    var doorCentres: [Float] {
        let back = -half + 0.5, front = noseStart - (cab ? 0.3 : 0.5)
        let count = cab && style.nose > 4 ? max(1, style.doors - 1) : max(1, style.doors)
        if let at = style.doorsAt { return at }
        if count == 1 { return [cab ? back + style.doorWidth : front - style.doorWidth] }
        if style.doorLayout == .carEnds && count == 2 { return [back + style.doorWidth * 1.1, front - style.doorWidth * 1.1] }
        return (0..<count).map { back + (front - back) * (Float($0) + 0.5) / Float(count) }
    }

    mutating func addOpenings() {
        let back = -half + 0.5, front = noseStart - (cab ? 0.3 : 0.5)
        guard front > back else { return }
        let low = y(style.windows.lowerBound), high = y(style.windows.upperBound)
        let doors = doorCentres
        let doorTop = y(min(0.97, style.windows.upperBound + 0.04)), doorBottom = y(max(0.02, style.skirtTop * 0.5))
        for centre in doors {
            let frame = Self.rounded(x: centre, y: (doorTop + doorBottom) / 2, width: style.doorWidth + 0.07, height: doorTop - doorBottom + 0.05, radius: 0.1)
            if detail == .near { addOnFlanks(frame, proud: 0.008, colour: Map3DTrainStyle.under) }
            let leaf = Self.rounded(x: centre, y: (doorTop + doorBottom) / 2, width: style.doorWidth, height: doorTop - doorBottom, radius: 0.08)
            addOnFlanks(leaf, proud: 0.016, colour: Map3DTrainStyle.doorColour)
            if style.doorWindows || detail == .near {
                let width = style.doorWindows ? style.doorWidth * 0.42 : style.doorWidth * 0.36
                let pane = Self.rounded(x: centre, y: (low + high) / 2 + 0.02, width: width, height: (high - low) * 0.9, radius: 0.06)
                addOnFlanks(pane, proud: 0.024, colour: Map3DTrainStyle.glass)
            }
        }
        let gap = (style.doorWidth + style.windowWidth) / 2 + 0.15
        let clear = { (at: Float) in !doors.contains { abs($0 - at) < gap } }
        var spans: [(Float, Float)] = []
        var at = back + style.windowPitch / 2
        while at + style.windowWidth / 2 < front {
            if clear(at) { spans.append((at - style.windowWidth / 2, at + style.windowWidth / 2)) }
            at += style.windowPitch
        }
        if detail == .far {
            // From afar the panes run together: one strip between each pair
            // of doors.
            var strips: [(Float, Float)] = []
            for span in spans {
                if let last = strips.last, span.0 - last.1 < style.windowPitch { strips[strips.count - 1].1 = span.1 } else { strips.append(span) }
            }
            for (from, to) in strips {
                addOnFlanks(Self.rounded(x: (from + to) / 2, y: (low + high) / 2, width: to - from, height: high - low, radius: 0.1),
                            proud: 0.02, colour: Map3DTrainStyle.glass)
            }
            return
        }
        let radius = min(0.14, style.windowWidth * 0.22)
        for (from, to) in spans {
            let x = (from + to) / 2, width = to - from
            addOnFlanks(Self.rounded(x: x, y: (low + high) / 2, width: width + 0.07, height: high - low + 0.07, radius: radius + 0.03),
                        proud: 0.012, colour: Map3DTrainStyle.darkLine)
            addOnFlanks(Self.rounded(x: x, y: (low + high) / 2, width: width, height: high - low, radius: radius),
                        proud: 0.022, colour: Map3DTrainStyle.glass)
        }
    }

    // MARK: The cab's face

    /// Cuts `outline` (in the plane across `direction`, its first coordinate
    /// up and its second to the right, about `origin`) along every shell
    /// triangle facing back along `direction` within `depth` of `origin`,
    /// each piece `proud` off its triangle.
    mutating func project(_ outline: [(Float, Float)], origin: Map3DPoint, direction: Map3DPoint, proud: Float, colour: UInt32,
                          glows: Bool = false, depth: Float = 1.6) {
        guard let d = direction.normalized else { return }
        let side = (Map3DPoint(0, 0, 1) - d * d.z).normalized ?? Map3DPoint(0, 0, 1)
        let up = d.cross(side)
        let area = outline.indices.reduce(Float(0)) { sum, i in
            let a = outline[i], b = outline[(i + 1) % outline.count]
            return sum + a.0 * b.1 - b.0 * a.1
        }
        let turn: Float = area > 0 ? 1 : -1
        let start = builder.mesh.vertices.count
        for triangle in shell {
            guard let normal = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized,
                  normal.dot(d) < -0.12, abs((centre(triangle) - origin).dot(d)) < depth else { continue }
            func planar(_ p: Map3DPoint) -> (Float, Float) { ((p - origin).dot(up), (p - origin).dot(side)) }
            var cut = triangle
            for e in outline.indices {
                let a = outline[e], b = outline[(e + 1) % outline.count]
                func inside(_ p: Map3DPoint) -> Float {
                    let q = planar(p)
                    return ((b.0 - a.0) * (q.1 - a.1) - (b.1 - a.1) * (q.0 - a.0)) * turn
                }
                var next: [Map3DPoint] = []
                for i in cut.indices {
                    let p = cut[i], q = cut[(i + 1) % cut.count], sp = inside(p), sq = inside(q)
                    if sp >= 0 { next.append(p) }
                    if (sp >= 0) != (sq >= 0) { next.append(p + (q - p) * (sp / (sp - sq))) }
                }
                cut = next
                if cut.count < 3 { break }
            }
            guard cut.count >= 3 else { continue }
            let lifted = cut.map { $0 + normal * proud }
            builder.face(lifted, inside: centre(lifted) - normal, color: colour)
        }
        if glows { builder.mesh.makeGlowing(from: start) }
    }

    /// The direction the windscreen is looked at along: square onto a flat
    /// front, down onto a sloping nose's top.
    func screenView() -> (origin: Map3DPoint, direction: Map3DPoint, low: Float, high: Float) {
        if front.onSlope {
            let from = noseStart + style.nose * front.screen.lowerBound, to = noseStart + style.nose * front.screen.upperBound
            let a = section(from).top, b = section(to).top
            let normal = Map3DPoint(a - b, to - from, 0).normalized ?? Map3DPoint(1, 0, 0)
            let middle = Map3DPoint((from + to) / 2, (a + b) / 2, 0)
            let span = Map3DPoint(to - from, b - a, 0).length
            return (middle, normal * -1, -span / 2, span / 2)
        }
        let origin = Map3DPoint(half, 0, 0)
        return (origin, Map3DPoint(-1, 0, 0), y(front.screen.lowerBound), y(front.screen.upperBound))
    }

    mutating func addFace() {
        guard cab else { return }
        let view = screenView()
        let tip = section(half)
        let reach = front.onSlope ? section(view.origin.x).half : tip.half
        let w = reach * front.screenWidth
        let low = view.low, high = view.high
        func trapezoid(_ grow: Float, top: Float = 0.9) -> [(Float, Float)] {
            // Narrower over the top, its corners rounded, as a cab's glass.
            let r = min(0.16, (high - low) * 0.2) + grow * 0.5
            let lo = low - grow, hi = high + grow, wl = w + grow, wh = w * top + grow
            var points: [(Float, Float)] = []
            for (cy, cz, from) in [(hi - r, wh - r, Float(0)), (hi - r, -wh + r, Float(90)), (lo + r, -wl + r, Float(180)), (lo + r, wl - r, Float(270))] {
                for i in 0...2 {
                    let a = (from + Float(i) * 45) * Float.pi / 180
                    points.append((cy + sinf(a) * r, cz + cosf(a) * r))
                }
            }
            return points
        }
        if let face = front.face {
            let lo = y(face.low), hi = y(face.high), fw = tip.half * 0.96
            project([(lo, -fw), (lo, fw), (hi, fw * 0.9), (hi, -fw * 0.9)], origin: Map3DPoint(half, 0, 0), direction: Map3DPoint(-1, 0, 0),
                    proud: 0.01, colour: face.colour, depth: style.nose + 1.6)
        }
        let depth = front.onSlope ? style.nose * 0.6 : style.nose + 1.6
        project(trapezoid(0.06), origin: view.origin, direction: view.direction, proud: 0.016, colour: Map3DColor.shaded(Map3DTrainStyle.glass, 0.7), depth: depth)
        project(trapezoid(0), origin: view.origin, direction: view.direction, proud: 0.026, colour: Map3DTrainStyle.glass, depth: depth)
        if front.pillar {
            project([(low, -0.045), (low, 0.045), (high, 0.045), (high, -0.045)], origin: view.origin, direction: view.direction,
                    proud: 0.032, colour: Map3DTrainStyle.doorColour, depth: depth)
        }
        if front.lowBand {
            project([(y(0.12), -tip.half * 0.72), (y(0.12), tip.half * 0.72), (y(0.18), tip.half * 0.72), (y(0.18), -tip.half * 0.72)],
                    origin: Map3DPoint(half, 0, 0), direction: Map3DPoint(-1, 0, 0), proud: 0.02, colour: Map3DTrainBuilder.lineColour,
                    depth: style.nose + 1.6)
        }
        addLamps()
        if front.coupler {
            builder.box(half - 0.03, style.floor + 0.02, 0, 0.38, 0.32, 0.25, Map3DTrainStyle.under)
        }
    }

    /// Two lamps a side: a housing, the headlamp and the tail lamp. On a
    /// sloping nose they stand on its shoulders, each looked at square on.
    mutating func addLamps() {
        let headLit = !front.tail
        for sign: Float in [-1, 1] {
            let origin: Map3DPoint, direction: Map3DPoint
            if front.onSlope {
                // On the shoulder, a little above the side's middle.
                let x = noseStart + style.nose * (style.lampSpan.lowerBound + style.lampSpan.upperBound) / 2
                let a: Float = sign > 0 ? 0.3 : Float.pi - 0.3
                let p = point(x, a), dx = point(x + 0.05, a) - point(x - 0.05, a), da = point(x, a + 0.02) - point(x, a - 0.02)
                var normal = dx.cross(da).normalized ?? Map3DPoint(1, 0, 0)
                let s = section(x)
                if normal.dot(p - Map3DPoint(x, (s.bottom + s.top) / 2, 0)) < 0 { normal = normal * -1 }
                origin = p
                direction = normal * -1
            } else {
                origin = Map3DPoint(half, y(front.lampShare), sign * section(half).half * front.lampAcross)
                direction = Map3DPoint(-1, 0, 0)
            }
            // On a nose's shoulder as big as the 700T's (0.66 by 0.29 m).
            let depth: Float = 0.5, size: Float = front.onSlope ? 1.15 : 1
            let housing = Self.rounded(x: 0, y: 0, width: 0.26 * size, height: 0.6 * size, radius: 0.08)
            project(housing, origin: origin, direction: direction, proud: 0.02, colour: Map3DTrainStyle.lampHousing, depth: depth)
            for (offset, head) in [(Float(0.14) * size, true), (Float(-0.14) * size, false)] {
                let o = sign * offset
                let lens = Self.rounded(x: 0, y: o, width: 0.16 * size, height: 0.2 * size, radius: 0.06)
                let lit = head == headLit
                let colour = head ? (lit ? Map3DTrainStyle.headlamp : Map3DColor.shaded(Map3DTrainStyle.headlamp, 0.72))
                    : (lit ? Map3DPalette.lantern : Map3DColor.shaded(Map3DPalette.lantern, 0.6))
                project(lens, origin: origin, direction: direction, proud: 0.034, colour: colour, glows: lit, depth: depth)
            }
        }
    }

    // MARK: Under and on top

    /// The bogies' middles: as far in from the ends as a car's are, the
    /// front one behind a long nose.
    var bogieCentres: [Float] {
        let inset = max(2.0, style.length * 0.145)
        let back = -half + inset
        var front = half - inset
        if cab, style.nose > 2 { front = min(front, noseStart - 0.4) }
        return [back, front]
    }

    var axles: [Float] { style.gauge > 1.2 && style.length > 22 ? [-1.25, 1.25] : [-1.05, 1.05] }

    mutating func addRunningGear() {
        let gauge = style.gauge, radius: Float = 0.43
        let wheelbase = axles.last! - axles.first!
        // The skirt's openings: covers between the bogies and the ends,
        // clear of each bogie by a hand's breadth.
        let opening = wheelbase + 2 * radius + 0.5
        var cuts: [Float] = [-half + 0.2]
        for c in bogieCentres { cuts += [c - opening / 2, c + opening / 2] }
        cuts.append(cab ? noseStart + style.nose * 0.25 : half - 0.2)
        let underTop = style.floor + 0.02
        for i in stride(from: 0, to: cuts.count - 1, by: 2) where cuts[i + 1] - cuts[i] > 0.4 {
            let from = cuts[i], to = cuts[i + 1], middle = (from + to) / 2
            if style.skirtCover {
                // A high-speed car's side skirt hangs over its underframe.
                for sign: Float in [-1, 1] {
                    let z = sign * (flank(style.floor + 0.05) - 0.02)
                    builder.box(middle, 0.34, z, to - from, 0.06, underTop - 0.34, style.skirt)
                }
            } else {
                // Equipment hung between the bogies.
                let boxes = max(1, Int((to - from) / 3.2))
                for b in 0..<boxes {
                    let x = from + (to - from) * (Float(b) + 0.5) / Float(boxes)
                    builder.box(x, 0.42, 0, min(2.6, (to - from) / Float(boxes) - 0.4), style.halfWidth * 1.5, underTop - 0.42, Map3DTrainStyle.under)
                }
            }
        }
        // The frame over the bogies, set in from the sides.
        builder.box(0, underTop - 0.14, 0, cuts.last! - cuts.first!, style.halfWidth * 1.6, 0.16, Map3DTrainStyle.under)
        for c in bogieCentres {
            if detail == .far {
                builder.box(c, 0, 0, wheelbase + 2 * radius, gauge + 0.3, 0.74, Map3DTrainStyle.under)
                continue
            }
            // The bolster and the two side frames.
            builder.box(c, 0.56, 0, 1.0, gauge + 0.1, 0.22, Map3DTrainStyle.under)
            for sign: Float in [-1, 1] {
                let z = sign * (gauge / 2 + 0.16)
                builder.box(c, 0.32, z, wheelbase + 0.7, 0.14, 0.26, Map3DTrainStyle.lampHousing)
                for a in axles {
                    builder.box(c + a, 0.28, z + sign * 0.03, 0.3, 0.16, 0.3, Map3DTrainStyle.under)
                    // The ten-sided wheel's flat bottom on the rail.
                    let hub = radius * cosf(Float.pi / 10)
                    builder.civicTube(Map3DPoint(c + a, hub, sign * (gauge / 2 - 0.02)), Map3DPoint(c + a, hub, sign * (gauge / 2 + 0.1)),
                                      radius: radius, color: Map3DStreetModel.tyre, sides: 10)
                }
            }
        }
    }

    mutating func addRoof() {
        let back = -half + 1.2, front = noseStart + (cab && style.nose > 2 ? 0.2 : -1.2)
        let length = front - back
        if style.roofKind == .cableShrouds {
            // The high-speed car's cable shrouds along the crown, and a low
            // fairing round the pantograph on the cars with one.
            let runFrom = back + 0.6, runTo = cab ? noseStart - 0.6 : front - 0.6
            let runLength = max(2.4, runTo - runFrom), runMid = (runFrom + runTo) / 2
            for lateral: Float in [-0.72, 0.72] {
                builder.box(runMid, style.roof - 0.06, lateral, runLength, 0.24, 0.28, Map3DColor.shaded(style.body, 0.94))
            }
            if pantograph {
                builder.box(runMid, style.roof - 0.02, 0, min(2.8, runLength * 0.6), style.halfWidth * 1.12, 0.3, Map3DTrainStyle.roofColour)
                if detail == .near {
                    // A single-arm pantograph, lowered.
                    let x = runMid, top = style.roof + 0.28
                    builder.beam(Map3DPoint(x - 0.6, top, 0), Map3DPoint(x + 0.5, top + 0.22, 0), 0.06, Map3DTrainStyle.lampHousing)
                    builder.beam(Map3DPoint(x + 0.5, top + 0.22, 0), Map3DPoint(x - 0.2, top + 0.4, 0), 0.05, Map3DTrainStyle.lampHousing)
                    builder.box(x - 0.2, top + 0.4, 0, 0.12, 1.4, 0.05, Map3DTrainStyle.lampHousing)
                }
            }
            return
        }
        // The air-conditioning units along the roof.
        let units = max(1, Int((length - 1.2) / 4.5))
        for i in 0..<units {
            let x = back + 0.6 + (length - 1.2) * (Float(i) + 0.5) / Float(units)
            builder.box(x, style.roof - 0.02, 0, 2.2, style.halfWidth * 1.25, 0.3, Map3DTrainStyle.roofColour)
            if detail == .near {
                builder.box(x, style.roof + 0.28, 0, 1.6, style.halfWidth * 0.9, 0.02, Map3DColor.shaded(Map3DTrainStyle.roofColour, 0.8))
            }
        }
    }

    /// The gangway's bellows at an end that is not a cab.
    mutating func addGangways() {
        let ends: [Float] = cab ? [-1] : [-1, 1]
        for end in ends {
            builder.box(end * (half - Self.gangway / 2), style.floor + 0.2, 0, Self.gangway, 1.2, min(2.1, height - 0.5), Map3DTrainStyle.under)
        }
    }

    // MARK: The model

    func model(named name: String) -> Map3DModelPack.Model {
        var car = self
        car.addShell()
        car.addOpenings()
        car.addFace()
        car.addRunningGear()
        car.addRoof()
        car.addGangways()
        // Without the triangles of no area a fan leaves where its points
        // meet (a cap closing, a cut along a projected lamp's edge): the
        // handbook's degenerate-face check (#1224, G), and of the slivers
        // whose three points lie on one line, which rounding gives an area.
        let mesh = car.builder.mesh
        var kept = Map3DMesh()
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
            let a = corners[0].position, b = corners[1].position, c = corners[2].position
            let area = (b - a).cross(c - a).length / 2
            let longest = max((b - a).length, (c - b).length, (a - c).length)
            if area >= 1e-7, area >= 1e-6 * longest * longest { kept.appendTriangle(corners) }
        }
        return Map3DModelPack.Model.flat(named: name, from: kept)
    }
}

/// Decision 410: a nose's shape along it, measured, its amplitudes the
/// style's ``Map3DTrainStyle/drop``, ``Map3DTrainStyle/tuck`` and
/// ``Map3DTrainStyle/lift``: each table how much of them is reached at
/// each point (0 at the body, 1 at the tip).
enum NoseShape: Sendable {
    /// A flat front, its edges rounded (a commuter, a metro).
    case flat
    /// A short rounded front (a people mover, the EMU800).
    case rounded
    /// A sloping nose (the EMU3000, the Puyuma, the Taroko).
    case sloped
    /// A long high-speed nose, its tables the 700T's (`dimensions`).
    case long

    var slopes: Bool { self == .sloped || self == .long }

    var rings: Int {
        switch self {
        case .flat: 4
        case .rounded: 6
        case .sloped: 10
        case .long: 14
        }
    }

    /// How much of ``Map3DTrainStyle/cap`` the tip closes by.
    var capShare: Float { self == .flat ? 0 : self == .rounded ? 0.5 : 1 }

    func drop(_ t: Float) -> Float {
        switch self {
        case .flat: Self.read(t, [(0, 0), (0.5, 0.12), (0.8, 0.45), (1, 1)])
        case .rounded: Self.read(t, [(0, 0), (0.3, 0.1), (0.6, 0.4), (0.85, 0.75), (1, 1)])
        case .sloped: Self.read(t, [(0, 0), (0.12, 0.04), (0.3, 0.2), (0.5, 0.45), (0.7, 0.7), (0.88, 0.9), (1, 1)])
        // The 700T's height table over its 6.7 m nose, as shares of its fall.
        case .long: Self.read(t, [(0, 0), (0.16, 0), (0.28, 0.052), (0.40, 0.199), (0.52, 0.388), (0.65, 0.619), (0.80, 0.829), (0.92, 0.935), (1, 1)])
        }
    }

    func tuck(_ t: Float) -> Float {
        switch self {
        case .flat: Self.read(t, [(0, 0), (0.5, 0.15), (0.85, 0.55), (1, 1)])
        case .rounded: Self.read(t, [(0, 0), (0.4, 0.1), (0.75, 0.45), (1, 1)])
        case .sloped: Self.read(t, [(0, 0), (0.5, 0.08), (0.75, 0.3), (0.9, 0.6), (1, 1)])
        // The 700T's width table, as shares of its narrowing.
        case .long: Self.read(t, [(0, 0), (0.3, 0), (0.5, 0.019), (0.7, 0.093), (0.85, 0.23), (0.95, 0.49), (1, 1)])
        }
    }

    func lift(_ t: Float) -> Float {
        Self.read(t, self == .sloped || self == .long ? [(0, 0), (0.55, 0), (0.85, 0.5), (1, 1)] : [(0, 0), (0.6, 0), (1, 1)])
    }

    static func read(_ t: Float, _ table: [(Float, Float)]) -> Float {
        for i in 1..<table.count where t <= table[i].0 {
            let a = table[i - 1], b = table[i]
            return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
        }
        return table.last!.1
    }
}
