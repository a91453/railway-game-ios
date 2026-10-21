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
            let width: Float = 0.65, height: Float = 1.05, spread: Float = 0.28
            for lx: Float in [-spread, spread] {
                for lz: Float in [-width / 2 + 0.04, width / 2 - 0.04] {
                    box(lx, 0, lz, 0.05, 0.05, 0.18, Self.commWarmWood)
                }
            }
            mesh.addQuad(Map3DPoint(spread, 0.15, -width / 2), Map3DPoint(spread, 0.15, width / 2),
                         Map3DPoint(0, height, width / 2), Map3DPoint(0, height, -width / 2), color: Self.commWarmWood)
            mesh.addQuad(Map3DPoint(-spread, 0.15, width / 2), Map3DPoint(-spread, 0.15, -width / 2),
                         Map3DPoint(0, height, -width / 2), Map3DPoint(0, height, width / 2), color: Self.commWarmWood)
            cylinder(0, height, 0, radius: 0.03, height: width, color: Self.commChrome, sides: 8)
            box(spread * 0.55 + 0.01, 0.55, 0, 0.01, 0.36, 0.40, Self.commYellow)
            box(-spread * 0.55 - 0.01, 0.55, 0, 0.01, 0.36, 0.40, Self.commWarmGlow)
            beam(Map3DPoint(-spread * 0.65, 0.40, -width / 2 + 0.05), Map3DPoint(spread * 0.65, 0.40, -width / 2 + 0.05), 0.02, Self.steel)
            beam(Map3DPoint(-spread * 0.65, 0.40, width / 2 - 0.05), Map3DPoint(spread * 0.65, 0.40, width / 2 - 0.05), 0.02, Self.steel)

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
                let cx = cosf(a) * 1.15, cz = sinf(a) * 1.15
                box(cx, 0.42, cz, 0.45, 0.45, 0.06, Self.commWarmWood)
                for lx: Float in [-0.18, 0.18] {
                    for lz: Float in [-0.18, 0.18] {
                        cylinder(cx + lx, 0, cz + lz, radius: 0.02, height: 0.42, color: Self.steel, sides: 6)
                    }
                }
                box(cx + cosf(a) * 0.18, 0.48, cz + sinf(a) * 0.18, 0.05, 0.42, 0.38, Self.steel)
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
            let height: Float = 3.8
            let colR: Float = 0.06

            for cx: Float in [0.1, 2.3] {
                for cz: Float in [-0.75, 0.75] {
                    cylinder(cx, 0, cz, radius: colR, height: height, color: Self.steel, sides: 8)
                }
            }
            for wy: Float in [0.5, 1.8, 3.6] {
                for wz: Float in [-0.75, 0.75] {
                    box(0.05, wy, wz, 0.25, 0.12, 0.12, Map3DPalette.tankStand)
                }
            }
            box(1.2, 1.8, 0, 2.2, 1.5, 0.10, Self.steel)
            box(2.28, 1.9, 0, 0.04, 1.5, 0.95, Self.steel)
            box(1.2, 1.9, -0.73, 2.2, 0.04, 0.95, Self.steel)

            box(1.2, 3.6, 0, 2.2, 1.5, 0.10, Self.steel)
            box(2.28, 3.7, 0, 0.04, 1.5, 0.95, Self.steel)
            box(1.2, 3.7, -0.73, 2.2, 0.04, 0.95, Self.steel)
            box(1.2, 3.7, 0.73, 2.2, 0.04, 0.95, Self.steel)

            let steps = 8
            let runL: Float = 2.0, stairW: Float = 0.65
            for i in 0..<steps {
                let t = (Float(i) + 0.5) / Float(steps)
                let sy = t * 1.8
                let sx = 0.2 + t * runL
                box(sx, sy, 0.35, runL / Float(steps) + 0.02, stairW, 0.08, Self.steel)
            }
            beam(Map3DPoint(0.2, 0.1, 0.70), Map3DPoint(2.2, 1.8, 0.70), 0.05, Self.steel)
            beam(Map3DPoint(0.2, 0.95, 0.70), Map3DPoint(2.2, 2.65, 0.70), 0.04, Self.steel)

            for i in 0..<steps {
                let t = (Float(i) + 0.5) / Float(steps)
                let sy = 1.8 + t * 1.8
                let sx = 2.2 - t * runL
                box(sx, sy, -0.35, runL / Float(steps) + 0.02, stairW, 0.08, Self.steel)
            }
            beam(Map3DPoint(2.2, 1.9, -0.70), Map3DPoint(0.2, 3.6, -0.70), 0.05, Self.steel)
            beam(Map3DPoint(2.2, 2.75, -0.70), Map3DPoint(0.2, 4.45, -0.70), 0.04, Self.steel)

        case .transitFeederBus:
            let length: Float = 10.4, width: Float = 2.5, wheelR: Float = 0.48
            let halfL = length / 2, halfW = width / 2

            box(0, 0.22, 0, length - 0.2, width - 0.12, 0.53, Self.commDarkRoof)
            box(4.35, 0.22, 0, 1.7, width, 0.56, Map3DPalette.tileWhite)
            box(0, 0.22, 0, 4.6, width, 0.56, Map3DPalette.tileWhite)
            box(-4.35, 0.22, 0, 1.7, width, 0.56, Map3DPalette.tileWhite)

            for mx: Float in [-4.2, -1.2, 1.2, 4.2] {
                for sign: Float in [-1, 1] {
                    box(mx, 0.36, sign * (halfW + 0.01), 0.12, 0.02, 0.05, Self.commOrange)
                }
            }

            box(0, 0.78, 0, length, width, 0.40, Self.commBusGreen)
            box(0, 1.18, 0, length, width - 0.04, 1.20, Self.commDarkGlass)

            for i in -3...3 {
                let px = Float(i) * 1.35
                box(px, 1.18, halfW, 0.10, 0.05, 1.20, Self.commDark)
            }
            box(3.2, 1.78, halfW + 0.01, 1.4, 0.03, 0.06, Self.steel)

            for dx: Float in [3.3, -0.6] {
                box(dx, 0.28, -halfW, 1.24, 0.08, 2.08, Self.commDark)
                box(dx - 0.30, 0.32, -halfW - 0.01, 0.56, 0.04, 1.98, Self.commDarkGlass)
                box(dx + 0.30, 0.32, -halfW - 0.01, 0.56, 0.04, 1.98, Self.commDarkGlass)
                cylinder(dx, 0.35, -halfW + 0.22, radius: 0.025, height: 1.9, color: Self.commYellow, sides: 6)
            }
            for px: Float in [1.35, -2.4, -3.8] {
                box(px, 1.18, -halfW, 0.10, 0.05, 1.20, Self.commDark)
            }

            box(0, 2.38, 0, length, width, 0.24, Map3DPalette.tileWhite)
            box(1.1, 2.62, 0, 6.2, width - 0.35, 0.42, Self.commBusGreen)
            commAwning(4.45, 2.62, 0, length: 0.8, width: width - 0.35, rise: 0.40, color: Self.commBusGreen)
            box(0.5, 3.05, 0, 3.8, width - 0.65, 0.04, Self.commDarkRoof)

            box(halfL + 0.08, 0.22, 0, 0.26, width - 0.1, 0.56, Map3DPalette.tileWhite)
            box(halfL + 0.22, 0.28, 0, 0.02, 0.52, 0.18, Map3DPalette.tileWhite)
            for sign: Float in [-1, 1] {
                let hy: Float = 0.50, hz = sign * (halfW - 0.35)
                box(halfL + 0.21, hy, hz, 0.03, 0.38, 0.18, Self.commDark)
                cylinder(halfL + 0.22, hy, hz - sign * 0.08, radius: 0.065, height: 0.03, color: Map3DPalette.tileWhite, sides: 8)
                cylinder(halfL + 0.22, hy, hz + sign * 0.08, radius: 0.045, height: 0.03, color: Self.commYellow, sides: 8)
            }
            box(halfL + 0.08, 0.78, 0, 0.18, width - 0.1, 0.40, Self.commDark)
            pane(halfL + 0.06, 1.18, 0, width - 0.25, 1.18)
            box(halfL + 0.08, 2.38, 0, 0.16, 1.8, 0.22, Self.commDarkRoof)
            box(halfL + 0.17, 2.40, 0, 0.02, 1.65, 0.18, Self.commYellow)

            for sign: Float in [-1, 1] {
                let mz = sign * (halfW + 0.25)
                beam(Map3DPoint(halfL - 0.2, 2.50, sign * halfW), Map3DPoint(halfL + 0.35, 2.25, mz), 0.035, Self.commDark)
                beam(Map3DPoint(halfL + 0.35, 2.25, mz), Map3DPoint(halfL + 0.35, 1.70, mz), 0.035, Self.commDark)
                box(halfL + 0.35, 1.70, mz, 0.10, 0.14, 0.42, Self.commDark)
                box(halfL + 0.29, 1.72, mz, 0.02, 0.11, 0.38, Self.commChrome)
            }

            box(-halfL - 0.05, 0.22, 0, 0.15, width - 0.1, 0.56, Map3DPalette.tileWhite)
            box(-halfL - 0.05, 0.78, 0, 0.15, width - 0.1, 0.40, Self.commBusGreen)
            pane(-halfL - 0.05, 1.35, 0, width - 0.4, 0.95)
            for sign: Float in [-1, 1] {
                let rz = sign * (halfW - 0.25)
                box(-halfL - 0.06, 0.85, rz, 0.02, 0.16, 0.16, Self.commRed)
                box(-halfL - 0.06, 0.65, rz, 0.02, 0.16, 0.14, Self.commYellow)
                box(-halfL - 0.06, 0.48, rz, 0.02, 0.16, 0.12, Map3DPalette.tileWhite)
            }
            box(-halfL - 0.06, 0.32, 0, 0.02, 0.52, 0.18, Map3DPalette.tileWhite)

            let wheelZOffset = halfW - 0.14
            commWheel(2.9, 0, -wheelZOffset, radius: wheelR, width: 0.28)
            commWheel(2.9, 0, wheelZOffset, radius: wheelR, width: 0.28)
            commWheel(-2.9, 0, -wheelZOffset, radius: wheelR, width: 0.28)
            commWheel(-2.9, 0, wheelZOffset, radius: wheelR, width: 0.28)
            cylinder(2.9, wheelR, 0, radius: 0.06, height: width - 0.4, color: Map3DPalette.tankStand, sides: 8)
            cylinder(-2.9, wheelR, 0, radius: 0.06, height: width - 0.4, color: Map3DPalette.tankStand, sides: 8)

        default:
            break
        }
    }
}
