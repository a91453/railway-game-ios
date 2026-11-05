# 安卓移植研究：3D、地圖、畫面層與最低規格（2026-11）

派工單 ANDROID-STUDY，研究 session_01YGNNupYr8zmehaeBVdjDCv，遊戲規劃第 49 任（session_01YGNNupMtajwSvF2wPZDUjt）派。只有文件：不動程式、決策號、存檔版本、golden、SaveFixtures、ReplayFixtures，不加依賴。量測的基準是 `main` `83c47417`。

作者 2026-11-05：「如果我考慮12月開始移植安卓用哪個3d跟地圖引擎比較好 還是自製最好」「還是你幫我開session研究」。後來遊戲規劃轉來兩題補充：最低 Android 版本（作者在想 Android 14），以及「安卓便宜機那麼多又很難控制」的硬體門檻（§6）。

比較照決策 421 的方法（`FRAME_TIME_AND_ENGINE_SPIKE_PLAN_2026-10-26.md` §5「長期比較要看的」）分四類：效能、製作成本、維護成本、功能缺口。每類都寫實際數字或紀錄，**不打主觀分數**。行數只說明範圍有多大，不是工時（作者 2026-10-26）。

## 0. 結論

**一句話**：走 (A)。GameCore 與 GamePresentation 原封不動，用 Swift 官方的 Android SDK 共用。這已實測過：三套 fixture 在 Android ARM64 上全過；3D 網格只有 EMU3000 因安卓的 `atan2f`／`asinf` 差最後一位而和雜湊鎖不同（§4.2）。3D 繼續自製，只為安卓另寫一個 Vulkan 的最底層，Swift 直接呼叫 NDK，不加依賴。地圖用 MapLibre Native Android。畫面層先用 Jetpack Compose 重寫；Skip 授權是 MPL／AGPL，要作者決定才能用。不換 Unity 或 Godot。

| 問題 | 建議 | 一句話的理由 |
| --- | --- | --- |
| 遊戲核心（GameCore 49.7k 行）與畫面邏輯（GamePresentation 150.5k 行） | 照用，Swift 6.4 官方 Android SDK | 已實測：整包連測試都編得過；Golden 24/24、存檔 38/38、重播全過（Android 14 的系統函式庫，qemu 上跑，§1） |
| 3D | 自製，加一個 Vulkan 1.1 後端 | 3D 邏輯 56.8k 行照用；要換的只有約 1,840 行 Swift 與 825 行 shader。Swift 直接呼叫 Vulkan 已編過；Linux CI 能用 lavapipe 跑 Vulkan（§1、§2） |
| 地圖 | MapLibre Native Android 13.x（BSD-2） | iOS 已用 MapLibre；底圖樣式由 GamePresentation 的 Swift 產生，安卓吃同一份 JSON；13.0 起預設就是 Vulkan（§2） |
| 畫面層（App 的 SwiftUI 45.9k 行） | 第一版用 Jetpack Compose 重寫；Skip 待作者決定 | Skip 免費，但 skip-ui 是 MPL-2.0、引擎 AGPL-3.0，照 CLAUDE.md 要作者同意；而且 Canvas、Metal、UIViewRepresentable 它都不支援（§3） |
| Unity／Godot | 不換 | 都要把 3D 邏輯改寫成 C#／GDScript，或每幀經 C 介面搬資料；Linux 測試跟著失效；SwiftGodot 的安卓支援沒驗證（§2） |
| 2D 地圖的卡頓（PERF114，全台縮圖約 8 fps） | 地面、軌道等不常變的圖層做成 GPU 頂點，只畫一次、存起來，交給和 3D 同一個底層畫；真實地圖上的軌道可以交給 MapLibre | 「畫一次存起來」若用 iOS 的點陣快取，安卓還得重寫一份；放在共用的 Swift 幾何＋自製後端，兩邊都受益（§5） |
| 最低規格 | **Android 12（API 31）＋Vulkan 1.1（必要）＋RAM 4 GB 以上**；另依實機量測用 Play Console 排除最弱的晶片 | 便宜機要靠 RAM、晶片與 Vulkan 的規則擋，不是靠系統版本：台灣新賣的 4 GB 入門機出廠就是 Android 14／15，Android 14 的下限反而擋掉 2020–21 年較強的舊旗艦（§6） |

白話說：要重寫的是「把東西畫到螢幕上」與「按鈕和面板」這兩層，遊戲本身和 3D 模型的配方都不用動。

## 1. 實測（本容器，Linux x86_64）

| 項目 | 結果 | 標記 |
| --- | --- | --- |
| 下載 swift.org 官方的 `swift-6.4.0-RELEASE_android.artifactbundle.tar.gz`（340 MB），對 swift.org `releases.json` 的 checksum `21fb5551…0b43` | 相符；`swift sdk install` 成功，triple 有 aarch64／armv7／x86_64，API 23–36 | VERIFIED |
| NDK：Google 的 `android-ndk-r28c-linux.zip`，跑 SDK 附的 `setup-android-sdk.sh` | 成功。Swift 6.4 官方建議用 NDK 30（LTS）；r28c 也能編，正式開工照官方用 30 | VERIFIED（r28c） |
| `swift build --swift-sdk aarch64-unknown-linux-android28 --target GameCore` | 不改一行就編過，約 83 秒 | VERIFIED |
| GamePresentation | **不改就編不過**：`Map3DR100.swift`、`Map3DPedestrianSignals.swift` 等用 `sin`／`cos`（Float），安卓的 Foundation 沒有把 Float 版的數學函式帶進來（只有 `Double` 與 `CGFloat` 版）。在 GamePresentation 加一個檔 `#if os(Android) @_exported import Android #endif` 就全部編過 | VERIFIED（改動只在 scratchpad 的複本） |
| 兩個測試包（`--build-tests`） | `PassengerRouteMemoryReportTests.swift` 的 `getrusage` 照 Glibc 寫，安卓要走 Darwin 那一支（`#if canImport(Darwin) \|\| os(Android)`，並 `import Android`）。改了這兩行之後，GameCore、GamePresentation、GameSim、兩個測試包都編過（345 秒） | VERIFIED（同上，只在複本） |
| 在 Android 上跑：沒有 KVM，裝不了模擬器。改從 Google 官方 Android 14 arm64 模擬器映像（`arm64-v8a-34_r04.zip`，sha1 相符）取出 bionic 的 `linker64`、`libc`、`libm`（runtime APEX）與 `/system/lib64`，用 `qemu-aarch64` 跑 Android 的測試執行檔 | 執行檔正常啟動，列出 1,791 個 GameCore 測試 | VERIFIED（qemu＋真 bionic，**不是實機或模擬器**） |
| `GoldenScenarioTests` | **24/24 過**（qemu 上 896 秒；CI 原生約 280–330 秒） | VERIFIED（qemu） |
| `SavedGameTests` | **38/38 過**（32 秒） | VERIFIED（qemu） |
| `ReplayFixtureTests` | **2 過、1 略過**；略過的是錄製用的測試，Linux 上也一樣略過 | VERIFIED（qemu） |
| GamePresentation 的 3D 測試：`Map3DTests` 18/18、`Map3DTEMU2000Tests` 9/9、`Map3DFarSets422Tests` 3/3 | **全過**（qemu 上 1,291／653／484 秒），含「同一場景每次都一樣」 | VERIFIED（qemu） |
| 3D 模型雜湊鎖（`Map3DModelPackLockTests`，每個頂點的 `Float` 逐位元比對 `tools/train-models/hashes.lock.json`） | **2 個失敗、1 略過**：鎖住的 1,081 個模型裡，只有 EMU3000 的 18 個（近景 8、遠景 8、車燈 2）雜湊不同，連帶整包的兩個摘要不同。原因是 bionic 的 `atan2f`、`asinf` 和 glibc 最後一位不同（§4.2） | VERIFIED（qemu）；同一份 EMU3000 原始碼與鎖在 Linux 上過（`main` 7ca083b9 的夜間完整 CI 綠） |
| Swift 呼叫 NDK 的 Vulkan、GLES3、EGL（`<vulkan/vulkan.h>` 經 module map） | 安卓 aarch64 編譯、連結都過（`NEEDED libvulkan.so`）。qemu 裡沒有 GPU，沒跑 | 編譯 VERIFIED；執行 UNVERIFIED |
| 同一份 Swift 的 Vulkan 程式在 Linux 主機跑，用 Mesa 的 lavapipe（軟體 Vulkan） | `vkCreateInstance` 成功，列出 `llvmpipe … api 1.4` | VERIFIED：Linux CI 可以無頭測 Vulkan 後端 |
| 把 `Map3DShaders.metal` 的天空 shader（`map3dSkyVertex`／`map3dSkyFragment`，加上 `map3dHaze`、`map3dFinish`）手翻成 GLSL，用 NDK 自帶的 `glslc` 編成 SPIR-V，再用 `spirv-val --target-env vulkan1.1` 檢查 | 都過（vert 852 bytes、frag 7,144 bytes；GLSL 66 行，對應 MSL 約 75 行） | 編譯 VERIFIED；畫出來的圖沒比對 |
| 實機（任何安卓手機）的效能、記憶體、App 大小 | 沒做：這裡沒有實機 | UNVERIFIED |

