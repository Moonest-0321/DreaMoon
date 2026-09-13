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
- Node 的事件關聯使用 cascade；刪除釘子會刪除所屬事件，正文 Section 保留。刪除服務亦清除相關歷史定位，並非保留事件。

## 獨立資料庫

- `Sailune-v5-item-copies.store`：`ItemCopy`、`ItemCopyHolding`、`ItemCopyHistory`。
- `Sailune-v5-item-copy-level-selections.store`：副本目前手動選擇的等級。
- `Sailune-v5-ability-progress.store`：能力進度相關資料。
- `Sailune-v5-story-planning.store`：`StoryPlanningSchemaV6`，包含既有故事規劃模型、`OutlineStageStartDetail` 與 `TimelineEventCardMetadata`。

獨立 store 的資料以穩定 UUID（例如 `itemID`、`copyID`、`characterID`、`sectionID`）互相連結；它們不是 SwiftData 的直接跨 store relationship。

## 重要不變條件

- UUID 在匯入、遷移與回填後必須保持不變。
- `sortOrder` 只負責同一父層內的顯示排序，不應被當作永久識別碼。
- ItemLevel 目前以 `itemID` 連結，不新增脆弱的 SwiftData inverse relationship。
- `StoryTag`（僅伏筆／修改）及 `OutlineItemAnchor` 都以「原文字＋UTF-16 offset」保存來源，正文變更後以相同規則重新解析。
- V4.4.81 在正文成功保存後，以實際文字候選檢查同節 `StoryTag`：伏筆／修改的 `anchorText` 完全找不到時刪除該 tag。此規則不同於 `OutlineItemAnchor` 的節首草稿降級，因 StoryTag 沒有需要獨立保留的大綱內容。
- `OutlineItemAnchor.anchorText == ""` 且 `anchorOffset == 0` 表示原錨定文字已消失、來源降級至原節次開頭；此時 anchor 與 `sectionID` 保留，對應項目改為草稿。它不是手動項目或待安置資料，後續檢查也不得重複降級。
- 副本目前等級選擇不自動改寫父物品設定。
- V4.2 全書規劃以 `bookID` 連回主 store；`storyLineID` 與可選 `stageID` 維持故事線、階段和項目的穩定連結。
- V4.2 至 V4.4.2a 敘事大綱與時間軸共用 `OutlineItem`；V4.4.3 時間軸接回主 store 的 Timeline／Era／Node／Event。敘事大綱仍讀寫原 OutlineItem，不自動轉換或複製資料，也不新增 schema。
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
- `OutlineTimelineLayout` 是執行期間的唯讀投影，不是 SwiftData 模型：欄位來自目前書籍的幕／節次順序，泳道來自故事線，卡片仍指向原本的 `OutlineItem`。V4.4.1 的 `StageBand` 只投影有效主線階段的起訖欄位；無法解析的位置只進入 `pendingItems`，失效階段不起帶，兩者都不會回寫或猜測安置資料。
- StoryPlanning schema V5 新增 `OutlineStageStartDetail`，以 `stageID` 一對一補充 V4 階段錨點的定位粒度（卷次／節次／幕標題）、幕標題快照及 offset。沒有 detail 的 V4 舊錨點維持節次語意；V4 模型本身不變。
- StoryPlanning schema V6 新增 `TimelineEventCardMetadata`，以唯一 `eventID` 連至主 store Event，並以可選 `outlineItemID` 連至敘事大綱；它保存 `bookID`、節錄模式、手動節錄與更新時間，不建立跨 store SwiftData relationship。
- Event 的標題、詳情、Node、Section 與角色仍由主 store 擁有。metadata 與有效 OutlineItemAnchor 共同決定正文來源；anchor 的 sectionID 會回填 Event.section，供卷節顯示與跳轉。
- 刪除 Event 後清理對應 metadata；刪除 OutlineItem 不跨 store 刪 Event，卡片改顯示來源失效。刪除 Node／Timeline 仍依主 store cascade 刪 Event，再以冪等清理移除孤立 metadata。
- V4.4.8 的跨 store 刪除一律先保存主 store，再清理 StoryPlanning 附屬資料。Book 刪除會以 `bookID` 清除該書所有規劃模型及間接附屬模型；任何其他書籍不得受影響。
- 一致性修復只依主 store 現存的 Book／Event UUID 清除缺失書籍的規劃資料與缺失事件的 metadata。缺失 OutlineItem 來源不構成刪除依據，Event 與 metadata 會保留並呈現來源失效。

## 待改善的模型風險

- 多個獨立 store 沒有共同交易邊界；目前以「主資料先保存、附屬清理可延後、啟動時冪等修復」收斂刪除失敗，但仍不等同完整備份或復原能力。
- 部分模型同時存在現行資料與舊版遷移資料，新增欄位時必須先更新 schema 快照與匯入測試。
