/// Which kind of device the game runs on, for text that names it
/// (decision 643): the language menu's "Same as iPhone" and the sound
/// footer's silent mode read "iPad" on an iPad. The app reads it from
/// `UIDevice`; GamePresentation only words it.
public enum DeviceFamily: CaseIterable, Hashable, Sendable {
    case iPhone
    case iPad

    /// The device's name as Apple writes it, the same in both languages.
    public var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }

    /// Whether a lesson's track step moves the map to show both towns
    /// (``GameSession/tutorialFraming``, decision 643, the iPad
    /// playtest's A1): on an iPad, where the building panel and the
    /// toolbar hid one. Not on an iPhone on its side: the map left clear
    /// there is so short that both towns fit only zoomed out to about
    /// 9 km across 400 points, where the first stretch tapped is too long
    /// to afford; there the player zooms out at the step before.
    public var framesTheLessonsTowns: Bool {
        self == .iPad
    }
}

/// How tall a card the game raises over the map can be (decision 643,
/// the iPad playtest's A2): on an iPhone it opens at half the screen,
/// the map still in sight, and is pulled up for the rest; on an iPad half
/// the screen was a short card at the bottom of a tall one, its form cut
/// after a few rows and a wide empty band under it, so it opens at its
/// full height, as Settings and Help do.
public enum SheetHeight: CaseIterable, Hashable, Sendable {
    case half
    case full

    /// The heights a card may take on `device`, the first the one it opens at.
    public static func offered(on device: DeviceFamily) -> [SheetHeight] {
        switch device {
        case .iPhone: [.half, .full]
        case .iPad: [.full]
        }
    }
}
