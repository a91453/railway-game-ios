# 交接：九州新幹線 N700 系（KYUSHU-SHINKANSEN-TRAINS，決策 977）

## 進度

- 做到哪：PR #2683（分支 `claude/kyushu-shinkansen-n700`，草稿）已有 N700 系頭車與中間車、真車顏色、天線鰭與燈位的修正、車門的門縫線。對話壓縮第 2 次，這個 session 照規定停手。
- 已驗證：本機 `swift build --build-tests -Xswiftc -warnings-as-errors` 過；`Map3DKyushuN700Tests`、`Map3DTrainOwnGlassTests`、`Map3DTrainMaterialTests`、`Map3DPaletteGuardTests`、`Map3DRealTrainsTests`、`Map3DShowcaseTests`、`Map3DTrainRegistryTests` 共 46 個測試過；`tools/train-models/check.mjs` ok。車頭 1,726 面、中間車 1,420 面。門縫線這一版的 CI 還沒讀。
- 下一步的第一個指令：`gh pr checks 2683`（只讀一次，不輪詢），再等工作室複審的結論。

## 作者定案的事（2026-11-25，不用再問）

1. 尺寸用真車尺寸：整節一起放大（長 × 1.19、寬 × 1.2、高 × 0.94），不單獨改車鼻。
2. 顏色照真車，登記成新色票：`kyushuWhiteBlue` #D8E5EB、`kyushuNavy` #214168、`kyushuGold` #897455（量法寫在決策 977）。
3. 車頭不可以另外改形（800 系被拉成尖刺是反例）。800 系與 N700S 照同三點做。
4. 合併前要工作室審過。CI 綠而且工作室說通過，才能把 PR 轉成可審並合併。

## 做了什麼

- 轉換器 `tools/texture-palette/kyushu_n700.py`、嵌入的網格 `Map3DKyushuN700Mesh.swift`、配方 `Map3DKyushuN700.swift`、登記一行、`kyushushinkansen` 路線的編成（8 節）、新功能說明一行、測試、lock、決策 977、`docs/art/kyushu-n700-2026-11/`。
- 工作室第一次審查（recheck-kyushu-n700-r1）退回兩點，已修：天線鰭補成 2.5 cm 厚的實心板；頭燈在外側、尾燈在內側。
- 車門：舊貼圖上的門框是一像素寬、接近車身色的線，轉換時被丟掉，只剩門上的小窗浮在牆上。現在照舊貼圖量出來的四個門框（轉換器裡的 `DOORS`）切出鐵灰色的門縫線（第 8 個材質 `doorLine`，用既有的 `Map3DPalette.steel`），門板是車身色。`testEveryDoorHasItsSeams` 守著。

## 還留下什麼

1. **工作室複審**：鰭、燈位、門縫線這三樣還沒有複審結論。送審的檔（兩個 GLB、總覽圖、算圖）要換成門縫線這一版；位置已經用訊息告訴協調者，不寫在公開 repo。
2. **門板拆成自己的一塊**（協調者 2026-11-25 轉述，作者同意）：之後要做到站開門的動畫，每片門板要是網格裡自己的一塊（自己的 submesh 或節點），面數與外觀維持現在這樣。還沒做。現在門板與車身同一個材質，只有門縫線分得出來；轉換器的 `DOORS` 已經有每片門的範圍，可以從那裡把門板的三角形分到自己的材質或自己的模型。遊戲的網格格式是一個單位一個模型、一個三角形一個顏色，「自己的一塊」要怎麼表示（另一個具名模型，或另一個材質索引）要先看 `Map3DRedCommuter.decodedMesh` 與 N700S 那一串的做法再定，兩台要一致。
3. **給作者看的新舊門框對照**：對照圖已經在這一串貼給作者（新版車側與舊貼圖車側）。舊貼圖是作者的原檔，不能放進公開 repo，所以對照圖沒有提交。
4. **合併**：複審通過、CI 綠之後 `gh pr ready 2683`、合併、在 #2118 留言、通知協調者（800 系與 N700S 兩串在等這個 PR）。合併前若落後 main 先併 `origin/main`。不要開 auto-merge。
5. lock 是在 Mac 上產生的：第一版的雜湊與 Linux CI 相同；門縫線這一版若 `Map3DModelPackLockTests` 在 CI 紅，照 CI 印出的雜湊改 `tools/train-models/locks/kyushuN700.json`。

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

不動存檔格式，不動 golden。UNVERIFIED：門縫線這一版在 CI（Linux 與 Xcode）還沒跑完；手機上的實機外觀沒看過。
