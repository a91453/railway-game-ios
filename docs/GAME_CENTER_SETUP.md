# Game Center 設定步驟（給作者）

> 讀者：作者。照著按就能完成；不需要密碼以外的任何資料交給 session，session 也不會問。
> 背景：決策 396（`docs/decisions/396.md`）。遊戲把每週挑戰的完成天數送上 Game Center 的每週排行榜，38 個成就同步成 Game Center 的成就。

## 順序（重要）

1. **第一個 PR（決策 396 的程式，#1156，已合併）**：遊戲已經會呼叫 Game Center，但 App 裡**還沒有** Game Center 的 entitlement。這時 Game Center 一律登入失敗，遊戲照舊，不跳任何訊息；TestFlight 照常可以發。
2. **作者照下面第 1、2 步打開 Game Center**（Apple Developer 與 App Store Connect；2026-10-24 已完成）。
3. **第二個 PR（#1158）** 才加 entitlement（`com.apple.developer.game-center`）和成就圖。entitlement 只要第 1 步做完就不會擋發版。
4. **作者照第 3、4 步在 GitHub 按一次 Game Center setup workflow**（先 dry run、再 apply；成就要等 #1158 的成就圖進 `main`），送審時照第 5 步勾 Game Center。建好之後的 TestFlight，玩家登入 Game Center 就看得到排行榜和成就。

為什麼要分兩個 PR：App 有 Game Center 的 entitlement，而 App ID 還沒開 Game Center 時，發版時匯出 App Store 版本會因為 provisioning profile 沒有這一項而失敗（Apple 的說明見決策 396）。先設定、再加 entitlement，就不會擋發版。萬一第二個 PR 之後發版失敗，revert 它的 entitlement commit（`431a69f`）就回到第一個 PR 的狀態。

## 第 1 步：App ID 打開 Game Center

1. 打開 <https://developer.apple.com/account>，登入。
2. 左邊選 **Certificates, Identifiers & Profiles** → **Identifiers**。
3. 點 `io.github.a91453.RailwayGame`。
4. 在 **Capabilities** 列表找到 **Game Center**，打勾（多半已經勾了；勾了就不用動）。
5. 右上角 **Save**。跳出確認視窗就按 **Confirm**。

## 第 2 步：App Store Connect 打開 Game Center

1. 打開 <https://appstoreconnect.apple.com>，**我的 App** → 「Along the Line」。
2. 上方分頁選 **Features（功能）**（有的帳號叫 **Services（服務）**），左邊選 **Game Center**。
3. 第一次會問要不要用 Game Center：選 **Enable for Single Game（只用在這個遊戲）**。

## 第 3、4 步：用 GitHub 一次建好排行榜和 38 個成就

不用一個一個在 App Store Connect 填。GitHub 上的「Game Center setup」會用發 TestFlight 那把 App Store Connect API key，照下面的表建好每週排行榜（含兩種語言）和 38 個成就（含兩種語言與圖）。

### 先確認 key 的權限（只要看一次）

建 Game Center 的項目，key 的角色要是 **Admin** 或 **App Manager**。發 TestFlight 那把 key 當初建的是 Admin（`docs/TESTFLIGHT_GITHUB_ACTIONS.md`），多半不用改。要確認的話：

1. 打開 <https://appstoreconnect.apple.com>，上方選 **使用者和存取權限（Users and Access）**。
2. 上方分頁選 **整合（Integrations）**，左邊選 **App Store Connect API**，再選 **團隊金鑰（Team Keys）**。
3. 找名稱是發 TestFlight 用的那把（例如 `GitHub Actions TestFlight`），看 **存取權限（Access）** 那一欄：寫 **Admin** 或 **App Manager** 就可以。

只看角色就好：不用下載、複製或貼上任何 key，也不用把任何東西給 session。

順便確認一次：GitHub 的 repository → **Settings** → **Environments** → **testflight** → **Deployment branches and tags**，應該只有 `main`。真正擋住其他分支拿到 key 的是這個設定（發 TestFlight 也靠它），不是 workflow 檔裡的那一行。

### 按 Run workflow

1. 打開 <https://github.com/a91453/railway-game-ios/actions>，左邊選 **Game Center setup**。
2. 右邊按 **Run workflow**：
   - **Use workflow from**：`main`（只能在 `main` 跑，選別的分支會直接失敗）。
   - **mode**：先選 **dry-run**。
   - **only**：**all**。
   - 按綠色的 **Run workflow**。
