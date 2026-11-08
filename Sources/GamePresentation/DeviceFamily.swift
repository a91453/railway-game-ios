/// Which kind of device the game runs on, for text that names it
/// (decision 642): the language menu's "Same as iPhone" and the sound
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
}

/// How tall a card the game raises over the map can be (decision 642,
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