重現的步驟和腳本放在 scratchpad，不進 repo。要重做時照上表：安裝 SDK，設 `ANDROID_NDK_HOME`，再 `swift build --swift-sdk aarch64-unknown-linux-android28 --build-tests`。

要正式支援安卓，repo 得改兩處，**這次沒改**：

1. GamePresentation 加 `#if os(Android) @_exported import Android #endif`（一個新檔）。
2. `PassengerRouteMemoryReportTests.swift` 的 `#if canImport(Darwin)` 加上 `|| os(Android)`。

兩處都在 12 月第一個 spike 的 PR 裡做（§8）。

## 2. 三條路（加其他路）

### 2.1 範圍盤點（`main` `83c47417`，`wc -l`）

| 層 | 行數 | import | 安卓上怎麼辦 |
| --- | --: | --- | --- |
| GameCore | 49,701（123 檔） | 無（不 import Foundation） | 照用（§1 已驗） |
| GamePresentation | 150,496 | 只有 Foundation、GameCore、Observation | 照用（§1 編過） |
| 　其中 `Map3D*`（場景、網格、車型配方、遠近模型、預算） | 56,789 | 同上 | 照用 |
| App（`RailwayGameApp/`，UITests 除外） | 45,944 | SwiftUI 88 檔、UIKit 17、Charts 6、MapKit 2、MapLibre 1、GameKit 1、WebKit 1、MetricKit 1、Metal／MetalKit 2 | 重寫（§3） |
| 　其中 Metal（`Map3DMetalView.swift` 1,569 行＋`FrameTimeRecorder.swift`，共 1,838 行）＋`Map3DShaders.metal` 825 行 | 2,663 | Metal、MetalKit | 換成 Vulkan 後端 |
| 　其中 2D 地圖（`MapView.swift` 3,669＋`MapArt.swift` 2,559＋其他 `Canvas` 檔） | `Canvas {` 在 10 個檔，共 9,644 行；`GraphicsContext` 出現 65 次 | SwiftUI `Canvas` | 見 §5 |
| 測試（`Tests/`） | 179,895 | XCTest | 照用，Linux 照跑；安卓上可加跑（§1） |
| UI 測試（`RailwayGameApp/UITests/`） | 12,075 | XCUITest | 重寫成 Compose 的 UI 測試（Espresso／Compose Test） |

Metal 這一層有 12 條 pipeline（`makeRenderPipelineState` 12 次）、16 個 shader 函式、太陽陰影圖、texture array、instancing、看板 atlas、天空。Vulkan 1.1 都有對應的功能，沒有一項要靠擴充。

### 2.2 比較表（四類）

| | (A) Swift 共用核心＋自製渲染＋MapLibre Android | (B) Unity 6.3 LTS | (C) Godot 4.7（含 SwiftGodot） |
| --- | --- | --- | --- |
| **效能** | 沒有實機數字（UNVERIFIED）。底層和 iOS 一樣是低階 API（Vulkan 對應 Metal），每幀的工作量與 iOS 相同；draw call 約 180（決策 421 的範例），在 Vulkan 或 GLES 都不是瓶頸 | 沒有實機數字。引擎本身成熟；但若 3D 邏輯留在 Swift，每幀要經 C 介面把網格與位置交給 C#（決策 421 V3 要量的介面成本，**還沒量**） | 同 Unity；預設的 Mobile renderer 走 Vulkan，另有 OpenGL 的 Compatibility |
| **製作成本**（要做的事） | ① 抽一個薄的「畫圖後端」介面（Metal、Vulkan 各一份）；② Vulkan 後端：約對應 1,840 行 Swift＋825 行 shader；③ Compose 畫面（§3）；④ MapLibre Android 的 Kotlin 接法（iOS 的 `OSMMapBackground.swift` 704 行對應）；⑤ JNI 橋（swift-java）。**3D 邏輯、模型工具、車型配方都不用改** | ① GameCore／GamePresentation 編成 Android 的 `.so`，C# 經 P/Invoke 呼叫（`@_cdecl`）；② 二選一：3D 邏輯 56.8k 行改寫成 C#（它的 Linux 測試 15k＋行跟著重寫），或留在 Swift、每幀搬網格；③ UI 用 Unity UI 重寫（不比 Compose 省）；④ 地圖：Unity 沒有官方 MapLibre，要自己接 Android View 或另找圖磚引擎 | 同 Unity；SwiftGodot 可省掉 C 介面，但它 README 只寫 iOS、Linux、macOS、Windows，「其他平台還沒測完」；Swift Package Index 有安卓編譯失敗的紀錄 |
| **維護成本** | 一份遊戲邏輯、一份 3D 邏輯，兩個薄後端。現有的 Linux 測試全部照用；Vulkan 後端能在 Linux CI 用 lavapipe 跑（§1）。35 個模型工具、程式產生的車型配方照用。每年要跟 Swift 與 NDK 的版本（Swift 6.4 用 NDK 30） | iOS 留 Metal、安卓用 Unity，等於**兩套 3D**；若連 iOS 一起搬到 Unity，就是決策 421 V3 那張表的全部成本。引擎每年升級；Pro 方案收入超過 20 萬美元才要付（每席每年 2,310 美元，2026-01-12 漲 5%）；CI 要 Unity 授權啟用 | 同 Unity 的「兩套 3D」；引擎 MIT、免費；SwiftGodot 0.99.2 還沒 1.0 |
| **功能缺口** | 光影、粒子、後製都要自己寫（現在 iOS 也是這樣）；Vulkan 驅動在舊 Adreno／Mali 上有坑（MapLibre 13.7.1 還在修 Adreno 600 的 `VK_ERROR_DEVICE_LOST`），要靠最低規格與實機測試擋（§6） | 現成的光影、粒子、後製（URP）；HDRP 不支援安卓 | 現成的光影、粒子；Mobile renderer 的功能比桌面版少 |
| **授權／依賴** | Swift（Apache-2.0）、NDK、MapLibre（BSD-2，已在用）、swift-java（Apache-2.0，還沒 1.0）。**不新增第三方圖形依賴** | 商業授權；新增依賴要作者同意 | MIT；SwiftGodot MIT；新增依賴要作者同意 |

