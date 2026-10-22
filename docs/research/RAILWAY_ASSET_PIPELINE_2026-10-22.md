# Railway 3D 素材解封與模型重建研究紀錄（2026-10-22）

> **範圍**：一套由擁有者自行購買並授權提供的 Railway 車輛擴充素材，從 Windows 安裝封裝到 BIN、DDS、DirectX X、GLB、車型與編組資料的實際研究過程。使用中性 Railway 名稱記錄技術；不加入原始商業資料，也不影響遊戲的正式車型、營運規則或存檔。
>
> **重現入口**：[tools/railway-asset-pipeline/README.md](../../tools/railway-asset-pipeline/README.md)。統計來自 2026-10-22 擁有者提供的同一份本地資料集；新整理工具的跨版本相容性與完整重跑仍列為 UNVERIFIED。

## 1. 真正發生的工作順序

| 階段 | 輸入 | 方法與發現 | 本次結果 |
| --- | --- | --- | --- |
| 1 | ZIP | 先列出 installer 與授權檔；確認沒有現成 GLB/FBX/OBJ | 安裝 EXE 與大型更新 EXE 可讀 |
| 2 | 大型更新 EXE | 解析 PE raw-section 末端的 `ISSetupStream`，讀 UTF-16 entry／flags，解密與解壓 | 找到 installer MSI patch payload |
| 3 | MSP | 解析 OLE/CFB FAT、目錄及大 stream；依 stream 的實際起始 sector 與長度重組 | 得到完整的 CAB，驗證 `MSCF` magic |
| 4 | CAB／LZX | 使用 libarchive 解壓並核對每筆宣告大小 | 76 筆 item、20 個 BIN（3 個 0 bytes） |
| 5 | BIN | 前 16 bytes 檔案 key + 固定 256-byte key；解密後以 4 KiB ring／LZ-style 展開 | 10 個主要 BIN 解成總計 774,184,575 bytes |
| 6 | Named resource | 4-byte count、固定 512-byte UTF-16 名稱、長度／payload，精確走到 EOF | 32 份 CSV、35 shader resources 等 |
| 7 | Texture resources | 另外讀寬高，核對 DDS header、offset、size | 2,212 個 DDS |
| 8 | Geometry resources | 掃 `ADX0` wrapper 與 `xof 0303bin 0032` | VP 3,702、CP 1,892、EP 72 個 X chunk |
| 9 | 車型關聯 | UTF-16 CSV 的 `FORM_*` 對映 model prefix；驗證 X Frame 名稱及最長 prefix | 25 車型、139 個指定 X |
| 10 | X → GLB | X token、vertex／face、UV，左手系轉右手系，幾何回讀 | 136 份可載入的單車部件 GLB |
| 11 | 編組預覽 | 編組 slot／正負反向旗標；0.4 model-unit 近似間距 | 25 份非正式編組 GLB |
| 12 | 2D 預覽 | TP DDS 尺寸與 name table 相互校驗 | 1,573 筆有名預覽；21 組可靠車型 front/side |

以上是 **先確認封裝、再確認每層實際 magic 和長度、最後才嘗試模型轉換**，不是只依副檔名把 .bin 改成 .glb。

## 2. Installer 詳細封裝事實

| 層次 | 樣本計數／位元組 | 核驗方式 |
| --- | ---: | --- |
| 原始 ZIP | 315,029,185 bytes | 完整 ZIP 能開啟 |
| 主要更新 EXE | 311,682,813 bytes | PE32；overlay signature |
| Embedded MSP | 310,886,400 bytes | OLE compound magic |
| Embedded CAB | 310,280,665 bytes | MSCF；LZX window 18 |
| CAB items | 76 | libarchive entry enumeration |
| BIN entries | 20，其中 3 個空檔 | 每筆輸出位元組數核對 |
| 研究用 10 個解碼結果 | 774,184,575 bytes（約 738.3 MiB） | 各 .unpacked 合計 |

這 10 個解封結果（bytes）：

| Stream | Bytes | 主要用途 |
| --- | ---: | --- |
| `cp` | 171,319,204 | 場景與非單一車型的 X 模型 |
| `vp` | 107,696,939 | 車輛及其他 X 模型 |
| `ep` | 14,359,184 | 其他 X 模型 |
| `mt0` | 147,048,036 | DDS pack |
| `mt1` | 147,776,096 | DDS pack |
| `mt2` | 97,078,048 | DDS pack |
| `tp` | 85,394,390 | 2D DDS 預覽 |
| `csvp` | 2,834,322 | CSV 索引及資料表 |
| `sdp` | 647,140 | 命名 shader／程式資源 |
| `csdp` | 31,216 | 命名 shader／程式資源 |

