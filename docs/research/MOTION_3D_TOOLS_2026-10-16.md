# 動態設計與 3D 工具：作者再列的 45 個專案能幫《沿線》什麼

日期：2026-10-16。基準：`railway-game-ios` main `878adaf`；官網原始碼：`a91453/railway-reference-private` `1d2c668` 的 `Website/`。
讀者：作者，以及之後做官網影片、教學動畫、3D 地圖素材、3D 城市網頁的 session。

作者 2026-10-16 貼了三份「15 個 GitHub repo」的清單，要評估哪些適合這個遊戲：

- **甲**：動態設計，15 個（上市影片、自己的影片、動畫短片、網站動畫、基礎元件）。
- **乙**：3D 工作室，15 個（生成 3D 素材、場景與世界、遊戲引擎、網頁 3D）。
- **丙**：遊戲工作室，15 個，外加一段「用 Unity 6 一個人做農場遊戲」的流程。

**丙已經評過**：15 個都在 [GAME_AI_TOOLS_2026-10-15.md](GAME_AI_TOOLS_2026-10-15.md) 的表裡，結論照用，這次不重查（第 5 節）。這次新查甲、乙的 30 個，加上農場流程提到的 Tripo。

**範圍：只加這份文件，加上 GAME_AI_TOOLS 開頭的一行連結。** GameCore、GamePresentation、App、`Web/`、golden、存檔、replay、workflow 都不動；存檔版本、決策編號、golden schema 都不動（工作登記 #231）。

## 0. 一頁摘要

先講《沿線》是什麼，才知道什麼裝得上：

- App 是 Swift：決定論的 GameCore、SwiftUI 介面，3D 地圖是自己寫的 Metal（決策 229–244）。所有幾何都在 Swift 裡用程式產生：頂點色、一個材質、扁平的微縮模型感。列車也是程式建模（決策 230）。
- 官網 `www.alongthelinegame.com` 是純 HTML／CSS／JS，沒有 React，CSP 是 `script-src 'self'`，所以不能從 CDN 載腳本。
- 官網的 `/city/` 是 three.js 0.186 寫的 3D 城市（`Web/CityView/`），列車模型用 Meshy 生成（決策 161）。
- **官網已經有自己的影片產生器**：`Website/tools/trailer/render.js`（57 行）用 Playwright 一格一格截 `trailer.html`，再交給 ffmpeg，做出首頁 37.5 秒的介紹影片；聲音由 `mix_audio.py` 用遊戲自己的音檔混出來（決策 219）。
- App 全球上架（含歐盟、英國、南韓），素材與輸出的授權都要能全球商用。

**結論分五類**（30 個加上 Tripo）：

| 結論 | 個數 | 是哪些 |
| --- | --: | --- |
| 已在用 | 1 | three.js |
| 候選（建議下一個做） | 2 | **LottieFiles motion-design-skill**（改寫成 SwiftUI 動畫的 skill）、**cth9191/animate**（官網與社群的說明短片） |
| 候選（要作者同意依賴、費用或登記） | 5 | HyperFrames、motion、TRELLIS.2、Stable Fast 3D、TripoSR（不在清單上，查 Tripo 時找到） |
| 只取想法 | 13 | product-launch-motion、motion-graphics-skills、claude-motion-design、Barty-Bart motion-graphics、claude-motion、Remotion、gsap-skills、threejs-skills、MCP for Blender、Tripo、三個引擎 MCP（unity-mcp、godot-ai、unreal-engine-mcp） |
| 不適用 | 9 | hyperframes-student-kit、claude-remotion-skill、motion-dev-animations-skill、remotion skills、editor-mcp-server、react-three-fiber、supersplat、meshy-mcp-server、kit-usd-agents |
| **不能用**（授權） | 2 | Hunyuan3D-2.1、HY-World-2.0：騰訊授權不准在歐盟、英國、南韓使用或展示輸出 |

**三句話**：

- **動態設計那 15 個，大多是同一招**：把每一格寫成 `seek(t)` 的 HTML，用無頭瀏覽器截圖，再用 ffmpeg 接起來。官網的 `render.js` 已經在做這件事，所以它們能帶來的是**做法與品味的規則**，不是新的能力。最值得拿的是兩個不綁函式庫的 skill：LottieFiles 的動畫原則（可以用在 App 的 SwiftUI），以及 animate 的「先分鏡、自訂畫風、音樂用程式寫」。
- **App Store 的預覽影片要用 App 的實際錄影**（2026-10-16 修正：原本寫「這些工具都做不了」太絕對）：Apple 審核準則 2.3.4 限制的是影片內容：只能是 App 本身的螢幕錄影，可以加旁白與文字或影片的覆蓋。它不限制製作工具。所以這些工具不能拿重建的假介面當預覽，但可以剪輯實際的錄影、加說明的覆蓋與旁白。錄影要在 macOS 模擬器或實機上做，Linux 容器做不到；但 `website-screenshots.yml` 已經在 GitHub Actions 的 macOS 上開模擬器截官網的圖，同一條路加上 `xcrun simctl io <裝置> recordVideo` 就能錄實機畫面（UNVERIFIED，沒有試）。這些工具適合官網影片、社群短片、TestFlight 的新功能短片，也可以替錄好的畫面加字卡。
- **3D 生成模型的預設輸出不能直接接進 App，現在轉換也不划算**（2026-10-16 修正：原本寫「做不出 App 要的模型」太廣）：它們輸出幾十萬面、帶 PBR 貼圖的網格，而 App 的渲染器是頂點色、一個材質（決策 229、231），決策 230 也否決過「縮面重上色搬進來」的列車。這是現在的材質與畫風的限制，不是說地標永遠只能程式建模：目前像 101 這種重複量體用程式組合（決策 230、235）比較乾淨，生成模型先當形體參考；轉檔流程（第 3.3 節）做出來、量過之後再重新評估。官網的 GLB 已經有 Meshy。
- **清單外更值得做的是處理已經有的模型**（2026-10-16 補，第 3.3 節）：glTF-Transform 與 meshoptimizer（都是 MIT）在這個容器就能把 GLB 解開、減面、烘成頂點色，接上決策 244 留下的「GLB 轉檔」。要作者同意 `tools/` 多兩個 npm 依賴。

