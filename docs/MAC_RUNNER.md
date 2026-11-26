# 作者的 Mac 當 iOS 的 CI runner（決策 1014）

PR 的 iOS 建置（`ios-build.yml` 的 build job）在作者的 Mac 在線又有空時用 Mac 跑，否則照舊用 GitHub 的 macOS 機器。
怎麼選、安全的考量在[決策 1014](decisions/1014.md)。這頁是設定步驟，約 15 分鐘。

## 1. 準備 Mac

1. 系統設定 → 使用者與群組，加一個**標準**使用者，`cirunner`（2026-11-26 已建）。runner 裝在這個帳號下，PR 的程式碰不到你自己帳號的東西。
2. 用 `cirunner` 登入一次：打開 Xcode（要 27.2，和 `.github/actions/select-xcode` 寫的同版），同意授權；Settings → Components 確認
   iOS 27.2 的模擬器在。
3. `cirunner` 帳號要保持登入（用「快速切換使用者」切回你的帳號就好）：UI 測試的模擬器需要登入的畫面。

## 2. 註冊 runner

1. GitHub：railway-game-ios → Settings → Actions → Runners → New self-hosted runner → macOS、ARM64。
2. 在 `cirunner` 帳號的終端機照頁面上的指令跑（下載、解壓、`./config.sh ...`）。`./config.sh` 問名稱時填 `chien-mac`，
   問 labels 時填 `chien-mac,xcode-27.2`，其他按 Enter。
   `xcode-27.2` 是在說這台 Mac 的 Xcode 版本，要和 `.github/actions/select-xcode` 的 `XCODE_VERSION` 一樣；沒有這個標籤，或版本對不上，PR 一律用 GitHub 的機器。
3. 裝成開機自動啟動的服務：

   ```sh
   ./svc.sh install
   ./svc.sh start
   ```

4. 回到 Runners 頁，`chien-mac` 應該是綠色 Idle。

現況（2026-11-26）：已上線，裝在 `/Users/cirunner/actions-runner`，labels 是 `self-hosted`、`macOS`、`ARM64`、`chien-mac`。
**還要加一個標籤**：Runners 頁點 `chien-mac` → Labels 旁的齒輪 → 輸入 `xcode-27.2` → 建立並勾選。加之前 PR 都還是用 GitHub 的機器。

**Xcode 不要自動更新**：App Store → 設定，關掉「自動更新」（或至少別讓 Xcode 自己升級）。要升級 Xcode 時：
1. 先把 runner 的 `xcode-27.2` 標籤拿掉（PR 會改用 GitHub 的機器）；
2. 升級、裝好對應的模擬器；
3. 等 repo 的 `select-xcode` 也改成新版本後，再加上新版本的標籤（例如 `xcode-27.3`）。
Mac 開著 FileVault，重新開機後要用 `cirunner` 登入一次，runner 才會再上線；沒登入的時候 Runners 頁是 Offline，
PR 會自動用 GitHub 的機器，不會卡住。

## 3. GitHub 的兩個設定

1. Settings → Actions → General → Fork pull request workflows from outside collaborators →
   **Require approval for all external contributors**。
2. 一把只能看 runner 狀態的 token：GitHub 右上頭像 → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate。Repository access 只選 `railway-game-ios`；Repository permissions 只把
   **Administration 設成 Read-only**。產生後到 railway-game-ios → Settings → Secrets and variables → Actions →
   New repository secret，名稱 `RUNNER_STATUS_TOKEN`，貼上。token 到期前再換一把；過期了只會全部改回 GitHub 的機器。

## 4. 平常怎麼用

- 什麼都不用做。PR 的 iOS run 第一個 job「Pick the Mac or a hosted runner」的摘要會寫這次用了 Mac 還是 GitHub、為什麼。
- 工作室要用 Mac：`cirunner` 帳號 `./svc.sh stop`，用完 `./svc.sh start`。或在 Settings → Secrets and variables → Actions →
  Variables 加 `MAC_RUNNER`，值 `off`（刪掉或改成別的就恢復）。
- 一次只跑一個 job；Mac 忙的時候新的 PR 用 GitHub 的機器。
- 已經排給 Mac 的 job，runner 中途被停掉會一直等：在 GitHub 重跑那個 run。

## 5. 不會用 Mac 的

full lane（每晚與發版前）、`release-archive.yml`、`ios-compilation-cache.yml`、別的 repository 開來的 PR。
`testflight.yml` 只用下面 §6 的發版專用 runner，不用 `cirunner`。

## 6. 發版專用的 runner（決策 1016，約 15 分）

TestFlight（從 main 手動按的 `testflight.yml`）要在 Mac 上跑，就在 Mac 上**再開一個帳號**、裝第二個 runner。
不和 PR 共用 `cirunner`：PR 的程式會在 `cirunner` 裡跑，可能在那個帳號留下東西，等發版寫出上傳用的金鑰時讀走。
沒做這一節之前，TestFlight 照舊全部用 GitHub 的機器，不會壞。

**不用在這個帳號登入 Apple ID 或 Xcode 的開發者帳號**：簽章和上傳用的是 GitHub 上 `testflight` 環境裡已經存好的
App Store Connect API key，和 GitHub 的機器一樣。你自己帳號裡登入的開發者帳號不會被用到。

1. 系統設定 → 使用者與群組 → 加入使用者：**標準**，名稱 `cirelease`（不要用管理者）。
2. 用 `cirelease` 登入一次，打開 Xcode（27.2，`/Applications` 裡同一個就好），按同意授權；如果問要不要裝 iOS 平台，裝 iOS 27.2。
   不用登入 Apple 帳號。
3. GitHub：railway-game-ios → Settings → Actions → Runners → New self-hosted runner → macOS、ARM64。
   在 `cirelease` 帳號的終端機照頁面上的指令跑（`mkdir actions-runner && cd actions-runner`、下載、解壓、`./config.sh ...`）。
   - 問名稱時填 `chien-mac-release`。
   - 問 labels 時填 `chien-mac-release,xcode-27.2`。**不要**填 `chien-mac`（那是 PR 用的，填了 PR 就會排到這個帳號）。
   - 其他按 Enter。
4. 裝成服務：

   ```sh
   ./svc.sh install
   ./svc.sh start
   ```

5. 回到 Runners 頁，`chien-mac-release` 應該是綠色 Idle，labels 只有 `self-hosted`、`macOS`、`ARM64`、`chien-mac-release`、`xcode-27.2`。
6. 平常：
   - `cirelease` 要保持登入（快速切換使用者切回自己的帳號就好），Mac 接電源時不要睡著
     （系統設定 → 能源 → 「顯示器關閉時防止自動進入睡眠」）。重開機後要用 `cirelease` 登入一次。
   - 按 TestFlight 之後，run 的第一個 job「Pick the Mac or a hosted runner」的摘要會寫用了 Mac 還是 GitHub、為什麼。
   - Mac 不在線、在忙、睡著時自動用 GitHub 的機器。已經排給 Mac 卻一直等（Mac 半路睡著）：取消，按 **Re-run all jobs** 重選。
   - 想要更保險：平常在 `cirelease` 帳號 `./svc.sh stop`，發版前 `./svc.sh start`，發完再停。停著的時候發版會用 GitHub 的機器。
   - 想暫時不用 Mac 發版：Variables 的 `MAC_RUNNER` 設 `off`（PR 也一起不用 Mac）。
