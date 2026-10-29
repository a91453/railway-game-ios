# 公測前抓蟲：貨運、挑戰與劇本、分享與 Game Center（BH5，2026-10-30）

派工單 BH5（遊戲規劃第 32 任派），分支 `claude/bughunt-freight-challenges`，對照 `main` 9fb305d。
存檔版本、決策號、golden 都不動。

**結論：沒找到 P1。** P2 一個、P3 八個，都寫在下面，公測後由規劃照順序派。

## 1. 怎麼找的

在 Linux 上用無頭方式照玩家的順序玩，邊玩邊存讀。下面的探針測試只在本機跑，沒有提交。

| 玩了什麼 | 怎麼玩 | 結果 |
| --- | --- | --- |
| 挑戰在午夜結束，前後每一秒存讀 | 一個「權益 ≥ 1」會過關的劇本、一個會因期限失敗的劇本，各在 `x1`、`normal`、`fast` 三種速度下，每 `advance(ticks: 10)` 存讀一次 `SavedGame` | 6 種組合都能讀回，而且相等。VERIFIED（Linux） |
| 三鎮連線、每週挑戰（2965 週）、鐵道大亨 | `PolicyPlayer` 的 `.challenge(.linked)` 玩 20 天，每天存讀一次 | 都能讀回。三鎮第 4 天連通；第 20 天每日運量 84,716。目標文字、狀態文字都對。VERIFIED |
| 每週挑戰換週 | 台灣時間 2026-11-02 00:00 前後一秒；第 0、2961、999,999 週；`weekly.-1`、`weekly.abc` | 週次、`daysLeft`、輪替（2964 大亨、2965 三鎮）都對；壞的 ID 回 `nil`。VERIFIED |
| 收到別人的檔案 | `SaveFixtures/` 79 個版本的存檔，各自包成現在的存檔檔案，再「開新的一局」；也試空檔、`{}`、`null`、亂碼、截斷的檔 | 壞檔都被擋下，不會當掉。19 個舊版存檔開不了新局（P3-1）；v50 帶過來朋友還沒領的補助（P2-1）。VERIFIED |
| 既有測試 | `ChallengeTests`、`BranchLineChallengeTests`、`LiuMingchuanChallengeTests`、`WeeklyChallengeTests`、`SharedNetworkTests`、`GameCenterMappingTests`、`FreightSessionTests`、`PingxiChallengeTests`、`ChallengeStory*`、`DemoModeTests`、`DemoRealLinesTests`、`TRADemoTests`、`HighSpeedDemoTests`（GamePresentation 共 122 個，跳過 1 個），以及 GameCore 的 `FreightTests` 24 個、`GoalsTests` 15 個 | 全部通過。VERIFIED（Linux，`main` 9fb305d） |

另外讀了以下程式路徑：

- 貨運與建材：`Freight.swift`、`LandDemand` 的建材、`FreightText`、`Map3DWorksKitFreight`、缺料泡泡（`MapAlerts`）。
- Game Center：`GameCenterLink`、`GameCenterMapping`、`GameCenterReport`、`GameCenterLedger`。
- 共享路網（決策 409）：`SharedNetwork`、`SharedNetworkViews`、`GameLauncher` 的接收與 `play(_:as:)`、Info.plist 的檔案類型。

10/25 之後，這些檔案只有 `MapAlerts`（泡泡）和 `GameLauncher`（讀道路搬離主執行緒）有改動，彼此沒有打架。

確認沒問題的地方：

- 運費不會溢位；收入只記一次，會進日帳和年帳。
- 建材不會變負的。沒有貨運時，城鎮照樣長，只是比較慢，不會卡住。
- 刪站、賣車時，貨物會一起清掉。
- 沒登入 Game Center 時什麼都不送；登入失敗、按取消都不會當掉。
- 成就百分比在 0–100 之間；ID 和 `docs/GAME_CENTER_SETUP.md` 一致。
- 「只看」不會寫到任何存檔。

**沒驗證的**（UNVERIFIED，要實機）：

- GameKit 的實際行為：登入畫面、換帳號。
- iOS 把收到的檔案放在哪裡。
- 別的 sheet 開著時，「朋友傳來的路網」能不能跳出來。

## 2. P2

### P2-1 從朋友的路網開新局，會領到朋友還沒領的錢

- **在哪**：`Sources/GamePresentation/SharedNetwork.swift` 的 `newGameWorld(balance:)`（約 110–120 行）。
  - 它清掉了 `economy` 和 `accounts` 的錢，但 `world` 裡還留著三樣東西：
    - `cityRequests`：`owed`（已達成、下個月 1 日才付的補助）、`paid`、`trust`（星等，決定能接幾個委託）、進行中的委託。
    - `freight.pendingRevenue`：這一小時已經賺到、還沒入帳的貨運費。
    - `lineAccounts`：朋友各路線的收支歷史。
