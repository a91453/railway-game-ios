# 車輛素材接手 prompt（給沒有任何對話紀錄的 Codex／Claude）

以下整段可直接複製到新 session，再附上新車的前、後、左右或斜視圖。沒有原始模型也能做；原生程序化建置是目前的預設。

```text
你正在接手 a91453/railway-game-ios 的遊戲車輛美術。請依我這次附的參考圖，實際完成一款能進原生遊戲的靜態 3D 車輛，匯出七向透明素材、檢查，最後推公開與私有 draft PR。不要只提出方案、描述模型、給我 prompt 或一張概念圖就停止。

作者已授權：更改參考車的配色與形狀；可組合作者私有庫的素材，但必須改成遊戲自己的霧面頂點色、重新組合造型；完成後推 task branch 與 draft PR。不准直接在 main 開發、不准推 main、不准 merge 或 auto-merge。不要重問已授權的例行步驟。沒有明確要求時不另開平行子 agent。

一、先接專案與工作範圍
1. 讀 AGENTS.md、CLAUDE.md、docs/HANDOFF.md、.claude/skills/art-style/SKILL.md，再讀最接近的車輛 skill 與 tools/README。CLAUDE.md 對所有 agent 生效。需要診斷真正 bug 時，先讀 diagnosing-bugs skill，建立會失敗的重現，再修。
2. git fetch origin，檢查最新 origin/main 與 GitHub #231 的所有認領／完成留言。先認領任務、獨立 codex/<vehicle>-<date> 分支、工作目錄、精確檔案；save version、決策編號、golden schema 都寫「不動」。不要覆蓋別人的工作或直接修改別人的分支；範圍重疊先協調。只加 #231 留言，不改 issue body，不在 GitHub 留觸發機器人的 mention。
3. 檢查依賴 PR 的 merged 狀態與目前 head，不能假設上一台車已在 main。需要尚未合併的 helper／enum 時，從那個 head 開 stacked branch，以它的分支作 PR base；只讓本批差異出現在 PR。依賴合併後才轉 main。不要無故把每張 PR 都更新 main 或 cherry-pick 所有前批內容。
4. 只改本批的 presentation 模型、自己的 tools／測試／素材說明／skill。車流整合若必要先認領 Map3DStreetLife.swift。docs/HANDOFF.md 只補一個可找到的交接連結，別重寫規劃。GameCore、save／golden／replay fixtures、ARCHITECTURE 決策、OVERVIEW、優先清單、其他人的模型不碰。App 接入若超出純模型自動註冊，另說明依賴，不冒稱已完成購車／營運玩法。

二、先看參考再建模，做出不同造型
1. 看懂車頭／尾、左右門、軸數、輪距、車高、窗帶與車頂。圖片不是精確工程尺寸；不捏造品牌型號或量測精度。臺灣靠右行駛，右側才是一般乘客上下車門。左側參考門若用途不明，保留成緊急／設備門並註明，不隨意複製成乘客門。
2. 用 Map3DPalette 既有色票，F 台灣版＋的平塗、霧面、頂點色。保留能辨識的車種比例，重新組合頭尾、燈組、車頂和細節，不能只把原模型換色。不要真實品牌、商標、車牌個資、照片貼圖或原始來源配色。
3. 私有來源位於 a91453/railway-reference-private。作者庫是已授權來源，讀其入口與 rights／授權註記，遵守實際署名要求。可本地轉換／拆件／混合後改風格；原始私有 mesh、貼圖、圖片不推公開、不上傳會保留或訓練的外部圖像／3D 服務。若需要難題的既有解法，先查作者庫，再查有合適授權的開源，依 CLAUDE.md 處理。不擅加依賴或使用 copyleft／無授權程式碼。
4. 先自選合理配色和造型，PR 從玩家、鐵道迷、開發、美術、音樂五角各寫一行理由。音樂無影響就明說；不為例行美術選擇停下等作者。把替代方案／現有模型對照留在私有預覽供審閱。

三、原生建模規格與常見失敗
1. 新增 Sources/GamePresentation/Map3D<Vehicle>.swift，提供公開 modelName、尺寸／色票與 model()，回傳 Map3DModelPack.Model。依本專案慣例呼叫 StationKitBuilder。
2. builder 內部是 +x 前／+y 上／+z 右；Model.flat(named:from:) 只轉一次成原生 +x 前／+y 左／+z 上，單位公尺，輪底 z=0。不要把 GLTF 的 Y-up 誤當原生軸。GLB 由既有封裝器轉成 +x 前／+y 上／-z 左。
3. 車體、車頂、底盤、輪胎、鏡殼與支架是封閉幾何；法線有限、單位化、朝外，不靠關掉剔除掩飾反面。頂點用不透明色，燈可 glow。不要每台用隨機彩色 instance 染色。一般車型約 1,500–3,000 三角形；上限需看當下 native loader／renderer，別把 15,000 loader 上限當每台應耗光的預算。
4. 輪拱是實際凹口，不是黑色貼片。shuttleShell 耳切可保留凹輪廓，不能用 triangle fan 填凹多邊形。輪胎用封閉 civicTube、輪子落地，檢查輪拱上緣有空隙且門／裙板不蓋住輪子。
5. 曲面車頭要在俯視與側視都重組，風擋依真實的分段斜面／弧面拆片，沿該片法線微移。側窗、前窗、門玻璃背後要有車身或實體門板，不能跨過折線浮在空中。屋頂quad可能非共面，目的地牌應從實際三角面裁片；bilinear插值可能讓牌埋進屋頂。有腰線折點的色帶拆成凸片，不能對凹多邊形直接fan，否則first-three normal可能反向。用射線測支持距離與面片朝外，再看前後左右／底面。
6. 服務／行李艙門採車身同色、薄接縫、小把手。StationKitBuilder.box／Map3DMesh.addBox 會對側面陰影著色，白漆蓋板可能變厚灰箱；需維持原色時用 face／shuttlePanel 直接著色。沿用 coachLuggageDoor 的封閉薄殼與面漆做法，不要復活舊厚鋼框。面漆與背板至少相差約 2 mm，薄片間距太近會深度閃爍；門仍應貼車身，不能為消閃爍突出幾公分。
7. 車頂與車身分段相接，不能兩個不同色的殼有整片同面頂板，否則出現斑駁破碎區塊。冷氣／通風設備有接觸支腳，支腳完整填滿頂面到設備的間隙；鏡殼由相連鏡臂接到車身，走廊／踏階也要有支持。
8. 複用舊 helper 可以，但不要為新車修改舊車的形狀／色彩。保留前批模型的 position/color/glow triangle payload；若沿用相同 provenance envelope，native 與 GLB 整檔也應一致。對照車是舊成果，不計新增。

四、接入車流（只有本批確實需要時）
1. 追加 Map3DStreetModel case、model() 分派、isBus 與需要的 model-length fade；standard 由 allCases 註冊。Map3DCityBus.pack(file:) 只替換既有 life-bus，新型不能被它吃掉。驗證 standard 與 App 使用的 fitted pack。
2. 保持總 5% bus pool、密度、道路資格、bus cap、17 m 保守間距，不增加整體車輛量。新增車型只分配既有剩餘比例，盡量保留前幾款的 seed 選型；記錄實際權重。未來舊車剩餘池耗盡時先重新設計並說明，不直接一直追加造成總比例膨脹。
3. 測試至少要涵蓋實際可生成新型、所有型都可達、a.buses 統計一致、buses=false 不改車輛總量、長車不與鄰車重疊。抽樣道路用獨立二維 seed，例如 (seed*1009,seed*9176+4)；連續 x 加固定 y 會與 vehicleIndex 的 key 重複，造成只測同一批車的假統計。
4. 這只是街景顯示，沒有新增 GameCore 可購買車輛、路線／班表／載客規則；不要把靜態模型當已完成營運功能。

五、產出可用素材與檢查
1. 從 tools/midi-bus（或最接近的上一批）複製成自己的 tools/<vehicle>/，不要在前批工具上改車型。使用現有 station-kit/package.mjs、renderer.js 與封閉幾何；不新增外部依賴。
2. 一起改 export.swift、render.mjs、verify.mjs、verify-png.py、browser-check.mjs、viewer.html、rebuild.sh 與 README 中的 generator、ID、名字、分類、數量、搜尋字、初選車、comparison 數、車隊排序及 XCTest suites。不要對所有「28」之類做盲目全文替換，會改掉尺寸／配色／樣式。避免留上批的 before-after 條件或舊預覽。
3. 每個模型輸出 .m3dmodel、嵌入 buffer 的 GLB、top／bottom／left／right／front／back／isometric 七張 384×384 RGBA 透明 PNG，寫 manifest、實際尺寸、三角形數、來源與 SHA。再做 900px 前後底、overview、七向、四底色／小尺寸／模糊灰階、既有車比較與互動 viewer。
4. 同尺度 fleet 必須用實際模型的 triangle records，只加以公尺計的位置平移、共用一台 camera；不要把各自自動 fit 的 PNG 排一起冒充同尺度。預覽合成不是新資產，不新增 model_count。遵守合成 renderer 的總三角形上限。
5. rebuild.sh 輸出必須在公開 checkout 之外。Swift 用 6.4（先確認 swift --version），warnings-as-errors。先 swift build --build-tests -Xswiftc -warnings-as-errors，再 swift test --skip-build --filter 觸及的測試；全套交正常 PR CI，不擅跑全套或 TestFlight。新 checkout 的首次 build 可以先預熱，但不要在編譯中的 target snapshot 混進尚未編譯的新 enum／test 引用。
6. 測試針對失敗風險：尺寸、輪底、有限不透明頂點、法線、封底、確定性、真輪拱射線、玻璃支持距離、門左右差異、頂架接觸、traffic 人口與 pack 共存。不要只重複實作常數或為過測試刪真斷言。發現缺陷後先留會失敗的重現。
7. 工具檢查所有 native vertices position/color/glow round-trip；normal 有合理小容差（既有 fit 模型約 1e-5），GLB 全量重建與 SHA 一致；Node 封裝測試、Chromium/WebGL 真幾何渲染、PNG SHA／不空白／不裁邊，再用 Pillow 完整解碼確認 RGBA、透明 alpha、像素數與 renderer 一致。Pillow 只驗證，不替代 image tool 修圖。
8. viewer 用 localhost 服務測（不可依賴 file://），驗證所有模型／七向 PNG 都能載入，中文搜尋／分類、orbit 真改畫面、zoom、PNG/native/GLB 下載與雜湊、390px 不橫向溢出、無外部請求／缺檔／JS 錯誤。留 desktop/mobile/underside 截圖。
9. 看 XCTest 實際的 suite passed，不能只看 shell exit=0。Swift Build 曾在某 runner failed 後被最後一個空 runner 的成功狀態遮住；rebuild 的 log guard 必須確認每個指定 suite passed 且沒有 Test Suite／Case failed。
10. 用 view_image 人工看真正產出的 overview、七向、底面、風格表及同尺度車隊，修完再完整重建。雜湊正確不等於好看；Linux WebGL 通過不等於真機 Metal、幀率、輪子／車門動畫通過。

六、儲存、PR 與交付（做到這裡才收工）
1. 公開庫只放原生配方、工具、必要測試、skill、README、小型 verification 和一張 overview。大型輸出與 ZIP 放私有庫 Railway/game-art-previews/docs/art/<vehicle>-<date>/，保留 source.json（本批參考、來源映射、重組方法、recipe SHAs、實際 producer commit）與完整 viewer/manifest。
2. 私有庫從當時 origin/main 開自己的資產分支，避免把其他尚未合併的素材批次帶進來。不要換 shared clone 分支時丟失別人的未提交檔案。處理 sparse checkout，不把 sparse 看不到當成遠端不存在。
3. ZIP 包含全部必需 viewer、model、PNG、manifest／verification／source／README，無絕對路徑、..、秘密或原始私有來源。完整解壓 CRC，逐一比內容 bytes 和 SHA，記錄檔案數／bytes／ZIP SHA。不要只看 zip 檔存在。
4. 本批 commit 帶 Agent: Codex（若實際 Claude，依它的 repo 規範）；推 task branch，開公開 draft PR 與私有 draft PR，互鏈，清楚寫 stacked base／合併先後、來源映射、五方理由、實跑 VERIFIED 與 UNVERIFIED、下一位接點。不要 merge／auto-merge／main／TestFlight，不用 force push 掩蓋他人工作。
5. 更新 #231 完成留言，寫 head／PR／檢查／剩餘限制。HANDOFF 要有 repo 內可找到的指引，不只把交接留在聊天。推完查實際 CI 狀態；pending 就寫 pending，不假報綠。遇到 CI failure 修自己的問題，但不要搶修別人的 scope。
6. 最後用繁體中文給我實際新車預覽圖、可下載 ZIP、公開／私有 PR、交接文件連結，以及一句檢查結果與真機限制。不要拿參考圖或上一台的圖片當本批結果，也不要把4台對照說成新增4款。

現在開始，依我附的新參考圖做下一台。
```

