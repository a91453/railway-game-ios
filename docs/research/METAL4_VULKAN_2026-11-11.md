# Metal 4 與 Android Vulkan 研究（2026-11-11）

派工單 METAL4-STUDY，研究 session_01YGNNumWbPFo4WN84YWcvPP，遊戲規劃第 60 任（session_01YGNNumCi7AYjpiS4ntJZjK）派。作者 2026-11-11：「順便開一個session研究metal4／還有安卓vulken 怎麼適配metal4」。只有這份文件：不動程式、決策號、存檔版本、golden，不加相依。基準 `main` `b72f1b3f`。

## 給作者的白話摘要

1. Metal 4 是蘋果在 iOS 26 給的新版畫圖方式。它主要幫「畫面非常複雜的大型遊戲」省力；我們的 3D 地圖沒有那麼複雜，整個換過去幾乎沒有好處，而且 iPhone 11 和幾台舊 iPad 用不了，等於要養兩套。**建議不換。**
2. 跟著一起出的「補幀」和「放大畫面」是另一包東西，不用換成 Metal 4 也能用。這兩樣對我們有用：舊手機可以少畫一點、看起來一樣順或一樣清楚。
3. 兩樣裡先做「放大畫面」比較划算：改動較小，Android 也有免費、可商用的對應做法。「補幀」在 Android 沒有公開可用的對應，做了就是 iPhone 獨有。
4. 做之前要先在實機量：現在慢是慢在顯示晶片，還是慢在處理器。只有前者，這兩樣才幫得上忙。這一步不用改程式，Mac 那邊順手就能量。
5. 光線追蹤、把 AI 放進畫圖：我們的畫風用不到，先不做。
6. Android 版：遊戲規則和 3D 模型的配方都不用重寫（11 月 5 日的研究已經實測過）。真正要重做的是「把東西畫到螢幕」那一小層和「按鈕與面板」那一大層。
7. Android 用的 Vulkan 和我們現在的畫法幾乎一對一，可以逐段照著翻。着色器沒有工具能自動從蘋果的寫法轉過去，要手翻一次（約一千行）。
8. 這些項目的分數都沒有比現在排著的工作高，不用改順序。
9. 幀率、耗電、發熱的數字，雲端量不到，文件裡都標了「未驗證」。

## 0. 怎麼讀這份

- **〔官方〕**：這次（2026-11-11）實際讀到的 Apple、Google、Khronos、swift.org 或專案自己的頁面，句尾有網址。
- **〔推測〕**：這個 session 從官方內容與本專案的程式推出來的，沒有官方的句子可以引。
- **〔未查到〕**：想查但沒讀到原文的。
- 授權都是讀各專案自己的授權檔；能不能用照 CLAUDE.md：MIT、BSD、Apache-2.0、zlib 可以搬（保留聲明），copyleft 與沒授權的只看不抄；**加相依一律要作者同意**。
- 沒有建置或執行任何東西。所有效能判斷都是 **UNVERIFIED**（需要 Mac／實機）。

## 1. 現在的 3D 地圖怎麼畫

實際讀的檔（`main` `b72f1b3f`）：

| 層 | 檔 | 行數 | 說明 |
| --- | --- | --: | --- |
| 繪圖（App） | `RailwayGameApp/Views/Map3D/Map3DMetalView.swift` | 1,960 | `MTKView` 的子類別。`import Metal`、`MetalKit`。整個 App 只有這個檔、`Map3DPreviewScreen.swift` 與 `App/FrameTimeRecorder.swift`（269 行）import Metal |
| 着色器 | `RailwayGameApp/Views/Map3D/Map3DShaders.metal` | 1,070 | 全部着色器在這一個檔：13 個 vertex、10 個 fragment 函式 |
| 3D 邏輯（共用） | `Sources/GamePresentation/Map3D*.swift`（237 檔） | 66,504 | 場景、網格、車型配方、遠近模型、預算、相機、串流。只 import Foundation、GameCore、Observation，Linux 上有測試 |

沒有用 SceneKit、RealityKit、SpriteKit、MetalFX、Model I/O。

畫法（都是傳統的 Metal，也就是 Apple 現在說的「Metal 3 programming model」）：

- 前向繪製，每幀最多兩個 render pass：太陽陰影圖（`depth16Unorm`，只在需要時重畫）與主畫面（`bgra8Unorm`，沒有 HDR、沒有後製用的 render target）。
- 16 條 `MTLRenderPipelineState`，開畫面時用 `makeRenderPipelineState` 同步建好；`makeDefaultLibrary()` 讀建置時編好的着色器。
- 繪製呼叫 25 處（`drawPrimitives`／`drawIndexedPrimitives`），大量用 instancing（遠景方塊、模型、看板、光暈、雨絲）。綁定用 `setVertexBuffer`／`setFragmentTexture` 一類共 49 處。
- 反鋸齒是 MSAA：一般 4 倍、省電 1 倍（決策 365）。
- 幀率目標 60，省電 30（`Map3DQuality.Plan`）。GPU 超過預算（一幀的 60%）就少畫像素：3× 螢幕改畫 2×2（`Map3DDrawScale`，決策 238 後記、460）；放大交給系統的圖層，沒有自己的升頻。
- 緩衝用 `.storageModeShared`，每幀的緩衝三份輪替（`Map3DFrameBuffers`），用 semaphore 擋住超過三幀。
- 沒有 motion vector、沒有可讀回的深度（MSAA 深度不保留）。這一點決定了 §3 補幀與時間升頻的改動大小。

