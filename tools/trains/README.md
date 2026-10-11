# tools/trains — 城市畫面的列車模型

兩個工具，都寫進 `Web/CityView/public/models/trains/` 並併入那裡的 `index.json`；
城市畫面（`Web/CityView/src/world/trains.js`）的 stock 加上 `models: { cab, car }` 就會用。

| | 什麼時候用 |
| --- | --- |
| `bake_model.py` | **有一個作者認可的密模型**（Meshy 之類）。把它降成遊戲資產 |
| `build_train.py` | 沒有模型。從頭放樣一節車，塗裝交給 `trains.js` 的 canvas |

做車之前先讀 `.claude/skills/rolling-stock/SKILL.md`：那裡寫了尺寸從哪裡來、
怎麼檢查、以及這兩條路各自踩過的坑。

```sh
pip install bpy                                   # Blender 當 Python 模組，CPU 就夠，不用 GPU
python3 -I tools/trains/bake_model.py <dense.glb> n700st-cab n700st-car
python3 -I tools/trains/build_train.py            # 全部
python3 -I tools/trains/build_train.py n700st-cab # 指定一款
```

## `bake_model.py`：密模型 → 遊戲資產

一個生成的模型是給人看一次的（N700ST 那個是 280,838 個三角形、17 MB 貼圖）。
形狀和塗裝要留，面數和貼圖大小不要。三步：**焊接再降面**、**重新攤 UV**、
**把密模型的顏色與遮蔽烘到輕模型上**。細節與每一步的坑寫在 skill 的第 2 節。

出處記在 `Web/CityView/public/models/trains/SOURCES.json`：降下來的檔案裡已經沒有原檔的
任何東西，而 Meshy 的條款要求輸出可被辨識為 AI 生成。

## `build_train.py`：從頭放樣

### 它負責什麼、不負責什麼

**不畫顏色。** 塗裝是 `trains.js` 畫在一張 canvas 上的，因為一條色帶要落在指定的高度這件事，
只有畫的做得到。這裡出的模型連材質都不帶（`export_materials="NONE"`）。

它出的是**形狀**和**遮蔽**：

- 車殼和 `trains.js` 的 `shellRing` 是同一條放樣，所以輪廓不會因為換了工具而變。
- 加上車側**站出來**的膠囊窗與塞拉門（凹進去沒有用，封閉的殼裡面看不見），
  以及轉向架、車輪、底盤、車頂冷氣。
- 用 Cycles 烘一張環境遮蔽，存成 8 bit 灰階 PNG。

兩層 UV：

| 層 | 怎麼來 | 給誰 |
| --- | --- | --- |
| `UVMap` | 照 `trains.js` 的 `uOf` 與斷面高度**寫死** | `material.map`，那張 canvas |
| `AO` | `smart_project` 打包，每個面有自己的 texel | `material.aoMap`（`channel = 1`） |

UV0 兩側共用同一塊圖，UV1 不行——烘焙要的是「窗板」和「窗板背後的車身」各有各的值。
`unwrap()` 寫完會跑 `audit()`，任何一個面落到別條去就直接中止。

### 加一款車（`build_train.py`）

在 `STOCK` 加一筆：車身長（= stock 的 `length` 減 0.6 m 車間縫）、車頭長、斷面 `shell`、
車窗與車門的尺寸。數字從參考庫的 catalog 或工程資料來，不要從生成的模型讀。
跑完之後給 `trains.js` 的 stock 加 `models`，再用
`.claude/skills/rolling-stock/preview.cjs` 算一次圖看過。