## 本批的可重現起點（2026-10-21，不代表已合併）

| 項目 | 位置／用途 |
| --- | --- |
| 公開庫 | `https://github.com/a91453/railway-game-ios` |
| 私有庫 | `https://github.com/a91453/railway-reference-private` |
| 工作登記 | 公開 issue #231；每次接手重讀最新留言與 merged 狀態 |
| #941 | `codex/shuttle-bus-2026-10-21`；高頂短鼻小巴與 shuttleShell helper |
| #942 | `codex/low-floor-bus-2026-10-21`；依 #941 的低地板公車 |
| #945 | `codex/coach-bus-2026-10-21`；依 #942 的三軸遊覽車，含最新同色行李門；本批基底 `0cabb0690ba1ec848ebeb1899b11f3c6949c7eb4` |
| 本批 | `codex/midi-bus-2026-10-21`；依 #945 的圓弧中巴，已按作者回饋改圓肩loft／包覆風擋／細連續窗帶，不取代前三台 |
| 新原生配方 | `Sources/GamePresentation/Map3DMidiBus.swift`／`life-midiBus`，約9.15×2.38×3.16m；鏡寬2.91m；軸 x=-2.12/+2.86 |
| 原生現況 | 五款 bus：shuttle30%、low-floor35%、coach20%、midi10%、原有大型5%，都在原5%總池內；前三款 seed 選型不變 |
| 工具 | `tools/midi-bus/rebuild.sh /absolute/private/output`；1新＋4對照，5native／5GLB／35七向PNG |
| 私有成品分支 | `codex/midi-bus-assets-2026-10-21`；`Railway/game-art-previews/docs/art/midi-bus-2026-10-21/` |
| 本批限制 | 靜態素材與既有街景車流整合；沒有購車、班表、物理碰撞或輪子／車門動畫；真機效果與效能未驗證 |

完整讀完 prompt 再按目前遠端狀態更新分支判斷。上表是本次工作紀錄，不是要求未來固定沿用未合併的分支。
