# GitHub Actions → TestFlight

目前的發佈路線是在 GitHub 標準 macOS runner（`macos-26`，預設 Xcode 26.6）上完成以下步驟，再上傳到 TestFlight。手動執行時可選 `internal`（僅內部測試）或 `external`（可加入 External Testing 群組並送 Beta App Review）：

1. Archive（Release）
2. 簽章
3. 匯出 IPA
4. 檢查 IPA
5. 上傳 App Store Connect

整個流程不需要自己的 Mac。Xcode Cloud 暫緩，[XCODE_CLOUD_ONBOARDING.md](XCODE_CLOUD_ONBOARDING.md) 保留供日後使用。

官方文件查閱日期：**2026-09-28**（來源列在文末）。

## 狀態

| 項目 | 狀態 |
| --- | --- |
| Workflow、腳本、暫存 keychain 與清理、build number、本手冊 | **已完成** |
| 不需帳號的驗證（腳本測試、macOS dry run、合成 IPA 檢查） | **VERIFIED**（見〈驗證狀態〉） |
| Apple Developer Program、Team API key、GitHub environment、真實 Apple 驗證 | **VERIFIED**（見〈真實執行紀錄〉） |
| 真實 Release Archive（`adhoc`）、App Store 發佈簽章匯出、IPA 檢查、上傳到 App Store Connect、清理 | **VERIFIED**：第 2 次執行全部成功 |
| `automatic` Archive | 在沒有已註冊裝置的新團隊**失敗**（已觀察）；仍保留為選項 |
| App Store Connect processing、TestFlight 安裝到裝置 | **UNVERIFIED**：repository 與 workflow log 裡沒有證據 |

`release-archive.yml` 的未簽章 Archive，以及 `testflight-checks.yml` 的 dry run 與合成 IPA 測試，仍然**不能**證明真實簽章；真實簽章與上傳的證據只來自〈真實執行紀錄〉的兩次執行。

## 流程

```
Actions → TestFlight → Run workflow（只允許 main）
  ├─ preflight（Linux，數秒）
  │    分支與觸發方式、每個必要設定是否存在且格式正確；
  │    缺少就一次列出全部並停止，不啟動 macOS runner
  └─ release（macos-26）
       再檢查一次設定，並依這次執行的 attempt 決定 build number
       → 暫存 keychain + API key 檔（權限 600）
       → Archive：Release、generic iOS device、已提交的專案與 shared scheme、
         真實 Team；預設 `adhoc` 簽章（`automatic` 為選項，見下）
       → 匯出 IPA：xcodebuild -exportArchive，App Store Connect 發佈，
         `internal` 時加入 `testFlightInternalTestingOnly=true`；`external` 時省略此鍵，
         自動簽章 + API key
         （本機沒有發佈憑證時使用 Apple 雲端管理的發佈憑證）
       → 檢查 IPA：bundle ID、版本、build number、Team 與 application identifier、
         發佈憑證、App Store 描述檔（無裝置清單、不可除錯）、結構
       → 上傳：同一份 archive、相同設定再以 xcodebuild -exportArchive
         （destination=upload，API key）送到 App Store Connect；
         只在 IPA 檢查通過後執行
       → 清理（成功、失敗、取消都執行）
```

| 檔案 | 用途 |
| --- | --- |
| `.github/workflows/testflight.yml` | 發佈；**只有** `workflow_dispatch`，沒有排程、push 或 PR 觸發 |
| `.github/scripts/testflight-preflight.sh` | 發佈前檢查與 build number |
| `.github/scripts/testflight-signing.sh` | 暫存 keychain、API key 檔的建立與清理 |
| `.github/scripts/testflight-archive.sh` | Archive，以及匯出（export）與上傳（upload）兩份 ExportOptions |
| `.github/scripts/testflight-verify-ipa.sh` | 上傳前的 IPA 檢查 |
| `.github/workflows/testflight-checks.yml` | PR 檢查：lint、腳本測試、macOS dry run、合成 IPA 測試；不需帳號、不用 secrets |
| `.github/scripts/testflight-selftest*.sh` | 上述檢查用的測試（只用假值） |

