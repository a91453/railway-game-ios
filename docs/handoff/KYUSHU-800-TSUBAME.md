# KYUSHU-800-TSUBAME：九州新幹線 800 系「つばめ」（作者舊版搬）

- 派工：專案「規劃3」工作串「九州新幹線 800 系」，認領在 #2118，決策 978（`docs/decisions/978.md`）。照 N700 那張（決策 977，#2683）的做法，把作者舊版 SwiftRailMac 的 800 系車頭 `d7f7f5e4`、中間車 `652fb052` 的貼圖切成色票面、放回真車尺寸、接進列車註冊表（決策 782）、九州新幹線與車庫「日本」類。
- session：作者 Mac 上的工作串（原始 GLB 只在那台 Mac 上，不進這個公開庫），2026-11-25。**對話壓縮第 2 次，照規矩停手**，所以寫這份。
- 分支 `claude/kyushu-shinkansen-800`，**只在 Mac 的本機 clone，還沒推、還沒開 PR**：派工說等 #2683 合了再從 main 重開分支。它現在疊在 N700 的舊提交 `9d61fb672` 上，#2683 之後又改過，之後 rebase 到 main 時 `tools/texture-palette/kyushu_n700.py`、`Map3DKyushuN700Tests.swift`、`Map3DRealTrains.swift` 多半會衝突。

## 做完、已提交的（`5a259ed12`）

- `tools/texture-palette/kyushu_800.py`：貼圖上每塊顏色的位置寫成一張表，轉檔前先對一次貼圖（`check_regions`），再照表切三角形。車頭 1,487 面、中間車 1,066 面。讀檔、切面、寫 GLB 用 `kyushu_n700.py` 的函式（`write_glb` 多了材質表參數，N700 的產出逐位元組不變）。
- 真車尺寸：中間車 25.00 m、頭車 27.35 m、寬 3.38 m、屋頂高 3.65 m、標準軌 1,435 mm，六節 154.7 m。**這一版的頭車是整節沿車身等比放大**（做法 A），車鼻沒有單獨拉長或改形。
- 顏色只用既有色票（白 `tileWhite`、紅 `trainRed`），沒有新增顏色；紅色在五張真車照片上量過（#5E0E11 到 #7A2522）。
- 車門：門框照舊貼圖的位置補回（`steel`），門板自成一個材質格位（`Map3DKyushu800.doorIndex`），每扇門的範圍在 `Map3DKyushu800.doors(_:)`，`testEachDoorIsAPieceOfItsOwn` 守著（和 N700S 同一個做法）。紅線在門的地方斷開，和舊貼圖、真車一樣。
- `Map3DKyushu800.swift`、`Map3DKyushu800Mesh.swift`（產生的）、註冊表名單末尾一行、`tools/train-models/locks/kyushu800.json`、`Map3DRealTrains` 的 `alternate`（車次奇數畫 800 系六節）、車庫「日本」類、`WhatsNewNext` 一行、`docs/art/kyushu-800-2026-11/`、`Map3DKyushu800Tests`（7 項）。存檔版本、golden schema、GameCore 都沒動。

## 做到一半的：頭車要用哪一種加長法

作者 2026-11-25 看了做法 A 之後先說「車頭彎曲部分不放大」「只放大方形部分」，接著又說「那還是原本照比例放大 哪種比較好 我不知道」。**還沒定。**協調者要一張對照圖給他選，選定之後 800 系、N700S、700T 都用同一種：

- **A**：頭車整節等比放大（已提交的這一版）。車鼻、窗、窗距都比中間車長 9%。
- **B**：頭車和中間車同一個比例（車鼻弧線、窗、門、窗距都不另外放大），到 27.35 m 還差的長度補在直線車身：窗帶中間多插窗格，剩下的加在沒有東西的牆上，窗不拉長。協調者建議 B。
- 對照圖要有：A、B、舊版三種頭車並排，旁邊放一節中間車當比例尺。舊版模型目錄的縮圖只在作者的 Mac 上用，不進公開庫，只貼在私有的工作串。

B 寫到一半，在本機分支 `claude/kyushu-800-lengthen-wip`（一個 WIP 提交，疊在 `5a259ed12` 上，**轉檔會中止**）：

