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
        Line(english: "The garage has the Kyushu Shinkansen's N700 series: pale blue with a navy line, eight cars.", chinese: "車庫多了九州新幹線 N700 系：白藍車身、窗下深藍細線，八節。"),
        Line(english: "The Train Pack's white high-speed train is now the N700S of the game's earlier version: white with two blue lines, twelve cars.", chinese: "列車包的白色高速列車換成舊版遊戲的 N700S：白色車身、窗下兩道藍線，十二節。"),
        Line(english: "Choose a paint for a line's trains on the line's page; the high-speed 700T now wears its real orange band, with the earlier teal as a choice", chinese: "路線頁可以替這條線的列車選塗裝；高鐵 700T 改成真車的橘色帶，原本的青綠帶可以選回來"),
        Line(english: "Hong Kong: the transit tool's ferry mode lays the two harbour crossings, Central and Wan Chai to Tsim Sha Tsui.", chinese: "香港：接駁工具的渡輪模式可以照真實航線開中環、灣仔到尖沙咀的兩條港內渡輪。"),
    ]

    public static let nextFixes: [Line] = [
    ]
}