機型：決策 676 之後最低 iOS 26。最慢的 iPhone 是 A13（iPhone 11、SE 第 2 代），**iPad 仍有 A12**（iPad Air 第 3 代、iPad 第 8 代）。

既有的結論：決策 676「查過的做法」已寫「用 Metal 4 重寫 3D：不做」。這份研究的結果與它一致，並補上細項與 MetalFX。

## 2. Metal 4 是什麼、多了什麼

來源代號：

- [205] Discover Metal 4：https://developer.apple.com/videos/play/wwdc2025/205/
- [254] Explore Metal 4 games：https://developer.apple.com/videos/play/wwdc2025/254/
- [211] Go further with Metal 4 games：https://developer.apple.com/videos/play/wwdc2025/211/
- [262] Combine Metal 4 machine learning and graphics：https://developer.apple.com/videos/play/wwdc2025/262/
- [Core] Understanding the Metal 4 core API：https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api
- [FST] Metal Feature Set Tables（PDF，2026-10-23 版）：https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
- [MSL] Metal Shading Language Specification（現在是 4.1）：https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
- [Tri] 範例 Drawing a triangle with Metal 4：https://developer.apple.com/documentation/metal/drawing-a-triangle-with-metal-4

### 2.1 核心〔官方〕

- 同一個 framework 裡的新型別，名字以 `MTL4` 開頭，和原本的 `MTL` 型別互相獨立 [205][Core]。
- Apple 講的好處：執行效能、記憶體效率，以及「更容易從 DirectX 與 Vulkan 移植過來」[Core]。
- **支援的機型**：A14 Bionic 以後、M1 以後 [205]；[FST] 寫「Metal 4 programming model is available as of Apple7」。執行時用 `device.supportsFamily(.metal4)` 判斷（https://developer.apple.com/documentation/metal/mtlgpufamily/metal4 ）。
- **舊 API 沒有被淘汰**：`MTLCommandQueue` 等沒有 deprecated 標記（https://developer.apple.com/documentation/metal/mtlcommandqueue ），[FST] 寫 Metal 3 的寫法「所有 Apple GPU 都能用」。四場 WWDC 都沒有說要淘汰。
- **可以分階段換** [Core][205]：App 的一部分可以單獨改用 `MTL4CommandQueue`，新舊 queue 用 `MTLEvent`／`MTLSharedEvent` 同步。Apple 建議的順序是：編譯 → 指令 → 資源管理。
- `MTKView` 可以用：有 `currentMTL4RenderPassDescriptor` 與 `residencySet`（https://developer.apple.com/documentation/metalkit/mtkview ）。

| 新東西 | 做什麼〔官方〕 | 來源 |
| --- | --- | --- |
| `MTL4CommandQueue`／`MTL4CommandBuffer`／`MTL4CommandAllocator` | command buffer 可重複使用、不替你保留資源；記憶體由 allocator 管，每個進行中的幀一個，GPU 做完後 `reset()` | [Core][254] |
| `MTL4RenderCommandEncoder` | 沒有逐項綁定的方法；跨 command buffer 的 suspend／resume 取代平行編碼 | [Core] |
| `MTL4ArgumentTable` | 綁定放進一張表，各階段與 encoder 共用 | [Core] |
| `MTLResidencySet` | 一次宣告哪些資源要留在 GPU；Apple 稱「easy win」，建議少而大的集合 | [205][254] |
| 明確的 barrier | Metal 4 把所有資源都當成不追蹤，階段之間的同步自己寫 | [Core][254] |
| placement sparse、`MTLTextureViewPool` | 稀疏資源自己配頁；輕量的 texture view 池。placement sparse 要 Apple8（A15）起，查 `supportsPlacementSparse` | [205][254][FST] |
| `MTL4Compiler`、可延後指定的 pipeline、預先編譯 | 編譯器獨立於 device、照呼叫執行緒的 QoS；unspecialized pipeline 編一次再依輸出格式特化（Apple 註明特化的有「小的 GPU 開銷」）；`metal-tt` 預先編成 archive，載入時間「幾乎為零」，沒命中要自己處理 | [205][254] |
| `MTLTensor`、`MTL4MachineLearningCommandEncoder`、Shader ML | 在 GPU 時間線上跑 Core ML 格式的網路；着色器裡直接做小型推論 | [205][262] |
| 光線追蹤的更新 | intersection function buffer（對應 DirectX 的 shader binding table）、建加速結構的新旗標 | [211] |
| MSL 4.0 | 改以 C++17 為基礎（之前是 C++14）；加 tensor 型別、per-vertex values、sampler LOD bias 等 | [MSL] |
| 工具 | Xcode 26 有 Metal 4 遊戲樣板；API／Shader Validation、Metal Debugger、Performance HUD、Metal System Trace 都支援 Metal 4 | [205][254] |

**Apple 沒有公布 Metal 4 的幀率或 CPU 時間數字**。四場演講唯一的數字是神經網路材質壓縮「佔 block 壓縮的 50%」[262]；其他都是定性的說法。

### 2.2 MetalFX（不需要換成 Metal 4）〔官方〕

[FST] 把下面四項都列在「Metal 3 & 4」，所以**現在的寫法就能用**。

