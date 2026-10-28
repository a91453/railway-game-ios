# C381 實車原圖與雙車續修（2026-10-28）

兩型均待使用者外觀驗收，撤回先前把「可以」推定為C371接受的紀錄。本輪同修兩車，依最新main8be22423與新railway-assets-private規範交付；[目前README](README.md)為現狀，下列照片細節與先前修訂觀察保留。

## 已親自開啟的完整原圖

| 原圖與來源頁 | 尺寸、SHA-256、作者／授權 |
|---|---|
| [TRSC 原廠正斜一](https://www.trsc.com.tw/upload/images/img-58acf37c0d2fe.JPG)，[規格頁](https://www.trsc.com.tw/train/tran-58acf37b4bd8a) | 3648×2736；`d437b5e8c9a29cdaf9b3fdb5ac087b9a78d5709e0517ef74eb93240fa643e5ad`。原廠頁未列影像作者與再利用授權；只目視參考。 |
| [TRSC 原廠另一斜角](https://www.trsc.com.tw/upload/images/img-58acf37cc1698.JPG) | 3648×2736；`590728c1b6e538663f1ba8a272c2e5e75bae6d5b43e0b562a69dc1e8f133f194`；同上。 |
| [近正面原圖](https://upload.wikimedia.org/wikipedia/commons/d/d9/Taipei-MRT_C381_20130908.jpg)，[Commons 頁](https://commons.wikimedia.org/wiki/File:Taipei-MRT_C381_20130908.jpg) | 1880×1296；`a57110c131991c82864abbb36a530ebdf0b2ebcac61e658b34f174aaf52d61c8`。Rsa，CC BY-SA 3.0／GFDL，見來源頁。 |
| [劍潭前斜原圖](https://upload.wikimedia.org/wikipedia/commons/0/02/C381_approaching_Platform_2%2C_Jiantan_Station_20130908.jpg)，[Commons 頁](https://commons.wikimedia.org/wiki/File:C381_approaching_Platform_2,_Jiantan_Station_20130908.jpg) | 5020×2410；`b38de58592b1c655bb8db1365fc4bf2ea32661288400da94e4ca400880490882`。Rsa，CC BY-SA 3.0／GFDL。 |

四張完整檔均下載到工作暫存並用影像工具親自打開；不是只看搜尋縮圖。來源頁已讀；Commons 頁另一次程式下載403不影響已成功下載的原始照片。原圖不放入公開庫、私包或ZIP，不複製圖素、標誌、車號與廣告。既有使用者插畫僅視覺參考，授權界線見歷史README。

## 照片支持的變更與限制

- 原廠雙側前斜與近正面共同支持銀色車身、深灰黑罩、拱形上緣、三片前窗、較寬中央逃生門玻璃、細門框與略斜側窗。用獨立C381雙軸分站曲面，端罩／玻璃共用分片邊界，避免穿出底面。
- 主藍帶往中央收為細尖，低位細線獨立繞鼻；圓角燈罩內仍看得見藍／銀分色。第一試稿用整片灰燈腔把藍帶切斷，已拒收，其PNG只作review，不冒充真前版。
- 鼻下三條防爬肋有實心背板；分離銀色前裙保留中央連結器開口，兩個箱形支架接到底板。接觸檢查只驗實際支架／底板局部，未冒稱完整結構工程。
- 原廠規格核對：DM連結面間23.710m、T/M23.5m、寬3.18m、車頂高3.585m、台車中心16.5m、軸距2.3m、新輪徑0.85m、軌距1435mm；六輛DM–T–M–M–T–DM、每側四組雙門。原廠規格不是端罩精確曲面圖。
- 鼻部半徑、窗／燈局部尺寸、隱藏底盤、受電靴與空調站位仍有比例推估。原有車頂與輪組位置三角保持；不因這次原圖已開啟便宣稱它們已還原。本輪C381外觀仍待使用者驗收。

## 本輪重建與格式

當前producer由各車source-record綁定。最新完整真前版為reference-private私庫63b44693／素材e791fdb7，原producer cf8d79ba，原ZIP SHA 2e26bbdc08046639ff724cf3d4ac8312e633d996f5ac01f08a99229e8366162a。git中的完整前版仍可還原，不新增history或ZIP到新素材庫。

本輪C381曲面橫向增加過渡面、讓肩部收進前罩外輪廓；收薄燈罩，前裙下緣降到比例推估0.55m、縮窄硬體。第一次降低前裙越過原分片0.60m下限，幾何封閉檢查確實報未封閉邊；擴大實際cap分片域到0.50m後，原檢查與故障反例通過，沒有放寬檢查。0.55m是照片推估，不是原廠工程尺寸。

兩型現由最終配方重新生成，assembly只嵌四個引用單元；不再使用前輪為保護C371整個容器而保留未引用C381記錄的凍結輸入。T/M裸模型bytes及原屋頂／輪組位置保護；兩型展示均在studies，不增加standard記憶體。新資產各車19PNG、最新重檔與viewer、README／SOURCE／source-record；無新增history／ZIP。更多白模、剪影與七向只在本機驗看，不超額提交。

原生封閉／方向／輪軌／反例、前窗射線與埋入玻璃、支架局部接觸與降低反例、Blender、producer重建、共用工具及遠端代表檔驗證分開列。它們不替代外觀接受、真機、效能、動畫、完整碰撞或工程驗收。兩PR與新資產PR保持draft；不合併、不啟動TestFlight；營運映射不改。
