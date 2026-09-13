# 測試策略

## 測試層級

- **模型與服務測試**：建立、更新、刪除、排序、字數計算、時間排序與資料回填。
- **編輯器測試**：自動儲存、切節、中文輸入、幕標題、角色引用、故事標籤錨點。
- **遷移測試**：V2／V3 store 匯入 V5、重複啟動不重複匯入、孤立資料修復、多 store 初始化。
- **匯出測試**：TXT 的卷節順序與標題格式、EPUB 結構及特殊字元 escaping。
- **回歸測試**：角色、物品、關係、時間軸與正文跳轉的跨模組行為。

## 每次修改至少驗證

- `git diff --check`
- 受影響的 SwiftData 模型與刪除規則
- 受影響功能的建立、編輯、重新開啟與刪除流程
- 若改動正文：字數、引用、標籤與自動儲存
- 若改動 schema：至少一份舊版資料庫與全新資料庫

## 目前測試資料

- 現有報告：`TEST_REPORT_2026-08-24.md`
- 現有測試案例：`SailuneTests/ItemV3Tests.swift`
- 最新環境基線：`technical-baseline.md`

測試報告代表當時狀態，不自動代表目前未提交修改已通過驗證。
2026-09-01 已在允許 Xcode macro plugin 正常啟動的環境完成 27 項測試；受限沙箱內仍可能重現 plugin malformed response，詳見 `technical-baseline.md`。

## V4.2 自動驗收

- `SailuneTests/V42OutlineTests.swift`：8 項，涵蓋故事背景、四類與多筆故事線、單一主線限制、主線階段、狀態、排序、共用模型、無正文依賴、全新 V2 store 重開及 V1→V2 遷移。
- `SailuneTests/ItemV3Tests.swift`：19 項既有回歸，包含故事標籤、每節註記、V5 主 store、物品與跨模組行為。
- 2026-09-01 執行 macOS 完整測試共 27 項全數通過；測試結果記錄於 `TEST_REPORT_2026-09-01_V4.2.md`。

## 未完成的測試覆蓋

- 跨主 store／StoryPlanning store 的刪除順序、延後清理與重試已有 V4.4.8 單元測試；其他獨立 store 的全面同步失敗仍未覆蓋。
- 刪除後的復原策略。
- 固定 Downloads 匯出路徑在不同使用者環境的行為。
- 大型正文、重複角色名稱與故事標籤錨點漂移。

## V4.4.8 自動驗收

- `V42OutlineTests` 覆蓋 Book 規劃資料完整清除、兩書隔離、缺 Book／Event 修復、重複修復，以及缺 OutlineItem 來源的保留語意。
- `ItemV3Tests` 覆蓋 Event 主資料與 metadata 協調刪除、Book 跨 store 清理，以及 primary failure 與 deferred cleanup 的結果分流。
- 2026-09-12 執行完整 macOS 測試共 77 項，全數通過；測試均使用隔離／in-memory store，未操作正式使用者資料。

## 正文錨點降級自動驗收

- `V42OutlineTests` 覆蓋唯一文字位移、重複文字最近候選、找不到候選、空錨點節首語意、原文字存在時不改資料，以及失效後保留項目／故事線／階段／節次並轉為草稿。
- 2026-09-13 完整 macOS 測試共 82 項全數通過；無簽章 Release 建置及 `git diff --check` 通過。

## V4.4.81 伏筆／修改失效清理

- `V42OutlineTests` 新增同節有效／失效與跨節 StoryTag 隔離，以及 StoryTag 刪除、大綱節首草稿降級、ChapterAnnotation 保留的混合 reconcile 測試。
- 2026-09-13 目標測試 46 項與完整 macOS 測試 84 項全數通過；無簽章 Release 建置及 `git diff --check` 通過。
- 共同 Undo 新增 AppKit grouping 驗證，以及保留原 UUID／欄位的 planning snapshot Undo→Redo 往返測試；2026-09-13 完整 macOS 測試增至 86 項，全數通過，無簽章 Release 建置通過。
