# FPS-DEVICE

- 派工單：FPS-DEVICE（遊戲規劃第 63 任 session_01YGNNuq9euTFvwq3qUD8j27；#1579 留言 6816196229、6817271597、6825721480）。
- session：Mac 本機（接實機 iPhone 17 Pro），2026-11-12。分支 `claude/fps-device`。
- 決策、存檔版本、golden、fixture：都不動。**沒有改程式**，只加兩個文件。

## 做了什麼

main `d098b79` 的 Release 組態裝上作者的 iPhone 17 Pro，用作者手機上「整個臺灣」的存檔量了 3D 最遠、台北街道、桃園機場日夜、600×／6000× 的 3D（過 3 次午夜），並在 Mac 上用作者的兩份存檔重播了 TICK-L0 合併前後。數字、量法、哪裡不準、最該先修的三件，都在 [FPS_DEVICE_2026-11-12](../research/FPS_DEVICE_2026-11-12.md)。

11-13 凌晨作者手動補了第二輪（跟著飛機、手動駕駛、鏡頭移很遠、150 列車存檔的 2D／3D 600× 與 2D 6000×），在報告第 7 節；最該先修的三件以第 8 節為準。第二輪最重的發現：存檔 B 開 3D 畫 892 萬三角形、記憶體 3,327 MB、離上限剩 48 MB。

## 還留下什麼

- **還沒量到的**：實機每 tick 的確切時間（只有作者在畫面上讀到的「推進」400–650）、涼機的數字、乾淨條件下的午夜（P2-3）。要用 Instruments。
- **階梯降到 25 萬三角形之後實際仍畫 564–892 萬**：沒有查原因（只量不改）。
- **P2-4**：手動在 3D 拖遠 98 秒，沒有看到比開 3D 更糟的停頓；開 3D 第一格（270 ms 到 1.8 秒）裡多少是機場重鋪仍不知道。
- **TICK-L1、L2 要不要派**：Mac 重播顯示 L0 對作者的存檔沒有差別（150 列車每 tick 30 ms）；實機上 600× 只跑到 372×、6000× 約 1,180×，值得派，派之前先用 Time Profiler 確認。
- 第一輪的頓挫次數偏悲觀（XCUITest 拖慢主執行緒，報告第 2 節）；第二輪是手動，乾淨。手機大半時間 thermal serious。

## 這台 Mac 與作者帳號上留下的東西（不在 repo）

- 作者手機的存檔備份：Mac 的 `~/RailwayGameDeviceBackups/2026-11-12-before-fps-device/`（裝新版之前的 `Application Support`，存檔版本 90）。
- 手機上的 App 現在是 main `d098b79`（存檔 91）：存檔在這版存過之後，TestFlight 127 讀不了，要等 128。作者 11-12 同意。
- 作者同意後用 `-allowProvisioningUpdates` 建了 UI 測試執行檔的開發描述檔：Apple 開發者帳號下多一個 App ID `io.github.a91453.RailwayGameUITests.xctrunner`；手機上多一個 `RailwayGameUITests-Runner` App，可以刪。
- 臨時的遙控 UI 測試沒有進 repo（做法寫在報告第 1 節）。Release 沒有 `-screenshot-*` 啟動參數，下次要在實機上自動擺鏡頭，得先決定要不要開一個 Release 也能用的入口。

## UNVERIFIED

- 實機每 tick 的確切時間；第二輪各段對應哪個情境是照作者口述的順序對的。
- 速度選單蓋在 3D 上掉到 16–27 fps 是不是量測造成的。
- 涼機、120 Hz（全程上限 60 格）。
