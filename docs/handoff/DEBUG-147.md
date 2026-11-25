# DEBUG-147（2026-11-25）

- 派工：協調者（147 發版後例行的除錯）。雲端 Linux，分支 `claude/project-thread-yymq7i`。
- 範圍：146→147（`0ecdedc..628fd6a`，first-parent 40 個合併；`Sources/` +8,475／−4,211 行，GameCore 14 檔 +887 行：決策 969 地圖長大、決策 970 軌距、存檔 112 → 114）。
- GameCore、存檔版本、golden schema、決策號都不動。**沒有找到當機，也沒有要修的 bug。**
- 作者擔心額度（「怕太長浪費額度」），所以這次不在本機重跑 CI 已經跑過的東西（見「沒做的」）。

## 做了什麼

1. **完整 `ci.yml`**（手動，run 45650235089，`628fd6a`）：全綠。14 個 Swift shard、doc-numbers、`warnings-as-errors` 的建置都過；時刻表體檢五個 job 都綠，沒有一條線比預算差（香港東涌綫、東涌＋機場快綫＋迪士尼、文湖線三處比預算好，可在 `CheckupBudgets/` 調低：CIOPT 的事）。機捷簡化仍沒發 13/333、誤點 92，和 HEALTH-146 同一個舊問題（TYMC-QINGPU-FULL）。
2. **full lane**（內層 `ios-build.yml` 45650404544，`628fd6a`）：**四個 job 全綠**：build 88 支（2 略過）、second 38 支（1 略過）、lessons 18 支、iPad 9 支，0 失敗。146 那兩支時好時壞的（`testConstructionHUDAppearsDuringTrackPreview`、iPad 教學 `checkToolIsUncovered`）這次都過。外層 `ios-full-lane.yml` 45650338902 顯示紅，只是派發時 GitHub 回 HTTP 500，作者隨即手動開了上面那次，不是測試失敗。
3. **Xcode 警告**（從 full lane 的 log 數，排掉 `Accessing Environment` 與 `appintentsmetadataprocessor`）：**0 個**。DEBUG-146 修的 `TrainRosterView` 警告確實沒了。
4. **讀新增的程式找當機寫法**（強制解包、`try!`、`as!`、`fatalError`、`precondition`），新的 10 處都安全：
   - `TrackGauge.init(rails:)` 的 `precondition(!rails.isEmpty)`：讀檔走 `init(from:)`，空陣列先丟 `DecodingError`；`init?(code:)` 也先擋空；`merged(with:)` 是兩個非空集合的聯集。壞存檔不會閃退。
   - `Map3DGeometry` 三個 `precondition`（法向量數量）：呼叫端自己組的陣列。
   - `Map3DHongKongLandmarks` 的 `models[false]!`／`models[full]!`：字典固定有 `true`、`false` 兩鍵。
   - `Map3DScenePlatforms` 的 `curved!.min()!`、`laterals[nearest]!`、`best!.gaps.min()!`、`line.map(\.x).min()!`：月台先濾掉少於兩點的；`gaps` 至少有一半的點；`nearest` 只從非 `nil` 的挑。
5. **讀存檔轉換**（`layGauges()`、`growMap(to:)`、`MapExpansion.granted`）：`v113-grown-map.json`、`v114-track-gauge.json` 兩個新樣本由 CI 的 `SavedGameTests` 讀過；舊存檔裡正在跑或停在軌道上的真實車型都會讓軌道照它們的軌距鋪，不會被困住。

## 讀程式看到、沒有驗證的一點（交規劃決定要不要派）

- **舊存檔裡「買了還沒配屬」的真實車型**（146 起車隊總覽可以先買車再配屬，決策 960）：`layGauges()` 只看停在軌道上的車和路線上的車，沒有位置也沒有路線的車不算。所以如果玩家在 146 先買了 700T 或 C381 放著、打算配到自己鋪、上面還沒有真實車型的線，147 讀進來那條線是預設的 1,067 mm，配屬時會被擋（「軌距不合」），要換車型或重鋪軌道。台鐵車、沙盒的標準車、`A`、`B` 不受影響。只是讀程式推出來的，沒有寫測試重現；影響應該很小（要 146 才有的先買後配，加上自鋪的 1,435 線）。

## 沒做的（CI 已經做過，重做只花額度）

- 本機 Linux debug 建置與「這段改過的測試類別」（98 類）：完整 `ci.yml` 在同一個 commit 已經用 `warnings-as-errors` 建好、跑完全部 shard。
- release 建置：HEALTH-147 的事（如果派了）。
- `Accessing Environment<Bool>'s value outside of being installed on a View`：這次 130 次（146 是 147 次），145 就有，DEBUG-146 已記，要在 Xcode 下中斷點才找得到。

## UNVERIFIED

- 實機、Metal、聲音。
- 上面「買了還沒配屬的真實車型」那一點：只讀程式。
