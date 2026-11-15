# ISLAND-REBUILD（決策 761）交接

- 派工：遊戲規劃；工作串「讓玩家把車站改成島式月台」；雲端 thread session，branch `claude/project-thread-03dm1f`。
- 決策 761；存檔版本、golden、GameCore 不動。
- 做了：車站面板月台區「改成島式月台」：雙線兩岸的站一股外移到 11 m、渡線拆掉重鋪、舊段拆掉、路線指定月台跟著換、擋路的車回路線起點（`Sources/GamePresentation/StationIslandRebuild.swift`，測試 `StationIslandRebuildTests`）。
- 舊存檔列出真實是島式的站、一鍵全部改建：決策 770 做了（`StationIslandRebuildAll.swift`、`IslandRebuildListCard`，雲端 thread session「舊存檔一鍵改建真實島式站」，`claude/project-thread-3w9z48`）。
- 還留下（決策 770「沒有做的」）：香港站沒有型式資料不會列出；混合站只改成兩股一島；一次復原全部。
- UNVERIFIED（決策 770）：卡片的自動跳出、勾選與「所有真實島式站…」按鈕沒在模擬器或手機看過；只有 Linux 測試與 CI 的 Xcode 建置。
- UNVERIFIED：模擬器與手機沒看過面板上的按鈕與改完的 3D 畫面；只有 Linux 測試。
