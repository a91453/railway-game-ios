# 台鐵 EMU500 原生靜態素材

追蹤 [#1310](https://github.com/a91453/railway-game-ios/issues/1310)。獨立配方 [Map3DEMU500.swift](../../../Sources/GamePresentation/Map3DEMU500.swift)，重建 [tools/emu500](../../../tools/emu500/README.md)。

## 接手、來源與遊戲範圍

公開 base `f6c6afa3bcc5888c350ff5594c3e8f370d565f31`；私庫 base `b6b18ba48102ca38859068c1511e0d2ab2ba9f5f`。實查 TEMU2000 公開 #1292 2026-10-26 13:31:59Z 已合併，私庫 #86 12:56:37Z 已合併；main 另含 #1308 的普悠瑪營運接入。

適用 AGENTS、CLAUDE、HANDOFF、art-style skill 與原生製作手冊已查；私庫找不到 AGENTS.md / CLAUDE.md。已查工作登記 #1041 與 #231 最後頁，認領自有檔案。EMC、EP、ET、EM 都由新截面與新設備生成；不沿用既有車型幾何。

`Map3DSceneKit.swift` 的 `05_TRA_classic_3x2-01` 是舊 EMU500 場景素材；查 `Map3DTrainSets.all` / `Map3DModelPack.styleByType` / TrainTypeCatalog，沒有 EMU500 專用營運映射，現行區間車 `emu800` 不能冒稱 EMU500。本輪只新增原生素材註冊；**合併後不會自動出現在營運列車**。GameCore、玩法、存檔及 fixtures 不變。

私庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/README.md`、`integration/FORMATIONS.md` 及 `assets/garage-blender-v1/emu500.json` 已讀。舊模型明示 Q-proportions、engineeringDimensionsM=null（長約 9.308 m），不可拿其 bounds 當真車長。本輪不讀取、複製其 mesh 或貼圖；只引用 metadata 的資料缺口。

## 六張附件：逐張實際查看

以對話直接目視六張內嵌圖，未取得本機原圖檔，故沒有原圖 SHA；不假稱以檔案工具開啟。原圖不進公開庫、ZIP 或外部服務。

| 圖 | 實際可見及用途 | 不可確認 |
|---|---|---|
| 1 | EMC、EP、ET 側視插畫與小端面：三對門、窗節奏、空調、EP 弓、EMC 藍頭和細腰帶 | 非工程圖；沒畫 EM 全側面、另一側、精確設備尺寸。標 K.Y.Chung / Nanyue Express，CC BY-NC-ND 4.0，僅目視形態，不取圖素 |
| 2 | 450×220 車站前側斜照：短圓角直立頭、中央貫通門、白折線、黃黑裙、銀側身 | 解析度低，不能判定小型配件及精確曲率；標 KASHIWA Train Collection |
| 3 | 站內大斜視照片（COMET115）：上方雙圓燈、灰黑貫通框、獨立駕駛窗、下圓燈、長車身輪廓 | 透視與傾斜不能作公尺量測；遮住的車底及另一側未知 |
| 4 | 彎道近正面：圓肩、藍色額頭、兩窗與中央窄門、下部警戒紋、弓與空調節奏 | 長焦壓縮，不能據此量各節間距或後車設備 |
| 5 | 330×220 遠前斜照：完整列車節奏、雙上燈及端面構圖 | 解析度低，左右設備與細部尺寸不足 |
| 6 | EP 幾乎正側面（KASHIWA）：三對門、小端窗、不同客窗、兩端空調、一端弓、兩轉向架及可見車底箱 | 只有一側；不能證明另一側或 EMC/ET/EM 全部車底配置 |

## 建模前特徵表

| 項目 | 決定與缺口 |
|---|---|
| 主曲面 | 銀色直身、圓肩淺拱頂、近直立圓角短端；沒有特急長鼻。先截面再輪架門窗設備 |
| 頭尾／左右 | EMC、EM 各有外向駕駛端，EP、ET 不設駕駛玻璃或頭燈；左右門位採對稱推估，非已證實 |
| 分色 | 遊戲既有銀灰 `BBC6C9`、低彩藍 `214F90`、深玻璃及暖黃；藍頭、細腰線、白折線及警戒紋，無商標 |
| 玻璃與門 | 三對薄雙扇門；每個客窗獨立深色座與玻璃，不用整條黑片代替。參考實際是銀色窗柱，不擅加全側連續黑窗帶 |
| 走行 | 每節兩組雙軸台車、860 mm 輪徑、2.8 m 軸距、軌面 Z=0；台車中心位置推估 |
| 車頂及車底 | 兩端空調、EP 一端折臂弓、簡化下掛設備；隱藏配管、左右差異與箱體功能未知 |
| 單元／編組 | EMC–EP–ET–EM，EM 在組裝時轉 180°，四車標準單組；照片多組重聯不代表單組變八車 |

## 尺寸與共同基準

2026-10-27 讀取[中文維基 EMU500 車型頁](https://zh.wikipedia.org/wiki/台鐵EMU500型電聯車)，二級資料列：單車長 20.330 m、寬 2.853 m、非 EP 高 3.964 m、EP 降弓高 4.219 m、輪徑 0.860 m、軸距 2.800 m，順序 EMC–EP–ET–EM。私庫 FORMATIONS.md 亦指出 EMU500 四輛，不能由區間車班表判定車型。

沒有取得原廠工程圖。本模型採 20.33 m 為編組節距，車殼 19.88 m、台車中心 ±6.65 m、各截面、門窗尺寸位置、設備、連結器與間距都是**比例推估**。不能把引用的車輛長解讀為已確認連結面距；81.32 m 是四倍引用長度的模型配置值。EP 採展示升弓，最高處不等於資料所列降弓高度。

各件共用車身中點 X=0、對稱中心 Y=0、輪底 Z=0。單元原生 +X 前、+Y 左、+Z 上，EM 自身駕駛端 +X，編組明列：

| 次序 | 單元 | X 平移 m | 繞原生 Z 旋轉 |
|---|---|---:|---:|
| 1 | EMC | 30.495 | 0° |
| 2 | EP | 10.165 | 0° |
| 3 | ET | -10.165 | 0° |
| 4 | EM | -30.495 | 180° |

中心間距 20.33 m；車殼間隙 0.45 m，短風琴與連結器為簡化展示。全部實際 bounds、三角數在私包 manifest，不把長度推估說成工程校準。

## 交付及驗收

最終總覽見 [overview.png](overview.png)；完整模型、GLB、各件七向透明 PNG、白模／剪影、同尺度風格與前後對照、離線 viewer、SHA 和 ZIP 在互鏈私有 draft PR。使用者要求保留真前版及 ZIP，優先於 CLAUDE 預設不留舊模型／ZIP 的儲存規則。這不表示使用者已認可任何版本。

外觀與技術的最終結果在下方及私包 `visual-review.md`、`verification.json`；CI 以 PR 最新 head 實查為準。

### 最終第三版外觀自檢

已親自查看第三版原生總覽、正／側／俯／斜配色、白模、剪影，四單元、四車編組、同尺度風格及真第二版→第三版對照；第一版→第二版亦留實際圖及模型。

| 判定 | 結論 |
|---|---|
| 已符合 | 短直立圓角藍頭、銀灰直身圓肩、中央貫通門及兩片駕駛玻璃、雙上燈與下圓燈、白線向內下折、左右對稱警戒紋；三對薄雙扇門、分離客窗及窗柱；EP 一端升弓、四輛兩端朝外，中車沒有駕駛玻璃或頭燈；色票及霧面與 TEMU1000 同尺度比較 |
| 仍不符合 | 相較照片，玻璃角仍偏多邊形，白折線較規整，前裙較平，台車與空調簡化；沒有照照片逐條復刻軟管、雨刷、前端插座及箱體格柵。非工程復刻，不宣稱使用者已認可 |
| 資料不足 | EMC/EM 完整左右差異、另一側精確門窗／車底箱、所有設備工程尺寸、原圖檔案及 SHA；參考的車長是否以連結面為準未確定 |

最終實量（含門窗／設備，非車殼規格）：EMC/EM 各 3,300 三角、EP 2,544、ET 2,440、編組 11,584。單件 bounds X ±10.165 m、Y ±1.487 m、輪底 Z=0；非 EP 頂 3.977 m、EP 升弓頂 5.000 m；全編組 X ±40.660 m。車殼寬 2.853 m 與包含突出門窗的總寬分開記。

**VERIFIED — Linux**：Swift 6.4 warnings-as-errors 建置及 10 項相關 XCTest；Swift 原生逐頂點讀回、有限數值／單位法線、封閉有向邊／正體積、八輪貼軌、編組逐頂點及色彩、TEMU1000 共存 payload；缺面／反面故障拒收；玻璃背板及空調中心支承射線抽樣、浮空玻璃反例；Blender 4.3.2 獨立匯入六 GLB；42 張七向圖完整解碼、透明與留白；Chromium WebGL2 真載入／旋轉／縮放／下載。最終 SHA、producer、ZIP 全解壓逐檔比對在私包紀錄。

**UNVERIFIED**：真機 Metal、效能、動畫、全設備支承及全域穿模／碰撞窮舉、另一側工程校準。自包含 viewer 已提供，但受此環境 Chromium 管理政策限制，`file://` 啟動被 `ERR_BLOCKED_BY_ADMINISTRATOR` 阻擋；相同 HTML 改由本機 HTTP 載入，測內嵌模型及互動下載、無外部請求。不能將此說成已驗證直接雙擊開檔。

公開 draft [#1312](https://github.com/a91453/railway-game-ios/pull/1312) ↔ 私有 draft [#92](https://github.com/a91453/railway-reference-private/pull/92)。[私有完整交付索引](https://github.com/a91453/railway-reference-private/tree/codex/emu500-native-2026-10-27/Railway/game-art-previews/docs/art/emu500-2026-10-27) 包含全部下載與真前版。最終 producer 的完整 SHA 及每件 producer 檔案 SHA 以私包 source-record.json 為準；模型幾何自第三版固定，後續只補工具稽核與文件。最新 head 的 CI 與衝突狀態見 PR 及 issue #1310 的實查留言，未完成的 CI 不記成 VERIFIED。
