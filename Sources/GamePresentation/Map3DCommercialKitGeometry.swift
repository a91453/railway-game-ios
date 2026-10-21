import Foundation

extension StationKitBuilder {
    static let commBlue: UInt32 = Map3DPalette.trainAccent
    static let commYellow: UInt32 = Map3DPalette.trainYellow
    static let commRed: UInt32 = Map3DPalette.templeRidge
    static let commCrimson: UInt32 = 0xFFA0241E
    static let commMint: UInt32 = 0xFF48A878
    static let commBusGreen: UInt32 = 0xFF28854E
    static let commCyan: UInt32 = 0xFF2292A4
    static let commOrange: UInt32 = 0xFFF06520
    static let commWarmWhite: UInt32 = 0xFFFAF6EE
    static let commDark: UInt32 = Map3DPalette.playerRim
    static let commDarkRoof: UInt32 = Map3DPalette.darkRoof
    static let commConcrete: UInt32 = Map3DPalette.concrete
    static let commBrick: UInt32 = Map3DPalette.counters[1]
    static let commWarmWood: UInt32 = 0xFFB87842
    static let commDarkWood: UInt32 = 0xFF4A2E18
    static let commTatungGreen: UInt32 = 0xFF1B6B46
    static let commChrome: UInt32 = 0xFFE0E6ED
    static let commWarmGlow: UInt32 = 0xFFFFEA88
    static let commDarkGlass: UInt32 = 0xFF1C222C

    mutating func commercial(_ part: Map3DCommercialKit.Part) {
        switch part.category {
        case .building:
            commercialBuilding(part)
        case .shop:
            commercialShop(part)
        case .facility:
            commercialFacility(part)
        }
    }

    mutating func commWindowBand(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, floors: Int, bays: Int = 4, frameColor: UInt32 = Map3DPalette.tileWhite, glassColor: UInt32 = Self.glass) {
        for floor in 0..<floors {
            let floorY = y + 0.9 + Float(floor) * 3.2
            for i in 0..<bays {
                let offset = (Float(i) + 0.5) * width / Float(bays) - width / 2
                pane(x + length / 2, floorY, z + offset, width / Float(bays) * 0.70, 1.45)
                box(x - length / 2 - 0.015, floorY, z + offset, 0.03, width / Float(bays) * 0.70, 1.45, glassColor)
            }
            for sign: Float in [-1, 1] {
                for i in 0..<2 {
                    let offset = (Float(i) + 0.5) * length / 2 - length / 2
                    box(x + offset, floorY, z + sign * (width / 2 + 0.015), length * 0.32, 0.03, 1.45, glassColor)
                }
            }
        }
    }

    mutating func commAwning(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, rise: Float, color: UInt32) {
        let p1 = Map3DPoint(x - length / 2, y + rise, z - width / 2)
        let p2 = Map3DPoint(x + length / 2, y, z - width / 2)
        let p3 = Map3DPoint(x + length / 2, y, z + width / 2)
        let p4 = Map3DPoint(x - length / 2, y + rise, z + width / 2)
        let thick: Float = 0.08
        let d = Map3DPoint(0, -thick, 0)

        mesh.addQuad(p1, p2, p3, p4, color: color)
        mesh.addQuad(p4 + d, p3 + d, p2 + d, p1 + d, color: Map3DColor.shaded(color, 0.7))

        face([p1, p2, p2 + d, p1 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p4, p3, p3 + d, p4 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p2, p3, p3 + d, p2 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p1, p4, p4 + d, p1 + d], inside: Map3DPoint(x, y, z), color: color)

        box(x, y - 0.1, z, length, width, 0.12, color)
    }

    mutating func commStripedAwning(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, rise: Float, color1: UInt32, color2: UInt32, stripes: Int = 6) {
        let stripeW = width / Float(stripes)
        for i in 0..<stripes {
            let sz = z - width / 2 + (Float(i) + 0.5) * stripeW
            let c = (i % 2 == 0) ? color1 : color2
            commAwning(x, y, sz, length: length, width: stripeW, rise: rise, color: c)
        }
    }

    mutating func commWaterTank(_ x: Float, _ y: Float, _ z: Float, radius: Float = 0.85, height: Float = 1.35) {
        let spread = radius * 0.7
        for sx in [-spread, spread] {
            for sz in [-spread, spread] {
                box(x + sx, y, z + sz, 0.08, 0.08, 0.75, Self.steel)
            }
        }
        box(x, y + 0.35, z - spread, spread * 2, 0.06, 0.06, Self.steel)
        box(x, y + 0.35, z + spread, spread * 2, 0.06, 0.06, Self.steel)
        cylinder(x, y + 0.75, z, radius: radius, height: height, color: commChrome, sides: 12)
        cylinder(x, y + 0.75 + height, z, radius: radius * 0.95, height: 0.25, color: Self.steel, sides: 10)
    }

    mutating func commAirConditionerUnit(_ x: Float, _ y: Float, _ z: Float, length: Float = 0.85, width: Float = 0.35, height: Float = 0.65) {
        box(x, y, z, length, width, height, Map3DPalette.tileWhite)
        box(x + length / 2 + 0.01, y + height * 0.22, z, 0.02, height * 0.65, height * 0.65, Self.commDark)
        box(x + length / 2 + 0.02, y + height * 0.32, z, 0.02, height * 0.45, height * 0.45, Self.steel)
    }

    mutating func commLantern(_ x: Float, _ y: Float, _ z: Float, radius: Float = 0.25, height: Float = 0.45, color: UInt32 = commRed) {
        cylinder(x, y, z, radius: radius, height: height, color: color, sides: 8)
        cylinder(x, y - 0.06, z, radius: radius * 0.55, height: 0.06, color: Self.commDark, sides: 8)
        cylinder(x, y + height, z, radius: radius * 0.55, height: 0.06, color: Self.commDark, sides: 8)
    }

    mutating func commSignboard(_ x: Float, _ y: Float, _ z: Float, length: Float, height: Float, thickness: Float = 0.15, frameColor: UInt32 = Self.steel, faceColor: UInt32 = commYellow) {
        box(x, y, z, thickness, length, height, frameColor)
        box(x + thickness / 2 + 0.01, y + 0.04, z, 0.02, length - 0.12, height - 0.08, faceColor)
    }

    mutating func commWheel(_ x: Float, _ y: Float, _ z: Float, radius: Float = 0.48, width: Float = 0.28) {
        box(x, y, z, radius * 1.8, width, radius * 1.8, Self.commDarkRoof)
        box(x, y + radius * 0.25, z, radius * 1.0, width + 0.02, radius * 1.0, Self.steel)
    }
}
