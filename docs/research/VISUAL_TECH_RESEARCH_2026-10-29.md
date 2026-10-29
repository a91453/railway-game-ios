# 視覺技術研究：借鏡 DayCity 的微縮城市、時間、天氣與光影（2026-10-29）

派工單 VTR（遊戲規劃第 31 任派，實作 session_01YGNNuoaWqHd4tA1jt2WLGE）。只做研究與文件：不改遊戲程式、不加依賴；決策號、存檔版本、golden 都不動。對照的是 `main` 6ff5ffe。

## 0. 標記方式與結論先講

每一句的性質用三個標記分開：

- **【事實】** 已確認的事實：讀過程式（附 `檔案:行`）、讀過文件，或查過來源（附網址；GitHub 專案的版本與日期是 2026-10-29 用 `git ls-remote --tags` 和淺層 clone 查到的 tag 所在 commit 日期，不是 Release 頁的日期）。
- **【推論】** 技術推論：從事實推出來，但沒有量過。
- **【假設】** 待驗證的假設：要真機或實驗才知道。

**一句話結論**：《沿線》的 3D 已經是自寫的 Metal，日夜、天空、太陽陰影、色調、反光、夜窗、雨天的變暗都有了（第 1 節）。和 DayCity 那種畫面比，差的不是引擎，而是三件事：

1. 太陽照真實的經緯度與日期走：現在是固定的 06:00 升、18:00 落。
2. 雨真的落在場景裡：現在是畫在 3D 上面的一層 SwiftUI `Canvas`。
3. 黃昏與夜晚的色彩要有一套看得出來的層次。

這三件都屬於方案 C（混合式），而且都不動 GameCore。真正的瓶頸是效能：作者的基準 36 fps 在 GPU 9.9 ms，已經貼著 `Map3DDrawScale` 的 10 ms 門檻（第 1.6 節），所以任何加畫面的東西都要先付得起。

**最值得先驗證的 3 個方案**（第 6 節）：

1. 先把 36 fps 的原因量清楚，同時把「時段×天氣」加進現有的畫面節奏測試。
2. 照真實日期與經緯度的太陽。
3. Metal 裡的雨，用 instanced 雨絲做，會被樓擋住，用來取代 `Canvas`。

## 1. 現況（只寫查過的）

### 1.1 渲染技術

- **【事實】** 3D 地圖是自寫的 Metal：`final class Map3DMetalView: MTKView`（`RailwayGameApp/Views/Map3D/Map3DMetalView.swift:20`），每幀在 `draw(_:)`（`:914`）。整個 App 沒有 import SceneKit、RealityKit、SpriteKit。
- **【事實】** 著色器只有一個檔：`RailwayGameApp/Views/Map3D/Map3DShaders.metal`。
  - 主要入口：`map3dVertex`、`map3dInstancedVertex`、`map3dFragment`（`:59`、`:80`、`:446`）。
  - 太陽深度：`map3dSunDepth*`（`:495`、`:499`、`:569`）。
  - 天空：`map3dSkyVertex`／`map3dSkyFragment`（`:625`、`:640`）。
  - 團狀影子：`map3dShadow*`（`:586`、`:595`）。
  - 招牌：`map3dSign*`（`:700`、`:742`）。
- **【事實】** 一幀的 pass 是這樣排的：
  - 太陽陰影的深度 pass 只在需要時才畫（`Map3DMetalView.swift:1010-1011`）。
  - 接著是一個主 pass，依序畫不透明幾何、天空（遠平面，`:1190-1194`）、最後疊團狀影子（`:1202-1219`）。
  - 沒有後製 pass。色調映射在 fragment 的最後做（`map3dFinish`，`Map3DShaders.metal:133-148`）；決策 356 寫明反光「不加 render pass、不做 SSR 或鏡面相機」（`docs/decisions/356.md:9`）。
- **【事實】** 畫面格式：
  - 顏色 `bgra8Unorm`、深度 `depth32Float`、反向深度（`Map3DMetalView.swift:401-405`）。
  - MSAA 4×，省電時 1×（`:249`、`:403`；`Sources/GamePresentation/Map3DQuality.swift:48`）。
  - `preferredFramesPerSecond` 60 或 30（`Map3DMetalView.swift:406`、`:570`；`Map3DQuality.swift:113-117`）。不支援 120 Hz（`docs/decisions/417.md:147`）。
- **【事實】** 材質是頂點顏色加兩張圖集：`Map3DSurfaces.png`（2D 陣列，每層 256²，`Map3DMetalView.swift:600-628`）與 `Map3DSigns.png`（2048²，`:634-660`）。模型多半是 Swift 寫的程序配方（`Sources/GamePresentation/Map3D*Kit*.swift`）。另有 11 個 `.m3dmodel`（約 404 KB，由 `tools/glb-to-m3dmodel/` 從 GLB 轉），格式在 `Sources/GamePresentation/Map3DModelFile.swift:3-25`。
- **【事實】** 2D 地圖：
  - 底圖是 MapLibre（`project.yml:33-35` exactVersion 6.31.0，是 App 唯一的外部套件；`Package.swift:14-21` 沒有依賴）。
  - 底圖的深淺跟系統外觀走，不跟遊戲時間（`RailwayGameApp/Views/OSMMapBackground.swift:60-70`）。
  - 遊戲裡的晝夜是一層 multiply 色（`MapView.swift:344`、`:431-433`；`Sources/GamePresentation/DayNight.swift:92-106`）。

### 1.2 時間、太陽、光

- **【事實】** 光照由 `Map3DLighting` 決定（`Sources/GamePresentation/Map3DCamera.swift:298-486`）。
  - 依遊戲時刻用 10 個關鍵幀，決定天頂、天空、太陽、地面、環境光、太陽強度與夜（`:329-340`）。
  - 唯一的輸入是一天中的第幾分鐘（`:343`、`:387`）。
