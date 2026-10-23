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
        // Decision 237: real models. TEMU1000 and TEMU2000 are the Taroko and
        // Puyuma rows above, and the 700T the high-speed row (`PERF_HSR`).
        .init(code: "metroC381", performance: .metroC381),
        .init(code: "emu800", performance: .emu800),
        // Decision 252: more of the Taiwan Railway's models.
        .init(code: "emu100", performance: .emu100),
        .init(code: "e200ChuKuang", performance: .e200ChuKuang),
        .init(code: "e500ChuKuang", performance: .e500ChuKuang),
        .init(code: "r100ChuKuang", performance: .r100ChuKuang),
        .init(code: "r200ChuKuang", performance: .r200ChuKuang),
        .init(code: "haiFeng", performance: .haiFeng),
        // Decision 286, later.
        .init(code: "mingRi", performance: .mingRi),
        // Decision 286, later (third).
        .init(code: "formosaStar", performance: .formosaStar),
        // Decision 286, later (fourth).
        .init(code: "midsummerFormosa", performance: .midsummerFormosa),
    ]

    /// Each code's row. Building it traps on a code listed twice.
    static let rowByCode: [String: Int] = Dictionary(uniqueKeysWithValues: builtIn.enumerated().map { ($1.code, $0) })

    /// The row with `code`, or `nil` for a code no row has.
    public static func spec(_ code: String) -> TrainPerformanceSpec? {
        rowByCode[code].map { builtIn[$0] }
    }
}
