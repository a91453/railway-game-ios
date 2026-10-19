# 研究證據索引

主報告：[PEAKLINE_MAP_ENGINE_STUDY.md](../PEAKLINE_MAP_ENGINE_STUDY.md)。日期2026-10-19；全部執行結果均來自Linux，沒有iPhone效能結果。

- `PACKAGES.md`／`packages.csv`／`packages.json`：附錄C 141列。registry只確認版本及授權metadata；包內查核另見`crate-package-audit.json`（20包）。
- `SOURCES.md`／`sources.csv`／`sources.json`：附錄D 26列及E01–E04。原始入口與解析後入口分列；頁面200不是模型下載成功。
- `glb-metrics.json`、`reference-bake.json`、`ktx-metrics.json`：普通GLB、靜態meshopt、量化／KTX2／skin的各階段數據；scratch來源函式修改與正式工具分開。
- `ordinary-comparison.png`：已在公開repo的Meshy公車之CPU固定視角研究圖，AI生成來源沿用原素材README與`tools/meshy/generated.json`；沒有進App。
- `worldcover-jiji.tif`、`worldcover-metrics.json`、`worldcover-comparison.png`：官方WorldCover2021 v200的集集裁切與既有資料比較；並非同期真值或App截圖。
- `compare_worldcover.py`、`python-requirements.txt`：離線分類比較的重現程式。只讀repo，寫指定輸出目錄；本研究沒有加正式地圖工具的依賴。
- `acquisition.json`／`hk-acquisition.json`／`official-http.json`：取得路徑、版本、SHA及HTTP結果；不含下載API參數值。
- `offline-package.json`／`offline-package-lock.json`：**研究證據用manifest**。要重跑，複製到scratch並改名package.json／package-lock.json，以Node22執行`npm ci --ignore-scripts`。它們不是App依賴，也不是已經完成的正式轉檔工具。

原始私有參考GLB、原檔對照與加工腳本留scratch／私有交付，依HANDOFF §3及art-style §7不進公開repo。主報告保留SHA、步驟與參數。

## 工具授權記錄

實際研究使用的版本與上游：

| 元件 | 版本／授權 | 官方來源與本次用途 |
| --- | --- | --- |
| glTF-Transform core、extensions、functions | 4.5.1；MIT | https://github.com/donmccurdy/glTF-Transform/tree/v4.5.1；NodeIO、extensions、prune／dequantize／weld／simplify；讀過安裝包LICENSE，版權告示留在scratch套件 |
| meshoptimizer | 1.3.0；MIT | https://github.com/zeux/meshoptimizer/tree/v1.3；官方JS/WASM decoder、encoder探針及simplifier；讀過包內LICENSE.md（Arseny Kapoulkine） |
| KTX-Software | 4.4.2；多授權，詳主報告§7 | https://github.com/KhronosGroup/KTX-Software/releases/tag/v4.4.2；只在scratch轉出3張PNG；二進位與庫沒有提交／打包 |
| Node | 22.14.0；MIT及其第三方告示 | https://nodejs.org/en/blog/release/v22.14.0；執行環境，未再散布二進位 |

MIT元件允許商用、修改及散布，散布其程式時保留版權與許可告示；輸入模型保留自己的權利與來源，不由工具授權涵蓋。研究安裝的npm間接套件各自版本／授權可在lockfile查核；本次無任何npm程式隨App交付。這是HANDOFF既定授權的研究驗證，正式實作仍須把manifest、lockfile及README放在`tools/`自己的工具目錄。

Python比較器的套件僅在scratch venv使用；版本在requirements記錄，未vendor其程式或二進位。主要為rasterio（BSD-3-Clause）／GDAL（MIT系告示）、NumPy（BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0）、Matplotlib（其PSF衍生授權及第三方告示）／Shapely（BSD-3-Clause）、pmtiles（BSD-3-Clause）、mapbox-vector-tile（MIT）。現有資料工具已採用的套件不因這份研究變成App依賴；研究環境完整freeze亦含未被最終比較器使用的探查套件。

## 資料署名與修改

© OpenStreetMap contributors, ODbL 1.0，https://www.openstreetmap.org/copyright 。比較使用App既有PMTiles、分區與水域的分類取樣，不以Peakline的重製資料庫作來源。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. CC BY 4.0，https://esa-worldcover.org/en/data-access ，https://creativecommons.org/licenses/by/4.0/ 。2021 v200資料的本次修改：集集120.76–120.82E／23.80–23.86N裁切、分類mask、多數重採樣與研究圖；沒有改遊戲水域、建造或農地規則。引用：Zanaga et al. (2022), ESA WorldCover 10 m 2021 v200, https://doi.org/10.5281/zenodo.7254221 。