### 2.3 (A) 的底層：自寫 Vulkan，還是用現成的跨平台底層

| | 自寫 Vulkan 1.1（Swift 直接呼叫） | wgpu-native | bgfx | Filament | GLES 3（自寫） |
| --- | --- | --- | --- | --- | --- |
| 授權 | 無新依賴 | MIT 或 Apache-2.0 | BSD-2 | Apache-2.0 | 無新依賴 |
| 安卓 | Vulkan 1.1 | Vulkan 為主、GLES 3 盡力支援 | GLES 3、Vulkan | GLES 3、Vulkan 1.0 | GLES 3.0／3.2 |
| 能不能也取代 iOS 的 Metal | 不取代（iOS 留現在的 Metal） | 能（它在 iOS 上跑 Metal） | 能 | 能（但它是整套 PBR 引擎，要用它的材質系統） | 不能（iOS 上的 GLES 已停止維護） |
| 從 Swift 呼叫 | C 標頭直接 import（§1 已驗） | C 標頭，可 import；要 Rust 工具鏈建置 | C API；社群的 Swift 綁定，維護狀況不明 | 主要是 C++ 與 Java；沒有官方 Swift | C 標頭直接 import（§1 已驗） |
| 大小 | 0（系統的 `libvulkan.so`） | `libwgpu_native.so` 10.2 MB（arm64） | 不明 | AAR 5.27 MB（全 ABI） | 0 |
| shader | GLSL→SPIR-V（NDK 自帶 `glslc`，§1 已驗） | WGSL | 自己的 shaderc 語法 | 自己的材質語言 | GLSL ES |
| 適合我們的地方 | 結構和 Metal 一對一（command buffer、pipeline、encoder），`Map3DMetalView` 能逐段對照翻；lavapipe 能在 Linux 測 | 一份後端同時給 iOS 與安卓 | 成熟 | 安卓官方背景 | 程式最短 |
| 不適合的地方 | Vulkan 程式長、驅動差異要自己擋 | 新依賴＋Rust 工具鏈；FFI 的 buffer 生命期要管（PEAKLINE 研究 R15） | 新依賴；shader 改寫成它的語法 | 和我們自己的網格、預算、LOD 重疊 | Google 說以後 GLES 只經 ANGLE（Vulkan 之上）提供；驅動的 CPU 開銷較高 |

建議用**自寫 Vulkan 1.1**：

1. 不加依賴。照 CLAUDE.md，加依賴要作者同意。
2. 能在 Linux CI 用 lavapipe 跑，接上現有的「Linux 測一切」做法。
3. MapLibre Android 13 起預設也是 Vulkan，App 裡的地圖與 3D 走同一條驅動路徑。

退路是 wgpu-native：Vulkan 後端若在實機上的驅動問題太多，或兩個後端的維護成本超過一份 wgpu，就換它。換之前要作者同意這個依賴。

### 2.4 其他想得到的路

| 路 | 結論 |
| --- | --- |
| 整個 App 用 Skip Fuse（SwiftUI 原生編到安卓，畫面轉成 Compose） | 畫面層用得上，見 §3；3D 與 2D 地圖仍要自己的後端（Skip 不支援 Metal 與 `Canvas`） |
| Kotlin Multiplatform／Compose Multiplatform | 要把 Swift 的核心改寫成 Kotlin，等於重寫遊戲，不考慮 |
| 把網站版（MapLibre GL JS＋Three.js，參考庫 `Railway/` 的做法）包進 WebView（Capacitor） | 參考庫的台灣鐵道網站就是 Capacitor 安卓 App（`taiwan-rail-reference-clean/source/app/android`，44 個 Java 檔，多是小工具與通知）。遊戲的邏輯是 Swift，要先編成 Wasm（`Web/WasmProbe` 已有 GameCore 的 Wasm 探針），3D 要用 Three.js 重寫；效能與觸控都比原生差。不建議當主路 |
| Unreal | 和 Unity 同類，C++，App 大小與建置更重；不考慮 |

## 3. 畫面層（45.9k 行 SwiftUI）怎麼上安卓

先看現況：GamePresentation 已經把「選單列什麼、卡片放哪、何時進下一步」這類邏輯從畫面拿出來，所以 App 那 45.9k 行多半是排版與畫圖。GamePresentation 公開的型別約 1,253 個，公開的函式與屬性約 7,751 個。

