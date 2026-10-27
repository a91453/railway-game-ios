import Foundation

// Decision 446: Taipei's scooters (機車) close up. Three kinds: the
// everyday 125 cc step-through, the battery-swap e-scooter and the
// step-through with a delivery box; ridden on the streets
// (``Map3DStreetModel/stepScooter`` …) and parked in rows in the shops'
// arcades (``Map3DScooter/addParkedRow(_:front:facing:width:r:)``), the
// rows only in the scene's closest layer (decision 267), standing still.
//
// The shapes are this project's own, flat-shaded side profiles and boxes,
// their proportions after the owner's TW3D pack
// (`railway-reference-private: Railway/tw3d-reference-clean/source/js/`
// `scooter-models.js` `SCOOTER_SPECS`, `stepParts`, `electricParts`: the
// wheels, the shield, the floorboard, the two-level seat, the top case,
// the box; `storefront-props.js`: the rows 0.74–0.81 m apart, nose in, a
// few tail in, the paints' shares), itself from slop-newyork (MIT,
// Copyright (c) 2026 Mr.doob). No brand marks, no delivery platform's
// colours.

/// Decision 446: the scooters' shapes.
enum Map3DScooter {
    /// The three kinds.
    enum Kind: CaseIterable, Sendable {
        /// The everyday 125 cc step-through, often with a top case.
        case step
        /// A battery-swap e-scooter: a taller shield, a slim upswept
        /// two-tone tail, no exhaust.
        case electric
        /// The step-through with a plain insulated box on a rack.
        case delivery
    }

    /// Within this distance of the eye, metres, a riding scooter is drawn
    /// in full; farther, decision 259's block scooter.
    static let detailReach: Float = 350

    /// How far apart the scooters of a row stand, metres (the reference's
    /// 0.74–0.81 m).
    static let rowSpacing: Float = 0.78

    // MARK: Colours (the street models' and the reference's neutrals)

