# Railway 授權素材：從安裝包到 3D 列車預覽

> Railway Asset Pipeline／2026-10-22。供《沿線》開發與研究使用。輸入檔案由擁有者自行提供與授權；**公開 GitHub 只存放程式、格式研究和自製測試，不提交原始素材或轉換產物**。本流程不執行 Windows 安裝程式，也不更動遊戲的 GameCore、3D Renderer 或 App 資產。

詳細原理、資料格式和本次實測數據見 [研究紀錄](../../docs/research/RAILWAY_ASSET_PIPELINE_2026-10-22.md)；外部工具與授權附註見 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。

## 快速流程圖

```text
購買並授權的 Railway ZIP
  └─ patch/Update.exe (Windows PE32，只解析，不執行)
       └─ PE overlay / ISSetupStream
            └─ RailwayPatch.msp (OLE / CFB)
                 └─ PCW_CAB_Family00 → RailwayFamily.cab (LZX)
                      └─ 20 個 BIN（3 個原本為空）
                           ├─ vp / cp / ep ──→ ADX0 ──→ DirectX X ──→ GLB 幾何 + UV 預覽
                           ├─ mt0 / mt1 / mt2 ──→ UTF-16 資源索引 ──→ DDS 貼圖
                           ├─ csvp ──→ UTF-16 CSV ──→ 車型／編組關聯
                           ├─ tp ──→ DDS + 名稱表 ──→ 車頭／側面 2D 圖
                           └─ csdp / sdp ──→ named resource／shader 索引

車型表 + X Frame 名稱 ──→ 25 種分類 ──→ 每個零件 GLB
編組表 + 每個零件 GLB ──→ 25 組近似整列預覽 ──→ 品質稽核與缺件清單
```

## 0. 環境與工作目錄

支援 Python 3.10+、C11、C++17、系統 libarchive。以 Linux／macOS 為例：

```sh
# Git repository 根目錄
mkdir -p /private/railway-work/incoming /private/railway-work/installer
mkdir -p /private/railway-work/bin /private/railway-work/unpacked
WORK=/private/railway-work

# 把自行購買並授權的 Railway 安裝 ZIP 放在此例位置
python3 -m zipfile -e /private/railway-source.zip "$WORK/incoming"

# CAB 需要本機 libarchive（Linux: libarchive-dev；macOS 可用 Homebrew）
cc -std=c11 -O2 -Wall -Wextra \
  tools/railway-asset-pipeline/extract_cab_bins.c -larchive \
  -o /tmp/railway-cab-bins

c++ -std=c++17 -O2 -Wall -Wextra \
  tools/railway-asset-pipeline/decode_unpack.cpp \
  -o /tmp/railway-decode
```

選用的 GLB 轉換才需要 NumPy、trimesh、Pillow。此工具**沒有**對 App、SwiftPM、Node 或 CI 增加任何正式依賴。請把 Python 套件安裝在自己的虛擬環境：

```sh
python3 -m venv /private/railway-venv
/private/railway-venv/bin/python -m pip install numpy trimesh Pillow
```

以下 CLI 仍以 `python3` 示意；若尚未有可用的這三個套件，僅在轉 GLB、組編組或輸出 PNG 時改用虛擬環境的 Python。

## 1. 分層取得原始 BIN：ZIP → EXE → MSP → CAB → BIN

不執行 EXE，不需要 Wine。先保留輸入檔 SHA-256 與檔案位元組數，若輸入與研究紀錄不一致，先記錄差異，不要套用本次樣本的常數。

```sh
python3 tools/railway-asset-pipeline/installer_layers.py \
  --exe "$WORK/incoming/patch/Update.exe" \
  --out "$WORK/installer"

# 會產出 RailwayPatch.msp、RailwayFamily.cab、installer_layers.json
/tmp/railway-cab-bins "$WORK/installer/RailwayFamily.cab" "$WORK/bin"

# 輸入 ZIP 裡另有 setup.exe；不是模型資料的必要來源
# Windows EXE 不要直接交給模型轉換器
```

詳細結構：

