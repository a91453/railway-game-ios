---
name: estate-kit
description: Generate player-owned amusement, hotel, residential and commercial buildings with native meshes, GLB, seven transparent views and reusable scene layouts.
---

# 自有建築與遊樂設施

先讀 `CLAUDE.md`、`docs/HANDOFF.md`、art-style、station-kit，以及工作登記 #1041（#231 已達留言上限）。登記自己的新增範圍，不改 GameCore、存檔、Golden、地圖接入或其他代理檔案。

`Map3DEstateKit.Part`：24 種素材，leisure / hotel / residential / commercial 各 6。木馬、摩天輪為靜態完整設施；不把座艙、馬匹、樓層或配色計為其他素材。`Example` 有 4 個街區，各重用該類 6 件。暖黃使用既有 player / playerRoof，白牆、淡藍窗、平塗頂點色，不加品牌。沒有新增遊戲建造規則或自動註冊到地圖。

## 配方與重建

- `Map3DEstateKit.swift`：目錄、按需建模、安裝面與接點。
- `Geometry.swift`：封底 prism / frustum、barrel、實牆窗帶、接柱雨棚。
- `Leisure / Hotels / Residential / Commercial.swift`：四類獨立輪廓。
- `Examples.swift`：同一份原生座標 placements 供組景與 manifest 使用。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/estate-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/estate-kit-2026-10-23
```

需要既有 Node、Python/Pillow、Playwright、Chromium；不新增依賴。`CHROMIUM_PATH` 可覆寫瀏覽器。大型輸出必須在公開 checkout 外。Swift 6.4、warnings-as-errors；重建跑本 kit、StationKit、ModelFile 三個 suite 與四個 GLB Node tests，完整 suite 交 CI。修改配方後重新匯出 native / GLB / 圖片。render cache 僅於原生、renderer 和七張 PNG SHA 全相同時重用。最終公開 producer commit 乾淨後再跑 `bundle.py`，確認 source.json working_tree_dirty=false。

## 接點與構造

內部 builder：x 前、y 上、z 右，box y 是底。原生模型／接點：x 前、y 左、z 上，公尺。mount=(0,0,0)，朝下，對齊地面；approach 是基地前緣、z=0.16 的接近點，朝前，並非門洞或通行路徑。每件基地實心厚 0.16。組景放置 z=0.16，在組景地坪上方。角度為俯視順時針：x'=c*x+s*y，y'=-s*x+c*y。不要再轉軸一次。

窗必須有實牆／背板；雨棚柱接到屋面下緣。摩天輪吊架連接座艙頂板與輪緣 pivot，座艙前移避開輻條；輪軸穿過兩輪與 A 字支架。木馬以實際豎桿接地台與屋頂。空橋伸入兩端塔牆；架空走廊最外緣必須落在地面支柱上。屋頂花台只放在實際退台／屋面上，屋頂棚四角均有柱。

看全部 directions、分類總覽、examples、undersides、style-checks，再操作 viewer 看背面與底面。幾何 SHA 或 WebGL 成功不能代替人工檢查，也不能宣稱 Metal／效能／碰撞／室內導航／經營規則／地圖接入完成。發現接點錯誤，先留會失敗的幾何測試再修正。

## 私有來源與交付

新批次 provenance.json 保留逐件來源路徑、SHA、目錄尺寸與重組方式；REFERENCE_ASSET_LICENSE.txt 保留實際授權，不宣稱原資產開源。來源先查 MODEL_CATALOG 與 ASSET_LICENSE，再讀實際 factory，wrapper 另追實作；未找到輪式遊樂設施配方的缺口明列為原創。不公開原 factory、模型、貼圖或品牌，不傳到外部生成服務。

公開只放新配方／工具／測試／skill／文件、一張 overview 及小型驗證 JSON。私有放全部模型、圖、viewer、來源對照、ZIP。兩庫 draft PR 互連，Agent: Codex trailer，更新 #1041；不推 main、不合併、不啟用 auto-merge。後續要加素材以新批次為主，不悄悄改變已匯出 manifest 的既有 ID。
