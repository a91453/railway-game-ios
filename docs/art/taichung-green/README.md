# 台中捷運綠線 studies：第三版外觀修訂

使用者重新提供四張實車照片要求確認。重新打開第二版原生正／側／斜圖後，確認車頭與黑罩過方、綠帶過灰且不連續、下裙方塊及連結器區實心感都是明顯偏差；撤回前版將它們僅列為細節簡化的寬鬆自評。第三版已實際改原生配方，技術通過仍不代表使用者接受。

[本批總覽](overview.png) · [來源及授權紀錄](source-record.json) · [驗證證據](verification.json) · [專用重建／驗收](../../../tools/taichung-green/README.md) · [素材draft #21](https://github.com/a91453/railway-assets-private/pull/21)

實際製作者：**Codex**。本輪從最新main `12e4590a` 開獨立 `codex/taichung-green-shape-2026-10-28`；前公開#1430已由規劃合併。本型只在studies，`tmrt → metroGeneric`兩車營運映射、GameCore、存檔、fixtures、購車、班表、動畫均未改。

## 本輪改動與照片對照

四張重新提供的聊天照片已逐張目視，無可下載原檔／作者／SHA，不重發圖素。並重新使用先前實際下載的中捷官方實車、川崎工廠實車與Blair南屯站原圖作旁置比較；逐圖URL／作者／日期／授權及SHA見source-record。川崎2011藍帶效果圖與K.Y.Chung插畫另列，只觀察，不冒充實車或工程圖。

| 方向 | 照片顯示／本輪修正 | 仍不足或資料缺口 |
|---|---|---|
| 正面 | 深罩與風擋上緣有弧度、下部圓收；改密輪廓並修裁切後完整面積法線，白U下緣形成上拱深色唇；燈改有邊緣的雙圓鏡片 | FRP肩部／燈座仍低面數，不聲稱精準復刻 |
| 側面 | 上下綠帶連續繞肩；改用遊戲既有綠色底色#7CC058，避開街道家具淡化；加接回腰帶的曲線肩帶 | 尚未量得真實塗裝曲線；沒有靠改色宣稱幾何全同 |
| 前斜 | 下裙為左右弧形頰板，中央開口露出連結器；實作凹孔、變暗車底、補吊座／轉向架枕座 | 隱藏管線／底箱／精確支承仍簡化，未冒稱工程資料 |
| 俯視 | 官方示意及聊天俯斜照支持每車前後各一空調、兩車共四組，沒有集電弓 | 沒有完整正俯實車原圖；精確設備長寬及站位資料不足 |

車體、門窗與設備位置仍以本型獨立配方為主，沒有套三鶯／C371車頭或底架。C371僅在同一公尺場景／相機作風格比較。既有霧面頂點色、無照片貼圖、無商標；不以反光補錯形。

## 實車資料與模型契約

中捷官網每車22.17×2.98×3.78m、兩車44.34m，DM1／DM2，鋼輪鋼軌1435mm、第三軌750VDC、每車每側五組1500×1875mm雙門、每車兩組空調、FRP車頭／不鏽鋼車身。川崎原始合約確認36輛／18組、無人駕駛與第三軌。台灣車輛分工號碼僅有次級報導，沒有冒稱完成原廠一次查證；沒有替本型編造數字系列。輪徑、軸距、底箱、設備及鼻面細部均屬照片比例推估。

原生+X前／+Y左／+Z上，公尺、軌面Z0。四單元DM1／DM2近景各**3828**、遠景各**1848**三角；兩車**7656／3696**，由最終單元重建M3DAssembly，平移±11.085m、旋轉0／180°。單檔15000、單元20000、編組近240000／遠120000與遠少於近一半分開驗；未擴大loader限制。GLB只轉一次軸向。

## 真版本與重建

- 最終producer：[0b6d26dfac46e702550fc5e9d1afc7a7bc9af339](https://github.com/a91453/railway-game-ios/commit/0b6d26dfac46e702550fc5e9d1afc7a7bc9af339)。獨立checkout重建14份native／GLB／assembly／bin，全部逐bytes相同。
- 真正第二版producer `e525a29aa141f46162662e361037f4901d8ec77a`，素材提交 `61084334187422a4383e05e058fa4afc8d1073f8`。同相機／canvas／同bounds比較見私包`png/true-before-after.png`，不是事後重造前版或各自縮放。
- [完整第三版／viewer／20PNG／SHA／重建README](https://github.com/a91453/railway-assets-private/tree/codex/taichung-green-assets-2026-10-28/game-art-previews/docs/art/taichung-green/revision-3)。第二版重檔在同素材PR移除，保留PNG／README／來源／授權；用真commit恢復，不建ZIP或history/old/backup。
- 公開只有一張小總覽，本輪私庫20PNG，每張≤2MiB，單檔≤50MiB、PR新增≤200MiB，交付前依最新素材AGENTS跑asset_guard。

```sh
git checkout 0b6d26dfac46e702550fc5e9d1afc7a7bc9af339
tools/train-models/run.sh /tmp/tg --ids taichung-green-dm1,taichung-green-dm2,taichung-green-dm1-far,taichung-green-dm2-far --assembly-spec tools/taichung-green/assembly.json
node tools/train-models/package.mjs /tmp/tg
node tools/train-models/audit.mjs /tmp/tg
python3 tools/taichung-green/audit.py /tmp/tg
# 其他Blender／Swift編組／PNG／viewer命令見 tools/taichung-green/README.md
```

## 驗證與限制

本機Swift6.4 warnings-as-errors與最終12項本型／ModelPackSize／ModelTests通過；另13項含啟用記憶體報告通過，standard仍583模型／133.3MB。684份其他模型與最新main獨立匯出逐bytes相同、全部欄位FNV不變；hash鎖只改本型四項。最新main既有28項其他車款鎖值與實際欄位不符，仍記為全包鎖問題，沒有改別款值消紅。

六件拓樸／正體積／退化面／缺面反面／編組錯位反例；近遠獨立玻璃射線、八輪貼軌與淨空、屋頂中央支承、風琴接面、中央開口、凹孔及兩枕座／吊座內部材料探點。埋玻璃、抬輪、抬設備、縮風琴、封開口與逐件刪支承反例均拒收。真第二版四單元被新凹孔probe拒收。虛擬射線門檻是顯示模型約束，不是工程尺寸或全碰撞證明。

Blender4.3.2獨立匯入六GLB，Swift直接編組34056頂點、色值相同／最大位置差1.68µm；168PNG完整RGBA透明解碼，最終六件七向配色／白模／剪影與實車旁置目視；最終viewer真下載native／GLB／PNG SHA、旋轉／縮放／手機寬度及六張下載PNG完整解碼。file://管理政策阻擋，該transport仍UNVERIFIED；loopback HTTP與自含資料驗收通過。

四種狀態分開：**本型素材技術VERIFIED（限證據範圍）／使用者第三版外觀接受UNVERIFIED／營運接入UNVERIFIED／Simulator及真機Metal、效能、記憶體、動畫UNVERIFIED**。Linux通過不等於裝置驗證；本輪未接營運、不合併、不auto-merge、不TestFlight。最新head實際CI看本輪公開draft checks，不能以舊#1430綠燈代替。

配方／成品遵循 [LICENSE.md](../../../LICENSE.md)：Copyright2026 a91453，All rights reserved。第三方照片／插畫只觀察、不重發圖素，保留各自權利。
