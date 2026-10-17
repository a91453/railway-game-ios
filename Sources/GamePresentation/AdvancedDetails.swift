import GameCore

/// The lines panel's "Advanced" switch (decision 196, later; TestFlight
/// 54.1 #6: a phone is too crowded, and players do not want to manage
/// platforms, grades and dispatch). Folded, the panel leaves out the
/// service day, stopping patterns, the tracks each leg takes, target
/// headways and the network's switches; the rules behind them run as they
/// were, and what a game already set there is said in one line, so an old
/// save's settings stay visible. Stops, assigning trains and the line's
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
        var parts: [String] = []
        if !line.patterns.isEmpty {
            parts.append(language.text(
                line.patterns.count == 1 ? "1 stopping pattern" : "\(line.patterns.count) stopping patterns",
                "\(line.patterns.count) 種停靠模式"
            ))
        }
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

    /// The network's folded switches as they are now, in one line: traffic
    /// control, how passengers route and the service day.
    public static func networkSummary(of world: GameWorld, in language: DisplayLanguage) -> String {
        [
            language.text(
                "Traffic control \(world.isTrafficControlEnabled ? "on" : "off")",
                "行車控制\(world.isTrafficControlEnabled ? "開" : "關")"
            ),
            world.passengerRoutingMode == .network
                ? language.text("passengers change lines", "旅客可轉乘")
                : language.text("passengers ride one line", "旅客只搭一條線"),
            world.serviceDay == .standard
                ? language.text("standard service day", "標準時段")
                : language.text("own service day", "自訂時段"),
        ].joined(separator: language.text(" · ", "・"))
    }
}
