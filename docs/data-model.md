# 資料模型與關聯

## 主資料庫（產品 schema V5）

主要關聯為：

`Book → Volume → Section`

`Book → Character → (Alias / Organization / Ability / Appearance / Psychology / Item / Relationship)`

`Book → Timeline → Node → Event`

`Book → Item → ItemLevel / ItemHistory`

### 刪除規則摘要

- Book 刪除 Volume、Character、Timeline 等所屬資料。
- Volume 刪除其 Sections。
- Character 的設定關聯依模型與刪除服務處理；正文文字保留，角色連結解除。
- Item 刪除 ItemLevel、ItemHistory 及角色持有關聯。
- Node 對 Section、Event 等關聯多使用 nullify，避免刪除時間定位時刪掉正文或事件。

## 獨立資料庫

- `Sailune-v5-item-copies.store`：`ItemCopy`、`ItemCopyHolding`、`ItemCopyHistory`。
- `Sailune-v5-item-copy-level-selections.store`：副本目前手動選擇的等級。
- `Sailune-v5-ability-progress.store`：能力進度相關資料。
- `Sailune-v5-story-planning.store`：`StoryPlanningSchemaV2`，包含 `StoryTag`、`ChapterAnnotation`、`BookPlanningProfile`、`OutlineStoryLine`、`OutlineStage` 與 `OutlineItem`。

獨立 store 的資料以穩定 UUID（例如 `itemID`、`copyID`、`characterID`、`sectionID`）互相連結；它們不是 SwiftData 的直接跨 store relationship。

## 重要不變條件

- UUID 在匯入、遷移與回填後必須保持不變。
- `sortOrder` 只負責同一父層內的顯示排序，不應被當作永久識別碼。
- ItemLevel 目前以 `itemID` 連結，不新增脆弱的 SwiftData inverse relationship。
- StoryTag 的位置是「原文字＋UTF-16 offset」錨點，正文變更後需重新解析。
- 副本目前等級選擇不自動改寫父物品設定。
- V4.2 全書規劃以 `bookID` 連回主 store；`storyLineID` 與可選 `stageID` 維持故事線、階段和項目的穩定連結。
- 敘事大綱與新時間軸直接查詢同一筆 `OutlineItem`；不存在需要同步的第二份內容。
- `OutlineItem.sortOrder` 只控制手動顯示順序；同值時以建立時間與 UUID 提供穩定排序。
- 主線階段只允許建立在 `.main` 故事線；此不變條件由 `StoryPlanningStore` 驗證。
- 同一本書只允許一條 `.main` 故事線；多段主線使用 `OutlineStage`，而不是建立第二條主線。

## 待改善的模型風險

- 多個獨立 store 沒有交易邊界；跨 store 寫入失敗時需有可重試或修復策略。
- 部分模型同時存在現行資料與舊版遷移資料，新增欄位時必須先更新 schema 快照與匯入測試。