- **只允許一個發佈同時進行**：`concurrency: testflight-release`，而且不取消進行中的上傳。執行中再按一次會排隊；排隊時又按一次，GitHub 會用最新的取代排隊中的那一個。
- **TestFlight 範圍**（Run workflow 的 `testing_scope` 選項）：`internal` 為預設，保留原本僅內部測試行為；`external` 會上傳可供 External Testing 使用的新 build。外部測試仍需在 App Store Connect 將該 build 加入外部群組並通過 Beta App Review。
- **Archive 簽章方式**（Run workflow 的 `archive_signing` 選項）：
  - `adhoc`（預設，第一個選項）：以 ad hoc（`-`）簽章封存，不需要開發憑證或開發描述檔。適合 CI 與沒有已註冊開發裝置的新團隊。
    - **它不是最後輸出的 IPA 類型**：最後的 IPA 仍在匯出階段以 App Store distribution 憑證與 App Store 描述檔簽章，IPA 檢查會驗證這一點（真實執行的 log 顯示「App Store distribution build」）。
  - `automatic`：對 archive 做自動開發簽章（API key + `-allowProvisioningUpdates`）。需要可用的開發描述檔，而 Apple 只有在團隊至少註冊一台裝置時才會產生；沒有裝置時 archive 會失敗（見〈真實執行紀錄〉）。團隊註冊裝置之後才有意義；保留作為選項，不需要時不必使用。

## 需要的設定

全部放在 GitHub repository 的 **Environment `testflight`**，不是 repository 層級。只有引用這個 environment 的 job 拿得到，且只允許 `main` 使用。

| 名稱 | 類型 | 內容 | 取得方式（Apple 網站） |
| --- | --- | --- | --- |
| `APPLE_TEAM_ID` | Variable | 10 字元 Team ID（公開識別碼） | developer.apple.com → Account → Membership details |
| `ASC_APP_ID` | Variable | App 在 App Store Connect 的數字 Apple ID | App Store Connect → Apps → 你的 App → App Information → Apple ID |
| `BUILD_NUMBER_OFFSET` | Variable（選填） | 0–9999；加到 run number 上，且相加後不可超過 9999；預設 0 | 見〈Build number〉 |
| `ASC_KEY_ID` | Secret | Team API key 的 Key ID | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys |
| `ASC_ISSUER_ID` | Secret | Issuer ID（UUID） | 同一頁上方 |
| `ASC_PRIVATE_KEY` | Secret | `AuthKey_<Key ID>.p8` 的**完整文字**，含 BEGIN / END 兩行 | 產生 key 時下載，**只能下載一次** |

**不需要、也不要提供**以下東西：
- `.p12`、憑證、描述檔
- keychain 密碼（執行時隨機產生，用完即刪）
- Apple 帳號密碼、App 專用密碼、雙重認證碼

Team ID 只放在 GitHub variable，**不寫進 repository**。會員生效前，不要填任何假值。

## 會員生效後：只用 iPad 的首次設定

Apple 沒有明文保證 iPad Safari 能操作下列網頁，但它們都是一般網站；版面有問題時，在 Safari 選「要求桌面版網站」。

1. **確認會員生效**：以 Account Holder 登入 App Store Connect。一開始只有 Account Holder 能登入。
2. **註冊 Bundle ID**：developer.apple.com → Certificates, Identifiers & Profiles → Identifiers →「+」→ App IDs → App → Explicit，填 `io.github.a91453.RailwayGame`，Capabilities 全不勾。
3. **建立 App record**：App Store Connect → Apps →「+」→ New App。
   - 平台選 iOS；名稱須在 App Store 唯一；Bundle ID 選上一步註冊的；SKU 例如 `railwaygame-ios`。
   - 建立後，在 App Information 記下 **Apple ID**，這就是 `ASC_APP_ID`。
4. **申請 API 存取**：Users and Access → Integrations → App Store Connect API → Request Access。只有 Account Holder 能申請，Apple 逐案審核，可能需要等待。
5. **產生 Team API key**：同一頁 Team Keys → Generate API Key → 名稱例如 `GitHub Actions TestFlight` → Access 選 **Admin** → Generate。
   - 名稱與權限之後不能修改。
   - 為什麼要 **Team** key：個人（Individual）key 不能使用 provisioning。
   - 為什麼要 **Admin**：雲端管理的發佈憑證預設只有 Admin / Account Holder 可用，建立發佈描述檔也需要 Admin。
   - 記下頁面上方的 **Issuer ID**，以及這把 key 的 **Key ID**。
   - 下載 `.p8`（只能一次）到「檔案」App。要複製內容時，把副檔名改成 `.txt` 再打開，全選後複製。
   - 這把 key 有 Admin 權限：
     - 只貼進 GitHub environment secret；要備份就放在密碼管理器。
     - 外流或遺失時，在同一頁 **Revoke**，再產生新的。
     - 不要貼給任何人（包括 Claude），也不要放進 repository、issue、PR 或聊天。
