# APP-STORE-FREE：首次上架（免費、不帶內購）

雲端工作串「準備免費上架版本」，分支 `claude/project-thread-hu0zjk`。決策 338（續三）。存檔版本、golden schema 不動。
寫於 2026-11-27 03:50（台灣時間），交給規劃4。

## 進度

- 做到：上架要進的 PR 都合了，開著的只剩內購 #2730（**上架版審過之前不合**）。上架版號 **0.6.0**（`project.yml` 的 `MARKETING_VERSION`，main 上就是 0.6.0，不要改）。
- 已驗證：TestFlight 152（run 45876417790，main `60a9c5f`，11-27 02:30–03:21）三段都成功，作者 iPhone 上三座城的地圖包都讀得到（`docs/handoff/MAP-PACK-COPY.md`）。
- 下一步：等 main 穩下來（下面「什麼時候按」），從 main 跑 `testflight.yml`，再到 App Store Connect 送審。作者 11-27 00:53：「不一定要明天上架」「週末再送也行」。

## 定了什麼

- 免費上架，不帶內購。列車包對所有玩家打開，正式版也是（#2728，決策 338 續三）。
- 版號維持 0.6.0（作者 11-26 23:00 在決策卡選「維持 0.6.0」）。0.7.0 的 #2762 已關。
- 上架後下一個 TestFlight 要升 **0.6.1**：0.6.0 審過之後，App Store Connect 不收同版號的新 build。
- 內購 #2730：上架版審過才合，合前要另一個 session 獨立審查。交接寫在那張 PR 裡。老玩家免費的規則看 build 號（iOS 的 `originalAppVersion` 是 `CFBundleVersion`），所以上架版的版號是多少都不影響。

## 合了哪些（11-26）

#2728 列車包全開、#2733→#2758 版號（0.7.0 又改回 0.6.0）、#2750 Mac runner、#2726 截圖工具、#2752 隱私清單、#2753、#2759 只改發版說明的 PR 不重建（決策 1017）、#2751 台中建物（決策 1015）、#2756 TestFlight 拆三段（決策 1016）、#2764 選車種卡住／日本型錄 N700／台灣高鐵畫法、#2765 台灣高鐵收購（決策 993，只在寫實規則）、#2766 轉轍器破圖、#2768 22 件地標，以及之後的拆檔 PR。

**注意**：協調者 11-27 00:45 說 #2767（N700ST）不進上架版，但它在 11-27 03:45 合進了 main（`86a3e53`）。從 main 發，上架版就會帶它。不想帶的話要先開 revert PR，否則照現況發。

## 什麼時候按

上架版的 commit 要同時滿足：

1. 那個 commit 的 `ci.yml` push run 綠。
2. 那個 commit 的**完整** `ci.yml`（每晚 01:37 那次，或手動跑一次）綠，`ios-full-lane.yml`（每晚 02:17，或手動）也綠。CLAUDE.md「Environments and validation」的發版條件。
3. 之後不再合 PR 進 main，直到 build 號出來。拆檔 PR 還在合，合一張就要重來第 1、2 步。

時間估算：完整 `ci.yml` 約 30 分，full lane 約 60–80 分，`testflight.yml` 約 50 分（152 是 51 分），App Store Connect 處理約 10–15 分，送審後審查約 1–2 天。所以按 `testflight.yml` 之後大約 1 小時能送審。

遊戲規劃要給作者一個可以按的時間時：看 main 最新 commit 的上面三項，綠了就給「現在到 X 點之間」，紅了先修。**session 不自己跑 `testflight.yml`**：只有作者在規劃串說「發」，而且第 2 項都綠，規劃串才可以幫按（CLAUDE.md）。

## 怎麼按 TestFlight（作者或規劃串）

GitHub Actions → TestFlight → Run workflow，branch `main`：

| 欄位 | 選 | 為什麼 |
| --- | --- | --- |
| archive_signing | `adhoc` | 預設，沒註冊裝置也能封存 |
| testing_scope | `external` | 能送審 |
| map_packs | `changed` | 只上傳有變的城市地圖包 |
| carry_map_packs | `yes`，除非下面那步驗過 | 地圖包內建在 App 裡（DEBUG-150）。`MAP-PACK-COPY.md` 的下一步是先發一個 `no` 的 TestFlight 給作者看；看過三座城都「已下載」、開得起來，上架版才改用 `no`，送審時要附上六包地圖包的現行版本 |

發版說明由 `.github/testflight-whats-new.md` 自動填。失敗時按 Re-run failed jobs，只會重跑失敗的那段（決策 1016）。

## App Store Connect 怎麼送審（作者）

1. App Store 分頁 → iOS App 的新版本：預設版號 1.0 **改成 0.6.0**（要和 build 的 `MARKETING_VERSION` 一樣）。
2. 「建置版本」選剛處理好的 build。
3. 上架資料的文字、關鍵字、截圖：專案資料夾 `app-store-1.0/`（截圖：iphone-6.9-zh、ipad-13-zh、iphone-6.9-en；英文 iPad 那組在作者的 Mac `~/Developer/app-store-1.0/`），檢查清單在專案的 Claude Doc「App Store 上架資料」。
4. App 內購買項目**不勾**（內購草稿留著，下一版才送）。
5. 隱私：不蒐集資料（#2752 的隱私清單）。出口合規：`Info.plist` 已寫 `ITSAppUsesNonExemptEncryption = NO`。
6. 定價與供應狀況：免費，排除中國大陸。歐盟 DSA：非商家。合約、稅務、銀行作者已設好。
7. 版本發佈選「**手動發佈**」，送審。
8. 審過後作者自己按「發佈」。原訂 12/1，作者已說可以延後。

## 上架之後

- `project.yml` 的 `MARKETING_VERSION` 升 0.6.1，重新產生 Xcode 專案（CLAUDE.md 的 XcodeGen 步驟），再發下一個 TestFlight。
- 內購 #2730：上架版審過後，獨立審查，合併，購買畫面拍審查截圖（共用資料夾 `app-store-1.0/HANDOFF.md`），跟新版一起送審。
- 提醒作者實機再按一次「選擇車種」，確認不再卡住（#2764）。
