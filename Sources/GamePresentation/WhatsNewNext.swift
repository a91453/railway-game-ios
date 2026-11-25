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
        Line(english: "The Kyushu Shinkansen from Hakata to Kumamoto is on sale on the Japan map.", chinese: "日本地圖可以買九州新幹線（博多到熊本）。"),
        Line(english: "Hong Kong: the transit tool's ferry mode lays the two harbour crossings, Central and Wan Chai to Tsim Sha Tsui.", chinese: "香港：接駁工具的渡輪模式可以照真實航線開中環、灣仔到尖沙咀的兩條港內渡輪。"),
        Line(english: "A new train to buy: the Keikyu New 1000, each car its real 18 m.", chinese: "新車款：京急新1000形，每節是真車的 18 公尺。"),
    ]

    public static let nextFixes: [Line] = [
    ]
}