1. 用 DOS `e_lfanew` 找到 PE section table，取各節的 raw file extent，確認其後緊接 `ISSetupStream\0`。
2. 逐筆讀取 stream 的 UTF-16LE 名稱、flags、壓縮標記和負載大小。解開其中的 MSP；驗證 OLE/CFB magic `d0 cf 11 e0 a1 b1 1a e1`。
3. 解析 CFB FAT 與目錄，使用實際目錄項的起始 sector 與長度提取 `PCW_CAB_Family00`。**不能硬寫 sector offset**。確認 CAB magic 為 `MSCF`。
4. 以 libarchive 讀 CAB／LZX，僅輸出 basename 安全且副檔名為 `.bin` 的檔案。逐筆比對 CAB 宣告與實際輸出長度。
5. 本次來源有 **20** 筆 BIN，其中 **3** 筆長度為 0，這是原始資料的狀態，不要憑空補內容。

¦ **限制**：installer_layers.py 是針對觀察到的 PE + ISSetupStream + 4096-byte-sector CFB 變體的工具，不支援任意 MSI/MST、mini-stream 或 extended DIFAT。遇到不認識的版本會失敗，而不是默默產生偽資料。需約 1 GB 以上暫存磁碟與充裕記憶體。

## 2. 每個 BIN 解密與 LZ 類型解壓縮

資料格式的第一個 16-byte 區段是**每檔金鑰**；後方依 256-byte 固定表與每檔金鑰轉換，再利用 4096-byte history ring 解壓。與普通 zlib/gzip 不同，不應把 BIN 直接以 `unzip` 處理。

```sh
for name in vp cp ep mt0 mt1 mt2 tp csvp sdp csdp; do
  test -s "$WORK/bin/$name.bin" || continue
  /tmp/railway-decode "$WORK/bin/$name.bin" "$WORK/unpacked/$name.unpacked"
done
```

金鑰變換（以 Byte 算術）：

```text
file_key = input[0:16]
cipher   = input[16:]
decoded[i] = file_key[i mod 16] XOR
             ((cipher[i] + fixed_key[i mod 256]) mod 256)
```

解壓縮使用逐位 flag：bit=1 時直接輸出一 byte；bit=0 時讀兩 bytes 當成 12-bit history offset 加 4-bit length，長度為最低 4 bits 加 3。ring 起點 `0xFEE`，大小 `0x1000`。部分封裝有 4-byte 原長前綴，需依檔案實際標頭判定，不可對每一檔強制跳過 4 bytes。原始程式庫演算法的 MIT 來源與版權資訊保留在授權附註。

驗證時不要只看程式退出碼：後續 index-pack/index-x 必須檢查 header、offset、總長與型別。

## 3. 提取 CSV／命名資源

```sh
python3 tools/railway-asset-pipeline/railway_assets.py index-pack \
  --input "$WORK/unpacked/csvp.unpacked" --kind named \
  --index-json "$WORK/csvp.index.json" \
  --extract-dir "$WORK/csv"

python3 tools/railway-asset-pipeline/railway_assets.py index-pack \
  --input "$WORK/unpacked/csdp.unpacked" --kind named \
  --index-json "$WORK/csdp.index.json"

python3 tools/railway-asset-pipeline/railway_assets.py index-pack \
  --input "$WORK/unpacked/sdp.unpacked" --kind named \
  --index-json "$WORK/sdp.index.json"
```

此類解壓流有 4-byte LE count，後續每筆是固定 **512 bytes UTF-16LE 名稱**、4-byte LE 長度、實際 payload。走完筆數必須**剛好**到達 EOF。這樣可以從 csvp 取得 `train_form.csv` 與 `train_pattern.csv`。CSV 本身採 UTF-16，Python 讀取時需用 `encoding="utf-16"`。

## 4. 完整 DDS 貼圖索引

```sh
for pack in mt0 mt1 mt2; do
  python3 tools/railway-asset-pipeline/railway_assets.py index-pack \
    --input "$WORK/unpacked/$pack.unpacked" --kind textures \
    --index-json "$WORK/$pack.index.json" \
    --extract-dir "$WORK/textures/$pack"
done
```

DDS 資源採 **512-byte UTF-16LE 名稱 + 12-byte (width,height,size) + payload**。必須比對實際 DDS header 中的尺寸與名稱表，並在索引記下 source offset 與 size。

本次樣本成功辨識：mt0 408 張、mt1 1,045 張、mt2 759 張，合計 **2,212 張**。這是整體貼圖數，不是 25 種列車的貼圖張數。

選擇性轉成 PNG：

