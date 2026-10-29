# 事件 × 通道回饋稽核（UI 健檢 P）

日期：2026-10-29。派工：`docs/research/UI_UX_REVIEW_2026-10-28.md` §3 第 4 名、§4.1 第 4 點。只出表，不改程式。

## 方法與出處

照 rshankras/claude-code-apple-skills 的 `design/game-feel/feedback-audit.md`（MIT，Copyright (c) 2025 Ravishankar，2026-07-24 commit `9ffb831`，來源表見 UI_UX_REVIEW 第 28 行）：先列玩家遇到的事件，再對每個事件逐通道問「有沒有、在哪個檔案」，最後把不一致與缺的列出來，聲音與觸覺留給實機確認。本作沒有前例，表是這次從程式裡找出來的。

通道五欄：畫面（動畫、卡片、顏色，`MotionRule`）、觸覺、聲音、減少動態效果時、VoiceOver 公告。

**怎麼查的**：從 `RailwayGameApp/` 與 `Sources/GamePresentation/` 搜 `playSound`、`sensoryFeedback`、`UIImpactFeedbackGenerator`、`AccessibilityNotification`、`accessibilityReduceMotion`，再追每個呼叫的事件。**沒有用模擬器或實機執行**，下表全是讀程式；聲音大小、觸覺手感、是否真的聽到都標在最後一節「要實機確認」。

## 通道總覽（全部的出口）

- 聲音：`SoundCue` 十二種（`Sources/GamePresentation/SoundCue.swift:7`）：arrival、track、transition、built、income、refused、warning、goalMet、lineAcquired、ticketIssued、horn；另有不經 cue 的迴圈：跟隨列車行駛聲、天氣、雷、垃圾車、背景音樂與降音（`RailwayGameApp/App/GameAudio.swift`）。
- 觸覺：只有兩處。`GameAudio.feedback(for:)`（`GameAudio.swift:453-460`）給三種：refused → `.error`、warning → `.warning`、built／goalMet／lineAcquired → `.success`，由 `RailwayGameApp.swift:96` 的 `sensoryFeedback` 發出；以及按住軌道 `UIImpactFeedbackGenerator(style: .medium)`（`Views/MapView.swift:661`）。觸覺在聲音關掉時仍會發（`GameAudio.swift:203-205`），但前面有 `guard plays, isActive`（`:207`）與同聲音的間隔限制（`:211`）。
- VoiceOver 公告：只有三處 `AccessibilityNotification.Announcement`：狀態橫幅（`Views/ControlPanel.swift:1097`）、達成目標勾（`Views/FeedbackViews.swift:382`）、教學提示的問題（`Views/TutorialOverlay.swift:347`）。
- 減少動態效果：畫面通道統一走 `MotionRule.running(reduceMotion:)`（`Sources/GamePresentation/InterfaceMotion.swift:53`），`Views/` 下二十多個檔案讀 `accessibilityReduceMotion`。聲音與觸覺不受它影響（合理，不需要處理）。

## 表（有／沒有，附檔案:行號）

「—」＝沒有。事件之外沒列的畫面通道（例如音樂開關）不在此表。