| 功能 | 最低 GPU | iPhone／iPad 晶片 | 系統 | 要給它什麼 |
| --- | --- | --- | --- | --- |
| 空間升頻 `MTLFXSpatialScaler` | Apple3 | A9 起 | iOS 16 | 一張低解析度的顏色圖 |
| 時間升頻 `MTLFXTemporalScaler` | Apple7 | A14、M1 起 | iOS 16 | 顏色、深度、motion vector，並每幀抖動投影 |
| 補幀 `MTLFXFrameInterpolator` | Apple5 | A12 起 | iOS 26 | 前後兩幀、motion vector、深度；Apple 建議補之前至少 30 fps [211] |
| 去雜訊升頻 `MTLFXTemporalDenoisedScaler` | Apple9 | A17 Pro 起、M3 起 | 見註 | 光線追蹤的輸入（法線、albedo、粗糙度） [211] |

- 每個 descriptor 有 `supportsDevice(_:)` 可在執行時查（https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor ）。
- 註：去雜訊升頻的文件頁寫 iOS 18.0／macOS 26.0（https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscaler ），和它在 WWDC25 才發表對不上，原因〔未查到〕。它只給光線追蹤用，和我們無關。
- 2025 年時間升頻另加：動態解析度輸入、reactive mask、曝光除錯工具 [211]。

### 2.3 其他〔官方〕

- Game Porting Toolkit 3 與 Metal shader converter（DXIL → metallib）是給 HLSL／Windows 遊戲移植用的（https://developer.apple.com/games/game-porting-toolkit/ 、https://developer.apple.com/metal/shader-converter/ ）。我們的着色器本來就是 MSL，用不到。

## 3. 這個遊戲用得上哪些

「要改多大」是照 §1 的現況估的〔推測〕；行數只說明範圍，不是工時。全部的幀率、耗電、發熱、記憶體都是 **UNVERIFIED（要 Mac／實機）**。

| 代號 | 項目 | 機型 | 要改什麼 | 風險 | 只能在 Mac／實機驗的 |
| --- | --- | --- | --- | --- | --- |
| **M** | 先量：用 Metal Performance HUD、Metal System Trace 與 App 自己的 3D 面板，在 A13、A12 與新機上分清楚是 GPU 慢還是 CPU 慢 | 全部 | 不改程式 | 無 | 全部 |
| **U1** | 空間升頻：少畫像素時（`Map3DDrawScale` 降到 2×2）改畫到自己的低解析度圖，再用 MetalFX 放大到螢幕 | A9 起，等於全部 | `Map3DMetalView`：加一張 render target 與一個 scaler，主 pass 改畫到它（MSAA 照舊先 resolve）。着色器不動。約一兩百行 | 多一張圖的記憶體；看板小字與細線放大後的樣子；截圖路徑（`capture`）要跟著改 | 清楚了多少、GPU 時間多了多少 |
| **U2** | 時間升頻取代 MSAA 4×：每幀抖動投影，輸出深度與 motion vector | A14 起；A13、A12 留原本的 MSAA | 每條不透明的 pipeline 都要多輸出 motion vector（13 個 vertex 函式要帶上一幀的位置；instance 也要留上一幀的矩陣）；深度改成可讀回；玻璃、光暈、雨絲等透明物要 reactive mask。動到 `.metal` 的大半與每幀緩衝 | 兩條路要一起維護；細的架空線、標線可能閃或拖影；看板文字 | 畫質、拖影、GPU 時間 |
| **F** | 補幀：省電的 30 補成 60，或 60 補成 120 | A12 起（全部） | 需要的輸入和 U2 一樣（motion vector、深度），另外要自己安排「真的一幀、補的一幀」各自何時顯示；`MTKView` 自動呈現的做法要改 | 補的那幀裡，貼在 3D 上面的 SwiftUI 面板不受影響〔推測：它們是另外的圖層〕，但 3D 裡自己畫的看板字、車號可能糊；輸入延遲多半幀到一幀；120 Hz 要 Info.plist 另開（現在沒開） | 順不順、延遲、耗電 |
| **C** | 着色器預先編譯（`MTL4Compiler`＋archive），縮短第一次開 3D 的等待 | A14 起 | 建置多一步產生 archive；載入改走新編譯器，舊機型留原路 | 只有 16 條 pipeline，現在花多久沒量過；可能省不到看得出來的時間 | 現在開 3D 時編 pipeline 花幾毫秒 |
| **Q** | 整個換成 Metal 4 的指令與資源模型（`MTL4CommandQueue`、argument table、residency set、barrier） | A14 起；A13、A12 要留舊的 | `Map3DMetalView` 幾乎重寫，並且兩套並存 | 兩套都要測；barrier 寫錯是難查的畫面錯誤；Apple 沒給數字，我們一幀約一兩百個 draw，本來就不是 CPU 編碼的瓶頸 | 全部 |
| **R** | 光線追蹤（陰影、反射） | 〔未查到〕這次沒查各晶片的支援表 | 加速結構、新的着色器、去雜訊；196 萬棟建物與串流的場景要建加速結構 | 發熱、記憶體；和扁平、頂點上色的畫風不合；Android 上對應的機型很少〔推測〕 | 全部 |
| **N** | 機器學習進繪圖（Shader ML、神經網路材質壓縮） | A14 起 | 我們幾乎沒有材質貼圖（頂點上色、少數 atlas），沒有可壓的東西 | 沒有用處 | — |

