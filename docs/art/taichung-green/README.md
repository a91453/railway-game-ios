# 台中捷運綠線：原生靜態展示第二版

本輪從公開 main `04f81f7a8ebffa94719785ce545f5e52e6aa7101` 獨立重建，配方為 Codex 製作。只追加 `Map3DModelPack.studies`，不增加 `standard` 常駐模型；既有 `tmrt → metroGeneric、2車` 營運接點完全保護。開工時三鶯 #1422 未合併（收尾已合main 9b9ad5c5，本分支已保留其追加）；工具 #1416/#1357、C371/C381 #1342 已合併，沒有搬三鶯分支或換色套其殼。

來源逐項網址、作者、日期、權利、下載 SHA、類別與缺口見 [source-record.json](source-record.json)。原圖只在暫存目視，不公開或打包。使用者附的 K.Y.Chung 插畫有 CC BY-NC-ND 標記，只觀察，不描圖、不重發；其他四張聊天照片沒有本機原檔／SHA。川崎產品頁的工廠圖是實車；2011 合約的藍帶圖是效果圖，不能當現行綠色實車依據。市府捷運工程局綠線頁的「車輛」連往中捷規格，另開啟該局頁面的實景合成背景，但不拿它量尺寸。

| 項目 | 已查證／模型處理 |
|---|---|
| 正式稱呼 | 中捷官網「電聯車」、川崎「緑線MRT電車 台湾 台中捷運」；採台中捷運中運量電聯車名稱，未冒填數字系列 |
| 製造 | 川崎合約主責36輛；Blair報導川崎／台灣車輛共同承造，分配號碼未獲原廠一次資料獨立確認 |
| 尺寸 | 官方每車22.17×2.98×3.78m，兩車44.34m；模型含門窗／連結器保持此外框 |
| 編組 | DM1、DM2，1號端朝外、2號端車間相對；各自單元本地+X為1號端，DM2組裝旋轉180° |
| 門窗 | 官方每車每側五組1500×1875mm雙門；四大客窗和端部窗帶按實車照片；兩側都有門 |
| 走行 | 1435mm鋼輪鋼軌、750VDC第三軌；每車兩轉向架／四軸／八輪，無集電弓 |
| 車頂 | 官方每車前後兩組空調；低矮銀灰罩、分格格柵；站位／尺寸是照片推估 |
| 端部 | FRP白U形圓肩、收底深罩、獨立玻璃、兩側上下圓燈、綠側帶轉肩、分離下裙及露出自動連結器 |
| 差異／缺口 | DM1/DM2底箱群分別簡化；隱藏設備身份、兩側精確不對稱、輪徑／軸距及鼻面尺寸均待工程資料，不能稱完整工程還原 |

四個最終合法M3DM單元：DM1/DM2各近3120、遠1512三角。近／遠完整兩車為6240／3024三角，使用M3DAssembly容器，從最終單元嵌入重建；不是把整列預覽bin冒稱可載入獨立檔。近單元≤15000格式／20000單元預算、遠少於近一半；全列另驗近240000／遠120000規則。固定平移+11.085／−11.085m、旋轉0／180°，軌面Z0，原生+X前／+Y左／+Z上，GLB軸向只轉一次。

## 重建及證據

[操作／專用驗收](../../../tools/taichung-green/README.md)；[編組資料](../../../tools/taichung-green/assembly.json)。真正producer、重建bytes與兩庫draft鏈結見下方交付紀錄及素材README。本對話已推第一版 ebf978be 為真正前版，第二版只延伸車間風琴，並新增縮回100mm的實際故障反例。

- Swift 6.4，warnings-as-errors build-tests；本型與ModelPackSize測試。以最終交付紀錄的實跑結果為準。
- 共用GLB／拓樸／缺面／反面／100mm編組錯位反例；本車玻璃射線、八輪逐一Z0和向上淨空射線、空調中央底面與真屋頂接觸；埋玻璃100mm、抬輪40mm、抬設備60mm反例。這些是幾何抽樣，不是全碰撞或工程支承認證。
- Blender 4.3.2獨立匯入六件GLB，查三角、軸向bounds及頂點色；Swift另讀交付單元直接組裝，與JS展開payload逐頂點比位置及全部色值。
- 完整PNG解碼／七向及白模剪影目視／互動viewer真下載SHA、producer獨立重建bytes、原有模型保護及CI依下方交付紀錄。

## 外觀與狀態

自檢：先看四向白模／剪影後修鼻端接合，再做薄門窗、弧面深罩、圓燈、綠色轉肩及設備。已逐件查看最終多視角，近遠保持同框。使用遊戲霧面頂點色，不帶真logo、貼圖或照片；C371只作同尺度風格比較。

尚不足：黑罩仍有低面數折線，綠色使用既有淡化遊戲色票，與照片鮮綠有差異；隱藏設備與左右底箱不對稱仍是簡化推估。不可將自檢視為使用者接受。

