# HK-SHARED-TRACK：機場快綫、東涌綫、迪士尼綫同時收購（決策 752）

2026-11-14，雲端 thread session，分支 `claude/project-thread-lelp9h`。

- 做完：三條任何順序都能收購（`HongKongMapTests.testTheThreeLinesOnOneTrackAreBoughtInEveryOrder`，Linux VERIFIED）。原因與改法在 `docs/decisions/752.md`。
- 沒做：3D 地圖上三條並排的截圖（機場快綫離真實畫線 25 m、迪士尼綫在欣澳 45 m），實機收購的等待時間。都是 UNVERIFIED。
- 注意：要在香港再加一條和別條共用畫線的綫，加進 `RealBranchLine.overseasLanes`（依據的是對方的畫線，不是已鋪的軌道），並把它加進同一個六種順序的測試。
