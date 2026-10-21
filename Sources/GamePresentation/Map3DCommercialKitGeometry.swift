import Foundation

extension StationKitBuilder {
    static let commBlue: UInt32 = Map3DPalette.trainAccent
    static let commYellow: UInt32 = Map3DPalette.trainYellow
    static let commRed: UInt32 = Map3DPalette.templeRidge
    static let commMint: UInt32 = 0xFF58B98C // Taiwanese transit mint green
    static let commCream: UInt32 = Map3DPalette.tileWhite
    static let commDark: UInt32 = Map3DPalette.playerRim
    static let commConcrete: UInt32 = Map3DPalette.concrete
    static let commBrick: UInt32 = Map3DPalette.counters[1]

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

    mutating func commWindowBand(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, floors: Int, bays: Int = 4) {
        for floor in 0..<floors {
            let floorY = y + 0.9 + Float(floor) * 3.2
            for i in 0..<bays {
                let offset = (Float(i) + 0.5) * width / Float(bays) - width / 2
                pane(x + length / 2, floorY, z + offset, width / Float(bays) * 0.70, 1.45)
                box(x - length / 2 - 0.015, floorY, z + offset, 0.03, width / Float(bays) * 0.70, 1.45, Self.glass)
            }
            for sign: Float in [-1, 1] {
                for i in 0..<2 {
                    let offset = (Float(i) + 0.5) * length / 2 - length / 2
                    box(x + offset, floorY, z + sign * (width / 2 + 0.015), length * 0.32, 0.03, 1.45, Self.glass)
                }
            }
        }
    }

    mutating func commAwning(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, rise: Float, color: UInt32) {
        // Closed double-surface canopy: top, bottom, and side faces
        let p1 = Map3DPoint(x - length / 2, y + rise, z - width / 2)
        let p2 = Map3DPoint(x + length / 2, y, z - width / 2)
        let p3 = Map3DPoint(x + length / 2, y, z + width / 2)
        let p4 = Map3DPoint(x - length / 2, y + rise, z + width / 2)
        let thick: Float = 0.08
        let d = Map3DPoint(0, -thick, 0)

        // Top surface
        mesh.addQuad(p1, p2, p3, p4, color: color)
        // Bottom underside
        mesh.addQuad(p4 + d, p3 + d, p2 + d, p1 + d, color: Map3DColor.shaded(color, 0.7))

        // Side closures
        face([p1, p2, p2 + d, p1 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p4, p3, p3 + d, p4 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p2, p3, p3 + d, p2 + d], inside: Map3DPoint(x, y, z), color: color)
        face([p1, p4, p4 + d, p1 + d], inside: Map3DPoint(x, y, z), color: color)

        // Triangular side valances
        box(x, y - 0.1, z, length, width, 0.12, color)
    }

    mutating func commSignboard(_ x: Float, _ y: Float, _ z: Float, length: Float, height: Float, thickness: Float = 0.15, frameColor: UInt32 = Self.steel, faceColor: UInt32 = commYellow) {
        box(x, y, z, thickness, length, height, frameColor)
        box(x + thickness / 2 + 0.01, y + 0.04, z, 0.02, length - 0.12, height - 0.08, faceColor)
    }

    mutating func commWheel(_ x: Float, _ y: Float, _ z: Float, radius: Float = 0.48, width: Float = 0.28) {
        cylinder(x, y + radius, z, radius: radius, height: width, color: Self.darkRoof, sides: 12)
        cylinder(x, y + radius, z - 0.02, radius: radius * 0.55, height: width + 0.04, color: Self.steel, sides: 8)
    }
}
