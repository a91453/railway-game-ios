# 在作者的 Mac 上本機發 TestFlight 內測（不經 GitHub Actions）

平常的發版是 `testflight.yml`（`docs/TESTFLIGHT_GITHUB_ACTIONS.md`）。這份是同一套步驟改在作者自己的 Mac 上跑，只發**內部測試**（`testFlightInternalTestingOnly`）：不送審、不開外部測試。第一次是 2026-11-27 發 0.6.0（152.1），從 origin/main `b168ab80e`。

一樣只有作者能決定發版（`CLAUDE.md`）；作者說「發內測」之後，session 才可以照這份做。

## 一行指令

```sh
git clone --local ~/Developer/railway-game-ios ~/Developer/testflight-local   # 第一次；之後 git fetch
cd ~/Developer/testflight-local && git checkout -B local-testflight origin/main
tools/release/testflight-local.sh
```

用另外 clone 的資料夾，不要在別的 session 正在用的 checkout 裡跑：腳本要乾淨的 `origin/main`，跑的時候會暫時把品牌寫進工作副本（結束時放回去）。

`--no-upload` 只封存、匯出、檢查 IPA，不傳任何東西給 Apple；`--archive <路徑>` 重用已經封存好的 archive（同一個 build 號）。

## build 號

預設是「最新一次成功的 `testflight.yml` run 號」加 `.1`，例如 CI 最後是 152，本機就發 `152.1`。CI 的 build 號是 `N`（第一次）或 `N.2`～`N.99`（重跑），從來不用 `N.1`（`testflight-preflight.sh`），所以本機和 CI 永遠不會撞號，下一次 CI（153）也一定比本機的大。同一個 CI 版之後再發本機版，腳本自己接著用 `152.1.1`、`152.1.2`…（記在 `~/RailwayTestFlight/last-release.json`）。

build 號只在封存時以 `CURRENT_PROJECT_VERSION` 傳進去，repo 裡的 `project.yml` 不用改，也不用開 PR。

## 和 CI 不同的地方

| 步驟 | CI（`testflight.yml`） | 本機 |
|---|---|---|
| 簽章用的鑰匙圈 | 每次新建的臨時鑰匙圈，設成預設 | 固定的發版鑰匙圈 `~/.appstoreconnect/release.keychain-db`，跑的那幾分鐘設成**唯一**、預設的鑰匙圈，結束（失敗或 Ctrl-C 也一樣）就改回原本的設定 |
| 封存簽章 | `adhoc` | `automatic`（API 金鑰自動開發簽章，第一次會在發版鑰匙圈裡新做一張 Apple Development 憑證）。這台 Mac 上 `adhoc` 會被拒：「has entitlements that require signing with a development certificate」，換成空的鑰匙圈也一樣 |
| 匯出、上傳 | API 金鑰（雲端發佈憑證） | 同上，金鑰要 **Admin**：App Manager 的金鑰匯出時會被拒「You haven't been given access to cloud-managed distribution certificates」 |
| 地圖包 | `testflight-map-packs.py` 判斷，`altool` 上傳 | 同一支腳本、同樣先傳地圖包再傳 build（DEBUG-138），但和「CI 上次」與「Mac 上次」（`last-release.json`）比較新的那次比（`tools/release/local_release.py`） |
| App 內建地圖包 | `carry_map_packs`（預設 yes） | `--carry-map-packs yes|no`（預設 yes）；`no` 只帶 `pack.json`，地圖從 App Store Connect 下載 |
| 品牌 | secret `GAME_BRAND_JSON` | `../railway-assets-private-2/branding/game-brand.json`（沒有就 `../railway-assets-private/`） |
| Team ID、App ID、上次發版 | 環境變數 | `gh variable get … --env testflight`、`gh run list` |
| What to Test、等處理完成 | Linux job | 同一支 `testflight-processing.py`，上傳完在本機等（最多 60 分鐘），What to Test 是上一次發版（CI 或 Mac，較新的那次）之後合的 PR |

內部測試群組 `Internal` 開了自動發佈，處理完（約 10～30 分鐘）就會出現在 TestFlight，不用手動加。

## 作者要按的（只有第一次）

1. **Admin 權限的 API 金鑰**：App Store Connect → Users and Access → Integrations → Team Keys →「+」，名稱 `Mac local release admin`，權限 **Admin**（管理），下載 `AuthKey_<Key ID>.p8`：

   ```sh
   mkdir -p ~/.appstoreconnect/private_keys && chmod 700 ~/.appstoreconnect ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/ && chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
   ```

   把 Key ID 和頁面上方的 Issuer ID 告訴 session，它寫進 `~/.appstoreconnect/local-release.env`（權限 600，兩行 `ASC_KEY_ID=…`、`ASC_ISSUER_ID=…`；發版鑰匙圈的隨機密碼第一次跑時也記在這裡）。`.p8` 的內容不要貼給任何人，這些檔都絕不放進 repo。金鑰建好就不能改權限，選錯了只能再做一把、把舊的 Revoke。

作者的「登入」鑰匙圈完全不用：2026-11-27 它的密碼和 Mac 登入密碼不同步，遠端 session 也叫不出解鎖視窗，codesign 會失敗（`errSecInternalComponent`），所以才改用發版鑰匙圈。

## 之後要記得

- 發版鑰匙圈當唯一鑰匙圈的那幾分鐘，其他 App 讀不到登入鑰匙圈；跑完會自動改回。腳本被強制結束（`kill -9`、當機）而沒改回時，在終端機跑 `security list-keychains -d user -s ~/Library/Keychains/login.keychain-db && security default-keychain -d user -s ~/Library/Keychains/login.keychain-db`。
- 不要的時候：developer.apple.com → Certificates 撤銷那張開發憑證，App Store Connect 撤銷 API 金鑰，刪掉 `~/.appstoreconnect/`。
- 本機發版不會變成「成功的 `testflight.yml` run」：本機腳本會讀 `last-release.json`，但下一次 **CI** 發版只認 CI 上一次的 commit，會把本機已經傳過的地圖包再傳一次（多一個要審的版本，內部測試不受影響）。
- 封存、IPA、log 在 `~/RailwayTestFlight/<build>/`；IPA 裡有發佈用的描述檔，build 出來之後就刪掉整個資料夾。
- 不要把 `~/RailwayTestFlight/` 或 `.p8` 複製進任何 repo。
