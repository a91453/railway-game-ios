---
name: recreation-kit
description: Generate open-front sports venues, gym equipment and pool facilities with native meshes, GLB, seven transparent views and supported indoor scenes.
---

# 社區運動中心、健身與泳池

先讀 CLAUDE.md、HANDOFF、art-style、station-kit、park-kit、civic-kit 與工作登記 #1041（#231 已滿）。登記自己的新增範圍；不動 GameCore、存檔、Golden、地圖或其他代理檔案。

24 件，venue / fitness / sport / aquatic 各 6，另 4 個完整組景。場館前側開放供組裝與檢視，不是門洞、導航或碰撞資料。器材能獨立擺放，球、槓片、保齡球瓶、樓層與重複擺設不另計件。不重做 ParkKit 球場／單槓／坡道、CivicKit 撞球桌，也不依賴未合併 EstateKit 的 API。

## 原生配方與重建

- Map3DRecreationKit.swift：目錄、按需建模、安裝面與接點。
- Geometry / Venues / Fitness / Sport / Aquatic.swift：封閉基本形狀與四類配方，使用 StationKitBuilder、Civic 圓管及既有色票。
- Examples.swift：原生 placements 與 support 是匯出 manifest、組景使用的同一份資料。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/recreation-kit/rebuild.sh /path/to/private/Railway/game-art-previews/docs/art/recreation-kit-2026-10-23
```

需要既有 Node、Python/Pillow、Playwright、Chromium，不加依賴。輸出必須在公開 checkout 外。配方改後同步 native、GLB、manifest、七向圖；render cache 僅在 native / renderer / 每張 PNG 的 SHA 一致時重用。最後公開 producer commit 乾淨後再跑 bundle.py，使 source.json working_tree_dirty=false。生成中不要改尚在編譯的幾何；最後從目前 build 再匯出比對全部 native/GLB，避免舊編譯參數殘留。

## 接點與構造

Builder：x 前／y 上／z 右；box 的 y 是底。Native、connector、placements：公尺，x 前／y 左／z 上。旋轉弧度俯視順時針：x'=c*x+s*y，y'=-s*x+c*y。mount 的 (0,0,0) 是落地參考平面；開架器材的實際腳點位於其底腳，中心不一定有支柱。

場館地板 top=0.16；場景地坪 top=0.12；器材在場館裡 mount z=0.28。泳訓池 frontDeck z=1.08，出發台必須放在池緣而非池底或懸空；waterSurface z=0.78。跳台 boardTip=(2.6,0,2.90)，只表示幾何位置。poolDeck 安裝與 venueFloor+apron 跨地坪支承要依同一份 placements 檢查，不拿全部 AABB 相交當成錯誤：器材本來就放在場館內，跳板本來就伸到水面上方。

窗有實牆背板。場館前柱、橫梁與封底屋頂相接。跑步機扶手接立柱／控制台；啞鈴落在層板上；斜背椅有撐桿；攀岩握點嵌進實際斜牆；球車輪頂接籃底；回球要接兩根導軌，以實際球底／軌頂高度差檢查，不能只落在中心立柱上；跳台懸臂與平台有重疊，梯梁／梯級／護欄接合。泳道繩兩端嵌進池壁；捲架軸穿過 A 字支架；淋浴頭接管。不得以加高掩蓋穿插或只換色改名。

## 驗證與交付

Swift 6.4、warnings-as-errors，跑本 kit / StationKit / ModelFile 相關測試，完整 suite 交 CI；GLB 共用四個 Node tests。每模型及組景 <=15,000 三角形；逐頂點 loader 讀回、完整 GLB 再編碼、PNG 完整解碼／SHA／alpha／非空未裁邊、viewer 28 模型與搜尋／四分類／七向／旋轉／縮放／四底色／下載／390px。

實際開 parts、全部 directions、undersides、examples、interiors、style-checks 與來源／既有畫風並排。interiors 使用同一個完整原生模型的低角度前視，不移除屋頂或修改正式模型。發現接點問題先保留失敗回歸，再修配方。照片貼圖未使用，不宣稱照片逐層相關係數；WebGL 不代替 iPhone Metal／效能、地圖採用、碰撞、動畫或運動／結構安全驗證。

公開只放配方／工具／測試／skill／文件、一張 overview、小型驗證 JSON；私有同名批次放全部模型、圖、viewer、ZIP、來源路徑／SHA／逐件改造、實際授權。六個來源 factory 只在本機讀取與渲染；功能上沒有對應配方的健身器材明列為原創，不假稱 24 個 factory 移植。不放原始 factory／模型／貼圖／品牌，不傳外部生成服務。兩庫各開互連 draft PR，Agent: Codex trailer，更新 #1041；不推 main、不合併、不 auto-merge。
