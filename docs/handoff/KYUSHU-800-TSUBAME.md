# KYUSHU-800-TSUBAME：九州新幹線 800 系「つばめ」（作者舊版搬）

- 派工：專案「規劃3」工作串「九州新幹線 800 系」，認領在 #2118，決策 978（`docs/decisions/978.md`）。照 N700 那張（決策 977，#2683）的做法，把作者舊版 SwiftRailMac 的 800 系車頭 `d7f7f5e4`、中間車 `652fb052` 的貼圖切成色票面、放回真車尺寸、接進列車註冊表（決策 782）、九州新幹線與車庫「日本」類。
- session：作者 Mac 上的工作串（原始 GLB 只在那台 Mac 上，不進這個公開庫），2026-11-25。前一串對話壓縮第 2 次，照規矩停手，寫了這份；接手的工作串把頭車的加長法定下來之後更新。
- 分支 `claude/kyushu-shinkansen-800`，**已推上 GitHub 備份，還沒開 PR**：派工說等 #2683 合了再 rebase 到 main 才開。它現在疊在 N700 的舊提交 `9d61fb672` 上，#2683 之後又改過，之後 rebase 到 main 時 `tools/texture-palette/kyushu_n700.py`、`Map3DKyushuN700Tests.swift`、`Map3DRealTrains.swift` 多半會衝突。

## 做完、已提交的（`5a259ed12`）

- `tools/texture-palette/kyushu_800.py`：貼圖上每塊顏色的位置寫成一張表，轉檔前先對一次貼圖（`check_regions`），再照表切三角形。車頭 1,825 面、中間車 1,573 面（中間車的窗帶多排了兩格、車端補了全周幌，見下面）。讀檔、切面、寫 GLB 用 `kyushu_n700.py` 的函式（`write_glb` 多了材質表參數，N700 的產出逐位元組不變）。
- 真車尺寸：中間車 25.00 m、頭車 27.35 m、寬 3.38 m、屋頂高 3.65 m、標準軌 1,435 mm，六節 154.7 m。**頭車照真車的比例**（做法 E，見下面）：車身乘 1.30 加一格窗，車鼻乘 1.14。
- 顏色只用既有色票（白 `tileWhite`、紅 `trainRed`），沒有新增顏色；紅色在五張真車照片上量過（#5E0E11 到 #7A2522）。
- 車門：門框照舊貼圖的位置補回（`steel`），門板自成一個材質格位（`Map3DKyushu800.doorIndex`），每扇門的範圍在 `Map3DKyushu800.doors(_:)`，`testEachDoorIsAPieceOfItsOwn` 守著（和 N700S 同一個做法）。紅線在門的地方斷開，和舊貼圖、真車一樣。
- `Map3DKyushu800.swift`、`Map3DKyushu800Mesh.swift`（產生的）、註冊表名單末尾一行、`tools/train-models/locks/kyushu800.json`、`Map3DRealTrains` 的 `alternate`（車次奇數畫 800 系六節）、車庫「日本」類、`WhatsNewNext` 一行、`docs/art/kyushu-800-2026-11/`、`Map3DKyushu800Tests`（現在 10 項）。存檔版本、golden schema、GameCore 都沒動。

## 頭車：照真車的比例（做法 E，2026-11-25 晚上定的，取代 A）

作者看了 A、C、D 之後說「還是看真車來評比採用哪個方案」。在三張不同角度的真車照片上用客室窗當尺量（窗距＝座位間距 1.04 m，沿側牆的透視配成一維的投影式），鼻尖到乘務員門正中約 7.85 m（三張 7.70、7.83、8.05 m），頭車 14 格窗。A 是 8.91 m、13 格；C、D 是 6.9 m。所以改成 E：乘務員門門框前緣往後的車身乘 1.30、窗帶多排一格（14 格，窗距 1.04–1.08 m），車鼻拿剩下的長度（乘 1.142）。`kyushu_800.py` 的 `CAB_BODY`、`CAB_BAYS`、`NOSE_TO`、`more_bays()`；`doors(.cab)` 改了；註冊表的面數上限改成 1,900；`testTheCabCarHasTheRealCarsProportions` 守著。完整的表在決策 978 第 3 點。

**每台車都照這張表比**（協調者 2026-11-25 定的統一規則：選最接近真車、車鼻最不變形的做法）：鼻尖到乘務員門正中、客室窗數、窗距、窗寬、客室門寬、乘務員門寬，一欄真車、一欄遊戲。量真車的方法：

