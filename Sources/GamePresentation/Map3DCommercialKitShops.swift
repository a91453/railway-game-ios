import Foundation

extension StationKitBuilder {
    mutating func commercialShop(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .bubbleTeaShop:
            // Counter base, ledge & tea dispensers
            box(0, 0, 0, 1.4, 3.2, 0.95, Map3DPalette.tileWhite)
            box(0.1, 0.95, 0, 1.6, 3.4, 0.08, Map3DPalette.counters[1]) // service counter top
            // Cup sealer machine
            box(-0.2, 1.03, -0.9, 0.45, 0.45, 0.65, Self.commBlue)
            cylinder(-0.2, 1.68, -0.9, radius: 0.16, height: 0.15, color: Self.commYellow, sides: 8)
            // 3 Stainless thermal tea urns
            for i in 0..<3 {
                let pz: Float = -0.2 + Float(i) * 0.5
                cylinder(-0.2, 1.03, pz, radius: 0.18, height: 0.55, color: Self.steel, sides: 10)
                box(0.05, 1.15, pz, 0.12, 0.08, 0.1, Self.commRed) // spigot
            }
            // Overhead illuminated digital menu board
            box(0, 2.3, 0, 0.15, 2.8, 0.65, Self.steel)
            box(0.08, 2.34, 0, 0.02, 2.65, 0.55, Map3DPalette.trainAccent)

        case .bentoShop:
            // Hot food display counter with warming trays
            box(0, 0, 0, 1.5, 3.0, 0.85, Map3DPalette.concrete)
            box(0.1, 0.85, 0, 1.6, 3.1, 0.08, Self.steel)
            // Sneeze guard glass
            box(0.45, 0.93, 0, 0.05, 2.8, 0.55, Self.glass)
            box(0.2, 1.48, 0, 0.55, 2.8, 0.05, Self.glass)
            // 4 Stainless food insert pans
            for i in 0..<4 {
                let pz: Float = -0.9 + Float(i) * 0.6
                box(0, 0.93, pz, 0.55, 0.45, 0.15, Self.commBrick)
            }
            // Soup cauldron station on side
            cylinder(-0.4, 0, 1.1, radius: 0.35, height: 0.85, color: Self.steel, sides: 10)
            cylinder(-0.4, 0.85, 1.1, radius: 0.32, height: 0.25, color: Self.commRed, sides: 10)

        case .bakery:
            // Bread display counter with 3 tiered wooden shelves
            box(0, 0, 0, 1.3, 2.8, 0.80, Map3DPalette.counters[1])
            // 3 Inclined display shelves
            for tier in 0..<3 {
                let ty: Float = 0.88 + Float(tier) * 0.42
                let tx: Float = 0.15 - Float(tier) * 0.12
                box(tx, ty, 0, 0.85, 2.6, 0.05, Map3DPalette.counters[0])
                // Simulated pastry items
                for i in 0..<4 {
                    let pz: Float = -0.9 + Float(i) * 0.6
                    cylinder(tx, ty + 0.05, pz, radius: 0.12, height: 0.10, color: Self.commYellow, sides: 8)
                }
            }
            // Warm timber top canopy
            box(-0.1, 2.2, 0, 1.2, 2.8, 0.15, Map3DPalette.counters[1])

        case .pharmacy:
            // Medical dispensing counter & medicine shelving
            box(0, 0, 0, 1.2, 2.6, 0.90, Map3DPalette.tileWhite)
            box(0.05, 0.90, 0, 1.3, 2.7, 0.06, Map3DPalette.concrete)
            // Medicine back wall shelving
            box(-0.9, 0, 0, 0.45, 2.6, 2.2, Map3DPalette.tileWhite)
            for shelf in 1...4 {
                box(-0.7, Float(shelf) * 0.45, 0, 0.4, 2.5, 0.04, Map3DPalette.concrete)
                // Medicine boxes
                for i in 0..<5 {
                    let pz: Float = -0.9 + Float(i) * 0.45
                    box(-0.7, Float(shelf) * 0.45 + 0.04, pz, 0.25, 0.30, 0.25, Self.commBlue)
                }
            }
            // Green cross illuminated lightbox
            box(0.4, 1.1, 1.1, 0.15, 0.55, 0.55, Map3DPalette.tileWhite)
            box(0.48, 1.15, 1.1, 0.04, 0.45, 0.15, Self.commMint)
            box(0.48, 1.15, 1.1, 0.04, 0.15, 0.45, Self.commMint)

        case .cornerGrocery:
            // Traditional Taiwanese grocery counter with snack jars
            box(0, 0, 0, 1.4, 2.8, 0.78, Map3DPalette.counters[1])
            // 4 Clear cylindrical candy jars with red lids
            for i in 0..<4 {
                let pz: Float = -0.9 + Float(i) * 0.6
                cylinder(0.1, 0.78, pz, radius: 0.18, height: 0.38, color: Self.glass, sides: 10)
                cylinder(0.1, 1.16, pz, radius: 0.20, height: 0.08, color: Self.commRed, sides: 10)
            }
            // Beverage glass-door cooler on side
            box(-0.4, 0, -1.8, 0.85, 0.85, 1.9, Map3DPalette.tileWhite)
            pane(0.05, 0.15, -1.8, 0.65, 1.6)

        case .stationeryStore:
            // 4-tier inclined book/magazine display table & postcard rack
            box(0, 0, 0, 1.5, 2.6, 0.75, Map3DPalette.concrete)
            for tier in 0..<3 {
                let ty: Float = 0.80 + Float(tier) * 0.35
                let tx: Float = 0.2 - Float(tier) * 0.15
                box(tx, ty, 0, 0.75, 2.4, 0.05, Map3DPalette.counters[1])
                for i in 0..<3 {
                    let pz: Float = -0.7 + Float(i) * 0.7
                    box(tx, ty + 0.05, pz, 0.45, 0.50, 0.18, Self.commBlue)
                }
            }
            // Rotating postcard rack
            cylinder(-0.5, 0, 1.6, radius: 0.05, height: 1.7, color: Self.steel, sides: 6)
            cylinder(-0.5, 0.8, 1.6, radius: 0.30, height: 0.8, color: Self.commYellow, sides: 8)

        case .ramenYatai:
            // Traditional wooden food cart with fabric noren and stools
            box(0, 0, 0, 1.6, 2.4, 0.75, Map3DPalette.counters[1])
            box(0.1, 0.75, 0, 1.8, 2.6, 0.08, Map3DPalette.counters[0]) // counter ledge
            // 4 Corner wooden roof posts
            for cx: Float in [-0.7, 0.7] {
                for cz: Float in [-1.1, 1.1] {
                    box(cx, 0.75, cz, 0.10, 0.10, 1.5, Map3DPalette.counters[1])
                }
            }
            // Gabled wooden roof
            gable(0, 2.25, 0, 2.0, 2.8, 0.55, Map3DPalette.playerRoof)
            // Fabric noren valance along front
            box(0.9, 1.95, 0, 0.05, 2.6, 0.30, Self.commRed)
            // Broth pot
            cylinder(-0.2, 0.83, -0.4, radius: 0.25, height: 0.35, color: Self.steel, sides: 10)
            // 3 Wooden round dining stools
            for i in 0..<3 {
                let sz: Float = -0.8 + Float(i) * 0.8
                cylinder(1.2, 0, sz, radius: 0.22, height: 0.48, color: Map3DPalette.counters[1], sides: 8)
                cylinder(1.2, 0, sz, radius: 0.06, height: 0.45, color: Self.steel, sides: 6)
            }

        case .nightMarketFryer:
            // Stainless deep fryer cart with sneeze shield
            box(0, 0, 0, 1.2, 2.2, 0.82, Self.steel)
            box(0.05, 0.82, 0, 1.3, 2.3, 0.06, Self.steel)
            // Glass shield
            box(0.4, 0.88, 0, 0.04, 2.1, 0.55, Self.glass)
            box(0.15, 1.43, 0, 0.50, 2.1, 0.04, Self.glass)
            // Deep fryer well & oil basket
            box(-0.1, 0.75, -0.5, 0.55, 0.65, 0.25, Map3DPalette.playerRim)
            box(-0.1, 0.88, 0.4, 0.55, 0.95, 0.12, Self.commYellow) // fried snacks tray
            // Exhaust pipe hood
            cylinder(-0.3, 1.5, 0, radius: 0.25, height: 0.5, color: Self.steel, sides: 8)
            cylinder(-0.3, 2.0, 0, radius: 0.12, height: 0.5, color: Self.steel, sides: 8)

        case .nightMarketFruit:
            // Stainless fruit cart with crushed ice display
            box(0, 0, 0, 1.2, 2.4, 0.80, Self.steel)
            // Crushed ice trough
            box(0.05, 0.80, 0, 1.1, 2.3, 0.15, Map3DPalette.tileWhite)
            // Acrylic sneeze shield
            box(0.45, 0.95, 0, 0.04, 2.2, 0.45, Self.glass)
            // 4 Colorful fresh fruit trays
            let fruitColors = [Self.commRed, Self.commYellow, Self.commMint, 0xFFFF8040]
            for i in 0..<4 {
                let pz: Float = -0.75 + Float(i) * 0.5
                box(0.05, 0.95, pz, 0.65, 0.42, 0.12, fruitColors[i])
            }
            // Overhead task lamp
            beam(Map3DPoint(-0.4, 0.8, -0.9), Map3DPoint(-0.4, 1.9, -0.9), 0.05, Self.steel)
            beam(Map3DPoint(-0.4, 1.9, -0.9), Map3DPoint(0.1, 1.9, 0), 0.05, Self.steel)
            cylinder(0.1, 1.82, 0, radius: 0.12, height: 0.15, color: Self.commYellow, sides: 8)

        case .nightMarketGame:
            // 4-unit marble pinball stall with prize rack
            box(0, 0, 0, 1.4, 2.4, 0.65, Map3DPalette.counters[1])
            // 4 Inclined pinball boards
            for i in 0..<4 {
                let pz: Float = -0.75 + Float(i) * 0.5
                box(0.1, 0.70, pz, 0.95, 0.42, 0.15, Self.commBlue)
            }
            // Rear prize display shelves
            box(-0.6, 0.65, 0, 0.35, 2.4, 1.2, Map3DPalette.counters[0])
            for i in 0..<3 {
                let pz: Float = -0.6 + Float(i) * 0.6
                box(-0.55, 1.2, pz, 0.25, 0.35, 0.35, Self.commRed)
            }
            // Plastic player stool
            cylinder(0.9, 0, 0, radius: 0.22, height: 0.35, color: Self.commMint, sides: 8)

        case .vendingBank:
            // Bank of 3 modern beverage vending machines with recycling bin
            for i in 0..<3 {
                let pz: Float = -1.1 + Float(i) * 1.05
                let bodyColor = i == 0 ? Self.commRed : i == 1 ? Self.commBlue : Self.commMint
                box(0, 0, pz, 0.95, 0.95, 1.95, bodyColor)
                // Display window
                pane(0.48, 0.65, pz, 0.75, 0.95)
                // Coin slot & dispense tray
                box(0.48, 0.20, pz, 0.04, 0.65, 0.25, Map3DPalette.playerRim)
            }
            // Attached plastic bottle/can recycling receptacle
            box(0, 0, 1.6, 0.75, 0.75, 1.05, Map3DPalette.concrete)
            cylinder(0, 1.05, 1.45, radius: 0.12, height: 0.04, color: Map3DPalette.playerRim, sides: 8)
            cylinder(0, 1.05, 1.75, radius: 0.12, height: 0.04, color: Map3DPalette.playerRim, sides: 8)

        case .mobileFoodCart:
            // Mobile towable food trailer with fold-up awning hatch
            box(0, 0.25, 0, 2.8, 1.8, 2.0, Map3DPalette.tileWhite)
            // Wheel wells & 2 tires
            commWheel(0, 0, -1.0, radius: 0.40, width: 0.22)
            commWheel(0, 0, 1.0, radius: 0.40, width: 0.22)
            // Side serving hatch opening
            box(0, 0.75, -0.92, 1.8, 0.05, 0.95, Map3DPalette.playerRim)
            // Fold-up awning hatch door
            commAwning(0, 1.75, -1.2, length: 2.0, width: 0.9, rise: 0.15, color: Self.commYellow)
            // Front tow hitch tongue
            beam(Map3DPoint(1.4, 0.35, 0), Map3DPoint(2.2, 0.35, 0), 0.10, Self.steel)
            cylinder(2.0, 0, 0, radius: 0.08, height: 0.35, color: Self.steel, sides: 6) // jockey wheel
        default:
            break
        }
    }
}
