# iCloud 存檔：作者要按的步驟

決策 397。這些是 Apple 帳號裡的設定，只有作者能做；程式（`SaveSync`、`ICloudSaveFolder`）已經在 App 裡，沒有權限時照舊只存本機。這份文件不需要、也不會要任何密碼、2FA 驗證碼或金鑰。

- 容器名稱：**`iCloud.io.github.a91453.RailwayGame`**
- 用到的服務：iCloud Documents（iCloud Drive）。**不用** CloudKit 的 record，也不需要在 CloudKit Console 部署 schema（TestFlight 的 build 用的是 production 環境；CloudKit 沒部署 schema 的話，TestFlight 上會不能用。iCloud Drive 沒有這一步，TestFlight 一裝上就能測）。
- TestFlight 的測試員用的是自己真正的 iCloud 帳號，存檔是真的資料：衝突時一定兩份都留（決策 397）。
- 和 Game Center（`docs/GAME_CENTER_SETUP.md`，決策 396）一起做，最後一個 PR 一起加兩個 entitlement。

## 1. Apple Developer：建 iCloud 容器

1. 開 developer.apple.com → **Account** → **Certificates, Identifiers & Profiles** → 左邊 **Identifiers**。
2. 右上角篩選選單選 **iCloud Containers**，按 **「+」**。
3. 選 **iCloud Containers** → **Continue**。
4. **Description** 填 `Along the Line saves`；**Identifier** 填 `iCloud.io.github.a91453.RailwayGame`（前面的 `iCloud.` 要留著）。→ **Continue** → **Register**。

## 2. Apple Developer：App ID 打開 iCloud

1. 同一頁，篩選選單改回 **App IDs**，點 `io.github.a91453.RailwayGame`。
2. **Capabilities** 分頁往下找 **iCloud**，勾起來。出現選項時選 **Include CloudKit support (requires Xcode 6)**（iCloud Documents 也走這個選項）。
3. iCloud 那一列右邊按 **Configure**（或 **Edit**），勾 `iCloud.io.github.a91453.RailwayGame` → **Continue**。
4. 右上角 **Save**。出現「修改 capability 會讓描述檔失效」的提示，按 **Confirm**。描述檔不用手動重做：`testflight.yml` 用 App Store Connect API key 加 `-allowProvisioningUpdates` 自動簽章，下一次跑會自己產生含 iCloud 的新描述檔。
5. Game Center 那一格照 `docs/GAME_CENTER_SETUP.md` 一起勾（同一頁同一次 Save 也可以）。

## 3. App Store Connect

iCloud Documents 不需要在 App Store Connect 另外設定。

- **App Privacy（隱私營養標籤）**：存檔放在玩家自己的 iCloud，開發者讀不到，不算「蒐集資料」（決策 397 的〈隱私〉）。不必因此新增任何資料類型。
- 送審（不是內部 TestFlight）之前，官網的隱私權政策要加一句「存檔會放進你自己的 iCloud」（決策 397 的下一步）。

## 4. 做完之後

在 #1041 或遊戲規劃的 session 說一聲「iCloud 和 Game Center 都設定好了」。之後的 PR 才會加 entitlement（`RailwayGameApp/project.yml` 加 entitlements 再重新產生 Xcode 專案）。**順序很重要**：entitlement 比 Apple 那邊的設定先合併的話，`testflight.yml` 的簽章會失敗。

加了 entitlement 的 build 上 TestFlight 後，請用同一個 Apple 帳號的兩台裝置試：

1. 兩台的「設定 › Apple 帳號 › iCloud」裡 iCloud 雲碟都開著，「使用 iCloud 的 App」裡《沿線》也開著。
2. iPhone 玩一下，回主畫面。
3. iPad 開《沿線》，存檔清單下面要出現「存檔也會放進你的 iCloud……」，按「繼續」接著 iPhone 的進度（iCloud 上傳下載有時要一兩分鐘）。
4. 兩台都關網路各玩一下，再打開網路，回開始畫面：要看到「兩份都留著」的訊息，存檔清單裡多一份「另一台裝置的進度」。

## 玩家關掉 iCloud 時

不用做任何事：沒登入 iCloud、iCloud 雲碟關閉、或關掉這個 App 的 iCloud，遊戲照舊存在這台裝置上，不跳錯誤，也不提 iCloud。
