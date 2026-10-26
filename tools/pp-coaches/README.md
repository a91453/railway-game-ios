# PP 客車原生模型與 E500 牽引展示工具

先讀 [製作手冊](../../docs/art/native-vehicle-modeling/README.md)、[PP 製作交接](../../docs/art/pp-coaches-2026-10-26/README.md)。四種 PP 客車配方獨立；E500 使用已接受第三版，沒有重做。PP 專用 `pushPull` 顯示接點、E500 展示編組及真機狀態須分開記錄。

需求：Swift 6.4、Node、Playwright／Chromium、Python NumPy／Pillow、Blender。沿用專案既有工具，不新增 App 依賴。所有完整輸出放公開庫外，原始私有圖片／mesh／貼圖不送外部生成服務。

```sh
export PATH=/workspace/scratch/swift-6.4/usr/bin:$PATH
# 若 Node 套件位於 scratch，先設定 NODE_PATH。
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DPPPassengerTests|Map3DModelFileTests|Map3DModelTests|Map3DTrainSetTests'
# 真前版從固定 base 讀當時營運中的通用 PP 客車。
tools/pp-coaches/capture-baseline.sh BASELINE_WORKTREE BASELINE_OUTPUT
# PP_ACCEPTED_E500 指向已接受第三版包，含 models/e500[-far].m3dmodel。
# 匯出器比實際三角 payload，再原樣複製該檔，不替換其 producer。
PRODUCER_COMMIT=$(git rev-parse HEAD) PP_BASELINE=BASELINE_NATIVE PP_ACCEPTED_E500=ACCEPTED_E500 PP_BASELINE=BASELINE_OUTPUT/models/before-pp-ppt1000.m3dmodel tools/pp-coaches/export.sh OUT
node tools/pp-coaches/review.mjs OUT
```

此時親自開啟八個近遠景 `previews/pp-*-review.png`：側／正／俯／斜配色、白模及剪影。若有主要偏差，先修幾何再全量重出。`before-pp-ppt1000` 是固定 base 的真 `set-pushPull-car`，明確標示既有通用模型，不冒充本次專用配方的前版；`PP_BASELINE` 產生與新近遠景同相機／公尺對照。若製作中另有修訂，保留真 first pass，以 `PP_PREVIOUS=FIRST_PASS` 重匯，`render.mjs` 自動產同相機／公尺對照。

```sh
node tools/pp-coaches/verify.mjs OUT
python3 tools/pp-coaches/support-audit.py OUT
node tools/pp-coaches/render.mjs OUT
blender --background --python tools/pp-coaches/glb-audit.py -- OUT
python3 tools/pp-coaches/verify-png.py OUT
node tools/pp-coaches/standalone.mjs OUT
node tools/pp-coaches/browser-check.mjs OUT
```

再查看最終單元、七向、完整展示編組、共同相機真前後及 E500／EMU3000 同尺度風格比較。公開僅保留一張 `overview.png`；完整模型、GLB、圖片、viewer 及來源在私庫。使用者本次明確要求完整 ZIP，故本批保留經逐檔驗證的 ZIP。

所有輸出來源穩定提交後，以真正 producer 全量重匯、重渲及驗證，再執行：

```sh
python3 tools/pp-coaches/bundle.py OUT PRODUCER_COMMIT
node tools/pp-coaches/standalone.mjs OUT
node tools/pp-coaches/browser-check.mjs OUT --standalone
node tools/pp-coaches/browser-check.mjs OUT
python3 tools/pp-coaches/bundle.py OUT PRODUCER_COMMIT
```

最後核 ZIP member 仍等於 live bytes；瀏覽器檢查會更新 `verification.json`，因此若在打包後重跑，必須重包。ZIP hash 記在包外 `package-verification.json`，不遞迴放進自己。

原生公尺 +X前／+Y左／+Z上，輪底 Z=0；GLB=(x,z,-y)。每個原生單元仍遵守 M3DM 15,000 三角上限；完整編組使用包含合法單元的 `M3DAssembly` JSON，只供靜態展示／轉 GLB，不冒充遊戲可載入的超限單一檔。Swift 的完整三角 payload 與 JS 組裝逐 bytes 比較；單元順序、前機0°／尾機180°朝向、實際平移與共同軌面在 manifest `assembly`。E500 與第一客車只有連結器相接，不加入虛構旅客貫通道。

`verify.mjs` 驗輸出幾何與刪面／反面／錯位反例；`support-audit.py` 驗玻璃支承與向外可見性、輪底、輪組淨空及可見故障反例。抽樣支承／射線不是全碰撞或動畫證明。`capture`／`coexistence` 核對保護模型的實際 payload，而非只有 bounds。Blender 獨立讀 GLB；Pillow 完整解碼透明 PNG／留白；Chromium 實際載入、七向、旋轉、縮放、原生／GLB／PNG／ZIP下載比 SHA，另驗內嵌離線 viewer。

靜態外觀、Linux 技術驗證、營運接入、同提交 CI、真機 Metal／效能／輪轉／門／推拉控制與動畫各自記錄。E500＋PP 展示編組不等於已接入營運，靜態通過不等於推拉控制或動畫通過。