6. **建立 GitHub environment**：在 github.com 用 Safari 開 repository → Settings → Environments → New environment，名稱 `testflight`。
   - **Deployment branches and tags**：選 **Selected branches and tags**，只加入 `main`。
   - **Required reviewers**（選用）：加上自己，每次發佈前多一次確認。不要勾「Prevent self-review」，否則你無法核准自己的發佈。preflight 與 release 兩個 job 都使用這個 environment，所以每次發佈會要求核准兩次。
   - **Environment secrets**：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY`（貼上 `.p8` 全文，換行保持原樣即可）。
   - **Environment variables**：`APPLE_TEAM_ID`、`ASC_APP_ID`；`BUILD_NUMBER_OFFSET` 選填。
7. **內部測試群組**：App Store Connect → 你的 App → TestFlight → Internal Testing「+」→ 群組 `Internal`，加入自己，勾「Enable automatic distribution」。Apple 說明中必須手動加入群組的是 Xcode Cloud 的 build；若新 build 沒有自動出現，在群組頁按 Add Builds 手動加入。
8. **發佈**：GitHub → Actions → **TestFlight** → Run workflow → Branch 選 `main`，`archive_signing` 維持預設的 `adhoc`；自己測試選 `testing_scope: internal`，要給朋友外部測試則選 `testing_scope: external` → Run workflow。
9. **上傳之後**：
   - App Store Connect 會先處理（processing），通常數分鐘到數十分鐘。
   - TestFlight 若顯示 **Missing Compliance**，依實際情況回答出口合規問題（見 XCODE_CLOUD_ONBOARDING.md〈出口合規〉；本專案不替你預設答案）。
   - `internal`：照原本方式在內部群組安裝。
   - `external`：在 App Store Connect → TestFlight → External Testing 將新 build 加到外部群組（例如 `Friends Beta`），填測試資訊並送 Beta App Review；核准後再以 Email 或 Public Link 邀請朋友。

**會員生效前也可以先試跑**：先完成步驟 6 的 environment 與分支限制。preflight 會在幾秒內列出所有缺少的設定並停止，不啟動 macOS runner、不簽章、不上傳。若 environment 還不存在，GitHub 會自動建立一個沒有分支限制的 `testflight`，之後再補上限制即可。

## Build number

- **規則**：`<BUILD_NUMBER_OFFSET + run number>.<run attempt>`。
  - 例如第 7 次執行是 `7.1`，重跑同一次是 `7.2`，下一次執行是 `8.1`。
  - 版本號（目前 0.2.0）來自 `project.yml` 的 `MARKETING_VERSION`，不由 workflow 改動。
- **GitHub**：run number 每次新執行加一、重跑不變；run attempt 每次重跑加一。所以每次執行與重跑都會得到從未用過的 build number，新的執行一定比舊的大。
  - release job 會自己依當下的 attempt 重新計算 build number。所以只按「Re-run failed jobs」重跑失敗的 release job 時，也會拿到新的號碼，不會沿用 preflight job 上一次算出的值。
- **Apple**：
  - `CFBundleVersion` 使用整數段；Apple 對第一段限制最多 4 位、第二段最多 2 位，所以 `7.2` 合法，而 workflow 會拒絕第一段大於 9999 或 attempt 大於 99。
  - App Store Connect 要求版本號與 build number 的組合不重複。
  - Apple 舊技術文件（TN2420）另寫明：同一版本內 build number 要遞增。所以同一版本已上傳較新的 build 之後，**不要重跑更舊的執行**，改按一次新的 Run workflow。
- **需要跳號時**設定 `BUILD_NUMBER_OFFSET`，例如 workflow 改名讓 run number 從 1 重新起算，或曾用其他方式上傳過較大的 build。Offset 與 run number 相加後必須 ≤ 9999；若此 workflow 真正累積到 10,000 次手動發佈，需要先改 build-number 編碼方案。

## 真實執行紀錄

第一次與第二次真實執行，都從 `main` 手動觸發，同一個 commit `3924f23`（PR #34 的 merge），`macos-26` runner（macOS 26.6.2、Xcode 26.6、iOS SDK 26.5）。以下都從 GitHub Actions 的 job 與 log 讀取確認，不是口述。

| 執行 | `archive_signing` | 結果 | 網址 |
| --- | --- | --- | --- |
| #1（attempt 1，build `1.1`） | `automatic` | **失敗**於 Archive | https://github.com/a91453/railway-game-ios/actions/runs/36674350344 |
| #2（attempt 1，build `2.1`） | `adhoc` | **成功**（含上傳） | https://github.com/a91453/railway-game-ios/actions/runs/36674626548 |

**#1 `automatic`**：Preflight 與設定檢查、build number、Toolchain、暫存 keychain 與 API key 檔都成功；Archive 失敗（exit 65），匯出、IPA 檢查與上傳因此略過，清理仍執行且成功（刪除 keychain、key 檔與 archive）。Apple／Xcode 的錯誤：

- `Communication with Apple failed: Your team has no devices from which to generate a provisioning profile.`
- `No profiles for '<bundle id>' were found: Xcode couldn't find any iOS App Development provisioning profiles`