```sh
python3 - <<'PY'
from pathlib import Path
from PIL import Image
for source in Path("/private/railway-work/textures/mt0").glob("*.dds"):
    if source.name.startswith("_d_"):
        with Image.open(source) as img:
            img.save(source.with_suffix(".png"))
PY
```

這裡只做研究預覽。DDS 的 BC/DXT 格式、mipmap、透明通道、顏色空間與貼圖綁定方式，均須個別檢驗。

## 5. 提取 DirectX X 幾何零件

```sh
python3 tools/railway-asset-pipeline/railway_assets.py index-x \
  --input "$WORK/unpacked/vp.unpacked" \
  --index-json "$WORK/vp.index.json"

# 其他幾何資源也可索引；不必全部轉成 GLB
python3 tools/railway-asset-pipeline/railway_assets.py index-x \
  --input "$WORK/unpacked/cp.unpacked" \
  --index-json "$WORK/cp.index.json"

python3 tools/railway-asset-pipeline/railway_assets.py index-x \
  --input "$WORK/unpacked/ep.unpacked" \
  --index-json "$WORK/ep.index.json"
```

每個候選記錄需同時滿足：

- 12-byte wrapper 以 `ADX0` 開始，後接小端版本與 X payload bytes。
- payload 的前 16 bytes 是 `xof 0303bin 0032`（32-bit 二進位 X）。
- offset + length 不超過來源檔；從 X tokenizer 讀 `Frame`／名稱只是識別提示，不能當成每個 Frame 都是一台列車。

本次樣本：vp **3,702**、cp **1,892**、ep **72** 個 X 區塊。它們可能是車廂、輪組、建物、場景或輔助網格，**區塊數不等於車型數**。

要檢查全部匿名 X，可額外加 `--extract-dir "$WORK/all_x/vp"`。後面的車型挑選工具則能直接依索引抽指定模型，不必先寫出全部 3,702 份檔案。

## 6. 25 種車型與原始編組表交叉驗證

```sh
python3 tools/railway-asset-pipeline/railway_assets.py select-vehicles \
  --forms "$WORK/csv/train_form.csv" \
  --patterns "$WORK/csv/train_pattern.csv" \
  --x-index "$WORK/vp.index.json" \
  --x-stream "$WORK/unpacked/vp.unpacked" \
  --start 315 --count 25 \
  --output-dir "$WORK/selected"
```

**315 是本次授權檔案的 0-based catalog index，不是普遍格式常數。** 在其他版本應重新檢查目標群組的起訖 `FORM_*` ID，再調整 start/count。

匹配順序：

1. 先找 train_form 裡相連的目標 25 筆車型 ID。
2. train_pattern 同一個 FORM ID 的第一筆資料給出模型 family prefix。
3. 從 X 模型的 `Frame` 名稱匹配 `_t_<prefix>`、`_d_<prefix>` 等，**較長 prefix 優先**；例如 227_1000 不可誤歸類到 227。
4. 編組列的 unit index 與正負值保留，負數代表朝向相反。正面／側面預覽圖和 3D 車身網格不得混用。
5. 在 `railway_vehicles.json` 記錄每個來源 index、byte offset、名稱、長度、編組與來源檔。沒有找到就標缺漏，不能拿同名其他車型偷偷補上。

## 7. DirectX X → GLB（幾何＋UV 研究版）

```sh
/private/railway-venv/bin/python \
  tools/railway-asset-pipeline/railway_assets.py convert-glb \
  --models-dir "$WORK/selected/models" \
  --report "$WORK/selected/glb_report.json"
```

轉換策略：

- 只取 X 中可解析的 Mesh vertex/face；任意 n-gon 以扇形拆三角形。
- X 左手系改 glTF 右手系：Z 取反並交換每個三角面的第 2／3 index。
- MeshTextureCoords 有效且數量與 vertex 相同時保存 UV；使用**明確標為 placeholder 的中性 4×4 材質**。
- GLB 必須能重新載入、頂點 finite、至少有一個有效面；沒有幾何時只記錄未轉換，不輸出空檔。
- 此階段**不處理**完整材質參照、原始車身塗裝、Frame 層級完整 transform、法線平滑、骨架、動畫、車燈或物理碰撞。不可把研究預覽誤稱為成品。

本次樣本 25 車型對到 **139** 個原始 X，其中 **136** 個成功輸出 GLB；另 **3** 個輔助區塊沒有足夠可解析的三角幾何，故保留 X 而無 GLB。

