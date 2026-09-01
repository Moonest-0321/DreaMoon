# 備份、遷移與資料修復

## 目前啟動順序

1. 尋找舊版 V3 或 V2 store。
2. 建立／開啟 V5 主資料庫。
3. 將舊資料匯入 V5；若 V5 已有資料，先驗證匯入完整性。
4. 執行懸空資料修復與 V4／V5 回填。
5. 開啟物品副本、能力進度與故事規劃的獨立 store；故事規劃 store 依 `StoryPlanningMigrationPlan` 從 V1 lightweight migration 至 V2。
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

- `StoryPlanningSchemaV1` 保持不變；V2 新增全書背景、故事線、主線階段與大綱項目。
- store 檔名維持 `Sailune-v5-story-planning.store`，由 SwiftData lightweight migration 原地升級；發布前仍需把它與主 store 一起備份。
- 遷移測試會先建立實際 V1 檔案型 store，再以 V2 遷移計劃開啟，驗證故事標籤 UUID、文字錨點與每節註記不變，並再次重開確認不重複建立資料。
- 主 store 內既有 `Timeline`、`Node`、`Event` 不刪除、不改寫，也不自動複製為 V4.2 `OutlineItem`；第一版採保留策略，避免在時間語意尚未定案時錯誤轉換使用者資料。
