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
    /// Decision 1008 (#2727, Hong Kong's people and jobs from the 2021
    /// census) moved the riders at every station and so the dwell times;
    /// measured on `main` `f1da01c` (run 45805083341), late / late out of
    /// a depot / peak gap:
    /// - EAL_LMC simple: 40 → 36 late (better).
    /// - EAL_LMC realistic: 9 → 15 late, peak gap +3 → +7 min.
    /// - SIL simple: 70 → 80 late, 0 → 1 late out of a depot, peak gap
    ///   +8 → +6 min (Admiralty 18:29, 11.0 min against 5.8).
    /// - SIL realistic: 88 → 68 late, peak gap +7 → +6 min (better).
    /// - TCL simple, alone and with AEL and DRL: 62 → 67 late, 6 → 7 late
    ///   out of a depot (the +19 min at Hong Kong 07:56 is older).
    /// - TCL realistic, alone and with AEL and DRL: 17 → 11 late, peak gap
    ///   +13 → +6 and +5 min (better).
    static let hongKongFull: [String: TimetableCheckup.Budget] = [
        "hk EAL_LMC simple": .init(notSent: 0, late: 36, lateOutOfDepot: 0, peakGapMinutes: 7),
        "hk EAL_LMC realistic": .init(notSent: 0, late: 15, lateOutOfDepot: 0, peakGapMinutes: 7),
        "hk SIL simple": .init(notSent: 0, late: 80, lateOutOfDepot: 1, peakGapMinutes: 6),
        "hk SIL realistic": .init(notSent: 0, late: 68, lateOutOfDepot: 0, peakGapMinutes: 6),
        "hk TCL simple": .init(notSent: 1, late: 67, lateOutOfDepot: 7, peakGapMinutes: 19),
        "hk TCL realistic": .init(notSent: 0, late: 11, lateOutOfDepot: 1, peakGapMinutes: 6),
        "hk TCL+AEL+DRL simple": .init(notSent: 1, late: 67, lateOutOfDepot: 7, peakGapMinutes: 19),
        "hk TCL+AEL+DRL realistic": .init(notSent: 0, late: 11, lateOutOfDepot: 1, peakGapMinutes: 5),
    ]
}
