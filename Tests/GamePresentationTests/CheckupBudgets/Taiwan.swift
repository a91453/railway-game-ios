extension TimetableCheckupBudgets {
    /// Taiwan's lines alone (decision 844; `main` `2cd9c94`, 2026-11-18).
    /// Decision 871 (the Taoyuan Airport MRT under the Tamsui River and
    /// at Huanbei, its viaduct stations at 16 m) moved its realistic
    /// day from 2 not sent, 26 late, 11 late out of a depot and a peak
    /// gap of +10 min to 1, 19, 7 and +13 (one gap of 27.7 min against
    /// 15 at Airport Terminal 1 at 18:01); under a new game's rules it
    /// is as it was.
    static let taiwanFull: [String: TimetableCheckup.Budget] = [
        "ntalrt:K simple": .init(notSent: 0, late: 2, lateOutOfDepot: 0, peakGapMinutes: 0),
        "ntalrt:K realistic": .init(notSent: 0, late: 1, lateOutOfDepot: 0, peakGapMinutes: 0),
        "sanying:LB simple": .init(notSent: 0, late: 7, lateOutOfDepot: 0, peakGapMinutes: 5),
        "trtc:BR simple": .init(notSent: 6, late: 179, lateOutOfDepot: 30, peakGapMinutes: 10),
        "trtc:BR realistic": .init(notSent: 0, late: 149, lateOutOfDepot: 0, peakGapMinutes: 7),
        "tymc:A simple": .init(notSent: 12, late: 97, lateOutOfDepot: 10, peakGapMinutes: 31),
        "tymc:A realistic": .init(notSent: 1, late: 9, lateOutOfDepot: 4, peakGapMinutes: 5),
    ]

    /// Taiwan's lines that share a station, bought together (2026-11-18).
    /// The Liujia line's three late runs under the realistic rules are
    /// its own (`tra:LIUJIA realistic`, LIUJIA-LATE), the same with the
    /// Neiwan line bought; under a new game's rules it has none since
    /// decision 849 (measured again on `main` `5a1efcf`), as alone.
    /// Decision 885 (SHALUN-ONE-ISLAND): the Blue Coast Line's trains
    /// run from Hongshulin on the Green Mountain Line's track, and those
    /// toward Fisherman's Wharf share Binhai Shalun's south platform
    /// track with the Green Mountain Line's trains toward Hongshulin
    /// (the game has no level crossing), so some wait there: none not
    /// sent, the latest 19 minutes behind (measured 2026-11-19).
    /// GRADE-CROSSING-SHALUN (decision 885, later): those toward the
    /// wharf now stop on the north face and cross the Green Mountain
    /// Line's track west of the station on the flat, and wait there no
    /// more. Of the 11 runs still late under a new game's rules, 10 leave
    /// Hongshulin late, both lines' (HONGSHULIN-TURN); 4 under the
    /// realistic rules; none late out of the depot (measured 2026-11-19).
    /// HONGSHULIN-TURN: the Green Mountain Line's Hongshulin is laid with
    /// 7 tracks, so the Blue Coast Line's three trains stand there at
    /// night as the real ones do, not one of them at the wharf: none
    /// leaves Hongshulin late. One run is left under a new game's rules,
    /// the Green Mountain Line's from Kanding at 17:38, 15 minutes late,
    /// and its evening peak gap at Hongshulin of 24.7 minutes against 18;
    /// none under the realistic rules (measured 2026-11-19).
    static let taiwanAllBought: [String: TimetableCheckup.Budget] = [
        "taiwan ntdlrt:V+ntdlrt:VB simple": .init(notSent: 0, late: 1, lateOutOfDepot: 0, peakGapMinutes: 7),
        "taiwan tra:LIUJIA+tra:NEIWAN realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
        "taiwan tra:NEIWAN+tra:LIUJIA realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
    ]
}