| 事件 | 畫面 | 觸覺 | 聲音 | 減少動態效果時 | VoiceOver 公告 |
|---|---|---|---|---|---|
| 列車到站 | 有間接：該站浮出「+$12」（`FeedbackViews.swift:103`，`pop`→`cardOut`，1.2 秒）；列車自己的動畫在地圖層，不在本表 | — | 有：站的鈴聲，關注的車 0.55／其他 0.2，其他每 6 秒一次（`GameSession.swift:1836`、`GameAudio.swift:396-397,431`）；600× 以上只播短動機（`GameAudio.swift:429`） | 浮字只淡出（`FeedbackViews.swift:163-165`） | —（金額由現金讀） |
| 列車發車 | — | — | — | — | — |
| 賺錢（收入入帳） | 有：現金下「+$」漂下淡出（`FeedbackViews.swift:61`、`HUDView.swift:254`） | — | 有：`income` 雙叮，間隔 3 秒，昨天虧損時不響（`GameFeedback.swift:120`、`GameAudio.swift:437`） | 原地淡出（`FeedbackViews.swift:61-63` 註解） | —（VoiceOver 讀現金本身） |
| 虧錢（日結算虧損） | 有：現金浮紅字「−$」（`GameFeedback.swift:123` 起，同一個 `IncomeFloat`） | — | 沒有（刻意：「虧損不是獎勵」，`GameFeedback.swift:123` 註解） | 同上 | — |
| 蓋好（建築、月台、買實體車站） | 有：落點的環與勾（`FeedbackViews.swift:10`，`builtRing` 0.9 秒） | 有 `.success`（`GameAudio.swift:457`） | 有：`built`（`GameFeedback.swift:105`） | 勾只淡出（`FeedbackViews.swift:6-7`） | 橫幅會讀成功訊息（`ControlPanel.swift:1097`） |
| 鋪軌 | 有：軌道本身出現；沒有環 | — | 有：`track` 軌縫聲，100 毫秒間隔（`NetworkSession.swift:243`、`AutoService.swift:432` 等） | — | 橫幅（若有訊息） |
| 拆掉（建築、軌道） | 軌道／建築消失；沒有環、沒有勾（`notePutUp` 只在蓋時呼叫：`BuildingSession.swift:318`、`NetworkSession.swift:594`、`RealStationPurchase.swift:194`） | — | — | — | 橫幅（若有訊息） |
| 買車 | 橫幅「已購買…請選擇車站」（`GameSession.swift:2121-2124`） | — | — | 橫幅改淡入淡出 | 橫幅 |
| 賣車 | 橫幅（`GameSession.swift:2136`）；橫幅上的「出售」鈕可復原（`ControlPanel.swift:1138` 起） | — | — | 同上 | 橫幅 |
| 指令被拒絕 | 有：橫幅警告色與三角（`ControlPanel.swift:1114-1123`） | 有 `.error` | 有：`refused` 兩個低音，600 毫秒間隔（`GameSession.swift:336`） | 橫幅淡入淡出（`MotionRule.cardIn`／`cardOut`） | 有（`ControlPanel.swift:1097`）；`announces` 的條件我沒追，見下 |
| 破產倒數 | 有：HUD 文字（`HUDView.swift:237`）、目標面板（`GoalsPanel.swift:72`）、地圖警示泡（`MapAlerts.swift:101,161`、`MapAlertBubbles.swift:34`） | — | 間接：新聞進「債務／期限」類時響 `warning`（`GameSession.swift:378`）；每天倒數數字變了不響 | 警示泡淡入淡出（`MapAlertBubbles.swift:34,39`） | —（數字變動不公告） |
| 新的警告（債務、颱風、缺建材、期限） | 新聞列、警示泡 | 有 `.warning` | 有：`warning` 兩聲鈴，2 秒間隔（`GameSession.swift:372-378`） | 同上 | — |
| 達成目標／市民請求 | 有：畫面中央勾與標題，彈一下停幾秒（`FeedbackViews.swift:344`，`confirm`） | 有 `.success` | 有：`goalMet`（`ActionFeedback.swift:286`、`NextSteps.swift:236`） | 只淡出（`FeedbackViews.swift:340-343`） | 有（`FeedbackViews.swift:382`）；另有橫幅 |
| 成就解鎖 | 橫幅「解鎖成就…」（`Achievements.swift:473-483`） | — | 有，但借用 `income`（`Achievements.swift:484`），不是專屬音 | 橫幅 | 橫幅 |
| 城鎮成長 | 有：站上黃環（`FeedbackViews.swift:397`，`builtRing`） | — | 沒有（刻意：太常發生，`FeedbackViews.swift:393-396`） | 只淡出 | — |
| 買下真實路線 | 卡片（`RealLineAcquisitionCards.swift`） | 有 `.success` | 有：`lineAcquired`（`RealLineAcquisition.swift:1080`） | 同卡片 | 橫幅 |
| 車票開賣／調價 | 橫幅 | — | 有：`ticketIssued`（`GameSession.swift:1697`） | — | 橫幅 |
| 教學步驟完成 | 有：教學卡（`TutorialOverlay.swift`，`pop`） | — | 沒找到（`Tutorial*` 檔案內沒有 `playSound`） | 縮放去掉（`TutorialOverlay.swift:319`） | 只有「問題」類提示公告（`TutorialOverlay.swift:347`）；步驟完成與下一步不公告 |
| 存檔成功 | 橫幅「已儲存遊戲」（`GameLauncher.swift:1576`） | — | — | 橫幅 | 橫幅（連按兩次的第二次也會公告，`ControlPanel.swift:1093-1097` 註解） |
| 存檔失敗 | 橫幅警告色（`GameLauncher.swift:1579`） | 有 `.error`（走 failure → refused） | 有 `refused` | 同上 | 橫幅 |
| 跳過夜晚（開始、結束） | 有：按鈕換成「停止」（`NightSkipChip.swift:29-44`，`pop`／`change`） | — | 背景音樂降 12 dB（`GameSession.swift:1175-1180`）；開始與結束沒有提示音 | 淡入淡出 | —；晨光到時沒有公告 |
| 切換工具、進出遊戲 | 工具列變化 | — | 有：`transition` 嗖聲（`GameSession.swift:1261`、`GameLauncher.swift:1485,1714`） | — | — |
| 按住軌道（長按） | 面板與路線高亮 | 有：中等衝擊（`MapView.swift:661`），**唯一不走 `sensoryFeedback` 的觸覺** | — | — | — |
| 鳴笛（3D 跟隨） | 無 | — | 有：`horn`，450 毫秒間隔（`GameSession.swift:1323,1345`） | — | — |
| 年度、月度報告 | 報告卡（`GameSession.swift:1850` 的 `yearEndYear`） | — | — | 卡片 | — |
| 劇本結束（勝、敗） | 切到目標面板（`ContentView.swift:171,304`、`GoalsPanel.swift:66`） | — | — | — | — |
| 颱風、天氣 | 地圖雨與閃電（地圖層） | — | 有：雨迴圈與雷（`GameAudio.swift:274-311`） | 地圖層另處理 | — |

