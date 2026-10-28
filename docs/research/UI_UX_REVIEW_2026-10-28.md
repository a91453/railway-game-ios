# 研究：外部 UI／UX 專案與畫面健檢（2026-10-28）

> **狀態**：研究與建議，沒有改程式。派工單 CA（規劃 session_01YGNNumoD1XSP8eSkjabCvp 派）。存檔版本、決策號、golden 都不動。健檢列出的改動由規劃排；10/31 公開測試前不合會改畫面的 PR。

作者 2026-10-28：「https://github.com/Leonxlnx/taste-skill 可以來改善我現在遊戲內的缺點嗎」→「還是有更好的使用者ui ux GitHub 專案」→「沒關係研究 值得就先做／有更好的使用者ui ux GitHub 專案也一起研究」。

這份分四段：

1. 外部專案：能拿什麼、授權、和我們規則衝突的地方。
2. 畫面健檢：程式碼層級，52 項。
3. 五方排序。
4. 哪些規則值得搬進 `.claude/skills/`。

**怎麼驗證的**：

- **VERIFIED**：每個專案都 clone 到 scratchpad，授權與最後一次 commit 由 `LICENSE` 與 `git log` 讀出。健檢的每一項都讀過 `main` `cc0256c` 的原始碼，行號是這個版本的。
- **UNVERIFIED**：沒有在 Simulator 或實機上看。Linux 沒有 Simulator，10/29–30 的 macOS runner 也留給修 bug。所以每一項都是「程式碼這樣寫，畫面上應該會這樣」，要等第 5 節的截圖檢查確認。

---

## 1. 外部專案

### 1.1 總表

