---
name: ui-review
description: 畫面怎麼做、怎麼審：觸控範圍與字級（Dynamic Type）、資料畫面的數字、轉 ready 前必做的截圖驗收、回饋稽核表（畫面／觸覺／聲音）、Liquid Glass、審查的寫法、SwiftUI 效能。做或改任何 SwiftUI 畫面、面板、清單、圖表之前先讀，也用於審查畫面。Use before building or changing any SwiftUI screen, panel, list or chart in the app (RailwayGameApp/Views), and when reviewing a screen or a pull request's interface changes; a screen change takes the screenshot review before it is marked ready.
---

# 畫面的做法與審查

做或改 App 的畫面（`RailwayGameApp/Views/`）之前讀這份；審別人的畫面也照它。它和另外兩份一起用：

- 畫風（顏色、外框、圖示）：`.claude/skills/art-style/SKILL.md`。
- 動態（動畫、轉場、減少動態效果）：`.claude/skills/motion/SKILL.md`。
- 顏色、對比、玩家看的文字：`docs/UI_THEME.md`。

三者衝突時以它們為準，這份不重複它們的規則。研究與健檢在 `docs/research/UI_UX_REVIEW_2026-10-28.md`，決策 482。

## 出處

規則改寫自下面五個專案，都是 MIT，授權全文在本資料夾的 `licenses/`。只拿相容的想法並改寫成我們的版本，不整段搬；和我們規則衝突的部分在第 8 節。