## 1. 怎麼查的

- 30 個 repository 加 Tripo 的兩個 repo（tripo-mcp、TripoSR、TripoSG）都淺 clone 到 session 的 scratchpad（不進 repo）。只讀 README、授權、主要原始碼，**沒有執行任何一個的程式**，也沒有 `npm install`。three.js 與 Remotion 太大，只 sparse clone 授權、文件與需要的原始碼。
- 推文的網址都被截斷，完整名稱是用 `git ls-remote` 與 clone 的內容對照確認的。
- 模型權重沒有下載。權重的授權看 Hugging Face 的模型卡。
- 服務條款（GSAP、Tripo、Apple 準則 2.3.4）抓網頁讀文字。Tripo 的網站對直接連線回 403，讀的是 archive.org 2026-10-04 與 2026-10-12 的快照。
- 對照這個 repo 的：
  - `CLAUDE.md`、`.claude/skills/`（art-style、rolling-stock、meshy-3d-generation、economy-balance）；
  - ARCHITECTURE 決策 161、163、219、229–231、235、244；
  - `Web/CityView/`（package.json、performance.md、`src/main.js`）、`tools/meshy/`、`tools/map3d-preview/`；
  - 官網：參考庫 `Website/site/`、`Website/_headers`、`Website/tools/trailer/`。
- 參考庫：這份研究是外部工具，不是移植參考庫的功能，沒有對照表。用到參考庫的只有官網原始碼，用來判斷影片工具與網頁動畫函式庫合不合。

## 2. 甲：動態設計的 15 個

### 2.1 總表