## 不一致與缺的地方

排序：先照五方各自的重要性，再看大小。大小：S＝一個函式內可改；M＝一個檔案或一個 cue；L＝跨層（GameCore 事件或新音檔）。建議只寫方向，不實作。

### 玩家

1. **賣車、買車、拆掉、存檔成功、教學步驟完成都沒有聲音也沒有觸覺**（S～M）。這些是玩家主動按的操作，卻比被動的「到站」還安靜。建議：存檔成功與買車／賣車用現成的 `transition` 或新 `.confirmed`（一聲）；拆掉用輕觸覺。先決定「哪些主動操作該有確認」再加。
2. **觸覺只在三種 cue 上，而且解鎖成就沒有觸覺**（S）。`GameAudio.feedback(for:)` 的 `.income` 回 nil，成就借 `income` 音，所以成就是唯一達成類事件沒有 `.success`。建議：成就走 `goalMet` 或給 `.success`。
3. **拆掉沒有任何完成回饋**（S）：蓋有環與勾，拆什麼都沒有，玩家看不出拆成功了沒有。建議：拆時在原位放一個縮小的環，或只給輕觸覺加橫幅。
4. **跳過夜晚開始與結束沒有提示**（S）：只靠按鈕換字和音樂變小聲。建議：結束時一個提示（早晨的鈴），VoiceOver 公告「天亮了」。
5. **破產倒數每天變化不公告**（S）：倒數是會輸的訊號，卻只有文字。建議：每天變小時對 VoiceOver 公告一次，剩 3 天以內加觸覺 `.warning`。

### 鐵道迷

