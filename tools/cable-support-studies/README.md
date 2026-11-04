# 纜車站務配套 producer

本批補CABLE3D #1782的站務素材，不取代其吊廂／塔柱／鋼索／站房，不註冊runtime、studies或standard。決策575僅相容性參考，不改其檔案、不另佔決策號。新寫配方，原生公尺+x沿索/y左/z上；靜態M3DM、GLB和可動body metadata。

```sh
PATH=/path/to/swift-6.4/usr/bin:$PATH tools/cable-support-studies/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/cable-support-2026-11
```

沿用既有Python/Pillow、Node/Playwright、Chromium、Swift6.4，不裝依賴。`produce.py OUTPUT --part platform|gate|queue|catwalk|kiosk|assembly`可逐件重建。正式首次製作逐件生成、拍七向、目視自檢後才做下一件；完整rebuild供已自檢配方再生成。禁止輸出到公開checkout內。GLB沿用station-kit/package.mjs，沒有標準glTF動畫軌或emissive材質；native glow flag與viewer日夜可用，GLB僅保留_NATIVE_GLOW。

關節axis(0,0,1)，pivot(0,-.65,.60)，角度0–π/2。只旋轉門扇三角範圍；兩柱、鉸鏈、狀態燈固定。狀態燈僅外觀，不是遊戲通行權。維修走台底面z0為安裝面，應掛到宿主橫樑；組裝例有兩支架支承。

相容性依PR1782 commit aaaaaca6：索距5.2、站內索高4.2、廂底下垂3.6、廂寬1.7。平台面.60、半寬1.65，至廂近側1.75有名義.10m間隔。這些是study設計值；原站房平台面.90，本批必須替換舊平台而非疊放，沒有宣稱整座舊站房無縫相容。未驗動態淨空、吊廂門檻／開門、結構安全與無障礙。

工具檢查：6項geometry test（有向封閉／正體積／故障反例／LOD／安裝面／平台對位／門扇剛體與固定件保持）、Swift真正loader逐頂點讀回、GLB完整byte重建、168PNG真正RGBA解碼/SHA/非空不裁邊、嵌入HTML關網12模型／七向／日夜／閘門slider／390px。

受管Chromium若封鎖file://，verify明寫UNVERIFIED並在新頁載入同份自含HTML、關網驗互動，不以此假稱直接雙擊已驗。viewer沒有fetch／CDN，模型與renderer內嵌；一般瀏覽器可下載index.html開啟，也可localhost。輸出模型各自一資料夾revision-1，各14日夜PNG；批次單一viewer，無history／ZIP。外觀接受、Metal與實機效能皆另驗。

沿用本專案渡輪producer407cbca的封閉box／beam／日夜與自含viewer流程，移除船配方，新增本批原創站務幾何；不帶私有factory或參考照片。色值沿用Map3DPalette。完整來源、照片及哪些是比例推估在私庫SOURCE。
