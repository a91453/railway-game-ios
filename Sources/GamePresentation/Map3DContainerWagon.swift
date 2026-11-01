import Foundation

/// Decision 539: the wagons of a freight line's train in the 3D map, behind
/// its R200 (``Map3DR200``): a container flat wagon carrying one 40 ft
/// container, two 20 ft ones, or (the last wagon) one with the red tail
/// marker lamp at its back end.
///
/// The references have no freight wagon (gap: the owner's Taiwan rail
/// garage's 62 models and the world edition's 120 are all passenger stock
/// and locomotives), so the wagon is this project's: an ISO 668 container
/// (12.192 × 2.438 × 2.591 m for 40 ft, 6.058 m for 20 ft) on a skeletal
/// flat wagon whose sizes are estimates of a Taiwan Railway container flat
/// wagon (14.2 m over couplers, the deck 1.1 m over the rail, two-axle
/// bogies 9.5 m apart, 860 mm wheels on the 1,067 mm gauge). No logos or
/// lettering; the containers' colours are plain.
///
/// Metres, +X the front, +Y left, +Z up, the rail at 0 (``Map3DModelPack``);
/// the builder works in x front, y up, z right and turns once at the end.
public enum Map3DContainerWagon {
    /// What a wagon carries.
    public enum Load: String, CaseIterable, Sendable {
        /// One 40 ft container, rust red.
        case forty
        /// Two 20 ft containers, blue and light grey.
        case twenties
        /// One 40 ft container, dark green.
        case fortyGreen
        /// The last wagon: one 40 ft container, ochre, and the red tail
        /// marker lamp on its back end.
        case tail
    }

    /// The steel is warm grey: a cool grey's shades read as the trains'
    /// glass (``Map3DTrainLights/isGlass(_:)``) and would light at night.
    public static let frame = Map3DColor.rgb(0x2F2D2A)
    public static let bogie = Map3DColor.rgb(0x292725)
    public static let metal = Map3DColor.rgb(0x67645E)
    public static let lock = Map3DColor.rgb(0xC9A23A)
    public static let rust = Map3DColor.rgb(0x9A4A36)
    public static let blue = Map3DColor.rgb(0x2F5F8F)
    public static let grey = Map3DColor.rgb(0xC6C9C5)
    public static let green = Map3DColor.rgb(0x2F6A50)
    public static let ochre = Map3DColor.rgb(0xC08A3A)

    /// The wagon's half length over its couplers.
    public static let halfLength: Float = 7.1
    /// The container floor over the rail.
    static let deck: Float = 1.12

    public static func model(_ load: Load, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.containerWagon(far: far)
        switch load {
        case .forty: b.container(x: 0, length: 12.192, colour: rust, far: far)
        case .fortyGreen: b.container(x: 0, length: 12.192, colour: green, far: far)
        case .tail: b.container(x: 0, length: 12.192, colour: ochre, far: far)
        case .twenties:
            b.container(x: 3.067, length: 6.058, colour: blue, far: far)
            b.container(x: -3.067, length: 6.058, colour: grey, far: far)
        }
        if load == .tail {
            // The tail marker lamp, on the back end sill's left (TRA's
            // freight trains end with a red marker).
            b.box(-halfLength + 0.36, 1.20, -1.05, 0.06, 0.20, 0.20, metal)
            let lens = b.mesh.vertices.count
            b.box(-halfLength + 0.32, 1.22, -1.05, 0.02, 0.16, 0.16, Map3DPalette.lantern)
            b.mesh.makeGlowing(from: lens)
        }
        return .flat(named: "container-wagon-\(load.rawValue)" + (far ? "-far" : ""), from: b.mesh)
    }
}

