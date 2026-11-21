/// Decision 910: the timetable checkup's budgets (decision 844), one file a
/// map in this folder, so that the sessions fixing a bug on one map change
/// that map's file alone. A world's budget is `main`'s numbers for it: runs
/// not sent, late, late out of a depot, and the peak gap's minutes over the
/// timetable's. A world not listed must have none of any. The sessions
/// fixing a bug lower its world's numbers.
enum TimetableCheckupBudgets {
    /// Every line's whole second day, alone (``TimetableCheckupFullTests``).
    static let full = merged([taiwanFull, hongKongFull])
    /// The lines that share a station, bought together
    /// (``TimetableCheckupAllBoughtTests``).
    static let allBought = merged([taiwanAllBought, fukuokaAllBought])

    /// The maps' tables as one; a world in two of them is a mistake.
    private static func merged(_ tables: [[String: TimetableCheckup.Budget]]) -> [String: TimetableCheckup.Budget] {
        tables.reduce(into: [:]) { all, table in
            all.merge(table) { _, _ in preconditionFailure("a world has a budget in two maps' files") }
        }
    }
}
