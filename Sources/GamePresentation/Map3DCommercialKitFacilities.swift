import Foundation

extension StationKitBuilder {
    mutating func commercialFacility(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .verticalNeonSign:
            // Wall-mounted vertical blade sign (starts at x=0 extending in +x)
            // Mounting wall brackets
            for hy: Float in [0.8, 4.2] {
                box(0.25, hy, 0, 0.50, 0.08, 0.08, Self.steel)
            }
            // Vertical structural support pole
            cylinder(0.50, 0.4, 0, radius: 0.06, height: 4.2, color: Self.steel, sides: 6)
            // 3 Stacked illuminated lightboxes
            for i in 0..<3 {
                let sy: Float = 0.6 + Float(i) * 1.3
                let boxColor = i == 0 ? Self.commRed : i == 1 ? Self.commYellow : Self.commBlue
                box(0.95, sy, 0, 0.85, 0.22, 1.15, boxColor)
                // Contrasting letter face
                box(0.95, sy + 0.1, 0.12, 0.70, 0.03, 0.95, Map3DPalette.tileWhite)
                box(0.95, sy + 0.1, -0.12, 0.70, 0.03, 0.95, Map3DPalette.tileWhite)
            }

        case .horizontalSignboard:
            // Wall-mounted horizontal commercial fascia sign (starts at x=0)
            box(0.12, 0.3, 0, 0.24, 4.2, 1.1, Map3DPalette.counters[1])
            // Front sign face
            box(0.25, 0.35, 0, 0.03, 4.0, 0.95, Self.commYellow)
            // 3 Overhead gooseneck LED spotlight fixtures
            for i in 0..<3 {
                let sz: Float = -1.4 + Float(i) * 1.4
                beam(Map3DPoint(0.05, 1.4, sz), Map3DPoint(0.55, 1.6, sz), 0.04, Self.steel)
                cylinder(0.55, 1.50, sz, radius: 0.08, height: 0.12, color: Self.steel, sides: 6)
            }

        case .totemLightbox:
            // Freestanding double-sided illuminated commercial totem
            box(0, 0, 0, 0.8, 1.4, 0.18, Map3DPalette.concrete) // base plate
            box(0, 0.18, 0, 0.35, 1.2, 3.4, Self.commBlue) // vertical body
            // Dual-sided advertising poster panels
            for sign: Float in [-1, 1] {
                box(sign * 0.19, 0.6, 0, 0.03, 0.95, 2.5, Map3DPalette.tileWhite)
            }

        case .aFrameSign:
            // Sidewalk folding chalkboard menu sign
            let thickness: Float = 0.06, width: Float = 0.75, height: Float = 1.05
            // Two inclined wooden chalkboard leaves
            for (sign, angle): (Float, Float) in [(-1, 0.18), (1, -0.18)] {
                let p1 = Map3DPoint(sign * 0.28, 0, -width / 2)
                let p2 = Map3DPoint(sign * 0.02, height, -width / 2)
                let p3 = Map3DPoint(sign * 0.02, height, width / 2)
                let p4 = Map3DPoint(sign * 0.28, 0, width / 2)
                mesh.addQuad(p1, p2, p3, p4, color: Map3DPalette.counters[1])
                mesh.addQuad(p4 + Map3DPoint(0, 0, thickness), p3 + Map3DPoint(0, 0, thickness),
                             p2 + Map3DPoint(0, 0, thickness), p1 + Map3DPoint(0, 0, thickness), color: Map3DPalette.counters[0])
            }
            // Blackboard chalkboard center
            box(0, 0.15, 0, 0.40, 0.62, 0.75, Map3DPalette.playerRim)
            // Metal restraint chain
            beam(Map3DPoint(-0.16, 0.45, 0), Map3DPoint(0.16, 0.45, 0), 0.02, Self.steel)

        case .commercialBannerPole:
            // Streetlight pole with twin commercial fabric event banners
            cylinder(0, 0, 0, radius: 0.20, height: 0.45, color: Map3DPalette.concrete, sides: 8) // base
            cylinder(0, 0.45, 0, radius: 0.08, height: 4.8, color: Self.steel, sides: 8) // main pole
            // Top luminaire
            cylinder(0, 5.25, 0, radius: 0.35, height: 0.25, color: Self.commYellow, sides: 8)
            // Twin banner cantilever brackets
            for by: Float in [2.2, 4.4] {
                beam(Map3DPoint(0, by, -0.9), Map3DPoint(0, by, 0.9), 0.04, Self.steel)
            }
            // Left and right fabric banners
            for sign: Float in [-0.55, 0.55] {
                box(0, 2.2, sign, 0.02, 0.65, 2.2, Self.commBlue)
            }

        case .retractableAwning:
            // Wall-mounted folding arm awning (starts at wall x=0)
            box(0.06, 0.8, 0, 0.12, 3.6, 0.18, Self.steel) // wall mounting bar
            // Folding scissor arms
            for az: Float in [-1.5, 1.5] {
                beam(Map3DPoint(0.08, 0.8, az), Map3DPoint(1.1, 0.65, az), 0.05, Self.steel)
                beam(Map3DPoint(1.1, 0.65, az), Map3DPoint(2.1, 0.5, az), 0.05, Self.steel)
            }
            // Sloped fabric canopy
            let p1 = Map3DPoint(0.08, 0.88, -1.8)
            let p2 = Map3DPoint(2.2, 0.52, -1.8)
            let p3 = Map3DPoint(2.2, 0.52, 1.8)
            let p4 = Map3DPoint(0.08, 0.88, 1.8)
            mesh.addQuad(p1, p2, p3, p4, color: Self.commYellow)
            mesh.addQuad(p4 - Map3DPoint(0, 0.04, 0), p3 - Map3DPoint(0, 0.04, 0),
                         p2 - Map3DPoint(0, 0.04, 0), p1 - Map3DPoint(0, 0.04, 0), color: Map3DPalette.counters[1])
            // Front scalloped valance
            box(2.2, 0.34, 0, 0.04, 3.6, 0.18, Self.commRed)

        case .cafeUmbrellaSet:
            // Cast iron base, bistro table, parasol and 3 chairs
            cylinder(0, 0, 0, radius: 0.35, height: 0.06, color: Map3DPalette.playerRim, sides: 12)
            cylinder(0, 0.06, 0, radius: 0.05, height: 2.3, color: Self.steel, sides: 8) // center pole
            // Bistro tabletop
            cylinder(0, 0.70, 0, radius: 0.65, height: 0.04, color: Map3DPalette.tileWhite, sides: 12)
            // Octagonal umbrella parasol canopy
            canopy(0, 1.9, 0, length: 2.6, width: 2.6, rise: 0.55, color: Self.commMint)
            // 3 Surrounding cafe chairs
            for i in 0..<3 {
                let a = Float(i) * 2 * Float.pi / 3.0
                let cx = cosf(a) * 0.95, cz = sinf(a) * 0.95
                cylinder(cx, 0, cz, radius: 0.22, height: 0.44, color: Map3DPalette.counters[1], sides: 8)
                cylinder(cx, 0, cz, radius: 0.04, height: 0.40, color: Self.steel, sides: 6) // leg
                // Backrest
                cylinder(cx * 1.15, 0.44, cz * 1.15, radius: 0.22, height: 0.38, color: Map3DPalette.counters[1], sides: 6)
            }

        case .commercialPlanter:
            // Concrete street planter with shrubs and stainless steel guide rail
            box(0, 0, 0, 1.1, 3.2, 0.55, Map3DPalette.concrete)
            box(0, 0.55, 0, 0.95, 3.0, 0.08, Map3DPalette.playerRoof) // soil
            // Shrub foliage
            for i in 0..<3 {
                let pz: Float = -0.9 + Float(i) * 0.9
                cylinder(0, 0.60, pz, radius: 0.42, height: 0.55, color: Map3DProp.greens[i], sides: 8)
            }
            // Stainless pedestrian guide railing along rear
            for sign: Float in [-1.4, 1.4] {
                cylinder(-0.45, 0.55, sign, radius: 0.04, height: 0.55, color: Self.steel, sides: 6)
            }
            beam(Map3DPoint(-0.45, 1.1, -1.4), Map3DPoint(-0.45, 1.1, 1.4), 0.06, Self.steel)

        case .commercialRecycling:
            // 3-stream commercial stainless sorting station (General, Recycle, Paper)
            box(0, 0, 0, 0.85, 2.4, 0.95, Self.steel)
            let binColors = [Map3DPalette.playerRim, Self.commYellow, Self.commBlue]
            for i in 0..<3 {
                let pz: Float = -0.75 + Float(i) * 0.75
                box(0, 0.95, pz, 0.75, 0.65, 0.08, binColors[i]) // color-coded top lid
                cylinder(0, 1.03, pz, radius: 0.16, height: 0.04, color: Map3DPalette.playerRim, sides: 8) // opening
            }

        case .coolingTower:
            // Commercial rooftop cooling tower unit with fan cowl
            box(0, 0, 0, 2.6, 2.6, 0.25, Self.steel) // steel skid base
            box(0, 0.25, 0, 2.4, 2.4, 1.8, Map3DPalette.tileWhite) // main casing
            // Louver ventilation grilles on sides
            for side: Float in [-1.22, 1.22] {
                box(0, 0.45, side, 2.2, 0.04, 1.3, Map3DPalette.playerRim)
            }
            // Top circular fan cowl
            cylinder(0, 2.05, 0, radius: 0.95, height: 0.55, color: Map3DPalette.concrete, sides: 12)
            cylinder(0, 2.60, 0, radius: 0.88, height: 0.06, color: Self.steel, sides: 8) // fan grill

        case .fireEscapeStair:
            // Exterior architectural steel fire escape stair (mounts to wall at x=0)
            // Landing platform at height 3.2m
            box(1.0, 3.2, 0, 2.0, 1.8, 0.12, Self.steel)
            // Safety railing around landing
            box(2.0, 3.32, 0, 0.08, 1.8, 0.9, Self.steel)
            box(1.0, 3.32, -0.9, 2.0, 0.08, 0.9, Self.steel)
            // Stairs running down to ground
            stairs(1.0, 0, 1.8, run: 2.8, width: 1.1, rise: 3.2)
            // Heavy wall anchor brackets into facade
            for hy: Float in [0.5, 3.2] {
                box(0.2, hy, -0.8, 0.4, 0.12, 0.12, Self.steel)
                box(0.2, hy, 0.8, 0.4, 0.12, 0.12, Self.steel)
            }

        case .transitFeederBus:
            // Modern Taiwanese low-floor electric transit feeder bus
            // Remodeled from reference photos: streamlined roof, panoramic curved front, low floor, dual doors, roof HVAC
            let length: Float = 10.4, width: Float = 2.5, bodyHeight: Float = 2.7
            let chassisY: Float = 0.35

            // Main bus lower body skirt (Crisp white)
            box(0, chassisY, 0, length, width, 0.75, Map3DPalette.tileWhite)

            // Upper bus body & window band (Mint green + tinted dark glass)
            box(0, chassisY + 0.75, 0, length, width, 1.45, Map3DPalette.playerRim) // glass band
            // Window framing pillars
            for i in -3...3 {
                let px = Float(i) * 1.3
                box(px, chassisY + 0.75, -width / 2, 0.12, 0.04, 1.45, Self.commMint)
                box(px, chassisY + 0.75, width / 2, 0.12, 0.04, 1.45, Self.commMint)
            }

            // Streamlined curved roof structure (Taiwanese transit mint green)
            box(0, chassisY + 2.2, 0, length, width, 0.45, Self.commMint)
            // Aerodynamic forward slope over driver cab
            let rf1 = Map3DPoint(length / 2 - 1.8, chassisY + 2.65, -width / 2)
            let rf2 = Map3DPoint(length / 2 + 0.1, chassisY + 2.30, -width / 2)
            let rf3 = Map3DPoint(length / 2 + 0.1, chassisY + 2.30, width / 2)
            let rf4 = Map3DPoint(length / 2 - 1.8, chassisY + 2.65, width / 2)
            mesh.addQuad(rf1, rf2, rf3, rf4, color: Self.commMint)

            // Front panoramic curved windshield
            pane(length / 2 + 0.02, chassisY + 0.75, 0, width - 0.25, 1.45)
            // Destination LED marquee display visor over windshield
            box(length / 2 - 0.05, chassisY + 2.22, 0, 0.25, 1.8, 0.32, Map3DPalette.trainAccent)

            // Low-floor passenger entrance double doors on right side
            // Front door at x = 2.8, Center door at x = -0.8
            for doorX: Float in [2.8, -0.8] {
                box(doorX, chassisY, -width / 2 - 0.02, 1.25, 0.05, 1.95, Self.steel)
                // Glazed door leaves
                pane(doorX, chassisY + 0.35, -width / 2 - 0.03, 1.05, 1.4)
            }

            // Driver windshield wipers
            beam(Map3DPoint(length / 2 + 0.04, chassisY + 0.85, -0.4), Map3DPoint(length / 2 + 0.04, chassisY + 1.25, 0.1), 0.03, Map3DPalette.playerRim)
            beam(Map3DPoint(length / 2 + 0.04, chassisY + 0.85, 0.4), Map3DPoint(length / 2 + 0.04, chassisY + 1.25, 0.9), 0.03, Map3DPalette.playerRim)

            // Rear engine / battery ventilation louvers & rear window
            pane(-length / 2 - 0.02, chassisY + 1.25, 0, width - 0.4, 0.95)
            box(-length / 2 - 0.02, chassisY + 0.45, 0, 0.04, 1.9, 0.65, Map3DPalette.playerRim)

            // Styled front headlights & rear taillights
            for sign: Float in [-0.95, 0.95] {
                cylinder(length / 2 + 0.02, chassisY + 0.45, sign, radius: 0.12, height: 0.04, color: Map3DPalette.trainYellow, sides: 8)
                cylinder(-length / 2 - 0.02, chassisY + 0.45, sign, radius: 0.12, height: 0.04, color: Self.commRed, sides: 8)
            }

            // Roof-mounted battery / HVAC pod with aerodynamic fairing
            box(0, chassisY + 2.65, 0, 3.8, 1.9, 0.45, Map3DPalette.tileWhite)
            box(0, chassisY + 2.75, 0, 3.2, 1.6, 0.25, Self.steel) // cooling vents

            // 4 Low-floor bus wheels (front steer, rear duals) with wheel arches
            commWheel(2.9, 0, -width / 2 + 0.05, radius: 0.46, width: 0.28)
            commWheel(2.9, 0, width / 2 - 0.05, radius: 0.46, width: 0.28)
            commWheel(-2.9, 0, -width / 2 + 0.05, radius: 0.48, width: 0.36)
            commWheel(-2.9, 0, width / 2 - 0.05, radius: 0.48, width: 0.36)
        default:
            break
        }
    }
}