extension StationKitBuilder {
    /// The skeletal flat wagon, its couplers at ±``Map3DContainerWagon/halfLength``.
    fileprivate mutating func containerWagon(far: Bool) {
        let frame = Map3DContainerWagon.frame, metal = Map3DContainerWagon.metal, bogie = Map3DContainerWagon.bogie
        let end = Map3DContainerWagon.halfLength
        // Centre sill, side sills, end sills and the bolsters over the bogies.
        box(0, 0.74, 0, 13.6, 0.44, 0.36, frame)
        for side: Float in [-1, 1] { box(0, 0.86, side * 1.30, 13.7, 0.12, 0.24, frame) }
        for sign: Float in [-1, 1] {
            box(sign * 6.80, 0.72, 0, 0.20, 2.74, 0.40, frame)
            box(sign * 4.75, 0.74, 0, 0.60, 2.60, 0.34, frame)
        }
        // Cross bearers carrying the container's floor.
        for x in stride(from: Float(-6.0), through: 6.0, by: far ? 3.0 : 1.5) where abs(abs(x) - 4.75) > 0.4 {
            box(x, 0.94, 0, 0.14, 2.56, 0.14, frame)
        }
        for sign: Float in [-1, 1] {
            // The twist-lock pedestals at the corners of a 40 ft and of two
            // 20 ft containers.
            for x: Float in [6.0, 0.08] {
                for side: Float in [-1, 1] { box(sign * x, 1.08, side * 1.13, 0.20, 0.16, 0.04, Map3DContainerWagon.lock) }
            }
            // Coupler, draft gear and the brake hose.
            box(sign * 6.98, 0.72, 0, 0.24, 0.26, 0.26, metal)
            box(sign * (end - 0.05), 0.66, 0, 0.10, 0.34, 0.38, metal)
            if !far {
                civicTube(Map3DPoint(sign * 6.92, 0.66, -0.36), Map3DPoint(sign * 7.02, 0.40, -0.40), radius: 0.03, color: bogie, sides: 6)
                // Corner steps and grab irons.
                for side: Float in [-1, 1] {
                    box(sign * 6.55, 0.36, side * 1.34, 0.42, 0.06, 0.04, metal)
                    beam(Map3DPoint(sign * 6.38, 0.36, side * 1.36), Map3DPoint(sign * 6.38, 0.92, side * 1.36), 0.03, metal)
                    beam(Map3DPoint(sign * 6.72, 0.36, side * 1.36), Map3DPoint(sign * 6.72, 0.92, side * 1.36), 0.03, metal)
                    beam(Map3DPoint(sign * 6.90, 0.98, side * 1.20), Map3DPoint(sign * 6.90, 0.98, side * 0.70), 0.03, metal)
                }
            }
        }
        if !far {
            // The hand brake wheel on the front end.
            civicTube(Map3DPoint(6.92, 1.02, 0.85), Map3DPoint(6.96, 1.02, 0.85), radius: 0.20, color: metal, sides: 10)
            // The brake cylinder and reservoir under the frame.
            civicTube(Map3DPoint(-1.4, 0.56, 0.55), Map3DPoint(-0.2, 0.56, 0.55), radius: 0.20, color: bogie, sides: 10)
            civicTube(Map3DPoint(0.4, 0.58, -0.55), Map3DPoint(1.2, 0.58, -0.55), radius: 0.15, color: bogie, sides: 8)
        }
        // Two two-axle bogies: side frames, axle boxes, wheels and axles.
        for centre: Float in [-4.75, 4.75] {
            box(centre, 0.56, 0, 0.50, 1.80, 0.18, bogie)
            for side: Float in [-1, 1] {
                box(centre, 0.30, side * 0.86, 2.50, 0.14, 0.26, bogie)
                if !far { cylinder(centre, 0.48, side * 0.86, radius: 0.12, height: 0.10, color: metal, sides: 8) }
                for dx: Float in [-0.95, 0.95] {
                    civicTube(Map3DPoint(centre + dx, 0.43, side * 0.48), Map3DPoint(centre + dx, 0.43, side * 0.62),
                              radius: 0.43, color: bogie, sides: far ? 8 : 14)
                    box(centre + dx, 0.30, side * 0.86, 0.30, 0.22, 0.26, metal)
                    if !far {
                        civicTube(Map3DPoint(centre + dx, 0.43, side * 0.615), Map3DPoint(centre + dx, 0.43, side * 0.63),
                                  radius: 0.30, color: Map3DColor.shaded(metal, 0.68), sides: 10)
                    }
                }
            }
            for dx: Float in [-0.95, 0.95] { beam(Map3DPoint(centre + dx, 0.43, -0.80), Map3DPoint(centre + dx, 0.43, 0.80), 0.12, metal) }
        }
    }

