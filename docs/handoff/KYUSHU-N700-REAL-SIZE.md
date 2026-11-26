# 九州 N700 照真車比例（決策 977 第 8 節）

工作串「讓九州 N700 照真車比例」，分支 `claude/project-thread-ulphlo`。接 `docs/handoff/KYUSHU-N700-RECHECK.md` 留下的兩樣：全周幌、頭車 27.35 m。這一串壓縮兩次後停手，下面是還沒做完的。

## 做完的

- 轉換器 `tools/texture-palette/kyushu_n700.py` 分段放大（車鼻 × 1.2、車身 × 1.287 多一格窗）、米色全周幌、門往車端移 0.30 m、扶正舊版車鼻的 2.23 mm 偏心、補 T 形接點（`mend_near`）、門框邊的細碎面歸門（`absorb_slivers`）。
- `port_check.py` 全過（三處修正寫在決策 977 第 8 節）；網格、`doors(_:)`、鎖檔、測試（窗數、窗距、門位置、幌）、總覽圖、決策、README 都更新了。
- VERIFIED（雲端 Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DKyushuN700Tests`、`Map3DModelPackLockTests`、`Map3DTrainOwnGlassTests`、`Map3DTrainMaterialTests`、`Map3DRealTrainsTests`、`Map3DTrainSetTests`、`Map3DTrainRegistryTests`、`Map3DPaletteGuardTests`、`Map3DShowcaseTests`、`Map3DTrainLightsTests`、`Map3DFukuokaTrainsTests`、`Map3DMotionBudgetTests`、`Map3DTrainShapeRefreshTests`、`TrainPaintTests`；`check.mjs` ok。

## 還沒做的

1. **工作室換家審一次**（model-look §4）：協調者轉給 Mac 工作室串；過了、CI 綠就合。只退小項就修好、`port_check.py` 全過、CI 綠即合，不跑第二輪。
2. **依賴 #2706（800 系）**：`tools/texture-palette/kyushu_800.py` 是 #2706 分支的同一份檔（逐位元組相同），這個 PR 先帶著；#2706 先合的話併 `origin/main` 就沒有差異。#2706 若再改這個檔，併的時候取 #2706 的版本，再跑一次轉換器確認輸出不變。
3. 經驗檔：私有素材庫 -2 的 `docs/studio/lessons/kyushu-n700.md`（規則 10），由協調者代推。
4. iPhone 上的樣子與幀數沒看過；發版後請作者看九州新幹線的車兩節之間。
5. 鼻尖到乘務員門比真車長 0.5 m、客室門比真車寬 0.2 m（表在決策 977 第 8 節），作者交代車頭不單獨改造型，沒動。

## 輪子和輪罩開口對不齊：已修（作者 2026-11-26 02:57「輪子是不是跑偏了」）

另一串接手修好（決策 977 第 8 節「輪罩開口對準轉向架」）：轉向架照真車位置不動，車身下緣（舊版 y 0.779 以下的裙板與開口頂板）另外放，每個開口 × 1.19、正中對到轉向架正中，伸縮放在開口之間的裙板；側牆下緣以上 7 cm 先橫切，只有那一條跟著斜，門窗藍帶車鼻都不動。三個開口正中和轉向架差不到 1 mm（新測試 `testTheWheelsAreInTheMiddleOfTheirOpenings`），`port_check.py` 全過，窗數窗距測試照舊過，鎖檔已改，總覽圖加了改前改後的側面下緣。輪軸距 2.13 m（真車 2.5 m）沒改，寫在決策與 README 的不足。照流程這是審查後的小修：自動檢查與 CI 綠就合，不再審。

## 重跑的指令

```
uv run --with pillow --with numpy python tools/texture-palette/kyushu_n700.py --cab <cab.glb> --middle <middle.glb> --out-dir OUT
uv run --with numpy python -I tools/texture-palette/port_check.py OUT --old <cab.glb> --nose-scale 1.2,0.94265,1.2 --nose-from 5.584 --md OUT/port-check.md
python3 -I tools/train-models/glb_to_swift.py --enum Map3DKyushuN700 --materials whiteBlue,navy,gold,glass,dark,headlamp,taillamp,doorLine,hood --out Sources/GamePresentation/Map3DKyushuN700Mesh.swift OUT/kyushu-n700-cab.glb OUT/kyushu-n700-middle.glb
tools/train-models/run.sh RENDER --tag after --ids set-kyushuN700-head,set-kyushuN700-car,set-kyushuN700-tail
node tools/train-models/check.mjs RENDER && node tools/train-models/render.mjs RENDER --time both
```

鎖檔照 `Map3DModelPackLockTests` 印出的雜湊改 `tools/train-models/locks/kyushuN700.json`。兩個舊模型是作者自己的舊版作品（舊版型錄「N700系『みずほ』『さくら』等」，車頭 `bc97d3e5`、中間車 `fd0310c2`），原檔與貼圖不進這個 repo。

## 存檔與 golden

不動。
