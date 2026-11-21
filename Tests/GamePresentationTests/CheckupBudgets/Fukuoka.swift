extension TimetableCheckupBudgets {
    /// FUKUOKA-OPEN: Fukuoka's three lines, bought together, as measured
    /// when its map opened (2026-11-19, Release): every run sent, but the
    /// Nanakuma Line's turns at its ends at 3 min 15 s run up to 15
    /// minutes late (126 or 127 runs), and the Kuko Line's peak gap at
    /// Fukuoka Airport is 10 minutes against 3.3 (60 runs late under a new
    /// game's rules, 3 under the realistic ones); the Hakozaki Line has
    /// none. FUKUOKA-LATE lowers them.
    /// Decision 890 (FUKUOKA-LATE): the home signal at the Kuko Line's
    /// ends, its trains late 0 (were 60 and 3) and its peak gap 7.0 and
    /// 6.0 minutes; the Nanakuma Line's are its trains too few for its
    /// peak (two more run it on time, but its ends have no tracks for
    /// them: FUKUOKA-NANAKUMA-FLEET).
    /// Decision 881, later (EAL-LMC-PEAK-GAP): under a new game's rules
    /// the Kuko Line's longest peak gap is 7.4 minutes, 24 s more (+5
    /// for +4), its worst run 2.0 minutes late for 3.7, the runs late as
    /// they were: fewer of the day's moves into the other berth of an end.
    /// Decision 898 (FUKUOKA-NANAKUMA-FLEET): the Nanakuma Line bought
    /// with its depot past Hashimoto and 23 trains, its day laid out from
    /// that end: no run late under either rules (were 127 and 126), its
    /// worst 3.5 minutes, its longest peak gap 6.5 minutes against 3.2;
    /// the Kuko Line's 7.0 against 3.3 (+3.7) and 6.0 (+2.7).
    static let fukuokaAllBought: [String: TimetableCheckup.Budget] = [
        "fukuoka fksubway:K+fksubway:H+fksubway:N simple": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 4),
        "fukuoka fksubway:K+fksubway:H+fksubway:N realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 4),
    ]
}