| 選項 | 要動的檔 | 好處 | 風險 |
| --- | --- | --- | --- |
| **Jetpack Compose 重寫**（Kotlin） | `RailwayGameApp/Views/*.swift`（約 80 檔）全部重寫成 Compose；`App/` 的入口、存檔位置、Game Center（→ Google Play Games）、iCloud（→ 雲端存檔另議）、MetricKit（→ Android vitals／`ApplicationExitInfo`）各自換。Swift 那側加一層「給畫面的門面」，每個畫面一個小型態，經 swift-java（JNI）交給 Kotlin | 安卓原生的外觀、字體、無障礙、返回鍵；沒有新依賴（swift-java 是 Apache-2.0 的官方專案，但還沒 1.0，加不加要作者確認） | 兩份畫面要同步維護；JNI 的門面要設計，不能把 7,751 個成員全接過去 |
| **Skip（Fuse 模式）** | 同一份 SwiftUI 檔，用 `#if SKIP` 或 `#if os(Android)` 分支；不支援的部分（`Canvas` 17 處、`UIViewRepresentable` 7 個、UIKit 17 檔、`Charts` 6 檔、MapKit 2 檔）各自補 Compose 版（`ComposeView`） | 一份畫面；Observation 在 Fuse 模式可用；已有正式上架的例子（Polymarket，約 17 萬行 Swift） | **授權**：skip-ui、skip-fuse-ui、skip 是 MPL-2.0，轉譯引擎 skipstone 是 AGPL-3.0。照 CLAUDE.md，copyleft 要作者同意才能用。手勢只有 `onChanged`／`onEnded`、自訂動畫不支援；地圖、3D、圖表都要另寫；Swift 執行環境讓 App 多約 50–60 MB |
| 只在安卓上用 SwiftUI 的部分 | 不可行：安卓沒有 SwiftUI | | |

建議：**第一版用 Compose 重寫**。Skip 要等作者決定可不可以用 MPL／AGPL 的元件；就算能用，要另寫的（地圖、3D、2D `Canvas`、圖表）正是程式最多、最難的那幾塊，Skip 省下的主要是設定、清單這類一般畫面。

畫面按工作量排序（從共用最多的開始）：

1. 開始畫面與設定；
2. 2D 地圖（§5 的後端）＋MapLibre；
3. 3D 地圖；
4. 路線、車站、列車面板；
5. 圖表（Compose 沒有內建，可自己畫，或用 Vico 這類 Apache-2.0 的函式庫，後者要作者同意）。

## 4. 確定性：golden、存檔、重播在安卓上是否同值

### 4.1 GameCore：已驗證同值

- 實測：§1 在 Android 14 的 bionic（ARM64，qemu）上跑 Golden 24/24、SavedGame 38/38、Replay 全過。這些測試比對的是 repo 裡寫死的值，所以「過」就代表和 Linux x86_64 算出逐位元相同的結果。
- 為什麼穩：GameCore 照 ARCHITECTURE 的規則，會進 fixture 的計算都用整數，不 import Foundation。全部只有 9 個 `Double`／`Float`，都在 `RunSpacing.swift` 第 92–97 行，是一次比大小（`theirTime < myTime + 60`），只用加減乘除。IEEE 754 的加減乘除在 ARM64 與 x86_64 上結果相同；剩下的風險只有編譯器把乘加合成 FMA，而 Swift 預設不這樣做。
- `Sendable`、Observation、Dispatch：安卓 SDK 都有（`libswiftObservation.so`、`libdispatch.so`、`libswift_Concurrency.so`），編譯沒有任何 `Sendable` 的錯誤。
- Foundation：安卓用的是和 Linux 同一份 swift-foundation（`FoundationEssentials` 等），JSON 的編解碼與 Linux 相同；`testFixturesUsePortableJSON` 也過了。
- 要守的：qemu 不是實機。12 月的 spike 要在實機（或 Firebase Test Lab 這類實機雲）再跑一次這三套（§8 驗收 1）。

### 4.2 GamePresentation 的 3D 網格：大多同值，EMU3000 不同

`Map3DModelPackLockTests` 把每個車型的每個頂點（`Float` 的 bitPattern）做雜湊，鎖在 `tools/train-models/hashes.lock.json`。網格用 `sin`／`cos`（`Float`），算這兩個函式的是各平台自己的 libm：Linux 是 glibc，安卓是 bionic，iOS 是 Apple 的 libm。三者不保證最後一位相同。

- 結果（qemu＋Android 14 bionic，GamePresentation 測試是 -Onone）：
  - `Map3DTests` 18/18、`Map3DTEMU2000Tests` 9/9、`Map3DFarSets422Tests` 3/3 全過。
  - `Map3DModelPackLockTests`：`testEveryModelIsAsLocked` 失敗，鎖住的 1,081 個模型只有 18 個不同，全是 EMU3000（`set-emu3000-*` 8 節、`set-emu3000Far-*` 8 節、`light-set-emu3000-head`／`-tail`）；`testTheOrderAndTheLampsAreAsBefore` 因為同一批模型，兩個整包摘要不同（`25d1ff1a4a7bd8cd`→`2e3aeff57d7ffe1`、`9ba8a2941836bb89`→`7b54f64b5f5f6f9b`）。
  - 對照：同一份 EMU3000 原始碼與同樣的 EMU3000 鎖值，在 `main` 7ca083b9 的夜間完整 CI（Linux，glibc）是綠的。
- 原因（已實測）：寫一個 C 小程式，`-fno-builtin` 各呼叫 20 萬次，比較 glibc（本機）與 bionic（qemu）的結果雜湊：`sinf`、`cosf`、`powf` 完全相同；**`atan2f`、`asinf` 不同**。EMU3000 是唯一用 `atan2f`／`asinf` 算頂點位置的鎖住車型（`Map3DEMU3000.swift` 第 254、260、286、372 行：車頭的圓角與車身斷面）；E500 的 `atan2f` 只拿來排序，結果沒變。
- 影響：
  - 不是存檔或遊戲規則的問題：GamePresentation 的網格不進存檔，GameCore 不用這些函式（§4.1）。差在最後一位，畫面看不出來。
  - 但逐位元的鎖不能直接搬到安卓。iOS 其實也一樣：雜湊在 Linux 上產生，沒有測試在 iOS 上比對；Apple 的 libm 很可能也有同樣的差異。
- 怎麼處理（Spike 1 的一部分，選一個）：
  1. 在 GamePresentation 自己寫 `atan2f`／`asinf`（只用加減乘除與 `sqrt`，IEEE 754 保證三個平台相同），讓三個平台逐位元一致。要改 EMU3000 的兩個呼叫點，Linux 上的雜湊會變一次，那張 PR 要逐值說明（照 CLAUDE.md 對鎖的規則）。
  2. 安卓上這個測試改用容許誤差比對，鎖照舊只在 Linux 逐位元。
  - 建議 1：之後新的車型配方也不會再踩到，且 iOS、安卓、Linux 三邊的網格真的相同。

## 5. 2D 地圖效能與安卓

### 5.1 現況

PERF114 量到 App 的 2D Canvas 全台縮圖約 8 fps：地面每秒約 442 ms、軌道每秒約 309 ms。數字是遊戲規劃轉述的，本研究沒有重量。

- `MapBaseCanvas`（`MapView.swift` 第 2604 行）每次相機一動，就用 `MapArt.drawBase`（`MapArt.swift`）在主執行緒以 `GraphicsContext` 把地面、街道、天際線、人口與通勤層重畫一遍。
- `MapCanvas`（第 2318 行）以同樣方式重畫軌道與車站。
- 平移、縮放都會變相機，所以每一格都要全部重畫；在 CPU 上畫上萬條路徑，自然慢。
- 投影已經抽成 `MapProjection`（GamePresentation，`MapCamera.swift` 第 134 行），這是共用的好起點。

