import Foundation

extension StationKitBuilder {
    mutating func commercialBuilding(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .departmentStore:
            // 1F-2F Podium with dark plinth, arcade colonnade and warm display windows
            box(0, 0, 0, 19, 23, 7.0, Self.commWarmWhite)
            box(0, 0, 0, 19.4, 23.4, 0.45, Self.commDarkRoof)
            pane(9.55, 0.45, -5.5, 6.0, 3.2)
            pane(9.55, 0.45, 5.5, 6.0, 3.2)
            for pz: Float in [-10, -5, 0, 5, 10] {
                box(9.6, 0.45, pz, 0.45, 0.45, 6.5, Self.commConcrete)
            }
            pane(9.55, 0.45, 0, 3.6, 3.2)
            commAwning(10.6, 4.2, 0, length: 2.5, width: 9.0, rise: 0.25, color: Self.commBlue)
            for pz: Float in [-4, 4] {
                beam(Map3DPoint(9.7, 5.8, pz), Map3DPoint(11.8, 4.4, pz), 0.06, Self.steel)
            }

            // 3F-5F Main shopping block with architectural sunshade fins
            box(-0.5, 7.0, 0, 16.5, 20.5, 9.0, Map3DPalette.tileWhite)
            for i in -8...8 {
                box(7.85, 7.5, Float(i) * 1.1, 0.22, 0.08, 8.0, Map3DPalette.counters[0])
            }
            commWindowBand(-0.5, 7.2, 0, length: 16.5, width: 20.5, floors: 3, bays: 5, frameColor: Self.commDark, glassColor: Self.commDarkGlass)

            // Rooftop terrace, parapet, water tank and LED billboard
            box(-0.5, 16.0, 0, 16.8, 20.8, 0.4, Self.commConcrete)
            box(-0.5, 16.4, 0, 16.2, 20.2, 0.65, Map3DPalette.roof)
            box(5.5, 16.4, 0, 0.08, 14.0, 1.0, Self.glass)
            box(-3.5, 16.4, 4.5, 5.0, 6.5, 3.2, Self.commConcrete)
            commWaterTank(-3.5, 16.4, -4.5, radius: 1.1, height: 1.6)
            box(6.2, 16.4, -7.0, 0.35, 6.0, 3.5, Self.steel)
            box(6.4, 16.6, -7.0, 0.05, 5.6, 3.1, Self.commYellow)

        case .cinema:
            box(0, 0, 0, 17, 15, 12, Self.commWarmWhite)
            box(8.55, 0, 0, 0.45, 9.0, 14.5, Self.commCyan)
            box(8.65, 0, 0, 0.55, 5.0, 16.0, Self.commRed)
            box(8.75, 0, 0, 0.65, 2.2, 17.2, Self.commYellow)

            box(10.0, 4.2, 0, 3.2, 11.0, 0.55, Self.commDarkRoof)
            box(10.0, 4.0, 0, 3.0, 10.6, 0.15, Self.commWarmGlow)
            beam(Map3DPoint(8.8, 8.5, -4.5), Map3DPoint(11.2, 4.7, -4.5), 0.08, Self.steel)
            beam(Map3DPoint(8.8, 8.5, 4.5), Map3DPoint(11.2, 4.7, 4.5), 0.08, Self.steel)

            box(10.2, 7.5, 0, 0.45, 0.85, 7.5, Self.commCrimson)
            box(10.45, 7.8, 0, 0.10, 0.65, 6.8, Self.commWarmGlow)

            for pz: Float in [-3.8, 0, 3.8] {
                box(8.6, 1.2, pz, 0.18, 1.8, 2.4, Self.commDarkRoof)
                let posterColor = pz < -1 ? Self.commBlue : pz > 1 ? Self.commMint : Self.commRed
                box(8.7, 1.35, pz, 0.05, 1.5, 2.1, posterColor)
            }

            box(9.2, 0, 0, 1.6, 2.4, 2.6, Self.commDarkWood)
            pane(9.95, 1.1, 0, 1.8, 1.3)
            box(0, 12.0, 0, 17.5, 15.5, 0.35, Map3DPalette.roof)

        case .supermarket:
            box(0, 0, 0, 16, 24, 6.8, Self.commWarmWhite)
            box(8.05, 4.8, 0, 0.22, 23.5, 1.6, Self.commMint)
            box(8.18, 5.2, 0, 0.08, 21.0, 0.8, Self.commOrange)

            pane(8.1, 0.45, 3.0, 8.5, 3.8)
            commAwning(9.2, 4.4, 3.0, length: 2.4, width: 10.5, rise: 0.25, color: Self.commMint)
            for pz: Float in [-1.5, 7.5] {
                box(10.2, 0, 3.0 + pz, 0.25, 0.25, 4.4, Self.steel)
            }

            box(8.8, 0, -6.5, 3.2, 4.2, 0.12, Self.commConcrete)
            box(8.8, 0.12, -8.4, 3.0, 0.10, 0.95, Self.steel)
            box(8.8, 0.12, -4.6, 3.0, 0.10, 0.95, Self.steel)
            box(7.4, 0.12, -6.5, 0.10, 3.8, 0.95, Self.steel)
            for i in 0..<4 {
                box(7.9 + Float(i) * 0.65, 0.15, -6.5, 0.85, 0.55, 0.75, Self.commChrome)
            }

            box(0, 6.8, 0, 16.6, 24.6, 0.35, Map3DPalette.roof)
            commAirConditionerUnit(-3.5, 7.15, 6.0, length: 1.8, width: 1.2, height: 1.4)
            commAirConditionerUnit(-3.5, 7.15, 2.5, length: 1.8, width: 1.2, height: 1.4)
            cylinder(3.0, 7.15, -4.0, radius: 0.95, height: 1.2, color: Self.steel, sides: 8)

        case .cornerOffice:
            let width: Float = 16, depth: Float = 15
            let halfD = depth / 2

            box(0, 0, 0, depth, width, 0.25, Self.commConcrete)
            box(0, 0.25, 0, depth - 0.2, width - 0.2, 4.0, Self.commWarmWhite)
            pane(halfD - 0.05, 0.45, 0, width - 3.0, 3.6)
            pane(halfD + 0.02, 0.45, 0, 2.8, 2.8)
            box(halfD - 2.5, 0.45, 0, 1.2, 3.2, 1.1, Self.commWarmWood)
            box(halfD - 2.5, 1.55, 0, 0.1, 2.8, 0.4, Self.commWarmGlow)

            commAwning(halfD + 1.2, 4.0, 0, length: 2.4, width: 6.5, rise: 0.20, color: Self.steel)
            for pz: Float in [-2.8, 2.8] {
                box(halfD + 2.2, 0.25, pz, 0.18, 0.18, 3.75, Self.commChrome)
            }

            box(0, 4.25, 0, depth, width, 12.75, Self.steel)
            for fl in 1...4 {
                let fy = 4.25 + Float(fl) * 3.1
                box(0, fy - 0.35, 0, depth + 0.15, width + 0.15, 0.45, Self.commWarmWhite)
            }
            commWindowBand(0, 4.35, 0, length: depth, width: width, floors: 4, bays: 5, frameColor: Self.steel, glassColor: Self.glass)

            box(0, 17.0, 0, depth + 0.1, width + 0.1, 1.1, Self.commConcrete)
            box(0, 17.0, 0, depth - 0.8, width - 0.8, 1.2, Map3DPalette.roof)
            box(-2.5, 17.0, 2.5, 5.5, 6.0, 3.2, Self.commWarmWhite)
            box(-2.5, 20.2, 2.5, 5.8, 6.3, 0.35, Self.steel)
            box(3.2, 17.0, 3.5, 2.4, 2.4, 1.6, Self.steel)
            cylinder(3.2, 18.6, 3.5, radius: 0.85, height: 0.45, color: Self.commConcrete, sides: 10)
            commWaterTank(-3.0, 17.0, -3.5, radius: 1.1, height: 1.5)
            cylinder(0, 17.0, 0, radius: 0.12, height: 6.5, color: Self.steel, sides: 6)
            cylinder(0, 23.5, 0, radius: 0.25, height: 0.25, color: Self.commYellow, sides: 6)

        case .yellowCafe:
            box(0, 0, 0, 11, 13, 7.5, Map3DPalette.counters[1])
            box(0, 0, 0, 11.4, 13.4, 0.35, Self.commConcrete)
            gable(0, 7.5, 0, 11.8, 13.8, 3.2, Map3DPalette.templeRoof)

            box(3.2, 8.5, 0, 1.8, 2.2, 1.6, Self.commWarmWhite)
            pane(4.15, 8.8, 0, 1.4, 1.1)
            gable(3.2, 10.1, 0, 2.0, 2.4, 0.85, Map3DPalette.templeRoof)

            for pz: Float in [-3.5, 3.5] {
                pane(5.55, 4.2, pz, 2.2, 2.4)
                commStripedAwning(6.4, 6.2, pz, length: 1.6, width: 2.6, rise: 0.45, color1: Self.commMint, color2: Self.commWarmWhite, stripes: 4)
            }

            pane(5.55, 0.45, 2.2, 3.5, 3.2)
            box(6.8, 0, -2.5, 3.2, 5.0, 0.25, Self.commWarmWood)
            box(8.2, 0.25, -2.5, 0.4, 4.6, 0.55, Self.commConcrete)
            box(8.2, 0.75, -2.5, 0.3, 4.4, 0.35, Map3DPalette.greens[1])

        case .gasStation:
            box(0, 5.2, 0, 13, 20, 0.85, Self.commWarmWhite)
            box(0, 5.3, 0, 13.4, 20.4, 0.35, Self.commBlue)
            box(0, 5.65, 0, 13.4, 20.4, 0.30, Self.commRed)
            for sx: Float in [-3.8, 3.8] {
                for sz: Float in [-5.5, 5.5] {
                    box(sx, 0, sz, 0.55, 0.55, 5.2, Self.steel)
                }
            }

            for sz: Float in [-5.5, 5.5] {
                box(0, 0, sz, 7.5, 1.6, 0.25, Self.commConcrete)
                for bx: Float in [-3.4, 3.4] {
                    cylinder(bx, 0.25, sz, radius: 0.16, height: 0.85, color: Self.commYellow, sides: 8)
                }
                for px: Float in [-1.5, 1.5] {
                    box(px, 0.25, sz, 0.85, 0.55, 1.65, Self.commDarkRoof)
                    box(px, 1.1, sz, 0.88, 0.58, 0.45, Self.commBlue)
                    box(px + 0.44, 0.85, sz, 0.03, 0.40, 0.35, Self.commYellow)
                    box(px, 0.75, sz - 0.32, 0.2, 0.1, 0.5, Self.commMint)
                    box(px, 0.75, sz + 0.32, 0.2, 0.1, 0.5, Self.commRed)
                }
            }

            box(-7.5, 0, 2.0, 5.5, 8.5, 4.0, Self.commWarmWhite)
            pane(-4.7, 0.45, 2.0, 6.5, 3.0)
            box(-7.5, 4.0, 2.0, 5.8, 8.8, 0.25, Map3DPalette.roof)

            box(6.8, 0, 9.5, 0.45, 1.4, 4.2, Self.commBlue)
            box(6.8, 1.2, 9.5, 0.50, 1.2, 2.6, Self.commDarkRoof)
            for i in 0..<3 {
                box(7.06, 1.6 + Float(i) * 0.7, 9.5, 0.02, 0.9, 0.4, Self.commYellow)
            }

        case .parkingGarage:
            box(0, 0, 0, 18, 16, 9.5, Self.commConcrete)
            for floor in 0..<3 {
                let fy: Float = 0.5 + Float(floor) * 3.0
                box(0, fy, 0, 18.2, 16.2, 0.9, Self.steel)
                for sx: Float in [-8.5, 0, 8.5] {
                    for sz: Float in [-7.5, 7.5] {
                        box(sx, fy, sz, 0.8, 0.8, 3.0, Self.commConcrete)
                    }
                }
            }
            box(9.2, 0, 2.5, 0.45, 0.45, 1.2, Self.commYellow)
            box(9.2, 0.85, 0.8, 0.08, 2.6, 0.15, Self.commRed)
            stairs(-8.5, 0, -8.5, run: 6.0, width: 3.2, rise: 3.0)
            for pz: Float in [-6.0, 6.0] {
                cylinder(0, 9.5, pz, radius: 0.08, height: 3.2, color: Self.steel, sides: 6)
                box(0, 12.6, pz, 0.65, 0.35, 0.2, Self.commWarmGlow)
            }

        case .commercialHotel:
            box(0, 0, 0, 15, 14, 16, Self.commWarmWhite)
            box(0, 0, 0, 15.4, 14.4, 0.45, Self.commDarkRoof)
            pane(7.55, 0.45, 0, 9.5, 3.4)

            box(9.6, 3.8, 0, 4.0, 10.0, 0.45, Self.commDarkRoof)
            for pz: Float in [-4.2, 4.2] {
                box(11.2, 0, pz, 0.45, 0.45, 3.8, Self.commChrome)
            }

            commWindowBand(0, 4.2, 0, length: 15, width: 14, floors: 3, bays: 4, frameColor: Self.commDark, glassColor: Self.glass)
            box(0, 16.0, 0, 15.6, 14.6, 0.65, Self.commConcrete)
            box(5.0, 16.65, 0, 0.35, 8.5, 1.8, Self.commBlue)
            box(5.2, 16.85, 0, 0.05, 8.0, 1.4, Self.commWarmGlow)
            commWaterTank(-3.5, 16.65, 3.0, radius: 0.95, height: 1.4)

        case .bankBranch:
            box(0, 0, 0, 14, 16, 9.5, Self.commConcrete)
            box(0, 0, 0, 14.6, 16.6, 0.65, Self.commDarkRoof)
            for pz: Float in [-5.5, -1.8, 1.8, 5.5] {
                box(7.2, 0.65, pz, 0.75, 0.75, 7.5, Self.commWarmWhite)
            }
            gable(7.2, 8.15, 0, 1.8, 14.0, 1.8, Self.commWarmWhite)
            pane(6.9, 0.65, 0, 6.5, 3.5)

            box(7.1, 0.65, 6.2, 0.85, 2.2, 3.2, Self.commBlue)
            pane(7.55, 0.85, 6.2, 1.6, 2.4)
            box(0, 9.5, 0, 14.5, 16.5, 0.45, Self.commDarkRoof)

        case .stackedShopHouse:
            box(0, 0, 0, 12, 8, 13.5, Self.commWarmWhite)
            box(4.5, 0, 0, 3.0, 8.0, 3.8, Map3DPalette.tileWhite)
            for pz: Float in [-3.6, 3.6] {
                box(5.8, 0, pz, 0.45, 0.45, 3.8, Self.commConcrete)
            }
            pane(4.45, 0.35, 0, 5.5, 3.2)

            pane(6.05, 4.2, 0, 5.5, 2.2)
            box(6.15, 4.2, 0, 0.04, 5.5, 2.2, Self.commMint)
            pane(6.05, 7.5, 0, 5.5, 2.2)
            box(6.15, 7.5, 0, 0.04, 5.5, 2.2, Self.commMint)

            box(6.4, 7.0, 0, 0.8, 6.5, 0.15, Self.commConcrete)
            box(6.75, 7.15, 0, 0.06, 6.5, 0.85, Self.steel)
            box(6.4, 7.15, -1.8, 0.4, 1.2, 0.45, Map3DPalette.greens[2])
            box(6.4, 7.15, 1.8, 0.4, 1.2, 0.45, Map3DPalette.greens[0])

            box(0, 13.5, 0, 11.5, 7.5, 2.8, Self.commMint)
            gable(0, 16.3, 0, 11.8, 7.8, 1.2, Map3DPalette.roof)
            commWaterTank(-3.2, 13.5, 2.2, radius: 0.85, height: 1.3)

        case .warehouseStore:
            box(0, 0, 0, 18, 22, 8.5, Self.commConcrete)
            box(0, 6.5, 0, 18.4, 22.4, 1.8, Map3DPalette.trainAccent)
            box(9.25, 7.1, 0, 0.05, 14.0, 0.9, Self.commRed)

            pane(9.05, 0.45, 4.5, 8.5, 4.8)
            commAwning(10.2, 5.2, 4.5, length: 2.4, width: 10.0, rise: 0.35, color: Map3DPalette.trainAccent)

            box(9.05, 0.85, -6.5, 0.15, 5.5, 3.8, Map3DPalette.tankStand)
            box(9.8, 0, -6.5, 1.8, 6.5, 0.85, Self.commConcrete)

            box(0, 8.5, 0, 18.5, 22.5, 0.35, Map3DPalette.roof)
            cylinder(-4.0, 8.85, 4.0, radius: 1.2, height: 1.2, color: Self.steel, sides: 8)
            cylinder(-4.0, 8.85, -4.0, radius: 1.2, height: 1.2, color: Self.steel, sides: 8)

        case .metroEntrance:
            box(0, 0, 0, 7.5, 4.2, 0.35, Self.commConcrete)
            stairs(0.5, 0, 0, run: 5.5, width: 3.2, rise: 2.8)
            for pz: Float in [-1.8, 1.8] {
                box(0.5, 0.35, pz, 5.5, 0.08, 1.1, Self.glass)
                box(0.5, 1.45, pz, 5.5, 0.10, 0.08, Self.commChrome)
            }
            for px: Float in [-1.8, 0.8, 3.4] {
                beam(Map3DPoint(px, 0.35, -2.0), Map3DPoint(px, 2.8, -2.0), 0.10, Self.commMint)
                beam(Map3DPoint(px, 0.35, 2.0), Map3DPoint(px, 2.8, 2.0), 0.10, Self.commMint)
                beam(Map3DPoint(px, 2.8, -2.0), Map3DPoint(px, 3.4, 0), 0.10, Self.commMint)
                beam(Map3DPoint(px, 2.8, 2.0), Map3DPoint(px, 3.4, 0), 0.10, Self.commMint)
            }
            canopy(0.8, 3.1, 0, length: 6.2, width: 4.2, rise: 0.45, color: Self.glass)

            box(3.8, 0, -2.4, 0.35, 0.35, 3.8, Self.commMint)
            box(3.8, 3.2, -2.4, 0.45, 0.45, 0.65, Self.commBlue)
            box(3.8, 3.3, -2.4, 0.48, 0.48, 0.45, Self.commWarmWhite)

        default:
            break
        }
    }
}