補充判斷〔推測〕：

- **U1、U2、F 只在 GPU 是瓶頸時有用**。決策 485 與 HANDOFF §4.29 量到的 3D 跟車 10× 是主執行緒（CPU）的問題；CPU 不夠時，升頻沒有幫助，補幀只是把不順的畫面補得比較密。所以先做 M。
- **F 與 U2 共用最貴的一塊**（motion vector 與可讀的深度）。要做其中一個，另一個就便宜很多。
- **規則**：HANDOFF §1.1「新的 3D 功能不准用只有 Metal 才有的功能」（2026-11-08）。MetalFX 只有 Apple 有。U1、U2 在 Android 有可商用的對應（§4.4），可以寫成「可關掉、兩邊各有實作」的畫質選項；**F 在 Android 沒有公開授權的對應**，做了就是 iOS 獨有，要規劃明說例外才能做。
- Q 的好處對我們最小：Metal 4 的指令模型和 Vulkan 很像，看起來像是替 Android 鋪路，但 iOS 還要留舊路給 A13／A12，等於三套。Android 版直接照現在的 Metal 寫法對翻就夠（§4.1）。

## 4. Android：Vulkan 怎麼對應

先說範圍：`docs/research/ANDROID_PORT_STUDY_2026-11.md`（2026-11-05）已經實測並決定了大方向（Swift 官方 Android SDK 共用 GameCore 與 GamePresentation、3D 自寫 Vulkan 1.1 後端、地圖 MapLibre Native、畫面 Compose 重寫、最低 Android 12＋Vulkan 1.1＋RAM 4 GB）。這一節只補它沒寫的：概念對照、Metal 4 的關係、着色器互轉、升頻與補幀的對應、這次重查的授權。和它不同的地方會註明。

### 4.1 概念對照

Apple 沒有出 Metal↔Vulkan 的對照表；下表每一列都是〔推測〕，根據 [Core] 與 Vulkan 的章節。Vulkan 規格頁（docs.vulkan.org）這個環境讀不到（403），所以規格的句子〔未查到〕；Khronos 的 Vulkan Guide 讀到的是「explicit API，把更多工作與責任交給應用程式」（https://github.com/KhronosGroup/Vulkan-Guide/blob/main/chapters/what_is_vulkan.adoc ）。

| 我們現在用的（Metal） | Metal 4 的說法 | Vulkan | 差在哪 |
| --- | --- | --- | --- |
| `MTLDevice` | 同 | `VkPhysicalDevice`＋`VkDevice` | 要自己挑裝置、開功能 |
| `MTLCommandQueue`、`commit()` | `MTL4CommandQueue`（一次交一組） | `VkQueue`＋`vkQueueSubmit` | — |
| 每幀一個 `MTLCommandBuffer` | `MTL4CommandAllocator` 每幀 `reset()`＋可重用的 `MTL4CommandBuffer` | `VkCommandPool` 每幀 reset＋`VkCommandBuffer` | Vulkan 與 Metal 4 都不替你保留資源；我們的三份輪替（`Map3DFrameBuffers`）剛好就是這個做法 |
| `MTLRenderPassDescriptor`＋encoder | `MTL4RenderCommandEncoder` | dynamic rendering（1.3 內建，1.1 用擴充）或 `VkRenderPass`／`VkFramebuffer` | load／store 對 loadOp／storeOp |
| `setVertexBuffer`、`setFragmentTexture`（49 處） | `MTL4ArgumentTable` | descriptor set＋push constant | Vulkan 要先宣告 layout |
| `MTLRenderPipelineState`＋`MTLDepthStencilState`（16 條） | `MTL4Compiler`、可特化的 pipeline | `VkPipeline`（深度、混色、光柵化都包在裡面）＋`VkPipelineCache` | Vulkan 的 pipeline 包得更多，16 條可能變成二十幾條 |
| `MTLLibrary`（`.metallib`） | 同 | `VkShaderModule`（SPIR-V） | §4.3 |
| 自動追蹤資源的使用 | 全部不追蹤，自己下 barrier | `vkCmdPipelineBarrier`＋image layout | Vulkan 最大的新負擔；我們只有陰影圖與 mipmap 兩處要轉換 |
| `makeBuffer`、`makeTexture` | placement heap、residency set | `VkDeviceMemory`，通常用 VMA（MIT，https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/blob/master/LICENSE.txt ；加相依要作者同意，也可以自己寫簡單的配置） | Vulkan 沒有 residency 的概念 |
| `MTKView`、`currentDrawable` | `waitForDrawable`／`signalDrawable` [Tri] | `VkSurfaceKHR`（`ANativeWindow`）＋`VkSwapchainKHR` | 要自己處理旋轉與 swapchain 重建 |
| 陰影圖＋比較取樣 | 同 | 深度 `VkImage`＋`compareEnable` 的 sampler | 裁切空間的 Y 相反；深度範圍一樣是 0–1 |
| MSAA 4× | 同 | 多重取樣的 attachment＋resolve | 手機 GPU 上 MSAA 便宜〔推測〕 |

結論〔推測〕：**現在的 Metal 寫法對翻到 Vulkan 1.1 就夠，不需要先把 iOS 換成 Metal 4**。Metal 4 讓 Metal「長得更像 Vulkan」，方便的是從 Vulkan 搬到 Apple 的人；我們是反方向。

