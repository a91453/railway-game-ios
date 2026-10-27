# EMU3000 遊戲石板藍灰塗裝

使用者要求評估莒光藏青並「順手把EMU3000黑色部分改成適合遊戲風格的顏色」。莒光建議保留深藏青／米色，本輪不改。EMU3000車頭罩面、窗框與目的地等外觀黑色飾件改成既有 `Map3DPalette.tunnelLining` **#6E7487**；白車身、玻璃、綠松肩線、燈、鋼色保持。輪胎、雨刷、底盤、風擋折棚／連結器與弓機構使用拆出的舊炭黑 `hardwareColor`，沒有整車機構染藍。

改色增加遊戲風格與視覺區隔，**不宣稱換色能保證沒有侵權風險，也不是法律審查**。原始照片不取圖素、不散布品牌車號或個資，不送外部生成服務。

## 真版本與範圍

- 幾何／塗裝前版：使用者已接受第五版producer `66a515e8f84ddb5001bae2dd0ce5d79f49063113`，私庫 `691fa114c3cfad8b7c06f93df14913df6b93ed1b`、`emu3000-refresh-2026-10-25/revision-5/`。已查公開#1229／私#77均已合併，最新main的EMU配方與該版相同。
- 新配方：仍在 `Sources/GamePresentation/Map3DEMU3000.swift`，僅拆分塗裝／功能性材質與替換外觀色；所有16近遠單元、12節序列、已接受側形／正形、門窗、屋頂、走行與設備實際位置／法線／拓樸保持，沒有任何分色細分。
- 工作 issue #1309；自己的分支 `codex/emu3000-slate-2026-10-27`／私庫 `codex/emu3000-slate-assets-2026-10-27`，新互鏈draft見issue。原第五版完整包保留，不把新色稱為已接受。
- 莒光藏青 `ac4c1e1e`／私庫 `6b16d40b`、E500第三版、PP／E1000等其他模型不修改。E500與莒光展示比較直接讀原生、保留其bytes與producer；莒光不是已接受版本，僅遊戲色彩比較。

## 外觀與實際幾何證據

先實看原生黑／石板藍灰同相機、公尺尺度前後，再檢視近遠側／正／俯／斜配色、白模及剪影；檢查暖白肩部、風擋、圓燈、側窗和綠松細線。石板藍灰比舊炭黑柔和，深玻璃與細緣仍可辨；幾何通過不代替外觀判斷。外觀自檢不是使用者接受。

`tools/emu3000-slate/paint-audit.py`讀真正第五版與新M3DM，每個52-byte三角依序核flags、三頂點位置bytes、拓樸／三角數及重算法線；只允許舊炭黑→石板藍灰，其他色不變。Z≤1.25m的走行／底盤、Z≥3.75m的屋頂機構及實際細雨刷連通體完整記錄保持；實際5mm頂點移動與錯改非炭黑反例拒收。編組位置／朝向表亦同第五版，不只看bounds。

`capture`／`coexistence`比最新main f6c6afa3的完整位置／法線／色／layer payload，允許16個專用EMU顯示單元及直接EMU端車的已稽核塗裝變更，其他模型逐bytes保持。塗裝新色並非舊版的完全payload相同；受保護範圍分開說明。

可靠工程資料、照片推估與另一側細節限制沿用[第五版製作紀錄](../emu3000-refresh-2026-10-25/README.md)，本輪不重新確認工程精度。新色的基礎色對比另見 `docs/UI_THEME.md` 自有一節，不把未打光數字當所有像素／真機結果。

## 驗證、接入與交接

Linux Swift6.4 warnings-as-errors；原有52項相關XCTest（1項既有成本skip）與實際結果見私包evidence。全量重出原生／GLB／各單元七向、完整12節、四向配色／白模／剪影、真正第五版前後與同尺度風格、可離線旋轉縮放與實際下載viewer、來源／bounds／三角／SHA及ZIP；完整包在私庫 `Railway/game-art-previews/docs/art/emu3000-slate-2026-10-27/`。公開僅自有配方／工具／文件及一張總覽。

原生讀回、封閉有向邊／正體積、玻璃支持／可見性及浮埋反例、八輪貼軌／淨空、Swift／JS完整組裝payload、獨立Blender匯入、PNG完整解碼／透明不裁邊、Chromium viewer真操作與下載SHA、ZIP完整解壓逐檔bytes各自記錄。抽樣支持／射線不等於完整碰撞。修改後全量重出，不把先行候選圖混充最終producer。

**營運**：維持既有EMU3000專用近／遠接點、車數、列車包解鎖及fallback。本PR合併後，使用專用EMU3000模型的近遠營運畫面會顯示石板藍灰；未解鎖的通用回退、900m後盒形及其他車種不由本輪換色。遊戲更新前不會改已安裝版本。GameCore、存檔、golden/replay、玩法不動。

UNVERIFIED：人工Simulator外觀、真機Metal／FPS／記憶體、輪轉／門／弓動畫、懸吊與完整動態碰撞。最新同producer CI看新draft checks，不把本機驗證寫成CI成功。不推main、不合併／auto-merge／TestFlight。

重建：[工具README](../../../tools/emu3000-slate/README.md)。接手先核source-record／manifest的真producer與原生SHA，重用第五版作真前版；後續若改色或幾何須另留本版並全量重出。
