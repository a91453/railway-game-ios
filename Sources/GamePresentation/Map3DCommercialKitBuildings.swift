import Foundation

extension StationKitBuilder {
    mutating func commercialBuilding(_ part: Map3DCommercialKit.Part) {
        switch part {
        case .departmentStore:
            // 4-level tiered department store
            box(0, 0, 0, 18, 22, 14, Map3DPalette.tileWhite)
            commWindowBand(0, 3.5, 0, length: 18, width: 22, floors: 3, bays: 6)
            // Ground floor grand entrance & display glass
            pane(9, 0.4, 0, 8, 3.0)
            commAwning(9.8, 3.4, 0, length: 2.2, width: 10, rise: 0.3, color: Self.commBlue)
            for side: Float in [-4.6, 4.6] { box(10.8, 0, side, 0.25, 0.25, 3.4, Self.steel) }
            // Setback upper level
            box(-1, 14, 0, 14, 18, 3.5, Map3DPalette.concrete)
            // Rooftop machinery & advertising sign frame
            box(-1, 17.5, 0, 14.4, 18.4, 0.25, Map3DPalette.roof)
            box(0, 17.75, 4, 3, 5, 2.2, Map3DPalette.tankStand)
            commSignboard(5, 17.75, 0, length: 12, height: 3.2, thickness: 0.3, frameColor: Self.steel, faceColor: Self.commRed)

        case .cinema:
            // Art Deco cinema with stepped vertical facade
            box(0, 0, 0, 16, 14, 11, Map3DPalette.counters[1])
            // Stepped central parapet
            box(8.05, 0, 0, 0.3, 8, 13.5, Map3DPalette.concrete)
            box(8.05, 0, 0, 0.4, 4, 14.8, Map3DPalette.trainAccent)
            // Windows with backplates
            commWindowBand(0, 4.5, 0, length: 16, width: 14, floors: 2, bays: 3)
            // Marquee canopy projecting over entrance
            box(9.2, 3.8, 0, 2.6, 10, 0.35, Map3DPalette.canopy)
            box(9.2, 3.55, 0, 2.4, 9.6, 0.15, Map3DPalette.trainYellow) // underside lighting
            // Tie rods supporting marquee
            beam(Map3DPoint(8.1, 7.5, -4), Map3DPoint(10.2, 4.15, -4), 0.10, Self.steel)
            beam(Map3DPoint(8.1, 7.5, 4), Map3DPoint(10.2, 4.15, 4), 0.10, Self.steel)
            // Center ticket booth
            box(7.5, 0, 0, 1.4, 2.2, 2.6, Self.steel)
            pane(8.2, 1.0, 0, 1.8, 1.4)
            // Ground entrance double doors
            pane(8.1, 0, -3.2, 2.2, 2.5)
            pane(8.1, 0, 3.2, 2.2, 2.5)
            // Roof parapet
            box(0, 11, 0, 16.4, 14.4, 0.35, Map3DPalette.roof)

        case .supermarket:
            // Wide single-story commercial supermarket with cart corral
            box(0, 0, 0, 15, 24, 6.5, Map3DPalette.concrete)
            // Front wide glass storefront
            pane(7.55, 0.4, 2, 12, 4.2)
            commWindowBand(0, 1.0, -8, length: 15, width: 6, floors: 1, bays: 2)
            // Supermarket entrance overhang
            commAwning(8.4, 4.8, 2, length: 2.2, width: 14, rise: 0.25, color: Self.commMint)
            for side: Float in [-6.5, 0, 6.5] { box(9.3, 0, 2 + side, 0.2, 0.2, 4.8, Self.steel) }
            // Cart return corral
            box(8.2, 0, -8, 2.8, 3.5, 0.12, Map3DPalette.concrete)
            box(8.2, 0.12, -9.6, 2.6, 0.1, 1.0, Self.steel)
            box(8.2, 0.12, -6.4, 2.6, 0.1, 1.0, Self.steel)
            box(6.9, 0.12, -8, 0.1, 3.2, 1.0, Self.steel)
            // Roof equipment
            box(0, 6.5, 0, 15.5, 24.5, 0.3, Map3DPalette.roof)
            cylinder(-2, 6.8, 4, radius: 1.2, height: 1.5, color: Map3DPalette.tankStand, sides: 8)
            cylinder(-2, 6.8, -4, radius: 1.2, height: 1.5, color: Map3DPalette.tankStand, sides: 8)

        case .cornerOffice:
            // 4-story commercial office building with chamfered corner
            box(0, 0, 0, 16, 16, 15.5, Map3DPalette.tileWhite)
            commWindowBand(0, 3.5, 0, length: 16, width: 16, floors: 3, bays: 4)
            // Ground floor entrance
            pane(8.05, 0, 0, 4.5, 3.2)
            box(8.8, 3.4, 0, 1.8, 6.0, 0.25, Map3DPalette.canopy)
            for side: Float in [-2.6, 2.6] { box(9.5, 0, side, 0.18, 0.18, 3.4, Self.steel) }
            // Corporate fascia band
            box(8.1, 3.8, 0, 0.25, 12, 1.1, Self.commBlue)
            // Rooftop elevator penthouse
            box(-2, 15.5, -2, 6, 6, 3.2, Map3DPalette.concrete)
            box(0, 15.5, 0, 16.4, 16.4, 0.35, Map3DPalette.roof)

        case .yellowCafe:
            // Warm yellow brick cafe with outdoor seating patio
            box(0, 0, 0, 10, 11, 7.5, Self.commBrick)
            // Ground floor display bay
            pane(5.05, 0.6, -1.8, 4.2, 2.4)
            pane(5.05, 0, 2.5, 1.8, 2.6) // entrance door
            commWindowBand(0, 4.0, 0, length: 10, width: 11, floors: 1, bays: 3)
            // Striped awning
            commAwning(5.8, 3.4, -1.8, length: 1.8, width: 5.2, rise: 0.25, color: Self.commYellow)
            // Mansard roof top
            box(0, 7.5, 0, 10.5, 11.5, 0.35, Map3DPalette.roof)
            gable(0, 7.85, 0, 9.5, 10.5, 2.6, Map3DPalette.playerRoof)

        case .gasStation:
            // Overhead pump island canopy with service kiosk
            // Service kiosk building
            box(-6, 0, 0, 6, 10, 4.2, Map3DPalette.tileWhite)
            pane(-3.05, 0.2, 0, 4.5, 2.8)
            commWindowBand(-6, 1.0, 0, length: 6, width: 10, floors: 1, bays: 2)
            box(-6, 4.2, 0, 6.4, 10.4, 0.25, Map3DPalette.roof)
            // Island canopy
            box(4, 5.2, 0, 12, 18, 0.6, Map3DPalette.canopy)
            box(4, 5.0, 0, 11.6, 17.6, 0.1, Map3DPalette.tileWhite) // underside
            // 4 canopy support pillars
            for cx: Float in [0, 8] {
                for cz: Float in [-5.5, 5.5] {
                    cylinder(cx, 0, cz, radius: 0.30, height: 5.2, color: Self.steel, sides: 12)
                }
            }
            // Twin pump islands
            for pz: Float in [-4, 4] {
                box(4, 0, pz, 6, 1.8, 0.22, Map3DPalette.concrete)
                // Fuel dispenser pumps
                box(2.8, 0.22, pz, 1.1, 0.9, 1.6, Self.commRed)
                box(5.2, 0.22, pz, 1.1, 0.9, 1.6, Self.commBlue)
                // Protective bollards
                cylinder(0.7, 0, pz, radius: 0.12, height: 0.9, color: Self.commYellow, sides: 8)
                cylinder(7.3, 0, pz, radius: 0.12, height: 0.9, color: Self.commYellow, sides: 8)
            }
            // Totem price sign
            box(11, 0, -9, 0.4, 2.0, 6.5, Self.commBlue)
            box(11, 3.2, -9, 0.5, 1.8, 2.8, Map3DPalette.trainYellow)

        case .parkingGarage:
            // 3-tier concrete open-structure parking garage
            let length: Float = 16, width: Float = 18
            for tier in 0..<3 {
                let ty = Float(tier) * 3.4
                box(0, ty, 0, length, width, 0.35, Map3DPalette.concrete)
                // Exterior safety barrier railings
                for sign: Float in [-1, 1] {
                    box(0, ty + 0.35, sign * (width / 2 - 0.1), length, 0.18, 0.9, Self.steel)
                    box(sign * (length / 2 - 0.1), ty + 0.35, 0, 0.18, width, 0.9, Self.steel)
                }
            }
            // Structural corner & intermediate columns
            for cx: Float in [-length / 2 + 0.6, 0, length / 2 - 0.6] {
                for cz: Float in [-width / 2 + 0.6, 0, width / 2 - 0.6] {
                    box(cx, 0, cz, 0.8, 0.8, 7.2, Map3DPalette.concrete)
                }
            }
            // Entrance barrier gate & ticket console
            box(8.2, 0, 2.5, 0.5, 0.5, 1.2, Self.commYellow)
            box(8.2, 0.9, 0.5, 0.15, 3.2, 0.15, Self.commRed) // barrier arm
            // Concrete approach ramp
            stairs(-2, 0, 7.2, run: 8, width: 3.2, rise: 3.4)

        case .commercialHotel:
            // Boutique business hotel with porte-cochere vehicle drop-off
            box(0, 0, 0, 14, 18, 17, Map3DPalette.tileWhite)
            commWindowBand(0, 4.0, 0, length: 14, width: 18, floors: 4, bays: 4)
            // Ground floor lobby picture windows
            pane(7.05, 0.3, 0, 10, 3.2)
            // Porte-cochere drop-off canopy
            box(9.2, 3.8, 0, 5.0, 12, 0.4, Map3DPalette.canopy)
            for cz: Float in [-4.8, 4.8] {
                cylinder(11.2, 0, cz, radius: 0.32, height: 3.8, color: Self.steel, sides: 12)
            }
            // Vertical hotel blade sign on facade corner
            box(7.15, 6, -7.5, 0.4, 0.9, 9.5, Self.commBlue)
            box(0, 17, 0, 14.5, 18.5, 0.35, Map3DPalette.roof)

        case .bankBranch:
            // Classical commercial bank with granite portal and ATM vestibule
            box(0, 0, 0, 14, 16, 9.5, Map3DPalette.concrete)
            commWindowBand(0, 4.2, 0, length: 14, width: 16, floors: 1, bays: 4)
            // Front granite entrance portal & pillars
            box(7.05, 0, 0, 0.6, 12, 8.8, Map3DPalette.tankStand)
            for pz: Float in [-4, -1.5, 1.5, 4] {
                cylinder(7.35, 0, pz, radius: 0.38, height: 7.2, color: Map3DPalette.tileWhite, sides: 12)
            }
            // Main double entrance doors with shutter housing
            pane(7.1, 0, 0, 2.8, 3.4)
            box(7.2, 3.5, 0, 0.4, 3.4, 0.6, Self.steel)
            // ATM vestibule on right
            pane(7.1, 0, 5.2, 2.0, 3.0)
            box(6.8, 0.9, 5.2, 0.3, 1.2, 0.9, Self.commBlue) // ATM console
            // Classical pediment top
            box(7.2, 7.2, 0, 0.8, 12.8, 1.6, Map3DPalette.concrete)
            box(0, 9.5, 0, 14.4, 16.4, 0.35, Map3DPalette.roof)

        case .stackedShopHouse:
            // 3-story Taiwanese commercial shophouse with arcade (騎樓) setback
            box(-1.5, 0, 0, 11, 7.5, 12, Map3DPalette.counters[1])
            // Ground floor arcade walkway & front columns
            box(3.5, 0, 0, 2.5, 7.5, 0.18, Map3DPalette.concrete) // sidewalk
            box(4.5, 0, -3.2, 0.5, 0.5, 3.8, Map3DPalette.concrete)
            box(4.5, 0, 3.2, 0.5, 0.5, 3.8, Map3DPalette.concrete)
            // Ground floor shop shutter & entrance
            pane(2.2, 0, 0, 5.5, 2.8)
            box(2.25, 2.9, 0, 0.3, 6.0, 0.6, Self.steel) // roll-up shutter box
            // Upper floors window bands & balconies
            commWindowBand(-1.5, 4.2, 0, length: 11, width: 7.5, floors: 2, bays: 2)
            for floor in 1...2 {
                let by = Float(floor) * 3.8
                box(4.2, by, 0, 1.4, 7.5, 0.22, Map3DPalette.concrete)
                box(4.8, by + 0.22, 0, 0.12, 7.5, 0.9, Self.steel) // security railing
            }
            // Rooftop water tank
            box(-1.5, 12, 0, 11.4, 7.9, 0.35, Map3DPalette.roof)
            cylinder(-3, 12.35, 1.5, radius: 0.9, height: 1.8, color: Self.steel, sides: 12)

        case .warehouseStore:
            // Commercial wholesale warehouse with raised loading dock
            box(0, 0, 0, 16, 20, 8.5, Map3DPalette.concrete)
            commWindowBand(0, 4.5, 0, length: 16, width: 20, floors: 1, bays: 4)
            // Raised loading dock (1.2m height)
            box(9.2, 0, 0, 2.8, 14, 1.2, Map3DPalette.concrete)
            // 2 roll-up cargo doors
            for side: Float in [-3.5, 3.5] {
                box(8.05, 1.2, side, 0.2, 4.5, 4.2, Self.steel)
                // Rubber bumper pads on dock edge
                box(10.6, 0.7, side - 1.8, 0.15, 0.35, 0.6, Map3DPalette.playerRim)
                box(10.6, 0.7, side + 1.8, 0.15, 0.35, 0.6, Map3DPalette.playerRim)
            }
            // Gabled metal roof
            gable(0, 8.5, 0, 16.5, 20.5, 3.2, Self.commBlue)

        case .metroEntrance:
            // Angled tempered glass metro entrance pavilion
            // Granite escalator pit walls
            box(0, 0, 0, 9, 5.5, 1.2, Map3DPalette.tankStand)
            // Escalator stair well opening
            stairs(0.5, 0, 0, run: 6.5, width: 2.8, rise: 2.2)
            // Angled glass canopy structure
            canopy(0, 2.4, 0, length: 10.5, width: 6.2, rise: 1.4, color: Self.commMint)
            // 4 tubular steel canopy columns
            for cx: Float in [-4, 4] {
                for cz: Float in [-2.6, 2.6] {
                    cylinder(cx, 0, cz, radius: 0.16, height: 2.8, color: Self.steel, sides: 8)
                }
            }
            // Transit signage totem
            box(5.2, 0, 3.2, 0.35, 0.8, 3.6, Self.commMint)
            box(5.2, 2.6, 3.2, 0.42, 0.7, 0.7, Map3DPalette.tileWhite)
        default:
            break
        }
    }
}