### 5.2 三個方向，對安卓各省多少

| 方向 | iOS 上 | 安卓上 | 共用多少 |
| --- | --- | --- | --- |
| ① 畫一次存成點陣（每個縮放級一張圖磚或整張圖，相機動時只搬圖） | 最快能做（`ImageRenderer`／`CGContext`），一張 PR | `MapArt` 2,559 行的 `GraphicsContext` 畫法要用 Compose 的 `DrawScope` 或 `android.graphics.Canvas` 再寫一份 | 只有幾何與投影共用；畫法兩份 |
| ② 2D 也交給自製 GPU 後端：GamePresentation 把地面、軌道、車站做成三角形（世界座標，地圖或圖層有變才重做），每格只換相機矩陣 | 用現在的 Metal（加一條 2D pipeline） | 用 §2.3 的 Vulkan 後端，同一條 pipeline | **幾何全在 GamePresentation（Swift，Linux 可測），兩邊只差最底層**；平移縮放幾乎不花 CPU |
| ③ 軌道交給 MapLibre 的圖層（`FollowingMapLibreView.drawRailways`／`OSMMapBackground.drawRailways` 已這樣畫真實鐵道） | 已有做法；GPU 畫、MapLibre 自己處理縮放級 | MapLibre Android 有同樣的 GeoJSON source 與 line layer（Kotlin） | GeoJSON 與樣式可由 Swift 產生、兩邊共用；接法兩份，但每份只有幾百行 |

③ 的限制：

- 只在實景地圖有 MapLibre。`drawsLand: realWorld == nil`（`MapView.swift` 第 382 行），非實景的地圖由遊戲自己畫地面。
- 玩家每蓋一段軌道，GeoJSON 就要重切一次。軌道不常變，這可以接受；但每格都在動的列車不適合放進 GeoJSON。

建議：

- **主路是 ②。** 「畫一次存起來」存在 GPU 的頂點裡，地面、軌道、車站都走它，和 3D 共用底層。iOS 與安卓都省，而且三角形化的程式在 Linux 測得到。
- **③ 當補充。** 實景地圖上，玩家的軌道可以交給 MapLibre，和真實鐵道畫在同一套圖層，標籤避讓也一致（決策 189）。
- 列車、選取框、動畫留在 ② 的覆蓋層。
- ① 只當 iOS 的短期止血：它對安卓沒有幫助，做了之後要再拆。

## 6. 最低 Android 版本與硬體門檻（遊戲規劃補題）

作者在想 Android 14（API 34），對照 iOS 最低 17.0。iOS 17 支援 iPhone XS（2018），而 iPhone XS 有 4 GB RAM。

**建議：Android 12（API 31）＋必要 Vulkan 1.1＋RAM 4 GB 以上，最弱的晶片看實機量測再排除。** 系統版本只決定「多舊的手機」，擋不住「多弱的手機」，所以三項要一起看。

| 項目 | 建議值 | 怎麼設 |
| --- | --- | --- |
| 系統版本 | `minSdk 31`（Android 12） | `build.gradle` |
| Vulkan | 1.1 以上，必要 | `<uses-feature android:name="android.hardware.vulkan.version" android:version="0x401000" android:required="true"/>`。啟動時再檢查 Android Baseline Profile 2022，不合就用最低一格畫，並記進問題回報 |
| RAM | 總記憶體 3,200 MB 以上（4 GB 級） | Play Console「裝置目錄」→ 排除規則，依 RAM。4 GB 級的手機用決策 417／460 的最低一格 |
| 晶片 | 先不排除；實機量過最弱的 Mali-G52 MC2、G57 MC2 級，跌破目標的才列進排除 | Play Console 排除規則，依 SoC（只認得 API 31 以上的裝置，這也是選 API 31 的理由之一） |
| 驅動黑名單 | 實機或 Android vitals 發現崩潰的 GPU／驅動版本，在 App 裡改用最低一格或停用 3D | App 內的清單；做法同 Unity 6 的 Vulkan Device Filtering |
| targetSdk | 36（2026-08-31 起新 App 與更新都要） | `build.gradle` |

### 6.1 各版本以上的占比

| 下限 | Google（Android Studio，2026-10-19，heise 等轉述） | StatCounter 全球（2026-10，網頁瀏覽） | StatCounter 台灣（2026-10） |
| --- | --: | --: | --: |
| Android 12 以上 | 77.8% | 87.5% | 92.8% |
| Android 13 以上 | 68.2% | 80.3% | 87.7% |
| Android 14 以上 | 56.4% | 69.4% | 78.8% |

- Google 官方的 dashboard 頁已不列版本表，改要開發者看 Play Console 的「觸及率與裝置」。表裡 Google 那欄是 Android Studio 的資料，由媒體轉述，**沒有讀到 Google 原頁**。
- StatCounter 算的是網頁瀏覽次數，偏向較新、較常用的手機，所以比 Google 的裝置數高。
- 台灣的安卓手機整體比全球新：Android 14 的下限在台灣約擋掉 1／5，在全球（依 Google）約擋掉 4／10。

### 6.2 各下限擋掉的常見機型

| 機型（上市） | 最後的 Android | 12 下限 | 13 下限 | 14 下限 |
| --- | --- | --- | --- | --- |
| Galaxy S10（2019，與 iPhone XS 同代） | 12 | 留 | 擋 | 擋 |
| Pixel 3／3a（2018／19） | 12 | 留 | 擋 | 擋 |
| Galaxy S20（2020） | 13 | 留 | 留 | 擋 |
| Galaxy A51（2019／20） | 13 | 留 | 留 | 擋 |
| Pixel 4／4a（2019／20） | 13 | 留 | 留 | 擋 |
| ASUS Zenfone 8、ROG Phone 5／5s（2021） | 13 | 留 | 留 | 擋 |
| Redmi Note 10 Pro／10T（2021） | 13 | 留 | 留 | 擋 |
| OPPO Reno5／Reno6 5G（2020／21） | 13（之後有沒有 14 未確認） | 留 | 留 | 擋（未確認） |
| Redmi Note 10 Lite | 12 | 留 | 擋 | 擋 |
| Pixel 5／4a 5G（2020） | 14 | 留 | 留 | 留 |
| Galaxy A52／A52s（2021） | 14 | 留 | 留 | 留 |
| Galaxy A50（2019） | 11（未確認） | 擋 | 擋 | 擋 |
| Sony Xperia 1 II／5 II／10 III | 12 確認；13 未確認 | 留 | 未確認 | 擋 |

和 iPhone XS 同代（2018–19）的安卓旗艦多半停在 Android 12。所以 **Android 12 的下限最接近 iOS 17「XS 還能玩」的線**。Android 14 的下限會擋掉 2020–21 年的 S20、Pixel 4、Zenfone 8、ROG Phone 5，而這些手機的 GPU 比現在新賣的 4 GB 入門機還強。

