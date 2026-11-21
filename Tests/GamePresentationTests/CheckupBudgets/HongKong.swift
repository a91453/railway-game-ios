extension TimetableCheckupBudgets {
    /// Hong Kong's lines alone (decision 844; `main` `2cd9c94`, 2026-11-18).
    /// Decision 849 (the home signal) lowered Hong Kong's under a new
    /// game's rules: the South Island Line from 21 not sent, the East
    /// Rail Line from 15, the Tseung Kwan O Line from 92 late to none
    /// (and the Liujia Line's 3 late).
    /// The Tung Chung Line's went from 2 not sent, 81 late and 6 late out
    /// of a depot to 1, 64 and 7: one more late out of Siu Ho Wan, a run
    /// after midnight, which decision 850 (TCL-DEPOT-CLAIM) took back,
    /// with two of the late runs.
    /// Decision 849's later part (the home signal with block sections
    /// too) lowered Hong Kong's under the realistic rules: the South
    /// Island Line from 10 not sent, the East Rail Line from 4, the Tung
    /// Chung Line from 4 (alone) and 3 (with the Airport Express and the
    /// Disneyland Resort Line, 64 late on `main` `5a1efcf`), the Tseung
    /// Kwan O Line from 92 late to none (and the Liujia Line's 3 late).
    static let hongKongFull: [String: TimetableCheckup.Budget] = [
        "hk EAL_LMC simple": .init(notSent: 0, late: 40, lateOutOfDepot: 0, peakGapMinutes: 7),
        "hk EAL_LMC realistic": .init(notSent: 0, late: 9, lateOutOfDepot: 0, peakGapMinutes: 3),
        "hk SIL simple": .init(notSent: 0, late: 134, lateOutOfDepot: 1, peakGapMinutes: 7),
        "hk SIL realistic": .init(notSent: 0, late: 91, lateOutOfDepot: 1, peakGapMinutes: 4),
        "hk TCL simple": .init(notSent: 1, late: 62, lateOutOfDepot: 6, peakGapMinutes: 19),
        "hk TCL realistic": .init(notSent: 0, late: 19, lateOutOfDepot: 1, peakGapMinutes: 11),
        "hk TCL+AEL+DRL simple": .init(notSent: 1, late: 62, lateOutOfDepot: 6, peakGapMinutes: 19),
        "hk TCL+AEL+DRL realistic": .init(notSent: 0, late: 18, lateOutOfDepot: 1, peakGapMinutes: 11),
    ]
}