原因：這個新的 Apple Developer Team 沒有已註冊的裝置，Apple 無法產生 iOS App Development 描述檔，而 `automatic` 的 archive 需要它。Apple 的回應本身證明 API key 驗證是通的。

**#2 `adhoc`**：Preflight、Toolchain、暫存 keychain、Archive（約 60 秒）、Sign and export the IPA、Check the IPA、Upload to App Store Connect、Clean up 全部成功。log 的重點：

- IPA 檢查：bundle ID 正確、版本 `0.1.0 (2.1)`、簽章為 distribution 憑證、有此 Team 與 App 的 App Store 描述檔、結構完整，結論「The IPA is an App Store distribution build」。
- 上傳：xcodebuild 回報 `Upload succeeded`、`Uploaded package is processing`。
- 清理：暫存 keychain 已刪除、這次新增的 1 份描述檔已移除、key 檔／archive／IPA 已移除。

## 安全設計

- **Secrets 的範圍**：secrets 只在 environment `testflight`，只有從 `main` 手動觸發的發佈 job 拿得到。一般 PR、fork 的 PR、`testflight-checks.yml` 都拿不到，也不會發佈。preflight 另外會擋下非 `main` 或非手動的觸發。
- **API key 檔**：寫在 `$RUNNER_TEMP` 下、權限 600 的檔案，並移除 CR 與前導空行。
- **暫存 keychain**：以隨機密碼建立，暫時設為預設並加入搜尋清單，讓簽章過程中 Xcode 建立的任何東西都存進它。
- **清理**（`if: always()`）：
  - 還原原本的 keychain 搜尋清單與預設 keychain；
  - 刪除暫存 keychain、key 檔、這次新增的描述檔、archive 與 IPA（IPA 內含描述檔）。
  - 清理可以重複執行，setup 失敗或只完成一半時也安全。
- **不會存成 artifact**：IPA、archive、描述檔、憑證、key 都不會上傳成 artifact。
- **上傳的內容**：先檢查一份本地匯出的 IPA；上傳步驟再從**同一份 archive** 以相同 ExportOptions（只差 `destination`）與相同簽章方式重新匯出並直接上傳。它不是宣稱逐位元上傳剛才檢查的那個 IPA；上傳步驟只在本地 IPA 檢查通過後才執行。`internal` 模式的兩份 ExportOptions 都設 `testFlightInternalTestingOnly=true`；`external` 模式則都省略該鍵。
- **Log 是公開的**：這個 repository 公開，Actions log 任何人都看得到。
  - 腳本只印出「是否存在、格式是否正確、yes/no、版本資訊」，不印秘密，也不印含帳號持有人姓名的憑證或描述檔名稱。
  - GitHub 會自動遮蔽 secrets，但官方說明遮蔽不保證完整，所以腳本本身就不輸出它們。
  - 簽章 Archive、IPA export 與 upload 都以 `xcodebuild -quiet` 執行，降低公開 log 出現 signing identity 的機會；Apple 工具的錯誤訊息仍可能提到憑證名稱。
- **公開 log 裡看得到的識別碼**（真實執行 #1、#2 的 log 實際檢查）：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY` 與 key 檔名都被遮蔽為 `***`，`.p8` 內容、憑證與簽章者姓名都沒有出現。`APPLE_TEAM_ID` 與 `ASC_APP_ID` 是 **variables**，GitHub 不遮蔽 variables，所以它們會出現在每個步驟的 `env:` 區塊。這兩個是公開識別碼（Team ID 本來就在每個簽章的 App 與描述檔裡，App 的 Apple ID 在 App Store 網址裡），不能用來驗證或簽章；本 repository 仍不把它們的值寫進檔案。若想讓它們也不出現在 log，可以改放 environment secrets（要同步改 workflow 的 `vars.` 為 `secrets.`，這是另一個小改動）。
- **寫入權限**：有 repository 寫入權限的人都能讀取 secrets，不要把寫入權限給不信任的人。

