# THSR-700T-OLD-SWAP：高鐵 700T 換成作者舊版的 700 系，另接原塗裝的 700 系（決策 988、989）

## 進度

- 做到哪（2026-11-25 深夜，第三個 session）：兩款車都做完並接進遊戲，700T 車鼻定案為 B（朝上的面全白，d8c09215b 的網格；決策 988 第 11 輪），分支上的就是最終版，相關測試在 Mac 上全過。下一步是工作室換家審查（規劃安排）。**還沒開 PR**。
- 分支：`claude/thsr-700t-old-700`，疊在還沒合的 #2683（九州 N700）與 #2689（逐線選塗裝，決策 983）上，另帶 N700S 那一個 commit（決策 979）。三者合進 main 後併 main，再開草稿 PR。
- 下一步的第一個指令：`gh pr view 2683 --json state && gh pr view 2689 --json state`；都合了就 `git fetch origin main && git merge origin/main`，再跑下面「驗證」那一行測試。

## 這件工作是什麼

- 派工：擁有者 2026-11-25「好 換成舊版700系 塗裝改成跟真實台灣高鐵一樣塗裝」（決策 988）。之後看了轉換後的圖：「那原始要順便接入嗎」「這樣就直接省事」「還多兩種車款」：舊版原本白藍塗裝的 700 系也當成一款車接進來，同一件工作做（決策 989）。
- 「還多兩種車款」指的是 700T 與原塗裝 700 系這兩款車本身（規劃 2026-11-25 更正）。前一版交接把它讀成「再多做另一端的車頭與寬窗車」，那是誤讀。這兩種車後來還是做了，理由是真車的十六節編組本來就有它們（第 8 到 10 節是寬窗、一個門的車；第 16 節的後門在車尾端），已告訴規劃；擁有者若要簡單一點，拿掉的改動很小（`Map3DTrainSet.series700()` 的 `tail` 改用轉向的 `cab`、拿掉 `centre` 與 `centreCars`，重寫鎖檔與測試裡的排法）。
- 規則：尺寸照真車；整節車一起放大，不單獨拉長或改車鼻的形狀；公開庫裡只稱「舊版」；舊版的貼圖與縮圖不進公開庫；不畫公司標誌與字樣。
- 擁有者看了總覽圖（2026-11-25）：「正面塗裝是不是怪怪的」「他是從車燈到上方」。真的 700T 的前窗與燈在同一片黑色面罩裡；已加（`thsr_700t.py` 的 `MASK`，只有 700T；測試 `testTheMaskRunsFromTheLampsToTheWindscreensTop`），前後對照圖已給擁有者。之後擁有者圈了車鼻兩肩朝上的那一層橘色：「這層應該可以白色，還是維持橘色我不知道」；對照片後改成車鼻朝上的面全白（`thsr_700t.py` 的 `tongue` 改成整片，測試在 `testTheNoseWearsTheDeepBand`），A／B 兩版並排給擁有者；他說「誰比較好 我都行」，選了 B（分支上的 d8c09215b）。
- 接著擁有者在 A 版的圖上把中間的白色 V 與兩肩塗成橘色：「但其實好像這樣塗多一點比較像」。試做：`tongue` 改成「白色的頂」（鼻尖後 1.8 m 起寬 ±0.2 m、3 m 處 ±0.8 m、5.5 m 處超出車寬，一直到鼻尖後 40 m；只到 9 m 的話後面的車頂也會變橘），外面朝上的面記成橘色，推上去過（ad8364ac5）。擁有者把它和 A、B 比過後說「看來看去還是這兩版比較好」，所以退回 B（之前選的那版）。若擁有者之後改要 A：A 是 d8c09215b 的上一個 commit 39969d680 的車鼻（`tongue` 是鼻尖窄、往後變寬的白舌頭，兩肩朝上的面照橘色的頂緣畫），頭車 1,999 面。
- 全周幌的經過：擁有者先說「全周幌保持舊版原樣吧」「我只說改車門而已」，後來交給做的人判斷，以最接近真車為準。實車照片（Commons 的 700T 側面照）上接縫被一圈同輪廓的幌蓋住，所以兩款都照 N700S 的 `hoods` 加了。700 系自己的接縫沒有另外找照片對。

## 做了什麼

細節在 `docs/decisions/988.md`、`989.md` 與 `docs/art/thsr-700t-2026-11/README.md`（含重做的指令）。重點：

