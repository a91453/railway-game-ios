import GameCore

/// The lines panel's "Advanced" switch (decision 196, later; TestFlight
/// 54.1 #6: a phone is too crowded, and players do not want to manage
/// platforms, grades and dispatch). Folded, the panel leaves out the
/// service day, the tracks each leg takes and target headways (decision
/// 383: no longer the stopping patterns or the network's switches); the
/// rules behind them run as they were, and what a game already set there
/// is said in one line, so an old save's settings stay visible. Stops, assigning trains and the line's
/// money are never folded.
///
/// A choice of the device, not of the game: nothing here is saved.
public enum AdvancedDetails {
    /// Whether the details show: the player's own choice once made,
    /// otherwise shown only where the screen is roomy (an iPad), folded on
    /// a phone.
    ///
    /// Decision 266: only among the tools unlocked: in a lesson before the
    /// details are taught (`unlocked` false) they never show, and the
    /// switch with them.
    public static func isShown(stored: Bool?, roomy: Bool, unlocked: Bool = true) -> Bool {
        unlocked && (stored ?? roomy)
    }

    /// What `line` has set among the folded details, in one line, or `nil`
    /// when it has nothing but the defaults there.
    public static func lineSummary(_ line: ServiceLine, in language: DisplayLanguage) -> String? {
        // Decision 383: a stopping pattern is not folded any more, so it
        // is not said here.
        var parts: [String] = []
        let routed = line.routePreferences.count + line.patterns.reduce(0) { $0 + $1.routePreferences.count }
        if routed > 0 {
            parts.append(language.text(
                routed == 1 ? "1 leg on set tracks" : "\(routed) legs on set tracks",
                "\(routed) 段指定進路"
            ))
        }
        if line.targetHeadways != .none || line.patterns.contains(where: { $0.targetHeadways != .none }) {
            parts.append(language.text("target headways", "目標班距"))
        }
        guard !parts.isEmpty else { return nil }
        return language.text("Advanced: ", "進階：") + parts.joined(separator: language.text(", ", "、"))
    }

    /// The network's folded setting as it is now, in one line: the
    /// service day. Decision 383: traffic control and how passengers
    /// route have their own block at the top of the panel, never folded.
    public static func networkSummary(of world: GameWorld, in language: DisplayLanguage) -> String {
        world.serviceDay == .standard
            ? language.text("Standard service day", "標準時段")
            : language.text("Own service day", "自訂時段")
    }
}
