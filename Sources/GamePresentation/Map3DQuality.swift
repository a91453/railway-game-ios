// Decision 238's later note (2026-10-21, the owner asked whether players
// should set the 3D map's look themselves): three choices, each one set
// of the values the map already has, and no sliders.

/// The 3D map's look, chosen in Settings.
public enum Map3DQuality: String, CaseIterable, Sendable {
    /// The sharpest picture until the GPU keeps over its budget
    /// (``Map3DDrawScale``); in Low Power Mode or when the phone runs hot,
    /// as ``saving``.
    case automatic
    /// Fewer pixels and half the frames from the start.
    case saving
    /// The sharpest picture always, but when the phone is about to slow
    /// itself down for heat.
    case high

    /// Where the choice is kept, on the device.
    public static let key = "map3D.quality"

    /// How hot the phone is: `ProcessInfo.ThermalState`'s four steps.
    public enum Heat: Int, Comparable, Sendable {
        case nominal, fair, serious, critical

        public static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
    }

    /// What the map draws.
    public struct Plan: Equatable, Sendable {
        /// The frames a second it aims for.
        public var framesPerSecond: Int
        /// Whether it draws fewer pixels from the start.
        public var fewerPixels: Bool
        /// Whether a GPU that keeps over its budget makes it draw fewer.
        public var lowersWhenOver: Bool
    }

    /// The plan with Low Power Mode on or off and the phone at `heat`.
    public func plan(lowPower: Bool, heat: Heat) -> Plan {
        switch self {
        case .automatic:
            if lowPower || heat >= .serious { return Self.saving.plan(lowPower: lowPower, heat: heat) }
            return Plan(framesPerSecond: 60, fewerPixels: false, lowersWhenOver: true)
        case .saving:
            return Plan(framesPerSecond: 30, fewerPixels: true, lowersWhenOver: true)
        case .high:
            return Plan(framesPerSecond: 60, fewerPixels: heat >= .critical, lowersWhenOver: false)
        }
    }
}
