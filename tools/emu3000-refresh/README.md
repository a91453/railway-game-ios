# EMU3000 第五版原生重建與正面修正

先讀[原生車輛手冊](../../docs/art/native-vehicle-modeling/README.md)與[本輪外觀／重建交接](../../docs/art/emu3000-refresh-2026-10-25/README.md)。本工具只處理這次EMU3000，尺寸與專用三角預算不可套給其他車。

需求：Swift **6.4**、已安裝Node／Playwright／Chromium、Python NumPy／Pillow、Blender4.3。沒有新增依賴。OUT必須在公開庫外；原始參考不公開／不隨包散布／不送外部生成服務。

```sh
# 真正main前版：獨立worktree由原commit重建，不倒改新模型。
git worktree add --detach /tmp/emu-before 85d9aa359dfcd6213f76a6559abebd9155806e97
tools/emu3000-refresh/capture-baseline.sh /tmp/emu-before /tmp/emu-baseline
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DEMU3000Tests|Map3DHighSpeedSetsTests|Map3DTrainSetTests|Map3DModelTests|Map3DModelFileTests|Map3DRealTrainsTests'
# 保存真正第四版完整原生／manifest／配方到OUT/history/4b6352d8，
# 真未提交初稿到OUT/history/first-pass；先提交配方／工具，再匯出同一producer。
PRODUCER_COMMIT=$(git rev-parse HEAD) EMU_BASELINE=/tmp/emu-baseline EMU_FINGERPRINTS=/tmp/current-pack \
  tools/emu3000-refresh/export.sh OUT
node tools/emu3000-refresh/verify.mjs OUT
python3 tools/emu3000-refresh/front-audit.py OUT
python3 tools/emu3000-refresh/door-audit.py OUT
python3 tools/emu3000-refresh/support-audit.py OUT
python3 tools/emu3000-refresh/revision-audit.py ACTUAL_REVISION_4 OUT
python3 tools/emu3000-refresh/coexistence.py /tmp/emu-baseline /tmp/current-pack OUT
node tools/emu3000-refresh/review.mjs OUT
# 親自打開ED／EP3／完整編組配色、白模、剪影的側／正／上／斜；不合格再修。
node tools/emu3000-refresh/render.mjs OUT
blender --background --python tools/emu3000-refresh/glb-audit.py -- OUT
python3 tools/emu3000-refresh/verify-png.py OUT
node tools/emu3000-refresh/standalone.mjs OUT
node tools/emu3000-refresh/browser-check.mjs OUT
node tools/emu3000-refresh/browser-check.mjs OUT --standalone
# reference-review／appearance-review／README／同head CI及evidence先備好，才打包。
python3 tools/emu3000-refresh/bundle.py OUT ACTUAL_PRODUCER_COMMIT
node tools/emu3000-refresh/browser-check.mjs OUT
python3 tools/emu3000-refresh/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# 最後實際點viewer下載ZIP、比最終SHA；證據留ZIP外避免自我雜湊。
```

export.swift：M3DM v1逐頂點／法線／顏色／layer讀回；signed-zero正規化。12節用自含合法單元M3DAssembly，不造超限M3DM。Swift／JS組裝payload逐bytes一致；GLB轉換(x,z,-y)，公尺與輪底基準見manifest。recipe_version=5，所有最終視圖來自同份最終原生模型。

第四版側面保持，僅修前艙橫斷面／前端寬度／黑罩及前部貼合。圓U分色以半平面切原殼，各相鄰原三角傳遞邊切點，局部中心扇只在有共線分點時使用；分色不靠外掛片。風擋／燈座的凸輪廓逐實際朝前殼三角切分、沿X薄擠出，遠景也不跨凸面；輪廓需凸形且順序連續。圓燈依真正正面投影定尺寸，不沿角度參數拉伸。前罩縫仍投到真殼，門葉仍用白殼、封閉薄門縫／分段玻璃；字典邊排序保證重建順序穩定。

verify.mjs驗所有單元封閉有向邊／正體積，GLB相同幾何，Swift／JS組裝逐bytes；缺面／反面／偏移組裝變異拒收。前版只保存比對，不宣稱通過新品質要求。

front-audit.py針對近遠頭尾真正朝前、朝上的風擋大面射線，排除薄邊壁與實際窄雨刷的預期遮擋；實際連通風擋往殼內移120mm必須被射線拒收。發光連通體的實際前平面bounds抓圓燈拉長，Swift同樣在真4b6352d8先紅4項。不能把本檢查說成與參考的相似度分數。

door-audit.py對16單元側門玻璃正面centroid向外射線，拒收3mm以上遮擋及1mm同深度異色衝突；Swift另有實際埋玻璃100mm變異。中間門不改，端車隨新截面重新貼合。

support-audit.py用實際三角精確最近距離（玻璃背襯≤120mm），真正8個輪胎連通體貼軌0及上方5–300mm靜態淨空、屋頂65mm容差取樣支持圖。浮玻璃1m／升輪變異拒收；不是全表面碰撞、懸吊或真接觸網證明。

revision-audit.py對真正4b6352d8原生三角多重集合：12中間payload全同、頭尾差集限前艙x≥6.2、走行／設備／連結器／總bounds保持；抽取真殼連通體，101個切平面的側面上下包絡差須<20微米。是真模型量測，不把透視像素叫工程尺寸。history/4b6352d8保存真正原生／組裝／manifest／配方，完整revision-4私庫保持；bundle逐件核前版SHA。

近景頭尾8962／整列74676，遠景3834／整列33716。專用上限9200／4000，較第四版全列增約0.8%／1.8%，為圓弧分色與貼合修正；不提高410共用2k／4k預算。500m切遠景、900m後原盒形，真機成本UNVERIFIED。

render.mjs產168七向透明圖及真正同相機／公尺尺度revision-4-vs-5.png、chin-before-after.png局部、門保持對照、風格比較。局部嵌入有留白不透明頁，完整七向不裁邊。review.mjs先看ED／EP3／編組四向配色白模剪影，不能以測試綠燈取代外觀。

coexistence.py比168既有非EMU模型每個Float32位置／顏色／layer bytes。glb-audit.py用獨立Blender glTF匯入量bounds／三角／頂點色／霧面無貼圖。verify-png.py全PNG完整Pillow解碼、七向alpha與不裁邊。

browser-check.mjs實際載入24件、旋轉／縮放／七向、原生GLBPNGZIP下載SHA、390px版面／無外部遺漏請求；離線同HTML以setContent實測，file://直接導覽UNVERIFIED。bundle.py核實際producer的全部來源bytes、最終模型／PNG哈希、唯一公開總覽同最終渲染，ZIP全解壓逐檔bytes。package-verification.json留ZIP外避免雜湊自我參照；ci-status-at-packaging只表示當時同head，最新看PR。
