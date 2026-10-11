# tools/trains — 在 Blender 裡建城市畫面的列車

`build_train.py` 用 Blender 建一節車、烘焙環境遮蔽、匯出一個 GLB，寫進
`Web/CityView/public/models/trains/` 並併入那裡的 `index.json`。
城市畫面（`Web/CityView/src/world/trains.js`）的 stock 加上 `models: { cab, car }` 就會用它。

做車之前先讀 `.claude/skills/rolling-stock/SKILL.md`：那裡寫了尺寸從哪裡來、
怎麼檢查、以及這條路踩過的坑。

```sh
pip install bpy                                   # Blender 當 Python 模組，CPU 就夠，不用 GPU
python3 -I tools/trains/build_train.py            # 全部
python3 -I tools/trains/build_train.py n700st-cab # 指定一款
```

## 它負責什麼、不負責什麼

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

## 加一款車

在 `STOCK` 加一筆：車身長（= stock 的 `length` 減 0.6 m 車間縫）、車頭長、斷面 `shell`、
車窗與車門的尺寸。數字從參考庫的 catalog 或工程資料來，不要從生成的模型讀。
跑完之後給 `trains.js` 的 stock 加 `models`，再用
`.claude/skills/rolling-stock/preview.cjs` 算一次圖看過。
