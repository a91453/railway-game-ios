# 研究證據索引

主報告：[PEAKLINE_MAP_ENGINE_STUDY.md](../PEAKLINE_MAP_ENGINE_STUDY.md)。日期2026-10-19；全部執行結果均來自Linux，沒有iPhone效能結果。

- `PACKAGES.md`／`packages.csv`／`packages.json`：附錄C 141列。registry只確認版本及授權metadata；包內查核另見`crate-package-audit.json`（20包）。
- `SOURCES.md`／`sources.csv`／`sources.json`：附錄D 26列及E01–E04。原始入口與解析後入口分列；頁面200不是模型下載成功。
- `glb-metrics.json`、`reference-bake.json`、`ktx-metrics.json`：普通GLB、靜態meshopt、量化／KTX2／skin的各階段數據；scratch來源函式修改與正式工具分開。
- `ordinary-comparison.png`：已在公開repo的Meshy公車之CPU固定視角研究圖，AI生成來源沿用原素材README與`tools/meshy/generated.json`；沒有進App。
- `worldcover-jiji.tif`、`worldcover-metrics.json`、`worldcover-comparison.png`：官方WorldCover2021 v200的集集裁切與既有資料比較；並非同期真值或App截圖。
- `compare_worldcover.py`、`python-requirements.txt`：離線分類比較的重現程式。只讀repo，寫指定輸出目錄；本研究沒有加正式地圖工具的依賴。
- `acquisition.json`／`hk-acquisition.json`／`official-http.json`：取得路徑、版本、SHA及HTTP結果；不含下載API參數值。
- `offline-package.json`／`offline-package-lock.json`：**初版歷史環境**，含functions及間接LGPL；保留以稽核原減面／反量化數據，不再推薦安裝，不代表repo已批准此整棵樹。
- `bridge-package.json`／`bridge-package-lock.json`：修正後的MIT-only靜態重跑環境；複製到scratch並命名package.json／package-lock.json，Node22執行`npm ci --ignore-scripts`。全樹只有五包，逐包LICENSE SHA見`bridge-license-audit.json`；不是App依賴或完成的正式工具。
- `bridge-replay.json`：不用functions的12節點靜態重跑，三角形payload與原實驗逐byte相同；非AI來源仍用scratch函式。
- `supplement-review.json`：#820補充的查核基準、參考WorldCover檔案SHA與manifest；香港樣本未在本環境重現。

原始私有參考GLB、原檔對照與加工腳本留scratch／私有交付，依HANDOFF §3及art-style §7不進公開repo。主報告保留SHA、步驟與參數。

## 工具授權記錄

實際研究使用的版本與上游：

| 元件 | 版本／授權 | 官方來源與本次用途 |
| --- | --- | --- |
| glTF-Transform core、extensions | 4.5.1；MIT | https://github.com/donmccurdy/glTF-Transform/tree/v4.5.1；NodeIO、extensions；新靜態重跑只用core清理引用，逐包LICENSE SHA見bridge稽核 |
| property-graph、ktx-parse | 4.1.0、1.1.0；MIT | bridge lock的兩個間接依賴；已讀MIT正文與記SHA |
| functions與其影像依賴（歷史） | functions4.5.1本身MIT；間接libvips為LGPL-3.0-or-later | 原減面／反量化環境；初版漏查間接授權已修正，不列入推薦工具或MIT-only重跑 |
| meshoptimizer | 1.3.0；MIT | https://github.com/zeux/meshoptimizer/tree/v1.3；官方JS/WASM decoder、encoder探針及simplifier；讀過包內LICENSE.md（Arseny Kapoulkine） |
| KTX-Software | 4.4.2；多授權，詳主報告§7 | https://github.com/KhronosGroup/KTX-Software/releases/tag/v4.4.2；只在scratch轉出3張PNG；二進位與庫沒有提交／打包 |
| Node | 22.14.0；MIT及其第三方告示 | https://nodejs.org/en/blog/release/v22.14.0；執行環境，未再散布二進位 |

MIT元件允許商用、修改及散布，散布其程式時保留版權與許可告示；輸入模型保留自己的權利與來源，不由工具授權涵蓋。研究安裝的npm間接套件各自版本／授權可在lockfile查核；本次無任何npm程式隨App交付。初版把直接包MIT過度概括到整棵樹，已更正；新的五包MIT組合才是沿用HANDOFF決策的推薦入口。正式實作仍須把manifest、lockfile及README放在`tools/`自己的工具目錄。

Python比較器的套件僅在scratch venv使用；版本在requirements記錄，未vendor其程式或二進位。主要為rasterio（BSD-3-Clause）／GDAL（MIT系告示）、NumPy（BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0）、Matplotlib（其PSF衍生授權及第三方告示）／Shapely（BSD-3-Clause）、pmtiles（BSD-3-Clause）、mapbox-vector-tile（MIT）。現有資料工具已採用的套件不因這份研究變成App依賴；研究環境完整freeze亦含未被最終比較器使用的探查套件。

## 資料署名與修改

© OpenStreetMap contributors, ODbL 1.0，https://www.openstreetmap.org/copyright 。比較使用App既有PMTiles、分區與水域的分類取樣，不以Peakline的重製資料庫作來源。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. CC BY 4.0，https://esa-worldcover.org/en/data-access ，https://creativecommons.org/licenses/by/4.0/ 。2021 v200資料的本次修改：集集120.76–120.82E／23.80–23.86N裁切、分類mask、多數重採樣與研究圖；沒有改遊戲水域、建造或農地規則。引用：Zanaga et al. (2022), ESA WorldCover 10 m 2021 v200, https://doi.org/10.5281/zenodo.7254221 。
