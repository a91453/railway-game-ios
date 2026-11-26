/// Decision 999: the places a game on Japan's map can begin round, one a
/// line, in the order the new-game list shows them (`start`, from 0, the
/// pack's start extents). `.gitattributes` merges this file with
/// `merge=union`, so two branches that each add a prefecture keep both
/// lines, as the trains' own-glass list does: every line ends with a comma,
/// and nothing else goes between the brackets.
/// `OverseasStartLandJapanTests` checks the numbers run from 0 with no gap
/// or twin.
enum OverseasStartLandJapanList {
    static let places: [(start: Int, chinese: String, english: String)] = [
        (0, "福岡", "Fukuoka"), // Decision 999.
        (1, "佐賀", "Saga"), // Decision 999.
        (2, "熊本", "Kumamoto"), // Decision 999.
        (3, "長崎", "Nagasaki"), // Decision 997.
    ]
}
