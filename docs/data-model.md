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
- `Sailune-v5-story-planning.store`：`StoryPlanningSchemaV4`，包含 V3 的故事規劃模型，以及 `OutlineStageStartAnchor`、`OutlineItemPlacement`。

獨立 store 的資料以穩定 UUID（例如 `itemID`、`copyID`、`characterID`、`sectionID`）互相連結；它們不是 SwiftData 的直接跨 store relationship。

## 重要不變條件

- UUID 在匯入、遷移與回填後必須保持不變。
- `sortOrder` 只負責同一父層內的顯示排序，不應被當作永久識別碼。
- ItemLevel 目前以 `itemID` 連結，不新增脆弱的 SwiftData inverse relationship。
- `StoryTag`（僅伏筆／修改）及 `OutlineItemAnchor` 都以「原文字＋UTF-16 offset」保存來源，正文變更後以相同規則重新解析。
- 副本目前等級選擇不自動改寫父物品設定。
- V4.2 全書規劃以 `bookID` 連回主 store；`storyLineID` 與可選 `stageID` 維持故事線、階段和項目的穩定連結。
- 敘事大綱與新時間軸直接查詢同一筆 `OutlineItem`；不存在需要同步的第二份內容。
- `OutlineItemAnchor.outlineItemID` 是唯一值，因此一筆大綱項目最多一個正文來源；手動建立項目可沒有來源。
- `OutlineStageStartAnchor.stageID` 是唯一值；它以幕（`Volume`）與節次（`Section`）UUID 加上名稱快照保存主線階段起點。來源結構被刪除時，階段保留並顯示快照與刪除標記。
- `OutlineItemPlacement.outlineItemID` 是唯一值；手動項目可為待安置、幕首、接在項目後或幕末。掛點刪除時保留項目並改為待安置，不自動猜測新位置。
- `OutlineItemStatus.occurred` 的已發布 raw value 保持「已發生」，UI 顯示為「已完成」；只有帶 `OutlineItemAnchor` 的正文來源項目可以使用。舊手動已發生資料保留並提示作者調整。
- 刪除 `OutlineItem` 時一併刪除其 anchor；刪除 `OutlineStoryLine` 時級聯其階段、項目與所有相關 anchors，均不得改動正文。
- `OutlineItem.sortOrder` 是沒有有效正文來源時的手動後備排序；有來源時，卷／節順序與重新解析後的 UTF-16 offset 優先，同值再以建立時間與 UUID 穩定排序。
- 主線階段依其有效開始節次排序；項目在階段內依幕首、正文位置及其掛接項目、幕末、待安置排序。`sortOrder` 只作相同語意位置的穩定後備，沒有 UI 輸入。
- 主線階段只允許建立在 `.main` 故事線；此不變條件由 `StoryPlanningStore` 驗證。
- 同一本書只允許一條 `.main` 故事線；多段主線使用 `OutlineStage`，而不是建立第二條主線。
- 刪除 `OutlineStage` 時一併刪除所屬 `OutlineItem` 與其 `OutlineItemAnchor`，正文內容不變；刪除後通知編輯器重新載入紅色正文標記。項目只能手動移往同一主線的階段或未分階段。
- `BookPlanningProfile.backgroundText` 相容保存故事背景引導與其他背景；非結構化舊值一律視為其他背景，避免遺失既有文字。

## 待改善的模型風險

- 多個獨立 store 沒有交易邊界；跨 store 寫入失敗時需有可重試或修復策略。
- 部分模型同時存在現行資料與舊版遷移資料，新增欄位時必須先更新 schema 快照與匯入測試。