    /// One ISO container centred at `x`, standing on the wagon's floor: its
    /// corrugated sides, the corner posts and castings, and its doors at
    /// the back (−X) end.
    fileprivate mutating func container(x centre: Float, length: Float, colour: UInt32, far: Bool) {
        let deck = Map3DContainerWagon.deck, width: Float = 2.438, height: Float = 2.591
        let half = length / 2, dark = Map3DColor.shaded(colour, 0.72), post = Map3DColor.shaded(colour, 0.80)
        box(centre, deck, 0, length - 0.02, width - 0.04, height, colour)
        // Corner posts and the top and bottom side rails.
        for sx: Float in [-1, 1] {
            for side: Float in [-1, 1] {
                box(centre + sx * (half - 0.08), deck, side * (width / 2 - 0.08), 0.17, 0.17, height, post)
                box(centre + sx * (half - 0.09), deck, side * (width / 2 - 0.09), 0.19, 0.19, 0.12, Map3DContainerWagon.frame)
                box(centre + sx * (half - 0.09), deck + height - 0.12, side * (width / 2 - 0.09), 0.19, 0.19, 0.12, Map3DContainerWagon.frame)
            }
        }
        for side: Float in [-1, 1] {
            box(centre, deck, side * (width / 2 - 0.02), length - 0.30, 0.06, 0.16, dark)
            box(centre, deck + height - 0.16, side * (width / 2 - 0.02), length - 0.30, 0.06, 0.16, post)
            // The corrugation: raised ribs standing out of each side.
            if !far {
                for x in stride(from: centre - half + 0.40, through: centre + half - 0.40, by: Float(0.28)) {
                    box(x, deck + 0.16, side * (width / 2 + 0.005), 0.12, 0.03, height - 0.32, post)
                }
            }
        }
        // The roof's slight panels and the front end's corrugation.
        if !far {
            for x in stride(from: centre - half + 0.6, through: centre + half - 0.6, by: Float(1.2)) {
                box(x, deck + height, 0, 0.08, width - 0.30, 0.015, post)
            }
            for z in stride(from: Float(-0.9), through: 0.9, by: 0.3) {
                box(centre + half + 0.005, deck + 0.16, z, 0.03, 0.12, height - 0.32, post)
            }
        }
        // The doors: two leaves, their locking bars and handles.
        let back = centre - half - 0.005
        box(back, deck + 0.10, 0, 0.03, 0.03, height - 0.22, dark)
        for side: Float in [-1, 1] {
            for bar: Float in [0.30, 0.82] {
                let z = side * bar
                if far {
                    box(back - 0.02, deck + 0.14, z, 0.03, 0.05, height - 0.28, Map3DContainerWagon.metal)
                } else {
                    beam(Map3DPoint(back - 0.03, deck + 0.10, z), Map3DPoint(back - 0.03, deck + height - 0.10, z), 0.04, Map3DContainerWagon.metal)
                    box(back - 0.04, deck + 1.05, z + side * 0.10, 0.04, 0.22, 0.05, Map3DContainerWagon.metal)
                    for h: Float in [deck + 0.25, deck + height - 0.35] {
                        box(back - 0.02, h, z, 0.04, 0.10, 0.10, Map3DContainerWagon.metal)
                    }
                }
            }
        }
    }
}