6. **列車發車沒有任何回饋**（M）：站長發車鈴是鐵道的核心動作，到站有鈴、發車沒有。建議：關注的列車發車時一聲短鈴，間隔限制比照到站（只對關注的車）。要先確認 GameCore 有可讀的發車事件（讀 `train.execution` 的轉換即可，不需要新事件）。
7. **成就借用 `income` 音**（S）：鐵道迷的成就（例如開通新線）聽起來像收入。建議：用 `goalMet` 的變體。

### 開發

8. **觸覺有兩個出口**（S）：`MapView.swift:661` 直接用 `UIImpactFeedbackGenerator`，其餘走 `GameAudio.haptic`；兩邊都該尊重系統觸覺設定。建議：長按也走 `GameAudio.haptic`（加 `.impact` 類型），一個出口好測。
9. **VoiceOver 公告只有三處**（M）：橫幅、達成勾、教學問題。到站、破產倒數、跳夜、存檔都靠橫幅或根本沒有。`announces` 的條件（`ControlPanel.swift:1096`）我沒追到底，要看哪些訊息會被擋。建議：先查 `announces`，再決定要不要補 2 處。
10. **回饋沒有集中表**（M）：事件→通道是散在 20 個檔案的 `playSound?`／`message =`。建議：新增 `Sources/GamePresentation/FeedbackMap.swift`，列事件到通道的對照（資料表），測試檢查每個 `SoundCue` 都有事件，之後這份文件可以由它產生。

### 美術

11. **減少動態效果的規則統一，但「沒有環」的事件（拆、買車）沒有對應畫面**（S）：見 3。
12. **`IncomeFloat`（現金）、`FareFloat`（站）、`TripStamp`（站）同時出現時層次**（M）：三個浮出物用同一個 `pop`→`cardOut` 但高度不同（`FeedbackViews.swift:170-177` 註解說「Above the fares」）。要實機看 600× 的擁擠度。

### 音樂

13. **到站鈴與音樂的調性**（S，需實機）：音樂降音只在跟隨列車進換乘站與跳夜時（`MusicDuck`），平常到站鈴與音樂疊在一起；站的和弦是否與背景音樂同調我讀不出來。
14. **關注列車到站（0.55）比 `built`（0.6）、`goalMet`（0.55）小聲或相當**（S，需實機）：數值見 `GameAudio.swift:394-414`；高速時 600× 動機每 1.5 秒一次，可能蓋過 `built`。
15. **沒有「蓋好」之外的正向回饋音**（M）：買車、拆掉、存檔、教學步驟、成就全都是 `income` 或沉默。若要補，最好一次想好一組（例如 `confirmed`、`removed`、`stepDone` 三個）而不是各自借音。

## 要實機確認（模擬器聽不到、摸不到）

1. 三種觸覺（`.error`、`.warning`、`.success`）手感是否分得出，尤其 `.warning` 與 `.error`。
2. `UIImpactFeedbackGenerator(.medium)`（長按軌道）與 `.success`（蓋好）會不會互相蓋掉。
3. 聲音關掉時觸覺仍響（`GameAudio.swift:203-205`）是否符合預期；系統關觸覺時是否真的不響。
4. 600× 時到站動機（每 1.5 秒）與 `built`、`goalMet` 同時響的音量與層次；`warning` 的 2 秒間隔在連續警告時是否太稀。
5. 成就用 `income` 雙叮是否聽起來像收入。
6. 跳夜時音樂降 12 dB 的淡出時間（`MusicDuck.fadeSeconds`）。
7. 環、勾、浮字在 Reduce Motion 打開時的實際樣子（淡出夠不夠清楚）。
8. VoiceOver 開著時：橫幅公告會不會被「達成目標」公告打斷；存檔成功連按兩次是否公告兩次。

## 下一步

建議先做 1、2、3、6（玩家與鐵道迷，都是 S～M），再看實機清單；項目 10 的對照表可以和健檢 N 一起排。以上都是建議，不是決定；要不要做、先做哪個由規劃定。
