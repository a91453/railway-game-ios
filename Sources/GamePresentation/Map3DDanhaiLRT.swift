import Foundation

/// TRSC / Voith five-module Danhai fleet. Static studies; no operational mapping.
/// Body dimensions: operator; internal module dimensions: photo-informed approximation.
public enum Map3DDanhaiLRT {
    public enum Unit: String, CaseIterable, Sendable {
        case m1, m2, m3, m4, m5
        public var length: Float { switch self { case .m1, .m5: 8; case .m2, .m4: 6; case .m3: 4.45 } }
        public var centre: Float { switch self { case .m1: 13.225; case .m2: 5.725; case .m3: 0; case .m4: -5.725; case .m5: -13.225 } }
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        // Independent identity, livery and role contract. Shared only within this new family.
        NTLRTBody.model(id: "danhai-lrt-" + unit.rawValue + (far ? "-far" : ""),
            length: unit.length, role: unit.rawValue, far: far, sea: true, body: Map3DPalette.water)
    }
}
