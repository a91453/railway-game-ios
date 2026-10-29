# TEMU2000 普悠瑪靜態素材續修

本版 producer：`02d61687481ebdd832edc5c11685af51eca05362`。公開小[總覽](overview.png)；完整原生模型、GLB、20 張預覽、viewer、來源與 SHA 在 railway-assets-private [draft PR #23](https://github.com/a91453/railway-assets-private/pull/23) 的 `game-art-previews/docs/art/temu2000/revision-1/`。

基準：公開 main `504372492547a72f9c38692d6137fe92f57e9652`。真正前版是已合併的 #1292 配方與私庫舊交付，producer `8d78f038aeb3a1d59d53c5ca04e649b257a401d8`。營運接入 #1308 已合併；本輪只動 `studies`。舊交付的綠松色與車頂方塊外觀沒有當作實車證據。台中綠線 producer `498d85ef234a00345b4b024c4aa0e6783d73b933` 只作霧面風格參考。

## 實際查證與界限

2026-10-29 下載並目視 [日本車輛製造的交車照與型錄](source-record.json)、臺鐵 2016 年《靚道》封面實車照片，並與使用者提供的正面、側面與斜側照片比較。前兩者是實車照片；使用者首圖是插畫，不當作尺寸圖。原檔不進倉庫。私有參考庫的車隊資料也查過，未搬用示意網格。

正式車型是 TEMU2000 型傾斜式電聯車，日車開發與製造，住友商事為供應聯合方；未找到可支持臺灣本地組裝該型車的來源。日車資料寫明 2012–2014 交車、一編組台東通車特殊彩繪；臺鐵 2016 刊物另有當年猴年新購車首記號，不當作一般塗裝。現役個別車號與 2026 年狀態尚未逐列核實。

日車型錄列 TED 車體 21.745×2.900×3.632 m、中車 20.000×2.900×3.565 m；1067 mm 軌距、2200 mm 軸距、860 mm 輪徑，交流 25 kV 60 Hz 架空線。既有 TTSB 資料列 TED 連結後 22.095 m、中車 20.700 m、八車 168.390 m。編組採 TED–TEMA–TEP–TEMB–TEMB–TEP–TEMA–TED，兩端 TED 外向，第二個 TEP 旋轉 180°；兩端中央風琴與端面連結器細形、TEMA/TEMB 箱體差異、另一側門窗仍為推估。TEP 有受電弓；每車兩組雙軸轉向架。車頭白頰、紅額頭、深色風擋、三上燈、兩側下燈座及鼻唇的面積邊界依兩份官方實車圖目測，不冒稱工程尺寸。

## 重建

使用 Swift 6.4，公尺、+X 前／+Y 左／+Z 上、軌面 Z=0：

```sh
tools/train-models/run.sh OUT --tag after --ids temu2000-leading,temu2000-tema,temu2000-tep,temu2000-temb,temu2000-trailing,temu2000-leading-far,temu2000-tema-far,temu2000-tep-far,temu2000-temb-far,temu2000-trailing-far --assembly-spec tools/temu2000/assembly-spec.json
node tools/train-models/package.mjs OUT
node tools/train-models/audit.mjs OUT
node tools/train-models/render.mjs OUT --time day
```

完整編組是 M3DAssembly，從十個獨立單元按 `assembly-spec.json` 重建，沒有把全列裝進超限 M3DM。外觀接受、營運、真機狀態另見交付的 status.json；技術通過不代表外觀已獲使用者接受。

## 固定鏡頭與逐視角外觀自檢

真正前版原生端車從既有私有交付取出，SHA-256 `e2de16b25875e790a457d4e5dbf8d5607eba79f63904f075779117bebbd82b73`。`tools/temu2000/feedback-compare.mjs` 用同一原生座標、相機中心、包絡與決策 370 的日間燈光，把該檔與本輪最終端車並排；不以事後重造的前版冒充。官方原圖旁置比較只在本地工作區進行，因照片授權未允許再散布，不進兩庫交付。

| 視角 | 已符合 | 仍不符合 | 資料不足 |
| --- | --- | --- | --- |
| 正面（臺鐵 2016 封面、使用者正面實車照片） | 紅額頭、深色風擋、雙側下燈座、紅色中央鼻面與白頰可辨；原有灰色方屋頂突出收下 | 低多邊形白頰接近鼻尖仍顯塊狀，下燈腔較實車小而尖，車頭中央面有可見的色階與薄件痕跡 | 官方封面非正交，橫向斷面不能量成工程尺寸 |
| 側面（製造商交車照、使用者側照） | 鼻頂往前下降、側窗與雙紅線；色帶切在平直殼面及門葉同高處 | 實車的大幅紅色側面圖形因不複製真實商標而缺席，鼻尖白色下裙與車側設備仍過於概略 | 另一側門窗位置、TED 底盤各箱尺寸 |
| 俯視（製造商交車照局部、使用者遠斜照） | 頭車收窄及 TEP 集電弓能辨 | cab 屋頂設備在本輪降低後可能過於平薄；空調罩仍屬簡化盒形 | 沒有足夠清楚的正俯視原圖，不能宣稱屋頂設備列序已工程確認 |
| 斜視（製造商交車照、臺鐵封面） | 正側主色關係與八車整列有一致輪廓，遠景仍保留鼻面與雙帶 | 實車車頭與白頰的平滑連續曲率尚未達成，車底設備與車間風琴為遊戲尺度簡化 | 車首隱藏連結器、車底、兩側照明與設備細節 |

2026-10-29 本輪自檢結論：可交付 **studies 技術素材供外觀審閱**；外觀仍有上表失配，沒有使用者對本 producer 的接受紀錄。營運 `set-puyuma*`／`light-set-puyuma*` 未替換，實機 Metal、動畫與效能未驗。
