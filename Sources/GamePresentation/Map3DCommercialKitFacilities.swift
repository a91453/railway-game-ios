import Foundation

extension StationKitBuilder {
    mutating func commercialFacility(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .verticalNeonSign:
            for hy: Float in [0.8, 4.2] {
                box(0.25, hy, 0, 0.50, 0.08, 0.08, Self.steel)
            }
            cylinder(0.50, 0.4, 0, radius: 0.06, height: 4.2, color: Self.steel, sides: 6)
            let colors = [Self.commRed, Self.commYellow, Self.commBlue]
            for i in 0..<3 {
                let sy: Float = 0.6 + Float(i) * 1.3
                box(0.95, sy, 0, 0.85, 0.22, 1.15, colors[i])
                box(0.95, sy + 0.1, 0.12, 0.70, 0.03, 0.95, Self.commWarmWhite)
                box(0.95, sy + 0.1, -0.12, 0.70, 0.03, 0.95, Self.commWarmWhite)
            }

        case .horizontalSignboard:
            box(0.12, 0.3, 0, 0.24, 4.2, 1.1, Map3DPalette.counters[1])
            box(0.25, 0.35, 0, 0.03, 4.0, 0.95, Self.commYellow)
            for i in 0..<3 {
                let sz: Float = -1.4 + Float(i) * 1.4
                beam(Map3DPoint(0.05, 1.4, sz), Map3DPoint(0.55, 1.6, sz), 0.04, Self.steel)
                cylinder(0.55, 1.50, sz, radius: 0.08, height: 0.12, color: Self.steel, sides: 6)
            }

        case .totemLightbox:
            box(0, 0, 0, 0.9, 1.5, 0.18, Self.commConcrete)
            box(0, 0.18, 0, 0.38, 1.3, 3.5, Self.commBlue)
            for sign: Float in [-1, 1] {
                box(sign * 0.20, 0.6, 0, 0.04, 1.05, 2.6, Self.commWarmWhite)
                box(sign * 0.22, 1.2, 0, 0.02, 0.95, 1.8, Self.commWarmGlow)
            }

        case .aFrameSign:
            box(0, 0, 0, 0.58, 0.78, 1.10, Self.commWarmWood)
            box(0, 0.18, 0, 0.62, 0.65, 0.78, Self.commDark)
            box(0.32, 0.35, 0, 0.02, 0.50, 0.55, Self.commYellow)
            beam(Map3DPoint(-0.18, 0.45, 0), Map3DPoint(0.18, 0.45, 0), 0.02, Self.steel)

        case .commercialBannerPole:
            cylinder(0, 0, 0, radius: 0.22, height: 0.45, color: Self.commConcrete, sides: 8)
            cylinder(0, 0.45, 0, radius: 0.08, height: 5.0, color: Self.steel, sides: 8)
            cylinder(0, 5.45, 0, radius: 0.35, height: 0.25, color: Self.commYellow, sides: 8)
            for by: Float in [2.2, 4.6] {
                beam(Map3DPoint(0, by, -1.0), Map3DPoint(0, by, 1.0), 0.04, Self.steel)
            }
            for sign: Float in [-0.60, 0.60] {
                box(0, 2.2, sign, 0.03, 0.75, 2.4, Self.commBlue)
                box(0, 2.6, sign, 0.04, 0.60, 1.6, Self.commWarmWhite)
            }

        case .retractableAwning:
            box(0.06, 0.8, 0, 0.12, 3.8, 0.18, Self.steel)
            for az: Float in [-1.6, 1.6] {
                beam(Map3DPoint(0.08, 0.8, az), Map3DPoint(1.1, 0.65, az), 0.05, Self.steel)
                beam(Map3DPoint(1.1, 0.65, az), Map3DPoint(2.2, 0.5, az), 0.05, Self.steel)
            }
            commStripedAwning(1.2, 0.52, 0, length: 2.2, width: 3.8, rise: 0.38, color1: Self.commYellow, color2: Self.commWarmWhite, stripes: 6)
            box(2.3, 0.34, 0, 0.04, 3.8, 0.20, Self.commRed)

        case .cafeUmbrellaSet:
            cylinder(0, 0, 0, radius: 0.38, height: 0.06, color: Self.commDark, sides: 12)
            cylinder(0, 0.06, 0, radius: 0.05, height: 2.4, color: Self.steel, sides: 8)
            cylinder(0, 0.72, 0, radius: 0.72, height: 0.05, color: Self.commWarmWood, sides: 12)
            canopy(0, 2.0, 0, length: 2.8, width: 2.8, rise: 0.65, color: Self.commMint)

            for i in 0..<4 {
                let a = Float(i) * 2 * Float.pi / 4.0
                let cx = cosf(a) * 1.05, cz = sinf(a) * 1.05
                cylinder(cx, 0, cz, radius: 0.24, height: 0.45, color: Self.commWarmWood, sides: 8)
                cylinder(cx * 1.15, 0.45, cz * 1.15, radius: 0.24, height: 0.40, color: Self.steel, sides: 8)
            }

        case .commercialPlanter:
            box(0, 0, 0, 1.4, 2.8, 0.75, Self.commConcrete)
            box(0, 0.75, 0, 1.25, 2.65, 0.45, Map3DPalette.greens[1])
            for i in -1...1 {
                cylinder(0, 1.2, Float(i) * 0.85, radius: 0.22, height: 0.15, color: Self.commRed, sides: 6)
            }

        case .commercialRecycling:
            box(0, 0, 0, 0.85, 2.6, 0.95, Self.steel)
            let binColors = [Self.commDarkRoof, Self.commYellow, Self.commBlue]
            for i in 0..<3 {
                let pz: Float = -0.8 + Float(i) * 0.8
                box(0, 0.95, pz, 0.75, 0.70, 0.08, binColors[i])
                cylinder(0, 1.03, pz, radius: 0.16, height: 0.04, color: Self.commDarkRoof, sides: 8)
            }

        case .coolingTower:
            box(0, 0, 0, 2.6, 2.6, 0.25, Self.steel)
            box(0, 0.25, 0, 2.4, 2.4, 1.8, Self.commWarmWhite)
            for side: Float in [-1.22, 1.22] {
                box(0, 0.45, side, 2.2, 0.04, 1.3, Self.commDarkRoof)
            }
            cylinder(0, 2.05, 0, radius: 0.95, height: 0.55, color: Self.commConcrete, sides: 12)
            cylinder(0, 2.60, 0, radius: 0.88, height: 0.06, color: Self.steel, sides: 8)

        case .fireEscapeStair:
            box(1.0, 3.2, 0, 2.0, 1.8, 0.12, Self.steel)
            box(2.0, 3.32, 0, 0.08, 1.8, 0.9, Self.steel)
            box(1.0, 3.32, -0.9, 2.0, 0.08, 0.9, Self.steel)
            stairs(1.0, 0, 1.8, run: 2.8, width: 1.1, rise: 3.2)
            for hy: Float in [0.5, 3.2] {
                box(0.2, hy, -0.8, 0.4, 0.12, 0.12, Self.steel)
                box(0.2, hy, 0.8, 0.4, 0.12, 0.12, Self.steel)
            }

        case .transitFeederBus:
            let length: Float = 10.4, width: Float = 2.5, wheelR: Float = 0.46
            let chassisY: Float = 0.35

            box(0, chassisY, 0, length, width, 0.85, Self.commWarmWhite)
            box(0, chassisY, 0, length + 0.15, width + 0.05, 0.22, Self.commDarkRoof)

            box(0, chassisY + 0.35, -width / 2 - 0.015, length * 0.85, 0.03, 0.35, Self.commBusGreen)
            box(0, chassisY + 0.35, width / 2 + 0.015, length * 0.85, 0.03, 0.35, Self.commBusGreen)

            box(0, chassisY + 0.85, 0, length, width, 1.35, Self.commDarkGlass)
            for i in -3...3 {
                let px = Float(i) * 1.35
                box(px, chassisY + 0.85, -width / 2, 0.12, 0.04, 1.35, Self.commDark)
                box(px, chassisY + 0.85, width / 2, 0.12, 0.04, 1.35, Self.commDark)
            }

            box(0, chassisY + 2.20, 0, length, width, 0.40, Self.commWarmWhite)
            commAwning(length / 2 - 0.9, chassisY + 2.25, 0, length: 1.8, width: width, rise: 0.35, color: Self.commWarmWhite)

            pane(length / 2 + 0.08, chassisY + 0.85, 0, width - 0.35, 1.35)
            box(length / 2 + 0.02, chassisY + 2.25, 0, 0.25, 1.8, 0.32, Self.commDarkRoof)
            box(length / 2 + 0.15, chassisY + 2.27, 0, 0.02, 1.6, 0.24, Self.commYellow)

            for sign: Float in [-0.95, 0.95] {
                cylinder(length / 2 + 0.08, chassisY + 0.35, sign, radius: 0.12, height: 0.05, color: Map3DPalette.tileWhite, sides: 8)
                cylinder(length / 2 + 0.08, chassisY + 0.52, sign, radius: 0.08, height: 0.05, color: Self.commYellow, sides: 8)
            }
            box(length / 2 + 0.08, chassisY + 0.35, 0, 0.04, 1.1, 0.32, Self.commDark)
            box(length / 2 + 0.11, chassisY + 0.25, 0, 0.02, 0.55, 0.18, Self.commWarmWhite)

            for sign: Float in [-1, 1] {
                let mz = sign * (width / 2 + 0.35)
                beam(Map3DPoint(length / 2 - 0.2, chassisY + 2.1, sign * (width / 2)), Map3DPoint(length / 2 + 0.4, chassisY + 1.8, mz), 0.04, Self.commDarkRoof)
                box(length / 2 + 0.4, chassisY + 1.45, mz, 0.10, 0.18, 0.45, Self.commDarkRoof)
                box(length / 2 + 0.35, chassisY + 1.47, mz, 0.02, 0.14, 0.40, Self.commChrome)
            }

            for doorX: Float in [2.8, -0.8] {
                box(doorX, chassisY, -width / 2 - 0.02, 1.30, 0.06, 1.95, Self.commDarkRoof)
                pane(doorX, chassisY + 0.35, -width / 2 - 0.03, 1.10, 1.45)
                cylinder(doorX + 0.3, chassisY + 0.4, -width / 2 + 0.15, radius: 0.03, height: 1.6, color: Self.commYellow, sides: 6)
            }

            pane(-length / 2 - 0.05, chassisY + 1.25, 0, width - 0.45, 0.95)
            box(-length / 2 - 0.05, chassisY + 0.45, 0, 0.05, 1.9, 0.65, Self.commDark)
            for sign: Float in [-0.95, 0.95] {
                box(-length / 2 - 0.06, chassisY + 0.65, sign, 0.04, 0.14, 0.18, Self.commRed)
                box(-length / 2 - 0.06, chassisY + 0.45, sign, 0.04, 0.14, 0.18, Self.commYellow)
                box(-length / 2 - 0.06, chassisY + 0.25, sign, 0.04, 0.14, 0.18, Self.commWarmWhite)
            }

            box(0, chassisY + 2.60, 0, 3.8, 1.9, 0.45, Self.commWarmWhite)
            commAwning(1.6, chassisY + 2.65, 0, length: 0.6, width: 1.8, rise: 0.25, color: Self.commWarmWhite)
            box(0, chassisY + 2.68, 0, 3.2, 1.94, 0.22, Self.commDarkRoof)

            commWheel(2.9, 0, -width / 2 + 0.06, radius: wheelR, width: 0.30)
            commWheel(2.9, 0, width / 2 - 0.06, radius: wheelR, width: 0.30)
            commWheel(-2.9, 0, -width / 2 + 0.06, radius: wheelR, width: 0.34)
            commWheel(-2.9, 0, width / 2 - 0.06, radius: wheelR, width: 0.34)

        default:
            break
        }
    }
}
