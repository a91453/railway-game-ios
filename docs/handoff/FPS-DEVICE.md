# FPS-DEVICE

- 派工單：FPS-DEVICE（遊戲規劃第 63 任 session_01YGNNuq9euTFvwq3qUD8j27；#1579 留言 6816196229、6817271597、6825721480）。
- session：Mac 本機（接實機 iPhone 17 Pro），2026-11-12。分支 `claude/fps-device`。
- 決策、存檔版本、golden、fixture：都不動。**沒有改程式**，只加兩個文件。

## 做了什麼

main `d098b79` 的 Release 組態裝上作者的 iPhone 17 Pro，用作者手機上「整個臺灣」的存檔量了 3D 最遠、台北街道、桃園機場日夜、600×／6000× 的 3D（過 3 次午夜），並在 Mac 上用作者的兩份存檔重播了 TICK-L0 合併前後。數字、量法、哪裡不準、最該先修的三件，都在 [FPS_DEVICE_2026-11-12](../research/FPS_DEVICE_2026-11-12.md)。

## 還留下什麼

- **沒量到的六項**（報告第 5 節，附接手做法）：跟著飛機、手動駕駛三段、鏡頭移很遠（P2-4 的直接量測）、150 列車存檔在實機的 600×／6000×、實機每 tick 時間、涼機的數字。這些都要作者用手操作，或用 Instruments。
- **P2-4 沒有結論**：只知道每次開 3D 第一格 CPU 至少 270 ms，不知道其中多少是機場重鋪。
- **TICK-L1、L2 要不要派**：Mac 重播顯示 L0 對作者的存檔沒有差別（150 列車每 tick 30 ms）；實機數字還缺，建議補了再決定。
- 量到的頓挫次數偏悲觀（XCUITest 拖慢主執行緒，報告第 2 節）；手機全程 thermal serious。

## 這台 Mac 與作者帳號上留下的東西（不在 repo）

- 作者手機的存檔備份：Mac 的 `~/RailwayGameDeviceBackups/2026-11-12-before-fps-device/`（裝新版之前的 `Application Support`，存檔版本 90）。
- 手機上的 App 現在是 main `d098b79`（存檔 91）：存檔在這版存過之後，TestFlight 127 讀不了，要等 128。作者 11-12 同意。
- 作者同意後用 `-allowProvisioningUpdates` 建了 UI 測試執行檔的開發描述檔：Apple 開發者帳號下多一個 App ID `io.github.a91453.RailwayGameUITests.xctrunner`；手機上多一個 `RailwayGameUITests-Runner` App，可以刪。
- 臨時的遙控 UI 測試沒有進 repo（做法寫在報告第 1 節）。Release 沒有 `-screenshot-*` 啟動參數，下次要在實機上自動擺鏡頭，得先決定要不要開一個 Release 也能用的入口。

## UNVERIFIED

- 實機每 tick 時間；存檔 B 在實機；跟飛機、手動駕駛、鏡頭移很遠。
- 速度選單蓋在 3D 上掉到 16–27 fps 是不是量測造成的。
- 涼機、120 Hz（全程上限 60 格）。