- `tools/texture-palette/thsr_700t.py`：`--train thsr`（預設）出 700T 三節，`--train series700` 出 700 系五節。頭車 27 m 用多兩格窗的做法（量過兩種，舊版頭車與中間車的窗距、窗寬、門寬本來就一樣）；重複那一段用 `same_section` 檢查截面。
- `Map3DTHSR700T.swift`／`…Mesh.swift`：set `highSpeed`，十二節；`Map3DTrainSet.litEnd` 讓車頭只亮白燈、車尾只亮紅燈。
- `Map3DSeries700.swift`／`…Mesh.swift`：註冊表的車 `series700`，十六節，車庫的一款車；`Map3DTrainRegistryList.swift` 加一行；鎖檔 `tools/train-models/locks/series700.json`。
- 鎖檔：`hashes.lock.json`、`pack.lock.txt` 只動 `highSpeed` 的行（拿掉 `highSpeedFar`）。
- 四個舊的對照匯出工具不再要 `highSpeedFar`。
- `DataSourceCredits` 加 `highSpeed700Model`；`WhatsNewNext.nextItems` 加兩行。

## 前一版交接寫錯的地方

- 它說 `Map3DTHSR700TTests` 全過，其實當時提交的網格有兩個斷言是紅的（車頂的頂點不是每 1.5 m 都有；牆面的切線穿過窗，數窗緣會多算）。已改成：車頂量較寬的範圍，窗用玻璃三角形在 x 上的合併區間來數。
- `TrainPaintTests` 的三個紅字不是新車造成的：決策 979 把 N700S 的 key 改成 `n700s`，而 #2689 的測試鎖著 `"n700sG"`。這個分支改成鎖 `Map3DN700S.key`。**N700S 與 #2689 誰後合，誰就要帶這個修正**（已告訴規劃）。

## 還留下什麼

1. （做完）車鼻定案為 B。之後擁有者或審查有意見就改工具、重產網格、重寫鎖檔（Mac 上 `run.sh OUT --lock TMP/hashes.lock.json` 會改到三十幾個無關模型的雜湊，含配方的 `refresh-700t-*`，只取 `set-highSpeed-head`／`-tail` 的行與 `TMP/locks/series700.json`；`pack.lock.txt` 只在燈變時用 `MAP3D_WRITE_PACK_LOCK=1` 跑 `Map3DModelPackLockTests/testTheOrderAndTheLampsAreAsBefore` 重寫）。規劃請工作室審查。
2. #2683、N700S、#2689 合進 main 後：併 main、開草稿 PR（本文開頭兩行署名、「經驗：…」一行、指派並請 a91453 審）、在 #2118 留言。
3. 經驗的全文已傳給規劃一次（給私有庫 `docs/studio/lessons/thsr-700t.md`；Mac 推不了那個庫，由雲端的工作串推）。規劃要的是：工作室審查完，在「每輪被退回什麼」的表加上審查那一列，再整份傳一次。草稿在作者 Mac 的工作資料夾（`thsr-700t.md`）。
4. 可以再做的小事：`thsr_700t.py` 的 `ORANGE_KIND` 改名；配方畫的 `refresh-700t-*` 研究模型與配方是否拿掉。

## 驗證

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DSeries700Tests|Map3DTHSR700TTests|Map3DTrainMaterialTests|Map3DTrainSetTests|TrainPaintTests|Map3DHighSpeedSetsTests|TrainPackTests|Map3DChristmasLiveryTests|Map3DTrainShapeRefreshTests|Map3DTrainOwnGlassTests|Map3DPaletteGuardTests|Map3DShowcaseTests|Map3DN700STests|Map3DKyushuN700Tests|Map3DTrainRegistryTests|Map3DModelPackSizeTests|RealRailwaysTests|WhatsNewTests'
```

- VERIFIED（Mac，Swift 6.4）：上面兩行（本機另外繞過 `MapPackChoicesTests.swift` 的一個編譯錯，沒有提交）；`doc_numbers.py --check`；四個舊工具 `swiftc -typecheck`；`tools/train-models/check.mjs`（預算都過，紅的只有 Mac 上既有模型的雜湊差）；遊戲繪圖器看過兩款車。
- UNVERIFIED：Linux 上的建置與測試、寫進鎖檔的雜湊（Mac 算的）交給 CI；`Map3DModelPackLockTests.testEveryModelIsAsLocked` 在 Mac 上本來就有三十幾個無關模型是紅的，這兩款車不在其中；iPhone 上沒看過。

工作用的資料夾（照片、各輪輸出、看圖與排總覽圖的小程式）在作者的 Mac 上，不在任何 repo；位置記在那台 Mac 的 session 記憶裡。