## 驗證狀態

| 項目 | 狀態 | 在哪裡 |
| --- | --- | --- |
| Preflight：缺值、格式錯誤、非 main、tag、非手動觸發、`.p8` 截斷都會停止並一次列出；CRLF／前導空行的 `.p8` 可接受；不輸出秘密 | VERIFIED | 本機 Linux ＋ `testflight-checks.yml`（Linux） |
| Build number：`7.1` → 重跑 `7.2` → 下一次 `8.1`；offset；排序遞增；Apple 的 4 位／2 位 component 上限會在 preflight 擋下 | VERIFIED | 同上 |
| 暫存 keychain 建立、設定、設為預設、還原、刪除；假 `.p8` 的權限與正規化；失敗步驟後清理；重複清理 | VERIFIED | macOS dry run（真實 `security`）＋ 本機 stub |
| Archive 指令三種模式的參數與 ExportOptions；已提交的專案能以未簽章方式 archive | VERIFIED | macOS dry run ＋ 本機 stub |
| Xcode 26 提供需要的 `xcodebuild` 選項（`-exportArchive`、`-allowProvisioningUpdates`、`-authenticationKey*`）、ExportOptions 鍵、`app-store-connect` 方法與 `testFlightInternalTestingOnly`；匯出與上傳兩份設定只差在 `destination`，並以 macOS dry run 分別驗證 internal 會加入 internal-only 鍵、external 會省略該鍵 | VERIFIED | macOS dry run |
| IPA 檢查：正確的發佈 IPA 通過；build number 不符、開發描述檔、有裝置清單、缺描述檔、開發憑證簽章都擋下；不輸出姓名 | VERIFIED | macOS dry run（自簽的一次性憑證、合成 IPA）＋ 本機 stub |
| 真實 Apple 驗證：Team API key（Admin）與 GitHub environment `testflight` 的 secrets／variables 讀取、preflight 通過；不需要 `.p12`、Apple 密碼或雙重認證 | VERIFIED | 真實執行 #1、#2 |
| 沒有已註冊裝置的新團隊：`automatic` archive 失敗（沒有開發描述檔）；cleanup 在失敗後仍成功 | VERIFIED（觀察到的失敗） | 真實執行 #1 |
| `adhoc` 真實 Release Archive | VERIFIED | 真實執行 #2 |
| App Store distribution 簽章與描述檔的匯出（API key，雲端管理的發佈憑證）；IPA 檢查（distribution 憑證、App Store 描述檔、bundle ID、版本、build number、結構） | VERIFIED | 真實執行 #2 |
| 上傳到 App Store Connect（`Upload succeeded`） | VERIFIED（App Store Connect upload） | 真實執行 #2 |
| 清理（成功後與失敗後）；log 沒有 key、Key ID、Issuer ID、簽章者姓名 | VERIFIED | 真實執行 #1、#2 |
| App Store Connect processing 完成、Missing Compliance、TestFlight 安裝到裝置 | **UNVERIFIED** | repository 沒有證據；由你在 App Store Connect 與 TestFlight App 確認 |
| 取消時的清理（`if: always()`） | 由 macOS dry run 的失敗步驟驗證；**尚未**在真實執行中取消過 | — |
| `automatic` archive 在已註冊裝置的團隊上能否成功 | **UNVERIFIED** | 尚未有裝置可試 |

## 如果真實執行失敗

