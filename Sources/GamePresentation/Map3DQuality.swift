// Decision 238's later note (2026-10-21, the owner asked whether players
// should set the 3D map's look themselves): three choices, each one set
// of the values the map already has, and no sliders. Decision 365: a
// fourth, Off, for playing on the flat map only.

/// The 3D map's look, chosen in Settings.
public enum Map3DQuality: String, CaseIterable, Sendable {
    /// The sharpest picture until the GPU keeps over its budget
    /// (``Map3DDrawScale``); in Low Power Mode or when the phone runs hot,
    /// as ``saving``.
    case automatic
    /// Fewer pixels and half the frames from the start, and no sun shadows
    /// (decision 357, ``Map3DSunShadow``).
    case saving
    /// The sharpest picture always, but when the phone is about to slow
    /// itself down for heat.
    case high
    /// Decision 365: no 3D on the map: the 3D buttons put away and nothing
    /// built ahead for it while the flat map is pinched close.
    case off

    /// Where the choice is kept, on the device.
    public static let key = "map3D.quality"

    /// Decision 365: the first Apple GPU family (`MTLGPUFamily.apple7`,
    /// the A14 of the iPhone 12) the 3D map starts on; older GPUs start
    /// with it ``off``.
    public static let lowestFamilyFor3D = 7

    /// The choice a device with the Apple GPU family `family` (``Map3DStreetDetail/forGPUFamily(_:)``'s
    /// number) starts with, before the player picks one: a choice already
    /// kept is never changed.
    public static func startingChoice(gpuFamily family: Int) -> Map3DQuality {
        family >= lowestFamilyFor3D ? .automatic : .off
    }

    /// Whether the map offers 3D: its buttons, a pinch past the flat map's
    /// closest zoom and the scene built ahead for it.
    public var shows3D: Bool { self != .off }

    /// The look the 3D map draws with, opened from Settings while 3D is
    /// ``off``: the lightest one.
    public var drawn: Map3DQuality { self == .off ? .saving : self }

    /// Decision 365: the samples a pixel the 3D map takes against jagged
    /// edges: four (the thin rails smooth), one on ``saving``, which spends
    /// the GPU's time and memory on frames instead.
    public var samplesPerPixel: Int { drawn == .saving ? 1 : 4 }

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
        case .saving, .off:
            return Plan(framesPerSecond: 30, fewerPixels: true, lowersWhenOver: true)
        case .high:
            return Plan(framesPerSecond: 60, fewerPixels: heat >= .critical, lowersWhenOver: false)
        }
    }
}
