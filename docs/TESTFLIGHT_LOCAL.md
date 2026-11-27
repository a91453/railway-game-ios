# 在作者的 Mac 上本機發 TestFlight 內測（不經 GitHub Actions）

平常的發版是 `testflight.yml`（`docs/TESTFLIGHT_GITHUB_ACTIONS.md`）。這份是同一套步驟改在作者自己的 Mac 上跑，只發**內部測試**（`testFlightInternalTestingOnly`）：不送審、不開外部測試。第一次是 2026-11-27 發 0.6.0（152.1）。

一樣只有作者能決定發版（`CLAUDE.md`）；作者說「發內測」之後，session 才可以照這份做。

## 一行指令

```sh
git clone --local ~/Developer/railway-game-ios ~/Developer/testflight-local   # 第一次；之後 git fetch
cd ~/Developer/testflight-local && git checkout -B local-testflight origin/main
ASC_KEY_ID=<Key ID> ASC_ISSUER_ID=<Issuer ID> tools/release/testflight-local.sh
```

用另外 clone 的資料夾，不要在別的 session 正在用的 checkout 裡跑：腳本要乾淨的 `origin/main`，跑的時候會暫時把品牌寫進工作副本（結束時放回去）。

`--no-upload` 只封存、匯出、檢查 IPA，不傳任何東西給 Apple；`--archive <路徑>` 重用已經封存好的 archive（同一個 build 號）。

## build 號

預設是「最新一次成功的 `testflight.yml` run 號」加 `.1`，例如 CI 最後是 152，本機就發 `152.1`。CI 的 build 號是 `N`（第一次）或 `N.2`～`N.99`（重跑），從來不用 `N.1`（`testflight-preflight.sh`），所以本機和 CI 永遠不會撞號，下一次 CI（153）也一定比本機的大。同一個 CI 版之後要再發第二次本機版，就用 `--build 152.1.1`。

build 號只在封存時以 `CURRENT_PROJECT_VERSION` 傳進去，repo 裡的 `project.yml` 不用改，也不用開 PR。

## 和 CI 不同的地方

| 步驟 | CI（`testflight.yml`） | 本機 |
|---|---|---|
| 簽章用的鑰匙圈 | 臨時鑰匙圈，設成預設 | 作者的「登入」鑰匙圈（不換預設鑰匙圈，免得影響作者其他 App） |
| 封存簽章 | `adhoc` | 自動開發簽章（Xcode 裡登入的帳號）；這台 Mac 上 `adhoc` 會被拒：「has entitlements that require signing with a development certificate」 |
| 匯出、上傳 | API 金鑰 | 有 `ASC_KEY_ID`／`ASC_ISSUER_ID` 就用 API 金鑰，沒有就用 Xcode 帳號 |
| 地圖包 | `testflight-map-packs.py` 判斷，`altool` 上傳 | 同一支腳本、同樣先傳地圖包再傳 build（DEBUG-138）；地圖包**只能**用 API 金鑰傳 |
| 品牌 | secret `GAME_BRAND_JSON` | `../railway-assets-private-2/branding/game-brand.json`（沒有就 `../railway-assets-private/`） |
| Team ID、App ID、上次發版 | 環境變數 | `gh variable get … --env testflight`、`gh run list` |
| What to Test、等處理完成 | Linux job | 沒有：上傳後到 App Store Connect 看 |

內部測試群組 `Internal` 開了自動發佈，處理完（約 10～30 分鐘）就會出現在 TestFlight，不用手動加。

## 作者要按的（第一次）

1. **解鎖登入鑰匙圈**：遠端控制的 session 叫不出密碼視窗，鑰匙圈鎖著時 codesign 會失敗（`errSecInternalComponent`）。在終端機：

   ```sh
   security unlock-keychain ~/Library/Keychains/login.keychain-db
   ```

   跳出「codesign 想要存取鑰匙圈」時輸入密碼、按**永遠允許**，之後就不會再問。
2. **本機用的 API 金鑰**（地圖包有變時才一定要）：App Store Connect → Users and Access → Integrations → Team Keys →「+」，名稱 `Mac local release`，權限 **App Manager**，下載 `AuthKey_<Key ID>.p8` 放到 `~/.appstoreconnect/private_keys/`（`altool` 預設找這裡）。Key ID 和 Issuer ID 不是機密，可以告訴 session；`.p8` 的內容不要貼給任何人，也絕不放進 repo。
3. Xcode → Settings → Accounts 要登入團隊的 Apple ID（匯出時的雲端發佈簽章用它）。

## 之後要記得

- 本機發版不會變成「成功的 `testflight.yml` run」，所以下一次 CI 發版還是拿 CI 上一次的 commit 比地圖包，會把本機已經傳過的地圖包再傳一次（多一個要審的版本，內部測試不受影響）。
- 封存、IPA、log 在 `~/RailwayTestFlight/<build>/`；IPA 裡有發佈用的描述檔，build 出來之後就刪掉整個資料夾。
- 不要把 `~/RailwayTestFlight/` 或 `.p8` 複製進任何 repo。
