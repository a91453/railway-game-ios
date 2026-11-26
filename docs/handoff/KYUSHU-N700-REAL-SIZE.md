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

## 先不要合：輪子和裙板開口對不齊（作者 2026-11-26 02:57「輪子是不是跑偏了」）

工作室審查通過之後作者看總覽圖發現的，**#2720 等修好才合**（協調者另派一串修）。

- 轉向架本身沒問題：照真車放（`BOGIE_FROM_END = 3.75`、`BOGIE_CENTRES = 17.5`，只平移不縮放），頭車前轉向架中心離鼻尖 6.10 m、後轉向架離連結面 3.75 m，中間車兩個都離連結面 3.75 m，兩轉向架中心 17.5 m；左右對中心，軌距 1.435 m（`port_check` 軌距項過）。
- 問題在車身：車身下緣讓輪子露出來的那一段裙板開口（輪罩）是車身的一部分，跟著車鼻 × 1.2、車身 × 1.287 一起拉長、搬了位置，轉向架卻照真車位置放，兩者就錯開了。從底下看（`render/…/set-kyushuN700-head-bottom.png`）：頭車前轉向架偏在開口前端，開口中心比轉向架中心往後約 0.8–0.9 m；後轉向架開口中心比轉向架往連結面方向偏約 0.5 m；中間車偏約 0.1–0.25 m。以前整節等比放大，轉向架也跟著舊位置，所以沒錯開。
- 改法（建議）：`kyushu_n700.py` 的 `along()`／`middle_along()` 再加折點，把舊版每個輪罩開口的前後緣對到「真車轉向架中心 ± 開口半長」（開口本身只平移或照車鼻倍率），窗帶的拉長改在兩個開口之間吃掉；改完窗數、窗距、門的位置要再對一次（`testTheCarsAreAtTheRealCarsProportions`），`port_check.py` 全過、鎖檔照 CI 印的改、總覽圖重拍並加一張側面輪子近看。另一個做法是轉向架改放在開口中心（不照真車），會讓前轉向架離鼻尖約 6.9 m、兩轉向架中心約 16.2 m，和真車差較多，不建議。
- 順帶：輪軸距 2.13 m（舊版的），真車 2.5 m，要不要一起改由修的那串決定。

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
