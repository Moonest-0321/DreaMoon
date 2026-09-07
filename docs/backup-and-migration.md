# 備份、遷移與資料修復

V4.4.2 的 StoryPlanning schema V5 以新增 `OutlineStageStartDetail` 的輕量遷移升級 V4。既有 `OutlineStageStartAnchor` 不改寫；缺少 detail 的舊資料在執行時視為節次定位。主書庫正文與大綱項目錨點不參與此遷移。

## 目前啟動順序

1. 尋找舊版 V3 或 V2 store。
2. 建立／開啟 V5 主資料庫。
3. 將舊資料匯入 V5；若 V5 已有資料，先驗證匯入完整性。
4. 執行懸空資料修復與 V4／V5 回填。
5. 開啟物品副本、能力進度與故事規劃的獨立 store；故事規劃 store 依 `StoryPlanningMigrationPlan` lightweight migration 至 V3，再轉換舊結構標籤。
6. 完成各 store 的資料修復後才顯示主畫面。

## 目前資料檔

- 主資料：`Sailune-v5.store`
- 舊資料來源：`Sailune-v3.store`、`Sailune.store`
- 物品副本：`Sailune-v5-item-copies.store`
- 副本等級選擇：`Sailune-v5-item-copy-level-selections.store`
- 能力進度：`Sailune-v5-ability-progress.store`
- 故事規劃：`Sailune-v5-story-planning.store`

實際位置由應用程式的 Application Support 目錄決定；測試時可使用 `SAILUNE_TEST_STORE_URL` 指定主資料庫。

## 歷史版本差異（保留、不修改）

- V1／V2 使用較早的模型命名與資料範圍。
- V3 將時間軸、紀元、時間釘子與事件納入 released schema。
- V5 將物品、角色設定與多項歷史資料納入主 schema，並把物品副本拆至獨立 store。
- Git 產品版本曾出現 V2.3.4、2.4.5 後再回到 V2.3.5 等命名順序差異；這些是歷史事實，不修改提交訊息。

## 可持續遷移規則

- 歷史 schema 只能新增新快照，不得修改已發布快照。
- 遷移與回填必須可重複執行（idempotent）。
- 匯入前後驗證每個核心實體的 UUID 數量與集合。
- 任何回填不得刪除原始資料，除非有明確且可驗證的孤立資料規則。
- 新版本發布前，使用代表性舊 store 做開啟、匯入、重新開啟與資料抽查。
- 多 store 備份必須視為一組；只備份主 store 會造成副本、能力或故事規劃遺失。

## 已知缺口

- 目前介面尚未提供完整的使用者備份／復原流程。
- 未建立自動化的多 store 一致性檢查與備份封裝格式。

## V4.2 故事規劃遷移

- `StoryPlanningSchemaV1`、V2、V3 均保持不變；V3 新增 `OutlineItemAnchor`，不回寫 V2 的 `OutlineItem` snapshot；V4 只新增獨立的階段開始定位與手動安置模型，不改寫 V3 的 `OutlineStage`／`OutlineItem`。
- store 檔名維持 `Sailune-v5-story-planning.store`，由 SwiftData lightweight migration 原地升級；發布前仍需把它與主 store 一起備份。
- V2→V3 開啟後在同一個 save 內將主軸／支線／計劃加入轉為同 UUID 的大綱項目及錨點，成功後才刪除原標籤；伏筆／修改不變。檔案型測試會驗證轉換與重開不重複。
- V4.3 的故事背景引導不新增 SwiftData 欄位或 schema；使用既有 `backgroundText` 的可版本化結構值保存。舊自由文字讀取時視為「其他背景」，首次儲存才轉為結構值，內容不遺失。
- V3→V4 以 lightweight migration 開啟。既有階段不從最早正文項目猜測開始位置，既有手動項目不猜測安置位置；兩者保留原資料並在 UI 顯示需設定／待安置提示。檔案型測試驗證舊 V3 資料重開後 UUID 與數量不變。
- V4.4 的寬版工作區、時間軸投影及故事背景入口搬移均為呈現層變更，不新增 schema、不複製 `OutlineItem`，也不搬動 `backgroundText`；因此不需要新的資料遷移。無法解析的時間軸位置只在執行期間列入待安置區。
- 主 store 內既有 `Timeline`、`Node`、`Event` 不刪除、不改寫，也不自動複製為 V4.2 `OutlineItem`；第一版採保留策略，避免在時間語意尚未定案時錯誤轉換使用者資料。