### 4.2 Android 的 Vulkan 底線〔官方〕

- Google：Vulkan 是 Android 上首選的低階繪圖介面；之後 GLES 只經 ANGLE 提供（https://developer.android.com/games/develop/vulkan/overview ）。
- 版本規定（https://source.android.com/docs/core/graphics/implement-vulkan ）：Android 10 以前出廠的 64 位元機要 1.1；Android 13 起出廠的要 1.3；Android 16 起出廠的要 1.4；Android 14 起所有有 Vulkan 的機器都要 1.1 與 Android Baseline 2021。
- Android Vulkan Profiles 的涵蓋率（2025 年 10 月）：2021 版 95.5%、2022 版 86.5%、2025 版 80.1%（https://developer.android.com/ndk/guides/graphics/android-vulkan-profile ）。
- 幀節奏：Swappy（AGDK Frame Pacing）支援 Vulkan（https://developer.android.com/games/sdk/frame-pacing ）；它的授權這次〔未查到〕。
- 和 11-05 研究一致：下限 Vulkan 1.1。這次補一句〔推測〕：有 1.3 時用內建的 dynamic rendering，沒有時用擴充或傳統 render pass。

### 4.3 着色器怎麼互轉

**沒有還在維護的工具能把 MSL 當輸入**；查到的都是輸出 MSL 或讀別的語言。naga 的 README 把 Metal 只列在輸出（https://github.com/gfx-rs/wgpu/blob/trunk/naga/README.md ）〔官方〕。

| 工具 | 進 → 出 | 授權 | 能不能用 |
| --- | --- | --- | --- |
| glslang／`glslc`（NDK 自帶 shaderc） | GLSL → SPIR-V | BSD-3 等寬鬆授權（https://github.com/KhronosGroup/glslang/blob/main/LICENSE.txt ；前處理器另有授權，沒全讀） | 可以；建置工具，不進 App。11-05 研究已用它編過天空着色器 |
| SPIRV-Cross | SPIR-V → MSL／GLSL／HLSL | Apache-2.0（https://github.com/KhronosGroup/SPIRV-Cross/blob/main/LICENSE ） | 可以，但方向是「別的語言 → MSL」 |
| Slang | Slang／HLSL → SPIR-V、MSL、WGSL 等 | Apache-2.0 WITH LLVM-exception（https://github.com/shader-slang/slang/blob/master/LICENSE ） | 授權可以；是新的建置相依，要作者同意 |
| DXC | HLSL → SPIR-V | NCSA（https://github.com/microsoft/DirectXShaderCompiler/blob/main/LICENSE.TXT ） | 授權可以；我們沒有 HLSL |
| naga | SPIR-V、WGSL、GLSL → SPIR-V、WGSL、MSL、HLSL、GLSL | MIT 或 Apache-2.0（https://github.com/gfx-rs/wgpu/blob/trunk/LICENSE.MIT ） | 授權可以；要 Rust 工具鏈 |
| SDL_shadercross | HLSL／SPIR-V → SPIR-V／MSL／DXIL | zlib（https://github.com/libsdl-org/SDL_shadercross/blob/main/LICENSE.txt ） | 授權可以；同上是新相依 |
| Tint（Dawn 裡） | 以 WGSL 為中心 | BSD-3（https://github.com/google/dawn/blob/main/LICENSE ）；完整的輸入輸出表〔未查到〕 | — |

兩條路〔推測〕：

1. **手翻一份 GLSL，MSL 留著**（11-05 研究的做法）。1,070 行 MSL 對一份差不多長的 GLSL。不加相依。代價是之後每改一次着色器要改兩處；用 Linux CI 的 `glslc`＋`spirv-val` 擋編譯錯，畫面對不對要靠兩邊各自截圖。
2. **改成單一來源**（例如 Slang），兩邊都由它產生。之後只改一處；代價是新的建置工具、iOS 的建置也要改、產生的 MSL 要重新驗一次畫面。

建議先走 1：不用作者決定相依，iOS 也完全不動。等兩份真的開始分歧、維護有感，再回頭評估 2。

### 4.4 現成的轉譯層與跨平台底層（這次重查授權）

和 11-05 研究 §2.3 的結論相同：自寫 Vulkan，退路 wgpu-native。這次多查到的寫在「備註」。全部是寬鬆授權，**授權上都能用；但每一個都是新相依，要作者同意**。

