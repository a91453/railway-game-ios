/// Which kind of device the game runs on, for text that names it
/// (decision 643): the language menu's "Same as iPhone" and the sound
/// footer's silent mode read "iPad" on an iPad. The app reads it from
/// `UIDevice` and `ProcessInfo`; GamePresentation only words it. Decision
/// 656: a Mac running the iPad app is a Mac, which has no silent mode
/// and no app switcher.
public enum DeviceFamily: CaseIterable, Hashable, Sendable {
    case iPhone
    case iPad
    case mac

    /// The device's name as Apple writes it, the same in both languages.
    public var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }

    /// The settings' footer under the sounds: what each volume is for and,
    /// on a device that has one, that its silent mode silences the game.
    public func soundNote(in language: DisplayLanguage) -> String {
        switch self {
        case .iPhone, .iPad:
            language.text(
                "Station chimes ring when a train arrives. Other effects: building, changing tools, income and warnings. In silent mode the game makes no sound.",
                "車站鈴聲在列車到站時響。其他音效：建造、換工具、收入與警告。\(name) 在靜音模式時，遊戲不會發出聲音。"
            )
        case .mac:
            language.text(
                "Station chimes ring when a train arrives. Other effects: building, changing tools, income and warnings.",
                "車站鈴聲在列車到站時響。其他音效：建造、換工具、收入與警告。"
            )
        }
    }

    /// How the player closes the game to open it again.
    public func reopenNote(in language: DisplayLanguage) -> String {
        switch self {
        case .iPhone, .iPad:
            language.text("Close it from the app switcher and open it again.", "請從多工畫面關掉遊戲，再重新開啟。")
        case .mac:
            language.text("Quit it and open it again.", "請結束遊戲，再重新開啟。")
        }
    }
}

/// How much room the game's window has, which the layout follows rather
/// than the device (decision 656, the L15 review's L15-6): an iPad's
/// window in Split View, Slide Over or a small Stage Manager window is as
/// narrow as an iPhone's, and is laid out as one.
public enum WindowLayout: CaseIterable, Hashable, Sendable {
    /// An iPhone, or a window as narrow as one (a compact width).
    case narrow
    /// An iPad's or a Mac's window of regular width.
    case wide

    /// The layout of a window on `device`, `compactWidth` when its
    /// horizontal size class is compact. An iPhone stays narrow on its
    /// side too, where the larger ones are of regular width.
    public init(device: DeviceFamily, compactWidth: Bool) {
        self = device != .iPhone && !compactWidth ? .wide : .narrow
    }

    /// Whether a lesson's track step moves the map to show both towns
    /// (``GameSession/tutorialFraming``, decision 643, the iPad
    /// playtest's A1): in a wide window, where the building panel and the
    /// toolbar hid one. Not in a narrow one (an iPhone on its side, an
    /// iPad's window in Split View): the map left clear there is so short
    /// or so thin that both towns fit only zoomed out to about 8–9 km
    /// across 400 points, where the first stretch tapped is too long to
    /// afford; there the player zooms out at the step before. Even in a
    /// wide window, ``PlanCamera/lessonFraming(_:clearOf:)`` leaves the
    /// camera where framing would zoom out that far.
    public var framesTheLessonsTowns: Bool {
        self == .wide
    }
}

/// How tall a card the game raises over the map can be (decision 643,
/// the iPad playtest's A2): in a narrow window it opens at half the
/// screen, the map still in sight, and is pulled up for the rest; in a
/// wide one, where the card floats in the middle, half the screen was a
/// short card at the bottom of a tall one, its form cut after a few rows
/// and a wide empty band under it, so it opens at its full height, as
/// Settings and Help do. Decision 656: by the window, not the device, so
/// an iPad's narrow window keeps the map in sight.
public enum SheetHeight: CaseIterable, Hashable, Sendable {
    case half
    case full

    /// The heights a card may take in a window laid out as `layout`, the
    /// first the one it opens at.
    public static func offered(in layout: WindowLayout) -> [SheetHeight] {
        switch layout {
        case .narrow: [.half, .full]
        case .wide: [.full]
        }
    }
}

/// The lesson's track step's framing of both towns (decision 643's A1),
/// moved at most once a step (decision 656, the L15 review's L15-8.3):
/// the step's region is framed the first time the insets it is clear of
/// hide part of it, including when the building panel is measured a
/// frame after the step appeared, but not once the step has settled, so
/// the player's own pans and zooms are left as they are.
public struct LessonFramingLatch: Hashable, Sendable {
    /// The step's region the latch watches.
    private var region: WorldRegion?
    /// Whether the region was framed, or found clear once the step had
    /// settled.
    private var done = false

    public init() {}

    /// The camera to move to, or `nil` to leave it: `region` (the
    /// session's ``GameSession/tutorialFraming``) seen from `camera`
    /// clear of `insets` in a window laid out as `layout`. `settling`
    /// while the step has only just appeared, when a region found clear
    /// is looked at again as the insets are measured.
    public mutating func camera(
        for region: WorldRegion?, from camera: PlanCamera, clearOf insets: ScreenInsets, layout: WindowLayout, settling: Bool
    ) -> PlanCamera? {
        guard let region else {
            self.region = nil
            done = false
            return nil
        }
        if region != self.region {
            self.region = region
            done = false
        }
        guard !done, layout.framesTheLessonsTowns else { return nil }
        if camera.framing(region, clearOf: insets) != nil {
            // Hidden: framed now, or left where framing would zoom out too
            // far; either way once.
            done = true
            return camera.lessonFraming(region, clearOf: insets)
        }
        if !settling { done = true }
        return nil
    }
}
