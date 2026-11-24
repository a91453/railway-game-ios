# DEBUG-146（2026-11-24）

- 派工：協調者（146 發版後例行第 2 件）。雲端 Linux，分支 `claude/project-thread-k1mfku`。
- 範圍：145→146（`fcaa3f0..0ecdedc`）。REVIEW-L34（#2649）、HEALTH-146、CIOPT-15 是別串；TRAIN-MODEL-UNIFY（#2647／#2648）沒碰。
- GameCore、存檔版本、golden schema、決策號都不動。
- **沒有找到當機。** 修了一個 Xcode 編譯警告；full lane 兩支紅都不是當機（crash report 0 份），交規劃決定派不派。

## 做了什麼

1. **Linux debug 建置**（`swift build --build-tests`，Swift 6.4.0，4 核）：`0ecdedc` 從頭 9 分 36 秒，**0 個警告**。
2. **這個範圍動到的測試**：`fcaa3f0..0ecdedc` 新增或改過的測試檔裡的 51 個類別（GameCore 7、GamePresentation 44），`swift test --skip-build --parallel`，**460 支全過，沒有當機、沒有失敗**（18 分 58 秒）。
3. **讀新增的程式找當機寫法**：`Sources/` 這次新增的約 5,800 行裡，**沒有新的**強制解包、`try!`、`as!`、`fatalError`、`precondition`。`Map3DGuideway.supports` 的 `Int((length / spacing).rounded())` 除數是常數支柱間距；`RealLineShortBridge` 的 `Int(point.y / Land.cellLength)` 是整數座標。
4. **full lane**（內層 `ios-build.yml` 45416414975，`0ecdedc`）：second、lessons 綠，build 與 iPad 兩個 job 紅，**crash report 都是 0 份**：
   - build job：`MapInteractionTests.testConstructionHUDAppearsDuringTrackPreview`（第 919 行），鋪軌預覽等不到「map.constructionHUD」。印出的畫面樹裡鋪軌工具是選中的、地圖「Nothing selected」、**沒有 `details.card`**，兩次各點兩下都沒選到起點。這支在 `559162f`、`2816b43`、`0ecdedc` 紅，在 `fcaa3f0` 綠：**不是 #2639 帶來的**（`2816b43` 在它之前就紅），但最近四次紅三次，已經不能當偶發。交接說「再紅就當 bug 派」，請規劃派。
   - iPad job：`TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds`，在 `checkToolIsUncovered` 第 672 行（`dock.build` 等 10 秒沒出現）。`559162f` 同一行紅過另一支（`testTraditionalChineseTutorialNavigation`），`fcaa3f0` 綠：同一個等待點時好時壞。
5. **Xcode 的警告**（從 full lane 的 log 數）：
   - 編譯警告只有一種：`TrainRosterView.swift` `TrainRosterBuiltRows` 的 `@Sendable` 列閉包「capture of non-Sendable type 'ID.Type'」（`#SendableMetatypes`），145 就有。**修了**：`ID` 加上 `Sendable`（四個呼叫的 ID 都是 `TrainID`／`LineID`，本來就 `Sendable`）。只在 Xcode 編得到，Linux 驗不了，看這個 PR 的 iOS 檢查。
   - 執行期警告「Accessing Environment<Bool>'s value outside of being installed on a View」：每支 UI 測試進遊戲畫面時印一次（這次 147 次，145 的 full lane 129 次），145 就有，不是這版帶來的。讀到的是預設值、不會更新；Bool 環境值多半是「減少動態效果」（43 處），玩家開了減少動態效果時某個地方可能照樣動。用靜態掃描（找非 View 型別裡的 `@Environment`）沒找到，要在 Xcode 下 `SwiftUI` 執行期中斷點才找得到，沒修。
   - 其餘是 Xcode 自己的 `appintentsmetadataprocessor` 提示，與程式無關。

## 給下一個做 DEBUG 的人

- full lane 的失敗訊息：`gh api repos/a91453/railway-game-ios/actions/runs/<id>/logs > l.zip` 解開，在 `3_Xcode build (iOS Simulator).txt` grep `error:`；警告 grep ` warning: `，排掉 `Accessing Environment` 與 `appintentsmetadataprocessor` 再看。
- 這個範圍的測試類別：`git diff --name-only --diff-filter=AM <舊>..<新> -- Tests` 裡的 `final class *Tests`。

## UNVERIFIED

- `TrainRosterView` 的修正：只在 macOS／Xcode 編得到，看這個 PR 的 `ios-build.yml`。
- release 建置沒跑（145 跑過 0 警告；這次只跑 debug）。
- 實機、Metal、聲音。