| 專案 | 授權（授權檔） | Metal＋Vulkan | 備註 |
| --- | --- | --- | --- |
| MoltenVK | Apache-2.0（https://github.com/KhronosGroup/MoltenVK/blob/main/LICENSE ） | 把 Vulkan 架在 Metal 上 | **方向相反**：它讓 Vulkan 程式跑在 Apple 上。只有把 iOS 也改寫成 Vulkan 才用得到，不建議 |
| wgpu／wgpu-native | MIT 或 Apache-2.0（https://github.com/gfx-rs/wgpu-native/blob/trunk/LICENSE.MIT ） | 兩邊都有 | C 標頭可從 Swift 呼叫〔推測，沒編過〕；要 Rust 工具鏈 |
| Dawn | BSD-3（https://github.com/google/dawn/blob/main/LICENSE ） | 兩邊都有 | 文件仍把 Android 的 Vulkan 寫成進行中（https://github.com/google/dawn/blob/main/docs/support.md ）；Kotlin 包裝 androidx.webgpu 是 1.0.0-alpha06（https://developer.android.com/jetpack/androidx/releases/webgpu ） |
| SDL3 GPU | zlib（https://github.com/libsdl-org/SDL/blob/main/LICENSE.txt ） | 兩邊都有 | 11-05 研究沒列。C 介面，最容易從 Swift 接〔推測〕；Android 上「部分裝置」支援 Vulkan（https://wiki.libsdl.org/SDL3/CategoryGPU ） |
| sokol_gfx | zlib（https://github.com/floooh/sokol/blob/master/LICENSE ） | 都列了；Vulkan 後端成熟度〔未查到〕 | 很小的 C 標頭 |
| bgfx | BSD-2（https://github.com/bkaradzic/bgfx/blob/master/LICENSE ） | 兩邊都有 | 自己的着色器寫法 |
| Filament | Apache-2.0（https://github.com/google/filament/blob/main/LICENSE ） | 兩邊都有 | 整套引擎，會取代我們自己的繪圖 |
| The Forge | Apache-2.0（https://github.com/ConfettiFX/The-Forge/blob/master/LICENSE ） | 兩邊都有 | 很大的 C/C++ 框架 |
| Diligent Engine | Apache-2.0（https://github.com/DiligentGraphics/DiligentEngine/blob/master/License.txt ） | Vulkan 有；**Metal 後端要商業授權** | 11-05 研究寫「Apache-2.0、不建議」，這次補：它開源的部分在 iOS 只能經 MoltenVK |
| ANGLE | BSD-3（https://github.com/google/angle/blob/main/LICENSE ） | GLES 架在 Vulkan／Metal 上 | 要改寫成 GLES，不建議 |
| Godot RenderingDevice | MIT（https://github.com/godotengine/godot/blob/master/LICENSE.txt ） | — | 不是獨立函式庫，等於換引擎 |

**升頻與補幀在 Android 的對應**：

| 對應 | 授權 | 能不能用 |
| --- | --- | --- |
| Arm ASR（時間升頻，源自 FSR 2.2.2） | MIT（https://github.com/arm/accuracy-super-resolution/blob/main/LICENSES/MIT.txt ） | 可以（保留聲明；加相依要作者同意） |
| Snapdragon GSR 1（空間）、2（時間） | BSD-3（https://github.com/SnapdragonStudios/snapdragon-gsr/blob/main/LICENSE ） | 可以；GSR 1 是一個着色器，最接近 U1 |
| AMD FSR 1、FSR 2（舊的獨立 repo） | MIT（https://github.com/GPUOpen-Effects/FidelityFX-FSR/blob/master/license.txt 、https://github.com/GPUOpen-Effects/FidelityFX-FSR2/blob/master/LICENSE.txt ） | 可以 |
| AMD FidelityFX SDK 現行版（FSR 3.1／4） | **不是 MIT**：只准以二進位形式散布（https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/main/docs/license.md ） | 不用 |
| Qualcomm Adreno Frame Motion Engine（補幀） | 沒找到公開授權；只在 Qualcomm 的文章提到（https://www.qualcomm.com/developer/blog/2026/05/snapdragon-game-studios-developer-forum-gdc-2026-recap ，次要來源） | 當成專有、只限 Adreno，不用 |

所以 U1（空間升頻）兩邊都有可用的做法，U2（時間升頻）也有；**F（補幀）在 Android 沒有可用的公開對應**。

### 4.5 Android 版真正要重做的幾層

行數是 `main` `b72f1b3f` 的 `wc -l`（比 11-05 研究多，是這六天長的）：

| 層 | 行數 | Android 上 |
| --- | --: | --- |
| GameCore | 50,482 | **照用**。11-05 研究實測：Android 14 的系統函式庫上 Golden 24/24、存檔 38/38、重播全過（qemu，不是實機） |
| GamePresentation（含 `Map3D*` 66,504） | 167,489 | **照用**。3D 的場景、網格、車型、預算都在這裡。已知一處：EMU3000 的 18 個模型因 Android 的 `atan2f`／`asinf` 最後一位不同，雜湊鎖要處理（11-05 研究 §4.2） |
| 繪圖最底層 | `Map3DMetalView.swift` 1,960＋`FrameTimeRecorder.swift` 269＋`Map3DShaders.metal` 1,070＝3,299 | **重做**：Vulkan 後端＋GLSL。照 §4.1 逐段對翻〔推測：Vulkan 版會比 Metal 版長，因為 swapchain、descriptor、記憶體都要自己寫〕 |
| 畫面（SwiftUI 的 App） | 約 48,000（`RailwayGameApp/`，不含 UI 測試） | **重做**：Compose。這是最大的一塊（11-05 研究 §3） |
| 2D 地圖（SwiftUI `Canvas`） | 包在上一列裡，約一萬行 | **重做**，11-05 研究 §5 建議和 3D 共用同一個底層 |
| UI 測試 | 另計 | 重寫成 Compose 的測試 |

