# 三鶯線列車：貼給新對話

這是下一個製作任務的入口，本輪工具更新**沒有製作三鶯線模型**，車型／編組／尺寸仍須下一位查證。

```text
請製作「新北捷運三鶯線列車」原生3D素材。

先讀最新main的docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md，依其中完整流程實作；同時讀AGENTS.md／CLAUDE.md／HANDOFF、rolling-stock、原生建模手冊及tools/train-models/README.md、railway-assets-private的AGENTS.md。查相關工具PR是否已合併，從最新main開獨立codex/分支並在#1041認領，不假設本對話任何分支已進main。

親自搜尋、下載並開啟新北捷運工程主管機關／營運單位、製造商的實車原圖，再用可靠照片交叉比較。先確認正式車型、尺寸、編組／朝向、各單元差異、兩側門窗、風擋與車頭曲面、燈、屋頂設備、走行與集電方式。實車、效果圖、插畫要分開；來源看不到的設備標待查，不照C371／C381補成六車或鏡像複製。照片只供觀察時不把原圖提交素材庫，保留來源／作者／授權紀錄。

先做正側俯斜的比例、白模及剪影，自己看圖修主曲面，再做塗裝／門窗／燈／支承細節。C371／C381只作工具與風格參考，不直接換色搬它們的車頭、底盤或設備排列。

本輪完成各獨立單元、由它們重建的完整編組與必要遠景版，作studies靜態展示；營運映射、購車、班表、動畫、GameCore／存檔／golden不在範圍。使用共用編組JSON、GLB與驗收／交付工具；本車專用玻璃可見性、設備接觸、輪軌淨空和近遠景檢查仍需實作並驗故障反例。保護其他車款payload。

公開放程式／文件及一張小總覽，成品放railway-assets-private的單一模型輪次。整輪PNG最多21張、各≤2MiB、單檔≤50MiB、PR新增≤200MiB；不放ZIP或history副本。以producer／git歷史留真前版；同PR移除被取代輪次重檔。用deliver.py、asset_guard及真viewer下載檢查完成交付。

持續做到可審查成果，推公開與素材draft PR互鏈、更新#1041與HANDOFF，報實際CI及四種完成狀態。外觀須我明確接受該producer才記已接受；技術通過不等於外觀／裝置通過。不要合併、開auto-merge或啟動TestFlight。
```
