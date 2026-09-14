# 技術架構

> 基準：2026-09-13 目前工作樹。

## 技術組成

- macOS 原生應用；SwiftUI 負責主要畫面，AppKit `NSTextView` 負責正文編輯。
- SwiftData／`ModelContext` 持久化；正文使用 `AttributedString`。
- TXT 與 EPUB 由專案內原生程式產生，不依賴外部壓縮套件。
- `SailuneTests` 使用 XCTest，測試模型、投影、遷移、錨點、刪除與編輯器橋接。

## 執行結構

```text
SailuneApp
├─ 主 store（書籍、正文、設定、世界時間）
├─ 物品副本 store
├─ 副本等級選擇 store
├─ 能力進度 store
└─ 故事規劃 store（標籤、背景、敘事大綱、事件卡 metadata）

ContentView（書櫃）
└─ BookOverviewView（書籍總覽、卷節、背景）
   └─ EditorWorkspaceView
      ├─ 正文工作區 + 設定集／右側大綱
      └─ BookPlanningWorkspaceView
         ├─ 敘事大綱畫布
         └─ 世界時間軸
```

## 主要責任

- `SailuneApp.swift`：建立六個 store、匯入舊 V2／V3 資料、執行回填與啟動修復、呈現啟動錯誤。
- 主資料模型：`Book`、`Volume`、`Section`、`Character`、`Item`、`Timeline`、`Node`、`Event` 等。
- `BookOutline.swift`／`StoryTag.swift`：故事規劃 schema V1–V6、文字錨點、故事線與階段、排序投影和 store 操作。
- `EditorWorkspaceView`：讓正文與寬版大綱在同一書籍視窗中保留各自生命週期；切換前提交待存正文。
- `RichEditorView`／`EditorBridge`：文字輸入、CJK composition、選取與跨節跳轉、格式、右鍵工具、角色連結及規劃錨點協調。
- `InspectorViews`、`CharacterSectionViews`、`RelationshipWorkspace`：設定集與角色／物品／能力／勢力／關係管理；V5 勢力不與角色或正文連結。
- `OutlineViews`：故事背景、敘事畫布、故事線／階段／大綱項目管理，以及「由大綱加入世界時間軸」。
- `TimelineViews`／`TimelineEngine`：紀元、日期投影、主副軸、節點與事件管理、卡片及正文跳轉。
- `PersistentStoreRepair`／`CrossStoreDeletionCoordinator`：主 store 修復與 Book／Event／Node／Timeline 的跨 store 收斂。
- `MigrationPlan` 與各 Backfill：歷史 schema 匯入及獨立 store 回填。

## 兩種「連動」

1. 主 store 內使用 SwiftData relationship，例如書籍—卷—節、時間軸—節點—事件、角色—設定。
2. 獨立 store 之間只用 UUID 連結。`TimelineEventCardMetadata.eventID` 指向主 store Event，可再以 `outlineItemID` 指向故事規劃中的大綱項目；這不是跨 store relationship。

敘事大綱和世界時間軸不是同一套資料。作者可由 `OutlineItem` 建立主 store `Event`，metadata 保存兩者的關聯與節錄設定；刪除大綱來源不會刪除世界事件。

## 文字位置策略

- 角色引用寫入自訂 `sailune://character/<UUID>` URL，名稱變更時可同步已連結文字；未連結同名文字只列為候選。
- 故事標籤與大綱來源保存選取文字及 UTF-16 offset，重新解析時取最接近舊位置的候選。
- 伏筆／修改錨定文字消失時刪除輕量標籤；大綱來源消失時保留項目，降級到原節開頭並轉草稿。

## 已知技術風險

- 六個 store 沒有共同交易；目前只有部分資料域具完整協調刪除與冪等修復。
- 書籍總覽與編輯器 sidebar 的 Volume／Section 刪除、角色事件刪除仍直接呼叫 `modelContext.delete`，沒有使用既有集中清理服務。
- `AttributedString`、UTF-16 offset、角色 URL 連結與規劃錨點需持續做跨模組回歸。
- TXT／EPUB 匯出寫死 `/Users/hsuchengyu/Downloads`，不具其他帳號與環境的可攜性。
- 多 store 尚無單一備份／還原封裝；正式發布前需補齊。
