# 台中捷運綠線 studies：第四版正面分色

使用者指出第三版正面塗裝不自然。重新打開中捷官方實車、Blair南屯站原圖及真正第三版原生圖，確認少了肩部接到燈座的深色兩頰，造成整片白臉與孤立燈座。本輪只補正面分色及相接肩帶，保留車體、玻璃、燈與設備幾何。

[本批總覽](overview.png) · [來源／授權](source-record.json) · [驗證](verification.json) · [重建／驗收工具](../../../tools/taichung-green/README.md) · [公開draft #1437](https://github.com/a91453/railway-game-ios/pull/1437) ↔ [素材draft #21](https://github.com/a91453/railway-assets-private/pull/21)

實際producer：**Codex／498d85ef234a00345b4b024c4aa0e6783d73b933**。沿用尚未合併的`codex/taichung-green-shape-2026-10-28`，分支起點main12e4590a；本輪fetch最新main7bc5539a、重讀規則，沒有衝突或新工具依賴而未合main。仍只有studies，`tmrt → metroGeneric`兩車營運映射、GameCore、存檔、fixtures、購車、班表及動畫保持。

## 修正與限制

實車的白色U框介於中央黑罩與外側深色兩頰之間，兩頰接到燈座，上肩才接綠帶。第四版新增貼合本車既有曲面的兩頰／綠肩面片，重分肩帶，修掉前側白縫。未改中央黑罩、風擋、燈位、下裙與設備；新增面會影響相鄰車頭烘焙遮蔽，不聲稱整個車頭所有色值不變。

實車綠色到深藍的柔和過渡，在遊戲裡簡化為既有色票的乾淨色塊；未放照片貼圖、漸層貼圖、真實商標。分色曲線仍是照片推估，並非工程尺寸。肩部折面與曲率仍簡化；沒有以技術測試宣稱外觀已被接受。C371／三鶯只作風格／工具參考，本車沒有搬其車頭或底架。

來源沿用已實際下載、開啟的中捷原圖、川崎工廠照片、Blair實車原圖與官方示意。URL、作者、日期、SHA及授權逐張見source-record；川崎2011藍帶圖是效果圖，K.Y.Chung圖是插畫，均不作現況照片。聊天照片作者與原始URL不明，沒有補造；沒有重發第三方圖素。

## 模型與真版本

中捷官方每車22.17×2.98×3.78m、兩車44.34m、DM1／DM2、每車每側五組雙門、1435mm鋼輪鋼軌、750VDC第三軌、每車兩組空調、FRP頭／不鏽鋼身。川崎原始合約確認36輛／18組與無人駕駛。台灣車輛分工僅次級資料，未完成一次來源核對；沒有編造數字車型。輪徑、軸距、底箱、曲率與隱藏設備仍是視覺推估。

原生+X前／+Y左／+Z上、公尺、軌面Z0。DM1／DM2各近**4804**、遠**2208**三角，兩車**9608／4416**；由最終單元M3DAssembly重建、±11.085m與0／180°。單檔15000、單元20000、編組240000／120000及遠景少於近景一半分開驗，GLB軸向只轉一次。

真前版producer **0b6d26dfac46e702550fc5e9d1afc7a7bc9af339**／素材 **1adbab9f0f03ca7636abfc3ea5b7f0118e156fca**。私庫`revision-4/png/true-before-after.png`用真正第三版與第四版，同bounds／相機／canvas／尺度；不是事後重造前版。

[本輪完整素材／viewer／20PNG／SHA](https://github.com/a91453/railway-assets-private/tree/codex/taichung-green-assets-2026-10-28/game-art-previews/docs/art/taichung-green/revision-4)。第三輪重檔在同素材PR移除，只留PNG、README、來源及授權；舊成品用真commit恢復，沒有ZIP/history/old/backup。公開只放一張小總覽；每輪合計20私庫PNG＋1公開總覽，單張≤2MiB、單檔≤50MiB、PR新增≤200MiB，提交前再跑asset_guard。

```sh
git checkout 498d85ef234a00345b4b024c4aa0e6783d73b933
tools/train-models/run.sh /tmp/tg --ids taichung-green-dm1,taichung-green-dm2,taichung-green-dm1-far,taichung-green-dm2-far --assembly-spec tools/taichung-green/assembly.json
node tools/train-models/package.mjs /tmp/tg
node tools/train-models/audit.mjs /tmp/tg
python3 tools/taichung-green/audit.py /tmp/tg
# 完整Blender／Swift編組／PNG／viewer命令見工具README。
# 用真第三版還可跑 --previous-paint PREVIOUS_RUN。
```

## 驗證邊界

VERIFIED（Linux）：Swift6.4 warnings-as-errors、最終12項相關測試；六模型拓樸及本車玻璃、八輪、屋頂、風琴、開口、凹孔與支承反例。新增正面第一可見材質探點，實際兩頰塗白反例拒收，真第三版四單元均被拒收；與真前版逐三角比較，改動包絡外幾何及車頭後方色值保持。相鄰車頭烘焙遮蔽色可改變，沒有把簡單總bounds當局部保護證據。

684份其他模型與真第三版逐bytes、所有欄位FNV保持；只改本型四鎖。分支繼承的28項他車舊鎖不符仍列在verification，不改別款值消紅，不能宣稱全包鎖綠。standard pack本輪未動；第三版啟用記憶體報告583模型／133.3MB是前版紀錄，非本輪裝置測量。

Blender4.3.2獨立六GLB匯入、Swift42072頂點編組與全部色值相同／最大位置差1.68µm、170本機PNG完整RGBA解碼、最終六件七向配色／白模／剪影目視、14成品獨立producer重建bytes相同。最終交付viewer下載SHA及本輪實際CI見verification及#1437 checks；file://被瀏覽器管理政策阻擋，loopback HTTP驗收，前者仍UNVERIFIED。

四種狀態分開：**本型素材技術VERIFIED（限證據範圍）／使用者第四版外觀接受UNVERIFIED／營運接入UNVERIFIED／Simulator與真機Metal、效能、動畫UNVERIFIED**。不合併、不auto-merge、不TestFlight。

原生配方與成品：[LICENSE.md](../../../LICENSE.md)，Copyright2026 a91453，All rights reserved。第三方照片只觀察，權利歸原作者。
