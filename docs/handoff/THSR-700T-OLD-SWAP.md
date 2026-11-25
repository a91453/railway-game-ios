# THSR-700T-OLD-SWAP：高鐵 700T 換成作者舊版的 700 系（決策 988，做到一半）

## 進度

- 做到哪：轉換工具寫完、外觀看了六輪（r6）、三節車的 mesh 與車組已接進遊戲、測試寫了但**有三個類別是紅的**；鎖檔、決策 988、總覽圖、PR 都還沒做。第一個 session 在第二次壓縮後照規定停手（2026-11-25）。
- 已驗證（這台 Mac，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 過；跑了 11 個類別共 97 個測試，`Map3DTHSR700TTests`、`Map3DHighSpeedSetsTests`、`TrainPackTests`、`Map3DChristmasLiveryTests`、`Map3DTrainShapeRefreshTests`、`Map3DTrainOwnGlassTests`、`Map3DPaletteGuardTests`、`Map3DShowcaseTests` 全過；`Map3DTrainMaterialTests`（1 個）、`Map3DTrainSetTests`（2 個）、`TrainPaintTests`（3 個）失敗，見「紅的測試」。
- 下一步的第一個指令：`swift build --build-tests -Xswiftc -warnings-as-errors && swift test --skip-build --filter 'Map3DTrainMaterialTests|Map3DTrainSetTests|TrainPaintTests'`，照「紅的測試」修。

## 這件工作是什麼

- 派工：作者 2026-11-25「好 換成舊版700系 塗裝改成跟真實台灣高鐵一樣塗裝」。遊戲裡的 700T 原本是配方畫的（決策 408、422，頭車 25.2 m，比真車的 27 m 短），換成作者舊版的 700 系，照 N700S 的做法（決策 979）切成色票面。
- 分支：`claude/thsr-700t-old-700`，疊在兩張還沒合的 PR 上：#2683（九州 N700，連帶 N700S 的分支）與 #2689（逐線選塗裝，決策 983）。**還沒開 PR**（測試是紅的，而且疊著兩張沒合的 PR，開了只會白跑 CI）；兩張合進 main 後併 main 再開草稿 PR。
- 決策 988 已在 #2118 登記，`docs/decisions/988.md` 還沒寫。存檔版本、golden schema 不動。
- 作者同意的範圍：不畫駕駛室側的乘務員門；集電弓車 = 中間車加集電弓；門照 N700S 的做法每扇自成一片（`doors(_:)`）；1,435 mm 軌距的輪子；橘色與青綠兩種塗裝都留（決策 983）；顏色從 Wikimedia Commons 的照片量；先給作者看總覽（舊版並排），作者說好之後交給工作室做不同家的審查，再合。
- 規劃給的規則：尺寸照真車；整節車一起放大，不單獨拉長或改車鼻的形狀；公開 repo 裡只稱「舊版」，不寫別的遊戲的名字；舊版的縮圖與貼圖不放公開 repo。

## 頭車怎麼加長：量過 A 和 B，選 B（多兩格窗）

規劃最後的規則是「每一款都量 A（整節等比放大）和 B（插窗格），用讓頭車的窗距、窗寬、門寬最接近中間車的那一種」。量到的（舊版原始尺寸，公尺）：

| | 窗距 | 窗寬 | 門寬 |
|---|---|---|---|
| 舊版頭車 | 0.8155（平均 0.813） | 0.635 | 0.635、0.623 |
| 舊版中間車 | 0.813 | 0.635 | 0.623 |

兩節本來就一樣，表示舊版的頭車沒有被壓短。中間車放大 25/21.001 = 1.190 倍；頭車若整節放大到 27 m 要 1.286 倍，窗、窗距、門都會比後面的車大 8 %。所以用 B：車鼻和門照中間車的倍率放大（車鼻形狀不動、不單獨拉長），直的車身多 2 m，窗從 12 格變 14 格，窗距 0.968 m 與中間車相同。N700S 與 800 系量出來是 A，700T 是 B。

## 做了什麼（都在這個分支）

- `tools/texture-palette/thsr_700t.py`：轉換工具。不從貼圖取色，而是在 3D 裡上漆：各色區是（沿車長、高度）平面上的凸多邊形，三角形照它切開；貼圖只用來認擋風玻璃、車燈和裙板。車鼻頂面用俯視的白色「舌形」留白。輸出 `thsr-700t-cab.glb`、`-middle.glb`、`-pantograph.glb` 與 `report.json`。用法在檔頭。
- `Sources/GamePresentation/Map3DTHSR700TMesh.swift`：r6 的三節車（頭車 1,903、中間車 1,308、集電弓車 1,392 個三角形）。
- `Sources/GamePresentation/Map3DTHSR700T.swift`：`Unit`、色票、`doors(_:)`、`model(_:)`，以及 `Map3DTrainSet.highSpeed700T()`（十二節，第 4、9 節是集電弓車，後半列轉向）。
- `Map3DTrainSets.swift`：`highSpeed` 換成新車組，沒有遠景車組；`highSpeedFar` 這個舊名字在 `byType` 指到 `highSpeed`；`nearOnly` 拿掉 `highSpeed`。
- `Map3DTrainShapeRefresh.swift`：`highSpeedPaints` 的車組改成 `[Map3DTHSR700T.key]`。配方與 `refresh-700t-*` 研究模型還留著。
- 測試：新增 `Map3DTHSR700TTests`；改了 `Map3DHighSpeedSetsTests`、`TrainPaintTests`、`TrainPackTests`、`Map3DTrainSetTests`、`Map3DChristmasLiveryTests`；刪了 `Map3DFarSets422Tests`。