- **【事實】** 太陽方向是簡單曲線，不是天文算式：
  - `angle = π·(hour−6)/12`，仰角 `max(sin, 0.08)·1.15`，固定往南偏 0.45（`Map3DCamera.swift:371-374`）。
  - 夜裡改用固定的月光方向（`:375`），日出日落前後 0.5 小時交換（`:376-379`）。
  - 所以台北與屏東、夏至與冬至的影子一樣長、日出一樣是 06:00。
- **【事實】** 時刻來自 GameCore 的 `GameClock`（`Sources/GameCore/Time/GameClock.swift:108`），由 `Map3DLighting(at: session.world.clock.now)` 讀（`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:79`）。這個時鐘是決定論的，不讀牆上時鐘（`GameClock.swift:104-107`）。
- **【事實】** 已有的光影：

  | 項目 | 決策 | 程式 |
  | --- | --- | --- |
  | 天空穹頂、太陽、月亮、星星（無雲） | 347 | `Map3DSky.swift:4-10`、`:29-52` |
  | 色調映射肩部、調色、貼地薄霧 | 349 | `Map3DGrade.swift:3-23` |
  | 玻璃與水面 Fresnel 反光、水波 | 356 | `Map3DReflection.swift:58-68`、`:141-182` |
  | 太陽陰影貼圖：2048²，16 MB；過熱或超預算時降到 1024²、每秒才重畫 | 357 | `Map3DSunShadow.swift:24-44` |
  | 團狀接地影 | 232 | `Map3DShaders.metal:586-620` |
  | 夜窗、路燈、光圈 | 229／234 續、352、370 | `Map3DShaders.metal:263-277`、`:336-352`、`:396-411` |
  | 列車夜燈 | — | `Map3DTrainLights.swift:3-6` |
  | 列車遮蔽陰影烘焙 | 439 | — |
  | 列車玻璃與不鏽鋼反光 | 450 | — |

- **【事實】** 太陽陰影只在太陽轉超過 0.01 rad 或目標移動超過 25% 時才重畫（`Map3DSunShadow.swift:64-67`）。

### 1.3 天氣

- **【事實】** GameCore 有天氣：`enum Weather { clear, rain, thunderstorm }`（`Sources/GameCore/Passenger/Weather.swift:24-37`）。
  - 每天依月份機率從種子推出來（`:85-88`、`:112-120`），颱風在 180–299 日（`:93-98`）。
  - 不存逐日紀錄（`:15-18`），會影響需求（決策 162）。
- **【事實】** 3D 只有兩種光的預設：晴、雨（`Sources/GamePresentation/Map3DWeather.swift:34-43`）。
  - 雷雨與颱風都當雨（`:48-52`），換天氣用 2 秒。
  - 數值照 town-scene 參考的雨天預設（決策 277）。
  - 陰天與雪不是 GameCore 的天氣（`Map3DWeather.swift:9-10`）。
- **【事實】** 3D 的雨絲是一層 SwiftUI `Canvas`：
  - 外面包 `TimelineView(.animation(minimumInterval: 1/60))`，疊在 Metal 畫面上（`Map3DPreviewScreen.swift:1094-1128`）。
  - 數量 480／260／140 條乘雨量（`Sources/GamePresentation/Map3DRain.swift:76-83`）。
  - 減少動態效果時與隧道裡不畫（`Map3DPreviewScreen.swift:1117`）。
- **【推論】** 這層 `Canvas` 不知道深度，所以雨絲會畫在樓前、車廂裡（駕駛室視角）、高架橋下。而且它在主執行緒上每秒重繪 60 次，和 `MTKView` 搶同一個執行緒（第 1.6 節）。

### 1.4 效能預算與降級

- **【事實】** `Map3DQuality` 有自動、省電、高、關四檔（`Map3DQuality.swift:11-20`、`:109-119`），A14 以前的機器預設關（`:28-35`）。
- **【事實】** 決策 417 的負載階梯：
  - 設備分三級：A12–A14、A15–A16、A17 Pro／M3 起；M 系列升一級（`Sources/GamePresentation/Map3DMotionBudget.swift:41-52`）。
  - 會動的東西的三角形預算是 25 萬、60 萬、100 萬（`:67-73`）。
  - 降的步驟：`full → fewerOnStreets → fewestOnStreets → nearerFarModels → fewerPixels`（`:168-169`）。
  - 半秒一窗。連續 3 窗吃緊就降，20 窗輕鬆才升（`:308-311`）。「吃緊」是 fps 低於目標的 75%，或 GPU 超預算（`:288-290`）。
- **【事實】** `Map3DDrawScale`：GPU 超過一幀的 0.6（60 Hz 時 10 ms）就算超預算，降成每點 2×2 像素（`Sources/GamePresentation/Map3DDrawScale.swift:11-15`、`:36-38`）。
- **【事實】** 決策 460 加了記憶體與 CPU 兩軸。據決策 455 的量測，真實城市的場景在 App 裡佔 367–517 MB。

### 1.5 量幀時間的工具

- **【事實】** 畫面上的數字：
  - 由 `statsLabel` 組成（`Map3DPreviewScreen.swift:336-361`）。
  - 「CPU」是 `draw(_:)` 從開始到 commit 扣掉等 drawable 的時間（`Map3DMetalView.swift:1251`）；「GPU」是 `gpuEndTime − gpuStartTime`。兩者都是半秒的中位數（`:1332-1384`）。
  - 「3×」是 `contentScaleFactor`，也就是每點幾個像素（`:1355`）。
  - 「higher full」是 `Map3DLoadLevel.summary`：設備級與街景步驟（`Map3DMotionBudget.swift:240-242`）。
