# Game Center 設定步驟（給作者）

> 讀者：作者。照著按就能完成；不需要密碼以外的任何資料交給 session，session 也不會問。
> 背景：決策 396（`docs/decisions/396.md`）。遊戲把每週挑戰的完成天數送上 Game Center 的每週排行榜，38 個成就同步成 Game Center 的成就。

## 順序（重要）

1. **第一個 PR（決策 396 的程式，#1156，已合併）**：遊戲已經會呼叫 Game Center，但 App 裡**還沒有** Game Center 的 entitlement。這時 Game Center 一律登入失敗，遊戲照舊，不跳任何訊息；TestFlight 照常可以發。
2. **作者照下面第 1、2 步打開 Game Center**（Apple Developer 與 App Store Connect；2026-10-24 已完成）。
3. **第二個 PR（#1158）** 才加 entitlement（`com.apple.developer.game-center`）和成就圖。entitlement 只要第 1 步做完就不會擋發版。
4. 作者照第 3–5 步建排行榜與成就、送審時勾 Game Center。建好之後的 TestFlight，玩家登入 Game Center 就看得到排行榜和成就。

為什麼要分兩個 PR：App 有 Game Center 的 entitlement，而 App ID 還沒開 Game Center 時，發版時匯出 App Store 版本會因為 provisioning profile 沒有這一項而失敗（Apple 的說明見決策 396）。先設定、再加 entitlement，就不會擋發版。萬一第二個 PR 之後發版失敗，把那個 PR revert 就回到第 1 步的狀態。

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

## 第 3 步：建立每週排行榜（recurring leaderboard）

在 Game Center 頁面的 **Leaderboards** 旁按 **＋**，選 **Recurring Leaderboard**，照下表填：

| 欄位 | 填什麼 |
| --- | --- |
| Reference Name | `Weekly challenge days v2` |
| Leaderboard ID | `weekly.days.v2` |
| Score Format Type | **Integer** |
| Submission Type | **Best Score** |
| Sort Order | **Low to High**（天數越少越前面） |
| Score Range | 最小 `1`、最大 `1080`（最長的挑戰是 3 年） |
| Start Date | 設定那天之後的**下一個星期一 00:00（台灣時間）**。畫面若是 UTC，就填**前一天（星期日）16:00** |
| Duration | **1 Week** |
| Restarts Every | **1 Week** |

按 **Save**，然後在 **Leaderboard Localization** 按 **＋** 加兩種語言：

| 語言 | Display Name | Score Format | Formatter Suffix（單數／複數） |
| --- | --- | --- | --- |
| English (U.S.) | `Weekly Challenge` | Integer | ` day` ／ ` days` |
| Chinese (Traditional) | `每週挑戰` | Integer | ` 天` ／ ` 天` |

排行榜的圖可以不放（之後第二個 PR 會附一張，想放再放）。

**之後挑戰的目標改了**（程式裡的 `ChallengeRecords.rulesVersion` 換版本）：要另建一個新的排行榜（ID 例如 `weekly.days.v3`），session 會在那個 PR 裡寫好。舊的不用刪。

## 第 4 步：建立 38 個成就

圖：38 張 1024×1024 的成就圖在 `docs/game-center/achievements/`（第二個 PR，#1158；檔名就是成就 ID）。App Store Connect 要圖才能存語言，所以這一步等 #1158 合併再做最方便。

每一個成就：在 **Achievements** 旁按 **＋**，填：

- **Reference Name**：下表的英文名稱
- **Achievement ID**：下表的 ID
- **Point Value**：下表的點數（38 個共 800 點，Game Center 上限 1,000，留給之後的成就）
- **Hidden**：No（遊戲裡的成就清單本來就全部看得到）
- **Achievable More Than Once**：No

按 **Save**，再在 **Achievement Localization** 按 **＋** 加兩種語言：

- **Title**：下表的名稱
- **Pre-earned Description** 與 **Earned Description**：都填下表的說明
- **Image**：`docs/game-center/achievements/<ID>.png`

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

## 第 5 步：送審的版本加上 Game Center

只有送 App Store 審查時要做；內部 TestFlight 不用（TestFlight 的測試者在排行榜和成就還沒上線前就能用）。

1. App Store Connect → 「Along the Line」→ **App Store** 分頁 → 要送審的版本。
2. 往下捲到 **Game Center**，打勾。
3. 按 **＋** 把 `weekly.days.v2` 和 38 個成就都加進去，**Done**，再 **Save**。

## 隱私標示

不用改。遊戲不讀玩家的 Game Center 名字或 ID，也不把任何資料傳給作者或第三方；分數和成就只送到 Apple 的 Game Center，Apple 的說明是「Apple 蒐集的資料不由開發者揭露」。App Privacy 維持「不蒐集資料」（決策 396、`docs/XCODE_CLOUD_ONBOARDING.md` 的「隱私」）。

## 設好之後

在遊戲規劃 session 說「Game Center 設好了」。第二個 PR（entitlement 與成就圖）合併後，照平常的發版流程發下一版。
