# POST-134（134 發版後的例行公事）

- 派工：遊戲規劃，2026-11-16。session `session_01JMHz9cTTQbxuNsY3Q9S3KY`，分支 `claude/post-134`。
- 決策號、存檔版本（107）、golden、`SaveFixtures/`、`ReplayFixtures/`：都不動。保留的決策 796 沒用到，已放掉。
- 這個 session 壓縮 1 次（#2118 有記），做完這張不接新工作。

## 做了什麼

1. **發版紀錄**：`docs/research/PLAYER_FEEDBACK.md` 的 0.6.0 (134) 一節、`docs/HANDOFF.md` §2.0 的 134 那幾行
   （134 ＝ `36b5cb5`，TestFlight run 43782701616，地圖包第 1 版上傳 0 警告）。
2. **REVIEW-L24**：`docs/research/REVIEW_L24_2026-11-16.md`。P1 0、P2 3、P3 6。
3. **HEALTH-134**：`docs/research/HEALTH_134_2026-11-16.md`。機捷簡＋控 4/333、文湖簡＋控 6/532，死結都是 0。
4. **full lane 的兩個紅燈（都只改測試與腳本）**：
   - `LessonUITests.passFirstLesson()`：第二次加站的觸控掉在欄上時再加一次（單跑綠，run 43790654781）。
   - `.github/scripts/ui-smoke-missing-button.sh`：補決策 775 的編譯快取設定。
5. **L23 P3-3**：`Map3DDepotYardKit.bays(forSiding:)` 遇到 NaN、無限大不再在轉 `Int` 時當機，補四個斷言。

## 還留下什麼（請規劃派工）

- **機捷舊線不動、簡化規則、關掉行車管制：第二天 318/333 班沒發**（133 是 0）。134 的退步，推定 #2289 帶出來，沒查完；
  重現指令與下一步在 HEALTH-134 §3。五方加權約 2.4，是 bug。會動 GameCore。
- 買下的十分不能改建成島式（約 2.5）、中洲沙崙三股照舊兩側月台（約 2.2）：REVIEW-L24 P3-5，來源 `docs/handoff/ISLAND-ACQUIRE.md`。
- 冬季活動第 5 週漏算 00:00 開始營運的路線（L23 P3-1）：WINTER-MISSIONS，12/1 前。
- 有乘客的四格、長途客運這次沒量，下一次健檢補。

## UNVERIFIED

- 「少了按鈕」證明的修正：只有夜裡排程的 full lane 與手動 `verify_missing_button` 會跑，要下一次夜裡的 full lane 才知道。
- 第一課那支測試單跑一次綠，不能證明不再晃。
- iOS 實機、畫面全部沒看。
