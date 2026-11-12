# COACH-HEALTH

派工單 COACH-HEALTH（session_01YGNNuo6tQeX7QkcatggiHC，`claude/coach-health`，2026-11-12）。只量不改：GameCore、`CoachRules`、存檔版本、golden、ReplayFixtures、SaveFixtures 都不動；沒有用決策號。規則在[決策 706](../decisions/706.md) §2。

## 做了什麼

- `Tests/GamePresentationTests/CoachHealthReportTests.swift`：只在要求時跑的報告測試（`COACH_HEALTH=<天>`、`COACH_HEALTH_ONLY=<情境>`），在玩家的全島實景世界裡量 17 個情境開、關客運站的差別。指令、每個情境的設定與耗時在 `docs/research/COACH_HEALTH_2026-11-12.md`「怎麼量的」。
- `docs/research/COACH_HEALTH_2026-11-12.md`：數字表、判定、給規劃的結論。
- 結果：**整體 HEALTHY**。票收 0%～+3.4%（護欄 ≥ −5%）；一天 100 旅次以上的站對最多 22.0%（護欄 25%）；沒有線由賺轉賠；中部、南部、東部與只買一兩條線的存檔客運搶 0。COACH-MEASURE 的全臺基準在併入 #2094 的 main 上重跑，數字相同。

## 還留下的

- **NOT ASSESSED**（研究文件「沒量到的」有細節）：高雄捷運紅橘線；全島世界裡的機場捷運；玩家改票價規則之後；玩家把車站鋪在中南部客運站旁邊；自強號與玩家自己的班表；多天。
- **和客運無關、量測時碰到的兩件事**，沒有查原因，請規劃決定要不要另派：
  1. 示範模式只鋪高雄捷運（`layDemoRealLines`，`krtc`）時 3 條線 74 站、0 列車、0 旅次，訊息仍說車在跑。
  2. 有地形的全島示範世界（點在 25.02, 121.30）收購機場捷運 `tymc:A` 回報坡度太陡、買不成；同樣做法其他在售的線都買得成。沒有確認玩家的正式遊戲會不會遇到。
- 決策 706 的「量到的」沒有改：這次的數字都在研究文件；規劃要的話把判定表那一列「中南部…NOT ASSESSED」改成指向這份文件。
- 「站滿或放棄」有客運時 +0%～+11.2%，沒有目標，沒有判（決策 706 同）。

## VERIFIED／UNVERIFIED

- VERIFIED（Linux 雲端容器）：release 建置後每個情境跑過 1 天（`728d58d`）；不設環境變數時測試跳過；`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨。
- UNVERIFIED：其餘測試交給 CI（這個 PR 只加一個預設跳過的測試檔與文件）。