| 專案 | 授權（讀 `LICENSE`） | 最後 commit | 對我們的用處 |
| --- | --- | --- | --- |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | MIT，Copyright (c) 2026 Leonxlnx | 2026-10-25 `12af471` | 中：資料畫面的數字規則、看截圖挑毛病的方法；大半是網頁 |
| [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) | MIT，Copyright (c) 2025 Ravishankar | 2026-07-24 `9ffb831` | **高**：iOS 的 HIG 檢查、Dynamic Type 的處理順序、遊戲回饋稽核、Liquid Glass |
| [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill)（SwiftUI Pro） | MIT，Copyright (c) 2026 Paul Hudson. | 2026-10-26 `f2920b6` | **高**：SwiftUI 的無障礙、版面伸縮、效能、在地化寫法 |
| [raintree-technology/apple-hig-skills](https://github.com/raintree-technology/apple-hig-skills) | MIT，Copyright (c) 2025 Raintree Technology，只涵蓋它自己的程式；`skills/*/references/` 是 Apple HIG 原文，© Apple Inc.（見它的 `THIRD_PARTY_NOTICES.md`） | 2026-10-22 `48bd383` | 低到中：HIG 章節索引；`packages/core/src/patterns.ts` 的 Swift 檢查規則清單可以改寫成 Linux 的檢查 |
| [ebuntario/apple-hig](https://github.com/ebuntario/apple-hig) | MIT，Copyright (c) 2026 Ethan Buntario（作者自己改寫 HIG，逐條附出處） | 2026-04-21 `c434b91` | 中：圖表、教學、載入的檢查清單 |
| [ibelick/ui-skills](https://github.com/ibelick/ui-skills)（自己找的） | MIT，Copyright (c) 2026 Julien Thibeaut | 2026-10-25 `59193a7` | 低：只拿 `improve-ui` 的審查方法 |
| [jakubkrehel/skills](https://github.com/jakubkrehel/skills)（自己找的） | MIT，Copyright (c) 2026 Jakub Krehel | 2026-10-25 `592aedc` | 中：`interface-review`（審 PR 的分類法）、`better-writing`（按鈕與錯誤訊息的寫法） |
| [cvs-health/ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques)（自己找的） | Apache-2.0，CVS Health | 2026-10-27 `f27dc0f` | 中：SwiftUI 無障礙的逐項做法；附的 `a11y-check` 是靜態檢查工具，加進來算新的依賴 |
| [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/)（網站） | 沒找到授權或使用條款，**只看想法、只引用** | — | 中：遊戲專屬的無障礙（速度、教學、目標提醒、可在暫停時操作） |
| [Xbox Accessibility Guidelines](https://learn.microsoft.com/gaming/accessibility/guidelines)（網站，v3.2） | 頁面上沒寫授權，**只看想法、只引用** | 2023-06-08 | 中：文字放到 200%、疊在變動背景上的對比要用最差的那一塊量 |

- 沒有 copyleft（GPL、LGPL、AGPL、MPL）的程式碼要拿。
- 兩個網站沒寫授權，照 CLAUDE.md 只看想法。
- 規劃點名的五個 repository 都是 MIT，已確認。
- 只能在網頁上用的部分都不拿：Node／Chrome 腳本、CSS、Tailwind、React。

### 1.2 每個專案能拿什麼

**taste-skill**

讀的檔：`skills/taste-skill/SKILL.md`、`references/critique.md`、`tells.md`、`copy.md`、`app-screens.md`。能拿的是資料畫面的規則（`app-screens.md`）：

- 一個畫面回答一個問題，最大的那塊就是答案；最重要的一個數字放在標題下面；最常做的事一次點到。
- 同一個數字出現兩次，要來自同一個值；總數與變化量用畫面上顯示的數字算。
- 每個變化量都寫跟什麼比。變化的顏色表示好壞，不表示漲跌；零或算不出來的變化用灰色。
- 數字的排法：靠右、等寬數字、固定小數位、千分位，變化量帶正負號。
- 真的零印 0；沒有資料用灰色的「—」。
- 空的、載入中、錯誤的狀態，都保留原本那塊的框。載入中用平的灰條，不用閃光。
- 清單的列：
  - 一行的列 36–53 點高，兩行的至少 40–44 點；
  - 總覽只列 4–6 列，加「看全部」；
  - 不用斑馬紋。
- 手機上：數字卡兩欄，表格改成兩行的列，有動作的塊往上移。
- 顏色只用在資料、狀態和唯一的主要動作；一個畫面最多四個色相。
- `copy.md`：按鈕用一到三個字說出動作；一個畫面只有一個主要動作。
- `critique.md`：看截圖挑毛病的方法，見第 5 節。

**衝突**（以我們的為準）：

- 它禁止藏青、石板色的深色主題，而藏青是我們圖示的主色。
- 它要 1 px 細框；我們用粗的藏青外框。
- 它說「一律 12–16 px 圓角」是 AI 味的破綻；我們刻意全部用圓角。
- 它禁止玻璃與模糊；我們浮在地圖上的控制用 Liquid Glass。
- 它允許浮動選單有陰影；我們全部不用陰影。
- 它要有個性的字體；我們用系統字，配 Dynamic Type。
- 它說「不要進場動畫」、說彈跳是破綻；我們有 `MotionRule` 的 `cardIn` 與 `pop`。
- 它允許折線圖下面淡出的漸層；我們不用漸層。
- 它的暖黃、米色警告不適用：暖黃是圖示的主色。

**rshankras/claude-code-apple-skills**（最貼近我們）

讀的檔：`skills/ios/ui-review/{SKILL.md,hig-checklist.md}`、`design/game-feel/{SKILL.md,feedback-audit.md}`、`design/ux-writing`、`design/typography`、`design/animation-patterns/SKILL.md`、`ios/accessibility-audit`、`design/liquid-glass`、`ios/ipad-patterns`。

- 觸控範圍至少 44×44 點；文字對比 4.5:1，控制項 3:1（和我們一樣）。`hig-checklist.md`
- Dynamic Type 依序處理：
  1. 用文字樣式；
  2. 用 `@ScaledMetric`；
  3. 字放大到輔助使用的大小時，用 `AnyLayout` 把橫排改直排；
  4. 最後才用「大型內容檢視器」。

  `typography/SKILL.md`
- 遊戲的手感（`game-feel/SKILL.md`）：
  - 越少見的事件，回饋越大；
  - 一個事件只由一層負責回饋；
  - 數字變化用 `.contentTransition(.numericText())`，不要瞬間跳；
  - 每個效果在「減少動態效果」打開時都要有對應的做法。
- 事件與通道的稽核表（`feedback-audit.md`）：每個事件列出畫面、觸覺、聲音三欄，附檔案與行號，最後在實機確認。這是五方裡「音樂」唯一明確能用的工具（第 3 節 P 項）。
- 文字：PACE（目的、預期、情境、同理）。刪掉「輕鬆、快速、只要」這類贅字；空的狀態不能是死路。`ux-writing/SKILL.md`
- 無障礙稽核：UI 測試裡的 `performAccessibilityAudit()`，加上手動逐項。`accessibility-audit/SKILL.md`
- Liquid Glass（`liquid-glass/SKILL.md`）：
  - 只用在工具列、浮動控制，不用在清單與內容上；
  - 不在玻璃上疊玻璃；
  - 好幾塊玻璃放在一起時，包進 `GlassEffectContainer`。

**衝突**：

- 它的慶祝產生器（彩帶）、MeshGradient、shader 特效違反畫風與動態規則。
- 它建議用系統顏色而不是固定色票；我們用 `Theme`。

**SwiftUI Pro**

讀的檔：`swiftui-pro/SKILL.md`、`references/{accessibility,localization,design,hygiene,resizability,performance}.md`。

- 只有圖示的按鈕也給文字（`Button("…", systemImage:)` 加 `.labelStyle(.iconOnly)`）。用 `Button`，不用 `onTapGesture`。
- 尊重「不以顏色區分」（`accessibilityDifferentiateWithoutColor`）。
- 標籤會一直變的按鈕（例如 HUD 上即時的數字），給 `accessibilityInputLabels`。
- 時間、間距放在共用常數（和我們的 `Theme`／`MotionRule` 同一個想法）。
- 版面：
  - 空間可能不夠的地方用 `ViewThatFits`；
  - 少用 `.caption2`；
  - 依 size class `== .regular` 分版面，狀態放在分支外面。
- 車站卡在 iPad 可以用 `inspector()`：iPad 上是側欄，iPhone 上變成 sheet。
- 清單效能：每列只傳它自己的資料，列的形狀固定；變化快的值不要放進 environment；用 `Text(value, format:)`，不要在 body 裡建 formatter。
- 套件裡的字串要用 `bundle: #bundle`。

它假設 iOS 27 與 Xcode 27；那些 API 照它自己說的放在 `#available` 後面。

**raintree／ebuntario**

- raintree 的 `designing-for-games.md` 指到 Apple 的遊戲章節：用玩的方式教、好的預設值、字要讀得清楚、選單隨畫面比例調整。
- raintree 的 `patterns.ts` 是 MIT，可以改寫成我們自己的檢查。它查的寫法有：`.font(.system(size:`、`Color(red:`、`.onTapGesture`、`UIScreen.main`。
- ebuntario：
  - 圖表上面寫一行摘要、標出高點、同一份資料同一個顏色、加 `accessibilityChartDescriptor`；
  - 教學可以略過、邊玩邊教、隨時看得到「略過」；
  - 短的等待不放轉圈；不讓錯誤代碼給玩家看。
- **衝突**：ebuntario 說「先用 SF Symbols、不畫自己的圖示」「不寫色碼」，和決策 121 的地圖圖示、`Theme` 的色碼定義衝突，以我們的為準。

**ibelick/ui-skills（`improve-ui`）**

- 審查方法：對照專案自己的設計規則。一個問題要有三樣才算：
  - 違反哪一條規則；
  - 證據顯示那個值真的畫到畫面上；
  - 正好一個改法。
- 每個問題都先試著推翻它，最多報三個。
- 它說「沒要求就不加動畫」，和 `MotionRule` 衝突。

**jakubkrehel/skills**

- `interface-review`：審 PR 時把問題分成「這個 PR 新加的」「改壞的」「本來就有的」。也抓沒做完的改動，例如新字串沒進翻譯、少了空的、載入中、停用的狀態。
- `better-writing`：
  - 整句帶佔位與複數規則，不拼字串；
  - 按鈕用動詞開頭；
  - 錯誤訊息說怎麼修；
  - 能復原就不用確認框；
  - 確認框的按鈕寫出動作與對象。

**CVS Health（Apache-2.0）**

- 表格的格子要讀出它的列名與欄名（原生 `Table()` 在 iPad 上的 VoiceOver 有缺陷）。
- 地圖要有縮放、平移的按鈕，不能只靠手勢。
- 打開「降低透明度」時，玻璃與材質的控制要變不透明。系統的 `.regularMaterial` 與 `glassEffect` 會自己處理，我們的 `glassBackground` 用的就是這兩個。
- 不會跟著放大的 HUD 按鈕，用「大型內容檢視器」。
- 它的 `a11y-check`（swift-syntax，45 條）沒確認能不能在 Linux 上建。加進 CI 算新的依賴，要作者同意。

**Game Accessibility Guidelines／Xbox Accessibility Guidelines**（只看想法）

- 遊戲速度可以調，可以關觸覺，觸控控制大、間距夠。
- 教學邊玩邊教，玩的時候隨時看得到目標與操作。
- 有不會失敗的練習場，音效與音樂的音量分開，資訊不只靠顏色。
- 暫停時也能操作，兩個方向都能拿，設定會記住，會自動存檔。
- XAG：
  - 文字能放到 200%，放大後不用兩個方向捲動；
  - 疊在變動背景上的字，對比用背景最差的那一塊算（例如 3D 地圖上的字）；
  - 玩家隨時知道自己在介面的哪裡。

### 1.3 和我們的規則對照後，各專案留下的

| 我們的規則 | 外部專案說的 | 結論 |
| --- | --- | --- |
| 畫風：扁平、粗藏青外框、圓角、不用漸層與陰影（art-style、決策 84、121） | taste-skill 要細框、說圓角是破綻、允許陰影；rshankras 的 MeshGradient | 以我們的為準，這幾條不拿 |
| 動態：`MotionRule`，減少動態只留淡入淡出（motion、決策 253） | taste-skill「不要進場動畫」；ui-skills「不加動畫」；rshankras 的彩帶 | 不拿；rshankras 的「每個效果都要有減少動態的對應」和我們一致 |
| 顏色只從 `Theme`／`Palette` 取 | rshankras、ebuntario「用系統顏色、不寫色碼」 | 不拿；我們的色票本身就算過對比 |
| 玩家看的文字：只寫效果，不寫理由與內部術語（UI_THEME） | jakubkrehel、rshankras 的寫作規則 | 相容，可以補進「玩家看的文字」：動詞開頭、錯誤說怎麼修、確認框寫出動作 |
| Liquid Glass 只用在浮在地圖上的元件 | rshankras「不要玻璃疊玻璃、用 `GlassEffectContainer`」 | 相容，值得拿 |

---

## 2. 畫面健檢（程式碼層級）

**範圍**：`RailwayGameApp/Views/` 的主要畫面，以及 `Sources/GamePresentation/` 裡它們讀的邏輯。

**做法**：用上面最合適的幾套規則逐檔讀：

- rshankras 的 `ui-review`、SwiftUI Pro 的 accessibility／resizability／performance；
- taste-skill 的資料畫面規則；
- 我們自己的 UI_THEME、art-style、motion。

每項都讀過原始碼。抽查的幾項（2-1、2-17、3-1、3-2、3-10、3-29）逐行核對過。

**先排除的（看起來像問題、其實已處理）**：

- 狀態列的圖示鈕已經有 44 點觸控範圍（`TouchTargetButtonStyle`，`HUDView.swift:984-1021`）。
- 健檢範圍內的檔案，字串都已進 `Localizable.xcstrings`。
- 教學外框的黑色光暈、警示泡泡的硬邊，是 UI_THEME 記下的例外。
- 2D 地圖有放大、縮小的按鈕（`MapView.swift:1950-1975`）。
- 大的破壞性動作有確認框，按鈕寫出動作與金額：刪路線、賣車、拆站、拆商店、關公車路線、改自由模式。

**「規則」欄的代號**：

- **HIG**：Apple Human Interface Guidelines，經 rshankras 的 `ui-review`。
- **SP**：SwiftUI Pro。
- **TS**：taste-skill 的 `app-screens.md`。
- **WCAG**：WCAG 2。
- **UT**：`docs/UI_THEME.md`。
- **MS**：`.claude/skills/motion/SKILL.md`。
- **AS**：`.claude/skills/art-style/SKILL.md`。

**大小**：S 是一兩個檔的小改；M 要改幾個畫面或加 GamePresentation 的邏輯與測試；L 是版面重排。

### 2.1 地圖旁、一直在畫面上的（HUD、建造、教學、開始畫面）

| # | 畫面 | 檔案:行號 | 問題 | 玩家看到什麼 | 建議改法 | 大小 | 依據 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2-1 | 狀態列：破產倒數、新聞徽章 | `HUDView.swift:240`、`:417` | `Theme.error` 底上用 `.white` 字；深色模式的 `error` 是 `#FF9B9B`，白字約 2:1 | 深色模式下快破產的倒數、新聞的未讀數幾乎看不清 | 改用 `Theme.onError`（深色是藏青，6.59:1） | S | WCAG 1.4.3、UT 色票 |
| 2-2 | 狀態列：倍速選單 | `HUDView.swift:1078` | 標籤 48×32 點；`Menu` 只有標籤那塊點得到（同檔 `:483-490` 的註解就這樣說），離暫停鈕只有 4 點 | 想按暫停點到倍速，或反過來 | 照遊戲選單的做法：44 點的標籤加負的 padding | S | HIG 44 點 |
| 2-3 | 手機上狀態列下面那一排 | `ContentView.swift:498-512` | 每個元件都固定大小：圖層條約 300 點，跳過夜晚的膠囊約 190 點。窄的時候不會換行，也不會收起來 | 375 點寬的 iPhone 上，跳過夜晚出現或直拿開著細節卡時，這排超出畫面或疊到卡片上（決策 305 記為未驗證） | 用 `ViewThatFits` 給窄的排法（圖層條收成一顆鈕），GamePresentation 加寬度測試 | M | SP resizability、TS 手機 |
| 2-4 | 狀態訊息 | `ControlPanel.swift:1157`（✕ 26×26）、`:1121-1149`（賣出、擴建膠囊約 26 點高） | 會自己消失的訊息，上面的按鈕又小 | 訊息消失前來不及點到 | 觸控範圍 44 點，外觀不變 | S | HIG 44 點 |
| 2-5 | 小地圖收合鈕 | `MiniMapView.swift:66` | 約 28 點，疊在拖曳地圖的範圍上 | 想收合，地圖卻移動了 | 44 點 | S | HIG 44 點 |
| 2-6 | 教學卡片的收合 | `TutorialOverlay.swift:462` | 32×32 | 教學時點不準 | 44 點 | S | HIG 44 點 |
| 2-7 | 地圖上的警示泡泡 | `MapAlertBubbles.swift:122` | 每顆 28 點高；疊起來時相隔 46 點，放得下 44 點的觸控範圍 | 點泡泡常常點到地圖 | `contentShape` 放大到 44 點 | S | HIG 44 點 |
| 2-8 | 復原、重做、細節卡開關 | `ControlPanel.swift:254`、`:277`；`ContentView.swift:854` | 40 點寬：按鈕樣式只在上下加 padding | 復原常點偏 | 寬度也補到 44 點 | S | HIG 44 點 |
| 2-9 | 建造的 ✓ | `MapBuildConfirm.swift:223` | ✓ 40 點高，旁邊的 ✕ 和復原 48 點：主要動作反而最小 | 確認建造比取消難點 | ✓ 至少和 ✕ 一樣大 | S | HIG 44 點、TS 主要動作 |
| 2-10 | 開始畫面「第一次玩」卡片的 ✕ | `StartView.swift:253` | 32×32 | 關不掉卡片 | 44 點 | S | HIG 44 點 |
| 2-11 | 警示泡泡、小地圖、細節卡的動畫 | `MapAlertBubbles.swift:33`（縮放）、`:38`（彈簧 0.3 秒、bounce 0.4）；`MiniMapView.swift:31`、`:80`；`ContentView.swift:577`（0.15 秒）、`:542`、`:660`（滑動） | 沒走 `MotionRule`，也不看「減少動態效果」；bounce 0.4 超過規則的 0.2 | 打開減少動態效果仍會彈、會滑；泡泡比其他東西跳得大 | 改用 `.pop`、`.card`、`MotionRule.*.layout(reduceMotion:)` | S | MS §1、§3 |
| 2-12 | 細節卡、小地圖、教學卡片的陰影 | `ContentView.swift:675`、`MiniMapView.swift:79`、`TutorialOverlay.swift:690` | 軟陰影，UI_THEME 沒記為例外 | 和扁平畫風不一致 | 拿掉，或用外框分層 | S | AS §1、MS §5 |
| 2-13 | 圖層條、狀態列的小字 | `MapQuickLayerStrip.swift:69`、`:72`（14 點、9.5 點）；`HUDView.swift:354`、`:416`（9 點） | 寫死字級，不跟著 Dynamic Type 變，而且小於 11 點 | 設定大字的玩家，這幾個字不會變大，反而最難讀 | `.caption2` 加 `@ScaledMetric`；狀態列的寬度要固定的地方設上限（決策 251） | M | HIG Dynamic Type、SP |
| 2-14 | 蓋建物、拆建物的訊息 | `Sources/GamePresentation/BuildingSession.swift:310`、`:337`、`:341` | 「蓋好辦公大樓 #12」：內部編號 | 玩家看到地圖上沒有的號碼（UT 第 6 條：只有畫在地圖上的編號才算名字；建物的編號要確認有沒有畫） | 確認地圖上沒有就拿掉 `#id`；`DisplayText.swift:142`、`:151` 的「節點 #」「軌段 #」一起檢查 | S | UT 玩家看的文字 §3、§6 |
| 2-15 | 圖層表的說明 | `MapLayerSheet.swift:41`、`:64` | 「800 公尺步行參考範圍」是怎麼算的；資料來源混在說明裡 | 讀起來像規格書 | 只寫看得到什麼；出處留在出處那一行 | S | UT §2、§4 |
| 2-16 | iPhone 直拿的細節卡 | `ContentView.swift:1188-1190` | 用 `verticalSizeClass == .regular` 判斷，直拿的 iPhone 也成立；註解說只有 iPad | 手機上窄的細節卡多了路網總覽，要捲更久 | 改用 `horizontalSizeClass`，或改註解（要先確認原意） | S | SP resizability |
| 2-17 | 拆除建物 | `ControlPanel.swift:646-649` | 一點就拆。「復原」只在遊戲時間沒動時有效（`GameSession.swift:3204-3216`：任何一個 tick 都會清空復原紀錄） | 遊戲在跑時點錯就拆掉了，救不回來 | 用建造的 ✓／✕ 確認，或拆除模式時自動暫停 | M | HIG 破壞性動作、jakubkrehel better-writing |
| 2-18 | 細節卡開關的 VoiceOver | `ContentView.swift:858` | 讀「隱藏／顯示控制」，實際開關的是細節卡，狀態也塞在標籤裡 | VoiceOver 玩家不知道按了會怎樣 | 標籤改「細節」，狀態用 value 或 `.isToggle` | S | SP accessibility |
| 2-19 | 跟隨列 | `FollowBar.swift:24-25`、`:30-85` | 每個 tick 讀整個 `session.world`，重建五種 `ViewThatFits` 排法 | 跟車時舊機型掉幀 | 照決策 367、377 把資料搬進 session 算好的值 | M | SP performance |
| 2-20 | 手機上選取工具時的整個畫面 | `ContentView.swift:470-700` | 同時約 11 組浮在地圖上的元件，看不出哪個是主要動作 | 玩家回報「手機上太擠」「卡片面板太大」（PLAYER_FEEDBACK「設計意見的累計」已 4 人） | 窄畫面把圖層條收成一顆鈕；先做第 5 節的截圖檢查再定 | M–L | TS「一個畫面一個問題」、HIG |
| 2-21 | 無害的動作用紅色 | `FollowBar.swift:192`、`:198`（取消跟隨是實心紅）；`NewGameOptionsView.swift:147`（清掉種子用 `.destructive`） | 紅色是「會失去東西」的意思 | 取消跟隨看起來像危險動作 | 改用一般樣式 | S | TS 顏色、UT `ThemeProminentButtonStyle` |
| 2-22 | 建造時的數字列 | `MapConstructionHUD.swift:15-65` | 一排固定、沒有窄的排法；坡度的字是小寫開頭，和其他行不一樣 | iPhone SE 最大字級時超出畫面 | `ViewThatFits`；文字統一 | S | SP resizability |
| 2-23 | 實景地圖的載入畫面 | `RealWorldLoadingView.swift:18-49` | 沒有進度，也不能取消 | 載得慢時像當機 | 顯示階段或進度；加「回開始畫面」 | M | TS 載入狀態、ebuntario |

### 2.2 資料多的面板與表單（財務、路線、時刻表、車站、車隊、設定）

| # | 畫面 | 檔案:行號 | 問題 | 玩家看到什麼 | 建議改法 | 大小 | 依據 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3-1 | 車站、時刻表、路線面板的移除類按鈕 | `StationPanel.swift:646`（拆月台）、`:708`（拆貨場）、`:1233`（清運量）、`:590`（退出轉乘群組）；`TimetableEditor.swift:194`（清空時刻表）；`LinesPanel.swift:1116`（刪除這個停站模式）、`:2275`（刪除停靠站）、`:493`（回到標準營運日） | 一點就生效。程式註解說靠復原，但任何一個 tick 都會清空復原紀錄（同 2-17） | 遊戲在跑時誤點一下，整張時刻表、整個貨場就沒了 | `confirmationDialog`，按鈕寫出動作（「清空時刻表」「拆除第 2 月台」），和拆站、賣車一樣；或讓這些編輯的復原跨過 tick | M | HIG 破壞性動作 |
| 3-2 | 地圖上的列車檢視卡 | `InspectorView.swift:122-137`（`chip`）、`:144-162`（`followButton`） | 時刻表、車隊、停車、繼續、折返、跟隨都是 `caption2` 字加上下 4 點，約 20–22 點高 | 最常用的幾個鈕在地圖上點不準，點偏就點到地圖 | 觸控範圍 44 點，膠囊外觀不變 | S | HIG 44 點 |
| 3-3 | 車隊總覽的賣出、跟隨 | `FleetOverviewSheet.swift:166-180`、`:275-295` | 膠囊約 22 點高；賣出就在載客條右邊 | 容易誤點（有確認框擋著） | 44 點 | S | HIG 44 點 |
| 3-4 | 車隊總覽的列 | `FleetOverviewSheet.swift:354-359` | 用 `.onTapGesture` 選列 | VoiceOver 不知道這列能點 | 改成 `Button`，或加 `.isButton` 與 action | S | SP「用 Button 不用 onTapGesture」 |
| 3-5 | 損益表、資產負債表、年度決算 | `YearEndReport.swift:15-46`（`StatementGrid`） | VoiceOver 逐格讀，不帶「本期／上期」欄名；三欄在 375 點、最大字級時擠 | 聽不出哪個數字是本期；手機大字時標題斷成好幾行 | 每列合併成一句（「票價收入，本期 $1,234，上期 $1,100」）；大字時改上下排 | M | CVS 表格標頭、SP、WCAG 1.3.1 |
| 3-6 | 時刻表、營運日的步進器 | `TimetableEditor.swift:251-266`；`LinesPanel.swift:466-477` | 標籤只有「到」「開」「起」，沒有站名與時間 | VoiceOver 只聽到「到，步進器」，改了也不知道變成幾點 | 標籤加站名，value 給時間 | S | SP accessibility |
| 3-7 | 路線的運量圖 | `FinanceTrendCharts.swift:252-280`；收入圖 `:102-106` | 利潤線縮放後畫在運量的軸上，軸的刻度是人數，沒有圖例；收入圖的虛線（成本）也不在圖例裡 | 把利潤線讀成人數，判斷錯哪條線賺錢 | 運量圖拿掉利潤線（下一張圖就有利潤），或加右軸與圖例；收入圖補「成本（虛線）」 | M | TS 圖例對得上、ebuntario 圖表 |
| 3-8 | 財務趨勢圖 | `FinanceTrendCharts.swift:112`、`:130`、`:154`、`:268`、`:296` | 只有一句摘要，沒有 `accessibilityChartDescriptor` | VoiceOver 玩家沒有音訊圖表，不能逐點聽 | 每張圖加 descriptor（資料在 `FinanceHistory`、`LineReport` 裡已有） | M | Apple Audio Graphs、ebuntario |
| 3-9 | 運行圖的縮放與平移 | `TrainDiagramView.swift:208-244` | 只能捏合與拖曳；只有「現在」一個鈕 | 單手、切換控制、VoiceOver 的玩家停在預設範圍 | 工具列加放大縮小、前後移，或 `accessibilityZoomAction`／`accessibilityScrollAction` | M | CVS「手勢要有按鈕替代」、HIG |
| 3-10 | 路線顏色選單、開通卡的色票 | `LinesPanel.swift:834`；`LineConfirmationCard.swift:145` | 顏色用色碼標示（「#42A5F5」） | 選單裡是色碼；VoiceOver 逐字讀「井字號 4 2 A 5…」 | 用顏色名稱（「藍」）；`LineBadge.namedCodes` 已有每個預設色的代號 | S | UT §3 |
| 3-11 | 型錄、路線面板的動畫 | `RollingStockCatalogView.swift:102`、`:124`、`:273`；`LinesPanel.swift:154`、`:165`、`:290` | 寫死的彈簧與秒數，或預設的 `withAnimation`，都不看減少動態效果 | 打開減少動態效果仍會滑、會彈 | `MotionRule.change`／`pop` 的 `layout(reduceMotion:)` | S | MS §1、§3 |
| 3-12 | 路線示意條、載客條 | `RouteStrip.swift:58`；`TrainLoadBar.swift:41` | 等速可以用（MS §2），但秒數寫死、不看減少動態效果 | 減少動態時列車點仍在滑 | 減少動態時不動畫；秒數放進 `MotionRule` | S | MS §2、§3 |
| 3-13 | 路線示意條上的列車 | `RouteStrip.swift:53` | 在路線色上用寫死的白色 | 黃、白、淺綠的路線上，列車幾乎看不見 | 淺色線改藏青（決策 216 的徽章已這樣做） | S | AS 對比、UT 決策 216 |
| 3-14 | 設定 | `SettingsView.swift:225`、`:228`、`:566`、`:674` | 用系統的 `.secondary`，不是 `Theme.textSecondary` | 對比不是色票算過的那個 | 換成 `Theme.textSecondary` | S | AS 色票 |
| 3-15 | 財務圖表的顏色 | `FinanceTrendCharts.swift:168-177`、`:258` | 圖表的藍、橘、水藍是寫在 View 裡的 `UIColor`，沒在 UI_THEME 的「刻意保留」；`Color.accentColor` 應為 `Theme.primary` | （外觀一致性） | 搬進 `Theme`，對比寫進 UI_THEME，或標「Theme: kept」 | S | AS 色票 |
| 3-16 | 檢視卡、運用表的小字 | `InspectorView.swift:406`（10 點）、`:527`、`:540`（9 點）；`TrainRosterView.swift:236`（9 點） | 寫死字級 | 數值會跟著放大，「時速、下一站、載客」的標題不會 | `.caption2` 或 `@ScaledMetric` | S | HIG Dynamic Type |
| 3-17 | 列車運用表的列 | `TrainRosterView.swift:200`；`Sources/GamePresentation/TrainRoster.swift:286-288`（44／26 點） | 名稱格固定 44 點高、放三行字 | 大字時被切掉，營收那行消失 | 列高用 `@ScaledMetric`，或大字時少一行 | M | SP resizability |
| 3-18 | 型錄的四格數字 | `RollingStockCatalogView.swift:139-145` | 四格一排 | 375 點、大字時標題縮到 80% 後被截斷 | `ViewThatFits` 退成 2×2（下面的購買列已這樣做） | S | SP、TS 手機兩欄 |
| 3-19 | 型錄的價格 | `RollingStockCatalogView.swift:222` | 「買不起」只把價格變紅 | 色弱玩家看不出買不起 | 加字或圖示（「錢不夠」），也放進 VoiceOver | S | WCAG 1.4.1、UT 不只靠顏色 |
| 3-20 | 型錄的縮圖 | `RollingStockCatalogView.swift:270-300` | 選中只有 2 點外框，沒有 `.isSelected` | VoiceOver 不知道現在看的是哪一款 | 加 `.isSelected` | S | SP accessibility |
| 3-21 | 財務面板的帳目 | `EconomyPanel.swift:589` | `ForEach(… id: \.offset)`，清單從上面長 | 每次結算整列重認，VoiceOver 的焦點會跳 | 穩定的 id（GamePresentation 給） | S | SP performance |
| 3-22 | 財務面板的趨勢 | `EconomyPanel.swift:168` | 每個 tick 重算 `FinanceHistory.make` 與三張圖；資料一天才變一次 | 面板開著時白白耗電、掉幀 | `TickStable` 或 `.task(id: day)` | S | SP performance |
| 3-23 | 財務面板的借款 | `EconomyPanel.swift:293-310` | 借款、還款並排，沒有窄的排法 | 手機大字時「償還 $ 1,000,000」斷行或被截斷 | `ViewThatFits` 退成上下排 | S | SP resizability |
| 3-24 | 票價的步進器 | `EconomyPanel.swift:358`、`:374` | 0–10,000，一格 25 分，共 400 格 | 從 $5 調到 $20 要按 60 下 | 加常用票價的選單或直接輸入；或數值越大一格越大 | S | HIG 步進器只給小範圍 |
| 3-25 | 車隊總覽的摘要卡 | `FleetOverviewSheet.swift:190-226` | 三個數字加分隔線一排 | iPhone SE 最大字級時換行或被切 | `ViewThatFits` 或 `Grid` | S | SP resizability |
| 3-26 | 月報 | `MonthlyReport.swift:110-122` | ▲▼ 加顏色 | VoiceOver 讀「黑色向上三角形 18%」 | 標籤改成「比上月多 18%」 | S | SP、TS 變化量寫跟什麼比 |
| 3-27 | 新聞紀錄 | `NewsLogView.swift:75`、`:96` | 新的只有字比較粗 | 看不出哪幾則是新的；VoiceOver 也不說 | 加「新」的膠囊，也放進 VoiceOver | S | WCAG 1.4.1 |
| 3-28 | 車站面板 | `StationPanel.swift:58-91` | 一張表單疊了約 20 段（營運、商店、看板、旅程、月台、土地、道路、公車、需求、活動、運量、旅客、貨運、拆除…） | 找拆除或貨運要捲很久；PLAYER_FEEDBACK 也有「拆除月台找不到」（#516） | 少用的段落收進 `DisclosureGroup`，或工具列加「跳到」選單（已有 `ScrollViewReader`） | M | TS「一個畫面一個問題」、SP `inspector()` |
| 3-29 | 賣車的確認 | `TrainControls.swift:74-83`；`FleetOverviewSheet.swift:146-153` | 「可取回帳面價值的 70 %」：解釋算法與會計用語，按鈕已經寫出金額 | 多讀一句玩家用不到的話 | 「可取回 $X。」 | S | UT 玩家看的文字 §2 |

### 2.3 程式整體的數字

`RailwayGameApp/Views/`，`main` `cc0256c`，用 grep 數的：

- **已經普遍做的**：
  - `accessibilityLabel` 142 處；
  - `monospacedDigit` 196 處；
  - `ViewThatFits` 17 處；
  - `confirmationDialog` 13 處；
  - 觸覺回饋集中在 `GameAudio` 的 `sensoryFeedback`。
- **一處都沒有**：
  - `accessibilityChartDescriptor`；
  - `accessibilityDifferentiateWithoutColor`；
  - `accessibilityInputLabels`；
  - `accessibilityShowsLargeContentViewer`；
  - `contentTransition(.numericText())`；
  - UI 測試的 `performAccessibilityAudit()`。
- **要看一下的**：
  - `.font(.system(size:` 32 處（扣掉 `StationStampPassportView` 依畫布大小縮放的幾處，其餘多半該改）；
  - `lineLimit(1)` 80 處，`minimumScaleFactor` 40 處；
  - `Color.red`／`.white` 這類系統色 16 處（部分是「Theme: kept」）。

### 2.4 已經做得好的

- **狀態列寬度固定**：遊戲在跑時暫停鈕不會在手指下移動（決策 251 的 `WidestTextRoom`、四種 `ViewThatFits`、等寬數字）。
- **觸控範圍**：44 點是刻意做的，程式註解記著當初 CI 抓到的漏網。
- **動態**：集中在 `MotionRule`；狀態訊息的跳與搖、載入畫面都有接減少動態效果。
- **VoiceOver**：
  - 圖示鈕大多有標籤，裝飾圖藏起來；
  - 狀態訊息會讀出來；
  - 教學標題會拿到焦點；
  - 車站每小時人流圖有 `accessibilityAdjustableAction`。
- **不只靠顏色**：狀態膠囊有圖示與字，擁擠度用一到三個人，連假把時鐘換成旗子。
- **效能**：會一直更新的 HUD 依讀的資料拆開；運用表、運行圖、運量在背景算；`TickStable` 讓選單在遊戲跑時不跳。
- **空的狀態**：空的路線與列車有插圖，新聞用 `ContentUnavailableView`，搜尋沒結果有字。

---

## 3. 五方排序

把第 2 節的 52 項併成 16 件工作，照 NEXT_PRIORITIES §19 的權重打分：玩家 30%、開發 25%、美術 15%、鐵道迷 15%、音樂 15%。每方 1–5 分；同分先看玩家，再看開發，再看鐵道迷。

| 名次 | 工作 | 含 | 大小 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --: | --- | --- | --- | --: | --: | --: | --: | --: | --: |
| 1 | **C 深色模式的白字配紅底** | 2-1 | S | 4 | 5 | 3 | 1 | 1 | **3.20** |
| 2 | **D 手機畫面太擠** | 2-3、2-20、2-22 | M–L | 5 | 3 | 4 | 1 | 1 | **3.15** |
| 3 | **H 圖表讀錯與聽不到** | 3-7、3-8 | M | 4 | 3 | 3 | 3 | 2 | **3.15** |
| 4 | **P 事件×通道回饋稽核**（rshankras `feedback-audit.md`） | 新的 | M | 3 | 3 | 3 | 2 | 5 | **3.15** |
| 5 | **A 移除類動作沒有確認、復原又會被 tick 清掉** | 2-17、3-1 | M | 5 | 4 | 1 | 2 | 1 | **3.10** |
| 6 | B 觸控範圍小於 44 點 | 2-2、2-4～2-10、3-2、3-3 | M（每處 S） | 5 | 4 | 2 | 1 | 1 | 3.10 |
| 7 | O 無害的動作用紅色 | 2-21 | S | 3 | 5 | 4 | 1 | 1 | 3.05 |
| 8 | N 車站面板 20 段 | 3-28 | M | 4 | 3 | 3 | 3 | 1 | 3.00 |
| 9 | G 玩家文字：內部編號、色碼、算法 | 2-14、2-15、3-10、3-29 | S | 4 | 4 | 2 | 2 | 1 | 2.95 |
| 10 | E 繞過 `MotionRule`、不看減少動態效果 | 2-11、3-11、3-12 | S | 3 | 4 | 4 | 1 | 1 | 2.80 |
| 11 | M 載入畫面沒有進度與取消 | 2-23 | M | 4 | 3 | 3 | 1 | 1 | 2.70 |
| 12 | K 每個 tick 重算 | 2-19、3-21、3-22 | M | 4 | 4 | 1 | 1 | 1 | 2.65 |
| 13 | F 陰影、色票外的顏色 | 2-12、3-13、3-14、3-15 | S | 2 | 4 | 5 | 1 | 1 | 2.65 |
| 14 | L 運行圖、票價不好調 | 3-9、3-24 | S–M | 3 | 3 | 1 | 4 | 1 | 2.55 |
| 15 | I 大字時被切、寫死字級 | 2-13、3-5、3-16、3-17、3-18、3-23、3-25 | M | 3 | 3 | 3 | 2 | 1 | 2.55 |
| 16 | J VoiceOver 細節 | 2-18、3-4、3-6、3-19、3-20、3-26、3-27 | M | 3 | 4 | 1 | 1 | 1 | 2.35 |

**前五名各方的理由**：

**1. C（2-1）**

- 玩家：深色模式下快破產的倒數讀不到，偏偏是最要緊的訊息。
- 開發：兩行，換成色票已有的 `onError`，確定是對的。
- 美術：回到色票算過的組合。
- 鐵道迷：無。
- 音樂：無。

**2. D（2-3、2-20、2-22）**

- 玩家：「手機上太擠、卡片太大」已有 4 位提到，是累計最多的設計意見。
- 開發：要加 GamePresentation 的寬度邏輯與測試，也要截圖確認，比較大。
- 美術：地圖露出越多，畫面越接近 SimCity BuildIt 的方向。
- 鐵道迷：無。
- 音樂：無。

**3. H（3-7、3-8）**

- 玩家：運量圖上的利潤線沒有圖例，會讓人做錯決定。
- 開發：資料已在 `FinanceHistory`、`LineReport`，改的是畫法。
- 美術：圖例要和線對得上。
- 鐵道迷：路線的運量與收支是經營的核心數字。
- 音樂：Audio Graph 用音高念出圖表，是畫面以外的聲音通道。

**4. P（新的稽核）**

- 玩家：列車到站、賺錢、被拒絕，有沒有聲音與觸覺，各事件一致嗎？
- 開發：先出一張表，不改程式。
- 美術：畫面上的回饋和 `MotionRule` 一起看。
- 鐵道迷：到站與發車的提示音可以照真實的做。
- 音樂：唯一直接檢查音效與觸覺的一件。

**5. A（2-17、3-1）**

- 玩家：一點就清空時刻表，遊戲在跑時救不回來。
- 開發：照現有的拆站、賣車加確認框；改復原要動 `GameSession`，要另外評估。
- 美術：確認框沿用系統樣式。
- 鐵道迷：時刻表是鐵道迷花最多時間的東西。
- 音樂：無。

**其他排法**（沒選）：

- **只看「確定是 bug」的**（C、A、3-7）：漏掉玩家最常說的 D。
- **把 B 的 44 點全部排第一**：每處都小，但加起來要改十幾個檔、要截圖確認，不如先做確定的 C 與最常被提的 D。

**10/31 之前**：照派工，不合會改畫面的 PR。C、O、G、E、F 都是 S，適合 10/31 之後併成一個「畫面小修」PR。A、D、H 各自一個 PR。

---

## 4. 哪些規則值得搬進 `.claude/skills/`（只建議，不搬）

### 4.1 建議搬：新的 `ui-review` skill

**時機**：做或審任何畫面之前讀，像 `motion` 的做法。

**寫法**：

- 改寫成我們的版本，衝突的部分拿掉，並列出「不採用」。
- 資料夾裡放各來源的 MIT 授權全文，`SKILL.md` 寫出處與 commit。

**內容**：

1. **觸控與字級**（rshankras `ios/ui-review/hig-checklist.md`、`design/typography/SKILL.md`；SwiftUI Pro `references/accessibility.md`、`resizability.md`）：
   - 觸控範圍 44 點；
   - Dynamic Type 的四步處理順序；
   - 窄的地方用 `ViewThatFits`；
   - 用 `Button` 不用 `onTapGesture`；
   - 圖示鈕要有文字標籤；
   - 「不以顏色區分」的設定。
2. **資料畫面的數字**（taste-skill `references/app-screens.md`）：
   - 靠右、等寬、帶正負號；
   - 變化量寫跟什麼比；
   - 零與沒有資料分開寫；
   - 圖例對得上；
   - 空的、載入中、錯誤的狀態保留框。

   只拿這些，它的字體、配色、細框、玻璃禁令不拿。
3. **截圖檢查的方法**（taste-skill `references/critique.md` 與 `app-screens.md` §2.7）：見第 5 節。
4. **回饋稽核表**（rshankras `design/game-feel/feedback-audit.md`）：事件 × 畫面／觸覺／聲音，附檔案與行號，最後在實機確認。
5. **Liquid Glass**（rshankras `design/liquid-glass/SKILL.md`）：
   - 只用在浮動控制；
   - 不疊玻璃；
   - 好幾塊放在一起時包 `GlassEffectContainer`。
6. **審查的寫法**：
   - 問題要有三樣才算：規則、證據、一個改法（ibelick `improve-ui`）；
   - 分成這個 PR 新加的、改壞的、本來就有的（jakubkrehel `interface-review`）。

### 4.2 建議補進 `docs/UI_THEME.md`「玩家看的文字」，不另開 skill

jakubkrehel `better-writing` 與 rshankras `ux-writing`（MIT，註明出處）：

- 按鈕用動詞開頭。
- 錯誤訊息說怎麼修。
- 確認框的按鈕寫出動作與對象。
- 整句帶佔位與複數，不拼字串。
- 刪掉「輕鬆、只要」這類贅字。

這些和現在的六條相容。

### 4.3 建議做成 Linux 的檢查（之後的工作，要規劃決定）

- 把 raintree `packages/core/src/patterns.ts`（MIT）的 Swift 規則改寫成 `tools/` 下的 Python 檢查，跑在 `RailwayGameApp/Views/`。查的寫法：
  - `.font(.system(size:`
  - `Color.red`、`.white` 這類系統色
  - `.onTapGesture`
  - 寫死的 `.spring(`、`.easeInOut(`
  - `withAnimation {` 沒帶 `MotionRule`
- 先只報告、不擋 CI。
- 不加新的依賴。

### 4.4 只引用，不搬

- **Apple HIG 原文**（raintree 的 `references/`，© Apple）：連到 Apple 的網頁。
- **ebuntario**：作者自己的改寫，好讀，但和決策 121、`Theme` 有衝突，只當連結。
- **CVS Health**（Apache-2.0）：逐項做法很好，查的時候看就好。它的 `a11y-check` 要加進 CI 是新的依賴，要作者同意。
- **Game Accessibility Guidelines、Xbox Accessibility Guidelines**：沒有授權，只引用想法。
- **SwiftUI Pro** 的 iOS 27 部分：等專案的最低版本到了再說。
- **taste-skill** 的網頁部分與腳本：用不上。

---

## 5. 之後的步驟：截圖檢查

repository 裡沒有 App 的實際截圖：

- `docs/art/` 是設計預覽；
- 網站的截圖只在 `website-screenshots.yml` 的 artifact 裡；
- 先前的實機截圖照 `UX_REDESIGN_STUDY.md` 不放進 repo。

所以這次沒做截圖檢查，也照派工沒跑 macOS workflow。

**10/31 之後**，用下面其中一種取得截圖：

- 在 `website-screenshots.yml` 的分支上跑一次；
- 用 TestFlight 實機截圖。

每個主要畫面拍 iPhone SE 寬、iPhone Pro、iPad 三種，各拍淺色、深色、最大字級。

照 taste-skill `critique.md` 的方法改成 App 版：

1. **只看截圖，不看程式。**
2. **逐項看**：
   - 一秒、五秒各看一次；
   - 瞇眼看；
   - 數左邊的對齊線；
   - 留白與外框；
   - 字；
   - 顏色比例；
   - 重複感；
   - 手機上的樣子；
   - 東西互相疊到。
3. **回答 `app-screens.md` §2.7 的七個問題**：
   1. 最大的那塊是不是回答這個畫面的問題？
   2. 各塊的邊有沒有對齊？
   3. 顏色是不是只用在資料上？
   4. 數字加起來對不對、有沒有對齊？
   5. 零看起來像零、沒有資料看起來像「—」嗎？
   6. 圖例和線對得上嗎？
   7. 每一塊在手機上還能用嗎？
4. **每輪寫出最嚴重的三個問題**，附截圖與改法；最多三輪。
5. **改的順序**：想法、層次、構圖、字、圖、顏色、細節、動態。

第 2 節標 UNVERIFIED 的項目在這一步確認或刪掉。尤其是：

- 2-3、2-20：手機太擠；
- 2-16：直拿時的細節卡；
- 2-22、3-5、3-17、3-18、3-23、3-25：大字被切。