### 6.3 便宜機：台灣 2025–26 年新賣的 4 GB 機

這些手機出廠就是 Android 14 或 15，**任何系統版本的下限都擋不到**：

| 機型 | RAM | 晶片（GPU，未逐一查證） | 台灣價格 |
| --- | --- | --- | --- |
| Galaxy A07 5G | 只有 4 GB | Dimensity 6300（Mali-G57 MC2） | NT$5,990，2026-08 街價 NT$4,190 |
| Galaxy A16 5G | 4 GB／6 GB | （未查） | NT$7,490／8,490 |
| Redmi 14C | 4 GB | Helio G81-Ultra（Mali-G52 MC2） | 街價最低 NT$2,850 |
| Redmi 15C | 台灣版 4 GB／8 GB | Helio G81-Ultra | NT$4,499 |
| OPPO A6x 5G | 只有 4 GB | Dimensity 6300 | NT$5,990 |

所以要擋便宜機，得靠 RAM、晶片與 Vulkan 的規則：

- **Play Console 的裝置目錄**可以訂排除規則：依 RAM（看裝置的總記憶體）、依 SoC，另有一個開關排除 Android Go 機。規則對之後新加入目錄的機型也有效；也能逐一排除型號。被排除的手機在 Play 上看不到、裝不了。內部測試的人不受限。系統版本不是排除規則，要用 `minSdk` 設。
- **manifest** 可以用 `uses-feature` 要求 Vulkan 版本，或用 `glEsVersion` 要求 GLES 版本；Play 會濾掉缺這個功能的手機。
- **Vulkan 1.1 以上**涵蓋 88.8% 的手機，1.3 以上只有 26.7%（Google dashboard，2025-11-24）。Android 13 起出廠的手機規定要支援 1.3，但市場上的舊機還很多，所以要求 1.3 太嚴。Google 給遊戲的建議下限是「Android 10＋Vulkan 1.1＋ABP 2022」。只有 1.0 的手機驅動多半有問題（Godot 維護者的說法）；要求 1.1 正好把它們排掉。
- **RAM 要擋到哪**：
  - 擋 4 GB 機，就擋掉 A07、A6x、Redmi 14C／15C 這一整群入門機，也和 iOS 不一致（XS 是 4 GB，iOS 仍支援）。
  - 建議留 4 GB，用決策 417、460 的最低一格（三角形預算 250,000）畫；只擋 4 GB 以下（總記憶體不到 3,200 MB）。
  - 要注意 Play 的新記憶體指標：遊戲在 4 GB 級手機上前景用量超過 **2.25 GB**（6 GB 級 2.75 GB、8 GB 級 3.5 GB），**2027 年 2 月**起可能降低曝光。Spike 2、3 要量 4 GB 實機的用量。
- **Android vitals**：
  - 使用者感受到的閃退率 1.09%、ANR 0.47% 是整體門檻；單一機型 8%。28 天平均，超過時 Play 可能降低曝光、在商店頁加警告。
  - 沒找到「低階機佔壞指標多少」的公開數字。vitals 會指出錯誤率和 RAM、系統版本、SoC 的關聯；Google 自己的建議是修不了就調整排除規則。
  - 所以排除規則是**上架後依 vitals 調整的工具**，不必一次訂死。

### 6.4 各元件的最低 API

| 元件 | 最低 API | 來源 |
| --- | --- | --- |
| Swift SDK for Android | 28（swift.org 平台表寫 Android 9）；SDK 本身有 23–36 的 triple | §1 實測用 28 |
| MapLibre Native Android 12.0 起 | 23 | CHANGELOG |
| Jetpack Compose 1.10 起 | 23 | Google Maven 的 AAR |
| Play Games Services v2 22.1.0 | 24 | Google Maven 的 AAR |
| Vulkan 1.1（Google 的保證：64 位元、Android 10 起） | 29 | Android 開發者文件 |
| Play 的 SoC 排除規則、ADPF 效能提示 API | 31 | Play 說明、ADPF 文件 |

元件最高的要求是 29。選 31，是因為：晶片排除規則只認得 API 31 以上的裝置；ADPF 的效能提示 API 從 31 才有；最接近 iOS 的世代線；要測的版本也少三個（10、11 不用測）。

### 6.5 五方（最低規格）

- 玩家：台灣約 93% 的安卓手機系統夠新（StatCounter，網頁瀏覽口徑）；4 GB 的入門機能玩，畫質用最低一格。真的跑不動的晶片在 Play 上直接看不到，不會買了才發現卡。
- 鐵道迷：無直接關係；2020–21 年的舊旗艦（S20、Zenfone 8、ROG 5）留著，這群玩家多半是愛玩模擬的人。
- 開發：要測的系統版本是 12–17；Vulkan 1.1 一條路，不寫 GLES 後備；便宜機用 Play 的 RAM、晶片規則與 App 內的驅動黑名單擋，上架後照 vitals 調整。
- 美術：最低一格（決策 417 的 250,000 三角形）就是 4 GB 機看到的樣子，要在一台 Mali-G52／G57 級的實機上截圖確認看得過去。
- 音樂：無。

## 7. 先找現成的：查了什麼、找到什麼

### 7.1 作者的參考庫（`a91453/railway-reference-private`，`ea6f7877`，blobless clone）

先在全部 11,929 個檔名裡找 `android`、`gradle`、`kotlin`、`vulkan`、`filament`、`bgfx`、`wgpu`、`godot`、`unity`、`maplibre`，再讀命中的檔。

| 參考檔 | 對應到這裡 | 能用多少 |
| --- | --- | --- |
| `Railway/taiwan-rail-reference-clean/source/app/android/`（Capacitor 安卓殼，44 個 Java 檔：小工具、通知、`RailNativeL10n`、`RailStorePlugin` 等） | 安卓版的入口、通知、在地化 JSON 的讀法 | 只有殼與小工具；沒有遊戲的 3D 或地圖渲染。`RailNativeL10n.json` 的雙語資料格式可參考 |
| `Railway/*/source/vendor/maplibre-gl*`（MapLibre GL JS，BSD-3） | 樣式 | MapLibre GL JS 與 Native 共用同一份樣式規格。遊戲的底圖樣式已由 `BaseMapStyle.swift`（GamePresentation）產生 JSON，安卓的 MapLibre 直接吃同一份；PMTiles 圖磚照用（要確認 Android 13.x 的 `pmtiles://` 支援，§8 spike 2） |
| `Railway/world-rail-reference-clean/rights/app/licenses/CAPACITOR-*-MIT.txt` | | 只證明網站版用 Capacitor（MIT） |
| 其他（`Simulator/`、`MapBuilder/`、`OpenWorld/` 等） | | 都是網頁（Three.js、MapLibre GL JS），沒有原生安卓的渲染或 Vulkan 程式 |

