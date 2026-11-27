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
    /// SHINKANSEN-SALE (decision 975): the Kyushu Shinkansen bought alone
    /// (`testFukuokaShinkansen`), its eight trains turning round at
    /// Hakata in eight minutes on two tracks: no run late under either
    /// rules (with twelve minutes on one track, 24 and 22), its longest
    /// peak gap at Kumamoto 16.7 minutes against 15.0.
    static let fukuokaAllBought: [String: TimetableCheckup.Budget] = [
        "fukuoka fksubway:K+fksubway:H+fksubway:N simple": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 4),
        "fukuoka fksubway:K+fksubway:H+fksubway:N realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 4),
        // Decision 1030: with Kumamoto to Shin-Minamata, sold with it
        // (2026-11-27: its own 42 runs all 0 under both rules; the 2
        // minutes are Hakata–Kumamoto's, as before).
        "fukuoka kyushushinkansen:KS+KS2 simple": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 2),
        "fukuoka kyushushinkansen:KS+KS2 realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 2),
        // Decision 998: the Nishi-Kyushu Shinkansen bought alone from Nagasaki (2026-11-26: all 0).
        "fukuoka kyushushinkansen:NK simple": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
        "fukuoka kyushushinkansen:NK realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
        // Decision 1028: the Relay Kamome bought alone (2026-11-27: all 0).
        "fukuoka jrkyushu:RK simple": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
        "fukuoka jrkyushu:RK realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
        // Decision 1029: the Sanyo Shinkansen bought alone, on sale under
        // the realistic rules only (2026-11-27: all 0, the worst run 3.7
        // minutes late).
        "fukuoka sanyoshinkansen:SY realistic": .init(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0),
    ]
}
