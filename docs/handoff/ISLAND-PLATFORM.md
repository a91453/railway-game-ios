# ISLAND-PLATFORM（決策 741）交接

- 做了：示範路線（高鐵、宜蘭線）真實是島式的站，月台兩側軌道鋪成隔 11 m，3D 畫得出中間的島式月台（`HighSpeedDemo.swift`）。
- 沒做／下一張：玩家既有車站「改成島式」（五方 3.30：玩家 4、開發 3、美術 4、鐵道迷 4、音樂 1）。做法：沿用 `StationLayout` 雙線一島把旁邊那股外移、`removeTrackEdge` 拆舊段，加收班後才改（如 `RealLineRebuild`）、路線指定股道跟著換、收費；舊存檔第一次開時跳卡列出真實是島式的站（勾選框＋「全部改建」一鍵，作者 11-14「那如果太多 要出現一鍵更改選項嗎」），先顯示總價；軌道上有車的站排到收班後才改。仍由玩家按，不自動。不做讀檔自動轉（要升存檔、會轉錯岸式站）。
- 收購線（`RealLineAcquisition`）的站也是 5 m，同一張改建單可一起處理。
- 沒在裝置上驗證的：見 PR。
- 待辦（bug，GameCore，要完整 CI）：決策 518 停待避線的分支 `freePlatformPath(..., below: max(own, 1))`（`RunSpacing.swift` 約 436 行）把「停著但會準時空出來」（`platformWaits` 1）的待避線排除，要停站的車就選正線；而 `freePlatformOnTheWay` 只在目標月台有車停著或有車迎面出來時重選，待避線空出時不會改回。修了才能讓高鐵南港端成對外移（`HighSpeedDemo.spec` 的 `endIslands.north` 改回 3；重現：`HighSpeedDemoDayTests.testCallingSetsStandOnTheLoops`，12:50 THSR 3 at Taoyuan）。詳見決策 741「暫不改的兩站」。
- 待辦：高鐵台中改島式（`islandPlatforms` 加 6）前，先讓台中外觀研究挖過外移 6 m 的待避線後仍在三角形上限內（近景 8000、遠景 3000；現在 8765／3083），或重切站體。不放寬上限。