結論：參考庫沒有能直接搬的安卓 3D 或地圖渲染程式；樣式規格與資料檔可以共用。

### 7.2 開源專案

| 專案 | 網址 | 授權 | 能不能用 |
| --- | --- | --- | --- |
| Swift SDK for Android | https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html | Apache-2.0 | 用（工具鏈，不是 App 依賴） |
| swift-java | https://github.com/swiftlang/swift-java | Apache-2.0 | 可用；0.7.0，還沒 1.0。加進專案要作者同意 |
| MapLibre Native Android | https://github.com/maplibre/maplibre-native | BSD-2 | 用（iOS 已用同一專案） |
| maplibre-compose | https://github.com/maplibre/maplibre-compose | BSD-3 | 可用，0.20.0、還沒 1.0；也可以直接用 Android View |
| wgpu／wgpu-native | https://github.com/gfx-rs/wgpu-native | MIT 或 Apache-2.0 | 退路（§2.3），要作者同意 |
| bgfx | https://github.com/bkaradzic/bgfx | BSD-2 | 不建議（§2.3） |
| Filament | https://github.com/google/filament | Apache-2.0 | 不建議（§2.3） |
| Diligent Engine、The Forge | https://github.com/DiligentGraphics/DiligentEngine 、https://github.com/ConfettiFX/The-Forge | Apache-2.0 | 不建議：沒有 Swift 綁定，規模大 |
| Skip | https://skip.dev 、https://github.com/skiptools/skip-ui | skip-ui 等 MPL-2.0；skipstone AGPL-3.0 | copyleft：要作者決定 |
| SwiftGodot | https://github.com/migueldeicaza/SwiftGodot | MIT | 安卓支援沒驗證 |
| Godot | https://github.com/godotengine/godot | MIT | 不換（§2.2） |
| Mesa lavapipe | https://docs.mesa3d.org/drivers/llvmpipe.html | MIT | CI 的工具，不進 App（§8） |
| shaderc／glslc（NDK 自帶） | https://github.com/google/shaderc | Apache-2.0 | 建置工具，不進 App |

## 8. 12 月的步驟與第一個 spike

每一步一張 PR，不動 GameCore 的行為、存檔、golden；加依賴的步驟先問作者。

**Spike 1（第一張，約一個 session）：安卓上的 Swift 核心＋CI**

- 做：
  - §1 的兩處小改（GamePresentation 加 `import Android`、測試的 `getrusage`）。
  - 一個 `android-probe.yml`：Linux 容器裡裝 Swift 6.4 的 Android SDK 與 NDK 30，`swift build --swift-sdk aarch64-unknown-linux-android28 --build-tests`，再用 qemu＋bionic 跑 Golden、SavedGame、Replay。照 Wasm Probe 的觸發條件：只在 GameCore、GoldenScenarios 等改到時跑。
- 驗收：
  1. 三套 fixture 在 aarch64-android 全過。另外，作者有實機時，用 `adb push` 在一台實機跑一次。
  2. 3D 模型雜湊鎖在安卓上的處理定案並落地（§4.2：自寫 `atan2f`／`asinf`，或安卓用容許誤差）。
  3. `swift build -Xswiftc -warnings-as-errors` 在 Linux 照樣乾淨。
  4. 本機與 CI 都不加任何 Package 依賴。

**Spike 2：一個 Android App 殼**

- 做：
  - Gradle 專案，放在 repo 的 `Android/`。
  - 一個 Activity，用 swift-java（JNI）載入 GameCore 的 `.so`，開一局示範遊戲、推進 1 遊戲小時，畫面上顯示站數與車數。
  - 用 MapLibre Android 13.x 開台北的底圖：`BaseMapStyle` 產生的 JSON，加上 App 自帶的 `taiwan.pmtiles`。
- 驗收：
  1. 一台 Android 12 以上的實機能開，地圖與數字正確；最好再加一台 4 GB 的入門機（§6.3）。
  2. 量 APK 大小（Swift 執行環境預計多 50–60 MB）與冷啟動時間。
  3. 寫下 swift-java 要不要成為正式依賴（作者決定）。

**Spike 3：Vulkan 後端的第一張圖**

- 做：
  - 把 `Map3DMetalView` 用到的東西抽成一個小介面（建 buffer、建 pipeline、畫、換相機）。
  - Vulkan 版先畫天空（§1 已翻好的 shader）、一塊地面、一列車，在 Linux 用 lavapipe 輸出 PNG。
- 驗收：
  1. Linux CI 上 lavapipe 輸出的圖，與一張檢查過的參考圖逐像素比對（容許誤差寫明）。
  2. 同一份程式在 Spike 2 的 App 裡，在實機上畫出同一個畫面。
  3. 量 GPU ms 與幀間隔 p95，用決策 421 V1 的量法。

**之後**：

- 2D 的 GPU 後端，見 §5 的 ②。這一步 iOS 先受益，可以和 PERF114 的修正合併考慮。
- Compose 的畫面，照 §3 的順序。
- Google Play 的上架準備：targetSdk 36、雲端存檔、Play Games。

## 9. 五方

**整體建議（A＋Compose）**

- 玩家：遊戲規則、存檔與 iOS 完全相同（已驗 golden、存檔、重播），兩邊玩到的是同一個遊戲；安卓版的按鈕與手勢是安卓自己的樣子。
- 鐵道迷：真實路網、時刻、車型配方都在共用的 Swift 裡，安卓不會少一條線或一款車；地圖仍是 MapLibre＋同一份台灣圖磚。
- 開發：要寫的是 Vulkan 後端與 Compose 畫面，不是重寫遊戲；所有 Linux 測試照用，Vulkan 也能在 Linux CI 測；不新增圖形依賴。
- 美術：35 個模型工具與車型配方照用，同一個模型兩邊長一樣；只要確認 shader 翻成 GLSL 後色調一致（Spike 3 的比對圖）。
- 音樂：無（音效檔照用，播放改用安卓的 API）。

**不選 Unity／Godot**

- 玩家：短期看不出差別；長期 iOS 與安卓的 3D 若各走一套，畫面與修好的問題會不同步。
- 鐵道迷：車型配方若改寫成 C#／GDScript，加一款車要做兩次。
- 開發：3D 的 Linux 測試（約 15k 行）失效，或每幀要經 C 介面搬資料；多一個引擎要升級。
- 美術：要學新的編輯器；程式產生的車型要先匯出 GLB。
- 音樂：無。

**2D 走 GPU 後端（§5 ②）**

- 玩家：全台縮圖從約 8 fps 變順（要實機量）。
- 鐵道迷：無。
- 開發：三角形化放在 GamePresentation，Linux 測得到；iOS、安卓共用。
- 美術：2D 的顏色與線寬照 `MapArt` 的規則搬，要對照截圖。
- 音樂：無。

## 10. 來源（存取日期都是 2026-11-05）

