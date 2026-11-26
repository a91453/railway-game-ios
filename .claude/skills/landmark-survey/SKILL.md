---
name: landmark-survey
description: 地標與自然景點建模前先「量」：做或改任何地標（城、廟、神社、車站以外的名建築、橋、塔）或自然景點（瀑布、峽谷、海岸、梯田）的 3D 模型之前先讀。先從 OpenStreetMap 量輪廓、分段、高度標籤、會取代哪些建物、附近不能清的名勝，從標高資料量地面落差，再補平面圖、立面圖、照片，每一格寫來源；交件前跑自動檢查（大小對實測、從上面看封頂、異色共面、地坪）。Use before building, rebuilding or porting a landmark or natural-spot model for the 3D map (castles, temples, shrines, towers, bridges, falls, gorges), when a brief for one is written, or when a landmark「比例不對」「太小」「蓋到旁邊」「浮在坡上」.
---

# 地標與自然景點：先量再建

模型的「像不像」照 [model-look](../model-look/SKILL.md)；這份管它之前的一步：**尺寸、位置、地面先從真實資料量好，每一格寫來源**，做的人與審的人才有同一把尺。憑印象估的長寬高，審查一輪只能退「比例不對」，下一輪又估一次。

做法借自 Pocket City（April Zhu 的等角小城 skill，作者 2026-11-26 上傳的 11/25 版）：抓 OSM 時不切到名建築、每個名建築先找平面圖與立面圖與照片、每個畫面上的事實都要有讀過的來源、示意的另外列、每一層都要封頂、從六個方向加俯視看。**它的授權是 PolyForm Noncommercial 1.0.0（只限非商業）**，所以只學做法，程式一行都沒搬：`tools/landmark-survey/` 是這個專案自己寫的。

工作室怎麼派單、去哪找平面圖與照片、研究紀錄怎麼寫、審查怎麼審，在私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/landmark-survey.md`。有權限的 session 先讀那份。

## 1. 先查舊版

新建模前先查作者舊版有沒有現成模型（私有素材庫 model-look §6 與 `docs/studio/README.md` 第 1 項）。有的話用第 2 步量出的長寬高去對舊版目錄的尺寸，挑最接近的那份起手；舊版只稱「舊版」。

## 2. 量（`tools/landmark-survey/survey.py`）

```sh
pip install osmium numpy        # 一次
python3 -I tools/landmark-survey/survey.py --pbf kyushu.pbf \
    --lat 33.8845 --lon 130.8741 --name 小倉城 --dem gsi --out work/kokura-castle
```

- OSM 讀整份 extract（osmtoday.com，九州 355 MB；CLAUDE.md 的規則，不問 Overpass），九州約 46 秒；切下來的那塊存成 `osm-slice.json`，之後 `--slice` 一秒重跑。
- `--osm way/<id>` 直接指定；不給就找名字含 `--name` 的，再不給就取點下的建物。
- `--dem gsi`：國土地理院標高タイル（雷射 5 m，沒有時 10 m）；`--dem terrarium`：AWS 的 Terrarium（台灣、其他地方，約 30 m）。出處文字寫在輸出裡，照抄進 README 與遊戲的資料來源。
- 輸出：`survey.json`（輪廓公尺座標、面積、最小外接矩形 L×W 與長邊方位、OSM 的高度／層數／屋頂／顏色標籤與來源、`building:part`、會被取代的建物、附近有名的、輪廓下地面最低最高）、`plan.svg`（俯視平面，含等高線與 10 m 比例尺）、`survey.md`（同一份的表，加「還要補」的空格）。

讀結果時注意：

- **OSM 的 `height` 常常不對或只是某一段**，層數換算的高度標「推估」。總高以立面圖、官方資料為準，OSM 只是起點（小倉城：OSM 18.8 m，史料的總高約 23–25 m，[範例](#5-範例小倉城)）。
- **輪廓常把相連的部分包在一起**（大天守＋小天守＋入口、本殿＋拜殿）。L×W 是整片的外框；要拆成幾個量體，看 `plan.svg` 的形狀、`building:part`，再對平面圖。
- **國土地理院的 5 m 標高把石垣、台基、堤防都算成地面**。輪廓下落差大（小倉城 8 m）多半是天守台：決定模型含不含台基，寫進 README；不含就由地圖的地面接住，含的話台基照坡分層（私有 model-look §6 搬舊版的第 2 件事）。
- 「會被取代的建物」是模型站到、遊戲要清掉的；「附近有名的」一個都不能被清掉或蓋到（OSM 的有名＝有 wikidata／wikipedia／文化財、historic、tourism 景點的面）。名建築沒標好時自己補看。

## 3. 補：平面圖、立面圖、照片

`survey.md` 的「還要補」每一格填值與來源：總高、各層高度、屋頂形式與屋脊方向、屋頂主色（俯視照或航照）、牆與重點色、認得出的三到五個特徵、照片（正面、另兩側、俯視）。寫不到來源的就寫「示意」，選樸素的做法；不憑記憶。照片與研究紀錄放私有素材庫，不進這個公開 repo。

自然景點（瀑布、峽谷、梯田）也是同一套：`--dem` 給地形，OSM 給水道、步道、觀景台；標高資料把瀑布、窄溪、石階抹平成斜坡是常態，要從照片補落差與寬度，標「示意」。

## 4. 交件前自動檢查（`tools/landmark-survey/landmark_check.py`）

```sh
uv run --with numpy python -I tools/landmark-survey/landmark_check.py model.glb \
    --survey work/kokura-castle/survey.json --md model-check.md
```

查：離地 1 m 外框對實測 L×W（±5 %）、總高對有來源的高度（±5 %）、從正上方看沒有看到背面或圍起來的空洞（每一層封頂）、異色共面與近共面（`port_check.py` 同一套）、退化面、三角形上限、沒有自帶地坪、地面落差。一項不過不送審；表照抄進送審的 REQUEST.md，審查就不用自己重量這些，專心看照片像不像。故意開著的天井給 `--allow-open <m²>`，碼頭這類真的要地坪的給 `--allow-ground-plate`，並在 README 寫原因。

測試：`uv run --with numpy python -I tools/landmark-survey/test_landmark_survey.py`。

## 5. 範例：小倉城

私有素材庫 `game-art-previews/docs/art/jp-kokura-castle-2026-11/`（三縣景點 JP-CASTLES 派單前的第一步）：OSM 輪廓 55.3 × 27.9 m 其實是大天守加小天守與入口，主體 29.2 × 27.9 m；OSM 高度 18.8 m 比史料的總高少 4–6 m；國土地理院 5 m 標高在輪廓下落差 8.2 m，是天守台。三件事不量，都要到審查才會被退。
