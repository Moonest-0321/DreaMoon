# 備份、遷移與資料修復

V4.4.81 的 StoryPlanning schema V7 以新增 `PlanningRecordMetadata` 的輕量遷移升級 V6；既有時間序不改寫、不猜測故事線。產品 V5 不遷移既有主 store：主資料維持 `NovelWriterSchemaV5`。設定集配置、自訂勢力層級、勢力、直接隸屬、地點與世界條目保存於獨立 `V5SettingsSchemaV3` store，並由 `V5SettingsMigrationPlan` 依序升級 V1／V2。

## 目前啟動順序

1. 尋找舊版 V3 或 V2 store。
2. 以既有 `NovelWriterSchemaV5` 原樣開啟主資料庫，不執行 schema migration。
3. 將舊資料匯入 V5；若 V5 已有資料，先驗證匯入完整性。
4. 執行懸空資料修復與 V4／V5 回填，並冪等清除舊 `Organization`、角色—組織關聯、組織身分歷史及其 StoryPlanning metadata；其他主資料不允許刪除。
5. 開啟獨立的 V5 settings、物品副本、能力進度與故事規劃 store；settings store 依 `V5SettingsMigrationPlan` 升級至 V3，故事規劃 store 依 `StoryPlanningMigrationPlan` lightweight migration 至 V7，再轉換舊結構標籤。
6. 完成各 store 的資料修復後才顯示主畫面。

V4.4.8 在主 container 與 StoryPlanning store 都成功開啟後，會以現存 Book／Event UUID 執行跨 store 一致性修復；進入世界時間軸時再做一次相同的冪等檢查。它不新增 schema 或 migration，也不會因 OutlineItem 來源缺失而刪除 Event metadata。

## 目前資料檔

- 主資料：`Sailune-v5.store`
- V5 設定集與勢力：`Sailune-v5-settings.store`
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
- 已建立 Book／Event 與 StoryPlanning store 的刪除一致性檢查；但 Volume／Section 與角色事件的部分 UI 入口仍直接刪除，尚未全部接入集中服務。其他獨立 store 的全面一致性檢查與多 store 備份封裝格式也仍未建立。

## V4.2 故事規劃遷移

- `StoryPlanningSchemaV1`、V2、V3 均保持不變；V3 新增 `OutlineItemAnchor`，不回寫 V2 的 `OutlineItem` snapshot；V4 只新增獨立的階段開始定位與手動安置模型，不改寫 V3 的 `OutlineStage`／`OutlineItem`。
- store 檔名維持 `Sailune-v5-story-planning.store`，由 SwiftData lightweight migration 原地升級；發布前仍需把它與主 store 一起備份。
- V2→V3 開啟後在同一個 save 內將主軸／支線／計劃加入轉為同 UUID 的大綱項目及錨點，成功後才刪除原標籤；伏筆／修改不變。檔案型測試會驗證轉換與重開不重複。
- V4.3 的故事背景引導不新增 SwiftData 欄位或 schema；使用既有 `backgroundText` 的可版本化結構值保存。舊自由文字讀取時視為「其他背景」，首次儲存才轉為結構值，內容不遺失。
- V3→V4 以 lightweight migration 開啟。既有階段不從最早正文項目猜測開始位置，既有手動項目不猜測安置位置；兩者保留原資料並在 UI 顯示需設定／待安置提示。檔案型測試驗證舊 V3 資料重開後 UUID 與數量不變。
- V4.4 的寬版工作區、時間軸投影及故事背景入口搬移均為呈現層變更，不新增 schema、不複製 `OutlineItem`，也不搬動 `backgroundText`；因此不需要新的資料遷移。無法解析的時間軸位置只在執行期間列入待安置區。
- 主 store 內既有 `Timeline`、`Node`、`Event` 不刪除、不改寫，也不自動複製為 V4.2 `OutlineItem`；第一版採保留策略，避免在時間語意尚未定案時錯誤轉換使用者資料。
- V5→V6 只新增空的 `TimelineEventCardMetadata` entity；不替舊 Event 猜測 OutlineItem。舊 Event 若已有有效 Section，執行期仍視為已寫入相容卡；作者主動綁定後才建立 metadata。
- 產品 V5 的 `BookSidebarSetting`、`PowerLevel`、`PowerUnit`、`PowerSubordination`、`Place` 與 `WorldTerm` 位於獨立 settings store；主 store 不升級 schema。舊 Organization 型別保留於主 schema 以安全開啟舊 store，啟動清理只移除其資料，不轉換為勢力。
- Settings V1→V2 保留既有勢力 UUID、名稱、簡介、側邊欄配置、地點與世界條目；既有勢力遷移為未指定層級。舊連線沒有層級可供驗證，因此遷移只刪除 `PowerSubordination`，不建立預設層級，也不刪除或改寫其他 store 的資料。
- Settings V2→V3 新增高層管理員、其他名單、勢力關係、政治與宗教自由文字欄位；既有 V2 勢力與自訂層級完整保留。尚無層級的既有書補上兩個中性預設層級，已有自訂層級者不增補、不改名。
- V6→V7 只新增空的 `PlanningRecordMetadata` entity。既有時間序若有節次但沒有歸屬，執行期列入「未分類時間序」；作者儲存定位後才建立 metadata。來源刪除後，工作區開啟時會冪等清理孤立 metadata。
- 新建／綁定採先保存主 Event、再保存 metadata；後者失敗時保留 Event 並允許重試。刪 Event 後若 metadata 清理失敗，孤立記錄不顯示，下一次時間軸載入時冪等清理。