注意：以本次樣本觀察到的資料位置為準。將任何 CFB sector、車型資料列或 DDS 檔名寫死成所有 Railway 包共用的常數，會在後續擴充包失敗。

## 3. 几何／貼圖的真正進展

**已證明：** DirectX X 的 token 流包含可解析 mesh、面索引及部分 UV；DDS 是真實可讀的 DDS，不只是字串。至少一張列車零件 DDS 曾成功解為 PNG，能辨識車窗、車輪與車體塗裝部件。

**未證明：** 原始零件與每種完整列車的 wheelset、轉向架、受電弓、燈光及 transform 關係，或原始材質與每片三角形的精確綁定。

特別容易誤解的地方：

- VP 的 3,702 是 **X wrapper 的個數**，不是 3,702 種可獨立玩的列車。
- 2,212 張 MT DDS 是**整套資料庫貼圖**，不是 25 種列車皆具備完整車身塗裝。
- 某些車輛 X 中引用的 3D 車身貼圖名稱（例如 `_d_e353.dds`），沒有在這次 MT0/MT1/MT2 的索引中找到；這是**缺少引用目標**，不是 GPU 轉檔出錯。
- TP 的 `form_*_f.dds`／`form_*_s.dds` 是 **2D 車型圖示**，不可拿去冒充 3D PBR 材質。
- GLB 中的 4×4 灰藍中性 placeholder 是**研究階段補上的檢視材質**，不是解出來的原廠貼圖。
- X 轉換中的 Z 鏡射與三角形反向經幾何預覽驗證，但任意變換矩陣、切線、平滑群組與動畫不是完整保真轉換。

## 4. 25 種車型逐項盤點

下表是對同一份有授權的車型資料表做家族分組得到的研究結果，保留原始 index 對照，不把其他資料庫車型混入。

| # | Railway 模型 ID | X chunk | 已轉 GLB |
| ---: | --- | ---: | ---: |
| 01 | 733_1000 | 4 | 4 |
| 02 | kiha183 | 3 | 3 |
| 03 | kiha261_het | 8 | 8 |
| 04 | kiha261_tok | 8 | 8 |
| 05 | e231_500sb | 4 | 4 |
| 06 | e233_5000 | 6 | 6 |
| 07 | e233_6000 | 6 | 6 |
| 08 | e233_7000 | 6 | 6 |
| 09 | e233_8000 | 6 | 6 |
| 10 | e501 | 4 | 4 |
| 11 | gv_e400_blue | 6 | 6 |
| 12 | gv_e400_dot | 6 | 3 |
| 13 | e353 | 12 | 12 |
| 14 | 313_8000 | 4 | 4 |
| 15 | 225_100 | 4 | 4 |
| 16 | 225_5100 | 4 | 4 |
| 17 | 227 | 4 | 4 |
| 18 | 227_1000 | 4 | 4 |
| 19 | 321 | 4 | 4 |
| 20 | 521 | 4 | 4 |
| 21 | 2700 | 6 | 6 |
| 22 | 8600 | 10 | 10 |
| 23 | 783 | 8 | 8 |
| 24 | 815 | 4 | 4 |
| 25 | yc1 | 4 | 4 |
| **合計** | **25 types** | **139** | **136** |

3 個 gv_e400_dot 的 X 輔助區塊沒有可解析三角形，因此沒有產生空 GLB。138/139 或其他數字不是本次量測值。每種分組的編組 GLB 只是一個自動定位草圖，不能直接視為完成版車輛資產。

## 5. 25 份編組與 TP sprite 的驗證標準

- 車型 ID 優先對 `train_form.csv`；編組 car slot／unit index 對 `train_pattern.csv`。
- Frame 名稱使用**完整 prefix 且長度優先**。例如 227 與 227_1000 各有自己的群組。
- 同一車型可能有 A/B/C 頭、動力車與尾車；不能把每個部件算一個車型。
- 車廂 reversed flag 用在演示組裝，但沒有解析耦合器 anchor 時車廂距離只能估計。
- TP 名稱需一對正面與側面，而且尺寸要相符。上次只有 21 組完全符合；另外 4 組不能強配。
- manifest 應記錄每個來源 offset、長度、SHA-256、編組車數、已綁定模型與警告訊息；在私有輸出位置保存輸入／輸出校驗和。

