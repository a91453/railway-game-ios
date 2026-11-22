# DEBUG-144（2026-11-22）

- 派工：協調者（144 發版後例行 A 的除錯）。雲端 Linux，分支 `claude/post-release-144`（PR #2591）。
- 範圍：143→144（`a011379..e6728ee`，17 個 PR）。REVIEW-L32 在 `docs/research/REVIEW_L32_2026-11-22.md`；HEALTH-144 與記憶整理是別串，這裡沒碰。
- GameCore、存檔版本、golden schema、決策號都不動。

## 做了什麼

1. **release 建置**（`swift build -c release -Xswiftc -enable-testing --build-tests`）：`859633a` 從頭 2,079 秒，**0 個警告**；併進 `e6728ee`（多 #2589 兩個地標與 #2595 一行說明）後再建一次 1,537 秒，**0 個警告**。
2. **release 下跑這個範圍動到的程式的測試**，57＋4＋9 支，**沒有當機、沒有失敗**（1 支照設計跳過，要環境變數才寫圖）：
   `PreferredPlatformKeepLeftTests`、`LineRoutePreferencePropertyTests`（決策 919）；`TrainPortraitTests`（TRAIN-IDENTITY）；`Map3DCrossroadsClusterTests`、`Map3DRoundaboutTests`、`Map3DStreetLifeTests`（920 與單行道）；
   `Map3DJapanSignalTests`、`Map3DJapanStreetTests`、`Map3DJapanStationTests`、`Map3DFukuokaTanksTests`（921–924）；`Map3DLandmarkRegistryTests`、`Map3DHongKongLandmarksTests`（925–927）；`HongKongBoughtAgainTests`（CIOPT-13 搬的那一類，release 23 秒）。
3. **`TrainPortrait` 全掃**（REVIEW-L32 P3-2）：原本的測試每個車種只畫 3 節，App 會要 1–3 節與沒有車種的演出車。補了 `testEveryKeyTheAppAsksForPaintsAtEveryLength`：每個車種的鍵與每組演出車的鍵，1、2 節都和 3 節一樣畫得出來（或一樣沒有模型）、大小對、圖裡有車。debug（CI）與 release（本機）都過。
4. **讀程式找當機寫法**（強制解包、`try!`、浮點轉 `Int`、範圍、除以零、越界）：結果寫在 REVIEW-L32，沒有要修的。
5. **CI**：nightly `ci.yml` 44956141155（`53b6da1`）全綠、沒有缺權重的警告；`e6728ee` 的完整 `ci.yml`（45046206140）與 full lane（45046220626）結果見 PR #2591。

## 注意（給下一個做 DEBUG 的人）

- 建置途中不要動原始檔：這次在 release 建到一半時併了 `main`，`Map3DLandmarkRegistryTests.testTheListIsEveryRegistrationInTheSources` 紅了一次（它拿磁碟上的原始檔對編進去的地標表，原始檔多了 #2589 的兩個、二進位還是舊的）。重建後就綠，不是 bug。
- 雲端背景指令有時間上限：debug 的 `swift build --build-tests` 與 release 建置同時跑，兩邊搶 CPU，debug 那個被時間上限砍掉。一次跑一個；這個 PR 的 debug 建置與測試以 CI 為準。

## UNVERIFIED

- 實機、Metal、聲音。
- macOS／Xcode：只有 CI 的 Simulator 建置與 `only_testing` 那一支 UI 測試（結果見 PR）。
- 本機沒有跑完 `swift build --build-tests -Xswiftc -warnings-as-errors`（debug）；CI 的 `Swift 6.4 (Linux) build` 用同一個指令，在 `fb81727` 與 `9656e10` 都綠。