3. 等它跑完（一兩分鐘），點進去，看 **Summary** 的清單。dry run 只讀 App Store Connect，不會建任何東西。清單長這樣：
   - `排行榜 weekly.days.v2：新建：……`，下面兩行 `加語言 en-US`、`加語言 zh-Hant`。
   - `成就 achievement.firstFare：新建：First Fare，5 點，不隱藏，不可重複`，下面兩行語言、兩行上傳圖。
   - 最上面一行是總數：第一次跑應該是「新的項目 39 個、語言 78 個、圖 76 張」。
4. 清單沒問題，再按一次 **Run workflow**，這次 **mode** 選 **apply**。它會先印出同一份清單，再一個一個建，最後寫「全部建好了」。

**排行榜和成就上線之後就刪不掉了**（隨 App 版本送審通過之後），所以 apply 之前一定先看 dry run 的清單。apply 只是建立，還沒上線：在第 5 步送審之前，都可以在 App Store Connect 自己改或刪。

### 跑第二次也安全

- 已經有的 ID 一律跳過，**不刪、不改** App Store Connect 已經有的任何東西。
- 已經有的項目跟下面的表不一樣時，清單會寫「注意（不會改）：……」，要改請自己在 App Store Connect 改。
- 中途失敗（例如網路斷了）：前面建好的會留著，再跑一次 apply 只會補還沒建的排行榜、成就和語言。
- **例外是傳到一半的成就圖**：清單若寫「注意（不會改）：en-US: its image is AWAITING_UPLOAD; not touched」之類，表示那張圖的位置建了、檔案沒傳完。工具不會刪它，也不會補傳。到 App Store Connect 打開那個成就、那個語言，把圖刪掉，再跑一次 apply，就會重新上傳。

### 成就圖還沒進 `main` 時

App Store Connect 的成就要有圖。38 張圖在成就圖的 PR（#1158）裡；它合併之前，清單會寫「先不建，the image … is not in the repository yet」，只建排行榜。#1158 合併之後再跑一次（dry run、再 apply），就會建成就。

### 權限不夠或 key 不對

| 看到的錯誤（在失敗的步驟裡） | 原因 | 怎麼辦 |
| --- | --- | --- |
| `HTTP 403 (This request is forbidden for security reasons: The API key in use does not allow this request)`，後面接「這把 key 的角色不能建 Game Center 的項目」 | key 的角色不是 Admin 或 App Manager | 照上面「先確認 key 的權限」看角色。角色建好後不能改，要另產生一把 Admin 的 key，照 `docs/TESTFLIGHT_GITHUB_ACTIONS.md` 換掉 `testflight` environment 裡的 secrets（這會換掉發 TestFlight 用的 key） |
| `HTTP 401 (Authentication credentials are missing or invalid…)` | key 被撤銷，或 secrets 填錯 | 發 TestFlight 也會一起壞，照 `docs/TESTFLIGHT_GITHUB_ACTIONS.md` 檢查 |
| `this app has no Game Center in App Store Connect yet` | 第 2 步還沒做 | 做第 2 步，再跑 |
| `ASC_KEY_ID is not set.` 之類 | `testflight` environment 少了 secret | 照 `docs/TESTFLIGHT_GITHUB_ACTIONS.md` 補 |
| 清單寫 `its image is AWAITING_UPLOAD`（或 `FAILED`）`; not touched` | 上次那張成就圖傳到一半 | 在 App Store Connect 那個成就的那個語言把圖刪掉，再跑 apply |
| `HTTP 409` 或其他 `HTTP 4xx`，在排行榜那一項 | App Store Connect 不收排行榜的某個欄位 | 告訴遊戲規劃 session 那一行錯誤。成就可以先建：**only** 選 **achievements** 再跑；排行榜也可以照下面的表在 App Store Connect 手動建 |

### 會建的內容

這三張表和工具讀的是同一份資料：`docs/game-center/game-center.json`。要改內容請改那個檔，再執行 `python3 tools/game-center-setup/game_center_setup.py --write-doc` 更新這裡（CI 會檢查兩邊一樣）。

**每週排行榜**（Recurring Leaderboard）：

<!-- leaderboard: generated from docs/game-center/game-center.json by tools/game-center-setup/game_center_setup.py --write-doc; do not edit by hand -->
| 欄位 | 內容 |
| --- | --- |
| Reference Name | `Weekly challenge days v2` |
| Leaderboard ID | `weekly.days.v2` |
| Score Format Type | **Integer** |
| Submission Type | **Best Score** |
| Sort Order | **Low to High**（天數越少越前面） |
| Score Range | 最小 `1`、最大 `1080`（最長的挑戰是 3 年） |
| Start Date | 執行那天之後的**下一個星期一 00:00（台灣時間）**（UTC 是前一天星期日 16:00） |
| Duration | **1 Week** |
| Restarts Every | **1 Week** |
<!-- end leaderboard -->

