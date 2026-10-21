import Foundation

extension StationKitBuilder {
    mutating func commercialShop(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .bubbleTeaShop:
            box(0, 0, 0, 2.8, 4.8, 1.05, Self.commWarmWood)
            box(0.05, 1.05, 0, 2.9, 4.9, 0.08, Self.commWarmWhite)

            for i in 0..<4 {
                let pz: Float = -1.6 + Float(i) * 1.05
                cylinder(-0.4, 1.13, pz, radius: 0.22, height: 0.75, color: Self.steel, sides: 10)
                let tapColor = i == 0 ? Self.commRed : i == 1 ? Self.commMint : i == 2 ? Self.commYellow : Self.commDark
                cylinder(-0.4, 1.88, pz, radius: 0.18, height: 0.12, color: tapColor, sides: 8)
            }

            box(0.3, 1.13, -1.8, 0.55, 0.45, 0.85, Self.commChrome)
            cylinder(0.3, 1.98, -1.8, radius: 0.18, height: 0.25, color: Self.commRed, sides: 8)

            box(0.4, 1.13, 0.8, 0.55, 1.6, 0.35, Self.glass)
            box(0.4, 1.13, 0.8, 0.50, 1.5, 0.25, Self.commDark)
            box(0.4, 1.13, -0.4, 0.35, 0.40, 0.45, Self.commDark)

            box(-1.3, 0, 0, 0.25, 4.8, 3.4, Map3DPalette.tileWhite)
            box(-1.15, 1.8, 0, 0.05, 4.2, 1.2, Self.commDarkRoof)
            box(-1.12, 1.9, 0, 0.02, 3.9, 1.0, Self.commWarmGlow)
            commStripedAwning(0.6, 3.1, 0, length: 2.8, width: 5.0, rise: 0.45, color1: Self.commMint, color2: Self.commWarmWhite, stripes: 6)

        case .bentoShop:
            box(0, 0, 0, 2.6, 4.6, 1.0, Self.steel)
            box(0.2, 1.0, 0, 1.4, 4.2, 0.45, Self.glass)
            for i in 0..<6 {
                let pz: Float = -1.6 + Float(i) * 0.65
                let foodColor = i % 2 == 0 ? Map3DPalette.counters[1] : Map3DProp.greens[2]
                box(0.2, 1.02, pz, 0.75, 0.55, 0.10, foodColor)
            }

            cylinder(-0.6, 1.0, -1.6, radius: 0.32, height: 0.45, color: Self.commTatungGreen, sides: 10)
            cylinder(-0.6, 1.45, -1.6, radius: 0.30, height: 0.15, color: Self.steel, sides: 8)
            cylinder(-0.6, 1.0, 1.4, radius: 0.38, height: 0.55, color: Self.steel, sides: 10)
            cylinder(-0.6, 1.55, 1.4, radius: 0.35, height: 0.08, color: Self.commWarmWood, sides: 8)

            box(1.2, 2.6, 0, 0.05, 4.6, 0.95, Self.commRed)
            box(1.23, 2.7, 0, 0.02, 4.2, 0.75, Self.commYellow)

            box(2.8, 0, 0, 1.4, 2.0, 0.75, Self.steel)
            for sz: Float in [-1.4, 1.4] {
                cylinder(2.8, 0, sz, radius: 0.22, height: 0.45, color: Self.commRed, sides: 8)
            }

        case .bakery:
            box(0, 0, 0, 3.2, 4.8, 3.5, Self.commWarmWhite)
            pane(1.65, 0.45, 0, 4.2, 2.3)
            box(1.2, 0.65, 0, 0.65, 3.8, 0.85, Self.commWarmWood)
            for i in 0..<4 {
                box(1.2, 1.52, -1.4 + Float(i) * 0.9, 0.45, 0.65, 0.25, Map3DPalette.counters[0])
            }
            commAwning(2.2, 3.0, 0, length: 1.8, width: 5.0, rise: 0.35, color: Self.commCrimson)

        case .pharmacy:
            box(0, 0, 0, 3.4, 5.2, 3.6, Self.commWarmWhite)
            box(1.75, 2.8, 0, 0.22, 5.2, 0.85, Self.commCyan)
            box(1.88, 2.9, 0, 0.04, 4.8, 0.65, Self.commOrange)
            pane(1.75, 0.35, 0, 4.6, 2.3)
            for pz: Float in [-1.6, 1.6] {
                box(2.3, 0, pz, 0.65, 0.95, 0.75, Self.commChrome)
            }

        case .cornerGrocery:
            box(0, 0, 0, 3.2, 5.2, 3.5, Self.commWarmWhite)
            commStripedAwning(2.1, 2.9, 0, length: 1.8, width: 5.4, rise: 0.45, color1: Self.commRed, color2: Self.commMint, stripes: 6)
            pane(1.65, 0.45, 0, 4.6, 2.2)
            for i in -1...1 {
                box(2.1, 0, Float(i) * 1.2, 0.65, 0.95, 0.65, Map3DPalette.counters[1])
                cylinder(2.1, 0.65, Float(i) * 1.2, radius: 0.35, height: 0.15, color: Map3DProp.greens[i + 1], sides: 8)
            }

        case .stationeryStore:
            box(0, 0, 0, 3.2, 4.8, 3.4, Self.commWarmWhite)
            pane(1.65, 0.45, 0.8, 2.8, 2.4)
            box(1.3, 0.65, 0.8, 0.4, 2.4, 0.75, Map3DPalette.counters[1])
            pane(1.65, 0.45, -1.5, 1.4, 2.4)
            commAwning(2.2, 3.1, 0, length: 1.8, width: 5.0, rise: 0.35, color: Self.commBlue)

        case .ramenYatai:
            box(0, 0.45, 0, 2.4, 3.8, 0.85, Self.commDarkWood)
            box(0.1, 1.3, 0, 2.6, 4.0, 0.10, Self.commWarmWood)

            commWheel(0, 0, -1.95, radius: 0.48, width: 0.12)
            commWheel(0, 0, 1.95, radius: 0.48, width: 0.12)

            for sx: Float in [-1.0, 1.0] {
                for sz: Float in [-1.7, 1.7] {
                    box(sx, 1.4, sz, 0.12, 0.12, 1.6, Self.commDarkWood)
                }
            }
            gable(0, 3.0, 0, 2.8, 4.2, 0.75, Self.commDarkWood)
            box(1.15, 2.4, 0, 0.03, 3.6, 0.65, Self.commDark)

            cylinder(-0.4, 1.4, 0, radius: 0.45, height: 0.65, color: Self.steel, sides: 10)
            box(-0.4, 2.05, 0, 0.6, 0.6, 0.08, Self.commWarmWood)

            commLantern(1.2, 2.1, -1.4, radius: 0.22, height: 0.42, color: Self.commRed)
            commLantern(1.2, 2.1, 1.4, radius: 0.22, height: 0.42, color: Self.commRed)

            for i in -1...1 {
                cylinder(1.7, 0, Float(i) * 1.1, radius: 0.20, height: 0.65, color: Self.commWarmWood, sides: 8)
                cylinder(1.7, 0, Float(i) * 1.1, radius: 0.04, height: 0.60, color: Self.steel, sides: 6)
            }

        case .nightMarketFryer:
            box(0, 0, 0, 2.4, 4.2, 0.95, Self.steel)
            box(0.2, 0.95, 0, 1.2, 3.8, 0.85, Self.glass)
            for i in 0..<5 {
                let pz: Float = -1.4 + Float(i) * 0.7
                box(0.2, 1.0, pz, 0.8, 0.5, 0.12, Map3DPalette.counters[1])
            }

            box(-0.6, 0.95, -1.2, 0.95, 1.2, 0.55, Self.steel)
            box(-0.6, 1.5, -1.2, 0.65, 0.95, 0.15, Self.steel)
            box(-0.6, 2.2, -1.2, 1.1, 1.4, 0.45, Self.steel)
            cylinder(-0.6, 2.65, -1.2, radius: 0.16, height: 0.95, color: Self.steel, sides: 8)

            cylinder(0.5, 0.95, 1.4, radius: 0.08, height: 0.25, color: Self.commChrome, sides: 6)
            cylinder(0.5, 0.95, 1.6, radius: 0.08, height: 0.25, color: Self.commRed, sides: 6)

            box(1.15, 2.6, 0, 0.04, 4.0, 0.95, Self.commYellow)
            box(1.18, 2.7, 0, 0.02, 3.6, 0.75, Self.commRed)

        case .nightMarketFruit:
            box(0, 0, 0, 2.4, 4.0, 0.95, Self.steel)
            box(0.2, 0.95, 0, 1.2, 3.6, 0.85, Self.glass)
            let fruitColors = [Self.commRed, Self.commMint, Self.commYellow, Self.commOrange]
            for i in 0..<4 {
                box(0.2, 1.0, -1.2 + Float(i) * 0.8, 0.75, 0.65, 0.15, fruitColors[i])
            }
            cylinder(-0.6, 0.95, 1.2, radius: 0.18, height: 0.55, color: Self.glass, sides: 8)
            box(-0.6, 0.95, 1.2, 0.45, 0.45, 0.25, Self.steel)

            box(1.15, 2.6, 0, 0.04, 3.8, 0.85, Self.commMint)
            box(1.18, 2.7, 0, 0.02, 3.4, 0.65, Self.commWarmWhite)

        case .nightMarketGame:
            box(0, 0, 0, 2.6, 3.6, 0.85, Self.commWarmWood)
            commAwning(0.2, 0.85, 0, length: 1.6, width: 3.2, rise: 0.45, color: Self.commYellow)
            for i in 0..<6 {
                cylinder(0.2, 1.15, -1.2 + Float(i) * 0.48, radius: 0.04, height: 0.08, color: Self.commChrome, sides: 6)
            }
            box(-1.0, 1.8, 0, 0.35, 3.6, 1.4, Self.commWarmWood)
            for i in 0..<3 {
                cylinder(-0.8, 2.2, -1.0 + Float(i) * 1.0, radius: 0.22, height: 0.35, color: Self.commRed, sides: 8)
            }
            for sz: Float in [-0.9, 0.9] {
                cylinder(1.6, 0, sz, radius: 0.20, height: 0.45, color: Self.commBlue, sides: 8)
            }

        case .vendingBank:
            let colors = [Self.commBlue, Map3DPalette.counters[1], Self.commRed]
            for i in 0..<3 {
                let pz: Float = -1.5 + Float(i) * 1.5
                box(0, 0, pz, 1.1, 1.35, 2.2, colors[i])
                box(0.56, 0.75, pz, 0.04, 1.15, 1.05, Self.commDarkRoof)
                box(0.59, 0.85, pz, 0.02, 1.05, 0.85, Self.commWarmGlow)
                box(0.56, 0.22, pz, 0.04, 0.95, 0.35, Self.commDarkRoof)
            }
            box(0, 0, 3.0, 0.95, 0.85, 1.1, Self.commMint)
            cylinder(0, 1.1, 2.85, radius: 0.12, height: 0.04, color: Self.commDarkRoof, sides: 8)
            cylinder(0, 1.1, 3.15, radius: 0.12, height: 0.04, color: Self.commDarkRoof, sides: 8)

        case .mobileFoodCart:
            box(0, 0.35, 0, 2.4, 1.4, 0.75, Self.commWarmWood)
            commWheel(-1.0, 0, 0, radius: 0.38, width: 0.10)
            commWheel(0.8, 0, -0.75, radius: 0.38, width: 0.10)
            commWheel(0.8, 0, 0.75, radius: 0.38, width: 0.10)

            box(0.2, 1.1, 0, 1.4, 1.3, 0.10, Self.steel)
            cylinder(0.2, 1.2, 0, radius: 0.35, height: 0.45, color: Self.steel, sides: 10)
            for sx: Float in [-0.6, 0.8] {
                for sz: Float in [-0.6, 0.6] {
                    box(sx, 1.1, sz, 0.04, 0.04, 1.2, Self.steel)
                }
            }
            canopy(0.1, 2.3, 0, length: 1.8, width: 1.6, rise: 0.35, color: Self.commYellow)

        default:
            break
        }
    }
}