- **【事實】** `FrameTimeRecorder`（決策 421，`RailwayGameApp/App/FrameTimeRecorder.swift:11-19`）：
  - 3D 用 `presentedTime`（`Map3DMetalView.swift:1246`）。
  - 統計有中位數、p95、p99、最長，以及 50／100／250 ms 的停頓（`Sources/GamePresentation/FrameTimeRecord.swift:139-172`）。
  - 「設定 → 回報問題」會附上這些（`SettingsView.swift:698-704`）。
- **【事實】** 畫面節奏測試 V2（`Sources/GamePresentation/FrameTimeBench.swift:17-35`；`RailwayGameApp/App/FrameTimeBenchRunner.swift`；`Tests/GamePresentationTests/FrameTimeBenchTests.swift`）：
  - 台北車站，1／5／10／20 條線 × 2D 平移、3D 環繞、3D 跟車（從後面），每項 60 秒、先跑 5 秒、跑 3 次。
  - 入口：設定裡點版本五下，演示模式出現後的「畫面節奏測試」（`docs/decisions/421.md:35`）。
  - 它**沒有**駕駛室視角，也不能指定時段或天氣。
- **【事實】** 沒有用 `OSSignposter`、MetricKit、WidgetKit、SpriteKit，也沒有影像快取或截圖比對的套件。
  - 預覽圖靠 `tools/map3d-preview/`：用 WebGL 照同一套算式在無頭 Chromium 裡畫，並用 pixelmatch 比對。它的 README 寫明「不是 Metal、不是 iPhone 的畫面」。

### 1.6 已知問題：作者的基準 36 fps

作者 2026-10-29 在真機上量到：駕駛室視角，10 倍速，36 fps；CPU 4.6 ms、GPU 9.9 ms、wait 0 ms；3×；314 draws；29 萬三角形；higher full。

- **【事實】** 這組數字的意思：
  - 36 fps 是一幀約 27.8 ms。CPU 4.6 + GPU 9.9 就算完全不重疊也只有 14.5 ms，wait 是 0。
  - 3× 是原生像素，higher full 是最高一級、沒有降。
  - 10× 正好是 3D 跟車的上限（決策 360，`Sources/GamePresentation/Map3DFollowSpeed.swift:3-11`）。
- **【推論】** 一幀裡大約有 13 ms 不在 `draw(_:)` 裡，最可能在主執行緒別的地方。`MTKView` 用主執行緒的 display link 叫 `draw`，主執行緒忙時這一幀就跳過，所以 fps 掉了，但 CPU、GPU 的數字看起來還好。
- **【推論】** GPU 9.9 ms 正貼著 `Map3DDrawScale` 的 10 ms 門檻（`Map3DDrawScale.swift:14-15`）。所以：
  - 畫面上再加任何 GPU 工作，自動畫質就會降到 2×；
  - 在「高」畫質下則會直接掉幀。
  - 這是這份研究最重要的限制：**加畫面之前要先騰出預算**。
- **【假設】**（要量）主執行緒那 13 ms 的可能來源：
  1. 10× 時每 100 ms 一個 tick 的結果合回主執行緒，以及 SwiftUI 因此重算的 HUD 與駕駛資訊（決策 403）；
  2. 駕駛室前方的 chunk 串流（決策 358）建場景、上傳緩衝；
  3. 下雨時的 `Canvas`（第 1.3 節）；
  4. 中位數藏住的尖峰：要看 p95、p99 與停頓次數，不能只看中位數。

  第 5 節的第 0 步就是把這幾個分開。

### 1.7 美術與 skill

- **【事實】** 相關的 skill：
  - `.claude/skills/art-style`：畫風；
  - `motion`：介面動畫，以及減少動態效果時怎麼辦；
  - `ui-review`：畫面審查與截圖驗收；
  - `rolling-stock`：列車的近遠景、發光頂點、預算與雜湊。
  - 畫風是「淡色模型」（決策 370、451，`Sources/GamePresentation/Map3DLook.swift:3-20`），整座城一種材質，只有頂點色加圖集（決策 229）。
- **【事實】** 素材管線：
  - 程序配方與 `tools/` 下的各個 kit（station-kit、civic-kit…），輸出七向透明圖給作者看。
  - Meshy 生成的模型轉成每三角形一色、壓低面數後才進遊戲。私庫 `a91453/railway-assets-private` 有 Meshy 批次的經驗整理，結論是先高品質生成、再減面、把顏色收到少數幾種。
  - 參考庫和素材庫裡**都沒有** ComfyUI、ControlNet、Stable Diffusion 或打光重算的管線。

### 1.8 參考庫（私庫）裡有什麼（只寫結論）

- **真實太陽位置**：台灣鐵道網站的 3D 部分有一份照 NOAA 太陽計算公式（公有領域的數學）寫的太陽方位與仰角，輸入是 UTC 時間與經緯度，另有依太陽仰角連續混合天空色與光色的做法。OpenWorld 參考也有簡化版，四季與淡水的日落方位對過。
- **天空與大氣**：OpenWorld 參考有 Rayleigh＋Mie 散射烘成一張小 LUT、太陽移動夠多才重算、自動曝光（夜裡有下限，避免夜景被拉白）、行動裝置用的便宜 HDR 擴散，以及低／中／高／極高四檔畫質。
- **時段與天氣預設**：tw3d 與 slop-taipei（MIT，源自 slop-newyork）有早晨、正午、黃金時刻、暮光、午夜五個時段預設，每個帶太陽角度、顏色、天空、霧、雲量、曝光。天氣以「雲量、變暗、霧」三個數疊上去，不在每幀配置記憶體。town-scene 有晴、陰、雨、雪四種天氣預設，決策 277 已經用了雨天那組。
- **夜景**：night-district 參考有每棟樓「亮燈比例」放進一張資料貼圖、末班車後窗燈漸暗的做法。
- **素材**：預覽圖與宣傳影片素材在素材庫，有遊戲內的白天、黃昏、夜晚錄影，可以當目標畫面。
- **授權**：
  - tw3d 與 slop-taipei 的程式是 MIT，可以改寫並保留聲明。
  - 其他沒附授權檔的是作者自己提供的參考，CLAUDE.md 視為已授權可用。
  - procedural-assets 參考的素材授權**禁止用來訓練或評估生成模型**：它不能進第 2.3 節的 AI 管線，連當 IP-Adapter 的參考圖都不行。

