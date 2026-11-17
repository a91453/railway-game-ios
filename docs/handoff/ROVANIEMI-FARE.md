# ROVANIEMI-FARE（含 ROVANIEMI-PAIR）

session_01JMHz9bnKhejDxHKpyueHQ3，分支 `claude/rovaniemi-fare`（從 `claude/rovaniemi-open`，含 #2355），決策 828，存檔版本 108，golden schema 不動（77）。
這個 session 壓縮兩次後依規則停了；下面是接手要做的。

## 進度

- 做完：遠距需求（`DistanceDemand`、`GameWorld.farDemand`）、國家軌道（`LineAcquisition.stateTrack`、`layStateTrack`、每公里 NT$5、使用費 1 %）、
  海外新局打開遠距需求、`vr:` 線收購走國家軌道、存檔 108 與 fixture `v108-state-track.json`、決策 828、§29.30 更新。
- 判定：CONCERNS（KJA 單買回本 14,686 天；MUL 84 天、兩條 219 天、香港 SIL 364、TCL 97 天）。數字見決策 828 §2。

## 已驗證（Linux 雲端容器）

- VERIFIED：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨（合併 main 之前的 commit `dad309a`）。
- VERIFIED：`FarDemandTests`、`StateTrackTests`、`DistanceDemandTests`、`LineAcquisitionTests`、`SavedGameTests`（38）、
  `FullEndWithoutDepotTests`、`RovaniemiRailwaysTests`（7）通過（同上）。
- VERIFIED：`doc_numbers.py --check` 0 差異（合併之後）。
- VERIFIED：香港 SIL 關掉遠距需求和打開一模一樣（64,216 旅次、+84,022／天）。UNVERIFIED：TCL 的對照沒跑完。
- VERIFIED：合併 main 之後重 build 乾淨；CI rest-1 的 `HarbourSightsTests.testASaveOfVersion106IsReclassifiedWhenRead`（寫死 107）改讀 `SavedGame.currentVersion`，本機通過。
- UNVERIFIED：iOS（Xcode、UI 測試）交給 `ios-build.yml`。

## 接手的下一步

1. 看 PR 的 CI；紅了照失敗修。全綠後轉 ready，在 #2118 留「可合併、head …」。
2. 補香港 TCL 的對照（約 32 分；SIL 已量）：
   ```sh
   swift build --build-tests -Xswiftc -warnings-as-errors
   ROVANIEMI_REPORT=30 ROVANIEMI_CITY=hk ROVANIEMI_FAR_OFF=1 ROVANIEMI_ONLY=hkmtr:SIL swift test --skip-build --filter RovaniemiReportTests
   ROVANIEMI_REPORT=30 ROVANIEMI_CITY=hk ROVANIEMI_FAR_OFF=1 ROVANIEMI_ONLY=hkmtr:TCL swift test --skip-build --filter RovaniemiReportTests
   ```
   和決策 828 §2 的「遠距需求開」比；香港的線都在 20 km 內，預期幾乎一樣。
3. 後續排在 NEXT_PRIORITIES §29.30 第 4–6 項（ROVANIEMI-KJA 2.40、FAR-DEMAND-TW 2.30、LINE-COST-SPLIT 1.95）。
