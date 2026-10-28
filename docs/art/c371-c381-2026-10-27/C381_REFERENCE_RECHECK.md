# C381 實車原圖重查與修訂（2026-10-28）

使用者「可以 那c381能照同樣的辦法製作嗎」授權本輪 C381；前一個「可以」記為 C371 第五輪外觀接受，不代表工程／真機／合併驗收。C371 producer `d4ee39b5eaec951137af6158959e8d6ff2cc97de` 的全部原生／GLB保持bytes；本輪只改C381。

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

## 可重建與保護

真正前一完整交付（私庫 `fa7bf6f07ff23edc9b629a5c02b6539d3371280c`，ZIP SHA `be95b0a0ca240cd0f62462a3a2819eca87ee3fc44e3ce236bab833c8f2cb0651`）完整存到 `history/true-v9`；true-v1～v8保留。這依使用者保存真正前版的明確要求，優先於一般清理規則。

`export.sh OUT PROTECTED_C371_SCENE`的第二參數傳入 `history/true-v9/models/c371-formation.m3dscene.json`。舊C371編組容器包含未使用的舊C381單元記錄；只更新C381會連帶改變這些冗餘記錄。為保持已接受C371容器整檔bytes，明確保留該容器，匯出前核每個被引用C371單元與新Swift配方相同、編組平移相同；package再核展開payload等於Swift整列。新C381編組獨立使用新單元，沒有把新C381替換成舊模型。source-record記錄這個受保護輸入的SHA；重建必須帶同一輸入。

局部射線檢查、幾何封閉／方向、輪軌／支座與埋入玻璃反例、Blender、RGBA解碼、同相機真前後、共用工具FNV／日夜七向、producer重建及遠端ZIP逐bytes各有報告。它們不取代真機、效能、動畫、完整碰撞或使用者外觀接受。兩PR保持draft；不合併、不啟動TestFlight；營運映射不改。
