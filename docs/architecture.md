# 技術架構

> 基準：目前工作樹（2026-09-05）。歷史版本差異不回寫至舊提交。

## 技術組成

- 平台：Apple 平台桌面應用程式（目前以 macOS API 為主）。
- UI：SwiftUI。
- 持久化：SwiftData／ModelContext。
- 原生編輯器：AppKit `NSTextView`，透過 `NSViewRepresentable` 接入 SwiftUI。
- 文件內容：`AttributedString`，以字體屬性區分內文與幕標題。
- 匯出：原生 Swift 組裝 TXT 與 EPUB，不依賴外部壓縮套件。

## 分層責任

### 應用啟動層

`SailuneApp.swift` 負責建立主資料庫、獨立功能資料庫、舊資料匯入、回填與啟動錯誤畫面。

### 資料模型層

根模型位於 `Book`、`Volume`、`Section`、`Character`、`Item`、`Timeline` 等檔案；V4.2 全書規劃模型位於 `BookOutline.swift`，透過穩定 `bookID` 連接獨立故事規劃 store。模型以關聯與 UUID 連接，並使用 SwiftData 儲存。

### 工作區與功能 UI 層

`ContentView` 負責書櫃，`BookOverviewView` 負責書籍與卷節結構及故事背景入口，`EditorWorkspaceView` 負責寫作與寬版大綱兩種同視窗呈現。寫作面使用 `NavigationSplitView`，寬版大綱則是獨立的中央 surface，不包含正文 sidebar，因此系統側邊欄控制也不會出現在大綱模式。進入前先提交待存文字；書籍、目前節次與 editor bridge 狀態由外層保留，返回正文或來源時重新建立文字 surface 並定位。

`InspectorViews` 及各功能 View 負責右側設定集；`WorkspaceInspectorView` 保留「設定集／大綱」頂層切換，右欄大綱只提供敘事大綱與時間軸。`OutlineViews` 同時提供可重用的垂直敘事大綱、寬版 `BookPlanningWorkspaceView` 與橫向結構時間軸。故事背景不再放在右欄，而是在 `BookOverviewView` 以摘要卡及完整寬度編輯器呈現。

### 編輯器橋接層

`RichEditorView` 封裝 AppKit 文字元件。`EditorBridge` 提供 SwiftUI 與編輯器之間的選取、焦點、標題切換、載入與儲存同步。

### 服務與修復層

匯出由 `ExportManager`／`EpubExporter` 負責；舊時間定位排序由 `TimelineEngine` 負責；V4.2 之後的大綱排序、資料操作與 V4.4 `OutlineTimelineLayout` 投影集中在 `StoryPlanningStore`。投影只把可解析位置放入幕／節次欄位，無法解析者交給 UI 的待安置區；資料清理與刪除由 `PersistentStoreRepair`、`MigrationPlan` 及相關 Backfill 負責。

## 可持續性原則

- 歷史 schema 只保留快照，不直接指向會持續變動的現行模型。
- 新增資料域時，優先使用獨立 store 或穩定 UUID 連結，降低舊資料庫遷移風險。
- 跨 UI 與模型的同步需有明確責任者，不在 SwiftUI view 更新期間同步回寫狀態。
- 破壞性資料操作要有明確刪除規則、錯誤處理與驗收案例。
- 技術重構不得默默改變已記錄的產品行為；若行為改變，先更新對應規格。

## 技術風險

- 多個獨立 store 的一致性需在刪除、匯入與備份時一併處理。
- `AttributedString`、UTF-16 offset、角色連結與故事標籤錨點需避免互相失步。
- 匯出目前含有平台特定儲存路徑，尚不具跨環境可攜性。
