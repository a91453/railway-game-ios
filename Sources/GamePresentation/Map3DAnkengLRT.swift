import Foundation

/// TRSC / Voith five-module Ankeng fleet. Static studies; no operational mapping.
/// Body dimensions: operator; internal module dimensions: photo-informed approximation.
public enum Map3DAnkengLRT {
    public enum Unit: String, CaseIterable, Sendable {
        case m1, m2, m3, m4, m5
        public var length: Float { switch self { case .m1, .m5: 8; case .m2, .m4: 6; case .m3: 4.45 } }
        public var centre: Float { switch self { case .m1: 13.225; case .m2: 5.725; case .m3: 0; case .m4: -5.725; case .m5: -13.225 } }
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        // Independent identity, livery and role contract. Shared only within this new family.
        NTLRTBody.model(id: "ankeng-lrt-" + unit.rawValue + (far ? "-far" : ""),
            length: unit.length, role: unit.rawValue, far: far, sea: false, body: NTLRTBody.blend(Map3DPalette.schoolWalls, Map3DPalette.containers[3], 0.35))
    }
}