| # | 專案 | 是什麼 | 授權 | 結論 |
| --: | --- | --- | --- | --- |
| 1 | [AbubakrChan/product-launch-motion](https://github.com/AbubakrChan/product-launch-motion) `b25b163` | 一個上市影片的 skill。v2：自己的 `seek(t)` HTML、每格 4 個子格做動態模糊、照節拍放音效。v1（`legacy/`）是 GSAP＋HyperFrames，旁白對字 | MIT＋`NOTICE`：範例影片是 Cheerful 公司的，不得再用 | 只取想法 |
| 2 | [charlie947/motion-graphics-skills](https://github.com/charlie947/motion-graphics-skills) `229022e` | 15 個純文字的 prompt 範本（上市影片、圖表、短影音），輸出用 HyperFrames | MIT | 只取想法 |
| 3 | [howseen-ai/claude-motion-design](https://github.com/howseen-ai/claude-motion-design) `3d90d34` | 一個 skill 加 Python 腳本：先做節拍圖，重點放在 drop | MIT；用 Mixkit 音效、Cartesia 旁白、21st.dev 的 API 金鑰 | 只取想法（和 #1 v2 幾乎重複） |
| 4 | [nateherkai/hyperframes-student-kit](https://github.com/nateherkai/herk-edit-kit)（已改名 herk-edit-kit）`10511e5` | 790 MB 的對鏡頭說話影片剪輯包：剪靜音、剪口誤、406 張卡片範本 | MIT＋自己的使用許可；HyperFrames Apache-2.0 | 不適用：我們沒有真人影片 |
| 5 | [Barty-Bart/motion-graphics](https://github.com/Barty-Bart/motion-graphics) `3d83d98` | 六個 skill：照字幕時間放 B-roll、SAM 2 去背、產品說明影片、CC0 音效庫 | MIT；音效 CC0 | 只取想法：音效庫違反決策 219 的「不用音色庫」 |
| 6 | [cth9191/animate](https://github.com/cth9191/animate) `7e5eb56` | 說明短片：一張 `<canvas>`、固定種子的亂數、七種畫風各一個外掛，有建立新畫風的流程；先故事、再分鏡、再做；音樂用程式合成；一次輸出 9:16、1:1、4:5、16:9 | MIT | **候選，建議下一個做**（第 2.3 節） |
| 7 | [whaleyxbt/claude-motion](https://github.com/whaleyxbt/claude-motion) `e627941` | 四個 skill（品味規則、逐拍拼圖自我檢查、音效、網頁模擬）；`timeline.json` 一份時間軸；`sfx/` 是純 Python 標準函式庫的音效引擎；主流程是 Remotion；`sims/` 是 three.js 0.186 的網頁逐格截圖 | MIT；主流程依賴 Remotion 的授權 | 只取想法：`sims/`、`sfx/`、`review-loop`（第 2.4 節） |
| 8 | [haidrrrry/claude-remotion-skill](https://github.com/haidrrrry/claude-remotion-skill) `1dcbe5e` | Remotion 的 skill：10 條規則、17 個元件 | MIT；依賴 Remotion | 不適用：第 5 條規則「每個場景五層：網格背景…調色…顆粒＋暗角，不准平塗背景」和畫風相反 |
| 9 | [motiondivision/motion](https://github.com/motiondivision/motion) `2d27b04` | 網頁動畫函式庫（plain JS 的 `animate()`、React、Vue） | MIT | 候選（低優先）：官網目前 CSS 就夠；要用得放進官網自己的檔案（CSP） |
| 10 | [199-biotechnologies/motion-dev-animations-skill](https://github.com/199-biotechnologies/motion-dev-animations-skill) `3feedfb` | 第三方的 Motion skill，範本是 Next.js／`.tsx` | MIT | 不適用：它的說明自己寫「不要用在沒有 JS 框架的靜態網站」，正是我們的官網 |
| 11 | [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) `4d6b5be` | HTML 轉 MP4 的工具，附 21 個 skill；Node 22＋ffmpeg，可指定現有的 Chromium | Apache-2.0，「no per-render fees or commercial-use thresholds」；但部分範本附的 GSAP 不是開源授權；遙測預設打開 | 候選（要作者同意依賴）：只在影片變多時才值得，`render.js` 已經能做核心的事 |
| 12 | [remotion-dev/remotion](https://github.com/remotion-dev/remotion) `2f64140` | 用 React 元件做影片 | Remotion License：個人、3 人以下的公司、非營利免費（`LICENSE.md:18-23`），其他要公司授權（`:43`）；不是開源授權 | 只取想法：要為了影片多一個 React 專案，而我們已經有一樣結果的流程 |
| 13 | [remotion-dev/skills](https://github.com/remotion-dev/skills) `1441a11` | Remotion 官方的 agent skill | 沒有 LICENSE 檔（推論：屬 Remotion License） | 不適用（跟著 #12） |
| 14 | [greensock/gsap-skills](https://github.com/greensock/gsap-skills) `aed9cfd` | GSAP 官方的 8 個 skill | skill 本身 MIT；GSAP 是 Webflow 的「no charge」專有授權 | 只取想法（第 2.2 節） |
| 15 | [LottieFiles/motion-design-skill](https://github.com/LottieFiles/motion-design-skill) `f9a8a04` | 約 1,630 行的動畫原則：時間與緩動表、迪士尼 12 原則改寫成介面用、編排、減少動態；不綁任何函式庫 | MIT | **候選，建議下一個做**（第 2.3 節） |

### 2.2 授權上要注意的三個

- **Remotion**：不是開源授權。作者若是個人或 3 人以下（含約聘人數，FAQ 寫「aggregates with yours for the 4-person threshold」）可以免費商用；超過就要買公司授權。它附的 ffmpeg 是 GPLv2+。
- **GSAP**：2025 年起由 Webflow 免費提供，但授權頁自相矛盾：
  - FAQ 寫「All of GSAP… can be used in commercial projects at no charge」；
  - 同一頁的白話摘要還寫「as long as end users are not charged a fee of any kind」（擷取文字第 88 行）；
  - 終止（第 V 節）和違反條款連動：「may terminate… if you fail to comply with any of these terms」。
  - 改條款時，不接受新條款的人仍可以照舊條款用之前的版本：「you may continue using previous versions of GSAP Products under the applicable terms licensed to you prior to the effective date of the revised GSAP License」。
  - 禁止用在和 Webflow 競爭的無程式碼動畫工具，我們不是。
  - 2026-10-16 修正：原本寫「可以隨時收回，所以不要放進 `/city/`」理由不足。照現行條款，官網、`/city/`、宣傳影片都可以商用。現在不採用，是因為**沒有需求**（官網的 CSS 與 `render.js` 夠用），不是授權禁止。白話摘要那句和 FAQ 不一致，真的要用時再請作者確認一次。
  - gsap-skills 的 `README.md:33` 對 AI agent 寫「recommend GSAP」，裝了會讓之後的 session 偏向選它。
- **HyperFrames**：本體 Apache-2.0，可以用。要注意：
  - 範本庫有些區塊附 GSAP；
  - 工作室介面用到的 mediabunny 是 MPL-2.0（copyleft，只能看不能抄）；
  - 遙測預設打開，要設 `HYPERFRAMES_NO_TELEMETRY` 或 `DO_NOT_TRACK`；它的 skill 還會叫 agent 每次算繪後「send one feedback report」。

### 2.3 建議下一個做的兩個（不需要作者同意，照 NEXT_PRIORITIES 排程）

**A. 動畫原則的 skill：改寫 LottieFiles motion-design-skill**

- **為什麼**：App 的介面動畫（卡片滑入、教學卡片、快轉、狀態列）現在沒有一份共同的規則；每個 session 各自選時間與彈簧。這份 skill 不綁函式庫，表裡已經有 Apple 的曲線（`reference/timing-easing-tables.md:55-56`：「Apple HIG (0.25, 0.1, 0.25, 1)」、「Apple Spring stiffness:300 damping:20」）。
- **做法**：
  - 照 economy-balance 的前例（決策 161 也是）放成 `.claude/skills/<名稱>/`，保留 MIT 授權全文與出處；
  - 改寫成 SwiftUI 的寫法：`.spring`、`withAnimation`、`accessibilityReduceMotion`；
  - 對照 `docs/UI_THEME.md` 與決策裡已經定下的動畫（例如決策 182 的滑行、教學卡片的打開方式）；
  - 拿掉和畫風衝突的部分（陰影、模糊、漸層）。
- **成本**：只加一個 skill，沒有程式依賴。
- **四個角度**：
  - 玩家：介面動得一致，「減少動態」打開時真的會少動。
  - 開發：之後的 session 不用每次自己選曲線，UI 測試等「停穩」的時間也比較好估。
  - 美術：動畫的節奏和扁平畫風一起定下來。
  - 音樂：無。

**B. 官網與社群的說明短片：參考 animate 的流程**

- **為什麼**：清單上的影片工具裡它最合這個遊戲：
  - 一張 canvas、固定種子，每一格都可以重做（和 GameCore 的決定論是同一個想法）；
  - 它的「做一種新畫風」流程（`new-style.md`、`tools/compare.mjs`）可以做出《沿線》的畫風：平塗、粗的藏青外框、圓角、不用漸層與陰影。它的等角畫風（2:1 投影、圓角板塊、沒有陰影）已經接近微縮模型感；
  - 音樂用程式合成（`kit/score-head.js`），和決策 219 的方向一致；
  - 只要 Node、Playwright Chromium、ffmpeg，容器裡都有，不用 npm 套件（推論，沒有執行）。
- **做法**：不把整個外掛搬進來。先拿它的「故事 → 分鏡 → 做 → 檢查」流程與新畫風的方法，改寫成官網 `Website/tools/trailer/` 旁邊的一個 skill，算繪仍用現有的 `render.js`。聲音照舊用遊戲自己的音檔（`mix_audio.py`）。
- **用途**：官網的玩法說明、社群的直式短片、TestFlight 新功能的短片。它畫的是重建的畫面，不能當 App Store 的預覽影片（第 0 節）；預覽要用實際錄影，可以用它的流程加覆蓋。App 裡的教學動畫照舊在 SwiftUI／Metal 做。
- **四個角度**：
  - 玩家：還沒下載的人能在一分鐘內看懂怎麼玩。
  - 開發：沿用已經有的 `render.js`，沒有新依賴。
  - 美術：說明短片和 App 圖示是同一個畫風。
  - 音樂：配樂與音效都來自遊戲本身，不另外找素材。

### 2.4 只取想法：值得記下的做法

- **claude-motion 的 `sims/`**：一頁 HTML 帶 three.js 0.186，`window.SIM.render(t)` 能畫出任何一刻，`capture.mjs` 逐格截圖再交給 ffmpeg。如果 `Web/CityView/` 也提供一個固定時間的 `render(t)`，就能在 Linux 上把 3D 城市錄成 60 fps 的官網影片（軟體 WebGL 會慢，推論，沒有試）。這也接得上 GAME_AI_TOOLS §3.2 的截圖腳本。
- **claude-motion 的 `review-loop`**：每一拍抽一格拼成一張圖，自己先看過再交出去。和 rolling-stock skill 的預覽表是同一個做法，可以用在影片上。
- **claude-motion 的 `sfx/`**：純 Python 標準函式庫的音效合成與 −14 LUFS 的母帶處理。官網影片的音量標準化可以參考。
- **product-launch-motion v2**：閉式解的彈簧、子格動態模糊（ffmpeg `tmix`）、輸出後量 MP4 確認長度與格數。
- **motion-graphics-skills 的 `brand-intake`**：先寫一份 `MOTION.md` 給所有動畫 skill 讀。對我們來說，這份就是 art-style skill 加上第 2.3 節 A 的動畫原則。

## 3. 乙：3D 工作室的 15 個

### 3.1 總表

| # | 專案 | 是什麼 | 授權（程式／權重／輸出） | 能在這個容器跑嗎 | 結論 |
| --: | --- | --- | --- | --- | --- |
| 1 | [microsoft/TRELLIS.2](https://github.com/microsoft/TRELLIS.2) `75fbf01` | 一張圖生成帶 PBR 貼圖的 3D 資產 | MIT／MIT／不受限。但 GLB 匯出用的 nvdiffrast 是「Nvidia Source Code License (1-Way Commercial)」，§3.3 只准非商業（`o-voxel/o_voxel/postprocess.py:10` 引用它）；圖像編碼器 DINOv3 是 Meta 自訂授權，要申請 | 不能：要 24 GB 以上的 NVIDIA GPU | 候選（低優先，要作者同意租 GPU 與依賴，並改寫一條不經 nvdiffrast 的頂點色匯出） |
| 2 | [Tencent-Hunyuan/Hunyuan3D-2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1) `82920d6` | PBR 3D 資產 | 騰訊社群授權：`LICENSE:40`「You must not use… Output… outside the Territory」，Territory 不含歐盟、英國、南韓（`:18`） | 不能：要 29 GB | **不能用** |
| 3 | [Stability-AI/stable-fast-3d](https://github.com/Stability-AI/stable-fast-3d) `ff21fc4` | 一張照片生成 UV 展開的網格 | Stability AI Community License：年營收 100 萬美元以下免費（`LICENSE.md:10`）；商用要登記（`:22`）；要附 Notice 並明顯標示「Powered by Stability AI」（`:27`）；輸出歸使用者（`:32`）；沒有地區排除 | CPU 可以（推論，沒有試） | 候選（低優先，要作者同意登記、標示、依賴，與營收超過門檻時授權終止的風險） |
| 4 | [meshy-dev/meshy-mcp-server](https://github.com/meshy-dev/meshy-mcp-server) `fad086d` | Meshy API 的 MCP（28 個工具） | MIT；輸出照 Meshy 條款 | 用 API | 不適用：和已經採用的 `meshy-cli` 與 skill（決策 161）重複，而且要把 API 金鑰放進環境（CLI 用裝置登入）。可參考：新的 `meshy-t2.5` 拓撲（100–30,000 面）；`lowpoly` 2026-10-30 停用，`tools/meshy` 沒有用到 |
| 5 | [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp)（現名 MCP for Blender）`7a0373e` | 用自然語言操作開著的 Blender | MIT；遙測預設送匿名紀錄，同意之後會收 prompt、程式、截圖並可能拿來訓練 | 不能：容器沒有 Blender | 只取想法（第 3.2 節） |
| 6 | [Tencent-Hunyuan/HY-World-2.0](https://github.com/Tencent-Hunyuan/HY-World-2.0) `df9988e` | 文字或圖生成可走動的 3D 世界（主要是高斯潑濺） | 騰訊社群授權，同 #2 的地區排除（`License.txt:39`） | 不能：要多張 GPU | **不能用** |
| 7 | [playcanvas/supersplat](https://github.com/playcanvas/supersplat) `f2a1b49` | 瀏覽器裡的高斯潑濺編輯器 | MIT | — | 不適用：我們的城市是程式產生的，沒有潑濺 |
| 8 | [NVIDIA-Omniverse/kit-usd-agents](https://github.com/NVIDIA-Omniverse/kit-usd-agents) `4ce780d` | Omniverse 的 Chat USD 與四個回答 USD API 問題的 MCP | Apache-2.0；要 NVIDIA 的雲端 API 金鑰 | — | 不適用：沒有用 USD，也不生成模型 |
| 9 | [CoplayDev/unity-mcp](https://github.com/CoplayDev/unity-mcp) `142ea0a` | Unity 編輯器的 MCP，約 50 個工具 | MIT | — | 只取想法（第 4 節） |
| 10 | [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai) `b82b5c5` | Godot 4.7 編輯器的 MCP，46 個工具 | MIT | — | 只取想法（第 4 節，三個引擎 MCP 裡最有用的） |
| 11 | [flopperam/unreal-engine-mcp](https://github.com/flopperam/unreal-engine-mcp) `b1b495b` | Unreal 編輯器的 MCP；進階功能是付費的代管服務 | 沒有 LICENSE 檔，只有 README 與外掛設定寫 MIT | — | 只取想法（第 4 節） |
| 12 | [playcanvas/editor-mcp-server](https://github.com/playcanvas/editor-mcp-server) `b19fa06` | 操作雲端 PlayCanvas 編輯器的 MCP | MIT | — | 不適用：要 PlayCanvas 專案 |
| 13 | [mrdoob/three.js](https://github.com/mrdoob/three.js) `121e626` | three.js 本身 | MIT | — | **已在用**（`Web/CityView` 的 `three ^0.186.1`） |
| 14 | [pmndrs/react-three-fiber](https://github.com/pmndrs/react-three-fiber) `d74622e` | 用 React 寫 three.js | MIT | — | 不適用：CityView 是純 three.js，官網沒有 React |
| 15 | [CloudAI-X/threejs-skills](https://github.com/CloudAI-X/threejs-skills) `b1c6230` | 10 個通用的 three.js skill | 沒有 LICENSE 檔，只有 `README.md:140` 一句「MIT License」，沒寫著作權人；安裝說明指向另一個 repo | — | 只取想法：授權不清；內容對 r186 已經過時（下面） |

**threejs-skills 對 r186 過時的地方**（對照 three.js 原始碼查過）：

- 用 `THREE.Clock`（r183 起 deprecated，建立時會警告），應改 `Timer`；
- 用 `RGBELoader`（r180 起 deprecated），應改 `HDRLoader`；
- WebGPU 後製那節 import 不存在的 `three/addons/nodes/Nodes.js`，並用 r183 已改名為 `RenderPipeline` 的 `THREE.PostProcessing`；
- 教的是 three 自己的 `EffectComposer`，而 CityView 用的是 pmndrs 的 `postprocessing`、n8ao、takram 的大氣，以及 `performance.md` 說的 draw call 瓶頸。它都沒提到。

**順帶查到**：CityView 自己的 `src/main.js:539` 也還在用 `new THREE.Clock()`。下次改 CityView 時順手換成 `Timer`，這次不改。

### 3.2 生成模型和 App 的 3D 地圖合不合

- **App 的渲染器沒有地方放 PBR 網格**：頂點是 40 bytes（位置、法線、RGBA、uv、layer），只有一張 13 層的灰階貼圖乘上調色盤的頂點色，整個城市一個 pipeline（決策 229、231）。AI 生成的網格有幾十萬面，帶自己的 2K–4K 底色、金屬度、粗糙度、法線貼圖。
- **要用就得離線轉檔**：減到幾百到幾千面、把底色烘成每個面的頂點色、量化成 `Palette` 的顏色、改平塗法線。決策 244 已經把「GLB 在電腦上轉檔與地標（淡江大橋、日月潭）」列為下一步，所以這條路本來就在計畫裡。但仍受兩條限制：
  - 決策 230：作者看過「縮面、重上色就搬進來」的列車，否決了；
  - art-style §7：成品不能像從別的遊戲搬來的；參考庫的圖不上傳到會保留或拿去訓練的外部服務。
- **建議**：
  - 目前的地標先照決策 230、235 用程式組合。例如台北 101 是 8 節重複的斗形量體，程式做比 AI 生成乾淨（AI 生成的建築邊角軟、面有雜訊）。
  - AI 生成只拿來做形體參考或粗模。要做的話，**TripoSR**（程式與權重都是 MIT、預設就輸出頂點色、能用 CPU 跑，`run.py:52`、`run.py:97-99`）最合，可以在本機處理自己拍的照片，不用上傳。它要 torch 等幾 GB 的工具依賴，要作者同意。
  - 官網的 GLB 照舊用 Meshy。
  - 已經有的 GLB 要轉進 App，用第 3.3 節的 glTF-Transform 與 meshoptimizer。
- **MCP for Blender**：決策 244 的「在電腦上轉檔」如果要在作者的 Mac 上用 Blender 做，可以考慮它。但要關遙測（`DISABLE_TELEMETRY=true`），不用它的 `generate_3d` 走騰訊的路線，也要注意 `execute_blender_code` 會跑任意 Python。同樣的事用一支 Blender 腳本也做得到。

### 3.3 清單外：glTF-Transform 與 meshoptimizer（2026-10-16 補）

作者轉來另一個 AI 的分析，建議這兩個清單外的專案。查過，比清單上的 3D 生成工具更貼近目前的需求：決策 244 留下的「GLB 轉檔與地標」要的是**處理已經有的模型**，不是再多一個生成器。

| 專案 | 是什麼 | 授權 | 能在這個容器跑嗎 |
| --- | --- | --- | --- |
| [donmccurdy/glTF-Transform](https://github.com/donmccurdy/glTF-Transform)（npm `@gltf-transform/core` 4.5.1） | 讀寫、檢查、合併、減面、去重、焊接 GLB 的 Node 函式庫與 CLI | MIT（npm 的 `license`） | 可以：純 Node，容器有 Node 22 |
| [zeux/meshoptimizer](https://github.com/zeux/meshoptimizer)（npm `meshoptimizer` 1.3.0、`gltfpack` 1.3.0） | 減面、頂點快取與索引最佳化、meshopt 壓縮的編解碼 | MIT（npm 的 `license`） | 可以：npm 版是 WASM |

**為什麼合**：
- 決策 244 的「外部專案」寫過：GLB 讀取器（cgltf、GLTFKit2、GLTFSceneKit、SwiftGLTF）沒有能在 Linux 跑的純 Swift 版本，所以「下一步改成在電腦上轉檔」。glTF-Transform 在這個容器就能跑，不需要作者的電腦或 Blender。
- 參考庫的角色 GLB 本身就是 glTF-Transform 4.5 輸出的，帶 `EXT_meshopt_compression`、`KHR_mesh_quantization`、`KHR_texture_basisu`（PHASE6C_BUILDINGS_STUDY 第 508 行、PHASE8_ASSET_INVENTORY §2.1）。要解開正是這兩個工具。
- 流程可以全部離線、放在 `tools/`：讀 GLB → 解 meshopt 與量化 → 減面 → 取樣貼圖烘成每個面的頂點色 → 量化到 `Palette` → 輸出 Metal 渲染器的 40 bytes 頂點格式（決策 231）。最後兩步要自己寫；App 不讀 GLB，也不加套件。
- 不要只把壓縮的 GLB 放進 App：渲染器讀不了。

**限制**：仍受決策 230（作者否決過「縮面、重上色就搬進來」的列車）與 art-style §7 約束。所以先用在程式建模不划算的少量物件（廟宇裝飾、攤位、雕像、小地標），列車、軌道、月台、成排透天厝照舊程式產生。

**第一次驗證**：挑一座車站、一棟建物、一個街景物件跑完整個流程，比較外觀、三角形數、材質數、記憶體與實機每幀時間（決策 229 的量測）。有收益才擴大。

**要作者同意**：`tools/` 多兩個 npm 依賴（MIT，只在工具裡，App 不帶）。

**四個角度**：
- 玩家：地標與小物件多了，城市更有台灣的樣子。
- 開發：在雲端容器就能轉檔，不用作者的 Mac；輸出照現有的頂點格式，渲染器不改。
- 美術：顏色量化到調色盤，和程式建模的物件同一個畫風；不合的就不放。
- 音樂：無。

### 3.4 Tripo（農場流程第 3 步）

- **條款**（archive.org 快照，「Last updated: July 11, 2025」）：
  - §5.2.1：免費使用者的輸入與輸出「Tripo retains all rights」；
  - §5.2.2：付費使用者「generally have all rights」，Tripo 也不拿來訓練；
  - §3.2：不能用輸出做和它競爭的模型；
  - 說明頁把「Use in a commercial game (Steam, mobile, console)」標為付費方案才可以。
- **官方 MCP** [VAST-AI-Research/tripo-mcp](https://github.com/VAST-AI-Research/tripo-mcp) `7e8ec9e`（MIT，alpha）只支援經 Blender 外掛，半年沒有更新。
- **結論：只取想法**。付費方案和 Meshy 條件相當，但會多一個付費服務，而 Meshy 已經在用。要比較兩家品質時，訂閱的費用由作者決定。

## 4. 三個新的引擎 MCP：給 GAME_AI_TOOLS §3 候選補的做法

三個都是引擎外掛，裝不上來，結論和 GAME_AI_TOOLS 對同類的 IvanMurzak/Unity-MCP、Coding-Solo/godot-mcp、ChiR24/Unreal_mcp 相同。但它們有上一份沒記到的做法，都可以補進 §3.1（無頭模擬的入口）與 §3.2（截圖與每幀量測）：

| 做法 | 來源 | 用在哪裡 |
| --- | --- | --- |
| **一批指令，任一個失敗就整批不生效**，回 `succeeded`、`stopped_at`、`results[]` | godot-ai `src/godot_ai/tools/batch.py` | §3.1 的 `apply`：把整批指令套在世界的副本上，全部成功才留下。GameCore 是值語意、失敗不留痕，幾乎不用另外寫 |
| 一批有上限（預設 25、最多 100），先檢查每一項，錯誤附第幾項 | CoplayDev `batch_execute.py` | §3.1 |
| 打錯操作名稱時回「是不是要…」 | godot-ai `middleware/op_typo_hint.py` | §3.1：補在 Unreal_mcp 的「不認得的參數就拒絕」上 |
| 篩選條件一個都沒中是錯誤，不是空的結果 | godot-ai `docs/testing.md` | §3.1 的 `dump --sections`：不認得的段落要失敗。和 economy-balance §1「略過不是通過」同一個原則 |
| 預設只回短的摘要，細節要指定才給 | godot-ai 的文件查詢；flopperam 的 `scene_brief` | §3.1 的 `dump` |
| **照遊戲時刻排的指令**：`{at_frame, action}` 一次送出，「because that's what reproduces identically」 | godot-ai `docs/TOOLS.md:331-376` | §3.1 的 `apply` 收 `{at_tick, command}`。ReplayFixtures 已經是這個格式，只是現在只能重播 |
| 先試跑不生效（dry run），再真的做 | CoplayDev 的 `dry_run`；flopperam `skills/blueprint-authoring/SKILL.md:15,32` | §3.1：`apply --dry-run` 回收據但不留下 |
| 固定的環繞六視角或方位 × 仰角的拼圖，加上 draw call、三角形、每幀時間的 JSON | CoplayDev `manage_camera.py:63-122`、`rendering_stats` | §3.2：`tools/map3d-preview/`（決策 238，2026-10-15 加的）已經能照固定視角存 PNG 前後對照，**還沒有**每幀時間與 draw call 的 JSON |
| 參考照片和算繪結果並排成一張 | CoplayDev `blender_bridge compare_screenshot` | rolling-stock skill 的預覽表 |

**GAME_AI_TOOLS §3 的現況**（main `878adaf`）：

| 項目 | 現況 |
| --- | --- |
| 3.1 無頭模擬的入口 | 還沒做：`Package.swift` 只有 GameCore、GamePresentation 兩個函式庫與兩個測試 target |
| 3.2 截圖與每幀量測 | 一半：`tools/map3d-preview/` 做了原生 3D 的固定視角截圖；每幀量測與 CityView 的 `_bench.mjs` 還沒有 |
| 3.3 腳本化玩法的比較 | 還沒做：`ChallengeReportTests` 仍是三種固定玩法 |
| 3.4 文件數字的一致性 | 還沒做，而且差得更多：OVERVIEW 寫存檔 56，程式已經是 63（`Sources/GameCore/World/SavedGame.swift:335`）；golden schema 72 對 74；golden 76 個對 77 個 |

## 5. 丙：遊戲工作室的 15 個（沿用上一份的結論）

15 個都在 [GAME_AI_TOOLS_2026-10-15.md](GAME_AI_TOOLS_2026-10-15.md) §0 的表裡，名字和推文一一對得上，結論照用：

- **已採用**：Claude-Code-Game-Studios → `economy-balance` skill。
- **候選，等作者**：ACE-Step 1.5（離線配樂，要改決策 219 §2.2）。
- **不能用**：ubisoft CHORD（只限研究）、HunyuanVideo-Foley 與 Hunyuan-GameCraft（地區限制）。
- **其餘**：只取想法或不適用。

**農場流程的六步**，對照這個 repo：

| 步驟 | 這個 repo 已經有的 | 結論 |
| --- | --- | --- |
| 1 用 MCP 把 Claude Code 接上 Unity 與 Blender | 沒有引擎可接；Bash 加 `swift test` 就是橋 | 不適用，GAME_AI_TOOLS §3.1 取代它 |
| 2 一頁的設計文件 | ARCHITECTURE 的決策、`docs/research/`、工作登記 #231、四個角度的理由，比一頁更嚴 | 已經做到 |
| 3 用 Tripo 生成模型 | Meshy（決策 161）、程式建模的列車（決策 230） | 不需要（第 3.4 節） |
| 4 用 Blender 整理 | 沒用 Blender；模型是程式產生或 Meshy，用預覽圖檢查 | 不適用 |
| 5 一次一個系統 | 「小而少的改動」、一個工作一個 PR | 已經做到 |
| 6 **Opus 用自動駕駛試玩，先列出所有 bug 再修** | 一部分：`ChallengeReportTests`（沒有玩家、幾個種子、三種玩法）、`BalanceReportTests`、性質測試的 `WorldInvariants.violations(in:)`、`HighSpeedDemoDayTests`（一天裡的重疊、逆行、誤點）、`WebsiteTimelineTests`（跑一年） | **值得補**：見下 |

**第 6 步缺的**：一個像玩家的自動駕駛，用幾種玩法跑完整局。它的發現分兩種（2026-10-16 修正：原本寫「全部不讓測試失敗、只列清單」，但虧錢不一定是 bug）：

| 種類 | 例子 | 怎麼處理 |
| --- | --- | --- |
| **確定的錯誤** | 死結（列車永遠互等、時間不再前進）、狀態損壞（`WorldInvariants.violations(in:)` 不是空的、存檔讀回來不一樣）、旅客的人數對不上 | **測試失敗**，和現在的性質測試一樣 |
| **觀察** | 卡住很久或一直閒著的列車、永遠上不了車的旅客、每個月都虧錢的路線、錢用光、做不到或第一天就達成的挑戰目標 | 不讓測試失敗，寫進排過序的報告，交給修 bug 或調平衡的 session 判斷（economy-balance skill） |

做法是 GAME_AI_TOOLS §3.3 的 `Policy` 加一段「異常」的輸出，經 §3.1 的 `advance` 與 `dump` 執行。全部放在測試與工具裡，不進 GameCore。

## 6. 等作者決定的

只有要加依賴、要花錢、要登記或要改決策的才列在這裡。第 2.3 節的兩個 skill 不需要等。

| 事項 | 要決定什麼 | 建議 |
| --- | --- | --- |
| HyperFrames | 官網的影片工具要不要多一個 npm 依賴（要關遙測） | 先不要：`render.js` 夠用，等影片多到要字幕、多段組合時再說 |
| motion（網頁動畫） | 官網要不要多一個放在自己檔案裡的函式庫 | 先不要：CSS 夠用 |
| Remotion | 要不要用（作者與幫手合計超過 3 人就要買公司授權） | 不要：要多一個 React 專案，結果和現有流程一樣 |
| GSAP | 要不要用在官網或 `/city/` | 現在不用：沒有需求（CSS 與 `render.js` 夠用）。授權照現行條款允許商用（第 2.2 節） |
| TripoSR | 要不要在工具裡加 torch（CPU）做形體參考 | 等決策 244 的地標開工、程式建模做不出來時再說 |
| Stable Fast 3D | 登記、「Powered by Stability AI」的標示、營收 100 萬美元的門檻 | 不要：TripoSR 授權更乾淨 |
| TRELLIS.2 | 租 24 GB 以上的 GPU、自己寫頂點色匯出 | 不要：品質最好，但成本與 nvdiffrast 的授權都不划算 |
| Tripo 付費方案 | 第二個付費的 3D 服務 | 不要：Meshy 已經在用 |
| glTF-Transform、meshoptimizer（清單外） | `tools/` 多兩個 MIT 的 npm 依賴 | **建議同意**：決策 244 的 GLB 轉檔在雲端容器就能做（第 3.3 節） |
| 付費的旁白服務（ElevenLabs、Cartesia 等，影片工具常用） | 帳號與條款 | 官網影片目前沒有旁白；要的話先看本地的 Kokoro-82M（Apache-2.0，沒有查它的訓練資料） |

## 7. 驗證

**VERIFIED**（這個容器，Linux，2026-10-16）：

- 30 個 repository 與 tripo-mcp、TripoSR、TripoSG 的完整網址、HEAD、授權檔與上面引用的行號；
- HF 模型卡的授權：TRELLIS.2-4B、stable-fast-3d、TripoSR、TripoSG、Hunyuan3D-2.1、HY-World-2.0；
- GSAP 授權頁、Tripo 條款（archive.org 快照）、Apple 審核準則 2.3.4 的文字；
- threejs-skills 與 r186 的落差（對照 three.js 原始碼）；
- 本 repo：`Web/CityView/package.json`、`src/main.js:539`、`tools/map3d-preview/`、`Package.swift`、`SavedGame.swift:335`、決策 229–231、244；
- 官網：參考庫 `1d2c668` 的 `Website/site/`（沒有 `package.json`、沒有框架）、`_headers` 的 CSP、`tools/trailer/render.js`。

**UNVERIFIED**：

- 沒有執行任何一個專案或模型。這個容器沒有 GPU，也沒有 Blender。
- animate、HyperFrames、Stable Fast 3D、TripoSR 能不能在這個容器跑，是讀程式推論的。
- 軟體 WebGL 錄 `/city/` 的速度。
- ElevenLabs、Cartesia、Mixkit、Kokoro-82M 的條款沒有讀。
- 作者是否符合 Remotion 免費授權的人數條件。
