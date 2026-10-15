import Foundation

// Decision 235: the shapes the city's buildings are put together from,
// beyond the box: pitched and hipped roofs, sawtooth roofs, cylinders
// (tanks, chimneys, towers). Each is a handful of faces: the 3D map draws
// thousands of buildings at once.

extension Map3DMesh {
    /// A pitched roof over a `length` × `width` box whose walls stop at
    /// `base` (the middle of the box's top): the ridge along `forward`,
    /// `rise` above the eaves, the eaves `overhang` past the walls all
    /// round. Both slopes in `color` (painted with `paint`); the two
    /// gables, the triangles under the ridge's ends, in `gable`.
    public mutating func addGableRoof(base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, rise: Float,
                                      overhang: Float = 0.4, color: UInt32, gable: UInt32, paint: Map3DPaint? = nil) {
        guard length > 0, width > 0, rise > 0, let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (length / 2 + overhang), r = across * (width / 2 + overhang), up = Map3DPoint(0, rise, 0)
        // The eaves drop with the slope over the overhang.
        let drop = Map3DPoint(0, -rise * overhang / (width / 2), 0)
        let ridgeFront = base + f + up, ridgeBack = base - f + up
        let eaves = [base + f - r + drop, base + f + r + drop, base - f + r + drop, base - f - r + drop]
        addFacet([ridgeFront, ridgeBack, eaves[2], eaves[1]], color: Map3DColor.shaded(color, 0.95), paint: paint)
        addFacet([ridgeBack, ridgeFront, eaves[0], eaves[3]], color: Map3DColor.shaded(color, 0.82), paint: paint)
        // The gables stand on the walls, not the eaves.
        let wallFront = along * (length / 2), wallSide = across * (width / 2)
        addFacet([base + wallFront + up, base + wallFront + wallSide, base + wallFront - wallSide], color: Map3DColor.shaded(gable, 0.9))
        addFacet([base - wallFront + up, base - wallFront - wallSide, base - wallFront + wallSide], color: Map3DColor.shaded(gable, 0.75))
    }

    /// A hipped roof: four slopes rising `rise` to a ridge along `forward`
    /// (a point when the roof is square), the eaves `overhang` past the
    /// walls. A temple's roof when `sweep` lifts the four corners.
    public mutating func addHipRoof(base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, rise: Float,
                                    overhang: Float = 0.5, sweep: Float = 0, color: UInt32, paint: Map3DPaint? = nil) {
        guard length > 0, width > 0, rise > 0, let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let halfLength = length / 2 + overhang, halfWidth = width / 2 + overhang
        let ridge = max(0, halfLength - halfWidth)
        let up = Map3DPoint(0, rise, 0), lift = Map3DPoint(0, sweep, 0)
        let ridgeFront = base + along * ridge + up, ridgeBack = base - along * ridge + up
        let corners = [base + along * halfLength - across * halfWidth + lift, base + along * halfLength + across * halfWidth + lift,
                       base - along * halfLength + across * halfWidth + lift, base - along * halfLength - across * halfWidth + lift]
        // Front, right, back and left slopes.
        addFacet([ridgeFront, corners[1], corners[0]], color: Map3DColor.shaded(color, 0.92), paint: paint)
        addFacet([ridgeFront, ridgeBack, corners[2], corners[1]], color: Map3DColor.shaded(color, 0.98), paint: paint)
        addFacet([ridgeBack, corners[3], corners[2]], color: Map3DColor.shaded(color, 0.78), paint: paint)
        addFacet([ridgeBack, ridgeFront, corners[0], corners[3]], color: Map3DColor.shaded(color, 0.85), paint: paint)
    }

    /// A sawtooth roof over a `length` × `width` shed, its teeth running
    /// across `forward`: each a steep glazed face toward `forward` (north
    /// light) and a long slope back, `rise` high.
    public mutating func addSawtoothRoof(base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, teeth: Int,
                                         rise: Float, color: UInt32, glazing: UInt32, paint: Map3DPaint? = nil) {
        guard teeth > 0, length > 0, width > 0, let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let step = length / Float(teeth), r = across * (width / 2), up = Map3DPoint(0, rise, 0)
        for tooth in 0..<teeth {
            let front = base + along * (length / 2 - Float(tooth) * step), back = front - along * step
            // The glazed face, upright, facing forward.
            addFacet([front - r + up, front + r + up, front + r, front - r], color: glazing)
            // The slope from the top of the glazing down to the back.
            addFacet([front - r + up, back - r, back + r, front + r + up], color: color, paint: paint)
            // The two triangles at the ends of the tooth.
            addFacet([front + r + up, back + r, front + r], color: Map3DColor.shaded(color, 0.8))
            addFacet([front - r + up, front - r, back - r], color: Map3DColor.shaded(color, 0.7))
        }
    }

    /// An arched (barrel) roof over a `length` × `width` shed, its arch
    /// across `forward`, `rise` high at the crown: `segments` flat strips
    /// along the shed, and the two arched ends in `end`.
    public mutating func addBarrelRoof(base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, rise: Float,
                                       segments: Int = 6, color: UInt32, end: UInt32, paint: Map3DPaint? = nil) {
        guard segments >= 2, length > 0, width > 0, rise > 0, let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (length / 2)
        // The arch from the left wall over to the right one: a parabola.
        let arch = (0...segments).map { index -> Map3DPoint in
            let t = Float(index) / Float(segments) * 2 - 1
            return base + across * (t * width / 2) + Map3DPoint(0, rise * (1 - t * t), 0)
        }
        for index in 0..<segments {
            let a = arch[index], b = arch[index + 1]
            let shade = 0.78 + 0.2 * Float(index) / Float(segments - 1)
            addFacet([a - f, b - f, b + f, a + f], color: Map3DColor.shaded(color, shade), paint: paint)
        }
        // The ends, fans from the middle of the walls' top.
        addFacet([base + f] + arch.map { $0 + f }, color: Map3DColor.shaded(end, 0.9))
        addFacet([base - f] + arch.reversed().map { $0 - f }, color: Map3DColor.shaded(end, 0.75))
    }

    /// An upright cylinder of `sides` faces standing on `base`: a tank, a
    /// chimney, a water tower's drum. Capped with `top` unless `capped` is
    /// false.
    public mutating func addCylinder(base: Map3DPoint, radius: Float, height: Float, sides: Int = 8, top: UInt32, side: UInt32,
                                     paint: Map3DPaint? = nil, capped: Bool = true) {
        guard radius > 0, height > 0, sides >= 3 else { return }
        let up = Map3DPoint(0, height, 0)
        let ring = (0..<sides).map { index -> Map3DPoint in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return base + Map3DPoint(cosf(angle) * radius, 0, sinf(angle) * radius)
        }
        for index in 0..<sides {
            let a = ring[index], b = ring[(index + 1) % sides]
            // Lit from the south-west: the faces toward it lighter.
            let facing = (a + b) * 0.5 - base
            let shade = 0.8 + 0.15 * ((facing.z - facing.x) / (radius * 1.42))
            addFacet([b, a, a + up, b + up], color: Map3DColor.shaded(side, shade), paint: paint)
        }
        if capped { addFacet(ring.reversed().map { $0 + up }, color: top) }
    }
}
