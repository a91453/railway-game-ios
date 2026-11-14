# RELEASE-131：0.6.0 (131) 發版

2026-11-14，雲端 thread session「發這一版 TestFlight」。

## 發了什麼

- 0.6.0 (131)，commit `4cff950`，TestFlight run [43598932732](https://github.com/a91453/railway-game-ios/actions/runs/43598932732)，作者自己按（`archive_signing=adhoc`、`testing_scope=external`）。上傳、App Store Connect 處理、What to Test 都成功。
- 範圍：`19aa342`（130）之後的 31 個合併，加 #2199、#2204、#2207（東鐵綫落馬洲支線）。說明在 #2206（`.github/testflight-whats-new.md` 與 `WhatsNew.swift` 的 `2026-11-14-131`，只寫這一版）。
- 完整 `ci.yml`（手動，run [43595170307](https://github.com/a91453/railway-game-ios/actions/runs/43595170307)）在 `4cff950` 全綠。

## 還沒結果、交給「縮短 CI 和 full lane 時間」那串追

- full lane：`ios-full-lane.yml` 13:18 UTC 起的 `ios-build.yml` run [43599067177](https://github.com/a91453/railway-game-ios/actions/runs/43599067177)（`4cff950`），寫這份時還在跑，約 16:05 UTC 出結果。130 的 full lane（`19aa342`，run 43539871635）是紅的。
- 紅了就修，修好的放進下一版（作者說明早再發一版，含 3D 記憶體修正）。最可能壞的是路線詳情、車站詳情改成全螢幕（#2200、#2203）後還假設「面板開著也點得到地圖」的 UI 測試，以及 #2204 的路線清單工具列改成圖示。
- Mac 上另跑的同一批 UI 測試（Remote Control，worktree `/tmp/rg-131`）在收尾時停掉了，沒有拿到結果；以 CI 的 full lane 為準。

## 沒在裝置上驗證

路線詳情、車站詳情全螢幕的樣子；設站確認框讓開路線；香港街上的車與機場 3D；示範路線的島式月台；3D 道路整平；存檔、回主畫面變快的程度。