| 症狀 | 處理 |
| --- | --- |
| Preflight 列出缺少的設定 | 依〈需要的設定〉在 environment `testflight` 補上。注意是 environment，不是 repository secrets |
| 「Branch … is not allowed to deploy to testflight」 | 只能從 `main` 執行；Run workflow 時選 `main` |
| 選了 `automatic` 而 Archive 出現 no devices / 無法產生開發描述檔 | 改用預設的 `archive_signing: adhoc` 重新執行，或在 Devices 註冊一台裝置 |
| 匯出時出現 `…_Managed is unknown` 或權限錯誤 | 確認 key 是 **Team** key、角色是 **Admin**；見下方〈備案〉 |
| 找不到 App 或 Bundle ID | 先完成步驟 2、3；Bundle ID 必須與 `project.yml` 相同 |
| IPA 檢查失敗 | 看錯誤列出的項目；IPA 不會被上傳 |
| 上傳被拒：build number 重複或較小 | 不要重跑舊的執行；按新的 Run workflow，必要時設定 `BUILD_NUMBER_OFFSET` |
| 上傳被拒：SDK / Xcode 太舊 | 需要 Xcode 26 以上；workflow 一開始就會檢查 |
| TestFlight 顯示 Missing Compliance | 在 App Store Connect 回答出口合規問題 |
| 測試者看不到 build | 確認群組有你、已接受邀請；沒開自動發佈時，手動把 build 加入群組 |
| API 存取申請尚未核准 | 等 Apple 核准；在那之前無法產生 Team key |

### 備案：API key 無法使用雲端簽章時

改用手動發佈憑證（`.p12`）與 App Store 描述檔。**這個方案尚未實作**，需要另一個小 PR：讓 workflow 依 GitHub 官方文件把 `.p12` 匯入暫存 keychain，匯出改用手動簽章。

沒有 Mac 時建立私鑰與 CSR：
- Apple 的說明只寫 Mac 的「鑰匙圈存取」。
- CSR 是標準 PKCS #10 格式（Apple TN3161 引用 RFC 2986），可以在 iPad 上用內建 OpenSSL 的 App（例如免費的 a-Shell）執行 `openssl req` 產生。但 Apple **沒有正式說明**支援這個做法。
- 私鑰只在你的 iPad 上產生，轉成 `.p12` 後以 base64 存進 environment secret；不要交給任何人（包括 Claude）。

## 與 Xcode Cloud 的關係

- Xcode Cloud 暫緩。它的第一次 onboarding 仍需要一次在 Mac 上操作 Xcode；GitHub Actions 路線不需要。
- 兩條路線共用同一份已提交的 Xcode 專案與 shared scheme。
- 日後啟用 Xcode Cloud 時，再決定是否保留 GitHub macOS 的發佈 workflow。
- 兩者上傳到同一個 App 時，build number 不可重複；必要時以 `BUILD_NUMBER_OFFSET`，或 Xcode Cloud 的 Next Build Number 錯開。

## 官方來源（查閱日期 2026-09-28）

**Apple**

- App Store Connect API 存取申請、Team key、角色、下載一次：
  - https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/
  - https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api
- Issuer ID / Key ID：https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
- 角色權限（cloud-managed 憑證、發佈描述檔）：https://developer.apple.com/help/account/access/roles/
- Cloud-managed certificates：https://developer.apple.com/help/account/certificates/cloud-managed-certificates/
- xcodebuild 以 API key 在無人操作環境自動簽章；雲端簽章與 Admin 角色：https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes
- `-exportArchive` 以 API key 上傳：https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes
- Xcode 26.1–26.6 release notes：對上傳、exportArchive 沒有變更。
- 上傳方式與「Xcode 26 or later」：
  - https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
  - https://developer.apple.com/news/upcoming-requirements/
- 為何不用 altool：Apple 的 altool 說明頁寫 `--upload-package` 需要 `--bundle-id`，但 macos-26 runner 上 Xcode 26.6 的 `altool --help` 沒有列出這個選項（dry run 實測）。所以上傳改用有官方說明、也能用 API key 的 `xcodebuild -exportArchive`。
- CFBundleVersion 格式：https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
- 版本號與 build number 組合唯一：https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
- 同版本遞增（舊文件）：https://developer.apple.com/library/archive/technotes/tn2420/_index.html
- CSR 建立：https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/
- TN3161：https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates

**GitHub**

- Environments、部署分支（依 `GITHUB_REF` 比對）、required reviewers：https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- `workflow_dispatch` 需在預設分支：https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch
- `run_number` / `run_attempt`：https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- concurrency：https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
- secrets 遮蔽與安全使用：
  - https://docs.github.com/en/actions/reference/security/secure-use
  - https://docs.github.com/en/actions/reference/security/secrets
- 在 macOS runner 使用暫存 keychain：https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- macos-26 runner 的 Xcode 26.6 與公開 repository 免費：
  - https://docs.github.com/en/actions/reference/runners/github-hosted-runners
  - https://github.com/actions/runner-images（`images/macos/macos-26-arm64-Readme.md`）
