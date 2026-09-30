# 最小 Swift / Wasm 探針（W0）

此 executable 直接依賴根目錄 `GameCore`，在原生、Node WASI 與瀏覽器 Web Worker 執行相同檢查。沒有重寫遊戲規則，不依賴 `GamePresentation`，沒有 Babylon.js，也沒有持續執行的遊戲指令 bridge。

## 固定工具

- Swift **6.4.0** compiler，配合 **6.4.0** 完整 Wasm SDK（非 Embedded Swift）。根目錄仍保留 Swift tools 6.0。
- SDK ID：`swift-6.4.0-RELEASE_wasm`；實際 target：`wasm32-unknown-wasip1`。
- Node.js 24 LTS；`@bjorn3/browser_wasi_shim` 0.4.2、Playwright 1.63.0，版本與 integrity 固定在 lockfile。
- Swift 安裝依照 [官方 Wasm 指南](https://www.swift.org/documentation/articles/wasm-getting-started.html)。compiler 與 SDK 必須同版本。

安裝 SDK（官方 checksum）：

```sh
swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
swift sdk list
```

## 建置與驗證

在 repository 根目錄執行：

```sh
cd Web/WasmProbe
npm ci --ignore-scripts
npx playwright install --with-deps chromium firefox webkit
npm run build
PROBE_BROWSERS=chromium,firefox,webkit npm test
```

若 compiler 不在 PATH，可用 `SWIFT=/absolute/path/to/swift npm run build`。使用已安裝的 Chromium，可用 `CHROMIUM_PATH=/absolute/path/to/chromium npm test`。`npm test` 預設只跑 Chromium；指定的任一瀏覽器無法啟動或檢查失敗都會讓命令失敗，不靜默略過。

`build.mjs` 以 warnings-as-errors 建置原生與 Wasm **release** executable。`prepare.mjs` 將現有 `Tests/GameCoreTests/GoldenScenario.swift`、`NetworkSupport.swift` 的 ID helpers 與排序後的全部 JSON fixtures 複製至忽略的 `Generated/`；JSON 以 Swift raw literal 嵌入 executable，瀏覽器不需要檔案系統，也不會先用 JS Number 解碼。生成檔不提交、不修改 fixture 預期。若 runner/helper 結構改變，探針的生成或編譯應明確失敗。

`verify.mjs` 驗證下列結果，任何不一致都返回非零 exit code：

1. 失敗指令不改變 GameWorld。
2. S4 豎曲線手算高度、列車沿坡道移動、tick 與唯讀 snapshot。
3. 超過 64 位元的完整寬度乘除、Int64 溢位偵測。
4. Codable 世界存讀與超過 JS 安全整數範圍的金額；傳到 JS 的金額維持十進位字串。
5. 時鐘溢位拒絕且保持狀態。
6. 全部 **17 個** golden scenarios 的逐步結果、拒絕原子性與最終狀態；另修改一個只存在記憶體的預期金額，證明 oracle 確實能報錯。
7. Wasm 載入返回 HTTP 503 時，Worker 與頁面必須顯示失敗。

Node 使用內建 `node:wasi`，瀏覽器使用獨立的 WASI shim，結果與原生 report 比對。不同 target 的 `intBits` / `intMax` 分別驗證後才排除於行為比較，不能忽略其他差異。

產物在忽略的 `.artifacts/`：`probe.wasm`、`native.json`、`node.json`、各 browser 的成功及錯誤路徑 report、toolchain 記錄。CI 的 [Wasm Probe](../../.github/workflows/wasm-probe.yml) 在相關 PR / main push 執行三種 browser engines，保留 artifact 7 天；它不發布網站。

## 手動檢視

```sh
npm run serve
```

開啟 `http://127.0.0.1:8787/`；頁面自動建立 module Worker，執行 Wasm 並顯示結果。開發伺服器僅綁定 localhost，只提供探針頁面、Worker、Wasm 與 WASI shim modules。它提供 `application/wasm` MIME type，不需要 COOP / COEP 或 SharedArrayBuffer。

## 實測與限制（2026-09-30）

- **VERIFIED，本地 Debian 13 / Swift 6.4.0 / Node 24.19.0**：原生與 wasm32 release 建置；Node WASI；Chromium 與 Firefox 的 Worker；17 個 fixtures 與 6 個 Swift 檢查。Wasm 使用的是同一份 GameCore。
- **VERIFIED，本地原生**：根目錄 `swift build --build-tests -Xswiftc -warnings-as-errors`；`swift test --filter 'GoldenScenarioTests|VerticalRailwayTests'`，36 tests、0 failures。
- **UNVERIFIED，本地 WebKit**：此工作區缺少 GTK4 等 shared libraries，無法啟動。CI 會安裝 browser dependencies 後執行；Playwright WebKit 也不能代替真正 iPhone / iPad Safari 驗證。
- **已確認的相容差異**：Wasm `Int` 是 32 位元（最大 2147483647），原生是 64 位元。GameCore 的部分 ID / counter 使用 Int，因此大 ID 的存檔及 IDs exhausted 邊界尚未跨平台統一。通過目前 fixtures 不表示所有原生存檔都能移植；此探針不修改核心來掩蓋差異。
- **大小基線**：本地未壓縮 Wasm release 產物 65,007,826 bytes（約 62 MiB），包含完整 Swift runtime、Foundation JSON codec 與 golden fixtures/runner；這是驗證 binary，並非最終遊戲下載大小，也尚未做 size optimization。
- **UNVERIFIED**：完整 property campaigns 在 Wasm 執行、持續 Worker session、完整 command API、3D renderer、瀏覽器持久存檔、效能與正式發布。核心的 Codable 在 executable 內驗證，尚未作為正式 Web wire protocol。

下一個 W1 PR 才實作宿主計時、持續 Worker session 與最小指令契約；是否統一 Int ID 邊界需先明確決策。整體計畫見 [WEB_PORT_READINESS](../../docs/WEB_PORT_READINESS.md)。