- **怎麼重現**：
  1. 拿 `SaveFixtures/v50-city-requests.json` 包成存檔檔案。
  2. 用 `SharedNetwork(data:).newGameWorld()` 開新局。
  3. `world.cityRequests?.owed` 是 20,000,000（$200,000）。下個月 1 日，這筆錢會記成收到的補助。
  4. 玩家的版本：朋友在月底達成市府委託後分享檔案，收到的人選「從這張路網開新的一局」，下個月 1 日就領到朋友的補助，星等也是朋友的。
- **建議修法**：在 `newGameWorld` 的 JSON 上一起處理：
  - `world["cityRequests"]` 設成 `nil`，或者只把 `owed`、`paid` 歸零、`trust` 設回 `startingTrust`、清掉 `active` 和 `results`。
  - `world["freight"]["pendingRevenue"]` 刪掉（解碼時預設是 0）。
  - `world["lineAccounts"]` 設成 `nil`。
  - 在 `SharedNetworkTests.testANewGameKeepsTheNetworkAndStartsTheMoneyAgain` 加上這三項的斷言。
  - 只動 GamePresentation，不動 GameCore 和存檔版本。
- **五面向**：
  - 玩家：錢應該從新公司重新算，這也是選項說明寫的。白拿的錢不大，但星等和委託會跟著過來，讓人摸不著頭緒。
  - 鐵道迷：無。
  - 開發：改三個 JSON 鍵，再加測試，風險很低。
  - 美術：無。
  - 音樂：無。

## 3. P3

### P3-1 沒有帳的世界開新局時，被說成「存檔已損壞」

- **在哪**：`SharedNetwork.newGameWorld`。它用 `guard var accounts = world["accounts"] as? [String: Any] else { throw .damaged }` 取帳。可是 GameCore 在帳還是全新的時候（`CompanyAccounts.isPristine`：自由模式，什麼都沒買過）根本不寫 `accounts`。
- **怎麼重現**：`SaveFixtures` 有 19 個版本開不了新局，例如 v9、v10、v37、v62、v70。它們都沒有 `accounts`，結果是 `SaveError.damaged`，玩家看到「這個存檔已損壞，無法讀取。」。用現在的版本照正常方式玩出來的存檔（經營模式，或自由模式下蓋過東西）都能開。所以只有很舊的自由模式存檔，或什麼都沒蓋過的空地圖會碰到。
- **建議修法**：`world["accounts"]` 沒有時，當成 `[:]` 處理，不要丟出錯誤。
- **五面向**：
  - 玩家：好好的檔案被說壞掉，會讓人以為是自己傳錯檔。
  - 鐵道迷：無。
  - 開發：改一行，並用一個沒有 `accounts` 的檔案做測試。
  - 美術：無。
  - 音樂：無。

### P3-2 收到沒有道路資料的舊檔時，可能卡住幾秒

- **在哪**：`GameLauncher.play(_:as:)`（約 1531–1558 行）。兩個選項都直接呼叫 `begin`，沒有先在背景讀道路（`open(reading:world:then:)`，決策 419、473）。所以 `readLandRoundStations(roads: nil)` 會在主執行緒上讀道路。按下選項時也沒有檢查 `isLoadingSave`。
- **怎麼重現**（推論，沒有在 Linux 量時間）：拿一個有道路之前的版本匯出的實景地圖檔案，開啟後選「只看」或「開新的一局」。決策 419 量過，這種檔案要讀「幾秒」的道路。這段時間畫面會停住，也沒有載入畫面。
- **建議修法**：把收到的世界交給 `open(reading:world:then:)`，或者在背景工作裡先算好 `GameSession.roadsReadAhead`，再傳給 `begin(roads:)`。
- **五面向**：
  - 玩家：停住幾秒，會以為 App 當了。
  - 鐵道迷：無。
  - 開發：照著其他讀檔的路徑做。
  - 美術：載入畫面照現有的樣子。
  - 音樂：無。

### P3-3 換 Game Center 帳號後，新帳號收不到之前的成就

- **在哪**：`RailwayGameApp/App/GameCenterLink.swift:43`。換帳號之後 `isSignedIn` 還是 `true`，`guard signedIn != isSignedIn` 直接返回，帳本（ledger）沒有重設。
- **怎麼重現**：在「設定」裡換 Game Center 帳號，再回到 App。要等重開 App，新帳號才會收到全部的成就和成績。需要實機，UNVERIFIED。
- **建議修法**：另外記下 `GKLocalPlayer.local.gamePlayerID`。它變了就重設帳本，再全部送一次。
- **五面向**：
  - 玩家：少數換帳號的人會短暫少了成就。
  - 鐵道迷：無。
  - 開發：只改 App 層幾行。
  - 美術：無。
  - 音樂：無。

