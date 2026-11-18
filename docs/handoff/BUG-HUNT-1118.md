# BUG-HUNT-1118（找 2026-11-18 合併的 bug）

派工：協調者，作者 2026-11-18「或是找bug之類的」。session：雲端工作串「找今天合併的 bug」，分支 `claude/project-thread-gqojr0`。第二次壓縮後照規則停手，沒做完的寫在下面。

決策 528 的「後來（BUG-HUNT-1118）」。只改 GamePresentation；GameCore、存檔版本（110）、golden（77）、ReplayFixtures 都不動。

## 進度

- 做完的：修了一個 bug（香港機場三綫一起買之後，刪掉機場快綫或東涌綫就再也買不回來），`RealLineLeftover.swift` 的 `RealLineClearing.edgesInUse`；回歸測試 `HongKongBoughtAgainTests`（修之前紅）。
- 已驗證（Linux，Swift 6.4，**不是實機**）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`HongKongBoughtAgainTests`、`DanhaiDepotTests`、`RealLineBundleTests`、`RealLineAcquisitionTests.testThePingxiLineIsBoughtAgainAfterItIsRemoved` 通過。其餘交給 CI。
- 下一步的第一個指令（要接「還留下什麼」第 1 項時）：`git apply /mnt/project-files/handoff/BUG-HUNT-1118-probes.patch`，再照最後一節跑 `BUGHUNT_REBUY=1 BUGHUNT_ONLY=small`。

## 查過、沒問題的

用 build 139（`a67c823`，#2461 之前）另開一個 worktree 存出 38 份真的舊存檔，在新版讀進來測：

- **舊存檔只買了線組的一部分，再補買剩下的**：香港機場三綫的九種買法、羅瓦涅米、淡海、竹中（各測剛買完與跑過一天兩種）。剩下的線綁成一組賣、買得到；存檔原有的月台一個都沒少；沒有疊在一起的月台；新舊月台同高（青衣除外，另一張單 TSING-YI-LEVEL 在修）；存讀相等；復原回到買之前；之後兩天班次全發。
- **香港跨功能**：先蓋昂坪纜車、再買機場三綫、設東涌站到站鈴與發車旋律、存讀檔、跑 30 小時，都正常；三綫買下後纜車的轉乘站變成東涌。
- 讀過 #2458、#2459、#2460、#2462、#2463、#2464、#2466、#2467、#2468、#2470 的改動，沒找到錯。v108 的舊存檔經 109、110 的轉換讀得進來。

## 修了什麼

香港機場快綫、東涌綫、迪士尼綫一起買之後，在路線面板刪掉機場快綫或東涌綫：那條線單獨重新上架，但收購卡寫「這裡不能建軌道…」，買不回來。機場快綫在 build 139 買得回來（今天的改動造成），東涌綫原本就不行。原因、做法、數字在決策 528 最後一節。

修完後量到（香港三條各自刪掉再買回來）：留下的軌道全部拆掉重鋪，之後一整天 226、274、220 班全發，月台沒有疊，存讀與復原都對。羅瓦涅米兩條、淡海兩條、內灣線、福岡三條買回來也都正常。

## 還留下什麼（評分在私有庫 `docs/priorities/BUG-HUNT-1118.md`）

