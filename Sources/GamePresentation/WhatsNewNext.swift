// Decision 415's amendment (2026-11-25): the news of the build not yet
// released, one `Line(english:chinese:)` on one line each. A pull request
// with news for players adds its line at the end of `nextItems` (what the
// player can now do) or `nextFixes` (what works again) and changes nothing
// else in this file: `.gitattributes` merges it with `merge=union`, so two
// branches that each add a line keep both instead of conflicting on the
// newest entry of `WhatsNew.entries`.
//
// Before each TestFlight release the game-planning session moves these
// lines into a new entry at the top of `WhatsNew.entries` (rewording them
// where needed) and empties both lists. `WhatsNewTests` checks the lines'
// form and that none is left here once it is in a released entry.
extension WhatsNew {
    public static let nextItems: [Line] = [
        Line(english: "The garage has the Kyushu Shinkansen's N700 series: white-blue with a navy and gold line, eight cars.", chinese: "車庫多了九州新幹線 N700 系：白藍車身、窗下深藍鑲金的線，八節。"),
        Line(english: "Hong Kong: the transit tool's ferry mode lays the two harbour crossings, Central and Wan Chai to Tsim Sha Tsui.", chinese: "香港：接駁工具的渡輪模式可以照真實航線開中環、灣仔到尖沙咀的兩條港內渡輪。"),
    ]

    public static let nextFixes: [Line] = [
    ]
}
