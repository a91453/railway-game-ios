# 文湖線兩款靜態草稿（未完成驗收）

從 repository 根目錄執行，Swift 6.4（warnings-as-errors）：

```sh
tools/wenhu/rebuild.sh /absolute/output
```

採通用 assembly-spec，沒有修改共用 exporter、loader 或格式。四車中心為 +20.67、+6.89、-6.89、-20.67 m，每車連結面間距暫按官方列示車長13.78m；此尺寸是否為嚴格連結面距尚未確認，不能當工程連結面認證。原生 +X／+Y左／+Z上、跑道面Z0。A車+X暫對AX、B車+X暫對BX，組裝不再次反轉。角色方向、隱藏輪組與A/B設備分配仍未確認。

兩款配方各自重建殼面／鼻面函式與截面；僅沿用 StationKitBuilder 原有 box／face 與新增本輪 primitive。沒有匯入參考庫幾何／照片貼圖。原始來源、衝突、權利與完成狀態見 docs/art/wenhu。

本輪尚不能作為完成交付：專型角色／方向、完整照片覆蓋、車底設備及安全／轉轍輪位置仍缺。rebuild 的 audit 若失敗須修真幾何，不能放寬 gate。技術、外觀接受、營運與裝置驗證分開保持UNVERIFIED，不能用本README或CI升格。
