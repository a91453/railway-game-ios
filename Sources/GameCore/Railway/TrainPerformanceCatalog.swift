// The built-in catalog of performances (decision 236): each way of running
// the menus offer by name, as one row of data, where it was a case of an
// enum and a `switch` for each of its numbers before. A row is known by its
// code. Saves store a train's or line's performance as its numbers, never
// as a code, so the codes are free to name and the save format does not
// depend on this table; a row is still never removed, since a menu names it.
// Adding a performance (a real model's, say) is adding a row and its name
// in GamePresentation.
//
// The numbers are ``TrainPerformance``'s presets, which say where each comes
// from (`RunningCurve.swift`).

/// One performance the menus offer by name (decision 236).
public struct TrainPerformanceSpec: Hashable, Sendable {
    /// The row's code.
    public let code: String
    public let performance: TrainPerformance
}

/// The built-in performances (decision 236).
public enum TrainPerformanceCatalog {
    /// Every performance, in the order the menus list them. Which one a
    /// performance reads as is the first here that accelerates, brakes and
    /// coasts as it does, so the order matters: the diesel express comes
    /// before the diesel railcar, which runs as it does.
    public static let builtIn: [TrainPerformanceSpec] = [
        .init(code: "standard", performance: .standard),
        .init(code: "metro", performance: .metro),
        .init(code: "local", performance: .local),
        .init(code: "ordinary", performance: .ordinary),
        .init(code: "semiExpress", performance: .semiExpress),
        .init(code: "express", performance: .express),
        .init(code: "emu3000", performance: .emu3000),
        .init(code: "pushPull", performance: .pushPull),
        .init(code: "taroko", performance: .tiltingTaroko),
        .init(code: "puyuma", performance: .tiltingPuyuma),
        .init(code: "dieselExpress", performance: .dieselExpress),
        .init(code: "dieselRailcar", performance: .dieselRailcar),
        .init(code: "forestRailway", performance: .forestRailway),
        .init(code: "highSpeed", performance: .highSpeed),
        .init(code: "steam", performance: .steam),
    ]

    /// Each code's row. Building it traps on a code listed twice.
    static let rowByCode: [String: Int] = Dictionary(uniqueKeysWithValues: builtIn.enumerated().map { ($1.code, $0) })

    /// The row with `code`, or `nil` for a code no row has.
    public static func spec(_ code: String) -> TrainPerformanceSpec? {
        rowByCode[code].map { builtIn[$0] }
    }
}