### P3-4 Game Center 送失敗時不會重送

- **在哪**：`GameCenterLink.send`（約 52–67 行）。`ledger.changes(in:)` 一呼叫，就當成已經送出；`GKAchievement.report` 和 `GKLeaderboard.submitScore` 的錯誤都被忽略。
- **怎麼重現**：沒有網路，或排行榜在 App Store Connect 還沒上線時達成成就。之後要等重開 App，或成績更好時才會再送。
- **建議修法**：先用帳本的複本算出要送的內容，GameKit 回報沒有錯誤之後，才寫回 `ledger`。
- **五面向**：
  - 玩家：成就偶爾晚出現。
  - 鐵道迷：無。
  - 開發：只改 App 層，沒辦法在 Linux 驗證。
  - 美術：無。
  - 音樂：無。

### P3-5 跨週才完成的每週挑戰不會上排行榜

- **在哪**：`GameCenterReport.init(achievements:facts:scope:challenges:at:)` 只送「現在這一週」的 `weekly.<week>` 成績。上週開始、這週才完成的挑戰，成績記在上週的 ID 下，永遠不會送出。可是 `GameCenterText.footer` 說「每週挑戰的完成天數會上 Game Center 的每週排行榜」。
- **建議修法**：Game Center 的週期排行榜只收當期成績，所以不改送法。改成：在挑戰卡或狀態列，對已經過週的每週挑戰說「這一局已不在本週排行榜」；或者改 footer 的字，說要在當週完成。
- **五面向**：
  - 玩家：週日晚上玩到週一才完成，會以為成績沒送出去。
  - 鐵道迷：無。
  - 開發：只改文字或加一行狀態。
  - 美術：無。
  - 音樂：無。

### P3-6 建材委託把倉庫裝不下、丟掉的噸數也算進去

- **在哪**：`Sources/GameCore/Freight/Freight.swift:673-675`。卸下建材時，用整批的 `group.tons` 計算市府建材委託的進度。可是 `storeMaterials` 受 5,000 t 上限限制，可能只存下一部分。
- **怎麼重現**：接下建材委託，等該站存到接近 5,000 t，再送一整列建材。委託照樣算全額完成。委託只會發給缺料的站，所以很少碰到。
- **建議修法**：改成 `let kept = state.storeMaterials(...)`，再用 `countRequestMaterials(kept, at:)`。這是 GameCore 的規則，要改就要照 golden 與 replay 的規矩。
- **五面向**：
  - 玩家：幾乎碰不到。
  - 鐵道迷：送到卻丟掉的貨不該算數。
  - 開發：改一行，但動到 GameCore。
  - 美術：無。
  - 音樂：無。

### P3-7 建材委託沒說要先蓋貨運場

- **在哪**：`Sources/GamePresentation/RequestsText.swift:181-183` 寫「用貨運列車送 N t 到那裡」。可是只有有貨運場的站才會卸貨（`Freight.swift:662`）。
- **怎麼重現**：接下委託，讓貨運線經過那一站，但不在那裡蓋貨運場。進度到期限都是 0。
- **建議修法**：兩種語言都加上「先在那一站蓋貨運場」。站長建議（`StationMasterAdvice.swift:574`）已經這樣寫了。
- **五面向**：
  - 玩家：照著字做卻失敗，會很挫折。
  - 鐵道迷：貨運要有貨場，本來就是真的。
  - 開發：只改字串。
  - 美術：無。
  - 音樂：無。

### P3-8 只停一個貨運場的貨運線會一直滿載，卻沒有提示

- **在哪**：只要有任何一個貨運場，就能把路線改成貨運線（`freightYardFirstText`）。列車在那個貨運場裝貨，但起點就是這一站的貨不會在這裡卸下（`Freight.swift:667`），所以列車會一直滿載，多出來的貨被丟掉。
- **怎麼重現**：只蓋一個貨運場，把 A–B 線改成貨運線並放一列車。路線上永遠顯示「載運 160 t / 160 t」。
- **建議修法**：貨運線停靠的貨運場少於兩個時，路線面板加一行提示。
- **五面向**：
  - 玩家：看不出哪裡錯。
  - 鐵道迷：貨要有去處。
  - 開發：只加一行文字。
  - 美術：照現有提示列的樣式。
  - 音樂：無。

## 4. 建議的順序

1. P2-1：只改 GamePresentation，公測後第一個修。
2. P3-1、P3-2：都在分享這條路上，可以和 P2-1 同一個 PR。
3. P3-7：只改字。
4. P3-8、P3-5：提示和文字。
5. P3-3、P3-4：App 層的 GameKit，要實機驗。
6. P3-6：GameCore，排在最後。