Swift 在 Android 的現況〔官方〕：Swift 6.3（2026-03-24）起有正式的 Android SDK（https://swift.org/blog/swift-6.3-released/ ）；入門文件現在寫 6.4.2、NDK r30，工具鏈與 SDK 的版本要完全相同（https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html ）。我們固定用 6.4.0，要配同版的 SDK（11-05 研究用的就是 6.4.0）。和 Kotlin 互通用 swift-java（Apache-2.0，https://github.com/swiftlang/swift-java ）。官方範例的純 Swift NativeActivity 用的是 OpenGL ES，不是 Vulkan（https://github.com/swiftlang/swift-android-examples ），所以 Vulkan 那段沒有官方範例可抄。

### 4.6 參考庫與 Web 版幫得上什麼

查了 `a91453/railway-reference-private`（`d8943125`，只列檔名與讀索引檔）：在全部檔名裡找 `three`、`tsl`、`webgpu`、`wgsl`、`glsl`、`shader`、`.frag`、`.vert`。

| 參考檔 | 是什麼 | 對 Android 的用處 |
| --- | --- | --- |
| `Railway/tw3d-reference-clean/source/js/tsl-materials.js`（2,959 行）、`Railway/slop-taipei-reference-clean/source/*/js/tsl-materials.js` | three.js 的 WebGPU／TSL 材質（外牆、標線、夜窗等），MIT | **不能直接變成 Vulkan 的着色器**。它是 JavaScript 組出來的節點，由 three.js 在執行時產生 WGSL 或 GLSL。能參考的是「外觀怎麼算」，而這些外觀搬進遊戲時本來就要寫成 MSL（那個包的 README 也這樣寫），再照 §4.3 手翻 GLSL |
| `Railway/geo-scene-reference-clean/source/src/three/shaders/glow.frag`、`trail.frag`、`trail.vert` | 手寫的 GLSL（光暈、軌跡） | GLSL 可以直接給 `glslc`。只有這三個小檔，遊戲的光暈已有自己的版本 |
| `Railway/tw3d-reference-clean/source/vendor/three/build/three.webgpu.js` 等 | three.js 本體 | 只有走 WebView 才用得到 |
| 本 repo 的 `Web/CityView`（three `^0.186.1`、vite，MIT） | 網站版的城市檢視 | 同上 |
| `Railway/taiwan-rail-reference-clean/source/app/android/` | Capacitor 的 Android 殼（11-05 研究 §7.1 已列） | 只有殼，沒有 3D |

走 WebView 的可行性：Chrome 121 起在 Android 12 以上的 Qualcomm 與 ARM GPU 開 WebGPU（https://developer.chrome.com/docs/web-platform/webgpu/overview ）〔官方〕；Chrome 146 加了架在 OpenGL ES 3.1 上的相容模式（https://developer.chrome.com/blog/new-in-webgpu-146 ）〔官方〕；Android WebView 從哪一版有核心的 WebGPU〔未查到〕。three.js 的 WebGPURenderer 會退回 WebGL 2，是從搜尋摘要看到的（次要來源，官方手冊頁這次讀不到）。

結論和 11-05 研究 §2.4 一樣：**Web 版可以當展示或備案，不當 Android 的主路**。遊戲規則是 Swift，要先編成 Wasm；3D 的 66,504 行配方要用 JavaScript 重寫；效能與觸控都輸原生。參考庫沒有任何 Vulkan 或原生 Android 的繪圖程式（nothing usable，Vulkan 後端會是這個專案自己寫的）。

## 5. 打分與建議

尺：NEXT_PRIORITIES §19（玩家 30%、開發 25%、美術 15%、鐵道迷 15%、音樂 15%），每欄 1–5。這是建議，**沒有改 NEXT_PRIORITIES**，由規劃決定。

| 代號 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 建議 |
| --- | --- | --: | --: | --: | --: | --: | --: | --- |
| M | 實機量 GPU／CPU（不改程式） | 3 | 5 | 1 | 1 | 1 | 2.60 | **做**，交給 Mac 本機（它量 LIQUIDGLASS 的 3D 幀數時順手） |
| F | 補幀 | 4 | 2 | 3 | 1 | 1 | 2.45 | **先不做**（和 §26 第 5 名同一項、同分） |
| U1 | 空間升頻（少畫像素時放大得清楚一點） | 3 | 3 | 3 | 1 | 1 | 2.40 | **M 顯示 GPU 是瓶頸才做**；U1 比 F 先 |
| V | Android 準備：繪圖後端抽介面、着色器手翻 GLSL 並在 Linux CI 編 | 3 | 4 | 1 | 1 | 1 | 2.35 | 照 11-05 研究 §8 的 spike 順序，等作者決定開始 Android 才做 |
| U2 | 時間升頻取代 MSAA | 3 | 2 | 3 | 1 | 1 | 2.15 | 先不做 |
| C | 着色器預先編譯 | 2 | 3 | 1 | 1 | 1 | 1.80 | 先不做；M 時順便量一次開 3D 編 pipeline 的時間，超過約 100 毫秒再說 |
| R | 光線追蹤 | 2 | 1 | 3 | 1 | 1 | 1.60 | 不做 |
| N | 機器學習進繪圖 | 1 | 1 | 2 | 1 | 1 | 1.15 | 不做 |
| Q | 整個換成 Metal 4 的指令與資源模型 | 1 | 1 | 1 | 1 | 1 | 1.00 | 不做（同決策 676） |

和現有項目比：

