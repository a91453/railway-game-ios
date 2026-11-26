# FINLAND-MML-BUILDINGS 交接（決策 1009）

2026-11-26，分支 `claude/project-thread-b5jxfx`。存檔、golden、GameCore 不動。

## 進度

- 做到：工具（`tools/rovaniemi-map/mml_buildings.py`、`build_rovaniemi_buildings.py` 改寫）、羅瓦涅米包 `buildings.pmtiles`
  （舊格式 `footprints/2`）、`StoreysFrom.mml`、資料來源畫面、測試、決策 1009。
- 已驗證（Linux 本機）：`swift build --build-tests -Xswiftc -warnings-as-errors` 無警告；RovaniemiBuildingsTests、
  RovaniemiRailwaysTests、Map3DFootprintsTests、DataSourceCredits*、Map3DMapLoadReport 全過；`doc_numbers.py --check` 過。

## 要等

1. 「縮小地圖包下載大小」（決策 1005，分支 `claude/project-thread-2mh2fd`）合併後：`git merge origin/main`，
   照 `tools/rovaniemi-map/README.md` 5b 重跑建物（`overseas_buildings.py` 的 metadata 要用 `tiles.WRITTEN_EXTENT`，
   `build_rovaniemi_buildings.py` 同樣改），再跑上面的測試。
2. #2723（羅瓦涅米人口，決策 1007）合併後：人口是照建物樓地板分的，建物換了要重跑 `finland_census_grid.py build`；
   建物的「猜」又照人口，兩個各跑一次就好，不要來回。

## 下一張：台灣官方樓高（作者：官方優先，都不行才 Overture）

查過（2026-11-26）：

- **國土測繪中心全國三維建物模型：不能用。** 要付費購買（LOD1 每公頃 4 元／加值型 8 元），申請書寫用途，
  《測繪成果申請使用辦法》第 8 條「不得移作申請目的以外之使用」「非經產製或提供之機關同意，不得自行轉錄、轉售或贈與」；
  加值型只給機關、團體；I3S／3D Tiles 介接服務的條款是「不可移轉的，並且只能用在宣傳或是表示您使用的是本服務」。
  沒有找到政府資料開放授權。要用得由作者以團體名義申請加值型並取得轉散布同意，這是作者的事，不是工作串能做的。
- **各市使用執照／建照開放資料：可用（政府資料開放授權第 1 版，可商用）**，有地上層數與建築物高度，但只有地址或地號、
  沒有座標：臺南市使用執照（data.gov.tw 121026）、臺北市歷年使用執照摘要（128203）、臺中市建築執照存根（108507）、
  新北市建築執照存查（123639）。另外臺中建物圖（2022、2024、2025）與臺北建照套繪（151936）已經在用。
  要接得把地址對到門牌坐標（各市門牌坐標開放資料，例：高雄市 113 年門牌坐標 TWD97），再對到建物輪廓。
- 高雄、桃園沒找到有層數的開放資料集，還要再查（data.kcg.gov.tw、桃園市資料開放平臺）。