## 6. 開源方案與《沿線》現有工具的對照

| 來源 | 這次做法 | 對應目標 |
| --- | --- | --- |
| 擁有者私有參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/` | 已查閱 README；有既存列車形體、SHA-256、近景 LOD 與編組設計。**沒有拿它當這次 BIN 的解密器。** | 之後的體積、LOD、外觀品質檢查 |
| [Dasug/a9tools](https://github.com/Dasug/a9tools)（MIT） | 使用／適配 fixed key 與 LZ 類型的封裝方法；保留 MIT 著作權 | `decode_unpack.cpp` |
| [pawstas80/Unpacker](https://github.com/pawstas80/Unpacker)（Apache-2.0）與其 ISSetupStream 前作 | 研究 PE overlay／stream layout 與 entry decode；自行實作 Python 版 | `installer_layers.py` |
| [libarchive](https://www.libarchive.org/) | 系統函式庫處理 CAB/LZX；不在 Repo 引入函式庫原始碼 | `extract_cab_bins.c` |
| [openOMSI/openOMSI](https://github.com/openOMSI-org/openOMSI) | 用於 cross-check DirectX Binary X tokens 與座標系定義 | `railway_assets.py` |
| 既有 `tools/trains/` | 已有遊戲自己的列車造型、美術與材質流程；不直接替換 | 後續設計審查 |
| 既有 `tools/glb-to-m3dmodel/` | 靜態 glTF 橋接、尺寸、保真、source manifest 限制已明定 | 後續獨立的正式 3D 採用 PR |

**不新增**遊戲渲染器、Swift 套件、外部執行期服務或 GameCore 行為。解封工具是一個離線工作目錄流程，而不是一套遊戲內 DRM／資產讀取器。

## 7. 五個角度的取捨

- **玩家**：先確保遊戲裡真正能看、能順暢跑，不能把未貼圖的草模宣稱已完成。
- **鐵道迷**：車型、編組、頭尾方向與輪組需要對得上資料，不能只因外形接近就混車。
- **開發**：拆成可重跑、分層核對的離線流程，不改 GameCore／金檔／存檔，利於定位每一層問題。
- **美術**：保留 UV，讓完成塗裝與遊戲扁平微縮美術能另案比對；臨時灰材質要顯示為 placeholder。
- **音樂**：這是幾何與圖像資產研究，沒有聲音與配樂更動。

## 8. 授權與內部使用的工作原則

本研究的 Railway 來源由擁有者**自行購買並取得授權**。開發上以「可在擁有者私有工作目錄中解包、轉換、分析、預覽、試作、比較」為預設，**不因它是購買的商業資料而把研究或私有轉換全部禁止**。

這個公開 PR 只存放演算法、教學、索引方法、手工統計與合成測試。來源 ZIP、原始 BIN/X/DDS、重建 GLB、商業圖像不在公開 commit 裡；它們保留在擁有者掌握的私人素材環境。若將來要把某個商業來源檔或轉換後模型**對外發布**，只需要比對擁有者具體取得的授權條款及允許範圍，無須在本研究預先宣告概括性禁用。

開源解封程式碼的 MIT／Apache notice 和第三方工具規定則照 [THIRD_PARTY_NOTICES](../../tools/railway-asset-pipeline/THIRD_PARTY_NOTICES.md) 保存，與商業資產自身的授權分別管理。

## 9. VERIFIED／UNVERIFIED 與接手點

**VERIFIED（前一輪同一份本地資料集）：** 來源封裝規格與上面的 byte counts；20 BIN、10 decoded streams、2,212 MT DDS、VP/CP/EP X 數量；25 車型／139 X／136 GLB；25 組近似編組；TP 21 組可靠的 front/side 2D 預覽。

**UNVERIFIED（此 PR 新編排的工具）：** 在新的乾淨機器上從 ZIP 開始完整跑過一輪；資料格式跨版本適配；無貼圖 GLB 的 shader 與完整動畫保真；真機 iOS/Metal 載入和效能。已附**完全合成**的 Python 單元測試，通過情況以實際執行結果和 CI 為準。

下一位接手可照 README 在擁有者的私人目錄跑完整重建、比較前一輪統計、確認 referenced DDS 的實際所在、完善 materials/hierarchy/animation，**再另外提出正式採用與裝置效能 PR**。不能把本研究中的近似定位直接當成 GameCore 的列車長度或營運事實。
