# WINTER-LIVERY-2 交接（2026-11-16）

session_01JMHz9bvL9kMdQXnJy9h3VW，分支 `claude/winter-livery-2`，draft PR #2310，決策 806。存檔、golden、GameCore、fixtures、模型包的模型與雜湊：都不動。

## 進度（中斷後只讀這一節與 `git status`、`git log -3`）

- 做到哪：選定的「A2＋頭車緞帶」實作完、測試寫完、文件寫完，已推上分支。這個 session 壓縮第 2 次，照規則停在這裡，不再接工作。
- 已驗證：雲端 Linux 的建置（含測試、警告當錯誤）與 `Map3DChristmasLiveryTests`、`Map3DGlowTests`、`Map3DWinterDecorTests`。App 的兩處改動、Metal、實機、效能、光暈與慢閃 UNVERIFIED。
- 下一步的第一個指令：看 #2310 這個 commit 的 `iOS App Build` 與 `Swift CI (gate)`（`pull_request_read` 的 check runs）；紅就照錯誤訊息修，綠就照下面「接手的人」做。

## 做完的

- `Sources/GamePresentation/Map3DChristmasLivery.swift` 重寫：`Wear`、`wear(of:)`、`dressed(...)`（雪頂＋裝飾）、`halos(...)`、`twinkle(...)`。決策 795 的部位表與 `recoloured` 拿掉。
- `Map3DModels.swift`（`pack.christmas` 改成 `[Int: Wear]`）、`Map3DTrains.swift`（聖誕車保留線色，方塊車車頂換雪色）、`Map3DGlow.swift`（`trainSpots(of:pack:festive:)`）、`Map3DWinterDecor.swift`（拿掉沒人用的 `christmasLivery`）。
- App：`Map3DPreviewScreen.swift` 的 `christmas(_:wear:model:)`、`Map3DMetalView.swift` 的頂點數與 `festive:`。
- 測試：`Tests/GamePresentationTests/Map3DChristmasLiveryTests.swift` 改寫。
- 工具：`export-winter-options.swift` 的 `mix` 用遊戲的程式畫；`export-winter-livery.swift` 改印每款車的數字；`export-winter-preview.swift`（決策 804 的 A／B 對照，靠已拿掉的部位表）刪了。
- 文件：決策 806 §7、`docs/art/winter-livery-2-2026-11-16/README.md` 第四輪與兩張圖。

## 接手的人

1. 等 #2310 的 CI。`ios-build.yml` 是第一次編那兩個 App 檔；編不過多半是 `Map3DMetalView.swift` 畫車那個迴圈（搜 `Decision 806`）或 `Map3DPreviewScreen.swift` 的 `christmas(_:wear:model:)`。
2. model-look 要另一個 session 或作者判總覽圖：圖在 `docs/art/winter-livery-2-2026-11-16/chosen-game-*.jpg`。這個 session 只自己看過。阿里山機車的花圈在拍圖之後才修（不超出車頭），沒有重拍：`tools/model-look/export-winter.sh options <資料夾>` 再 `node tools/model-look/shoot-livery.mjs --dir <資料夾> --out <圖的資料夾>`。
3. 綠了、圖有人判過之後把 PR 轉 ready。不要合併、不要開 auto-merge。
4. 合併或放棄時在 #2118 留言，釋出決策 806。

## UNVERIFIED

- App 的兩處改動能不能編、Metal 畫面、實機、效能、夜裡的光暈與慢閃；圖全部是離線 WebGL。
- 只看過一張真實照片（Commons 限流）。
- 第一次畫到某款聖誕車時在主執行緒做那一份緩衝（一節車幾千個頂點加表面查詢）；有沒有可感的卡頓沒量過。