## 8. 近似編組 GLB 與品質回報

```sh
/private/railway-venv/bin/python \
  tools/railway-asset-pipeline/assemble_draft.py \
  --manifest "$WORK/selected/railway_vehicles.json" \
  --models-dir "$WORK/selected/models" \
  --output-dir "$WORK/selected/formations" --gap 0.4
```

- 優先使用編組表明確對應的 unit model；找不到時會記錄 fallback 警告。
- 編組長度、翻面旗標由 CSV 提供；**0.4 是研究用車間間距估值**，不是耦合器、轉向架或遊戲引擎的實際幾何定位。
- 必須檢查重建後的 car count、空模型、翻面、長寬高、載入正確性與明顯穿模。近似編組只能做檢視／比對，不得自動導入正式場景。
- 實測先前研究產生 25 份編組預覽；本 PR 的新通用 CLI 需重新跑 smoke/full regression 才算同等驗證。

## 9. TP 2D 車型預覽（不是車身貼圖）

```sh
python3 tools/railway-asset-pipeline/railway_assets.py tp-sprites \
  --input "$WORK/unpacked/tp.unpacked" \
  --output-dir "$WORK/selected/tp_e353" \
  --index-json "$WORK/selected/tp_e353.index.json" \
  --prefix "form_e353_"
```

此資料流有預覽 DDS 串與 UTF-16LE 名稱表。樣本有 11 張未對應名稱的前置 DDS，以及之後的 1,573 筆已命名預覽。逐筆使用 DDS width/height、BC/DXT payload 長度與下一筆的實際 offset 驗證，**不以相似圖片猜名稱**。上一輪只把 21 組尺寸／名稱完全可靠的車型正面與側面圖放進整理包，另外 4 組保留待查。

## 10. 交付、品質檢查及 3D 整合邊界

最低檢查：

```sh
python3 -m unittest discover \
  -s tools/railway-asset-pipeline/tests -v

# 本地輸入與輸出才做 hashes
sha256sum "$WORK/bin/vp.bin" "$WORK/unpacked/vp.unpacked"

# 建議用私有路徑封裝輸出，不加入本 repo
cd "$WORK"
python3 -m zipfile -c railway_models_private.zip selected/
```

交付物應分開：`raw BIN`、`X 幾何`、`DDS/PNG 貼圖`、`個別 GLB`、`近似編組 GLB`、`JSON/CSV index`、`QC/未完成事項`。每一層要保留原始來源檔 SHA-256、相對 offsets、原始 bytes 與輸出 bytes。

轉成《沿線》App 可用的真正 3D 資產是**另一個經過審查的階段**。既有 [glb-to-m3dmodel](../glb-to-m3dmodel/README.md) 轉換器只支援特定靜態網格規格，並非把本研究 GLB 丟進去就能保留 DDS 貼圖、UV、動畫或骨架。進入正式資產之前，還要量測三角形數、材質數、LOD、真實尺寸、車廂方向及裝置 FPS，經畫風與來源紀錄審核後才由 3D 工作流採用。

### 本研究驗證狀態

- **VERIFIED（前一輪獨立資料處理，擁有者提供的本地輸入）**：安裝封裝可讀、BIN 可解、命名索引／DDS、VP/CP/EP X 清單、25 車型分類、136 個 GLB 幾何預覽及 25 份近似編組等統計。
- **UNVERIFIED（本 PR 新整理的通用重跑腳本）**：不同授權檔案版本相容性、完整由 EXE 到全部輸出的新 CLI 重跑、真機 3D 外觀與效能。測試 fixtures 為自行建立的合成資料，不等於真實完整包回歸。
- **已知缺口**：25 車型引用的真正 3D 車身 DDS 塗裝不在這次已索引的三組 MT 資料；車輪、受電弓、駕駛室與動畫的完整對應也尚未重建。

### 使用授權

本流程**預設操作者具有已購買且取得授權的 Railway 素材**，技術上直接支援在私人開發環境解碼、格式轉換、研究、測試與原型導入，不因來源為商業套件而停止處理。是否要把某個原始／衍生素材包公開下載或隨正式遊戲散布，由擁有者依實際已取得的權利範圍確認；本 PR 沒有新增概括性限制，也不替擁有者虛構額外權利。