1. 找看得到整面側牆的照片（斜角也可以），沿窗的中線取一條線，讀每格窗左右緣的像素位置。
2. 窗是等距的（一排座位一格，窗距＝公開的座位間距），用窗的序號對像素位置配 `x = (a·s + b) / (c·s + 1)`，殘差要在半個像素內。
3. 連結面的黑縫、門框、乘務員門都在同一面牆上，把它們的像素位置代回去就是離第一格窗幾個窗距。鼻尖不在牆上，不要直接量：用車長減掉連結面到乘務員門的距離。
4. 至少量兩張不同角度的照片，差在 0.3 m 內才用。窗寬與門寬同一個式子直接讀。

窗寬也照真車改了（協調者轉告照最接近真車的做）：`regions()` 裡客室窗的寬改回貼圖原本的 20 個像素，頭車 0.69–0.72 m、中間車 0.69–0.73 m（真車 0.71 m；先前看斜角照片以為是窄窗而收成 0.5 m）。

還和真車不一樣、沒改的：客室門改窄要把門框移開貼圖上的位置，`check_regions` 會對不上，沒有做；客室門 1.01 m 與中間車的門 1.12–1.16 m（真車 0.89 m）、乘務員門 0.74 m（真車 0.87 m）、中間車 16 格（真車 17–20 格）。多排窗的那一段裙板與肩部的頂點比較密，近看明暗和旁邊差一點（中間車從 16 格那一版就有）。

## 先前的做法 A（整節等比放大，已被 E 取代）

作者 2026-11-25 看了對照圖（A、B、舊版頭車並排，加一節中間車；圖只貼在私有的工作串）說「不知道 用你覺得對遊戲最好的方法」。協調者定的規則：**A、B 哪一種讓頭車的窗距、窗寬、門寬最接近中間車，就用哪一種**，每台車各自量。800 系量出來三項都是 A 比較接近（數字在決策 978 第 3 點的表），當時留了已提交的 `5a259ed12`；後來作者要看真車來比，改成上面的 E。

- **A（當時採用）**：頭車整節等比放大。窗 0.49–0.51 m、窗距 1.04–1.08 m、客室門 1.01 m、車鼻 8.56 m。
- **B（沒採用）**：頭車和中間車同一個比例，不足的長度在直線車身多插兩格窗、再補 0.37 m 的牆。窗 0.44–0.46 m、窗距 0.95–0.99 m、客室門 0.92 m、車鼻 7.83 m。中間車是 0.53–0.56 m、1.13–1.22 m、1.12–1.16 m。
- 原因：舊版的頭車沿車身被壓得比中間車短，窗與門本來就小一號，B 不拉它就離中間車更遠。
- B 的工具留在分支 `claude/kyushu-800-lengthen-wip`（已推，不開 PR、不併）：`kyushu_800.py` 的 `cut_at`、`spans`、`lengthen`（頭車的窗分兩組，窗距 0.833 與 0.800 舊版公尺；在最長的一組等距的窗中間照樣再排兩格，牆用移頂點的方式加長，頭車 1,824 面）。那個分支上 `Map3DKyushu800Tests` 有兩項沒過（乘務員門在那個比例只有 0.68 m 寬；新加的窗距檢查太緊），沒有修。別的車要用 B 時可以抄。

## 中間車的窗：14 格改成 16 格，後面的門往車端移 0.52 m

作者 2026-11-25 問真車有幾格窗、怎麼做既保有真實又對遊戲好。真車每排座位一格窗、窗距約 1 m（頭車 12、14 格，中間車 17–20 格）。頭車 13 格、窗距 1.04–1.08 m 已經對；中間車 14 格、1.13–1.22 m 太疏。`kyushu_800.py` 的 `more_windows()` 把窗帶多排兩格、沿車身乘 0.9：16 格、窗 0.48–0.51 m、窗距 1.04–1.08 m，和頭車一樣。第一版把窗帶收回原長、門不動，作者看了說「中間車格用 16，然後車門稍微移動」，所以改成窗帶後面那扇門往車端平移 0.52 m，門後的空牆 4.3 m 收成 3.8 m（決策 978 第 3 點；兩版的對照圖只在私有的工作串）。`doors(.middle)` 的第二扇跟著改了，`testTheWindowsAreAboutAMetreApartOnBothCars` 守著窗數、窗距與門的位置。

## 車端的縫：補了一圈深色的全周幌

