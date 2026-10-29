import Foundation

/// Game-style paint on existing E200CK units; no claim of an official E200 livery.
/// Deliberately studies-only: there is no independent player livery selector.
public enum Map3DE200MingriStyle {
    public enum Role: String, CaseIterable, Sendable { case head, car, tail }
    public static let orange = Map3DColor.rgb(UInt32(TrainLivery.mingRi.stripe!))
    public static let black = Map3DColor.rgb(UInt32(TrainLivery.mingRi.body!))

    static func original(_ role: Role, far: Bool) -> Map3DModelPack.Model {
        let raw: Map3DModelPack.Model = switch role {
        case .head: Map3DTrainSet.lit(Map3DTrainShapeRefresh.model("refresh-e200"), front: true)
        case .car: Map3DChuKuangPassenger.model(.standard, far: far)
        case .tail: Map3DTrainSet.chuKuangTail(far: far)
        }
        return raw
    }

    /// One triangle keeps its complete original geometry and all non-colour fields.
    /// The mask is local to these recipes, never a global palette replacement.
    static func paint(_ triangle: ArraySlice<Map3DVertex>, role: Role, index: Int, far: Bool) -> UInt32? {
        let first = triangle.first!, c = first.color
        let z = triangle.map(\.z).reduce(0,+) / 3
        let x = triangle.map(\.x).reduce(0,+) / 3
        let y = triangle.map(\.y).reduce(0,+) / 3
        if first.glows || Map3DTrainMaterial.isGlassColour(c) { return nil }
        let shades: [Float] = [1,0.7,0.8,0.86,0.92]
        func recolour(_ from: UInt32, _ to: UInt32) -> UInt32? {
            for s in shades where c == Map3DColor.shaded(from,s) { return Map3DColor.shaded(to,s) }
            return nil
        }
        if role == .head {
            // Original shell is the first 44 triangles, including the dark floor.
            if index < 44, c == Map3DPalette.shopAwnings[3] { return black }
            if let v = recolour(Map3DPalette.shopAwnings[0], orange), z > 1.1, z < 2.8 { return v }
            // Existing painted cab doors and V stripe, not roof insulators.
            if abs(y) > 1.47, abs(x) > 6.8, abs(x) < 7.6, z < 3.4,
               let v = recolour(Map3DPalette.tankWhite,black) { return v }
            if abs(x) > 8.50, z > 1.8, z < 2.8, c == Map3DPalette.shopAwnings[3] { return black }
        } else {
            // Only shell and existing door leaves/waist stripe. Roof, A/C,
            // dark frames, glass, gangways, vents, bogies and equipment stay.
            let shellCount = 7 * (far ? 21 : 29) * 2 + 16 + (far ? 11 : 19) * 2
            if index < shellCount, c == Map3DChuKuangPassenger.bodyColor || c == Map3DColor.rgb(0xECE2BC) {
                return z <= 1.92 ? orange : black
            }
            if abs(y) > 1.45, abs(x) > 8.5, abs(x) < 9.4, z < 3.14 {
                if let v = recolour(Map3DChuKuangPassenger.bodyColor,black) { return v }
                if let v = recolour(Map3DColor.rgb(0xECE2BC),orange) { return v }
            }
        }
        return nil
    }

    public static func model(_ role: Role, far: Bool = false) -> Map3DModelPack.Model {
        let base = original(role,far:far)
        var vertices = base.vertices
        for start in stride(from:0,to:vertices.count,by:3) {
            if let color = paint(base.vertices[start..<start+3],role:role,index:start/3,far:far) {
                for i in start..<start+3 { vertices[i].color = color }
            }
        }
        return .init(name:"e200mingri-style-" + role.rawValue + (far ? "-far" : ""),
                     vertices:vertices,minimum:base.minimum,maximum:base.maximum)
    }
}