- `kyushu_800.py` 多了 `cut_at`（沿車身把三角形切開）、`spans`、`lengthen`；`along()` 改回和中間車同一個比例；頭車轉向架照真車位置放（後轉向架中心離連結面 3.75 m、中心距 17.5 m）。
- 中止的原因：`lengthen` 先檢查頭車的窗是不是等距，結果不是。頭車 13 格窗分兩組，窗距是 0.833 與 0.800（舊版的公尺），中間還有一格 0.813。檢查要改成「在同一組等距的窗裡插」，用那一組自己的窗距；要補的長度約 1.975（舊版的公尺），插兩格之後剩下的加在乘務員門與第一格窗之間的牆。
- 還沒做：轉檔成功之後，`Map3DKyushu800Mesh.swift` 重產、`Map3DKyushu800.doors(_:)` 的頭車門位置、註冊表的面數範圍、`Map3DKyushu800Tests`、鎖檔、組裝用的車距、`docs/art/kyushu-800-2026-11/overview.jpg` 與 README、決策 978 裡「頭車整節放大」的句子，全部要跟著改。插進去的那一段要不要像門一樣自成一塊，協調者說可做可不做。
- 作者若選 A，丟掉 WIP 分支就好，已提交的那一版不用改。

## 還留下的

1. 做出 B，拍 A、B、舊版的對照圖給作者選（上面那一節）。
2. 照選定的做法收尾，重跑建置與測試，重產鎖檔。
3. 等 #2683 合進 main，把這個分支 rebase 到 main，推上去，開草稿 PR（開頭兩行署名、`經驗檔：docs/studio/lessons/kyushu-800.md`、五個角度、VERIFIED／UNVERIFIED），指派作者、請作者審，在 #2118 留言。
4. **合併前先送工作室審**（作者同意的）：把分支、GLB、總覽圖交給協調者，審過、CI 綠了才合。不開 auto-merge。
5. 私有素材庫 -2 的經驗檔 `docs/studio/lessons/kyushu-800.md` 與 `rolling-stock.md` §8 還寫著舊的說法（「頭車只拉長車鼻」），作者選定之後要請協調者代改成選定的做法；Mac 推不了那個庫。
6. 合了之後在 #2118 放掉決策 978。

## 在 Mac 上做的時候會撞到的

- `swift build --build-tests` 在 Swift 6.4.2 會卡在既有的 `Tests/GamePresentationTests/MapPackChoicesTests.swift`（「sending 'defaults' risks causing data races」）。本機把那個 teardown 裡的 `defaults` 換成 `UserDefaults.standard` 就能編，測完 `git checkout` 回來，不要提交。
- `Map3DModelPackLockTests.testEveryModelIsAsLocked` 在 Mac 上有 41 台既有的車雜湊不同（鎖檔是 Linux 的值），沒有一台是這台車，是已知的。
- 重產鎖檔會把每一個鎖檔都重寫：跑 `tools/train-models/run.sh OUT --lock tools/train-models/hashes.lock.json`，把 `locks/kyushu800.json` 先複製出來，`git checkout tools/train-models/hashes.lock.json tools/train-models/locks/`，再放回去。`--lock` 那一次不會匯出模型，拍圖要另外跑一次。
- 這個帳號的 `gh event listen` 沒開（HTTP 403），等 PR 只能輪詢。

## 驗證（都是已提交的那一版）

- **VERIFIED**（Mac，Swift 6.4.2）：`swift build --build-tests -Xswiftc -warnings-as-errors`（繞過上面那個既有的錯）；`Map3DKyushu800Tests`、`Map3DKyushuN700Tests`、`Map3DTrainOwnGlassTests`、`Map3DTrainMaterialTests`、`Map3DRealTrainsTests`、`Map3DTrainSetTests`、`Map3DTrainRegistryTests`、`Map3DPaletteGuardTests`、`Map3DShowcaseTests`、`Map3DTrainLightsTests`、`Map3DFukuokaTrainsTests`、`Map3DMotionBudgetTests`、`Map3DTaipeiMetro461Tests`、`WhatsNewTests` 全過；`check.mjs --new-set kyushu800` 沒有這台車的失敗；兩支轉檔工具重跑的產出逐位元組相同；`doc_numbers.py --check` 差異 0 項。
- **UNVERIFIED**：鎖檔雜湊是 Mac 算的，Linux 以 CI 為準；其餘測試沒跑；iPhone 上沒看過；做法 B 完全沒驗（還轉不出來）。樣子（model-look）要作者與工作室判，不是做的人自己判。