素材技術與證據見交付紀錄；**使用者外觀接受 UNVERIFIED、營運接入 UNVERIFIED（本輪未接）、Simulator／真機Metal／效能／記憶體／動畫 UNVERIFIED**。Linux WebGL不等於Metal。沒有更動GameCore、存檔、fixtures、購車、班表或動畫；draft不授權合併、auto-merge或TestFlight。

原創配方／輸出遵循公開庫 [LICENSE.md](../../../LICENSE.md)（Copyright 2026 a91453，All rights reserved）；外部來源只觀察，保留其權利，不把效果圖／照片再授權為本模型。

## 本批交付紀錄

- 公開 draft [#1430](https://github.com/a91453/railway-game-ios/pull/1430) ↔ 素材 draft [#21](https://github.com/a91453/railway-assets-private/pull/21)。
- 固定producer：[e525a29aa141f46162662e361037f4901d8ec77a](https://github.com/a91453/railway-game-ios/commit/e525a29aa141f46162662e361037f4901d8ec77a)。以該commit獨立checkout重建，14份native／GLB／assembly／bin全部逐bytes相同。
- [完整素材／20張預覽／viewer／SHA／重建README](https://github.com/a91453/railway-assets-private/tree/codex/taichung-green-assets-2026-10-28/game-art-previews/docs/art/taichung-green/revision-2)，最終PR約8.4MiB（含前版PNG），staged及committed asset_guard通過。公開只一張[總覽](overview.png)，合計21PNG。
- [技術證據](verification.json)：共用六模型audit、本車近遠射線與實際反例、Blender六GLB、Swift直接組裝27792頂點（最大位置差1.67µm、全部色相同）、168PNG完整解碼、最終交付viewer六模型日夜七向／旋轉／縮放／手機寬度／真下載bytes檢查均本機VERIFIED。file:// transport仍UNVERIFIED。
- 另以獨立main checkout匯出**680個既有原生檔**與本分支逐bytes核對，全相同；680個全頂點欄位FNV也相同，hash鎖只追加本型四行項目。
- 外觀已實看最終六件七向配色／白模／剪影，另同一公尺空間／相機並排C371作風格比較；不是照片相似度或使用者接受。
- 相容性擴查抓到studies總數原97漏新增4件，已補本型Role×2計數；模型及producer保持。

素材技術 **VERIFIED（限上述證據）**；使用者外觀接受、營運接入及裝置驗證皆 **UNVERIFIED**。不將綠燈解讀為使用者接受。

第二版真正前版為公開producer `ebf978be13e1be6eec1218389f596ff92137d6cb`／私庫`d90867d7`。本PR已刪revision-1重檔，只保留PNG／README／來源／授權。最終producer `e525a29a`，私包提交`61084334`。每單元只有36個位置頂點在風琴區改動；近景另有163個色值頂點因自動遮蔽重烘而變，遠景色值保持，不能說是全部其他payload不變。詳見revision-delta.json。

最終Swift6.4 warnings-as-errors與12項相關測試通過；另啟用記憶體報告的13項測試通過，standard仍583模型／133.3MB（單份模型資料，非真機實測）。最終viewer真下載原生／GLB逐bytes及SHA驗收見verification.json。完整CI／iOS以公開PR最新head checks為準，不拿舊head綠燈代替。

收尾因main前進發生三處衝突，已保留兩車款studies／計數和雙方HANDOFF。最新前置狀態：三鶯#1422已合，原工具#1416/#1357已合；本型沒有取用三鶯幾何。素材producer仍釘e525a29a，非把merge後工作區冒充舊producer。

依新合併手冊10.1，另在暫存把最終原生圖與原始來源照片並排實看（未重發第三方照片）：

| 方向／來源 | 照片／模型與仍有差異 |
|---|---|
| 正面／中捷official-front | 都是上寬下收深罩、寬白U及雙圓燈；模型罩下緣仍偏折線，白框下部與裙部偏幾何化；主要車型可辨，自檢不等於接受 |
| 側面／Blair南屯photo | 都有每側五組雙門、四大客窗和端部深窗帶、上下綠帶；模型綠色較淡、窗線與底箱較簡化，透視照片不能用作工程站位 |
| 斜視／川崎實車photo | 車頭下壓／肩帶、四空調兩車一致；模型肩帶轉折較直，設備格柵密度更低，沒有搬實車logo |
| 俯視 | 沒有來源完整正俯實車照片，資料不足；官方俯側示意只支援兩空調站區，不能冒充實車照片。聊天俯斜照片僅輔助、沒有可下載原檔SHA |

前置素材PR亦已實查：三鶯素材railway-assets-private#19於2026-10-28T12:23:54Z合併，head73fda55c；公開#1422於本輪收尾已合。不沿用其幾何。
