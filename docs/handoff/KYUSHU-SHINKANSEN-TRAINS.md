# 交接：九州新幹線 N700 系（KYUSHU-SHINKANSEN-TRAINS，決策 977）

## 進度

- 做到哪：PR #2683（分支 `claude/kyushu-shinkansen-n700`，草稿）已有 N700 系頭車與中間車、真車顏色、天線鰭與燈位的修正、車門的門縫線，以及每扇門拆成自己的一塊（2026-11-25 晚上，接手的第二個 session 做的）。
- 已驗證（Mac）：`swift build --build-tests -Xswiftc -warnings-as-errors` 過；`Map3DKyushuN700Tests`（8 個）、`Map3DTrainOwnGlassTests`、`Map3DTrainMaterialTests`、`Map3DPaletteGuardTests`、`Map3DRealTrainsTests`、`Map3DShowcaseTests`、`Map3DTrainRegistryTests`、`Map3DTrainLightsTests` 過；`tools/train-models/check.mjs` ok；`doc_numbers.py --check` 過。拆門前後：兩節車的面（1,726、1,420）逐一比過完全相同，遊戲匯出的 42 張算圖逐像素相同。
- 下一步的第一個指令：`gh pr checks 2683`（只讀一次，不輪詢），再等工作室第三次複審（r3）的結論。

## 作者定案的事（2026-11-25，不用再問）

1. 尺寸用真車尺寸：整節一起放大（長 × 1.19、寬 × 1.2、高 × 0.94），不單獨改車鼻。
2. 顏色照真車，登記成新色票：`kyushuWhiteBlue` #D8E5EB、`kyushuNavy` #214168、`kyushuGold` #897455（量法寫在決策 977）。
3. 車頭不可以另外改形（800 系被拉成尖刺是反例）。800 系與 N700S 照同三點做。
4. 合併前要工作室審過。CI 綠而且工作室說通過，才能把 PR 轉成可審並合併。

## 做了什麼

- 轉換器 `tools/texture-palette/kyushu_n700.py`、嵌入的網格 `Map3DKyushuN700Mesh.swift`、配方 `Map3DKyushuN700.swift`、登記一行、`kyushushinkansen` 路線的編成（8 節）、新功能說明一行、測試、lock、決策 977、`docs/art/kyushu-n700-2026-11/`。
- 工作室第一次審查（recheck-kyushu-n700-r1）退回兩點，已修：天線鰭補成 2.5 cm 厚的實心板；頭燈在外側、尾燈在內側。
- 每扇門自己的一塊（和 N700S、決策 979 同一種表示，協調者 2026-11-25 定）：轉換器照 `DOORS` 的外框給每個面標上是哪一扇門（門縫線的長方形本來就沿外框切，所以不用多切一刀，面數不變）；GLB 裡車身一個 node、每扇門一個 node（`kyushu-n700-cab-door-left-1`，由車頭端往後編號；頭車一側三扇含乘務員門，中間車一側兩扇），`report.json` 有 `doors`；Swift 還是一節一張網格（門的面排在最後），每扇門的範圍在 `Map3DKyushuN700.doors(_:)`，`testEachDoorIsAPieceOfItsOwn` 守著（門的面數頭車 436、中間車 380）。客室門的外框在牆上有一點斜（舊貼圖的貼法，整個門高差 2.2 cm），所以測試「沒有面跨過外框」留 3 cm；框選到的面和 GLB 的 node 完全一樣。
- 車門：舊貼圖上的門框是一像素寬、接近車身色的線，轉換時被丟掉，只剩門上的小窗浮在牆上。現在照舊貼圖量出來的四個門框（轉換器裡的 `DOORS`）切出鐵灰色的門縫線（第 8 個材質 `doorLine`，用既有的 `Map3DPalette.steel`），門板是車身色。`testEveryDoorHasItsSeams` 守著。

## 還留下什麼

1. **工作室複審 r3**：鰭、燈位、門縫線、門板四樣，要由和 Claude 不同家的審（Gemini／agy）。送審的檔（兩個 GLB、`report.json`、總覽圖、算圖、門板圖）已換成拆門這一版；位置用訊息告訴協調者，不寫在公開 repo。請求留在 #2118。
2. **尺寸**（長 × 1.19、寬 × 1.20、高 × 0.943）還在等作者回答高度，回答前不要動。
3. **給作者看的新舊門框對照**：對照圖已經在工作串貼給作者。舊貼圖是作者的原檔，不能放進公開 repo，所以對照圖沒有提交。
4. **合併**：工作室通過、CI 綠、尺寸確認，三樣都有了才 `gh pr ready 2683`、合併、在 #2118 留言、通知協調者（800 系與 N700S 兩串在等這個 PR）。合併前若落後 main 先併 `origin/main`。不要開 auto-merge。
5. lock 是在 Mac 上產生的：前兩版的雜湊與 Linux CI 相同；拆門這一版若 `Map3DModelPackLockTests` 在 CI 紅，照 CI 印出的雜湊改 `tools/train-models/locks/kyushuN700.json`。
6. `tools/texture-palette/n700s.py`（N700S 那一串，還沒推）借用這個轉換器的切面函式，並且有一行 `assert len(MATERIALS) == len(cut.MATERIALS)`：這裡從門縫線那一版起是 8 個材質，N700S 是 7 個，那一串 rebase 時要改那一行。`slabs`、`carve`、`settle`、`classify_point`、`centre`、`components`、`parts`、`read_glb` 的參數與回傳沒有動。
7. 到站開門的動畫還沒做。

## 重跑的指令

```
uv run --with pillow --with numpy python tools/texture-palette/kyushu_n700.py --cab <cab.glb> --middle <middle.glb> --out-dir OUT
python3 -I tools/train-models/glb_to_swift.py --enum Map3DKyushuN700 --materials whiteBlue,navy,gold,glass,dark,headlamp,taillamp,doorLine --out Sources/GamePresentation/Map3DKyushuN700Mesh.swift OUT/kyushu-n700-cab.glb OUT/kyushu-n700-middle.glb
tools/train-models/run.sh EXPORT --lock LOCKTMP/hashes.lock.json   # 只把 LOCKTMP/locks/kyushuN700.json 複製進 tools/train-models/locks/
tools/train-models/run.sh RENDER --tag after --ids set-kyushuN700-head,set-kyushuN700-car,set-kyushuN700-tail
node tools/train-models/check.mjs RENDER && node tools/train-models/render.mjs RENDER --time both
```

兩個舊模型是作者自己的舊版作品，在作者的舊版模型目錄裡（N700 系九州的頭車與中間車）；轉換器會驗 SHA-256。原檔與貼圖不進這個 repo。

## 存檔與 golden

不動存檔格式，不動 golden。UNVERIFIED：拆門這一版在 CI（Linux 與 Xcode）還沒跑完；手機上的實機外觀沒看過。