重做 mesh：

```sh
uv run --with pillow --with numpy python tools/texture-palette/thsr_700t.py \
  --cab OLD/models/<頭車 7a188937>.glb --middle OLD/models/<中間車 e33da7fa>.glb --out-dir OUT
python3 -I tools/train-models/glb_to_swift.py --enum Map3DTHSR700T \
  --materials white,orange,black,skirt,glass,dark,headlamp,taillamp,frame \
  --out Sources/GamePresentation/Map3DTHSR700TMesh.swift \
  OUT/thsr-700t-cab.glb OUT/thsr-700t-middle.glb OUT/thsr-700t-pantograph.glb
```

## 紅的測試（沒修，原因是讀程式碼的推測，未驗證）

1. `Map3DTrainMaterialTests.testThePackMarksWholeTrianglesAndNothingElse`（第 69 行，「only a cabin or a studio train marks its own glass」）：新車自己標玻璃，要把 `set-highSpeed` 加進那份允許名單（N700S 怎麼列就怎麼列）。
2. `Map3DTrainSetTests.testEverySetsCarsAreInThePack`（第 119 行，六個模型的三角形數不在範圍內）：往上找 `highSpeed` 落在哪一條範圍，改成新車的 1,200 到 2,000。
3. `Map3DTrainSetTests.testEachCarsModel`（第 344 行）：期待值要改成後半列是 `set-highSpeed-carBack`、`set-highSpeed-pantoBack`。
4. `TrainPaintTests` 的 `testTheFrameMarksTheChosenLinesCars`（205）、`testTheLinePagesMenuAndTheChoice`（229）、`testEveryLineRunningTheModelAtOnce`（278 起）：還沒查。現象是 `fast` 那條線找不到塗裝選單、`lines(running:)` 只回第二條線，且沒選塗裝時就有車的 `paint` 不是 0。先看測試的 `session()` 怎麼建線，以及 `paintFamily(of:)` 怎麼從模型名字認出車組（新增的 `carBack`、`pantoBack` 可能沒被認到，或 `highSpeedFar` 的別名讓一條線走到別的路）。

## 還留下什麼

- 修上面的測試，再跑鎖檔的測試。
- 鎖檔：`tools/train-models/hashes.lock.json`、`pack.lock.txt`、`budgets.json`。拿掉 `highSpeedFar` 的項目，換 `set-highSpeed-*`（含 `carBack`、`pantoBack`）的雜湊與車燈。在 Mac 上 `run.sh OUT --lock …` 會連帶改掉約 39 個舊配方模型的雜湊（Mac 與 Linux 的浮點差），**只留 highSpeed 的差異，其餘還原**；或在雲端 Linux 上跑。
- 還在用 `highSpeedFar` 的舊工具：`tools/hsr-far-422/export.swift` 與 README、`tools/hsr-trains-408/export.swift`、`tools/train-modeling-410/export.swift`、`tools/mesh-lod-420/export.swift`。別名讓它們還能編，但印出來的「遠景」已經是同一組車，要改註解或拿掉那幾行。
- 給玩家看的字：`DataSourceCredits`（仿 `highSpeedTrainModel` 加一筆，或改寫）、`WhatsNewNext` 加一行。
- 文件：`docs/decisions/988.md`（照 979 的結構，含五個角度與外觀回合）、`docs/art/thsr-700t-2026-11/`（只放轉換後模型的 `overview.jpg` 與 README）、`tools/texture-palette/README.md` 加一列、`.claude/skills/rolling-stock/SKILL.md` 若提到 700T 的尺寸要改。之後 `node tools/train-models/check.mjs`、`python3 -I tools/golden-checks/doc_numbers.py --check`。
- 外觀：用遊戲的匯出工具把 r6 重新匯出、渲染（目前手上的遊戲渲染是較早的 mesh），至少再看一輪；做總覽圖給作者（給作者的那份與舊版並排，不進公開 repo；公開的那份只有轉換後的模型）。作者說好之後請規劃交給工作室做不同家的審查。
- PR：本文開頭要有署名兩行，寫「經驗：…」一行（`lessons-link.yml`），指派並請 a91453 審；#2118 留言。經驗要寫進私有 repo 的 `docs/studio/lessons/`，Mac 推不了那個 repo，交給規劃。
- 工具裡的小整理：`thsr_700t.py` 的 `ORANGE` 先是色票編號、後來被高度範圍蓋掉，所以另有 `ORANGE_KIND`，改個名字。`Map3DTHSR700T.swift` 註解寫的「some 17,000」是對的（十二節合計約 17,000），留意改 mesh 後更新。

## 已知還不好的地方（寫進決策 988 的「還有哪裡不好」）

- 裙板的顏色先用 `tankStand`，沒對照片量。
- 窗與門是方角，真車是圓角。
- 集電弓、絕緣罩與兩片擋風板是工具手寫的（舊版沒有集電弓車）。
- 車頂全白。
- 擋風玻璃與車燈沿用舊版的小形狀；真車是一整片深色水滴形，燈在裡面。
- 配方畫的 `refresh-700t-*` 研究模型與配方還在程式裡。
- 還沒在 iPhone 上看過。

## UNVERIFIED

- Linux 上的建置與測試（只在 Mac 跑過）。
- 鎖檔測試、`check.mjs`、`doc_numbers.py`：沒跑。
- 遊戲渲染器裡 r6 的樣子：沒看（只看過軟體渲染的 r6 與遊戲渲染的 r3）。

工作用的資料夾（照片、六輪的輸出、看圖的小程式）在作者的 Mac 上，不在任何 repo；位置記在那台 Mac 的 session 記憶裡。
