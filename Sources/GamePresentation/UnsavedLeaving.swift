/// Decision 497 (P2-6): the question when Back to Start cannot write the
/// autosave (a full phone, a folder that cannot be written). Before it the
/// game stayed and every tap failed the same way, so the only way out was
/// to quit the app; now the player may leave without saving, told what is
/// lost, or keep playing.
public struct UnsavedLeaving: Equatable, Sendable {
    /// Why the save failed, as the game's status line says it.
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public static func title(in language: DisplayLanguage) -> String {
        language.text("Can't Save the Game", "無法存檔")
    }

    public func message(in language: DisplayLanguage) -> String {
        language.text(
            "\(reason) Leave anyway? What you did since the last save will be lost.",
            "\(reason)仍要離開嗎？上次存檔之後的進度會不見。"
        )
    }

    public static func leaveButton(in language: DisplayLanguage) -> String {
        language.text("Leave Without Saving", "不存檔離開")
    }

    public static func stayButton(in language: DisplayLanguage) -> String {
        language.text("Keep Playing", "繼續玩")
    }
}