排行榜的兩種語言：

<!-- leaderboard-localizations: generated from docs/game-center/game-center.json by tools/game-center-setup/game_center_setup.py --write-doc; do not edit by hand -->
| 語言 | Display Name | Score Format | Formatter Suffix（單數／複數） |
| --- | --- | --- | --- |
| English (U.S.) | `Weekly Challenge` | Integer | ` day` ／ ` days` |
| Chinese (Traditional) | `每週挑戰` | Integer | ` 天` ／ ` 天` |
<!-- end leaderboard-localizations -->

排行榜的圖不放。

**之後挑戰的目標改了**（程式裡的 `ChallengeRecords.rulesVersion` 換版本）：要另建一個新的排行榜（ID 例如 `weekly.days.v3`）。session 會在那個 PR 把它加進 `game-center.json`，作者再跑一次這個 workflow。舊的不用刪。

**38 個成就**：每一個都是 **Hidden** No（遊戲裡的成就清單本來就全部看得到）、**Achievable More Than Once** No；點數共 800 點，Game Center 上限 1,000，留給之後的成就。兩種語言的 **Pre-earned Description** 與 **Earned Description** 都是表裡的說明，**Image** 是 `docs/game-center/achievements/<ID>.png`。

<!-- achievements: generated from docs/game-center/game-center.json by tools/game-center-setup/game_center_setup.py --write-doc; do not edit by hand -->
| # | ID | 點數 | 隱藏 | 中文名稱 | 中文說明 | 英文名稱 | 英文說明 |
| --: | --- | --: | --- | --- | --- | --- | --- |
| 1 | `achievement.firstFare` | 5 | 否 | 第一筆票收 | 收到第一位旅客的車資 | First Fare | Take a passenger's first fare |
| 2 | `achievement.riders1k` | 10 | 否 | 月台常客 | 單日旅客 1,000 人次 | Regulars | 1,000 riders in a day |
| 3 | `achievement.riders10k` | 20 | 否 | 鐵道魂 | 單日旅客 10,000 人次 | Railway Soul | 10,000 riders in a day |
| 4 | `achievement.riders100k` | 40 | 否 | 尖峰時刻 | 單日旅客 100,000 人次 | Rush Hour | 100,000 riders in a day |
| 5 | `achievement.riders1m` | 80 | 否 | 百萬運量 | 單日旅客 1,000,000 人次 | A Million a Day | 1,000,000 riders in a day |
| 6 | `achievement.track10` | 5 | 否 | 十公里 | 路網長度 10 km | Ten Kilometres | Build 10 km of track |
| 7 | `achievement.track50` | 15 | 否 | 跨越縣境 | 路網長度 50 km | Across the County | Build 50 km of track |
| 8 | `achievement.track200` | 30 | 否 | 千里鐵道 | 路網長度 200 km | A Thousand Li | Build 200 km of track |
| 9 | `achievement.track1000` | 80 | 否 | 千公里俱樂部 | 路網長度 1,000 km | The Thousand-Kilometre Club | Build 1,000 km of track |
| 10 | `achievement.longLine` | 25 | 否 | 一氣呵成 | 一條 50 km 以上的路線（站間直線） | In One Go | A line 50 km long, station to station |
| 11 | `achievement.stoppingLine` | 15 | 否 | 站站是風景 | 一條停靠 20 站以上的路線 | Every Station Is a View | A line calling at 20 stations |
| 12 | `achievement.earlyBird` | 10 | 否 | 早鳥 | 一條 05:00 前就發出首班車的路線 | Early Bird | A line whose first train leaves before 05:00 |
| 13 | `achievement.nightOwl` | 10 | 否 | 夜行者 | 一條跨午夜營運的路線 | Night Owl | A line that runs past midnight |
| 14 | `achievement.ringLine` | 15 | 否 | 繞圈圈 | 第一條營運中的環狀線 | Round and Round | Run a ring line |
| 15 | `achievement.hub` | 15 | 否 | 轉乘樞紐 | 三條路線共用一站 | Interchange | Three lines calling at one station |
| 16 | `achievement.highSpeed` | 15 | 否 | 子彈列車 | 一列高鐵性能的列車 | Bullet Train | Run a train of the High Speed Rail's performance |
| 17 | `achievement.fleet20` | 15 | 否 | 車隊成形 | 擁有 20 列車 | Fleet | Own 20 trains |
| 18 | `achievement.stations25` | 10 | 否 | 車站巡禮 | 車站 25 座 | Station Tour | Build 25 stations |
| 19 | `achievement.stations50` | 20 | 否 | 五十站 | 車站 50 座 | Fifty Stations | Build 50 stations |
| 20 | `achievement.stations100` | 40 | 否 | 百站達成 | 車站 100 座 | A Hundred Stations | Build 100 stations |
| 21 | `achievement.firstBuilding` | 10 | 否 | 建商起步 | 第一棟公司建物 | Developer | Put up the company's first building |
| 22 | `achievement.firstFreight` | 10 | 否 | 第一噸貨 | 第一次送達貨物 | First Tonne | Deliver freight |
| 23 | `achievement.firstTile` | 10 | 否 | 開疆闢土 | 買下第一格地圖 | New Ground | Buy a tile of the map |
| 24 | `achievement.tower` | 15 | 否 | 站前大樓 | 車站 800 公尺內出現高樓 | Station Tower | A high-rise within 800 m of a station |
| 25 | `achievement.typhoonSeason` | 15 | 否 | 安然度颱 | 颱風季結束時沒有負債 | Weathered the Storms | End the typhoon season with no debt |
| 26 | `achievement.challengeGold` | 40 | 否 | 挑戰金牌 | 以金牌完成一項挑戰 | Gold Medal | Complete a challenge with gold |
| 27 | `achievement.pingxi` | 30 | 否 | 平溪線 | 完成平溪線劇本 | Pingxi Line | Complete the Pingxi challenge |
| 28 | `achievement.liuMingchuan` | 30 | 否 | 劉銘傳鐵路 | 完成劉銘傳劇本 | Liu Mingchuan's Railway | Complete the Liu Mingchuan challenge |
| 29 | `achievement.firstTourists` | 10 | 否 | 一日遊 | 第一次把觀光客載到景點 | Day Trippers | Bring tourists to an attraction |
| 30 | `achievement.tourists100k` | 25 | 否 | 觀光旺季 | 一年 100,000 位觀光客 | Tourist Season | 100,000 tourists in a year |
| 31 | `achievement.souvenirShop` | 15 | 否 | 名產名店 | 一間名產店升到最高級 | Local Specialties | A souvenir shop at its highest level |
| 32 | `achievement.fiveStars` | 25 | 否 | 五星景點 | 一處五星的景點 | Five Stars | An attraction rated five stars |
| 33 | `achievement.firstSubsidiary` | 10 | 否 | 多角經營 | 開第一間百貨公司、飯店或遊樂園 | In Business | Open a department store, hotel or amusement park |
| 34 | `achievement.allBusinesses` | 25 | 否 | 企業集團 | 百貨公司、飯店、遊樂園各一間 | Group | Run a department store, a hotel and an amusement park |
| 35 | `achievement.businessProfit` | 25 | 否 | 生意興隆 | 一間事業開業以來賺進 $1,000,000 | Paying Business | A business that has made $1,000,000 since it opened |
| 36 | `achievement.mixedFleet` | 10 | 否 | 車種齊全 | 車隊有三種以上車種 | Mixed Fleet | Trains of three types |
| 37 | `achievement.longTrain` | 10 | 否 | 長編組 | 一列 10 節以上的列車 | Long Train | A train of 10 cars or more |
| 38 | `achievement.fleetInvestment` | 10 | 否 | 車隊投資 | 車隊的購置成本達 $5,000,000 | Rolling Stock Investor | Spend $5,000,000 on trains |
<!-- end achievements -->

## 第 5 步：送審的版本加上 Game Center

只有送 App Store 審查時要做；內部 TestFlight 不用（TestFlight 的測試者在排行榜和成就還沒上線前就能用）。

1. App Store Connect → 「Along the Line」→ **App Store** 分頁 → 要送審的版本。
2. 往下捲到 **Game Center**，打勾。
3. 按 **＋** 把 `weekly.days.v2` 和 38 個成就都加進去，**Done**，再 **Save**。

## 隱私標示

不用改。遊戲不讀玩家的 Game Center 名字或 ID，也不把任何資料傳給作者或第三方；分數和成就只送到 Apple 的 Game Center，Apple 的說明是「Apple 蒐集的資料不由開發者揭露」。App Privacy 維持「不蒐集資料」（決策 396、`docs/XCODE_CLOUD_ONBOARDING.md` 的「隱私」）。

## 設好之後

第 3、4 步的 apply 跑完後，在遊戲規劃 session 說「Game Center 設好了」。排行榜與成就建好之後才發下一版（entitlement 與成就圖在 #1158），照平常的發版流程。