- §25：第 1 名鐵道博物館 3.70、第 2 名購車損益 3.20、第 6 名建材外賣 2.85。這裡最高的 M 是 2.60，**全部排在 §25 第 6 名之後**。
- §26：第 1 名 App 圖示 2.95、第 2 名 2.60。M 與 §26 第 2 名同分；F 就是 §26 第 5 名（2.45），分數不變；U1 的 2.40 緊接在後。
- §24：排法是半成品、玩家回報、bug 先做，§24.6 的 3D 項目（MAP3D-MEM、FACADE-REAL、NIGHT-GLOW）都是補現有缺口，**都比這裡的項目先**。其中 NIGHT-GLOW 之後若要做低解析度 bloom，會加第一張 render target；U1 也要一張，兩件事可以共用同一次改動。
- 結論：**不用改 §24、§25、§26 的順序**。唯一建議現在就動的是 M，因為它不花雲端 session、不改程式。

「F 和 U1 誰先」：照分數 F 高 0.05，但建議 U1 先，理由有三：U1 改動小一個量級；U1 在 Android 有可商用的對應，不違反 §1.1 的規則；F 要的 motion vector 是另一筆大工程，值得等 M 的數字。

### 各項的五個角度

**M 實機量測（做）**
- 玩家：之後的效能工作會打到真的慢的地方。
- 鐵道迷：無。
- 開發：不改程式；HUD 與 3D 面板的 `gpu`／`main` 毫秒已經有，只差在 A13、A12 上記下來。
- 美術：無。
- 音樂：無。

**U1 空間升頻（看 M 的結果）**
- 玩家：舊手機少畫像素時，畫面不那麼糊。
- 鐵道迷：車號、站名看板要仍然讀得清楚，是驗收的重點。
- 開發：只動 `Map3DMetalView`，着色器不動；Android 用 GSR 1 或 FSR 1 對應。
- 美術：窗格與標線的細線會被銳化，可能比現在好也可能出現鋸齒，要實機看。
- 音樂：無。

**F 補幀（先不做）**
- 玩家：省電模式的 30 看起來像 60，是最有感的一項。
- 鐵道迷：補出來的那一幀，車號與看板字可能糊。
- 開發：要 motion vector、可讀的深度、自己排呈現時間；Android 沒有對應，會是 iOS 獨有。
- 美術：快速轉鏡頭時邊緣可能有殘影。
- 音樂：無。

**U2 時間升頻（先不做）**
- 玩家：A14 以上可能更省電或更清楚；A13、A12 沒有。
- 鐵道迷：架空線、軌道這些細線最容易閃。
- 開發：動到大半着色器，兩條反鋸齒的路並存。
- 美術：整體會比 MSAA 柔一點。
- 音樂：無。

**V Android 準備（等作者說開始）**
- 玩家：Android 的玩家才玩得到；對現在的 iPhone 玩家沒有變化。
- 鐵道迷：無（資料與車型都共用）。
- 開發：抽出的介面也讓 iOS 的繪圖好測；GLSL 在 Linux CI 就能編。
- 美術：兩邊的畫面要逐一比對。
- 音樂：無。

**C 着色器預先編譯（先不做）**
- 玩家：第一次開 3D 可能快一點點，沒量過。
- 鐵道迷：無。
- 開發：建置多一步、兩條載入的路；16 條 pipeline 不多。
- 美術：無。
- 音樂：無。

**R 光線追蹤、N 機器學習、Q 整個換 Metal 4（不做）**
- 玩家：R 的反射與陰影好看，但發熱與耗電換不回來；N、Q 玩家看不到。
- 鐵道迷：無。
- 開發：三項都要兩套並存（A13、A12 用不了 Metal 4），Q 還沒有任何 Apple 公布的數字支持。
- 美術：畫風是頂點上色的扁平風格，R 與 N 針對的是寫實材質。
- 音樂：無。

## 6. 沒驗證與之後可以查的

- 所有效能：GPU 與 CPU 各佔多少、U1 的畫質、F 的延遲與耗電、開 3D 時編 pipeline 的時間。**UNVERIFIED，需要 Mac／實機**。
- 光線追蹤各晶片的支援、去雜訊升頻文件頁的系統版本：〔未查到〕。
- Vulkan 規格原文、three.js 手冊、WebView 的 WebGPU 版本、Swappy 的授權、sokol 的 Vulkan 後端成熟度：〔未查到〕。
- 這份沒有留下做到一半的事；`docs/HANDOFF.md` 沒有改。規劃若採用 M，請把它寫進給 Mac 本機 session 的 #1579 留言。

## 7. 查了什麼、找到什麼（照 CLAUDE.md）

| 來源 | 找到 | 取用 |
| --- | --- | --- |
| 作者的參考庫 `a91453/railway-reference-private`（`d8943125`） | TSL 材質三份、手寫 GLSL 三個小檔、three.js 本體、Capacitor 殼（§4.6） | 沒有可搬的 Vulkan 或原生 Android 繪圖程式（nothing usable） |
| 本 repo 的 `docs/research/ANDROID_PORT_STUDY_2026-11.md`、決策 676、`MAP3D_STATE_CHECK_2026-11-05.md` | Android 的大方向與實測、「不用 Metal 4 重寫」的決定、3D 的現況 | 沿用，沒有改它們 |
| Apple 官方文件、WWDC25 四場、兩份 PDF | §2 | 只引用 |
| Google、Khronos、swift.org 與各開源專案的授權檔 | §4 | 只引用；沒有拿任何程式 |

存取日期都是 2026-11-11。
