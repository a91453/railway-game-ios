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
        Line(english: "In the 3D map, each track's rails are as far apart as its gauge: standard gauge is wider, 762 mm narrower.", chinese: "3D 地圖裡，每段軌道的鋼軌照它的軌距畫：標準軌比較寬，762 mm 比較窄。"),
        Line(english: "Hong Kong: the transit tool's ferry mode lays the two harbour crossings, Central and Wan Chai to Tsim Sha Tsui.", chinese: "香港：接駁工具的渡輪模式可以照真實航線開中環、灣仔到尖沙咀的兩條港內渡輪。"),
    ]

    public static let nextFixes: [Line] = [
        Line(english: "The Danhai, Ankeng and Kaohsiung light rail trains are drawn at their real length, no longer stretched.", chinese: "淡海、安坑、高雄輕軌的列車照真車長度畫，不再被拉長。"),
    ]
}
