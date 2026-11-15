# 舊材質圖 → 遊戲建築色票對照（t003 第 4 輪）

給之後「批次換一般建築」直接用。來源是本機工作室 t003 第 4 輪的分類（9,453 張舊材質圖）：`classify.py` 的規則（第 3 輪），加上 `clip_refine.py` 用 CLIP 修正立面、俯視圖、其他三類（`clip-override.csv`，507 張）。舊材質圖是作者自己的作品；這裡只放檔名和顏色，不放貼圖、不放本機路徑。

重做（作者的 Mac；CLIP 在本機跑，貼圖不會傳出去）：

```sh
uv run --with pillow --with numpy python tools/texture-palette/classify.py --out <r3>
uv run --with open_clip_torch --with torch --with pillow --with numpy --with scikit-learn \
    python tools/texture-palette/clip_refine.py --rules <r3>/palette-map.csv --out tools/texture-palette/t003/clip-override.csv
uv run --with pillow --with numpy python tools/texture-palette/classify.py --override tools/texture-palette/t003/clip-override.csv --out <r4>
python3 -I tools/texture-palette/building_map.py --palette-map <r4>/palette-map.csv --out tools/texture-palette/t003
```

| 檔案 | 內容 |
| --- | --- |
| `building-map.csv` | 建築類 1,416 張：類別、狀態、主色與第二色，以及它們在遊戲裡的位置（Swift 寫法，例如 `Map3DPalette.cityConcreteWalls[3]`） |
| `manual-review.csv` | 要人工看的 235 張：瓦／屋面 65、地面／鋪面／草地 141、磚 29。工具給的建議色只是參考，「人工判定」欄留空，不猜 |
| `clip-override.csv` | CLIP 改了類別的 507 張（其他 → 立面 285、其他 → 地圖 129、地圖 → 立面 57、立面 → 地圖 36） |

## 狀態

| 狀態 | 意思 | 張數 |
| --- | --- | ---: |
| 可直接用 | 主色是遊戲裡已有的色票 | 725 |
| 色票未進遊戲（要提新色） | 主色是 t001 色票裡有、`Map3DPalette` 還沒有的色：鋼 #8A9099 271、紅磚 #B07A62 32、木頭 #9A7657 25、深色／窗 #2B2F36 24、洗石子 #E3DCCB 11 | 363 |
| 沒有合適色票（要提新色） | 最近的色票 ΔE > 15。工具建議的新色：#656461（145 張）、#5C412A（28）、#2F2B1F（13）、#698363（13） | 177 |
| 主色不明（另議） | 立面主色面積比 < 0.25，不給色 | 57 |
| 人工看 | 瓦／屋面、磚整類（地面不是建築，只在 `manual-review.csv`） | 94 |

依 model-look §6：沒有接近的色，在 PR 提出要加的色票，不直接用原色。所以「要提新色」的 540 張，要等批次換建築那個 PR 先決定加哪幾個色進 `Map3DPalette`。

## 各類

| 類別 | 可直接用 | 未進遊戲 | 沒有合適 | 主色不明 | 人工看 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 整面建築立面 | 509 | 238 | 144 | 57 | |
| 清水模／水泥 | 118 | 46 | 11 | | |
| 石材／洗石子／磁磚 | 76 | 30 | 10 | | |
| 金屬／鐵皮 | 18 | 8 | 3 | | |
| 木頭 | 4 | 13 | 7 | | |
| 玻璃／窗 | | 28 | 2 | | |
| 瓦／屋面 | | | | | 65 |
| 磚 | | | | | 29 |

可直接用的主色最多的是暖灰水泥 `cityConcreteWalls[3]`（226）、舊水泥灰 `cityConcreteWalls[5]`（118）、混凝土 `Map3DPalette.concrete`（115）、白灰水泥 `cityConcreteWalls[4]`（48）。

## 各輪的類別錯誤率（工作室 Codex B 獨立抽樣）

| 輪 | 改了什麼 | 全體抽樣類別錯 | 換類抽樣改對 |
| --- | --- | --- | --- |
| 2 | 立面、屋面、地面、地圖規則 | 13/90 = 14% | |
| 3 | 黑底亮點的夜間圖收回「夜間燈光」（354 張） | 10/60 = 16.7%（95% 區間 9%–28%） | 27/30 |
| 4 | CLIP 修立面／俯視／其他（507 張） | 9/60 = 15.0%（95% 區間 8%–26%） | 36/40 |

不同輪用不同的抽樣種子，全體錯誤率的差距在誤差範圍內；改善看得最清楚的是換類抽樣（改的那些大多改對了）和建築類的涵蓋：立面從 642 張增加到 948 張。

## 還有哪裡不好

- **類別仍未過 10% 的門檻。** 第 4 輪抽到的 9 張錯，第 3 輪就都已經存在。它們散在很多類：招牌被分到「其他」（2 張）、草地被分到「其他」、金屬網和百葉被分到「其他」或屋面、立面被分到「其他」、地圖或石材，還有一張俯視圖被分到地面。CLIP 這輪只修了立面、俯視、其他三類，沒有碰這些。
- 「立面 → 其他」「地圖 → 其他」兩個方向沒有做：抽看時大約一半是改錯的。
- 有混合拼版（同一張圖裡同時有俯視和立面），這種圖本來就不好歸類。
- 磚收得太嚴（29 張），有幾張真的磚在「其他」「招牌」「木頭」；這 29 張全列在人工看的清單裡。
- 同一個 hex #8A949E 在遊戲裡有兩個位置（`hallRoofs[2]` 銀灰鐵皮、`cityOfficeWalls[5]` 深灰鋁板），表照 t003 給的色名對。
