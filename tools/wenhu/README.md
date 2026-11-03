# 文湖線兩款靜態草稿（未完成驗收）

從 repository 根目錄執行，Swift 6.4（warnings-as-errors）：

```sh
tools/wenhu/rebuild.sh /absolute/output
node tools/wenhu/render.mjs /absolute/output /absolute/previous-91a31f0-output
python3 tools/wenhu/sheets.py /absolute/output
python3 tools/wenhu/curate.py /absolute/output
```

採通用 assembly-spec，沒有修改共用 exporter、loader 或格式。四車中心為 +20.67、+6.89、-6.89、-20.67 m，每車連結面間距暫按官方列示車長13.78m；此尺寸是否為嚴格連結面距尚未確認，不能當工程連結面認證。原生 +X／+Y左／+Z上、跑道面Z0。A車+X暫對AX、B車+X暫對BX，組裝不再次反轉。角色方向、隱藏輪組與A/B設備分配仍未確認。

兩款配方各自重建殼面／鼻面函式與截面；僅沿用 StationKitBuilder 原有 box／face 與新增本輪 primitive。沒有匯入參考庫幾何／照片貼圖。原始來源、衝突、權利與完成狀態見 docs/art/wenhu。

本輪尚不能作為完成交付：專型角色／方向、完整照片覆蓋、車底設備及安全／轉轍輪位置仍缺。rebuild 會執行共用audit及本型端部、玻璃／走行／屋頂接觸與assembly故障檢查；失敗須修真幾何，不能放寬gate。技術、外觀接受、營運與裝置驗證分開保持UNVERIFIED，不能用本README或CI升格。

## 原生幾何專用驗證（續修）

`end-audit.mjs`對全部A/B近遠的真native射線取樣：連結器孔口4條、端下凹腔2條；實際收縮中空頭內緣／壓平鼻下頂點均須拒收。`audit.py`沿用本專案既有的read／normal／ray／connected-component helper（來自taoyuan-airport/audit.py），本車尺寸與驗收獨立；檢查外向玻璃面質心可見與65mm內背襯，排除窗板邊壁而非放寬整片玻璃，四行走輪／八水平導引輪／兩HVAC的實際連通幾何與位置、接觸及包絡。每單元13種真正幾何故障（玻璃埋入／浮空、缺輪／錯軸／軸向厚度、輪離跑道、導引輪移位／缺漏、HVAC離頂／重複／移位複製、車殼複製等）須拒收。

`assembly-audit.mjs`修改最終真正assembly，拒收替錯角色、錯序、漏中央車、100mm間距錯誤、B車反向導致車對接合錯誤。基準payload另由獨立Swift importer組裝核對；這只驗研究配置，不能消除官方角色方向來源衝突。

導引輪配適軸位x=±4.65±0.68、y=±1.02、z=0.385m，水平半徑0.20m；與行走輪保留80mm縱向包絡餘量。這些為可檢查的展示假設，並非原廠工程位置；隱藏安全／轉轍輪與精確集電機構仍缺來源。驗證是指定取樣／包絡與真故障，不是完整工程碰撞或外觀接受。

同尺度前後對照採真前稿91a31f0原生bytes，前稿從未獲使用者接受；render第二參數必須指向該producer重建輸出，不能以標籤或後稿冒充。
