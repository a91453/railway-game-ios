# TAIWAN-CENSUS-GRID（決策 1002）

## 進度

- 做到哪：工作串壓縮第 2 次後停手（2026-11-26）。資料、工具、遊戲規則、測試期望、決策 1002 都在這張 PR；`.taiwan` 已加進 `CitySkyline.censusLooks`（決策 1006）。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 與改到的測試類別（見 PR）；其餘交 CI。
- 下一步第一個指令：看 PR 的 CI；紅了照失敗的類別修期望或規則，綠了就合。

## 派工

- 派工：協調者第 5 任，「換成台灣官方住與上班人口」；分支 `claude/project-thread-d3tv0o`。
- 存檔版本、golden schema、GameCore：不動。決策 1002。

## 還留下什麼

1. **CI**：這張 PR 的 CI 綠了就合（CLAUDE.md「PR 綠了就合」）。紅了多半是讀台灣人口的測試期望值（總數、台北人數），照新資料改並寫理由，不改規則。
2. **經濟平衡**：上班的人從約 1,200 萬降到約 966 萬（普查不算公務、軍、農），用 economy-balance skill 的報告量台灣開局的收入與旅次，給 HEALTHY／CONCERNS。
3. **網站資料來源**：a91453/railway-reference-private#162（SEGIS 快照＋`credits.html` 台灣人口一句＋字型）由作者合併；工作串不合那個 repo。
4. **OSM 地點改讀 pbf**：這次用 Overpass 數到 7.5″（數好的 `places75.json` 存在專案共用資料夾 `census-grid/`，可直接給 `build` 用）；要重建時照 CLAUDE.md 讀 osmtoday `asia/taiwan.pbf`，README 第 3 步目前只有 Overpass 的指令，改讀 pbf 要補一個讀法。
5. **香港、芬蘭**：同一做法，各自的串在 `censusLooks` 加自己的值；衝突時三個值都留。