| 專案 | commit | 讀的檔 | 授權全文 |
| --- | --- | --- | --- |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `12af471` | `skills/taste-skill/references/app-screens.md`、`critique.md` | `licenses/taste-skill.txt` |
| [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill)（SwiftUI Pro） | `f2920b6` | `swiftui-pro/references/accessibility.md`、`resizability.md`、`performance.md` | `licenses/swiftui-agent-skill.txt` |
| [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) | `9ffb831` | `skills/ios/ui-review/hig-checklist.md`、`design/typography/SKILL.md`、`design/game-feel/feedback-audit.md`、`design/liquid-glass/SKILL.md` | `licenses/claude-code-apple-skills.txt` |
| [ibelick/ui-skills](https://github.com/ibelick/ui-skills) | `59193a7` | `skills/improve-ui/SKILL.md` | `licenses/ui-skills.txt` |
| [jakubkrehel/skills](https://github.com/jakubkrehel/skills) | `592aedc` | `skills/interface-review/SKILL.md` | `licenses/jakubkrehel-skills.txt` |

只看想法、沒有搬文字的（沒有寬鬆授權，或是別人的原文）：

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)（© Apple）。
- [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/)（GAG，網站沒寫授權）。
- [Xbox Accessibility Guidelines](https://learn.microsoft.com/gaming/accessibility/guidelines)（XAG，頁面沒寫授權）。
- [cvs-health/ios-swiftui-accessibility-techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques)（Apache-2.0）：查的時候去看，不搬。

## 1. 觸控與字級（touch targets、Dynamic Type）

- **觸控範圍至少 44×44 點**。圖示小的按鈕用 `TouchTargetButtonStyle`（`HUDView.swift`）把範圍撐開，不放大圖示。
- **用 `Button`，不用 `onTapGesture`**：`Button` 才有 VoiceOver 的按鈕語意、鍵盤與指標的操作、按下的樣子（`ThemeSelectableButtonStyle` 等）。
- **只有圖示的按鈕也給文字**：`Button("…", systemImage:)` 加 `.labelStyle(.iconOnly)`，或 `.accessibilityLabel`。標籤會一直變的（例如狀態列上即時的數字），加 `accessibilityInputLabels` 給語音控制一個固定的名字。
- **Dynamic Type 照這個順序處理**（rshankras `typography`）：
  1. 用文字樣式（`.body`、`.headline`…），不用 `.font(.system(size:))`；固定大小只給依畫布縮放的東西（例如 `StationStampPassportView`）。
  2. 跟著字變大的間距、圖示用 `@ScaledMetric`。
  3. 字放到輔助使用的大小時，用 `AnyLayout`（`dynamicTypeSize.isAccessibilitySize`）把橫排改直排。
  4. 最後才用「大型內容檢視器」（`accessibilityShowsLargeContentViewer`）：給不能跟著放大的 HUD 按鈕。
- **窄的地方用 `ViewThatFits`**，不要靠 `lineLimit(1)` 加 `minimumScaleFactor` 把字縮到看不清；少用 `.caption2`。狀態列已經這樣做（決策 251 的 `WidestTextRoom`）。
- **iPad 與 iPhone 分版面**：依 `horizontalSizeClass == .regular` 分，狀態放在分支外面，換方向時才不會重設。
- **不只靠顏色**：尊重「不以顏色區分」（`accessibilityDifferentiateWithoutColor`）；狀態要有圖示或字（UI_THEME 已有的做法：狀態膠囊、擁擠度的人數）。
- **字疊在地圖上**：對比用背景最差的那一塊算（XAG 的想法），3D 地圖上的字尤其要看。

## 2. 資料畫面的數字（taste-skill `app-screens.md`）

財務、路線、車隊、時刻表、車站、圖表都算：

- **一個畫面回答一個問題**，最大的那塊就是答案；最重要的一個數字放在標題下面；最常做的事一次點到。
- **數字的排法**：靠右、等寬數字（`monospacedDigit()`）、固定小數位、千分位；變化量帶正負號。用 `Text(value, format:)`，不在 body 裡建 formatter。
- **變化量寫跟什麼比**（「比上個月」「比昨天」）。變化的顏色表示好壞，不表示漲跌；零或算不出來的變化用次要色。
- **同一個數字出現兩次要來自同一個值**；總數用畫面上顯示的數字加得起來。
- **零和沒有資料分開**：真的零寫 0；沒有資料寫次要色的「—」。
- **圖例對得上**：同一份資料在不同圖上同一個顏色；圖上面一行摘要；加 `accessibilityChartDescriptor`。
- **空的、載入中、錯誤**：都保留原本那塊的框，不讓版面跳；載入中用平的佔位，不用閃光；空的狀態告訴玩家下一步（不是死路）。
- **清單**：總覽只列 4–6 列再加「看全部」；不用斑馬紋；手機上表格改成兩行的列。
- **顏色只用在資料、狀態和唯一的主要動作**，而且只從 `Theme`／`Palette` 取（第 8 節）。

## 3. 截圖驗收（必做；作者要求，避免畫面做醜）

**改畫面的 PR 轉 ready 之前一定要做**。方法改寫自 taste-skill `critique.md` 與 `app-screens.md` §2.7（研究第 5 節）。

**拍**：

1. 在自己的分支手動跑 `website-screenshots.yml`（Actions 分頁，選自己的分支）。它在 iPhone Pro Simulator 上橫拿、深色模式，跑 `WebsiteScreenshotTests`，PNG 在 artifact `website-screenshots`。
2. 改的畫面沒被拍到，就在 `RailwayGameApp/UITests/WebsiteScreenshotTests.swift` 加一個 `test…` 方法：打開那個畫面，用 `keep("名字", app)` 留下來（每張匯出成 `名字.png`）。
3. **一次只跑一個截圖 run**：macOS runner 只有五台，full lane 佔四台。別的 session 的截圖 run 還在跑就等它。
4. 這個 workflow 只拍 iPhone Pro、橫拿、深色。iPhone SE 寬、iPad、淺色、最大字級拍不到的，在 PR 寫「沒拍到」與原因（UNVERIFIED），有實機截圖時再補。

**看**（每一輪）：

1. **只看截圖，不看程式**：看程式會把自己的意圖讀進去。
2. **逐項看，一項看一次**：一秒、五秒各看一次（看到的是什麼？）；瞇眼看（應該剩兩三大塊）；數左邊的對齊線（兩三條）；留白與外框；字的大小層級；顏色比例；重複感；手機上的樣子；東西互相疊到（地圖標籤、泡泡、按鈕）。
3. **回答七個問題**：
   1. 最大的那塊是不是回答這個畫面的問題？
   2. 各塊的邊有沒有對齊？
   3. 顏色是不是只用在資料上？
   4. 數字加起來對不對、有沒有對齊？
   5. 零看起來像零、沒有資料看起來像「—」嗎？
   6. 圖例和線對得上嗎？
   7. 每一塊在手機上還能用嗎？
4. **寫出最嚴重的三個問題**，各附截圖與一個改法（第 6 節的三樣），然後修掉，再拍下一輪。**最多三輪**；三輪後還有的寫進 PR 與決策的下一步。
5. **改的順序**：想法、層次、構圖、字、圖、顏色、細節、動態。

**交**：

- PR 放**最後一輪的總覽圖**（幾張拼成一張），以及**每一輪發現與修掉的問題**（輪次、問題、改法、commit）。圖大於約 2 MB 時照 CLAUDE.md 放 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/`，PR 只留總覽與連結。
- **規劃看過截圖才合**。

## 4. 回饋稽核表（rshankras `feedback-audit.md`）

改到玩家做事的回饋（建造、被拒絕、到站、收入、警訊、升級）時，列一張表：

| 事件 | 畫面 | 觸覺 | 聲音 | 判斷 |
| --- | --- | --- | --- | --- |
| 例：放好月台 | `BuildPulseMark` 的環（`builtRing`） | `.success` | — | 兩個通道，OK |

- 每格寫**程式裡真的有的**，附 `檔案:行號`；沒有就寫「—」。
- 越少見、越重要的事件回饋越大，兩個通道以上；例行的事件一個就夠。
- **一個事件只由一層負責回饋**：不要地圖和面板各播一次（決策 184 之後的修正：地圖與面板的同一則訊息，VoiceOver 只念一次）。
- 數字的變化不要瞬間跳：`.contentTransition(.numericText())`，時間照 `MotionRule`。
- 每個效果在「減少動態效果」打開時都要有對應（motion skill 第 3 節）；觸覺不受「音效」開關影響，由系統設定決定（`GameAudio`）。
- 聲音與觸覺的感覺只能在實機確認（Simulator 不放觸覺），表的最後一列寫「實機確認：未做／做了（版本）」。

## 5. Liquid Glass（rshankras `liquid-glass`）

- **只用在浮在地圖上的控制**（狀態列、工具列、浮動按鈕），不用在清單、列、內容上。我們的入口是 `Theme.swift` 的 `glassBackground(in:interactive:)`，iOS 26 以前退回系統材質。
- **不在玻璃上疊玻璃**：玻璃上的東西用實心色票，不再加材質。
- **好幾塊玻璃放在一起時包進 `GlassEffectContainer`**，讓它們一起算、一起變形。
- **只有主要動作上色**（tint）；全部上色就沒有重點。
- 不讓內容半壓在玻璃下面停著。
- 「降低透明度」「增加對比」打開時，系統的 `glassEffect` 與 `.regularMaterial` 會自己變不透明；自己畫的半透明底要自己接上 `accessibilityReduceTransparency`。

## 6. 審查的寫法（ibelick `improve-ui`、jakubkrehel `interface-review`）

審一個畫面或一個 PR 的介面時：

- **一個問題要有三樣才算**：
  1. 違反哪一條規則（這份、art-style、motion、UI_THEME、HIG 的哪一條）；
  2. 證據：那個值真的畫到畫面上（`檔案:行號`，有截圖更好）；
  3. 正好一個改法，用現有的 `Theme`、`MotionRule`、元件。
  三樣少一樣就不報；改法有兩種以上，表示證據不夠。
- **報之前先試著推翻每一個**：重新打開引用的程式，看是不是刻意的（UI_THEME 記下的例外、決策寫的取捨）。
- **依原因分三類**：這個 PR 新加的、這個 PR 改壞的（看 diff 的 `-` 那一邊：拿掉的標籤、觸控範圍、`reduceMotion`）、本來就有的。審 PR 時主要報前兩類，本來就有的最多提三個。
- **找沒做完的改動**：新字串沒進 `Localizable.xcstrings`；少了空的、載入中、錯誤、停用的狀態；iPad 或最大字級沒處理；新動畫沒接減少動態。
- **能在 Linux 測的邏輯先搬到 GamePresentation**（選單列什麼、卡片放哪、什麼時候換步），UI 測試只留「看得到、點得到」（CLAUDE.md）。

## 7. SwiftUI 效能（改寫自 SwiftUI Pro `references/performance.md`）

遊戲在 6000× 時每秒好幾個 tick，`GameSession` 每次變都會讓讀它的 view 重算。規則：

- **body 要輕**：body 會被呼叫很多次。排序、篩選、找路、建 `LineMap` 這類工作不放在 body 和 view 的 init 裡；建 formatter 也不要（用 `Text(value, format:)`）。
- **昂貴的東西算一次、記起來，並寫清楚什麼時候失效**：
  - 本專案的做法是 `GameSession` 的 memo：一個指令之後（`commandRevision`）或隔一段遊戲時間才重算，例如 `situationAlerts`、`trackInspection(of:)`（`PerFrameMemoTests`，ARCHITECTURE 決策 184 之後的修正「每一幀重算的工作」）；站長建議照 `stationMasterRefreshKey`。
  - 不要在 `@State` 裡存一份推導出來的集合卻沒有失效的條件（畫面會停在舊的）。
  - 遊戲在跑時要停住的部分（打開著的 `Menu`、做成選單的 `Picker`），包進 `TickStable(key)`：只在 key 變時重畫，內容從 key 裡的值建，不讀 `session.world`（`TickStable.swift`，決策 184 之後）。清單的順序在打開或換排序時固定，不每個 tick 重排（車隊總覽的 `GameWorld.fleet(keeping:)`）。
- **重的工作在背景算好，再交給主執行緒**：每個 tick 的推進與它要的讀數，在 `GameSession.LoopTick` 的 `work()` 裡、主執行緒外算好，`finish(_:with:)` 才在主執行緒換上（例如 #1470 把地圖「卡住」泡泡的死結搜尋移進去，決策 379 第 4 段把列車滑行移進去）。新的每個 tick 都要的貴東西，先想能不能放進這裡。
- **量，不要猜**：會一直更新的 view 用 `timed(.part) { … }` 包 body（`MapView.swift` 的 `timed`、`FrameCostPart`，決策 379），在「設定 › 地圖 › 幀數」讀「畫面更新」與各分項。Linux 上用 release 測試量 GamePresentation 的讀數（決策 379 的 `FastForwardReadsReportTests`）。
- **依讀的資料拆 view**：狀態列已經依錢、時間、天氣拆開（`HUDView`）；一個 view 只讀它要的，別讓整個面板因為一個數字重算。
- **`ForEach` 的 id 要穩定**：用東西自己的 ID（車站、列車、路線的 `id`），不用陣列的位置（`\.offset`、`indices`），也不用每次重建的 `UUID()`。每列只傳它自己的資料（`Row(train: train)`），不要傳整個 session 加索引，否則一列變全部重算。
- **列的形狀固定**：lazy 容器裡每個元素產生同樣數量、同樣種類的 view；要省略的元素在 `ForEach` 前先篩掉，不在列的最上層放 `if`。
- **大清單用 lazy 容器**：`List`、`LazyVStack`、`LazyHStack`；很多子 view 的 `VStack` 放在 `ScrollView` 裡會一次全建。
- **條件放在 modifier 裡**：`.opacity(isOff ? 0.4 : 1)`，不要用 `if/else` 換整個 view（會換身分、重建、打斷動畫）；不要寫 `View.if()` 這種 helper。少用 `AnyView`。
- **變化快的值不放進 environment**（拖曳座標、捲動位置、動畫進度、tick）：每次寫入都會讓底下整棵樹被檢查。放進 `@Observable` 物件，給 view 讀變化少的結果。
- **非同步工作用 `.task`**，不用 `onAppear` 開 `Task`：view 消失時會自己取消。

## 8. 不採用的部分

和本專案規則衝突，以我們的為準（研究的 §1.3）：

| 我們的規則 | 外部專案說的 | 不採用的原因 |
| --- | --- | --- |
| 畫風：扁平、粗藏青外框、圓角、不用漸層與陰影（art-style、決策 84、121） | taste-skill 要 1 px 細框、說統一圓角是破綻、允許浮動選單陰影與折線圖下的漸層、禁止藏青深色主題、要有個性的字體；rshankras 的 MeshGradient、shader 特效 | 畫風是作者選的，藏青與暖黃是圖示的主色；字用系統字配 Dynamic Type |
| 動態：`MotionRule`，減少動態只留淡入淡出（motion、決策 253） | taste-skill「不要進場動畫」、說彈跳是破綻；ibelick「沒要求就不加動畫」；rshankras 的彩帶、慶祝產生器 | 我們有 `cardIn`、`pop` 等規則；慶祝只用輕跳與蓋好的環。rshankras「每個效果都要有減少動態的對應」相容，已收在第 4 節 |
| 顏色只從 `Theme`／`Palette` 取，View 裡不寫色碼（UI_THEME） | rshankras、ebuntario「用系統顏色、不寫色碼」「先用 SF Symbols 不畫自己的圖示」 | 色票本身算過對比（`ThemeContrastTests`）；地圖圖示是決策 121 畫的 |
| Liquid Glass 用在浮在地圖上的控制 | taste-skill 禁止玻璃與模糊 | 只採 rshankras 的用法（第 5 節） |
| 最低版本 iOS 17（`project.yml`） | SwiftUI Pro 假設 iOS 27／Xcode 27（`@ContentBuilder`、`AsyncImage` 快取） | 新 API 放在 `#available` 後面；`@ViewBuilder` 照舊 |
| 網頁的工具 | taste-skill 的 Node／Chrome 腳本、CSS、Tailwind、React | 用不上 |

## 9. 怎麼檢查

1. **Linux**：畫面的邏輯在 GamePresentation 的測試裡（`swift test --skip-build --filter <Class>`）；顏色對比 `ThemeContrastTests`；動態 `InterfaceMotionTests`。
2. **Simulator**（`ios-build.yml`，Linux 上沒有）：UI 測試只問「看得到、點得到」；要看一兩支就用 `only_testing`。
3. **截圖驗收**（第 3 節，轉 ready 前必做）；**實機**：第 4 節的聲音與觸覺。
4. **PR 的寫法**：寫出用了這份的哪幾節、截圖驗收的總覽圖與各輪問題（拍不到的寫 UNVERIFIED 與原因）、回饋表（改到回饋時）。