- Swift 6.3（Android SDK 第一個正式版）：https://swift.org/blog/swift-6.3-released/
- Swift 6.4（NDK 30、Swift Build 支援安卓、swift-java 更新）：https://www.swift.org/blog/swift-6.4-released/
- Swift SDK for Android 入門：https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html
- swift.org 平台支援表（Android 9／API 28）：https://www.swift.org/platform-support/
- swift.org 的 `releases.json`（Android SDK 的 checksum）：https://www.swift.org/api/v1/install/releases.json
- 探索 Swift SDK for Android（Foundation、Dispatch、除錯現況）：https://www.swift.org/blog/exploring-the-swift-sdk-for-android/
- swift-java：https://github.com/swiftlang/swift-java
- swift-android-examples：https://github.com/swiftlang/swift-android-examples
- skiptools/swift-android-action：https://github.com/skiptools/swift-android-action
- Skip 免費（1.7，2026-01-21）：https://skip.dev/blog/skip-is-free
- Skip 模式（Fuse／Lite，大小）：https://skip.dev/docs/modes/
- skip-ui 支援表：https://github.com/skiptools/skip-ui
- skipstone（AGPL-3.0）：https://github.com/skiptools/skipstone
- Polymarket 的 Swift 安卓 App：https://forums.swift.org/t/our-android-app-is-written-in-swift/88778
- MapLibre Native Android 版本（Maven Central）：https://repo1.maven.org/maven2/org/maplibre/gl/android-sdk/
- MapLibre Native Android CHANGELOG（Vulkan 預設、Adreno 修正、自訂圖層）：https://github.com/maplibre/maplibre-native/blob/main/platform/android/CHANGELOG.md
- MapLibre Android Vulkan 公告：https://maplibre.org/news/2024-12-12-maplibre-android-vulkan/
- maplibre-compose：https://github.com/maplibre/maplibre-compose
- Filament：https://github.com/google/filament
- bgfx：https://github.com/bkaradzic/bgfx
- wgpu-native：https://github.com/gfx-rs/wgpu-native
- Unity 價格（2026-01-12 調整）：https://unity.com/products/pricing-updates
- Unity 取消 Runtime Fee：https://unity.com/blog/unity-is-canceling-the-runtime-fee
- Unity 6.3 安卓需求：https://docs.unity.com/en-us/engine/6000.3/manual/platform-specific/android/introducing/requirements-and-compatibility
- Godot 4.7 安卓建置設定：https://github.com/godotengine/godot/blob/4.7/platform/android/java/app/config.gradle
- Godot renderer：https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- SwiftGodot：https://github.com/migueldeicaza/SwiftGodot
- Android 分布（Vulkan、GLES）：https://developer.android.com/about/dashboards
- Android Vulkan 概觀（85%、ANGLE）：https://developer.android.com/games/develop/vulkan/overview
- Android 16 CDD：https://source.android.com/docs/compatibility/16/android-16-cdd
- Google Play 目標 API 要求：https://developer.android.com/google/play/requirements/target-sdk
- 實作 Vulkan（依出廠版本的要求）：https://source.android.com/docs/core/graphics/implement-vulkan
- 遊戲引擎的 Vulkan 建議下限（Android 10＋1.1＋ABP 2022）：https://developer.android.com/games/develop/vulkan/native-engine-support
- Android 版本分布，2025-12-01（Android Studio 資料，媒體轉述）：https://9to5google.com/2026/01/30/android-16-is-on-7-5-of-devices-in-latest-distribution-numbers-update/
- Android 版本分布，2026-10-19（Android Studio 資料，媒體轉述）：https://gadgets.beebom.com/news/google-android-17-adoption-figures-october-2026 、https://helentech.jp/?p=93101
- StatCounter 台灣、全球（2026-10）：https://gs.statcounter.com/android-version-market-share/mobile-tablet/taiwan 、https://gs.statcounter.com/android-version-market-share/mobile-tablet/worldwide
- 機型最後的 Android 版本：
  - Galaxy S10：https://www.androidcentral.com/samsung-galaxy-s10-android-12-us
  - Galaxy S20：https://9to5google.com/2023/01/10/galaxy-s20-one-ui-5-1-update/
  - Galaxy A51：https://www.sammobile.com/news/galaxy-a51-5g-one-ui-5-1-update-released/
  - Galaxy A52：https://www.sammobile.com/news/galaxy-a52-one-ui-6-android-14-update/
  - Pixel 3：https://gizmodo.com/rip-pixel-3-1847985883
  - Pixel 4：https://www.itechtics.com/eol/google-pixel/
  - Pixel 5：https://www.droid-life.com/2023/09/21/your-pixel-5-and-pixel-4a-5g-are-at-the-end-of-the-road/
  - Redmi Note 10 Pro：https://androidkenya.com/2024/03/redmi-note-10-pro-and-note-10-pro-max-hyperos-update/
  - Redmi Note 10 Lite：https://miuirom.org/ja/phones/redmi-note-10-lite
  - Zenfone 8：https://9to5google.com/2023/01/16/asus-zenfone-8-android-13/
  - ROG Phone 5：https://www.slashgear.com/1101846/here-are-the-asus-rog-phones-getting-android-13-upgrades
  - OPPO Reno5／Reno6：https://www.gizchina.com/phones/coloros-13-android-13-is-now-available-for-these-oppo-phones
  - Sony Xperia：https://www.phonearena.com/news/sony-xperia-5-II-android-12-update-rollout_id138869
- 台灣 4 GB 機：
  - Galaxy A07 5G：https://www.sogi.com.tw/articles/samsung-galaxy-a07-5g-sale/6269392
  - Galaxy A16 5G：https://technews.tw/2024/10/09/galaxy-a16-5g/
  - Redmi 14C：https://www.sogi.com.tw/articles/sale-redmi-14c/6266504
  - Redmi 15C：https://www.sogi.com.tw/articles/redmi-15c/6266990
  - OPPO A6x：https://technews.tw/2026/01/15/oppo-a6-series/
- Play Console 裝置目錄與排除規則：https://support.google.com/googleplay/android-developer/answer/7353455
- 裝置分級與群組：https://developer.android.com/google/play/device-targeting
- `uses-feature`（Vulkan、GLES）：https://developer.android.com/guide/topics/manifest/uses-feature-element
- ADPF：https://developer.android.com/games/optimize/adpf
- Android vitals（門檻、記憶體指標）：https://developer.android.com/topic/performance/vitals
- Unity Vulkan 裝置篩選：https://docs.unity3d.com/Manual/introduction-vulkan-device-filtering-asset.html
- Godot：只有 Vulkan 1.0 的驅動：https://github.com/godotengine/godot/issues/92327
- AndroidX 版本（minSdk 23）：https://developer.android.com/jetpack/androidx/versions
- Play Games Services v2 的版本：https://dl.google.com/android/maven2/com/google/android/gms/play-services-games-v2/maven-metadata.xml
