---
name: motion
description: 介面怎麼動：卡片、面板、泡泡、按鈕、建造回饋、教學卡片的動畫時間、曲線、彈簧，與「減少動態效果」打開時怎麼辦。加或改 App 裡任何 withAnimation、.animation、.transition、phaseAnimator、keyframeAnimator 之前先讀。Use before adding or changing any SwiftUI animation or transition in the app (RailwayGameApp/Views), or when judging whether an interface motion looks and feels right.
---

# 介面的動態

App 的介面動畫照一套規則走（ARCHITECTURE 決策 253）：每一種動作一條規則，「減少動態效果」只有一個答案。規則本身在 GamePresentation 的 `MotionRule`（`Sources/GamePresentation/InterfaceMotion.swift`，Linux 測試 `InterfaceMotionTests`），App 在 `Theme.swift` 把它轉成 SwiftUI 的動畫與轉場。**不要在 View 裡寫新的秒數或彈簧**，就像顏色不在 View 裡寫色碼一樣。

做法取自 LottieFiles 的 [motion-design-skill](https://github.com/LottieFiles/motion-design-skill)（`f9a8a04`，MIT，授權全文在本資料夾的 `LICENSE`）：時間與曲線表、迪士尼 12 原則的介面版、減少動態。它不綁任何函式庫，這裡改寫成 SwiftUI，並拿掉和畫風衝突的部分（第 5 節）。

## 1. 規則

| 規則 | 秒 | 曲線 | 用在 | SwiftUI |
| --- | --: | --- | --- | --- |
| `press` | 0.15 | 減速 | 按鈕按下、放開 | `ThemeSelectableButtonStyle` 等 |
| `change` | 0.2 | 兩端平滑 | 原地的變化；卡片或面板進出時，旁邊的版面讓位 | `.animation(MotionRule.change.layout(reduceMotion:), value:)` |
| `cardIn` | 0.28 | 減速 | 卡片、面板從它所在的邊進來（細節卡、地圖旁的面板、跟隨列、狀態訊息） | `.transition(.card(from:reduceMotion:))` |
| `cardOut` | 0.2 | 加速 | 同一張卡片離開：比進來短 | 同上（不對稱轉場） |
| `pop` | 0.25 | 彈簧，bounce 0.2 | 手指下方冒出的小東西（車站名牌、建造的 ✓ ✕）、教學卡片打開或收合 | `.transition(.pop(reduceMotion:))`、`MotionRule.pop.layout(reduceMotion:)` |
| `confirm` | 0.25 | 彈簧，bounce 0.2 | 好消息的狀態訊息輕輕一跳（放大 4%） | `StatusBanner` 的 `phaseAnimator` |
| `refuse` | 0.36 | 兩端平滑 | 被拒絕的狀態訊息左右搖三次，一次比一次小（`RefusalShake`，±6 點） | `StatusBanner` 的 `keyframeAnimator` |
| `builtRing` | 0.9 | 減速 | 蓋好東西的地方擴散的環（決策 117） | `BuildPulseMark` |

**加新的動畫時**：先找上表合用的一條。真的都不合，才在 `MotionRule` 加一條，並在 `InterfaceMotionTests` 加它的範圍，再補這張表與 `docs/UI_THEME.md`。

## 2. 原則（改寫自 LottieFiles）

- **進來的比離開的長 30–50%**：玩家在意出現的東西。進來減速（快速出發、輕輕落地），離開加速。原地的變化兩端平滑。
- **重量決定回彈**：
  - 卡片、面板、對話框是重的：0.2–0.35 秒，不回彈；
  - 名牌、泡泡、圖示是輕的：0.15–0.25 秒，回彈 5–15%（bounce 0.2）。
- **時間對應東西的種類**：按下的回饋少於 0.15 秒；圖示的變化 0.15–0.25 秒；卡片 0.2–0.35 秒；只有慶祝類（蓋好的環）可以到 1 秒。手機上整體再短一點。
- **一次一兩個屬性**：位置或縮放，加上透明度就夠了。三個以上會顯得亂。
- **空間上的移動不要用等速**：等速只給進度條、旋轉、跟著時間走的東西（例如列車在路線上的點，`RouteStrip`）。
- **重要的狀態變化不要只靠透明度**：再加位置、縮放或顏色。例如被拒絕：搖動加警告色的框。
- **被拒絕要堅定**：左右搖，不用彈簧，最後停在原位；不要放大跳動（那是好消息的動作）。
- **成功輕輕一跳**：小幅放大、彈簧，不加粒子、彩帶。
- **同一個動作每次動得一樣**：同一種卡片用同一個轉場，不要這裡滑、那裡縮放。
- **錯開出現的總長在 0.5 秒以內**（手機再少 30%）：清單逐列出現時，每列間隔 20–40 毫秒。
- **移動不超過畫面的三分之一**：超過的話中間要有轉折，或改成淡入淡出。

## 3. 減少動態效果

系統的「減少動態效果」打開時（`@Environment(\.accessibilityReduceMotion)`）：

- **不滑、不縮放、不彈、不搖**。
- **淡入淡出留著**，時間減半以上，不用彈簧：`MotionRule.reduced`。
- **只有移動的動作直接發生**：`reduced` 是 `nil`。
- **版面讓位直接發生**：`layout(reduceMotion:)` 是 `nil`。卡片與面板的轉場自己帶著淡入淡出的動畫（`AnyTransition.card`、`.pop`），所以版面不動、卡片照樣淡入。
- **不自動循環播放**：等待環的擴散、天氣、號誌的閃動都已經照這條做（`MapProblems.pulse`、`TrafficOverlay.deadlockStrength`、`MapWeather`）。

新的動畫一定要接上 `reduceMotion`。最簡單的方法是用 `Theme.swift` 的 `.card`、`.pop`、`layout(reduceMotion:)`，它們已經處理好。

## 4. 寫法上的陷阱

- **兩個同樣識別碼的 View 不要同時在畫面上**：
  - 用 `if/else` 換成另一個 View 再加轉場，舊的淡出時新舊兩個都在。教學卡片打開與收合時，兩邊都有 `tutorial.progress`、`tutorial.skipStep`，UI 測試會找到兩個。
  - 教學卡片的做法：換的那一下不加轉場，換好之後用 `keyframeAnimator` 讓新的那張從小一點長回來。
  - 自訂的 `Layout` 只放 `subviews.first`，轉場時的第二個 View 不會被放好。所以外面包一個 `ZStack`，讓 Layout 永遠只有一個子 View。
- **`.transition(x.animation(a))` 帶自己的動畫**：外面的 `.animation(_:value:)` 是 `nil`（減少動態）時，轉場照樣用 `a` 淡入。
- **`phaseAnimator`、`keyframeAnimator` 的 trigger 每次都會跑**：要依情況不同（好消息跳、拒絕搖、減少動態都不動），就在內容裡判斷，不要換 trigger 的值。換值本身也算一次觸發。
- **UI 測試**：會滑進來、縮放進來的東西，出現之後要等 `becomesHittable(within:)`，不要直接問 `isHittable`（CLAUDE.md）。

## 5. 不採用的部分（和畫風衝突）

LottieFiles 原文要求每個動畫都有三層：主要、次要、背景（漸層、陰影、粒子）。這裡**不照做**：

- 畫風是扁平、實心色塊、不用漸層與陰影（art-style skill、決策 84、121）。背景層只留遊戲本身的時間流動（列車、天氣、時段）。
- 不用陰影跟著移動、模糊、光暈、彩帶。
- 不加 Lottie 的播放套件：這份只拿原則，動畫用 SwiftUI 自己做。
- 「深色模式降低 10–20% 的動態強度」先不做：規則的數字已經小，等實機看過再說。

## 6. 怎麼檢查

1. **Linux**：`swift test --skip-build --filter InterfaceMotionTests`。檢查規則在表的範圍內、進比出長、只有小東西回彈、減少動態只留淡入淡出、拒絕的搖動三次、一次比一次小、停在原位。
2. **Simulator 或實機**（Linux 上看不到）：
   - 「設定 › 輔助使用 › 動作 › 減少動態效果」開與關各看一次。
   - 看的三處：建造（✓ ✕ 的泡泡、蓋好的環、被拒絕的訊息）；點車站與列車、開關面板；教學卡片的打開與收合。
3. **PR 的寫法**：寫出每個動畫用哪一條規則，改了哪個秒數，以及減少動態時變成什麼。