兩節車身的端牆各離連結面 0.298 m（頭車 0.326 m），所以舊版兩節車身相隔 0.60 m，中間只有 1.20 m 寬、2.10 m 高的通道幌，四周看得穿。作者 2026-11-25 先說「全周幌保持舊版原樣吧 真實車也存在吧 我只說改車門而已」，後來交代照最接近真車的做（協調者轉告，沒有附作者的原話）。真車側面照片上兩節之間是和車身齊平、從屋頂到裙板底的深色外幌，所以 `kyushu_800.py` 的 `hoods()` 在每個連結端把車身端面輪廓的凸包整圈延伸到離連結面 2 cm、口封起來，用既有的 `dark`；舊版那條窄的通道幌留在裡面。N700S 那一串用車身色，這台照真車用深色。`testADarkHoodClosesTheGapBetweenTwoCars` 守著；作者要改回舊版原樣的話，拿掉 `build()` 裡 `scaled += hoods(scaled, cab)` 那一行再重轉。

## 頭車的另外兩種做法（沒採用，只在本機）

作者 2026-11-25 畫了一張圖：車鼻留舊版的 6.58 m 不放大，只放大後面的車身。做了兩種給他比：C（車身乘 1.44，13 格窗，窗距 1.15–1.20 m，門 1.04 m）、D（車身乘 1.29 再插兩格窗，15 格，窗距 1.03–1.08 m，門 0.93 m）。作者說「不知道 你覺得怎麼做既能維持真實與遊戲的平衡點」，當時先留 A；接著作者說看真車來評比，量了之後 A、C、D 都不是最接近的，做了 E。C、D 只在作者 Mac 的暫存資料夾做過圖，沒有進任何分支。

## 還留下的

1. 等 #2683 合進 main，把這個分支 rebase 到 main（`tools/texture-palette/kyushu_n700.py`、`Map3DKyushuN700Tests.swift`、`Map3DRealTrains.swift` 多半會衝突），重跑建置與測試、重產鎖檔，開草稿 PR（開頭兩行署名、`經驗檔：docs/studio/lessons/kyushu-800.md`、五個角度、VERIFIED／UNVERIFIED），指派作者、請作者審，在 #2118 留言。分支已經推上 GitHub 備份，還沒開 PR。
2. **合併前先送工作室審**（作者同意的）：把分支、GLB、總覽圖交給協調者，由不同家的模型審，審過、CI 綠了才合。不開 auto-merge。
3. 私有素材庫 -2 的經驗檔 `docs/studio/lessons/kyushu-800.md` 與 `rolling-stock.md` §8 的更正（「頭車只拉長車鼻」改成上面那條規則）已經交給協調者代推；Mac 推不了那個庫。
4. 合了之後在 #2118 放掉決策 978。

## 在 Mac 上做的時候會撞到的

- `swift build --build-tests` 在 Swift 6.4.2 會卡在既有的 `Tests/GamePresentationTests/MapPackChoicesTests.swift`（「sending 'defaults' risks causing data races」）。本機把那個 teardown 裡的 `defaults` 換成 `UserDefaults.standard` 就能編，測完 `git checkout` 回來，不要提交。
- `Map3DModelPackLockTests.testEveryModelIsAsLocked` 在 Mac 上有 41 台既有的車雜湊不同（鎖檔是 Linux 的值），沒有一台是這台車，是已知的。
- 重產鎖檔會把每一個鎖檔都重寫：跑 `tools/train-models/run.sh OUT --lock tools/train-models/hashes.lock.json`，把 `locks/kyushu800.json` 先複製出來，`git checkout tools/train-models/hashes.lock.json tools/train-models/locks/`，再放回去。`--lock` 那一次不會匯出模型，拍圖要另外跑一次。
- 這個帳號的 `gh event listen` 沒開（HTTP 403），等 PR 只能輪詢。

## 驗證（都是已提交的那一版）

- **VERIFIED**（Mac，Swift 6.4.2）：`swift build --build-tests -Xswiftc -warnings-as-errors`（繞過上面那個既有的錯）；`Map3DKyushu800Tests`、`Map3DKyushuN700Tests`、`Map3DTrainOwnGlassTests`、`Map3DTrainMaterialTests`、`Map3DRealTrainsTests`、`Map3DTrainSetTests`、`Map3DTrainRegistryTests`、`Map3DPaletteGuardTests`、`Map3DShowcaseTests`、`Map3DTrainLightsTests`、`Map3DFukuokaTrainsTests`、`Map3DMotionBudgetTests`、`Map3DTaipeiMetro461Tests`、`WhatsNewTests` 全過；`check.mjs --new-set kyushu800` 沒有這台車的失敗；兩支轉檔工具重跑的產出逐位元組相同；`doc_numbers.py --check` 差異 0 項。
- **UNVERIFIED**：鎖檔雜湊是 Mac 算的，Linux 以 CI 為準；其餘測試沒跑；iPhone 上沒看過。樣子（model-look）要作者與工作室判，不是做的人自己判。