1. **bug：六家線刪掉後買不回來（LIUJIA-REBUY）**。台灣地圖買「六家線＋內灣線」，刪六家線，再買被拒：「這段軌道會與另一段軌道交叉，但兩者的高度差不到 8 公尺…」。build 139 就這樣，這次的修正沒有改變它（原因不同：是重鋪在竹中和內灣線的軌道交叉，不是留下的月台）。內灣線刪掉再買沒問題。還沒查為什麼退路（把站抬高、放旁邊）救不了。
2. **bug：淡海的濱海沙崙，兩條線的月台高度差 3.2 m、平面相距 10 m（DANHAI-SHALUN-LEVEL）**。照線組的順序（綠山線、藍海線）買就會這樣，所以每個買淡海線組的玩家都遇得到；build 139 也一樣。屬於「兩條線共站要同高並排」（skill `real-line-laying`、決策 848），和青衣那張單同一類。
3. **bug：舊存檔只買了藍海線，再買綠山線（DANHAI-OLD-SAVE）**。綠山線在 7 個共用車站另鋪自己的月台，高 10 到 17 m、離 25 m。只有 #2461 之前單買過藍海線的舊存檔會遇到；build 139 也一樣。
4. **真實纜車沒有乘客（CABLEWAY-NO-RIDERS）**。量到的（新遊戲，沒有鐵路時）：
   - 昂坪纜車 NT$10,250,500、每天維護 NT$28,835；買了東涌綫之後轉乘站是東涌，但轉乘旅次 0、在地旅次 0，跑 30 小時乘客 0。香港地圖沒有任何景點（`AttractionCatalog` 只有台灣的 217 個），而觀光客要有景點才會來。
   - 日月潭纜車 NT$3,990,000、每天 NT$9,300；烏來纜車 NT$1,771,500、每天 NT$1,905：附近沒有車站，跑 78 小時乘客 0（日月潭、九族文化村、烏來溫泉這些景點在，但觀光客要纜車接到車站才算）。
   - 貓空纜車 NT$8,849,500、每天 NT$20,165：沒買文湖線時一樣是 0；買了文湖線之後沒量。
   - 也就是今天加的三條「照真實路線拉」的纜車，玩家買了只會賠錢。要修是規則或資料的事（香港加景點、纜車站自己當觀光的落腳點），不是這張單的範圍。
5. **香港機場三綫的門檻**：整組 NT$135,678,431，標準開局 NT$9,000,000、貸款上限 NT$15,000,000。BUNDLE-SALE 的交接已經寫了、沒評分，這次補上分數。綁賣之前最便宜的迪士尼綫約 NT$586 萬，開局買得起。
6. 決策 528「下一步」原有的兩項（同一片軌道上路線不用的另一個月台也保護；卡片打開後世界變了不重算）還在。
7. **沒做**：今晚 01:37 的整輪 `ci.yml`（含時刻表體檢）與 full lane 的結果沒有看。

## UNVERIFIED

- 沒在 iPhone、iPad 上看過；收購卡多的那句「收購時會先拆掉這條線刪掉時留下的 N 段軌道…」在香港是第一次出現（機場快綫 354 段、東涌綫 432 段），樣子沒看。
- 買回來的線只在香港地圖跑了一天；台灣整張地圖上沒有測「刪掉再買」。

## 怎麼重跑

量測用的兩個測試檔沒有進 repo，存在 `/mnt/project-files/handoff/BUG-HUNT-1118-probes.patch`（`BugHunt1118ScratchTests.swift` 給現在的 main，`BugHuntDumpTests.swift` 給 build 139 的 worktree）。

```sh
# build 139 的存檔（約 20 分鐘，含編譯）
git worktree add /home/user/old139 a67c823      # 把補丁裡的 BugHuntDumpTests.swift 放進它的 Tests/GamePresentationTests/
(cd /home/user/old139 && swift build --build-tests && BUGHUNT_DUMP=<資料夾> .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.BugHuntDumpTests")

# 新版讀舊存檔、補買剩下的
BUGHUNT_DUMP=<資料夾> stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.BugHunt1118ScratchTests/testHongKong"
# 刪掉再買（small＝羅瓦涅米、淡海、竹中；hk；fukuoka；加 BUGHUNT_DAY=1 買回來後跑一天）
BUGHUNT_REBUY=1 BUGHUNT_ONLY=small stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.BugHunt1118ScratchTests/testRebuyNew"
# 香港某條線為什麼買不回來（逐段印出）
BUGHUNT_WHY=hkmtr:TCL stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.BugHunt1118ScratchTests/testWhyNotAgain"
# 纜車載客
BUGHUNT_CABLE=1 BUGHUNT_ONLY=hk stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.BugHunt1118ScratchTests/testCableRiders"
```

直接跑測試執行檔比 `swift test --filter` 快，也不會被 SwiftPM 的 `.build` 鎖卡住（兩個 `swift test` 同時跑，第二個會等到第一個結束）；`stdbuf -oL` 讓輸出一行一行出來。