    static let tyre = Map3DStreetModel.tyre
    static let black = Map3DColor.rgb(0x26292E)
    static let metal = Map3DColor.rgb(0x7A7F84)
    static let seat = Map3DStreetModel.seat
    static let trim = Map3DColor.rgb(0x2E3238)
    static let plate = Map3DColor.rgb(0xE9ECEF)
    static let topCase = Map3DColor.rgb(0x2E3136)
    /// The delivery box: plain dark navy, no platform's colours.
    static let box = Map3DColor.rgb(0x2E3B55)
    /// A parked scooter's paint, as many of each as the reference's
    /// Taipei shares (white 18, black and dark grey 23, silver and grey
    /// 19, red 11, blue 10, the pale greens 9, yellow and orange 5 of 100):
    /// the riding ones' colours (``Map3DStreetLife/scooterPaints``).
    static let paints: [UInt32] = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 4, 4, 5, 6, 0].map { colours[$0] }
    static let colours: [UInt32] = [0xF2F3F1, 0xC3C8CF, 0x3A4150, 0xD9473F, 0x3B7DD8, 0x8FD3C4, 0xF2C230].map(Map3DColor.rgb)
    /// The parked ones' paints, a shade off the riding ones' so that the
    /// city's look (decision 370) can tell them from the houses' colours
    /// and leave them as they are, as it leaves every vehicle.
    static let parkedPaints: [UInt32] = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 4, 4, 5, 6, 0].map { parkedColours[$0] }
    static let parkedColours: [UInt32] = [0xF1F3F1, 0xC2C8CF, 0x394150, 0xD8473F, 0x3A7DD8, 0x8ED3C4, 0xF1C230].map(Map3DColor.rgb)
    static let parkedTyre = Map3DColor.rgb(0x2A2D33)
    /// Every colour a parked scooter is drawn in (``Map3DLook/kept``).
    static let parked: Set<UInt32> = Set(parkedColours + [parkedTyre, seat, topCase, box])

    // MARK: Building

    /// A side `outline` (x forward, y up, metres; either turn) stood
    /// `width(x, y)` across the middle line: its two faces and its rim.
    static func addProfile(_ mesh: inout Map3DMesh, _ outline: [(Float, Float)], width: (Float, Float) -> Float, colour: UInt32) {
        var points = outline
        var area: Float = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.0 * b.1 - b.0 * a.1
        }
        if area < 0 { points.reverse() }
        let right = points.map { Map3DPoint($0.0, $0.1, width($0.0, $0.1) / 2) }
        let left = points.map { Map3DPoint($0.0, $0.1, -width($0.0, $0.1) / 2) }
        for (a, b, c) in triangulate(points) {
            // Seen from the right (+z) the outline turns counter-clockwise.
            mesh.addFacet([right[a], right[b], right[c]], color: colour)
            mesh.addFacet([left[a], left[c], left[b]], color: colour)
        }
        for index in points.indices {
            let next = (index + 1) % points.count
            mesh.addQuad(left[index], left[next], right[next], right[index], color: colour)
        }
    }

    /// The triangles of a simple counter-clockwise outline, cut ear by ear.
    static func triangulate(_ points: [(Float, Float)]) -> [(Int, Int, Int)] {
        var left = Array(points.indices), out: [(Int, Int, Int)] = []
        func cross(_ o: (Float, Float), _ a: (Float, Float), _ b: (Float, Float)) -> Float {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        while left.count > 3 {
            var cut = false
            for k in left.indices {
                let i = left[(k + left.count - 1) % left.count], j = left[k], n = left[(k + 1) % left.count]
                let a = points[i], b = points[j], c = points[n]
                guard cross(a, b, c) > 1e-9 else { continue }
                let inside = left.contains { m in
                    guard m != i, m != j, m != n else { return false }
                    let p = points[m]
                    return cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0
                }
                guard !inside else { continue }
                out.append((i, j, n))
                left.remove(at: k)
                cut = true
                break
            }
            // A degenerate outline: fan what is left.
            if !cut { break }
        }
        for k in 1..<max(left.count - 1, 1) { out.append((left[0], left[k], left[k + 1])) }
        return out
    }

    /// A wheel of radius `radius` at `x`, an octagon on its flat.
    static func addWheel(_ mesh: inout Map3DMesh, x: Float, radius: Float, width: Float) {
        let middle = radius * cosf(.pi / 8)
        let outline = (0..<8).map { k -> (Float, Float) in
            let angle = Float(k) * .pi / 4 + .pi / 8
            return (x + radius * cosf(angle), middle + radius * sinf(angle))
        }
        addProfile(&mesh, outline, width: { _, _ in width }, colour: tyre)
    }

    static func addBox(_ mesh: inout Map3DMesh, _ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float,
                       _ colour: UInt32, top: UInt32? = nil) {
        mesh.addBox(base: Map3DPoint(x, y, z), forward: Map3DPoint(1, 0, 0), length: length, width: width, height: height, top: top ?? colour,
                    side: colour)
    }

    /// Narrowing from `low` wide at the bottom of `y0…y1` to `high` at the
    /// top.
    static func tapered(_ low: Float, _ high: Float, _ y0: Float, _ y1: Float) -> (Float, Float) -> Float {
        { _, y in low + (high - low) * min(max((y - y0) / (y1 - y0), 0), 1) }
    }

    /// The scooter of `kind`, ridden: in the scene's axes (x its front, y
    /// up, +z its right), its tyres on y 0, painted `paint` (alpha 0 for
    /// the instance's colour); a top case when `topCase`.
    static func addBody(_ mesh: inout Map3DMesh, kind: Kind, paint: UInt32, topCase withCase: Bool) {
        func glowing(_ build: (inout Map3DMesh) -> Void) {
            let first = mesh.vertices.count
            build(&mesh)
            mesh.makeGlowing(from: first)
        }
        let electric = kind == .electric
        let radius: Float = electric ? 0.25 : 0.235
        addWheel(&mesh, x: electric ? 0.67 : 0.64, radius: radius, width: 0.11)
        addWheel(&mesh, x: electric ? -0.63 : -0.62, radius: radius, width: 0.12)
        // The fork, and the fender over the front wheel.
        addBox(&mesh, 0.6, radius - 0.02, 0, 0.07, 0.17, 0.62 - radius, black)
        addBox(&mesh, electric ? 0.69 : 0.66, radius * 2 + 0.02, 0, 0.36, 0.13, 0.045, paint)
        // The shield, the headlamp in it, the bar cover, the bars and
        // the mirrors on their stalks.
        if electric {
            addProfile(&mesh, [(0.31, 0.385), (0.48, 0.385), (0.6, 0.5), (0.618, 0.66), (0.61, 0.87), (0.52, 0.99), (0.42, 1.005), (0.35, 0.96)],
                       width: tapered(0.46, 0.3, 0.6, 1), colour: paint)
            glowing { addBox(&$0, 0.585, 0.79, 0, 0.06, 0.24, 0.12, Map3DStreetModel.headlamp) }
            addProfile(&mesh, [(0.3, 0.99), (0.52, 0.986), (0.545, 1.03), (0.45, 1.09), (0.33, 1.1), (0.285, 1.05)], width: { _, _ in 0.34 },
                       colour: paint)
        } else {
            addProfile(&mesh, [(0.31, 0.385), (0.47, 0.385), (0.59, 0.6), (0.585, 0.84), (0.5, 0.985), (0.4, 1.0), (0.34, 0.86)],
                       width: tapered(0.46, 0.32, 0.62, 1), colour: paint)
            glowing { addBox(&$0, 0.55, 0.81, 0, 0.06, 0.26, 0.09, Map3DStreetModel.headlamp) }
            addProfile(&mesh, [(0.3, 0.99), (0.5, 0.988), (0.535, 1.03), (0.495, 1.078), (0.33, 1.098), (0.285, 1.05)],
                       width: tapered(0.34, 0.24, 0.99, 1.1), colour: paint)
        }
        addBox(&mesh, 0.4, 1.035, 0, 0.04, 0.66, 0.035, black)
        for side: Float in [-1, 1] {
            addBox(&mesh, 0.38, 1.07, side * 0.25, 0.025, 0.025, 0.2, black)
            addBox(&mesh, 0.37, 1.25, side * 0.29, 0.03, electric ? 0.13 : 0.11, 0.07, black)
        }
        // The floorboard: its sides painted (the e-scooter's dark), a
        // rubber mat on top.
        addBox(&mesh, electric ? 0.11 : 0.12, 0.27, 0, electric ? 0.455 : 0.425, 0.41, 0.12, electric ? trim : paint, top: black)
        if electric {
            // The slim tail, painted over a dark lower half, narrowing to
            // its tip; the LED bar there; the swingarm on the left.
            let tail: (Float, Float) -> Float = { x, y in 0.4 * (1 - 0.72 * min(max((-x - 0.42) / 0.56, 0), 1)) * (1 - 0.12 * min(max((y - 0.66) / 0.14, 0), 1)) }
            addProfile(&mesh, [(-0.07, 0.6), (-0.055, 0.69), (-0.07, 0.72), (-0.7, 0.8), (-0.985, 0.905), (-0.965, 0.85), (-0.72, 0.705)],
                       width: tail, colour: paint)
            addProfile(&mesh, [(-0.1, 0.385), (-0.06, 0.5), (-0.07, 0.605), (-0.72, 0.71), (-0.962, 0.852), (-0.93, 0.8), (-0.66, 0.62),
                               (-0.4, 0.54), (-0.16, 0.42), (-0.12, 0.27), (-0.1, 0.27)],
                       width: { x, y in tail(x, y) * 0.97 }, colour: trim)
            addProfile(&mesh, [(0.06, 0.75), (0.035, 0.81), (-0.32, 0.818), (-0.41, 0.845), (-0.75, 0.872), (-0.815, 0.83), (-0.79, 0.79)],
                       width: { x, _ in 0.3 * (1 - 0.3 * min(max((-x - 0.55) / 0.27, 0), 1)) }, colour: seat)
            glowing { addBox(&$0, -0.97, 0.865, 0, 0.03, 0.12, 0.03, Map3DStreetModel.tailLamp) }
            addBox(&mesh, -0.94, 0.45, 0, 0.012, 0.2, 0.12, plate)
            addBox(&mesh, -0.35, 0.2, -0.13, 0.5, 0.07, 0.17, black)
        } else {
            // Under the seat to the tail; the two-level seat; the tail
            // lamp and the plate; the engine's case on the left, the
            // muffler on the right.
            addProfile(&mesh, [(-0.07, 0.27), (-0.07, 0.4), (-0.045, 0.72), (-0.8, 0.79), (-0.915, 0.74), (-0.86, 0.62), (-0.62, 0.552),
                               (-0.3, 0.45), (-0.12, 0.3)],
                       width: { x, y in 0.4 * (1 - 0.48 * min(max((-x - 0.48) / 0.44, 0), 1)) * (1 - 0.14 * min(max((y - 0.64) / 0.15, 0), 1)) },
                       colour: paint)
            addProfile(&mesh, [(0.06, 0.745), (0.035, 0.808), (-0.3, 0.815), (-0.4, 0.85), (-0.72, 0.865), (-0.81, 0.8), (-0.8, 0.752)],
                       width: { x, _ in 0.33 * (1 - 0.14 * min(max((-x - 0.62) / 0.2, 0), 1)) }, colour: seat)
            glowing { addBox(&$0, -0.9, 0.68, 0, 0.05, 0.2, 0.05, Map3DStreetModel.tailLamp) }
            addBox(&mesh, -0.93, 0.41, 0, 0.012, 0.2, 0.12, plate)
            addBox(&mesh, -0.38, 0.15, -0.14, 0.5, 0.085, 0.26, metal)
            addBox(&mesh, -0.56, 0.28, 0.17, 0.42, 0.1, 0.1, metal)
        }
        if kind == .delivery {
            // The plain box on its rack, over the passenger's seat.
            addBox(&mesh, -0.8, 0.85, 0, 0.44, 0.43, 0.02, metal)
            addBox(&mesh, -0.805, 0.87, 0, 0.49, 0.45, 0.44, box)
        } else if withCase {
            addProfile(&mesh, [(-0.66, 0.855), (-1.0, 0.855), (-1.045, 0.92), (-1.025, 1.06), (-0.95, 1.12), (-0.74, 1.12), (-0.662, 1.05)],
                       width: tapered(0.38, 0.33, 1, 1.12), colour: topCase)
        }
    }

    /// A parked scooter of `kind` in few triangles (no rider, no lamps
    /// lit, about 60), in the scene's axes as
    /// ``addBody(_:kind:paint:topCase:)``: its tyres, one outline for the
    /// shield, floorboard and body, its seat and its box.
    static func addParked(_ mesh: inout Map3DMesh, kind: Kind, paint: UInt32, topCase withCase: Bool) {
        let electric = kind == .electric
        for x: Float in electric ? [0.67, -0.63] : [0.64, -0.62] {
            // Its sides and tread ends only: the top is under the body.
            let low = Map3DPoint(x - 0.22, 0, 0), high = Map3DPoint(x + 0.22, 0, 0), up = Map3DPoint(0, 0.46, 0), side = Map3DPoint(0, 0, 0.055)
            mesh.addQuad(low + side, high + side, high + side + up, low + side + up, color: parkedTyre)
            mesh.addQuad(high - side, low - side, low - side + up, high - side + up, color: parkedTyre)
            mesh.addQuad(high + side, high - side, high - side + up, high + side + up, color: parkedTyre)
            mesh.addQuad(low - side, low + side, low + side + up, low - side + up, color: parkedTyre)
        }
        let tail: [(Float, Float)] = electric ? [(-0.06, 0.76), (-0.98, 0.9), (-0.6, 0.3)] : [(-0.05, 0.76), (-0.92, 0.78), (-0.6, 0.3)]
        addProfile(&mesh, [(0.15, 0.27), (0.6, 0.5), (0.5, 0.99), (0.36, 1.0), (0.28, 0.4), (-0.06, 0.4)] + tail,
                   width: { x, y in x > 0.25 ? 0.44 - 0.14 * min(max((y - 0.6) / 0.4, 0), 1) : 0.38 * (1 - 0.4 * min(max((-x - 0.5) / 0.45, 0), 1)) },
                   colour: paint)
        addBox(&mesh, -0.37, 0.76, 0, 0.84, 0.3, 0.1, seat)
        if kind == .delivery {
            addBox(&mesh, -0.805, 0.86, 0, 0.49, 0.45, 0.44, box)
        } else if withCase {
            addBox(&mesh, -0.85, 0.86, 0, 0.38, 0.38, 0.26, topCase)
        }
    }

    // MARK: Parked rows

    /// Where along a front `width` wide the scooters of a row stand, from
    /// its middle: from each end (clear of an arcade's pillars) toward
    /// the middle every ``rowSpacing``, leaving the shop's door open
    /// (1.2 m and a handlebar's half either side of the middle).
    static func rowSlots(width: Float) -> [Float] {
        let outer = width / 2 - 0.85, inner: Float = 0.6 + 0.33
        guard outer >= inner else { return [] }
        var slots: [Float] = []
        var at = outer
        while at >= inner - 1e-4 {
            slots += [-at, at]
            at -= rowSpacing
        }
        return slots.sorted()
    }

    /// Decision 446: a row of parked scooters at the street edge of a
    /// shop's arcade (騎樓) whose front, the house's face, is at `front`
    /// facing `facing`, `width` wide, in front of half the shops (the
    /// close layer's memory, decision 446): most nose in toward the shop,
    /// some rows tail in; a gap here and there, the door left open. Hashed
    /// from the house's `r`, so the same every time; nothing moves.
    static func addParkedRow(_ mesh: inout Map3DMesh, front: Map3DPoint, facing: Map3DPoint, width: Float, r: (Int32) -> Float) {
        guard r(300) < 0.5, let out = Map3DPoint(facing.x, 0, facing.z).normalized else { return }
        let across = Map3DPoint(-out.z, 0, out.x)
        let tailRow = r(301) < 0.12
        for (number, along) in rowSlots(width: width).enumerated() {
            let salt = Int32(310 + number * 8)
            guard r(salt) < 0.82 else { continue }
            let tailIn = tailRow ? r(salt + 1) < 0.85 : r(salt + 1) < 0.08
            let pick = r(salt + 2)
            let kind: Kind = pick < 0.6 ? .step : pick < 0.9 ? .electric : .delivery
            let paint = parkedPaints[min(Int(r(salt + 3) * Float(parkedPaints.count)), parkedPaints.count - 1)]
            // Its street end 0.1–0.25 m inside the arcade's edge.
            let inset = 0.1 + 0.15 * r(salt + 4)
            let forward = tailIn ? out : out * -1
            let foot = front - out * (inset + (tailIn ? 0.875 : 0.95)) + across * (along + (r(salt + 5) - 0.5) * 0.08)
            let yaw = (r(salt + 6) - 0.5) * 0.1
            let turned = forward * cosf(yaw) + across * sinf(yaw)
            var one = Map3DMesh()
            addParked(&one, kind: kind, paint: paint, topCase: r(salt + 7) < 0.5)
            mesh.append(one, at: foot, forward: turned)
        }
    }
}
