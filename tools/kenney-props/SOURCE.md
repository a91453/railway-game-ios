# SOURCE — tools/kenney-props

| 欄位 | 內容 |
|---|---|
| 來源 | 第三方：Kenney（https://kenney.nl）的 Nature Kit 與 City Kit (Industrial)；本專案改形、換色、轉檔（決策 458） |
| 授權 | CC0 1.0 Universal（公眾領域貢獻宣告）。全文 `source/CC0-1.0-legalcode.txt`（SHA-256 `a2010f34…0499`，取自 https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt）；兩包 zip 裡原樣的 `License.txt` 是 `source/nature-kit-License.txt`、`source/city-kit-industrial-License.txt` |
| 署名 | 不要求；遊戲的資料來源頁（`DataSourceCredits`，id `kenney`）寫「Kenney」與兩包的網址。不用 Kenney 的標誌（https://kenney.nl/support，2026-10-28：logo 只給官方專案）。 |
| 公開 | 可以：CC0，放公開庫與 App |

## 兩包的版本

2026-10-28（UTC）從各包頁面的「Continue without donating」下載，素材庫 `a91453/railway-assets-private` 的
`game-art-previews/docs/art/free-assets-kenney/SOURCE.md` 記了 zip 的大小與雜湊：

| 包 | 頁面 | `License.txt` 版本、日期 | Zip bytes | Zip SHA-256 |
|---|---|---|--:|---|
| Nature Kit | https://kenney.nl/assets/nature-kit | 2.1, 29-04-2020 | 10,537,521 | `fa7974a0d342bfe63c38664ba9f8ec1a4aab8ea25f099bdc56870e33588c4d9d` |
| City Kit (Industrial) | https://kenney.nl/assets/city-kit-industrial | 2.0, 31-08-2026 | 5,045,077 | `5b381164e5760f3830a2dbee43b972deee38b2a695d091b56e238ab2910c96d2` |

## `source/` 的三個 GLB

不是 Kenney 的原檔，是素材庫試做（同上資料夾 `revision-1/glb/`，素材庫 commit
`a77fd212782eed37fb6913c4bbdfa3310f78b956`）用 `revision-1/scripts/bake.py` 把原檔的材質色烘成頂點色、換成遊戲色票後的 GLB：

| 檔 | 原件 | SHA-256 |
|---|---|---|
| `tree_pineTallA.glb` | Nature Kit `Models/GLTF format/tree_pineTallA.glb` | `8d2b81433606e0096c42c5478f5391422415699c36947be0f92858768fd0fed7` |
| `plant_bushLarge.glb` | Nature Kit `Models/GLTF format/plant_bushLarge.glb` | `c0463f321d78ab5c6b153e0fea7fe2b139be74bb7f7a91b1fdac8357f7dc3254` |
| `detail-tank.glb` | City Kit (Industrial) `Models/GLB format/detail-tank.glb` | `a0d831e69e3526c22396eb3a1c7246683b2ed72f53e0b3de64f1c59b353d406f` |

這次（工單 BN）沒有重新從 kenney.nl 下載：網站的下載連結要經它的下載 API，自動化工具帶標頭去要被判為繞過防機器人檢查，沒有做。上面的 zip 雜湊可以讓人手動下載後核對是同一個檔。