## 2. 七項技術

### 2.1 技術比較表

| 技術 | 最新版（日期） | 程式授權 | 權重授權 | 維護 | 和本作的關係 | 適合度 |
| --- | --- | --- | --- | --- | --- | --- |
| [mourner/suncalc](https://github.com/mourner/suncalc) | v2.1.1（2026-10-05） | BSD-2-Clause | — | 活躍 | 純算式；照它或 NOAA 改寫成 Swift 放 GamePresentation | 高 |
| [ceeK/Solar](https://github.com/ceeK/Solar) | 4.0.1（2026-08-30） | MIT | — | 活躍 | 只算日出日落，用 Foundation＋CoreLocation | 低（功能不夠） |
| [Timac/SunCalc](https://github.com/Timac/SunCalc) | 1.0.0（最後 commit 2025-06-19） | MIT | — | 低 | suncalc v1 的舊算式 | 低 |
| Metal（現有） | iOS 內建 | — | — | Apple | 已是渲染器，粒子、Shader、光都能在同一個 pass 裡做 | 高 |
| SwiftUI `Canvas`／`TimelineView` | iOS 15 | — | — | Apple | 已用在雨絲，沒有深度、在主執行緒 | 只適合 2D 疊層 |
| SwiftUI Metal shader（`colorEffect`／`layerEffect`） | iOS 17 | — | — | Apple | 只作用在 SwiftUI 圖層，不能拿 3D 深度 | 只適合 UI 效果 |
| SpriteKit（`SKEmitterNode`、`SKRenderer`） | iOS 7／11 | — | — | Apple | 2D 粒子；`SKRenderer` 能畫進自訂 Metal pass，但不會被 3D 樓擋（未驗證，推論不行） | 低 |
| [Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI) | v0.43.1（2026-10-28） | **GPL-3.0** | 看所用模型 | 非常活躍 | 只當離線工具，不進 App | 中（只限 2D 宣傳、介面插圖） |
| [lllyasviel/ControlNet](https://github.com/lllyasviel/ControlNet)（v1.1） | 無 release（最後 commit 2023-09） | Apache-2.0 | v1.1：openrail；SDXL 版 openrail++ 或 Apache-2.0（xinsir）；FLUX.1-dev 系：非商用 | 停 | 固定構圖：用遊戲截圖的線稿或深度當條件 | 中 |
| [tencent-ailab/IP-Adapter](https://github.com/tencent-ailab/IP-Adapter) | 無 tag（最後 commit 2024-06） | Apache-2.0 | Apache-2.0（FaceID 版要 insightface，授權未驗證，避開） | 停 | 用參考圖固定畫風 | 中 |
| [lllyasviel/IC-Light](https://github.com/lllyasviel/IC-Light) | 無 tag（最後 commit 2025-02） | Apache-2.0 | v1（SD1.5）：OpenRAIL-M；v2（FLUX）：權重沒公開、作者說會是非商用 | 停 | 同一張圖換光線；預設去背 RMBG 1.4 非商用，要換 BiRefNet | 低～中 |
| WeatherKit | iOS 16 起的 Swift API；也有 REST API | Apple 條款 | — | Apple | 每月 50 萬次免費；**一定要顯示 Apple Weather 標誌與法律連結** | 低（與遊戲天氣衝突） |
| [Open-Meteo](https://github.com/open-meteo/open-meteo) | 1.7.0（2026-10-16） | 伺服器 **AGPL-3.0** | 資料 CC BY 4.0 | 非常活躍 | 免費 API 只限非商用；商用約 US$29／月起 | 低 |
| 中央氣象署開放資料 | — | 政府資料開放授權條款第 1 版 | — | 政府 | 可商用，要註明出處；要 API 金鑰，不能放進 App 或公開倉庫 | 低～中 |
| WidgetKit | iOS 14；互動 iOS 17 | — | — | Apple | 只有 SwiftUI 快照，不能即時 Metal；記憶體約 30 MB（開發者論壇的說法，非官方） | 中 |
| [kean/Nuke](https://github.com/kean/Nuke) | 13.2.0（2026-08-15）；14.0.0-beta.1（2026-10-11） | MIT | — | 活躍 | 處理遠端圖片的載入與快取；本作的圖都在 bundle 裡 | 低 |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.7（2026-10-21） | MIT | — | 活躍 | 圖片比對要 UIKit，在 Linux 只能比文字或 JSON；畫不出 Metal 3D | 低～中 |
| Instruments（Game Performance、Metal System Trace）、Metal HUD、`OSSignposter`、MetricKit | Xcode 內建 | — | — | Apple | 拆出第 1.6 節那 13 ms 的唯一可靠工具 | 高 |

### 2.2 各項重點

**1. SunCalc：真實太陽位置、方位、陰影、晝夜**
- **【事實】** suncalc v2 是照 Meeus《Astronomical Algorithms》重寫的。README 寫太陽位置誤差約 0.08°，有大氣折射修正（v2.0.0 改用度為單位，是破壞性更新）。私庫有一份照 NOAA 公式寫的同類算式。
- **【事實】** 本作的地圖有真實經緯度：`GeoAnchor`，例如 `FrameTimeBench.swift:20` 的台北車站。GameCore 的時鐘有日期。
- **【推論】** 太陽算式是純數學，可以寫成不 import Foundation 的 Swift。
  - 它只影響畫面，應放在 GamePresentation，不碰 GameCore 的狀態，也不影響 golden、存檔、replay。
  - `Map3DSunShadow` 已經「太陽轉超過 0.01 rad 才重畫」，換成真實太陽後，重畫次數和現在差不多。
- **【推論】** 改了以後的變化：
  - 夏天 05:00 天亮、冬天 17:20 天黑，台北與恆春有差。
  - 冬天正午的影子比夏天長得多（北緯 25° 的正午仰角：冬至約 41.5°、夏至約 88.5°）。
  - 這對鐵道迷是加分：夕陽照在西部幹線的哪一側是真的。
- **【推論】** 現在的關鍵幀依「幾點」排，換成真實太陽後應改依「太陽仰角」取色，私庫的 NOAA 實作就是這樣混色。否則冬天 17:30 太陽已下山，天空卻還是白天色。
- **【假設】** 夏天的白天比現在長，夜窗亮的時間比例會變。玩家能不能接受夏天 19:00 才天黑，要作者在 TestFlight 看。

**2. SpriteKit、SwiftUI Canvas、Metal**
- **【事實】** 疊在 `MTKView` 上的 `SKView` 或 SwiftUI 圖層，是 Core Animation 另外合成的一層：多一張畫面大小的混合，而且拿不到 Metal 的深度，雨雪不能被樓擋住。要同步只能用 `presentsWithTransaction`（[Apple](https://developer.apple.com/documentation/metalkit/mtkview/presentswithtransaction)）。
- **【事實】** `SKRenderer` 可以把 SpriteKit 畫進自訂的 Metal 管線（[Apple](https://developer.apple.com/documentation/spritekit/skrenderer)，文件舉的例子就是霧、雲、雨），但 SpriteKit 是 2D 的。
- **【推論】** 天氣粒子最合適的做法，是在現有主 pass 的不透明幾何之後、團狀影子之前，畫一批 instanced 四邊形的雨絲：
  - 讀深度但不寫深度，所以會被樓、車廂擋住；
  - 位置用 hash 加時間算，不需要 CPU 每幀更新緩衝。
  - 這樣也把 `Canvas` 從主執行緒拿掉。
- **【推論】** SwiftUI 的 `layerEffect`（iOS 17）適合 2D 地圖的雨滴玻璃、閃電一類 UI 效果，不適合 3D。

**3. ComfyUI、ControlNet、IP-Adapter：可重現的 AI 素材**
- **【事實】** ComfyUI 是 GPL-3.0。只在開發機上當工具用，不把它的程式放進 App 或倉庫，就不受 copyleft 影響。工作流程（含 seed）存成 JSON。
- **【事實】** PyTorch 文件寫明不同版本、平台之間「不保證完全可重現」，即使用同一個 seed（[PyTorch](https://docs.pytorch.org/docs/2.15/notes/randomness.html)）。
- **【推論】** 「可重現」只能做到同一台機器、同一套版本。所以要提交的是產出的 PNG 和產生它的記錄，不在 CI 裡重新生成。
- **【事實】** 基礎模型權重的授權，決定能不能商用：

  | 模型 | 權重授權 | 能不能用在本作 |
  | --- | --- | --- |
  | SD 1.5 | CreativeML OpenRAIL-M | 可 |
  | SDXL | OpenRAIL++ | 可 |
  | FLUX.1-schnell、FLUX.2-klein-4B | Apache-2.0 | 可 |
  | FLUX.1-dev | 非商用授權（[條款](https://huggingface.co/black-forest-labs/FLUX.1-dev/blob/main/LICENSE.md)）：產出物可商用，但「用模型做付費遊戲的美術」本身可能就算商業用途 | 不建議 |
  | SD3.5 | Stability Community License（[條款](https://stability.ai/community-license-agreement)）：年營收 100 萬美元以下免費 | 可，但有門檻 |

- **【推論】** 和本作的畫風合不太起來：
  - 3D 是「淡色模型、頂點色、整座城一種材質」（決策 229、370）。AI 生成的是 2D 點陣圖，不能變成可互動的軌道或建物幾何。
  - 它比較適合不需要互動的地方：載入畫面、宣傳圖、主畫面小工具的背景、App Store 截圖的氛圍圖。
  - 用遊戲自己的 3D 截圖當 ControlNet 的深度或線稿條件，構圖就固定在真實場景上；IP-Adapter 吃作者選的畫風圖，風格就一致。
- **【事實】** 生成內容要依 art-style skill 的流程給作者看。超過約 2 MB 的預覽放素材庫（CLAUDE.md）。

**4. IC-Light：同一個場景換光線**
- **【事實】** v1 是 SD1.5 的兩個模型：照文字換光、照背景換光，都需要一張前景圖；要求一致的光線時，可以合成法線。v2（FLUX）只在 Hugging Face Space 上開放過，權重沒公開，作者說會是非商用（[討論](https://github.com/lllyasviel/IC-Light/discussions/98)）。v1 的預設去背模型 BRIA RMBG 1.4 是非商用，要換成 BiRefNet。
- **【推論】** 它重算的是 2D 圖的光，和 3D 的即時光影是兩件事：
  - 對 3D 地圖沒用，因為 Metal 本來就即時算光。
  - 只對方案 B 的 2D 素材（小工具背景、宣傳圖）有用。即使如此，同一張圖重打光時，結構會有小幅漂移。
- **【假設】** 用 v1 把一張遊戲截圖換成黃昏、夜晚時，軌道與月台的位置會不會偏移，要實驗才知道。

**5. WeatherKit、Open-Meteo：連動真實天氣**
- **【事實】** WeatherKit：
  - 每月 50 萬次包含在 Apple 開發者會員裡，超過要付費（100 萬次 US$49.99 起，[Apple](https://developer.apple.com/weatherkit/get-started/)）。
  - 只要顯示資料，就要顯示 Apple Weather 標誌與法律連結。
- **【事實】** Open-Meteo：免費 API 只限非商用，商用要付費方案；資料是 CC BY 4.0，要註明出處；自架的伺服器是 AGPL-3.0。
- **【事實】** 中央氣象署開放資料可以商用，要註明出處，但要 API 金鑰：金鑰不能放進 App 或公開倉庫，只能經自己的伺服器拿。
- **【事實】** 遊戲的天氣是 GameCore 依種子推出來的，會影響需求，而且要決定論（第 1.3 節）。
- **【推論】** 真實天氣不能取代 GameCore 的天氣，否則同一份存檔在不同日子玩會得到不同結果，replay 與 golden 都會壞。
  - 唯一可行的做法是只連動畫面：一個「3D 用現在真實的天氣」選項，只換 `Map3DWeather`，不改 GameCore。
  - 但這樣一來，畫面在下雨，需求卻照晴天算，玩家會困惑。
- **【推論】** 結論是不建議做：成本不高，但標示義務、隱私（要位置）、網路依賴，加上與遊戲規則矛盾，划不來。若作者想要，用中央氣象署的資料最合授權，但要先有伺服器。

**6. WidgetKit：把車站或列車放到主畫面**
- **【事實】** 小工具是 SwiftUI 快照，沒有 `MTKView`。
  - 一天大約 40–70 次更新，每 15–60 分鐘一次；App 在前景或用 App Intent 觸發的更新不算（[Apple](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)）。
  - 動畫只在兩筆時間線之間，最長 2 秒（[Apple](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)）。
  - 記憶體上限約 30 MB（[開發者論壇](https://developer.apple.com/forums/thread/713561)，非官方文件）。
- **【事實】** DayCity 本身就是主畫面小工具：「DayCity: Weather Clock Widget」，Orude Inc.，2026 年 1 月上架，3.11.3 版，iOS 17.5 起，[App Store](https://apps.apple.com/us/app/daycity-weather-clock-widget/id6757228109)。
  - 它顯示 AI 生成的等角微縮城市，每小時依當地天氣（晴、雨、雪）與時段（清晨、白天、黃昏、夜）更新。
  - App Store 的編輯文章說畫面由生成式 AI 產生（[文章](https://apps.apple.com/ua/ipad/story/id1881811740)）。
  - 天氣來源、模型、是預先生成還是即時生成、用什麼渲染，都沒有公開。
- **【推論】** DayCity 很可能是方案 B：每個城市預先生成「時段×天氣」的圖，小工具依狀態換圖。這和本作 3D 的即時渲染是不同路線，**不要以為 DayCity 用了本研究列的哪一項技術**。
- **【推論】** 本作可行的做法：
  - App 在前景時用 `Map3DMetalView` 已有的拍照功能（決策 403 續二，`Map3DMetalView.swift:1270-1286`）拍一張玩家的車站，縮小後存進 App Group，小工具顯示這張圖加上下一班車。
  - 新增 target 要改 `project.yml`、加 App Group，還要作者在 Apple 帳號上設定。
  - 小工具上的時段變化，可以照方案 B 的思路，在 App 裡先拍好 4 個時段。
- **【事實】** Live Activities 最多 8 小時、資料 4 KB、不能上網（[Apple](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)），適合「跟著一班車」的進度，不適合畫場景。

**7. Nuke、SnapshotTesting、Instruments**
- **【推論】** Nuke 解決的是網路圖片，本作的圖都在 bundle 裡，現在沒有用處。
- **【推論】** swift-snapshot-testing 能比 SwiftUI 面板的截圖，但：
  - 不能比 Metal 3D（Simulator 的 Metal 和真機不同，CI 也不比圖，CLAUDE.md）；
  - 要加依賴，要作者同意。
  - 3D 的回歸比對繼續用 `tools/map3d-preview`（WebGL 同算式＋pixelmatch，只在開發機）。
- **【推論】** Instruments 是第 1.6 節最該用的工具：Game Performance 範本同時看主執行緒、GPU、display link 跳幀；Metal HUD 用環境變數 `MTL_HUD_ENABLED=1` 打開。
  - 這兩樣要 Mac 加 Xcode 加接線的 iPhone，是作者能做的步驟。
  - TestFlight 版上不能接 Instruments，但 MetricKit 每天會回報 hitch 與記憶體。
- **【假設】** MetricKit 在 TestFlight 版會送報告（Apple 文件沒寫限制，未驗證）。

## 3. 三種方案

- **A（全即時）**：天氣、日夜全部在現有 Metal 裡即時算。
- **B（離線預製）**：先生成「時段×天氣×季節」的美術素材，遊戲裡依狀態換圖或換貼圖。
- **C（混合）**：保留可互動的軌道、列車、建築幾何，用預製的小素材（雲貼圖、雨絲貼圖、天空 LUT、時段色表）加上 Shader 與即時光影。

| 項目 | A 全即時 | B 離線預製 | C 混合 |
| --- | --- | --- | --- |
| 鐵軌幾何一致性 | 不變：同一份幾何 | **差**：預製圖是 2D，玩家蓋的新軌道不在圖裡；做成貼圖也會和程序生成的城市對不上 | 不變：幾何不動，只改光與材質 |
| 碰撞判定、點選 | 不變 | 圖和可點的東西要另外對齊，容易錯位 | 不變 |
| 畫質 | 中高，受 GPU 預算限制（天空 LUT、體積雲做不起） | 單張圖最高，但不能轉鏡頭、不能拉近 | 高：預製的雲、天空色表補上即時做不起的部分 |
| FPS | 加多少掉多少；現在 GPU 已在 10 ms 門檻 | 3D 不變；換圖時可能卡一下 | 介於兩者之間；大部分預製素材查表就好，比 A 便宜 |
| GPU／CPU | GPU 增加最多 | 幾乎不增加 | GPU 小增；把 `Canvas` 雨搬進 Metal 還會讓主執行緒變輕 |
| 記憶體 | 幾乎不增加 | 大：每個場景×每個狀態一張大圖 | 小：幾張小貼圖、表，以 MB 計 |
| App 大小 | 不變 | 大：只做數十 MB 的「主畫面小工具」還可以，3D 用不了 | 小：增加不到 1 MB |
| 維護成本 | 中：改著色器要同時改 WebGL 預覽（HANDOFF §4.2） | **高**：每加一座城、一款車都要重新生成 | 中 |
| 美術成本 | 低：調數字 | **高**：生成、挑圖、授權記錄、給作者看 | 低～中 |
| 適合的地方 | 已經在用 | 小工具、宣傳圖、載入畫面 | 3D 地圖的下一步 |

**【推論】** 結論：3D 地圖走 C，A 的部分已經做完大半；B 只用在 3D 以外（小工具、宣傳）。

**可行性排序**（工程量是一位熟悉 Map3D 的 session 的估計，【推論】）：

| 順 | 項目 | 方案 | 工程量 | 碰的檔案 | 風險 |
| --: | --- | --- | --- | --- | --- |
| 0 | 量清楚 36 fps：Instruments 一次，加上畫面節奏測試的駕駛室、時段、天氣 | — | 小（1 PR，約半天到 1 天） | `FrameTimeBench.swift`、`FrameTimeBenchRunner.swift`、`OSSignposter` 幾個點 | 低 |
| 1 | 真實太陽（經緯度＋日期），關鍵幀改依仰角 | C | 小～中（1 PR） | `Map3DCamera.swift:298-486`（`Map3DLighting`）、`Map3DSky.swift`、`DayNight.swift`；新的 `Map3DSun` | 中：夜窗與 2D 的日夜跟著變，要五方決定 |
| 2 | Metal 的雨（instanced、會被擋），取代 `Canvas` | C | 中（1–2 PR） | `Map3DShaders.metal`、`Map3DMetalView.swift` 主 pass、`Map3DRain.swift`、`Map3DPreviewScreen.swift:1094-1128` | 中：`.metal` 只能在 macOS CI 編 |
| 3 | 黃昏與夜的色表：照私庫 tw3d 的五個時段預設與夜裡曝光下限，調 `Map3DLighting` 的關鍵幀 | C | 小（調數字＋預覽） | `Map3DCamera.swift:329-340`、`Map3DGrade.swift` | 低；要作者看圖 |
| 4 | 路面濕亮：雨天把 `Map3DReflection` 的水面 Fresnel 用在路面，夜裡映出路燈 | C | 小～中 | `Map3DReflection.swift`、`Map3DShaders.metal` | 中：GPU 成本要量 |
| 5 | 陰天與雲：只畫面，雲貼圖在天空穹頂上捲動，或在地面上投雲影 | C | 中 | `Map3DSky.swift`、`Map3DWeather.swift` | 中：GameCore 沒有陰天，要從「雨的前後一天」推，或只做純裝飾 |
| 6 | 主畫面小工具：玩家的車站加下一班車 | B | 中～大（新 target、App Group） | `project.yml`、新的 extension | 中：要作者在 Apple 帳號上設定 |
| 7 | AI 生成 2D 氛圍圖（載入畫面、宣傳） | B | 中（工具鏈在開發機） | 不進遊戲程式 | 授權風險：要選 Apache 或 OpenRAIL 的權重 |
| 8 | 真實天氣連動 | — | 中 | — | 高：與 GameCore 的天氣衝突、授權、隱私 → **不做** |
| 9 | IC-Light 重打光 | B | 中 | — | v2 非商用、v1 舊 → **不做** |

## 4. 和現有規則的關係

- **【事實】** GameCore 必須保持平台無關與決定論（CLAUDE.md、ARCHITECTURE）。這份研究提的 1–5 項都只在 GamePresentation 與 App：讀 `clock.now`、`Weather`、`GeoAnchor`，不寫回。存檔、golden、replay 都不動。
- **【事實】** 改著色器時，`tools/map3d-preview/index.html` 的 WebGL 算式要一起改（HANDOFF §4.2）。
- **【事實】** 決策 417 與 460 的降級規則要算進新的成本：雨的 instanced 四邊形要算進「會動的東西」的三角形預算，或在省電與過熱時關掉。
- **【事實】** 減少動態效果時雨不畫（`Map3DPreviewScreen.swift:1117`）。搬進 Metal 後要保留這個行為（motion skill）。
- **【推論】** 「不可為了視覺犧牲核心遊戲的正確性」在本作的意思是：畫面的任何變化都不能影響 tick 的結果、選路、點選的命中，也不能讓主執行緒慢到遊戲迴圈跟不上倍速（決策 464 的提示會跳出來）。

## 5. 小型技術驗證（Spike）

### 5.1 範圍

- **地點**：台北車站附近。
  - 已是畫面節奏測試的錨點（`FrameTimeBench.swift:20`），有高架、地下化、月台、站前街道；
  - 駕駛室視角從板橋往台北，正好經過地面、地下和高架三種狀況。
- **時段**：早晨 06:30、正午 12:00、夕陽 17:30、夜晚 21:00。日期用 6 月 21 日與 12 月 21 日各一次，讓真實太陽的差異看得出來。
- **天氣**：晴、雨。
- **鏡頭**：現有的 3D 環繞、3D 跟車，加上新增的駕駛室跟車，都是 10×。
- 4 個時段 × 2 種天氣 × 3 種鏡頭 = 24 項；每項 60 秒、3 次，照 V2 的做法。

### 5.2 怎麼做，而不動遊戲規則

- **【推論】** 時段與天氣只對畫面「釘住」：在 GamePresentation 加一個只在測試版出現的覆寫（`Map3DLighting` 的分鐘與日期、`Map3DWeather` 的預設）。GameCore 的時鐘與天氣照常跑。
- **【推論】** 這樣軌道、列車、號誌、點選都和平常一樣：時刻表照跑，只是天空看起來是 21:00。
- **步驟**（每一步是一個 PR，都不動 GameCore）：
  1. **第 0 步，只量不改**：
     - 畫面節奏測試加「駕駛室跟車」與上面的時段、天氣覆寫；
     - 在 `draw(_:)` 外面、tick 合回主執行緒、chunk 建置、`Canvas` 雨三處加 `OSSignposter` 區間；
     - 回報裡加一行主執行緒以外的時間：幀間隔 − `draw` 內的 CPU。
     - 用 Linux 測試釘住新的項目與統計。
  2. **第 1 步**：真實太陽。
  3. **第 2 步**：Metal 的雨。
  4. 每一步都和第 0 步的同一組 24 項對照。

### 5.3 量什麼、過關的標準

| 指標 | 來源 | 基準 | 過關 |
| --- | --- | --- | --- |
| fps 中位數與 p95 幀時間 | `FrameTimeRecord`（p95） | 第 0 步量到的同一項（駕駛室 10× 晴天；作者的 36 fps 是參考點） | 中位數不低於基準；p95 不超過基準＋1 ms |
| 停頓次數（>50、>100、>250 ms） | `FrameTimeRecord.swift:169-172` | 同上 | 不增加 |
| CPU、GPU（中位數、p95） | `Map3DMetalView` 的 Stats | 同上 | GPU 增加 ≤ 0.5 ms；**不能因此降到 2×**（看「3×」有沒有變） |
| 負載階梯 | `Map3DLoadLevel.summary` | higher full | 仍是 full |
| 記憶體最高、最少剩 | 決策 460 的回報欄位 | 同上 | 增加 ≤ 10 MB |
| 正確性 | Linux：既有 golden、replay、`Map3D*Tests`；真機：點選列車、車站，駕駛室進出隧道 | — | 全綠；點選與以前一樣 |

### 5.4 作者在 TestFlight 上的步驟

前提：第 0 步的 PR 合併、發版之後。發版是作者的決定，照 CLAUDE.md。

1. 同一台 iPhone（建議用今天量 36 fps 的那台），充飽電，關掉低耗電模式，放涼 5 分鐘；設定裡的 3D 畫質選「自動」。
2. 開 App → 設定 → 點版本五下 → 演示模式出現 → 「畫面節奏測試」。
3. 依序跑新加的 24 項：每項自動跑 3 次；跑的時候不要碰螢幕，遊戲上方的小卡會寫剩幾秒。
4. 跑完按「複製結果」，貼到 #1041 或給遊戲規劃。
5. 另外打開 3D、駕駛室、10×，停在台北地下段與板橋高架段各 1 分鐘，然後「設定 → 回報問題」送出。回報裡會附幀時間、記憶體與裝置。
6. 若有 Mac 和 Xcode（選做）：接線，Xcode → Product → Profile → Game Performance，同樣在駕駛室 10× 錄 30 秒，把 `.trace` 的主執行緒圖截圖給遊戲規劃。這一步能直接看出第 1.6 節那 13 ms 在哪裡。
7. 第 1、2 步各自發版後，重跑第 2–5 步，對照第 5.3 節的表。

## 6. 最值得先驗證的 3 個方案

1. **先量 36 fps 的原因，並建好「時段×天氣」的測試**（第 5.2 節第 0 步）
   - 現在 GPU 9.9 ms、CPU 4.6 ms 加起來還不到一幀，fps 卻只有 36。不先找出那 13 ms，後面的畫面改動無從比較。
   - 測試的覆寫也是後面兩項的展示工具。
2. **真實太陽**（第 3 節第 1 項）
   - 一個純算式加上依仰角取色，GPU 幾乎不增加：陰影重畫的條件已經存在。
   - 晨昏、季節、南北的光影第一次是真的，這是 DayCity 那種「時間在走」的感覺裡最便宜的一塊。
3. **Metal 裡的雨**（第 3 節第 2 項）
   - 雨會被樓、車廂擋住，駕駛室裡不再「室內下雨」。
   - 主執行緒少了每秒 60 次的 `Canvas` 重繪，有機會同時改善第 1.6 節的問題。
   - 之後的路面濕亮、雪、雲影，都疊在這個基礎上。

## 7. 搜尋紀錄（照 CLAUDE.md）

- **參考庫 a91453/railway-reference-private**（唯讀，只寫結論）：
  - 有真實太陽位置（NOAA 公式）、時段與天氣預設、天空 LUT 與自動曝光、夜窗資料貼圖、行動裝置的畫質分級與剔除。
  - 沒有 suncalc 套件，也沒有 AI 生成或重打光的管線。
- **素材庫 a91453/railway-assets-private**（唯讀）：
  - Meshy 批次的經驗、遠景實例的前後預覽、遊戲內白天、黃昏、夜晚的宣傳影片素材。
  - 沒有 ComfyUI、ControlNet 的工作流程。
- **外部專案**：第 2.1 節表內的每一個連結。都只讀了說明與授權，**沒有複製任何程式碼**，也沒有加依賴。
  - ComfyUI（GPL-3.0）與 Open-Meteo 伺服器（AGPL-3.0）是 copyleft，只能當外部工具或服務，不能把程式放進本作。
- **Apple 文件**：SKRenderer、MTKView `presentsWithTransaction`、WidgetKit 的更新與動畫、ActivityKit、WeatherKit 的價格與標示、Metal HUD、MetricKit，連結見各節。
- **DayCity**：只查到 App Store 頁與編輯文章，技術細節沒有公開（第 2.2 節第 6 項）。

## 8. 驗證

- **VERIFIED**（本 session，Linux）：
  - 第 1 節列的每個 `檔案:行` 都讀過原始碼；
  - `python3 -I tools/golden-checks/doc_numbers.py --check`（這份文件不佔決策號）。
- **UNVERIFIED**：第 1.6 節對 36 fps 的解釋、第 3 節的工程量、第 5.3 節的門檻，都要第 5.4 節的真機量測。這份研究沒有跑任何 iOS 或 Metal 的程式。
